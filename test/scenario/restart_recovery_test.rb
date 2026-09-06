# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class RestartRecoveryTest < Minitest::Test
  def test_actual_fresh_ruby_process_restores_catalog_and_policy_through_service
    Dir.mktmpdir("ruby-routing-fresh-process") do |directory|
      path = File.join(directory, "facts.jsonl")
      provider = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )
      policy = policy_for("fresh-process")
      payout = intent("fresh-process-payout")
      first = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [provider]
      )
      committed = first.prepare_and_commit_decision(intent: payout, policy: policy)

      script = File.expand_path("../support/fresh_process_resume.rb", __dir__)
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        script,
        path,
        payout.id
      )

      assert status.success?, "fresh process failed: stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      result = JSON.parse(stdout)
      assert_equal "success", result.fetch("status")
      assert_equal "stop", result.fetch("action")
      assert_equal 1, result.fetch("attempt_count")
      assert_equal committed.proposal.operation_id, result.fetch("operation_id")
      assert_nil result.fetch("ownership")

      reopened = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )
      snapshot = reopened.payout_snapshot(payout.id)
      assert_equal :success, snapshot.status
      assert_equal :settled, snapshot.attempts.first.phase
      assert_equal committed.proposal.operation_id, snapshot.attempts.first.operation_id
      assert_nil snapshot.ownership
    end
  end

  def test_restart_restores_committed_owner_contract_reservations_and_dispatch
    Dir.mktmpdir("ruby-routing-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      provider = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capacity: RubyRouting::CapacityBudget.new(max_slots: 1),
        throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60),
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, ttl_seconds: 30)
      )
      policy = policy_for("restart")
      payout = intent("restart-payout")

      first_journal = RubyRouting::State::FileJournal.new(path)
      first = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: first_journal,
        opportunities: [provider]
      )
      committed = first.prepare_and_commit_decision(intent: payout, policy: policy)

      recovered_journal = RubyRouting::State::FileJournal.new(path)
      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: recovered_journal
      )
      snapshot = recovered.payout_snapshot(payout.id)

      assert_equal :pending, snapshot.status
      assert_equal committed.proposal.operation_id, snapshot.ownership.operation_id
      assert_equal :committed, snapshot.current_operation_phase
      assert_equal "#{payout.id}:#{committed.proposal.operation_id}",
        snapshot.current_operation_contract.idempotency_key
      assert_equal 1, recovered.capacity_snapshot("A").used_slots
      assert_equal 1, recovered.throughput_snapshot("A").consumed_count
      assert_equal recovered.lifecycle_projection.to_h,
        RubyRouting::Projections::Replay.lifecycle(recovered.facts).to_h

      calls = []
      adapter = Class.new do
        define_method(:initiate) do |request|
          calls << request
          RubyRouting::ProviderObservation.new(
            observation_id: "restart-success",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end

        def resolve(_request)
          raise "resolve should not be used for a committed dispatch"
        end
      end.new
      result = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => adapter }
      ).resume(payout_id: payout.id)

      assert_equal :success, result.status
      assert_equal [committed.proposal.operation_id], calls.map(&:operation_id)
      assert_equal 1, recovered.payout_snapshot(payout.id).attempt_count
      assert_nil recovered.payout_snapshot(payout.id).ownership
      assert_equal recovered.capacity_projection.to_h,
        RubyRouting::Projections::Replay.capacity(recovered.facts).to_h
      assert_equal recovered.throughput_projection.snapshot("A").to_h,
        recovered.throughput_snapshot("A").to_h
    end
  end

  def test_restart_replays_throughput_window_expiry_at_evaluation_boundary
    clock = TestSupport::ControlledClock.new
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)
    )
    policy = policy_for("restart-throughput-window")
    coordinator = RubyRouting::State::Coordinator.new(clock: clock, opportunities: [provider])

    first = coordinator.prepare_and_commit_decision(intent: intent("restart-throughput-first"), policy: policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restart-throughput-first-failure",
        payout_id: first.payout.id,
        provider_id: "A",
        operation_id: first.proposal.operation_id,
        attempt_id: first.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :unknown)
      )
    )
    clock.advance(60)
    second = coordinator.prepare_and_commit_decision(intent: intent("restart-throughput-second"), policy: policy)

    restored = RubyRouting::State::Coordinator.from_facts(
      facts: coordinator.facts,
      opportunities: [provider],
      clock: clock
    )

    assert_equal :assign, second.proposal.action
    assert_equal :pending, restored.payout_snapshot(second.payout.id).status
    assert_equal 1, restored.throughput_snapshot("A").consumed_count
  end

  def test_restart_rebases_throughput_window_for_a_new_monotonic_origin
    start_time = Time.utc(2026, 8, 31, 12, 0, 0)
    clock = TestSupport::ControlledClock.new(start_time: start_time, monotonic_origin: 0)
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)
    )
    policy = policy_for("restart-throughput-origin")
    first = RubyRouting::State::Coordinator.new(clock: clock, opportunities: [provider])
    committed = first.prepare_and_commit_decision(
      intent: intent("restart-throughput-origin-first"),
      policy: policy
    )
    first.mark_attempt_started(committed)
    first.apply_observation(observation_for(committed, :safe_route_failure))
    clock.advance(1)

    restarted_clock = TestSupport::ControlledClock.new(
      start_time: clock.now,
      monotonic_origin: 100
    )
    restored = RubyRouting::State::Coordinator.from_facts(
      facts: first.facts,
      opportunities: [provider],
      clock: restarted_clock
    )

    assert_equal 1, restored.throughput_snapshot("A").consumed_count
    second = restored.prepare_and_commit_decision(
      intent: intent("restart-throughput-origin-second"),
      policy: policy
    )

    assert_equal :defer, second.proposal.action
    assert_includes second.proposal.reason_codes, :throughput_exhausted
  end

  def test_restart_deduplication_preserves_observation_identity
    Dir.mktmpdir("ruby-routing-dedup") do |directory|
      path = File.join(directory, "facts.jsonl")
      provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
      policy = policy_for("dedup")
      payout = intent("dedup-payout")
      journal = RubyRouting::State::FileJournal.new(path)
      coordinator = RubyRouting::State::Coordinator.new(journal: journal, opportunities: [provider])
      commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      coordinator.mark_attempt_started(commit)
      observation = observation_for(commit)
      coordinator.apply_observation(observation)

      recovered = RubyRouting::State::Coordinator.new(journal: RubyRouting::State::FileJournal.new(path))
      duplicate = recovered.apply_observation(observation)

      assert duplicate.duplicate
      assert_equal :success, duplicate.payout.status
      assert_equal 1, recovered.facts.count { |fact| fact.type == :provider_observed }
      assert_equal 1, recovered.facts.count { |fact| fact.type == :settlement_recorded }
    end
  end

  def test_restart_preserves_partial_settlement_reversals_and_idempotency
    Dir.mktmpdir("ruby-routing-reversal-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
      policy = policy_for("reversal-restart")
      payout = intent("reversal-restart-payout")
      journal = RubyRouting::State::FileJournal.new(path)
      coordinator = RubyRouting::State::Coordinator.new(
        journal: journal,
        opportunities: [provider]
      )
      commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      coordinator.mark_attempt_started(commit)
      coordinator.apply_observation(observation_for(commit))
      coordinator.record_reversal(
        payout_id: payout.id,
        reversal_id: "return-part-1",
        provider_id: provider.provider_id,
        operation_id: commit.proposal.operation_id,
        amount: RubyRouting::Money.new(40, "RUB")
      )
      coordinator.record_reversal(
        payout_id: payout.id,
        reversal_id: "return-part-2",
        provider_id: provider.provider_id,
        operation_id: commit.proposal.operation_id,
        amount: RubyRouting::Money.new(60, "RUB")
      )

      recovered = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )
      snapshot = recovered.payout_snapshot(payout.id)
      reversal_facts_before_duplicate = recovered.facts.count { |fact| fact.type == :reversal_recorded }

      assert_equal :reversed, snapshot.status
      assert_nil snapshot.ownership
      assert_equal commit.proposal.operation_id, snapshot.settlement_operation_id
      assert_equal ["return-part-1", "return-part-2"], snapshot.reversals.map(&:reversal_id)
      assert_equal 100, snapshot.reversals.sum { |reversal| reversal.amount.amount_minor }
      assert_equal(
        RubyRouting::Projections::Analytics.from_facts(coordinator.facts).to_h,
        RubyRouting::Projections::Replay.analytics(recovered.facts).to_h
      )

      duplicate = recovered.record_reversal(
        payout_id: payout.id,
        reversal_id: " return-part-2 ",
        provider_id: " A ",
        operation_id: " #{commit.proposal.operation_id} ",
        amount: RubyRouting::Money.new(60, "RUB")
      )

      assert_equal 2, duplicate.reversals.length
      assert_equal reversal_facts_before_duplicate,
        recovered.facts.count { |fact| fact.type == :reversal_recorded }
    end
  end

  def test_restart_after_dispatch_started_uses_same_provider_resolution
    Dir.mktmpdir("ruby-routing-dispatch-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      provider = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )
      policy = policy_for("dispatch-restart")
      payout = intent("dispatch-restart-payout")
      first = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [provider]
      )
      commit = first.prepare_and_commit_decision(intent: payout, policy: policy)
      first.mark_attempt_started(commit)

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      calls = []
      adapter = Class.new do
        define_method(:initiate) { |_request| raise "initiate must not repeat after dispatch" }

        define_method(:resolve) do |request|
          calls << request
          RubyRouting::ProviderObservation.new(
            observation_id: "dispatch-restart-success",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end
      end.new

      result = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => adapter }
      ).resume(payout_id: payout.id)

      assert_equal :success, result.status
      assert_equal [commit.proposal.operation_id], calls.map(&:operation_id)
      assert_equal 1, recovered.payout_snapshot(payout.id).attempt_count
      assert_equal :success, RubyRouting::Projections::Replay.payout(recovered.facts, payout.id).status
    end
  end

  def test_restart_after_resolution_commit_resumes_existing_resolution_token
    Dir.mktmpdir("ruby-routing-resolution-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      provider = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )
      policy = policy_for("resolution-restart")
      payout = intent("resolution-restart-payout")
      first = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [provider]
      )
      initial = first.prepare_and_commit_decision(intent: payout, policy: policy)
      first.mark_attempt_started(initial)
      unknown = RubyRouting::ProviderObservation.new(
        observation_id: "resolution-restart-unknown",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: initial.proposal.operation_id,
        attempt_id: initial.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
      )
      first.apply_observation(unknown)
      resolution = first.prepare_and_commit_decision(intent: payout, policy: policy)

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      decision_count_before = recovered.facts.count { |fact| fact.type == :decision_committed }
      calls = []
      adapter = Class.new do
        define_method(:initiate) { |_request| raise "initiate must not be used for resolution" }

        define_method(:resolve) do |request|
          calls << request
          RubyRouting::ProviderObservation.new(
            observation_id: "resolution-restart-success",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end
      end.new

      result = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => adapter }
      ).resume(payout_id: payout.id)

      assert_equal :success, result.status
      assert_equal [initial.proposal.operation_id], calls.map(&:operation_id)
      assert_equal decision_count_before, recovered.facts.count { |fact| fact.type == :decision_committed }
      assert_equal 2, recovered.facts.count { |fact| fact.type == :provider_observed }
      assert_equal resolution.proposal.operation_id, initial.proposal.operation_id
      assert_equal :resolve, resolution.proposal.action
    end
  end

  def test_restart_after_restart_recovery_decision_preserves_resolution_token
    Dir.mktmpdir("ruby-routing-restart-recovery-decision") do |directory|
      path = File.join(directory, "facts.jsonl")
      provider = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )
      policy = policy_for("restart-recovery-decision")
      payout = intent("restart-recovery-decision-payout")
      first = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [provider]
      )
      initial = first.prepare_and_commit_decision(intent: payout, policy: policy)
      first.mark_attempt_started(initial)

      recovered = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )
      restart_commit = recovered.resume_operation(payout.id)
      assert_equal :resolve, restart_commit.proposal.action
      assert_equal :resolving, recovered.payout_snapshot(payout.id).current_operation_phase

      resumed_again = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )
      adapter = Class.new do
        def initiate(_request)
          raise "restart recovery must not initiate a second money-moving operation"
        end

        def resolve(request)
          RubyRouting::ProviderObservation.new(
            observation_id: "restart-recovery-decision-success",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end
      end.new

      result = RubyRouting::Application::Orchestrator.new(
        coordinator: resumed_again,
        providers: { "A" => adapter }
      ).resume(payout_id: payout.id)

      assert_equal :success, result.status
      assert_equal [initial.proposal.operation_id], result.payout.attempts.map(&:operation_id)
      assert_nil result.payout.ownership
    end
  end

  def test_restart_after_restart_recovery_decision_preserves_idempotent_retry_token
    Dir.mktmpdir("ruby-routing-restart-recovery-retry") do |directory|
      path = File.join(directory, "facts.jsonl")
      provider = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(idempotent_retry: true)
      )
      policy = policy_for("restart-recovery-retry")
      payout = intent("restart-recovery-retry-payout")
      first = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [provider]
      )
      initial = first.prepare_and_commit_decision(intent: payout, policy: policy)
      first.mark_attempt_started(initial)

      recovered = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )
      restart_commit = recovered.resume_operation(payout.id)
      assert_equal :retry_same, restart_commit.proposal.action
      assert_equal :dispatching, recovered.payout_snapshot(payout.id).current_operation_phase

      resumed_again = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )
      adapter = Class.new do
        def initiate(request)
          RubyRouting::ProviderObservation.new(
            observation_id: "restart-recovery-retry-success",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end

        def resolve(_request)
          raise "idempotent retry recovery must not use status lookup"
        end
      end.new

      result = RubyRouting::Application::Orchestrator.new(
        coordinator: resumed_again,
        providers: { "A" => adapter }
      ).resume(payout_id: payout.id)

      assert_equal :success, result.status
      assert_equal [initial.proposal.operation_id], result.payout.attempts.map(&:operation_id)
      assert_nil result.payout.ownership
    end
  end

  def test_restart_with_unknown_owner_never_unlocks_cross_provider_fallback
    Dir.mktmpdir("ruby-routing-unknown-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      policy = RubyRouting::RoutingPolicy.new(
        id: "unknown-restart",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1, "B" => 1 }
      )
      payout = intent("unknown-restart-payout")
      first = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [
          RubyRouting::ProviderOpportunity.new(provider_id: "A"),
          RubyRouting::ProviderOpportunity.new(provider_id: "B")
        ]
      )
      commit = first.prepare_and_commit_decision(intent: payout, policy: policy)
      first.mark_attempt_started(commit)
      first.apply_observation(
        RubyRouting::ProviderObservation.new(
          observation_id: "unknown-restart-observation",
          payout_id: payout.id,
          provider_id: commit.proposal.provider_id,
          operation_id: commit.proposal.operation_id,
          attempt_id: commit.proposal.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :unknown)
        )
      )
      recovered = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )
      calls = []
      adapter = Class.new do
        define_method(:initiate) { |request| calls << [:initiate, request.provider_id] }
        define_method(:resolve) { |request| calls << [:resolve, request.provider_id] }
      end.new

      result = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => adapter, "B" => adapter }
      ).resume(payout_id: payout.id)

      assert_equal :defer, result.action
      assert_equal :unknown, result.payout.status
      assert_equal commit.proposal.provider_id, result.payout.ownership.provider_id
      assert_empty calls
    assert_equal 1, result.payout.attempt_count
  end

  def test_restart_with_missing_owner_adapter_defers_without_provider_io
    Dir.mktmpdir("ruby-routing-missing-adapter-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
      policy = policy_for("missing-adapter-restart")
      payout = intent("missing-adapter-restart-payout")
      first = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [provider]
      )
      committed = first.prepare_and_commit_decision(intent: payout, policy: policy)

      recovered = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )
      result = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: {}
      ).resume(payout_id: payout.id)

      assert_equal :defer, result.action
      assert_equal :pending, result.status
      assert_equal committed.proposal.operation_id, result.payout.ownership.operation_id
      assert_equal 1, result.payout.attempt_count
      assert_equal 0, recovered.facts.count { |fact| fact.type == :attempt_started }
    end
  end
  end

  def test_restart_after_safe_release_recomputes_fresh_fallback
    Dir.mktmpdir("ruby-routing-safe-release-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      policy = RubyRouting::RoutingPolicy.new(
        id: "safe-release-restart",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1, "B" => 1 }
      )
      payout = intent("safe-release-restart-payout")
      first = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [
          RubyRouting::ProviderOpportunity.new(provider_id: "A"),
          RubyRouting::ProviderOpportunity.new(provider_id: "B")
        ]
      )
      initial = first.prepare_and_commit_decision(intent: payout, policy: policy)
      first.mark_attempt_started(initial)
      first.apply_observation(
        RubyRouting::ProviderObservation.new(
          observation_id: "safe-release-restart-failure",
          payout_id: payout.id,
          provider_id: initial.proposal.provider_id,
          operation_id: initial.proposal.operation_id,
          attempt_id: initial.proposal.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
        )
      )
      recovered = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )
      provider_a = Class.new do
        def initiate(_request)
          raise "released provider must not be retried"
        end

        def resolve(_request)
          raise "released provider must not be resolved"
        end
      end.new
      provider_b = Class.new do
        def initiate(request)
          RubyRouting::ProviderObservation.new(
            observation_id: "safe-release-restart-success",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end

        def resolve(_request)
          raise "resolution must not be used"
        end
      end.new

      result = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => provider_a, "B" => provider_b }
      ).resume(payout_id: payout.id)

      assert_equal :success, result.status
      assert_equal "B", result.payout.settlement_provider_id
      assert_equal ["A", "B"], result.payout.attempts.map(&:provider_id)
      assert_equal({ "A" => 1 }, recovered.allocation_snapshot(policy: policy).measures)
    end
  end

  def test_restart_after_settlement_returns_final_state_without_dispatch
    Dir.mktmpdir("ruby-routing-settlement-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
      policy = policy_for("settlement-restart")
      payout = intent("settlement-restart-payout")
      first = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [provider]
      )
      commit = first.prepare_and_commit_decision(intent: payout, policy: policy)
      first.mark_attempt_started(commit)
      first.apply_observation(observation_for(commit))
      recovered = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )
      adapter = Class.new do
        def initiate(_request)
          raise "settled payout must not be dispatched"
        end

        def resolve(_request)
          raise "settled payout must not be resolved"
        end
      end.new

      result = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => adapter }
      ).resume(payout_id: payout.id)

      assert_equal :success, result.status
      assert_equal :already_final, result.action
      assert_equal 1, result.payout.attempt_count
      assert_nil result.payout.ownership
    end
  end

  def test_restart_during_reconciliation_block_keeps_owner_until_explicit_observation
    Dir.mktmpdir("ruby-routing-reconciliation-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      policy = RubyRouting::RoutingPolicy.new(
        id: "reconciliation-restart",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1 },
        recovery: RubyRouting::RecoveryPolicy.new(max_operations: 2, ttl_seconds: 1)
      )
      payout = intent("reconciliation-restart-payout")
      first = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [
          RubyRouting::ProviderOpportunity.new(
            provider_id: "A",
            capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
          )
        ]
      )
      commit = first.prepare_and_commit_decision(intent: payout, policy: policy)
      clock.advance(1)
      blocked = first.prepare_and_commit_decision(intent: payout, policy: policy)
      assert_equal :reconciliation_blocked, blocked.payout.status

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      resumed = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: {}
      ).resume(payout_id: payout.id)

      assert_equal :defer, resumed.action
      assert_equal :reconciliation_blocked, resumed.payout.status
      assert_equal commit.proposal.operation_id, resumed.payout.ownership.operation_id

      observation = observation_for(commit)
      settled = recovered.apply_observation(observation)
      assert_equal :success, settled.payout.status
      assert_nil settled.payout.ownership
    end
  end

  def test_file_journal_rejects_truncated_and_checksum_corrupt_history
    Dir.mktmpdir("ruby-routing-corrupt") do |directory|
      path = File.join(directory, "facts.jsonl")
      journal = RubyRouting::State::FileJournal.new(path)
      journal.append(
        RubyRouting::Fact.new(
          sequence: 1,
          type: :intent_registered,
          fact_id: "fact:1",
          payout_id: "corrupt-payout",
          payload: { money: RubyRouting::Money.new(1, "RUB") }
        )
      )

      File.open(path, "ab") { |file| file.write("truncated") }
      assert_raises(RubyRouting::State::DurableCorruptionError) { journal.facts }

      File.binwrite(path, File.binread(path).sub("truncated", ""))
      contents = File.binread(path)
      File.binwrite(path, contents.sub("\"checksum\":\"", "\"checksum\":\"0"))
      assert_raises(RubyRouting::State::DurableCorruptionError) { journal.facts }
    end
  end

  def test_working_restore_reports_malformed_provider_payload_as_durable_corruption
    malformed = RubyRouting::Fact.new(
      sequence: 1,
      type: :provider_opportunity_registered,
      fact_id: "fact:1",
      payout_id: "system:provider:A",
      payload: "not-a-provider-payload"
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: [malformed])
    end
  end

  def test_working_restore_rejects_operation_linkage_corruption
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-linkage")
    payout = intent("restore-linkage-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :ownership_acquired,
      operation_id: commit.proposal.operation_id,
      changes: { operation_id: "unknown-operation" }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_working_restore_rejects_duplicate_assignment_after_dispatch_started
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-duplicate-assignment")
    payout = intent("restore-duplicate-assignment-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    assignment = coordinator.facts.find do |fact|
      fact.type == :decision_committed && fact.payload[:action] == :assign
    end

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, assignment),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_reused_attempt_identity_for_recovery_assignment
    providers = [
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
    policy = RubyRouting::RoutingPolicy.new(
      id: "restore-attempt-identity-reuse",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 2)
    )
    payout = intent("restore-attempt-identity-reuse-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: providers)
    initial = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(initial)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-attempt-identity-reuse-failure",
        payout_id: payout.id,
        provider_id: initial.proposal.provider_id,
        operation_id: initial.proposal.operation_id,
        attempt_id: initial.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    recovery = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    refute_equal initial.proposal.operation_id, recovery.proposal.operation_id

    corrupted = coordinator.facts.map do |fact|
      if fact.payload[:operation_id] == recovery.proposal.operation_id && fact.payload.key?(:attempt_id)
        RubyRouting::Fact.new(
          sequence: fact.sequence,
          type: fact.type,
          fact_id: fact.fact_id,
          payout_id: fact.payout_id,
          payload: fact.payload.merge(attempt_id: initial.proposal.attempt_id)
        )
      else
        fact
      end
    end

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: providers)
    end
  end

  def test_working_restore_rejects_assignment_outside_evaluated_feasible_cohort
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-feasibility-link")
    payout = intent("restore-feasibility-link-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :opportunity_evaluated,
      changes: { feasible_provider_ids: [] }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end

  end

  def test_working_restore_rejects_assignment_without_allocation_fact
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-missing-allocation")
    payout = intent("restore-missing-allocation-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    facts_without_allocation = coordinator.facts.reject { |fact| fact.type == :allocation_committed }

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(facts_without_allocation),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_forged_opportunity_allocation_snapshot
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-allocation-trace")
    payout = intent("restore-allocation-trace-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }
    forged_snapshot = evaluation.payload.fetch(:allocation_snapshot).merge(measures: { "A" => 99 })
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :opportunity_evaluated,
      changes: { allocation_snapshot: forged_snapshot }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_noncanonical_opportunity_allocation_key
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-opportunity-key-types")
    payout = intent("restore-opportunity-key-types-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }
    snapshot = evaluation.payload.fetch(:allocation_snapshot)
    forged_key = snapshot.fetch(:key).dup
    forged_key[2] = :default
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :opportunity_evaluated,
      changes: { allocation_snapshot: snapshot.merge(key: forged_key) }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_forged_opportunity_capacity_trace
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capacity: RubyRouting::CapacityBudget.new(max_slots: 2)
    )
    policy = policy_for("restore-capacity-trace")
    payout = intent("restore-capacity-trace-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }
    forged_capacity = evaluation.payload.fetch(:capacity).merge(
      "A" => evaluation.payload.fetch(:capacity).fetch("A").merge(used_slots: 99)
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :opportunity_evaluated,
      changes: { capacity: forged_capacity }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_allocation_under_a_different_evaluation_key
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-allocation-key")
    payout = intent("restore-allocation-key-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    allocation = coordinator.facts.find { |fact| fact.type == :allocation_committed }
    forged_key = allocation.payload.fetch(:allocation_key).dup
    forged_key[-1] = ["B"] if forged_key.length == 4
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :allocation_committed,
      changes: { allocation_key: forged_key }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_noncanonical_allocation_key_segments
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-allocation-key-types")
    payout = intent("restore-allocation-key-types-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    allocation = coordinator.facts.find { |fact| fact.type == :allocation_committed }
    forged_key = allocation.payload.fetch(:allocation_key).dup
    forged_key[2] = :default
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :allocation_committed,
      changes: { allocation_key: forged_key }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_split_allocation_policy_or_reservation_trace
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capacity: RubyRouting::CapacityBudget.new(max_slots: 1)
    )
    policy = policy_for("restore-allocation-context")
    payout = intent("restore-allocation-context-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    forged_fields = {
      policy_id: "forged-policy",
      policy_scope: "forged-scope",
      policy_fingerprint: "forged-fingerprint",
      policy_epoch: "forged-epoch",
      capacity_reserved: false
    }

    forged_fields.each do |field, value|
      corrupted = replace_fact_payload(
        coordinator.facts,
        type: :allocation_committed,
        changes: { field => value }
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "field=#{field}") do
        RubyRouting::State::Coordinator.from_facts(
          facts: corrupted,
          opportunities: [provider]
        )
      end
    end
  end

  def test_working_restore_rejects_observation_health_signal_with_erased_provenance
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-health-provenance")
    payout = intent("restore-health-provenance-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-health-provenance-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :health_signal,
      changes: { source: nil, source_payout_id: nil }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_forged_health_signal_policy
    health_policy = RubyRouting::Routing::HealthPolicy.new(degrade_after: 3)
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [provider]
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :provider_failure,
      attribution: :provider
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :health_signal,
      changes: { policy: health_policy.to_h.merge(degrade_after: 99) }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider],
        health_policy: health_policy
      )
    end
  end

  def test_working_restore_rejects_provider_registration_with_split_capacity_definition
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capacity: RubyRouting::CapacityBudget.new(max_slots: 1)
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :provider_opportunity_registered,
      changes: { capacity: { max_slots: 99, max_count: nil, max_amount_minor: nil, currency: nil } }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_working_restore_rejects_provider_registration_with_split_policy_definition
    health_policy = RubyRouting::Routing::HealthPolicy.new(degrade_after: 3)
    quality_policy = RubyRouting::Routing::QualityPolicy.new(minimum_samples: 2)
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      quality_policy: quality_policy,
      opportunities: [provider]
    )

    {
      health_policy: coordinator.facts
        .find { |fact| fact.type == :provider_opportunity_registered }
        .payload.fetch(:health_policy)
        .merge(degrade_after: 99),
      quality_policy: coordinator.facts
        .find { |fact| fact.type == :provider_opportunity_registered }
        .payload.fetch(:quality_policy)
        .merge(minimum_samples: 99)
    }.each do |field, value|
      corrupted = replace_fact_payload(
        coordinator.facts,
        type: :provider_opportunity_registered,
        changes: { field => value }
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "field=#{field}") do
        RubyRouting::State::Coordinator.from_facts(
          facts: corrupted,
          opportunities: [provider],
          health_policy: health_policy,
          quality_policy: quality_policy
        )
      end
    end
  end

  def test_working_restore_rejects_feasible_provider_that_was_unavailable
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A", available: false)
    policy = policy_for("restore-forged-feasibility")
    payout = intent("restore-forged-feasibility-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :opportunity_evaluated,
      changes: { feasible_provider_ids: ["A"] }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_forged_opportunity_decision_context_traces
    providers = [
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
    policy = RubyRouting::RoutingPolicy.new(
      id: "restore-decision-context",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      ranking: RubyRouting::RankingPolicy.new(priority_by_provider: { "A" => 2, "B" => 1 })
    )
    payout = intent("restore-decision-context-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: providers)
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }

    forged_traces = {
      quality: evaluation.payload.fetch(:quality).merge(
        "A" => evaluation.payload.fetch(:quality).fetch("A").merge(score: Rational(1))
      ),
      ranking: evaluation.payload.fetch(:ranking).merge(
        priority_by_provider: { "A" => 999, "B" => 1 }
      ),
      health_policy: evaluation.payload.fetch(:health_policy).merge(degrade_after: 99),
      static_policy_feasibility: { status: :infeasible, reason_codes: [:forged] },
      previous_outcome: { status: :unknown, attribution: :provider, safe_to_release: false }
    }

    forged_traces.each do |field, value|
      corrupted = replace_fact_payload(
        coordinator.facts,
        type: :opportunity_evaluated,
        changes: { field => value }
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "field=#{field}") do
        RubyRouting::State::Coordinator.from_facts(
          facts: corrupted,
          opportunities: providers
        )
      end
    end
  end

  def test_working_restore_rejects_forged_assignment_decision_trace
    providers = [
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
    policy = RubyRouting::RoutingPolicy.new(
      id: "restore-assignment-trace",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      ranking: RubyRouting::RankingPolicy.new(priority_by_provider: { "A" => 2, "B" => 1 })
    )
    payout = intent("restore-assignment-trace-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: providers)
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assignment = coordinator.facts.find do |fact|
      fact.type == :decision_committed && fact.payload[:action] == :assign
    end
    candidate_trace = assignment.payload.fetch(:allocation_candidates)
    optimization_trace = assignment.payload.fetch(:optimization_trace)
    forged_traces = {
      snapshot_revision: assignment.payload.fetch(:snapshot_revision) + 1,
      allocation_discrepancy: Rational(999),
      allocation_candidates: candidate_trace.merge(
        "A" => candidate_trace.fetch("A").merge(discrepancy: Rational(999))
      ),
      allocation_share_violations: { "A" => { maximum: 1 } },
      optimization_trace: optimization_trace.merge(
        assignment.payload.fetch(:provider_id) => optimization_trace
          .fetch(assignment.payload.fetch(:provider_id))
          .merge(selected: false)
      ),
      runtime_feasibility: assignment.payload.fetch(:runtime_feasibility).merge(status: :infeasible),
      soft_constraint_violations: [:forged],
      reasons: ["forged assignment rationale"],
      reason_codes: [:forged_assignment],
      allocation_deviation_cause: assignment.payload.fetch(:allocation_deviation_cause) == :optimizer_choice ?
        :availability : :optimizer_choice,
      allocation_deviation_recoverability: assignment.payload.fetch(:allocation_deviation_recoverability) == :none ?
        :recoverable : :none
    }

    forged_traces.each do |field, value|
      corrupted = replace_fact_payload(
        coordinator.facts,
        type: :decision_committed,
        action: :assign,
        changes: { field => value }
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "field=#{field}") do
        RubyRouting::State::Coordinator.from_facts(
          facts: corrupted,
          opportunities: providers
        )
      end
    end
  end

  def test_working_restore_rejects_assignment_with_forged_operation_contract
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(
        idempotent_retry: true,
        status_lookup: true,
        ttl_seconds: 45,
        deadline_seconds: 60,
        version: "provider-v2",
        authoritative_sequence: true
      )
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "restore-operation-contract",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 2,
        ttl_seconds: 30,
        deadline_seconds: 90
      )
    )
    payout = intent("restore-operation-contract-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assignment = coordinator.facts.find do |fact|
      fact.type == :decision_committed && fact.payload[:action] == :assign
    end
    contract = assignment.payload.fetch(:contract)

    {
      idempotent_retry: false,
      status_lookup: false,
      ttl_seconds: 999,
      deadline_seconds: 999,
      version: "forged",
      authoritative_sequence: false
    }.each do |field, value|
      corrupted = replace_fact_payload(
        coordinator.facts,
        type: :decision_committed,
        action: :assign,
        changes: { contract: contract.merge(field => value) }
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "field=#{field}") do
        RubyRouting::State::Coordinator.from_facts(
          facts: corrupted,
          opportunities: [provider]
        )
      end
    end
  end

  def test_working_restore_rejects_attempt_start_with_wrong_decision_action
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("restore-attempt-action-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy_for("restore-attempt-action")
    )
    coordinator.mark_attempt_started(commit)
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :attempt_started,
      changes: { action: :retry_same }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_forged_reconciliation_block_evidence
    clock = TestSupport::ControlledClock.new
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "restore-reconciliation-evidence",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 2, ttl_seconds: 1)
    )
    payout = intent("restore-reconciliation-evidence-payout")
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [provider]
    )
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    clock.advance(1)
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    blocked = coordinator.facts.find { |fact| fact.type == :reconciliation_blocked }
    payload = blocked.payload

    {
      reason: :forged_reason,
      elapsed: payload.fetch(:elapsed) + 1,
      blocked_at: payload.fetch(:blocked_at) + 1
    }.each do |field, value|
      corrupted = replace_fact_payload(
        coordinator.facts,
        type: :reconciliation_blocked,
        changes: { field => value }
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "field=#{field}") do
        RubyRouting::State::Coordinator.from_facts(
          facts: corrupted,
          opportunities: [provider],
          clock: clock
        )
      end
    end

    duplicate = RubyRouting::Fact.new(
      sequence: blocked.sequence + 1,
      type: blocked.type,
      fact_id: "duplicate-reconciliation-block",
      payout_id: blocked.payout_id,
      payload: blocked.payload
    )
    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(coordinator.facts + [duplicate]),
        opportunities: [provider],
        clock: clock
      )
    end
  end

  def test_working_restore_rejects_assignment_without_ownership_fact
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-missing-ownership")
    payout = intent("restore-missing-ownership-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    facts_without_ownership = coordinator.facts.reject { |fact| fact.type == :ownership_acquired }

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(facts_without_ownership),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_assignment_without_required_throughput_fact
    clock = TestSupport::ControlledClock.new
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 2, window_seconds: 60)
    )
    policy = policy_for("restore-missing-throughput")
    payout = intent("restore-missing-throughput-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider], clock: clock)
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    facts_without_throughput = coordinator.facts.reject { |fact| fact.type == :throughput_consumed }

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(facts_without_throughput),
        opportunities: [provider],
        clock: clock
      )
    end
  end

  def test_working_restore_rejects_probing_assignment_without_health_reservation_fact
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 2
    )
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("restore-missing-health-reservation-payout")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [provider]
    )
    coordinator.record_health_signal(provider_id: "A", signal: :provider_failure, attribution: :provider)
    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)
    _commit = coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy_for("restore-missing-health-reservation")
    )
    assert_equal :probing, coordinator.health_snapshot("A").state
    facts_without_reservation = coordinator.facts.reject { |fact| fact.type == :health_exposure_reserved }

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(facts_without_reservation),
        opportunities: [provider],
        health_policy: health_policy
      )
    end
  end

  def test_working_restore_rejects_forged_observation_application_decision
    providers = [
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
    policy = RubyRouting::RoutingPolicy.new(
      id: "restore-observation-decision",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    payout = intent("restore-observation-decision-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: providers)
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-observation-decision-safe",
        payout_id: payout.id,
        provider_id: first.proposal.provider_id,
        operation_id: first.proposal.operation_id,
        attempt_id: first.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    second = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(second)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-observation-decision-success",
        payout_id: payout.id,
        provider_id: second.proposal.provider_id,
        operation_id: second.proposal.operation_id,
        attempt_id: second.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-observation-decision-late",
        payout_id: payout.id,
        provider_id: first.proposal.provider_id,
        operation_id: first.proposal.operation_id,
        attempt_id: first.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )
    late_observation = coordinator.facts.find do |fact|
      fact.type == :provider_observed &&
        fact.payload[:observation_id] == "restore-observation-decision-late"
    end
    facts_without_conflict = coordinator.facts.reject { |fact| fact.type == :economic_conflict }

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(facts_without_conflict),
        opportunities: providers
      )
    end

    [
      { applied: false, conflict: false },
      { applied: true, conflict: true }
    ].each do |changes|
      corrupted = renumber_facts(
        facts_without_conflict.map do |fact|
          next fact unless fact.equal?(late_observation)

          RubyRouting::Fact.new(
            sequence: fact.sequence,
            type: fact.type,
            fact_id: fact.fact_id,
            payout_id: fact.payout_id,
            payload: fact.payload.merge(changes)
          )
        end
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "changes=#{changes.inspect}") do
        RubyRouting::State::Coordinator.from_facts(
          facts: corrupted,
          opportunities: providers
        )
      end
    end
  end

  def test_working_restore_rejects_resolution_without_contract_capability_and_forged_policy_epoch
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-decision-contract")
    payout = intent("restore-decision-contract-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-decision-contract-unknown",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
      )
    )
    assignment = coordinator.facts.find do |fact|
      fact.type == :decision_committed && fact.payload[:action] == :assign
    end

    %i[resolve retry_same].each do |action|
      forged_resolution = append_fact(
        coordinator.facts,
        assignment,
        changes: { action: action, role: :resolution }
      )
      assert_raises(RubyRouting::State::DurableCorruptionError, "action=#{action}") do
        RubyRouting::State::Coordinator.from_facts(
          facts: forged_resolution,
          opportunities: [provider]
        )
      end
    end

    forged_epoch = replace_fact_payload(
      coordinator.facts,
      type: :decision_committed,
      action: :assign,
      changes: { policy_epoch: "forged-epoch" }
    )
    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: forged_epoch,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_duplicate_resolution_while_dispatch_is_pending
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    policy = policy_for("restore-duplicate-resolution")
    payout = intent("restore-duplicate-resolution-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    initial = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(initial)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-duplicate-resolution-unknown",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: initial.proposal.operation_id,
        attempt_id: initial.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
      )
    )
    resolution = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assert_equal :resolve, resolution.proposal.action
    resolution_fact = coordinator.facts.reverse.find do |fact|
      fact.type == :decision_committed && fact.payload[:action] == :resolve
    end

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, resolution_fact),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_resolution_action_or_reason_that_bypasses_classification
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(
        status_lookup: true,
        idempotent_retry: true
      )
    )
    policy = policy_for("restore-resolution-trace")
    payout = intent("restore-resolution-trace-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    initial = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(initial)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-resolution-trace-unknown",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: initial.proposal.operation_id,
        attempt_id: initial.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
      )
    )
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    [
      { action: :retry_same, reason_codes: [:same_provider_retry] },
      { reasons: ["forged resolution rationale"] }
    ].each do |changes|
      corrupted = replace_fact_payload(
        coordinator.facts,
        type: :decision_committed,
        action: :resolve,
        changes: changes
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "changes=#{changes.inspect}") do
        RubyRouting::State::Coordinator.from_facts(
          facts: corrupted,
          opportunities: [provider]
        )
      end
    end
  end

  def test_working_restore_rejects_forged_non_operation_decision_traces
    unavailable_provider = RubyRouting::ProviderOpportunity.new(provider_id: "A", available: false)
    no_route_policy = policy_for("restore-no-route-decision")
    no_route_payout = intent("restore-no-route-decision-payout")
    no_route_coordinator = RubyRouting::State::Coordinator.new(opportunities: [unavailable_provider])
    no_route_commit = no_route_coordinator.prepare_and_commit_decision(
      intent: no_route_payout,
      policy: no_route_policy
    )
    assert_equal :defer, no_route_commit.proposal.action
    assert_nil no_route_commit.proposal.operation_id

    [
      { reasons: ["forged no-route rationale"] },
      { reason_codes: [:forged_no_route] },
      { runtime_feasibility: nil },
      { role: :resolution }
    ].each do |changes|
      corrupted = replace_fact_payload(
        no_route_coordinator.facts,
        type: :decision_committed,
        action: :defer,
        changes: changes
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "no-route changes=#{changes.inspect}") do
        RubyRouting::State::Coordinator.from_facts(
          facts: corrupted,
          opportunities: [unavailable_provider]
        )
      end
    end

    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    final_policy = policy_for("restore-final-decision")
    final_payout = intent("restore-final-decision-payout")
    final_coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    initial = final_coordinator.prepare_and_commit_decision(intent: final_payout, policy: final_policy)
    final_coordinator.mark_attempt_started(initial)
    final_coordinator.apply_observation(observation_for(initial))
    final_commit = final_coordinator.prepare_and_commit_decision(intent: final_payout, policy: final_policy)
    assert_equal :already_final, final_commit.proposal.action
    assert_nil final_commit.proposal.operation_id

    corrupted = replace_fact_payload(
      final_coordinator.facts,
      type: :decision_committed,
      action: :already_final,
      changes: { reasons: ["forged final rationale"] }
    )
    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_working_restore_rejects_duplicate_intent_registration
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("restore-duplicate-intent-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.register_intent(payout)
    intent_fact = coordinator.facts.find { |fact| fact.type == :intent_registered }

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, intent_fact),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_duplicate_policy_registration_for_one_payout
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("restore-duplicate-policy-payout")
    policy = policy_for("restore-duplicate-policy")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    policy_fact = coordinator.facts.find { |fact| fact.type == :policy_registered }

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, policy_fact),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_cross_payout_policy_scope_redefinition
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    first_policy = policy_for("shared-policy-scope")
    second_policy = RubyRouting::RoutingPolicy.new(
      id: first_policy.id,
      epoch: first_policy.epoch,
      measure: :count,
      targets: { "B" => 1 }
    )
    first_payout = intent("shared-policy-first-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: first_payout, policy: first_policy)
    second_payout = intent("shared-policy-second-payout")
    second_intent = RubyRouting::Fact.new(
      sequence: coordinator.facts.length + 1,
      type: :intent_registered,
      fact_id: "second-intent",
      payout_id: second_payout.id,
      payload: {
        money: second_payout.money,
        recipient: second_payout.recipient,
        context: second_payout.context,
        created_at: nil
      }
    )
    second_policy_fact = RubyRouting::Fact.new(
      sequence: second_intent.sequence + 1,
      type: :policy_registered,
      fact_id: "second-policy",
      payout_id: second_payout.id,
      payload: {
        policy_id: second_policy.id,
        policy_epoch: second_policy.epoch,
        policy_scope: second_policy.scope,
        policy_fingerprint: second_policy.fingerprint,
        definition: second_policy.to_h,
        static_feasibility: second_policy.static_feasibility
      }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(coordinator.facts + [second_intent, second_policy_fact]),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_split_policy_static_feasibility
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("restore-policy-static-feasibility-payout")
    policy = policy_for("restore-policy-static-feasibility")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :policy_registered,
      changes: { static_feasibility: { status: :infeasible, reason_codes: [:forged] } }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_working_restore_rejects_noncanonical_policy_identity_values
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("restore-policy-identity-payout")
    policy = policy_for("restore-policy-identity")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

    {
      policy_id: :restore_policy_identity,
      policy_epoch: 1,
      policy_scope: :default
    }.each do |field, value|
      corrupted = replace_fact_payload(
        coordinator.facts,
        type: :policy_registered,
        changes: { field => value }
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "field=#{field}") do
        RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
      end
    end

    [
      [:opportunity_evaluated, { policy_id: :restore_policy_identity }],
      [:allocation_committed, { policy_epoch: 1 }]
    ].each do |type, changes|
      corrupted = replace_fact_payload(
        coordinator.facts,
        type: type,
        changes: changes
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "type=#{type}") do
        RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
      end
    end
  end

  def test_working_restore_rejects_noncanonical_operation_identity_values
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("restore-operation-identity-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy_for("restore-operation-identity")
    )
    coordinator.mark_attempt_started(commit)

    [
      [:allocation_committed, { operation_id: 1 }],
      [:ownership_acquired, { attempt_id: 1 }],
      [:operation_phase_changed, { attempt_id: 1 }],
      [:attempt_started, { operation_id: 1 }]
    ].each do |type, changes|
      corrupted = replace_fact_payload(
        coordinator.facts,
        type: type,
        changes: changes
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "type=#{type}") do
        RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
      end
    end
  end

  def test_working_restore_rejects_attempt_start_without_matching_operation_phase
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("restore-attempt-phase-payout")
    policy = policy_for("restore-attempt-phase")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    corrupted = coordinator.facts.reject do |fact|
      fact.type == :operation_phase_changed &&
        fact.payload[:operation_id] == commit.proposal.operation_id
    end

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(corrupted),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_observation_without_matching_outcome_phase
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    payout = intent("restore-observation-phase-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy_for("restore-observation-phase")
    )
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-observation-phase-unknown",
        payout_id: payout.id,
        provider_id: provider.provider_id,
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
      )
    )
    corrupted = coordinator.facts.reject do |fact|
      fact.type == :operation_phase_changed &&
        fact.payload[:operation_id] == commit.proposal.operation_id &&
        fact.payload[:to] == :unknown
    end

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(corrupted),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_resolution_observation_without_matching_outcome_phase
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    payout = intent("restore-resolution-observation-phase-payout")
    policy = policy_for("restore-resolution-observation-phase")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    initial = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(initial)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-resolution-observation-phase-initial",
        payout_id: payout.id,
        provider_id: provider.provider_id,
        operation_id: initial.proposal.operation_id,
        attempt_id: initial.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
      )
    )
    resolution = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_resolution_started(resolution)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-resolution-observation-phase-follow-up",
        payout_id: payout.id,
        provider_id: provider.provider_id,
        operation_id: initial.proposal.operation_id,
        attempt_id: initial.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
      )
    )
    corrupted = coordinator.facts.reject do |fact|
      fact.type == :operation_phase_changed &&
        fact.payload[:operation_id] == initial.proposal.operation_id &&
        fact.payload[:from] == :resolving &&
        fact.payload[:to] == :unknown
    end

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(corrupted),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_ownership_release_with_wrong_outcome_reason
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("restore-ownership-release-reason-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy_for("restore-ownership-release-reason")
    )
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-ownership-release-reason-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :ownership_released,
      changes: { reason: :success }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_working_restore_rejects_resolution_for_unknown_operation
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    policy = policy_for("restore-resolution")
    payout = intent("restore-resolution-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    initial = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(initial)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-resolution-unknown",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: initial.proposal.operation_id,
        attempt_id: initial.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
      )
    )
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :decision_committed,
      action: :resolve,
      changes: { operation_id: "unknown-operation" }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_working_restore_rejects_attempt_start_with_wrong_identity
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-attempt")
    payout = intent("restore-attempt-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :attempt_started,
      operation_id: commit.proposal.operation_id,
      changes: { attempt_id: "wrong-attempt" }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_working_restore_rejects_semantically_malformed_transport_fact
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-transport")
    payout = intent("restore-transport-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-transport-unknown",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :unknown),
        transport_kind: :ambiguous_after_possible_send
      )
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :transport_classified,
      changes: { kind: :forged_transport_classification }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_working_restore_rejects_settlement_linkage_corruption
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-settlement")
    payout = intent("restore-settlement-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation_for(commit))
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :settlement_recorded,
      changes: { provider_id: "B" }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_working_restore_rejects_unsupported_fact_types_instead_of_dropping_them
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("restore-unknown-fact")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.register_intent(payout)
    corrupted = coordinator.facts.map do |fact|
      next fact unless fact.type == :intent_registered

      RubyRouting::Fact.new(
        sequence: fact.sequence,
        type: :payout_state_changed,
        fact_id: fact.fact_id,
        payout_id: fact.payout_id,
        payload: fact.payload
      )
    end

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
    assert_includes error.message, "unsupported legacy payout_state_changed fact"
  end

  def test_working_restore_rejects_reversal_without_settlement_linkage
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("restore-reversal")
    payout = intent("restore-reversal-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation_for(commit))
    coordinator.record_reversal(
      payout_id: payout.id,
      reversal_id: "return-restore",
      provider_id: "A",
      operation_id: commit.proposal.operation_id,
      amount: payout.money
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :reversal_recorded,
      changes: { operation_id: "unknown-operation" }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_working_restore_rejects_economic_conflict_for_an_unrelated_operation
    providers = [
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
    policy = RubyRouting::RoutingPolicy.new(
      id: "restore-conflict",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    payout = intent("restore-conflict-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: providers)
    initial = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(initial)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-conflict-failure",
        payout_id: payout.id,
        provider_id: initial.proposal.provider_id,
        operation_id: initial.proposal.operation_id,
        attempt_id: initial.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    fallback = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(fallback)
    coordinator.apply_observation(observation_for(fallback))
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-conflict-late-success",
        payout_id: payout.id,
        provider_id: initial.proposal.provider_id,
        operation_id: initial.proposal.operation_id,
        attempt_id: initial.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :economic_conflict,
      changes: { operation_id: fallback.proposal.operation_id }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: providers)
    end
  end

  def test_working_restore_rejects_non_boolean_provider_runtime_facts
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.set_provider_availability("A", available: false)
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :provider_runtime_changed,
      changes: { available: "false" }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_provider_catalog_removal_survives_restart_without_losing_admission_history
    providers = [
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
    coordinator = RubyRouting::State::Coordinator.new(opportunities: providers)
    coordinator.replace_provider_opportunities([providers.first])

    assert_equal ["A"], coordinator.provider_opportunities.map(&:provider_id)
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :provider_opportunity_removed }

    restored = RubyRouting::State::Coordinator.from_facts(facts: coordinator.facts)

    assert_equal ["A"], restored.provider_opportunities.map(&:provider_id)
    assert_raises(ArgumentError) { restored.capacity_snapshot("B") }
  end

  def test_restore_rejects_non_enumerable_current_opportunity_input
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])

    assert_raises(ArgumentError) do
      RubyRouting::State::Coordinator.from_facts(facts: coordinator.facts, opportunities: nil)
    end
  end

  def test_restore_rejects_runtime_provider_without_durable_registration
    registered = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    unregistered = RubyRouting::ProviderOpportunity.new(provider_id: "B")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [registered])

    error = assert_raises(ArgumentError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: coordinator.facts,
        opportunities: [unregistered]
      )
    end

    assert_includes error.message, "B"
    assert_includes error.message, "durable provider history"
  end

  def test_restore_accepts_runtime_definition_for_current_durable_provider
    persisted = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    runtime = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      enabled: false
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [persisted])

    restored = RubyRouting::State::Coordinator.from_facts(
      facts: coordinator.facts,
      opportunities: [runtime]
    )

    assert_equal ["A"], restored.provider_opportunities.map(&:provider_id)
    assert restored.provider_opportunities.first.enabled
  end

  def test_restore_accepts_each_only_fact_input
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])

    restored = RubyRouting::State::Coordinator.from_facts(
      facts: TestSupport::EachOnlyCollection.new(coordinator.facts)
    )

    assert_equal coordinator.facts.map(&:payload), restored.facts.map(&:payload)
  end

  def test_restore_rejects_truthy_non_boolean_provider_definition
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    registration = coordinator.facts.find { |fact| fact.type == :provider_opportunity_registered }
    malformed_definition = registration.payload.fetch(:definition).merge(available: "false")
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :provider_opportunity_registered,
      changes: { definition: malformed_definition }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted)
    end
  end

  def test_removed_provider_can_still_release_an_unresolved_capacity_reservation
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "B",
      capacity: RubyRouting::CapacityBudget.new(max_slots: 1),
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "removed-provider-release",
      epoch: "1",
      measure: :count,
      targets: { "B" => 1 }
    )
    payout = intent("removed-provider-release-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.replace_provider_opportunities([])

    restored = RubyRouting::State::Coordinator.from_facts(facts: coordinator.facts)
    assert_equal "B", restored.payout_snapshot(payout.id).ownership.provider_id
    released = restored.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "removed-provider-safe-release",
        payout_id: payout.id,
        provider_id: "B",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :unknown)
      )
    )

    assert_nil released.payout.ownership
    assert_equal 0, restored.capacity_projection.snapshot("B").used_slots
  end

  def test_removed_provider_observation_can_restore_health_and_quality_history
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "B")
    policy = RubyRouting::RoutingPolicy.new(
      id: "removed-provider-health",
      epoch: "1",
      measure: :count,
      targets: { "B" => 1 }
    )
    payout = intent("removed-provider-health-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.replace_provider_opportunities([])

    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "removed-provider-health-observation",
        payout_id: payout.id,
        provider_id: "B",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )

    restored = RubyRouting::State::Coordinator.from_facts(facts: coordinator.facts)

    assert_equal coordinator.health_projection.to_h, restored.health_projection.to_h
    assert_equal coordinator.quality_projection.to_h, restored.quality_projection.to_h
    assert_equal :safe_route_failure, restored.payout_snapshot(payout.id).status
  end

  def test_restart_replays_ambiguous_transport_health_without_changing_unknown_ownership
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 1
    )
    providers = [
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
    policy = RubyRouting::RoutingPolicy.new(
      id: "restart-ambiguous-health",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    payout = intent("restart-ambiguous-health-payout")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: providers
    )
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restart-ambiguous-health-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :unknown),
        transport_kind: :ambiguous_after_possible_send
      )
    )

    restored = RubyRouting::State::Coordinator.from_facts(facts: coordinator.facts)

    assert_equal coordinator.health_snapshot("A").to_h, restored.health_snapshot("A").to_h
    assert_equal coordinator.health_projection.to_h, restored.health_projection.to_h
    assert_equal "A", restored.payout_snapshot(payout.id).ownership.provider_id
    assert_equal :unknown, restored.payout_snapshot(payout.id).status
  end

  def test_restore_rejects_health_signal_before_provider_registration
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "B")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    facts = coordinator.facts
    registration = facts.find { |fact| fact.type == :provider_opportunity_registered }
    health = RubyRouting::Fact.new(
      sequence: 1,
      type: :health_signal,
      fact_id: "fact:1",
      payout_id: "system:provider:B",
      payload: {
        provider_id: "B",
        signal: :provider_failure,
        attribution: :provider,
        release_exposure: true,
        policy: registration.payload.fetch(:health_policy)
      }
    )
    registration_late = RubyRouting::Fact.new(
      sequence: 2,
      type: :provider_opportunity_registered,
      fact_id: "fact:2",
      payout_id: registration.payout_id,
      payload: registration.payload
    )
    corrupted = [health, registration_late]

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted)
    end
  end

  def test_restore_rejects_provider_removal_before_provider_registration
    removal = RubyRouting::Fact.new(
      sequence: 1,
      type: :provider_opportunity_removed,
      fact_id: "fact:1",
      payout_id: "system:provider:B",
      payload: { provider_id: "B", removed_at: nil }
    )
    registration = RubyRouting::Fact.new(
      sequence: 2,
      type: :provider_opportunity_registered,
      fact_id: "fact:2",
      payout_id: "system:provider:B",
      payload: {
        provider_id: "B",
        definition: RubyRouting::ProviderOpportunity.new(provider_id: "B").to_h,
        health_policy: RubyRouting::Routing::HealthPolicy.new.to_h,
        quality_policy: RubyRouting::Routing::QualityPolicy.new.to_h
      }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: [removal, registration])
    end
  end

  def test_working_restore_rejects_health_transition_with_wrong_predecessor
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 2
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :provider_failure,
      attribution: :provider
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :health_state_changed,
      changes: { from: :quarantined }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted)
    end
  end

  def test_working_restore_rejects_missing_health_transition_fact
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 2
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :provider_failure,
      attribution: :provider
    )
    facts_without_transition = coordinator.facts.reject { |fact| fact.type == :health_state_changed }

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(facts_without_transition)
      )
    end
  end

  def test_working_restore_rejects_interleaved_health_transition_fact
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 2
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A"),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :provider_failure,
      attribution: :provider
    )
    coordinator.record_health_signal(
      provider_id: "B",
      signal: :operational_success,
      attribution: :provider
    )
    facts = coordinator.facts
    registrations = facts.select { |fact| fact.type == :provider_opportunity_registered }
    health_signal_a = facts.find do |fact|
      fact.type == :health_signal && fact.payload[:provider_id] == "A"
    end
    health_signal_b = facts.find do |fact|
      fact.type == :health_signal && fact.payload[:provider_id] == "B"
    end
    health_transition_a = facts.find do |fact|
      fact.type == :health_state_changed && fact.payload[:provider_id] == "A"
    end

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: renumber_facts(registrations + [health_signal_a, health_signal_b, health_transition_a])
      )
    end
  end

  def test_working_restore_rejects_duplicate_health_exposure_reservation
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 2
    )
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [provider]
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :provider_failure,
      attribution: :provider
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :operational_success,
      attribution: :provider
    )
    coordinator.prepare_and_commit_decision(
      intent: intent("duplicate-health-reservation"),
      policy: policy_for("duplicate-health-reservation")
    )
    reservation = coordinator.facts.find { |fact| fact.type == :health_exposure_reserved }
    refute_nil reservation

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, reservation)
      )
    end
  end

  def test_working_restore_rejects_health_exposure_reservation_with_wrong_attempt
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 2
    )
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [provider]
    )
    coordinator.record_health_signal(provider_id: "A", signal: :provider_failure, attribution: :provider)
    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)
    payout = intent("wrong-health-reservation-attempt")
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy_for("wrong-health-reservation-attempt"))
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :health_exposure_reserved,
      changes: { attempt_id: "forged-attempt" }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, health_policy: health_policy)
    end
  end

  def test_working_restore_rejects_noncanonical_health_reservation_attempt_identity
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 2
    )
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [provider]
    )
    coordinator.record_health_signal(provider_id: "A", signal: :provider_failure, attribution: :provider)
    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)
    payout = intent("noncanonical-health-reservation-attempt")
    coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy_for("noncanonical-health-reservation-attempt")
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :health_exposure_reserved,
      changes: { attempt_id: 1 }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        health_policy: health_policy
      )
    end
  end

  def test_working_restore_rejects_health_reservation_after_operation_release
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 3
    )
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [provider]
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :provider_failure,
      attribution: :provider
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :operational_success,
      attribution: :provider
    )
    payout = intent("released-health-reservation")
    commit = coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy_for("released-health-reservation")
    )
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "released-health-reservation-success",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )
    reservation = coordinator.facts.find { |fact| fact.type == :health_exposure_reserved }
    refute_nil reservation
    assert_equal :probing, coordinator.health_snapshot("A").state

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, reservation)
      )
    end
  end

  def test_working_restore_rejects_capacity_reservation_recreated_after_operation_release
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capacity: RubyRouting::CapacityBudget.new(max_slots: 1)
    )
    policy = policy_for("released-capacity-reservation")
    payout = intent("released-capacity-reservation-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "released-capacity-reservation-safe",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    reservation = coordinator.facts.find { |fact| fact.type == :capacity_reserved }
    refute_nil reservation

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, reservation),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_capacity_release_before_terminal_operation_outcome
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capacity: RubyRouting::CapacityBudget.new(max_slots: 1)
    )
    policy = policy_for("early-capacity-release")
    payout = intent("early-capacity-release-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    capacity_release = RubyRouting::Fact.new(
      sequence: 1,
      type: :capacity_released,
      fact_id: "placeholder",
      payout_id: payout.id,
      payload: {
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        amount: payout.money
      }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, capacity_release),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_health_exposure_release_before_terminal_operation_outcome
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 2
    )
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("early-health-release")
    payout = intent("early-health-release-payout")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [provider]
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :provider_failure,
      attribution: :provider
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :operational_success,
      attribution: :provider
    )
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    reservation = coordinator.facts.find { |fact| fact.type == :health_exposure_reserved }
    refute_nil reservation
    release = RubyRouting::Fact.new(
      sequence: 1,
      type: :health_exposure_released,
      fact_id: "placeholder",
      payout_id: payout.id,
      payload: {
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id
      }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, release),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_throughput_recreated_after_operation_release
    clock = TestSupport::ControlledClock.new
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 2, window_seconds: 60)
    )
    policy = policy_for("released-throughput")
    payout = intent("released-throughput-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider], clock: clock)
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "released-throughput-safe",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    throughput = coordinator.facts.find { |fact| fact.type == :throughput_consumed }
    refute_nil throughput
    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, throughput),
        opportunities: [provider],
        clock: clock
      )
    end
    facts_without_throughput = coordinator.facts.reject { |fact| fact.type == :throughput_consumed }

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(renumber_facts(facts_without_throughput), throughput),
        opportunities: [provider],
        clock: clock
      )
    end
  end

  def test_working_restore_rejects_allocation_recreated_after_operation_release
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("released-allocation")
    payout = intent("released-allocation-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "released-allocation-safe",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    allocation = coordinator.facts.find { |fact| fact.type == :allocation_committed }
    refute_nil allocation
    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, allocation),
        opportunities: [provider]
      )
    end
    facts_without_allocation = coordinator.facts.reject { |fact| fact.type == :allocation_committed }

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(renumber_facts(facts_without_allocation), allocation),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_duplicate_settlement_fact
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = policy_for("duplicate-settlement")
    payout = intent("duplicate-settlement-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation_for(commit))
    settlement = coordinator.facts.find { |fact| fact.type == :settlement_recorded }
    refute_nil settlement

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, settlement),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_duplicate_economic_conflict_fact
    providers = [
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
    policy = RubyRouting::RoutingPolicy.new(
      id: "duplicate-conflict",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    payout = intent("duplicate-conflict-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: providers)
    initial = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(initial)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "duplicate-conflict-failure",
        payout_id: payout.id,
        provider_id: initial.proposal.provider_id,
        operation_id: initial.proposal.operation_id,
        attempt_id: initial.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    fallback = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(fallback)
    coordinator.apply_observation(observation_for(fallback))
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "duplicate-conflict-late-success",
        payout_id: payout.id,
        provider_id: initial.proposal.provider_id,
        operation_id: initial.proposal.operation_id,
        attempt_id: initial.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )
    conflict = coordinator.facts.find { |fact| fact.type == :economic_conflict }
    refute_nil conflict

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, conflict),
        opportunities: providers
      )
    end
  end

  def test_working_restore_rejects_duplicate_observation_derived_health_signal
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 5,
      quarantine_after: 6
    )
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("duplicate-health-signal-payout")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [provider]
    )
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy_for("duplicate-health-signal"))
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "duplicate-health-signal-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    signal = coordinator.facts.find do |fact|
      fact.type == :health_signal && fact.payload[:source] == "duplicate-health-signal-observation"
    end
    refute_nil signal

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, signal),
        health_policy: health_policy,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_duplicate_observation_derived_quality_signal
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("duplicate-quality-signal-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy_for("duplicate-quality-signal"))
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "duplicate-quality-signal-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )
    signal = coordinator.facts.find { |fact| fact.type == :quality_signal }
    refute_nil signal

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, signal),
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_quality_signal_with_cross_currency_evidence
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("cross-currency-quality-signal-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy_for("cross-currency-quality-signal"))
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "cross-currency-quality-signal-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :quality_signal,
      changes: { currency: "USD" }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_malformed_quality_routing_context
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("malformed-quality-routing-context-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy_for("malformed-quality-routing-context")
    )
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "malformed-quality-routing-context-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :quality_signal,
      changes: { routing_context: "card" }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_unknown_persisted_routing_context_key
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("unknown-persisted-routing-context-key")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.register_intent(payout)
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :intent_registered,
      changes: { routing_context: { payment_methd: "card" } }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_malformed_configuration_revision
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("malformed-configuration-revision-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy_for("malformed-configuration-revision")
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :opportunity_evaluated,
      changes: { configuration_revision: "1" }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: corrupted,
        opportunities: [provider]
      )
    end

    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(
      intent: intent("mismatched-configuration-revision-payout"),
      policy: policy_for("mismatched-configuration-revision"),
      configuration_revision: 1
    )
    mismatched = replace_fact_payload(
      coordinator.facts,
      type: :decision_committed,
      changes: { configuration_revision: 2 }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: mismatched,
        opportunities: [provider]
      )
    end
  end

  def test_working_restore_rejects_duplicate_transport_classification
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    payout = intent("duplicate-transport-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy_for("duplicate-transport"))
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "duplicate-transport-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :unknown),
        transport_kind: :ambiguous_after_possible_send
      )
    )
    classification = coordinator.facts.find { |fact| fact.type == :transport_classified }
    refute_nil classification

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(
        facts: append_fact(coordinator.facts, classification),
        opportunities: [provider]
      )
    end
  end

  def test_restore_rejects_opportunity_evaluation_before_provider_registration
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = RubyRouting::RoutingPolicy.new(
      id: "restore-opportunity-timeline",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    payout = intent("restore-opportunity-timeline-payout")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :opportunity_evaluated,
      changes: {
        opportunities: ["B"],
        functional_provider_ids: [],
        feasible_provider_ids: []
      }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted)
    end
  end

  def test_restore_rejects_noncanonical_provider_identity_in_durable_fact
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    coordinator.set_provider_availability("A", available: false)
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :provider_runtime_changed,
      changes: { provider_id: " A " }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted)
    end
  end

  def test_restore_rejects_non_time_timestamp_in_durable_fact
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    payout = intent("restore-timestamp-payout")
    coordinator.register_intent(payout)
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :intent_registered,
      changes: { created_at: "not-a-time" }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted)
    end
  end

  def test_restoring_throughput_history_uses_the_system_monotonic_boundary
    Dir.mktmpdir("ruby-routing-clock-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      provider = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)
      )
      first = RubyRouting::State::Coordinator.new(
        clock: RubyRouting::State::SystemClock.new,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [provider]
      )

      first.prepare_and_commit_decision(
        intent: intent("system-monotonic-restart"),
        policy: policy_for("system-monotonic-restart")
      )
      recovered = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )

      assert_equal 1, recovered.throughput_snapshot("A").consumed_count
    end
  end

  def test_working_restore_rejects_malformed_observation_payload
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    payout = intent("restore-observation-payload")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy_for("restore-observation-payload"))
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation_for(commit))

    {
      observation_id: :symbol_id,
      applied: "true",
      conflict: nil,
      safe_to_release: 0,
      sequence: -1,
      observed_at: "not-a-time",
      status: :not_an_outcome,
      attribution: :not_an_attribution,
      transport_kind: :not_a_transport_kind
    }.each do |field, value|
      corrupted = replace_fact_payload(
        coordinator.facts,
        type: :provider_observed,
        changes: { field => value }
      )

      assert_raises(RubyRouting::State::DurableCorruptionError, "field=#{field}") do
        RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
      end
    end
  end

  def test_working_restore_rejects_ambiguous_observation_that_claims_safe_release
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    payout = intent("restore-ambiguous-safe-release")
    commit = coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy_for("restore-ambiguous-safe-release")
    )
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-ambiguous-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :unknown),
        transport_kind: :ambiguous_after_possible_send
      )
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :provider_observed,
      changes: {
        status: :safe_route_failure,
        attribution: :provider,
        safe_to_release: true
      }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_working_restore_rejects_definitely_not_sent_observation_with_unresolved_outcome
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    payout = intent("restore-not-sent-unresolved")
    commit = coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy_for("restore-not-sent-unresolved")
    )
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "restore-not-sent-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    corrupted = replace_fact_payload(
      coordinator.facts,
      type: :provider_observed,
      changes: {
        status: :pending,
        attribution: :unknown,
        safe_to_release: true,
        transport_kind: :definitely_not_sent
      }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::Coordinator.from_facts(facts: corrupted, opportunities: [provider])
    end
  end

  def test_coordinator_rejects_write_only_journal_for_restart_safe_recovery
    journal = Class.new do
      def append_many(_facts)
        nil
      end
    end.new

    error = assert_raises(ArgumentError) do
      RubyRouting::State::Coordinator.new(journal: journal)
    end

    assert_includes error.message, "restart-safe"
  end

  private

  def policy_for(id)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 2, ttl_seconds: 30)
    )
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def observation_for(commit, status = :success)
    RubyRouting::ProviderObservation.new(
      observation_id: "dedup-observation",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(status: status, attribution: :provider)
    )
  end

  def replace_fact_payload(facts, type:, changes:, operation_id: nil, action: nil)
    replaced = false
    facts.map do |fact|
      matches = fact.type == type &&
        (operation_id.nil? || fact.payload[:operation_id] == operation_id) &&
        (action.nil? || fact.payload[:action] == action)
      next fact unless matches && !replaced

      replaced = true
      RubyRouting::Fact.new(
        sequence: fact.sequence,
        type: fact.type,
        fact_id: fact.fact_id,
        payout_id: fact.payout_id,
        payload: fact.payload.merge(changes)
      )
    end
  end

  def renumber_facts(facts)
    facts.each_with_index.map do |fact, index|
      sequence = index + 1
      RubyRouting::Fact.new(
        sequence: sequence,
        type: fact.type,
        fact_id: "fact:#{sequence}",
        payout_id: fact.payout_id,
        payload: fact.payload
      )
    end
  end

  def append_fact(facts, source, changes: {})
    sequence = facts.length + 1
    facts + [
      RubyRouting::Fact.new(
        sequence: sequence,
        type: source.type,
        fact_id: "fact:#{sequence}",
        payout_id: source.payout_id,
        payload: source.payload.merge(changes)
      )
    ]
  end
end
