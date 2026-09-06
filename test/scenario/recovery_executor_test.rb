# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class RecoveryExecutorTest < Minitest::Test
  def test_one_pass_is_sorted_bounded_and_uses_canonical_resume
    clock = TestSupport::ControlledClock.new
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      clock: clock,
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
      steps: [
        TestSupport::Simulator::Step.unknown(attribution: :provider),
        TestSupport::Simulator::Step.unknown(attribution: :provider),
        TestSupport::Simulator::Step.success,
        TestSupport::Simulator::Step.success
      ]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    policy = policy_for("executor-order")
    service.commands.register_policy(policy)
    first = service.submit(intent: intent("a-due-payout"))
    second = service.submit(intent: intent("b-due-payout"))

    assert_equal :unknown, first.status
    assert_equal :unknown, second.status
    assert_equal %w[a-due-payout b-due-payout], service.queries.due_work.map(&:payout_id)

    pass = service.recovery_executor.run(limit: 1, as_of: clock.now)

    assert_equal 1, pass.processed_count
    assert_equal 0, pass.error_count
    assert pass.success?
    assert_equal clock.now, pass.as_of
    assert_equal 1, pass.limit
    assert_equal pass.to_h, {
      as_of: clock.now,
      limit: 1,
      items: pass.items.map(&:to_h)
    }
    assert_equal ["a-due-payout"], pass.items.map { |item| item.work_item.payout_id }
    assert_equal [:success], pass.items.map(&:status)
    assert_equal [:stop], pass.items.map(&:action)
    assert_equal :unknown, service.queries.payout("b-due-payout").status
    assert_equal ["b-due-payout"], service.queries.due_work(as_of: clock.now).map(&:payout_id)
    assert_equal 3, provider.calls.count { |call| call.first == :initiate || call.first == :resolve }

    second_pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
    assert_equal ["b-due-payout"], second_pass.items.map { |item| item.work_item.payout_id }
    assert_equal [:success], second_pass.items.map(&:status)
    assert_empty service.queries.due_work(as_of: clock.now)
  end

  def test_zero_limit_is_a_bounded_noop_and_invalid_limits_fail_closed
    clock = TestSupport::ControlledClock.new
    coordinator = RubyRouting::State::Coordinator.new(clock: clock)
    service = RubyRouting::Application::Service.new(coordinator: coordinator, providers: {})

    pass = service.recovery_executor.run(limit: 0, as_of: clock.now)
    assert_empty pass.items
    assert_equal 0, pass.processed_count
    assert_equal clock.now, pass.to_h.fetch(:as_of)
    assert pass.success?

    [nil, -1, 1.0, true, "1", RubyRouting::Application::RecoveryExecutor::MAX_BATCH_SIZE + 1].each do |limit|
      assert_raises(ArgumentError, "invalid limit #{limit.inspect}") do
        service.recovery_executor.run(limit: limit, as_of: clock.now)
      end
    end
    assert_raises(ArgumentError) do
      service.recovery_executor.run(limit: 1, as_of: "not-a-time")
    end
  end

  def test_future_scan_timestamp_is_rejected_instead_of_misrepresenting_execution_time
    service = StubService.new([work_item("future-scan")]) { StubService::StubResult.new(status: :success, action: :stop) }
    executor = RubyRouting::Application::RecoveryExecutor.new(service: service)

    error = assert_raises(ArgumentError) do
      executor.run(limit: 1, as_of: StubService::NOW + 1)
    end

    assert_equal "as_of cannot be later than the service current time", error.message
  end

  def test_scan_timestamp_is_not_reported_as_the_execution_timestamp
    clock = TestSupport::ControlledClock.new
    scan_at = clock.now
    resumed_at = []
    service = ClockedStubService.new([work_item("scan-only")], clock) do
      resumed_at << clock.now
      StubService::StubResult.new(status: :success, action: :stop)
    end
    executor = RubyRouting::Application::RecoveryExecutor.new(service: service)

    pass = executor.run(limit: 1, as_of: scan_at)

    assert_equal scan_at, pass.scan_as_of
    assert_equal [scan_at + 1], resumed_at
  end

  def test_provider_exception_is_structured_without_becoming_a_payout_outcome
    clock = TestSupport::ControlledClock.new
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      clock: clock,
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
      steps: [TestSupport::Simulator::Step.unknown(attribution: :provider)]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy_for("executor-error"))
    submitted = service.submit(intent: intent("executor-error-payout"))

    pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
    item = pass.items.fetch(0)

    assert_equal submitted.payout.id, item.work_item.payout_id
    assert item.error?
    assert_nil item.result
    assert_equal :error, item.status
    assert_equal :error, item.action
    assert_equal "RubyRouting::ProviderExecutionError", item.error.class_name
    assert_equal "provider execution failed", item.error.message
    assert_equal item.error.to_h, {
      class: "RubyRouting::ProviderExecutionError",
      message: item.error.message
    }
    assert_equal :unknown, service.queries.payout(submitted.payout.id).status
    assert_equal :unknown, service.queries.payout(submitted.payout.id).status
  end

  def test_raw_initiate_failure_becomes_immediate_due_work_without_changing_identity
    clock = TestSupport::ControlledClock.new
    calls = []
    provider = Class.new do
      define_method(:initiate) do |request|
        calls << [:initiate, request.operation_id, request.attempt_id]
        raise Timeout::Error, "raw initiate timeout"
      end

      define_method(:resolve) do |request|
        calls << [:resolve, request.operation_id, request.attempt_id]
        RubyRouting::ProviderObservation.new(
          observation_id: "raw-initiate-recovery-success",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy_for("raw-initiate-due"))
    payout = intent("raw-initiate-due-payout")

    error = assert_raises(RubyRouting::ProviderExecutionError) do
      service.submit(intent: payout)
    end
    assert_instance_of Timeout::Error, error.original_error

    failed = service.queries.payout(payout.id)
    owner = failed.ownership
    due_now = service.queries.due_work(as_of: clock.now)
    clock.advance(60)
    due_later = service.queries.due_work(as_of: clock.now)

    assert_equal :pending, failed.status
    assert_equal :dispatching, failed.current_operation_phase
    assert_nil failed.recovery_schedule
    assert_equal 1, failed.attempt_count
    assert_equal 1, failed.provider_interaction_count
    assert_equal 1, due_now.length
    assert_equal 1, due_later.length
    [due_now.first, due_later.first].each do |work_item|
      assert_equal :resolve, work_item.action
      assert_equal :provider_execution_failure, work_item.reason_code
      assert_equal payout.id, work_item.payout_id
      assert_equal owner.provider_id, work_item.provider_id
      assert_equal owner.operation_id, work_item.operation_id
      assert_equal owner.attempt_id, work_item.attempt_id
      assert_nil work_item.due_at
    end

    pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
    recovered = service.queries.payout(payout.id)

    assert pass.success?
    assert_equal [:success], pass.items.map(&:status)
    assert_equal [:stop], pass.items.map(&:action)
    assert_equal :success, recovered.status
    assert_equal [
      [:initiate, owner.operation_id, owner.attempt_id],
      [:resolve, owner.operation_id, owner.attempt_id]
    ], calls
    assert_equal [owner.operation_id], recovered.attempts.map(&:operation_id)
    assert_empty service.queries.due_work(as_of: clock.now)
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :provider_execution_failed }
    assert_equal 0, coordinator.facts.count { |fact| fact.type == :provider_observed && fact.payload[:transport_kind] }
  end

  def test_raw_initiate_failure_uses_idempotent_retry_policy_and_backoff
    clock = TestSupport::ControlledClock.new
    calls = []
    provider = Class.new do
      define_method(:initiate) do |request|
        calls << [:initiate, request.operation_id, request.attempt_id]
        if calls.length == 1
          raise Timeout::Error, "raw idempotent initiate timeout"
        end

        RubyRouting::ProviderObservation.new(
          observation_id: "raw-idempotent-retry-success",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end

      define_method(:resolve) do |_request|
        raise "status lookup must not be selected for idempotent retry"
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(idempotent_retry: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy_for(
      "raw-idempotent-retry",
      max_resolution_interactions: 1,
      initial_delay_seconds: 4,
      backoff_seconds: 3
    ))
    payout = intent("raw-idempotent-retry-payout")

    error = assert_raises(RubyRouting::ProviderExecutionError) do
      service.submit(intent: payout)
    end
    assert_instance_of Timeout::Error, error.original_error
    failed_at = clock.now
    failed = service.queries.payout(payout.id)
    owner = failed.ownership

    assert_empty service.queries.due_work(as_of: clock.now)
    clock.advance(4)
    due = service.queries.due_work(as_of: clock.now)
    assert_equal 1, due.length
    assert_equal :retry_same, due.first.action
    assert_equal :provider_execution_failure, due.first.reason_code
    assert_equal owner.operation_id, due.first.operation_id
    assert_equal owner.attempt_id, due.first.attempt_id
    assert_equal failed_at + 4, due.first.due_at

    pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
    recovered = service.queries.payout(payout.id)

    assert pass.success?
    assert_equal [:success], pass.items.map(&:status)
    assert_equal :success, recovered.status
    assert_equal [
      [:initiate, owner.operation_id, owner.attempt_id],
      [:initiate, owner.operation_id, owner.attempt_id]
    ], calls
    assert_equal 1, recovered.resolution_interaction_count
    assert_empty service.queries.due_work(as_of: clock.now)
  end

  def test_historical_due_work_does_not_expose_a_future_raw_failure_marker
    clock = TestSupport::ControlledClock.new
    provider = Class.new do
      def initiate(_request)
        raise Timeout::Error, "historical raw failure"
      end

      def resolve(_request)
        raise "resolve should not be called"
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy_for("historical-provider-failure"))
    payout = intent("historical-provider-failure-payout")

    assert_raises(RubyRouting::ProviderExecutionError) { service.submit(intent: payout) }
    failed_at = clock.now
    facts_before = coordinator.facts.length
    before_failure = service.queries.due_work(as_of: failed_at - 1, limit: 1)
    at_failure = service.queries.due_work(as_of: failed_at, limit: 1)

    assert_empty before_failure
    assert_equal 1, at_failure.length
    assert_equal :provider_execution_failure, at_failure.fetch(0).reason_code
    assert_equal facts_before, coordinator.facts.length
  end

  def test_historical_due_work_does_not_turn_a_future_failure_into_restart_work
    Dir.mktmpdir("ruby-routing-historical-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      provider = Class.new do
        define_method(:initiate) do |_request|
          clock.advance(1)
          raise Timeout::Error, "failure after attempt start"
        end

        def resolve(_request)
          raise "historical scan must not execute resolution"
        end
      end.new
      opportunity = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )
      coordinator = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [opportunity]
      )
      service = RubyRouting::Application::Service.new(
        coordinator: coordinator,
        providers: { "A" => provider }
      )
      service.commands.register_policy(policy_for("historical-restart-failure"))
      payout = intent("historical-restart-failure")

      assert_raises(RubyRouting::ProviderExecutionError) { service.submit(intent: payout) }
      started_at = coordinator.facts.reverse.find { |fact| fact.type == :attempt_started }.payload.fetch(:started_at)
      failed_at = coordinator.facts.reverse.find do |fact|
        fact.type == :provider_execution_failed
      end.payload.fetch(:failed_at)
      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )

      assert_empty recovered.due_work(as_of: started_at + Rational(1, 2))
      assert_equal [:resolve], recovered.due_work(as_of: failed_at).map(&:action)
      assert_equal [:provider_execution_failure], recovered.due_work(as_of: failed_at).map(&:reason_code)
    end
  end

  def test_historical_due_work_does_not_expose_a_future_reconciliation_block
    clock = TestSupport::ControlledClock.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, ttl_seconds: 10)
      )]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "historical-reconciliation-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 2)
    )
    payout = intent("historical-reconciliation-payout")
    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    token = coordinator.mark_attempt_started(committed)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "historical-reconciliation-unknown",
        payout_id: payout.id,
        provider_id: committed.proposal.provider_id,
        operation_id: committed.proposal.operation_id,
        attempt_id: committed.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
      ),
      interaction_token: token
    )
    clock.advance(10)
    blocked = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    blocked_at = clock.now

    assert_equal :reconciliation_blocked, blocked.payout.status
    assert_empty coordinator.due_work(as_of: blocked_at - 1)
    assert_equal [:operation_contract_expired],
      coordinator.due_work(as_of: blocked_at).map(&:reason_code)
  end

  def test_raw_resolve_failure_stays_due_for_executor_and_retries_same_operation
    clock = TestSupport::ControlledClock.new
    calls = []
    resolve_attempts = 0
    provider = Class.new do
      define_method(:initiate) do |request|
        calls << [:initiate, request.operation_id, request.attempt_id]
        RubyRouting::ProviderObservation.new(
          observation_id: "raw-resolve-initial-unknown",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
        )
      end

      define_method(:resolve) do |request|
        calls << [:resolve, request.operation_id, request.attempt_id]
        resolve_attempts += 1
        raise RuntimeError, "raw resolve exception" if resolve_attempts == 1

        RubyRouting::ProviderObservation.new(
          observation_id: "raw-resolve-recovery-success",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy_for("raw-resolve-due"))
    payout = intent("raw-resolve-due-payout")

    initial = service.submit(intent: payout)
    initial_owner = initial.payout.ownership
    initial_due = service.queries.due_work(as_of: clock.now)
    first_pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
    after_error = service.queries.payout(payout.id)
    after_error_owner = after_error.ownership
    due_after_error = service.queries.due_work(as_of: clock.now)
    replayed_after_error = RubyRouting::Projections::Replay.payout(coordinator.facts, payout.id)
    clock.advance(60)
    due_after_time = service.queries.due_work(as_of: clock.now)
    second_pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
    recovered = service.queries.payout(payout.id)

    assert_equal :unknown, initial.status
    assert_equal :wait, initial.action
    assert_equal [:resolve], initial_due.map(&:action)
    assert_equal initial_owner.operation_id, initial_due.first.operation_id
    assert_equal initial_owner.attempt_id, initial_due.first.attempt_id
    assert_equal :error, first_pass.items.first.status
    assert_equal "RubyRouting::ProviderExecutionError", first_pass.items.first.error.class_name
    assert_equal :resolving, after_error.current_operation_phase
    assert_equal initial_owner.operation_id, after_error_owner.operation_id
    assert_equal initial_owner.attempt_id, after_error_owner.attempt_id
    assert_equal [[:resolve, initial_owner.operation_id, initial_owner.attempt_id]],
      due_after_error.map { |item| [item.action, item.operation_id, item.attempt_id] }
    assert_equal [[:resolve, initial_owner.operation_id, initial_owner.attempt_id]],
      due_after_time.map { |item| [item.action, item.operation_id, item.attempt_id] }
    assert second_pass.success?
    assert_equal [:success], second_pass.items.map(&:status)
    assert_equal :success, recovered.status
    assert_equal [
      [:initiate, initial_owner.operation_id, initial_owner.attempt_id],
      [:resolve, initial_owner.operation_id, initial_owner.attempt_id],
      [:resolve, initial_owner.operation_id, initial_owner.attempt_id]
    ], calls
    assert_equal [initial_owner.operation_id], recovered.attempts.map(&:operation_id)
    assert_equal 3, recovered.provider_interaction_count
    assert_equal 2, recovered.resolution_interaction_count
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :provider_execution_failed }
    assert_equal :unknown, replayed_after_error.status
    assert_equal initial_owner.operation_id, replayed_after_error.attempts.first.operation_id
    assert_equal initial_owner.attempt_id, replayed_after_error.attempts.first.attempt_id
    assert_empty service.queries.due_work(as_of: clock.now)
  end

  def test_raw_provider_failure_without_recovery_capability_is_not_advertised_as_due
    clock = TestSupport::ControlledClock.new
    calls = []
    provider = Class.new do
      define_method(:initiate) do |request|
        calls << [:initiate, request.operation_id, request.attempt_id]
        raise RuntimeError, "provider has no recovery capability"
      end

      define_method(:resolve) do |request|
        calls << [:resolve, request.operation_id, request.attempt_id]
        raise "resolve must not run without status lookup or idempotent retry"
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "raw-failure-no-recovery-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 2)
    )
    payout = intent("raw-failure-no-recovery-payout")

    assert_raises(RubyRouting::ProviderExecutionError) do
      service.submit(intent: payout, policy: policy)
    end

    assert_empty service.queries.due_work(as_of: clock.now)
    result = service.resume(payout_id: payout.id, policy: policy)
    assert_equal :defer, result.action
    assert_equal :pending, result.status
    assert_equal [[:initiate, result.payout.ownership.operation_id, result.payout.ownership.attempt_id]], calls
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :provider_execution_failed }
  end

  def test_fresh_recovery_executor_discovers_crashed_dispatching_status_lookup
    Dir.mktmpdir("ruby-routing-recovery-executor") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      provider_opportunity = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )
      payout = intent("executor-crash-before-marker")
      policy = policy_for("executor-crash-before-marker")
      first = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [provider_opportunity]
      )
      committed = first.prepare_and_commit_decision(intent: payout, policy: policy)
      owner = first.mark_attempt_started(committed)
      attempt_id = committed.proposal.attempt_id

      calls = []
      provider = Class.new do
        define_method(:initiate) do |request|
          calls << [:initiate, request.operation_id, request.attempt_id]
          raise "crashed dispatch must not initiate a second operation"
        end

        define_method(:resolve) do |request|
          calls << [:resolve, request.operation_id, request.attempt_id]
          RubyRouting::ProviderObservation.new(
            observation_id: "executor-crash-before-marker-resolved",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end
      end.new
      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      service = RubyRouting::Application::Service.new(
        coordinator: recovered,
        providers: { "A" => provider }
      )

      before_start = service.queries.due_work(as_of: clock.now - 1, limit: 1)
      due = service.queries.due_work(as_of: clock.now, limit: 1)
      pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
      snapshot = service.queries.payout(payout.id)

      assert_empty before_start
      assert_equal 1, due.length
      assert_equal :resolve, due.first.action
      assert_equal :restart_recovery, due.first.reason_code
      assert_equal owner.operation_id, due.first.operation_id
      assert_equal attempt_id, due.first.attempt_id
      assert_equal :pending, due.first.status
      assert pass.success?
      assert_equal [:success], pass.items.map(&:status)
      assert_equal [:stop], pass.items.map(&:action)
      assert_equal [[:resolve, owner.operation_id, attempt_id]], calls
      assert_equal :success, snapshot.status
      assert_nil snapshot.ownership
      assert_equal [owner.operation_id], snapshot.attempts.map(&:operation_id)
      assert_equal 1, recovered.facts.count { |fact| fact.type == :allocation_committed }
      assert_equal 2, recovered.facts.count { |fact| fact.type == :attempt_started }
    end
  end

  def test_fresh_recovery_executor_discovers_crashed_dispatching_idempotent_retry
    Dir.mktmpdir("ruby-routing-recovery-executor") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      provider_opportunity = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(idempotent_retry: true)
      )
      payout = intent("executor-crash-before-marker-retry")
      policy = policy_for("executor-crash-before-marker-retry")
      first = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [provider_opportunity]
      )
      committed = first.prepare_and_commit_decision(intent: payout, policy: policy)
      first.mark_attempt_started(committed)

      calls = []
      provider = Class.new do
        define_method(:initiate) do |request|
          calls << [:initiate, request.operation_id, request.attempt_id]
          RubyRouting::ProviderObservation.new(
            observation_id: "executor-crash-before-marker-retried",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end

        define_method(:resolve) do |_request|
          raise "idempotent retry path must not resolve"
        end
      end.new
      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      service = RubyRouting::Application::Service.new(
        coordinator: recovered,
        providers: { "A" => provider }
      )

      due = service.queries.due_work(as_of: clock.now, limit: 1)
      pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
      snapshot = service.queries.payout(payout.id)

      assert_equal [:retry_same], due.map(&:action)
      assert_equal :restart_recovery, due.first.reason_code
      assert pass.success?
      assert_equal [[:initiate, committed.proposal.operation_id, committed.proposal.attempt_id]], calls
      assert_equal :success, snapshot.status
      assert_nil snapshot.ownership
      assert_equal [committed.proposal.operation_id], snapshot.attempts.map(&:operation_id)
    end
  end

  def test_crashed_dispatching_without_recovery_capability_stays_pinned_and_not_due
    Dir.mktmpdir("ruby-routing-recovery-executor") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      payout = intent("executor-crash-without-capability")
      policy = policy_for("executor-crash-without-capability")
      first = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
      )
      committed = first.prepare_and_commit_decision(intent: payout, policy: policy)
      first.mark_attempt_started(committed)

      calls = []
      provider = Class.new do
        define_method(:initiate) do |request|
          calls << [:initiate, request.operation_id, request.attempt_id]
          raise "unsupported crashed dispatch must remain pinned"
        end

        define_method(:resolve) do |request|
          calls << [:resolve, request.operation_id, request.attempt_id]
          raise "unsupported crashed dispatch must not resolve"
        end
      end.new
      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      service = RubyRouting::Application::Service.new(
        coordinator: recovered,
        providers: { "A" => provider }
      )

      assert_empty service.queries.due_work(as_of: clock.now)
      result = service.resume(payout_id: payout.id)
      snapshot = service.queries.payout(payout.id)

      assert_equal :defer, result.action
      assert_equal :pending, result.status
      assert_empty calls
      assert_equal committed.proposal.operation_id, snapshot.ownership.operation_id
      assert_equal committed.proposal.attempt_id, snapshot.ownership.attempt_id
      assert_equal :dispatching, snapshot.current_operation_phase
    end
  end

  def test_post_return_provider_validation_failure_aborts_instead_of_becoming_an_item_error
    clock = TestSupport::ControlledClock.new
    provider = Class.new do
      def initiate(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "post-return-unknown",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
        )
      end

      def resolve(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "post-return-malformed",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: "wrong-operation",
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy_for("post-return-validation"))
    submitted = service.submit(intent: intent("post-return-validation-payout"))

    assert_equal :unknown, submitted.status
    error = assert_raises(RubyRouting::ProviderContractError) do
      service.recovery_executor.run(limit: 1, as_of: clock.now)
    end

    assert_instance_of ArgumentError, error.original_error
    assert_equal "provider observation linkage does not match request", error.original_error.message
    snapshot = service.queries.payout(submitted.payout.id)
    assert_equal :unknown, snapshot.status
    assert_equal :resolving, snapshot.current_operation_phase
    assert_equal "A", snapshot.ownership.provider_id
    assert_equal 2, snapshot.provider_interaction_count
    assert_equal 0, coordinator.facts.count { |fact| fact.type == :provider_interaction_completed }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :provider_observed }
  end

  def test_durable_corruption_aborts_the_pass_instead_of_becoming_an_item_error
    first = work_item("corrupt-payout")
    second = work_item("independent-payout")
    resumed = []
    service = StubService.new([first, second]) do |payout_id|
      resumed << payout_id
      raise RubyRouting::State::DurableCorruptionError, "journal is poisoned"
    end
    executor = RubyRouting::Application::RecoveryExecutor.new(service: service)

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      executor.run(limit: 2, as_of: StubService::NOW)
    end

    assert_equal "journal is poisoned", error.message
    assert_equal ["corrupt-payout"], resumed
  end

  def test_programming_failure_aborts_the_pass_instead_of_becoming_an_item_error
    first = work_item("programming-failure-payout")
    second = work_item("independent-payout")
    resumed = []
    service = StubService.new([first, second]) do |payout_id|
      resumed << payout_id
      raise NoMethodError, "undefined method `resume_step' for nil"
    end
    executor = RubyRouting::Application::RecoveryExecutor.new(service: service)

    error = assert_raises(NoMethodError) do
      executor.run(limit: 2, as_of: StubService::NOW)
    end

    assert_includes error.message, "resume_step"
    assert_equal ["programming-failure-payout"], resumed
  end

  def test_configuration_drift_aborts_the_pass_instead_of_becoming_an_item_error
    first = work_item("configuration-drift-payout")
    second = work_item("independent-payout")
    resumed = []
    service = StubService.new([first, second]) do |payout_id|
      resumed << payout_id
      raise RubyRouting::ConfigurationDriftError, "active configuration drifted"
    end
    executor = RubyRouting::Application::RecoveryExecutor.new(service: service)

    error = assert_raises(RubyRouting::ConfigurationDriftError) do
      executor.run(limit: 2, as_of: StubService::NOW)
    end

    assert_equal "active configuration drifted", error.message
    assert_equal ["configuration-drift-payout"], resumed
  end

  def test_typed_provider_failure_does_not_hide_independent_due_work
    first = work_item("provider-failure-payout")
    second = work_item("independent-payout")
    resumed = []
    service = StubService.new([first, second]) do |payout_id|
      resumed << payout_id
      if payout_id == first.payout_id
        raise RubyRouting::ProviderExecutionError.new(
          Timeout::Error.new("provider read deadline exceeded")
        )
      end

      StubService::StubResult.new(status: :success, action: :stop)
    end
    executor = RubyRouting::Application::RecoveryExecutor.new(service: service)

    pass = executor.run(limit: 2, as_of: StubService::NOW)

    assert_equal ["provider-failure-payout", "independent-payout"], resumed
    assert_equal 1, pass.error_count
    assert_equal [:error, :success], pass.items.map(&:status)
    assert_equal "RubyRouting::ProviderExecutionError", pass.items.first.error.class_name
    assert_equal :stop, pass.items.last.action
  end

  def test_duplicate_executor_workers_share_existing_coordinator_authority
    clock = TestSupport::ControlledClock.new
    provider = BlockingRecoveryProvider.new(clock)
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy_for("executor-duplicate"))
    submitted = service.submit(intent: intent("executor-duplicate-payout"))
    assert_equal :unknown, submitted.status

    workers = 2.times.map do
      Thread.new { service.recovery_executor.run(limit: 1, as_of: clock.now) }
    end
    assert_equal :resolve, Timeout.timeout(3) { provider.entered.pop }

    provider.release
    passes = workers.map { |worker| Timeout.timeout(3) { worker.value } }

    assert_equal 1, provider.calls.count { |call| call.first == :resolve }
    assert_equal 1, passes.flat_map(&:items).count { |item| item.status == :success }
    assert_equal :success, service.queries.payout(submitted.payout.id).status
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :settlement_recorded }
    assert_equal 0, coordinator.active_unresolved_owners
  ensure
    provider&.release
    workers&.each { |worker| worker.join(3) }
  end

  def test_post_return_contract_failure_is_not_same_process_restart_work
    Dir.mktmpdir("ruby-routing-live-contract-failure") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      provider = Class.new do
        def initiate(request)
          RubyRouting::ProviderObservation.new(
            observation_id: "live-contract-initial-unknown",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
          )
        end

        def resolve(request)
          RubyRouting::ProviderObservation.new(
            observation_id: "live-contract-malformed",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: "wrong-operation",
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end
      end.new
      coordinator = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        )]
      )
      service = RubyRouting::Application::Service.new(
        coordinator: coordinator,
        providers: { "A" => provider }
      )
      service.commands.register_policy(policy_for("live-contract-failure"))
      payout = intent("live-contract-failure-payout")

      submitted = service.submit(intent: payout)
      assert_equal :unknown, submitted.status
      error = assert_raises(RubyRouting::ProviderContractError) do
        service.recovery_executor.run(limit: 1, as_of: clock.now)
      end

      snapshot = service.queries.payout(payout.id)
      assert_equal "provider observation linkage does not match request", error.original_error.message
      assert_equal :unknown, snapshot.status
      assert_equal :resolving, snapshot.current_operation_phase
      assert_equal 2, snapshot.provider_interaction_count
      assert_equal 1, snapshot.resolution_interaction_count
      assert_nil snapshot.recovery_schedule
      assert_equal 1, coordinator.facts.count { |fact| fact.type == :provider_observed }
      assert_equal 2, coordinator.facts.count { |fact| fact.type == :attempt_started }
      assert_equal 0, coordinator.facts.count { |fact| fact.type == :provider_execution_failed }

      # A live post-return failure is not a fresh-process restart signal. The
      # durable shape is intentionally still recoverable after reconstruction.
      assert_empty service.queries.due_work(as_of: clock.now)
      assert_raises(ArgumentError) do
        coordinator.apply_observation(
          RubyRouting::ProviderObservation.new(
            observation_id: "live-contract-initial-unknown",
            payout_id: payout.id,
            provider_id: "A",
            operation_id: snapshot.ownership.operation_id,
            attempt_id: snapshot.ownership.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        )
      end
      assert_empty service.queries.due_work(as_of: clock.now)
      assert_raises(ArgumentError) do
        coordinator.apply_observation(
          RubyRouting::ProviderObservation.new(
            observation_id: "malformed-independent-callback",
            payout_id: payout.id,
            provider_id: "A",
            operation_id: snapshot.ownership.operation_id,
            attempt_id: "wrong-attempt",
            outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
          )
        )
      end
      assert_empty service.queries.due_work(as_of: clock.now)

      probe = File.expand_path("../support/fresh_process_causal_due_work.rb", __dir__)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, probe, path, payout.id)
      assert status.success?, "fresh due probe failed: stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      fresh_due = JSON.parse(stdout).fetch("due")
      assert_equal [
        {
          "action" => "resolve",
          "provider_id" => "A",
          "operation_id" => snapshot.ownership.operation_id,
          "attempt_id" => snapshot.ownership.attempt_id,
          "reason_code" => "restart_recovery",
          "status" => "unknown"
        }
      ], fresh_due
    end
  end

  def test_post_return_application_failure_is_not_same_process_restart_work
    Dir.mktmpdir("ruby-routing-live-application-failure") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      failing_observation_class = Class.new(RubyRouting::ProviderObservation) do
        define_method(:with_interaction_duration) do |_duration_seconds|
          raise ArgumentError, "application duration enrichment failed"
        end
      end
      provider = Class.new do
        define_method(:initiate) do |request|
          RubyRouting::ProviderObservation.new(
            observation_id: "live-application-initial-unknown",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
          )
        end

        define_method(:resolve) do |request|
          failing_observation_class.new(
            observation_id: "live-application-valid-return",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end
      end.new
      coordinator = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        )]
      )
      service = RubyRouting::Application::Service.new(
        coordinator: coordinator,
        providers: { "A" => provider }
      )
      service.commands.register_policy(policy_for("live-application-failure"))
      payout = intent("live-application-failure-payout")

      submitted = service.submit(intent: payout)
      assert_equal :unknown, submitted.status
      error = assert_raises(RubyRouting::ApplicationProcessingError) do
        service.recovery_executor.run(limit: 1, as_of: clock.now)
      end

      snapshot = service.queries.payout(payout.id)
      assert_equal "application duration enrichment failed", error.original_error.message
      assert_equal :unknown, snapshot.status
      assert_equal :resolving, snapshot.current_operation_phase
      assert_equal 2, snapshot.provider_interaction_count
      assert_equal 1, snapshot.resolution_interaction_count
      assert_equal 1, coordinator.facts.count { |fact| fact.type == :provider_observed }
      assert_equal 2, coordinator.facts.count { |fact| fact.type == :attempt_started }
      assert_equal 0, coordinator.facts.count { |fact| fact.type == :provider_execution_failed }
      assert_empty service.queries.due_work(as_of: clock.now)

      probe = File.expand_path("../support/fresh_process_causal_due_work.rb", __dir__)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, probe, path, payout.id)
      assert status.success?, "fresh application-failure probe failed: stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      fresh_due = JSON.parse(stdout).fetch("due")
      assert_equal [
        {
          "action" => "resolve",
          "provider_id" => "A",
          "operation_id" => snapshot.ownership.operation_id,
          "attempt_id" => snapshot.ownership.attempt_id,
          "reason_code" => "restart_recovery",
          "status" => "unknown"
        }
      ], fresh_due
    end
  end

  def test_due_work_as_of_is_not_historical_time_travel
    clock = TestSupport::ControlledClock.new
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      clock: clock,
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
      steps: [TestSupport::Simulator::Step.unknown, TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy_for("due-work-causal-cutoff"))
    payout = intent("due-work-causal-cutoff-payout")

    submitted = service.submit(intent: payout)
    resolved_at = clock.now
    assert_equal :unknown, submitted.status
    assert_equal :success, service.resume(payout_id: payout.id).status
    clock.advance(10)
    facts_before_query = coordinator.facts.length

    assert_empty service.queries.due_work(as_of: resolved_at)
    assert_equal facts_before_query, coordinator.facts.length
  end

  def test_raw_resolve_failure_respects_resolution_budget_in_due_work_and_restart
    Dir.mktmpdir("ruby-routing-raw-resolution-budget") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      calls = []
      provider = Class.new do
        define_method(:initiate) do |request|
          calls << [:initiate, request.operation_id, request.attempt_id]
          RubyRouting::ProviderObservation.new(
            observation_id: "raw-budget-initial-unknown",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
          )
        end

        define_method(:resolve) do |request|
          calls << [:resolve, request.operation_id, request.attempt_id]
          raise Timeout::Error, "raw resolution timeout"
        end
      end.new
      coordinator = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        )]
      )
      service = RubyRouting::Application::Service.new(
        coordinator: coordinator,
        providers: { "A" => provider }
      )
      policy = policy_for(
        "raw-resolution-budget",
        max_resolution_interactions: 1,
        initial_delay_seconds: 5,
        backoff_seconds: 7
      )
      service.commands.register_policy(policy)
      payout = intent("raw-resolution-budget-payout")

      submitted = service.submit(intent: payout)
      owner = submitted.payout.ownership
      assert_empty service.queries.due_work(as_of: clock.now)
      clock.advance(5)
      first_pass = service.recovery_executor.run(limit: 1, as_of: clock.now)

      snapshot = service.queries.payout(payout.id)
      assert_equal :error, first_pass.items.first.status
      assert_equal :unknown, snapshot.status
      assert_equal :resolving, snapshot.current_operation_phase
      assert_equal 1, snapshot.resolution_interaction_count
      assert_equal [[:initiate, owner.operation_id, owner.attempt_id],
                    [:resolve, owner.operation_id, owner.attempt_id]], calls
      assert_empty service.queries.due_work(as_of: clock.now)

      second_pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
      assert_empty second_pass.items
      assert_equal [[:initiate, owner.operation_id, owner.attempt_id],
                    [:resolve, owner.operation_id, owner.attempt_id]], calls
      assert_equal 1, service.queries.payout(payout.id).resolution_interaction_count

      fresh_due_probe = File.expand_path("../support/fresh_process_causal_due_work.rb", __dir__)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, fresh_due_probe, path, payout.id)
      assert status.success?, "fresh raw-budget probe failed: stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      assert_empty JSON.parse(stdout).fetch("due")
    end
  end

  def test_raw_resolve_failure_uses_backoff_for_the_next_allowed_interaction
    clock = TestSupport::ControlledClock.new
    calls = []
    provider = Class.new do
      define_method(:initiate) do |request|
        calls << [:initiate, request.operation_id, request.attempt_id]
        RubyRouting::ProviderObservation.new(
          observation_id: "raw-backoff-initial-unknown",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
        )
      end

      define_method(:resolve) do |request|
        calls << [:resolve, request.operation_id, request.attempt_id]
        raise Timeout::Error, "raw resolution timeout"
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    policy = policy_for(
      "raw-resolution-backoff",
      max_resolution_interactions: 2,
      initial_delay_seconds: 3,
      backoff_seconds: 4
    )
    service.commands.register_policy(policy)
    payout = intent("raw-resolution-backoff-payout")

    initial = service.submit(intent: payout)
    owner = initial.payout.ownership
    clock.advance(3)
    first_pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
    failed_at = clock.now

    assert_equal :error, first_pass.items.first.status
    assert_empty service.queries.due_work(as_of: failed_at + 6)
    early_resume = service.resume(payout_id: payout.id)
    assert_equal :defer, early_resume.action
    assert_equal :resolving, early_resume.payout.current_operation_phase
    assert_equal [[:initiate, owner.operation_id, owner.attempt_id],
                  [:resolve, owner.operation_id, owner.attempt_id]], calls

    clock.advance(7)
    due = service.queries.due_work(as_of: clock.now)
    assert_equal 1, due.length
    assert_equal :resolve, due.first.action
    assert_equal :provider_execution_failure, due.first.reason_code
    assert_equal failed_at + 7, due.first.due_at

    second_pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
    assert_equal :error, second_pass.items.first.status
    assert_equal [[:initiate, owner.operation_id, owner.attempt_id],
                  [:resolve, owner.operation_id, owner.attempt_id],
                  [:resolve, owner.operation_id, owner.attempt_id]], calls
    assert_empty service.queries.due_work(as_of: clock.now)
  end

  def test_restart_recovery_respects_zero_resolution_budget_before_provider_io
    Dir.mktmpdir("ruby-routing-restart-budget") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      opportunity = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )
      policy = policy_for("restart-zero-budget", max_resolution_interactions: 0)
      payout = intent("restart-zero-budget-payout")
      first = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [opportunity]
      )
      committed = first.prepare_and_commit_decision(intent: payout, policy: policy)
      first.mark_attempt_started(committed)

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      calls = []
      provider = Class.new do
        define_method(:initiate) { |_request| calls << :initiate }
        define_method(:resolve) { |_request| calls << :resolve }
      end.new
      service = RubyRouting::Application::Service.new(
        coordinator: recovered,
        providers: { "A" => provider }
      )

      assert_empty service.queries.due_work(as_of: clock.now)
      result = service.resume(payout_id: payout.id)
      assert_equal :defer, result.action
      assert_equal :pending, result.status
      assert_empty calls
      assert_equal committed.proposal.operation_id, result.payout.ownership.operation_id
      assert_equal :dispatching, result.payout.current_operation_phase
    end
  end

  def test_fatal_adapter_failure_is_live_only_but_fresh_process_recovery_remains_discoverable
    Dir.mktmpdir("ruby-routing-fatal-adapter") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      provider = Class.new do
        def initiate(_request)
          raise NotImplementedError, "fatal adapter initiation probe"
        end

        def resolve(_request)
          raise NotImplementedError, "fatal adapter resolution probe"
        end
      end.new
      coordinator = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        )]
      )
      service = RubyRouting::Application::Service.new(
        coordinator: coordinator,
        providers: { "A" => provider }
      )
      service.commands.register_policy(policy_for("fatal-adapter"))
      payout = intent("fatal-adapter-payout")

      assert_raises(NotImplementedError) do
        service.submit(intent: payout)
      end

      snapshot = service.queries.payout(payout.id)
      assert_equal :pending, snapshot.status
      assert_equal :dispatching, snapshot.current_operation_phase
      assert_empty service.queries.due_work(as_of: clock.now)
      assert_empty coordinator.facts.select { |fact| fact.type == :provider_execution_failed }

      probe = File.expand_path("../support/fresh_process_causal_due_work.rb", __dir__)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, probe, path, payout.id)
      assert status.success?, "fresh fatal-adapter due probe failed: stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      fresh_due = JSON.parse(stdout).fetch("due")
      assert_equal [
        {
          "action" => "resolve",
          "provider_id" => "A",
          "operation_id" => snapshot.ownership.operation_id,
          "attempt_id" => snapshot.ownership.attempt_id,
          "reason_code" => "restart_recovery",
          "status" => "pending"
        }
      ], fresh_due
    end
  end

  private

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def policy_for(id, max_resolution_interactions: 2, initial_delay_seconds: 0, backoff_seconds: 0)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 3,
        max_resolution_interactions: max_resolution_interactions,
        initial_delay_seconds: initial_delay_seconds,
        backoff_seconds: backoff_seconds
      )
    )
  end

  def work_item(payout_id)
    RubyRouting::RecoveryWorkItem.new(
      payout_id: payout_id,
      action: :resolve,
      provider_id: "A",
      operation_id: "operation-#{payout_id}",
      attempt_id: "attempt-#{payout_id}",
      due_at: StubService::NOW,
      reason_code: :recovery_due,
      status: :unknown
    )
  end

  class StubService < RubyRouting::Application::Service
    NOW = Time.utc(2026, 1, 1).freeze
    StubResult = Data.define(:status, :action)

    attr_reader :queries

    def initialize(work, &resume_handler)
      @queries = StubQueries.new(work)
      @resume_handler = resume_handler
    end

    def resume(payout_id:)
      @resume_handler.call(payout_id)
    end
  end

  class StubQueries
    def initialize(work)
      @work = work.freeze
    end

    def current_time
      StubService::NOW
    end

    def due_work(as_of:, limit:)
      raise "unexpected as_of" unless as_of == StubService::NOW

      @work.first(limit)
    end
  end

  class ClockedStubService < StubService
    attr_reader :queries

    def initialize(work, clock, &resume_handler)
      @queries = ClockedStubQueries.new(work, clock)
      @clock = clock
      @resume_handler = resume_handler
    end

    def resume(payout_id:)
      @resume_handler.call(payout_id)
    end
  end

  class ClockedStubQueries
    def initialize(work, clock)
      @work = work.freeze
      @clock = clock
    end

    def current_time
      @clock.now
    end

    def due_work(as_of:, limit:)
      raise "scan timestamp changed before query" unless as_of == @clock.now

      @clock.advance(1)
      @work.first(limit)
    end
  end

  class BlockingRecoveryProvider
    attr_reader :calls, :entered

    def initialize(clock)
      @clock = clock
      @calls = []
      @entered = Queue.new
      @release = Queue.new
      @mutex = Thread::Mutex.new
      @operation = nil
    end

    def initiate(request)
      @mutex.synchronize do
        @calls << [:initiate, request.operation_id].freeze
        @operation = request
      end
      observation(request, :unknown, "initial")
    end

    def resolve(request)
      @mutex.synchronize { @calls << [:resolve, request.operation_id].freeze }
      @entered << :resolve
      @release.pop
      observation(request, :success, "resolved")
    end

    def release
      @release << true
    end

    private

    def observation(request, status, label)
      RubyRouting::ProviderObservation.new(
        observation_id: "executor:#{request.operation_id}:#{label}",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.new(
          status: status,
          attribution: :provider,
          safe_to_release: status == :success
        ),
        provider_reference: "executor-reference",
        observed_at: @clock.now
      )
    end
  end
end
