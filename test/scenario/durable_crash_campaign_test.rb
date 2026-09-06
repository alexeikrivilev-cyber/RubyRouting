# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class DurableCrashCampaignTest < Minitest::Test
  CRASH_SEED = 20_260_829

  class CrashJournal
    attr_reader :facts

    def initialize
      @facts = []
      @append_count = 0
      @crash_at = nil
    end

    def crash_on_next_append!
      @crash_at = @append_count + 1
    end

    def append_many(facts)
      @facts.concat(facts)
      @append_count += 1
      return unless @append_count == @crash_at

      @crash_at = nil
      raise SystemExit, "simulated crash seed=#{CRASH_SEED} append=#{@append_count}"
    end
  end

  class AlwaysSuccessProvider
    def initiate(request)
      observation(request, "initiate")
    end

    def resolve(request)
      observation(request, "resolve")
    end

    private

    def observation(request, phase)
      RubyRouting::ProviderObservation.new(
        observation_id: "crash-campaign:#{request.operation_id}:#{phase}",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    end
  end

  def test_crash_after_assignment_batch_restores_owner_and_dispatches_same_operation
    journal = CrashJournal.new
    coordinator = build_coordinator(journal: journal, opportunities: [opportunity("A", status_lookup: true)])
    payout = intent("crash-after-assignment")
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.prepare_and_commit_decision(intent: payout, policy: policy("crash-assignment"))
    end

    recovered = recover(journal: journal)
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: recovered,
      providers: { "A" => AlwaysSuccessProvider.new }
    ).resume(payout_id: payout.id)

    assert_equal :success, result.status, campaign_trace(recovered, "assignment")
    assert_nil result.payout.ownership
    assert_equal 1, result.payout.attempt_count
  end

  def test_crash_after_possible_provider_acceptance_preserves_settlement
    journal = CrashJournal.new
    coordinator = build_coordinator(journal: journal, opportunities: [opportunity("A")])
    payout = intent("crash-after-accepted")
    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy("crash-accepted"))
    coordinator.mark_attempt_started(committed)
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.apply_observation(observation(committed, :success, :provider))
    end

    recovered = recover(journal: journal)
    snapshot = recovered.payout_snapshot(payout.id)
    assert_equal :success, snapshot.status, campaign_trace(recovered, "accepted")
    assert_nil snapshot.ownership
    assert_equal recovered.lifecycle_projection.to_h,
      RubyRouting::Projections::Replay.lifecycle(recovered.facts).to_h
  end

  def test_crash_after_unknown_observation_keeps_owner_and_only_resolves_same_operation
    journal = CrashJournal.new
    coordinator = build_coordinator(journal: journal, opportunities: [opportunity("A", status_lookup: true)])
    payout = intent("crash-after-unknown")
    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy("crash-unknown"))
    coordinator.mark_attempt_started(committed)
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.apply_observation(observation(committed, :unknown, :provider))
    end

    recovered = recover(journal: journal)
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: recovered,
      providers: { "A" => AlwaysSuccessProvider.new }
    ).resume(payout_id: payout.id)

    assert_equal :success, result.status, campaign_trace(recovered, "unknown")
    assert_equal [committed.proposal.operation_id],
      result.payout.attempts.map(&:operation_id)
  end

  def test_crash_after_safe_release_restarts_with_fresh_fallback
    journal = CrashJournal.new
    coordinator = build_coordinator(
      journal: journal,
      opportunities: [opportunity("A"), opportunity("B")]
    )
    payout = intent("crash-after-release")
    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy("crash-release", targets: { "A" => 1, "B" => 1 }))
    interaction_token = coordinator.mark_attempt_started(committed)
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.apply_observation(
        observation(committed, :safe_route_failure, :provider),
        interaction_token: interaction_token
      )
    end

    recovered = recover(journal: journal)
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: recovered,
      providers: { "A" => AlwaysSuccessProvider.new, "B" => AlwaysSuccessProvider.new }
    ).resume(payout_id: payout.id, policy: policy("crash-release", targets: { "A" => 1, "B" => 1 }))

    assert_equal :success, result.status, campaign_trace(recovered, "safe-release")
    assert_equal ["A", "B"], result.payout.attempts.map(&:provider_id)
  end

  def test_crash_after_settlement_restores_final_state_without_dispatch
    journal = CrashJournal.new
    coordinator = build_coordinator(journal: journal, opportunities: [opportunity("A")])
    payout = intent("crash-after-settlement")
    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy("crash-settlement"))
    coordinator.mark_attempt_started(committed)
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.apply_observation(observation(committed, :success, :provider))
    end

    recovered = recover(journal: journal)
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: recovered,
      providers: {}
    ).resume(payout_id: payout.id)

    assert_equal :already_final, result.action, campaign_trace(recovered, "settlement")
    assert_equal :success, result.status
    assert_equal 1, result.payout.attempt_count
  end

  def test_crash_while_reconciliation_blocked_keeps_owner_until_explicit_observation
    journal = CrashJournal.new
    clock = TestSupport::ControlledClock.new
    coordinator = build_coordinator(
      journal: journal,
      clock: clock,
      opportunities: [opportunity("A", status_lookup: true)]
    )
    payout = intent("crash-reconciliation")
    policy = policy("crash-reconciliation", ttl_seconds: 1)
    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    clock.advance(1)
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    end

    recovered = recover(journal: journal, clock: clock)
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: recovered,
      providers: {}
    ).resume(payout_id: payout.id)

    assert_equal :defer, result.action, campaign_trace(recovered, "reconciliation")
    assert_equal :reconciliation_blocked, result.status
    assert_equal committed.proposal.operation_id, result.payout.ownership.operation_id

    settled = recovered.apply_observation(observation(committed, :success, :provider))
    assert_equal :success, settled.payout.status
    assert_nil settled.payout.ownership
  end

  def test_fresh_process_after_independent_release_without_completion_cannot_start_provider_b
    Dir.mktmpdir("ruby-routing-causal-crash") do |directory|
      path = File.join(directory, "facts.jsonl")
      payout = intent("ptz6-fresh-process-causal-gap")
      probe = File.expand_path("../support/fresh_process_causal_dispatch.rb", __dir__)
      resume = File.expand_path("../support/fresh_process_causal_resume.rb", __dir__)

      stdin, stdout, stderr, wait_thread = Open3.popen3(
        RbConfig.ruby,
        probe,
        path,
        payout.id
      )
      begin
        started = Timeout.timeout(3) { JSON.parse(stdout.gets) }
        assert_equal "initiate_started", started.fetch("event")
        assert_equal payout.id, started.fetch("payout_id")
        assert_equal "A", started.fetch("provider_id")

        callback_coordinator = RubyRouting::State::Coordinator.new(
          journal: RubyRouting::State::FileJournal.new(path)
        )
        callback = callback_coordinator.apply_observation(observation_from_started(started))
        assert_equal :wait, callback.next_action
        assert_equal started.fetch("operation_id"), callback.payout.ownership.operation_id
        assert_equal 1, callback_coordinator_facts(callback_coordinator, :attempt_started)
        assert_equal 0, callback_coordinator_facts(callback_coordinator, :ownership_released)

        stdin.puts("crash")
        stdin.close
        status = Timeout.timeout(3) { wait_thread.value }
        refute status.success?
      ensure
        Process.kill("KILL", wait_thread.pid) if wait_thread.alive?
        stdin.close unless stdin.closed?
        stdout.close unless stdout.closed?
        stderr.close unless stderr.closed?
      end

      due_probe = File.expand_path("../support/fresh_process_causal_due_work.rb", __dir__)
      due_output, due_error, due_status = Open3.capture3(
        RbConfig.ruby,
        due_probe,
        path,
        payout.id
      )
      assert due_status.success?, "fresh due-work probe failed: #{due_output}\n#{due_error}"
      due_result = JSON.parse(due_output)
      assert_equal "dispatching", due_result.fetch("phase")
      assert_equal "pending", due_result.fetch("status")
      assert_equal started.fetch("operation_id"), due_result.fetch("operation_id")
      assert_equal [
        {
          "action" => "resolve",
          "provider_id" => "A",
          "operation_id" => started.fetch("operation_id"),
          "attempt_id" => started.fetch("attempt_id"),
          "reason_code" => "restart_recovery",
          "status" => "pending"
        }
      ], due_result.fetch("due")

      output, error_output, status = Open3.capture3(RbConfig.ruby, resume, path, payout.id)
      assert status.success?, "fresh resume failed: #{output}\n#{error_output}"
      result = JSON.parse(output)

      assert_equal "wait", result.fetch("action")
      assert_equal "unknown", result.fetch("status")
      assert_equal [["resolve", started.fetch("operation_id")]], result.fetch("calls")
      assert_equal ["A"], result.fetch("attempts").map { |attempt| attempt.fetch("provider_id") }
      assert_equal 2, result.fetch("fact_counts").fetch("attempt_started")
      assert_equal 0, result.fetch("fact_counts").fetch("ownership_released", 0)
      assert_equal 2, result.fetch("fact_counts").fetch("provider_observed")
      assert_equal 0, result.fetch("fact_counts").fetch("economic_conflict", 0)
      assert_equal 1, result.fetch("fact_counts").fetch("allocation_committed")
    end
  end

  def test_fatal_apply_process_death_restarts_from_durable_attempt_without_provider_b
    Dir.mktmpdir("ruby-routing-fatal-apply") do |directory|
      path = File.join(directory, "facts.jsonl")
      payout = intent("ptz10-fatal-apply-process-death")
      probe = File.expand_path("../support/fresh_process_fatal_apply.rb", __dir__)
      due_probe = File.expand_path("../support/fresh_process_causal_due_work.rb", __dir__)
      resume = File.expand_path("../support/fresh_process_causal_resume.rb", __dir__)

      output, error_output, status = Open3.capture3(
        RbConfig.ruby,
        probe,
        path,
        payout.id
      )
      refute status.success?
      assert_equal "provider_returned", JSON.parse(output).fetch("event")
      assert_includes error_output, "fatal apply-path process-death probe"

      due_output, due_error, due_status = Open3.capture3(
        RbConfig.ruby,
        due_probe,
        path,
        payout.id
      )
      assert due_status.success?, "fresh due-work probe failed: #{due_output}\n#{due_error}"
      due_result = JSON.parse(due_output)
      assert_equal "pending", due_result.fetch("status")
      assert_equal "dispatching", due_result.fetch("phase")
      assert_equal ["resolve"], due_result.fetch("due").map { |item| item.fetch("action") }
      assert_equal ["A"], due_result.fetch("due").map { |item| item.fetch("provider_id") }

      resume_output, resume_error, resume_status = Open3.capture3(
        RbConfig.ruby,
        resume,
        path,
        payout.id
      )
      assert resume_status.success?, "fresh resume failed: #{resume_output}\n#{resume_error}"
      result = JSON.parse(resume_output)
      assert_equal "wait", result.fetch("action")
      assert_equal "unknown", result.fetch("status")
      assert_equal [["resolve", due_result.fetch("operation_id")]], result.fetch("calls")
      assert_equal ["A"], result.fetch("attempts").map { |attempt| attempt.fetch("provider_id") }
      assert_equal 0, result.fetch("fact_counts").fetch("economic_conflict", 0)
    end
  end

  def test_fresh_process_after_held_release_and_ttl_expiry_keeps_reconciliation_owner
    Dir.mktmpdir("ruby-routing-reconciliation-crash") do |directory|
      path = File.join(directory, "facts.jsonl")
      payout = intent("ptz6-fresh-process-reconciliation-crash")
      probe = File.expand_path("../support/fresh_process_reconciliation_dispatch.rb", __dir__)
      resume = File.expand_path("../support/fresh_process_reconciliation_resume.rb", __dir__)
      policy = policy(
        "ptz6-fresh-reconciliation-policy",
        targets: { "A" => 1, "B" => 1 },
        ttl_seconds: 1
      )

      stdin, stdout, stderr, wait_thread = Open3.popen3(
        RbConfig.ruby,
        probe,
        path,
        payout.id
      )
      begin
        started = Timeout.timeout(3) { JSON.parse(stdout.gets) }
        assert_equal "initiate_started", started.fetch("event")

        clock = TestSupport::ControlledClock.new(
          start_time: Time.utc(2026, 9, 1, 0, 0, 0)
        )
        callback_coordinator = RubyRouting::State::Coordinator.new(
          journal: RubyRouting::State::FileJournal.new(path),
          clock: clock
        )
        callback = callback_coordinator.apply_observation(observation_from_started(started))
        assert_equal :wait, callback.next_action
        assert_equal :dispatching, callback.payout.attempts.fetch(0).phase
        assert_equal started.fetch("operation_id"), callback.payout.ownership.operation_id
        assert_equal true,
          callback_coordinator.facts.reverse.find { |fact| fact.type == :provider_observed }.payload[:causal_hold]

        clock.advance(1)
        expired = callback_coordinator.prepare_and_commit_decision(
          intent: payout,
          policy: policy
        )
        assert_equal :reconciliation_blocked, expired.payout.status
        assert_equal :reconciliation_blocked, expired.payout.attempts.fetch(0).phase
        assert_equal started.fetch("operation_id"), expired.payout.ownership.operation_id

        stdin.puts("crash")
        stdin.close
        status = Timeout.timeout(3) { wait_thread.value }
        refute status.success?
      ensure
        Process.kill("KILL", wait_thread.pid) if wait_thread.alive?
        stdin.close unless stdin.closed?
        stdout.close unless stdout.closed?
        stderr.close unless stderr.closed?
      end

      output, error_output, status = Open3.capture3(RbConfig.ruby, resume, path, payout.id)
      assert status.success?, "fresh reconciliation resume failed: #{output}\n#{error_output}"
      result = JSON.parse(output)

      assert_equal "defer", result.fetch("action")
      assert_equal "reconciliation_blocked", result.fetch("status")
      assert_equal "A", result.fetch("ownership").fetch("provider_id")
      assert_equal started.fetch("operation_id"), result.fetch("ownership").fetch("operation_id")
      assert_empty result.fetch("calls")
      assert_equal ["A"], result.fetch("attempts").map { |attempt| attempt.fetch("provider_id") }
      assert_equal "reconciliation_blocked", result.fetch("attempts").fetch(0).fetch("phase")
      assert_equal 0, result.fetch("fact_counts").fetch("ownership_released", 0)
      assert_equal 1, result.fetch("fact_counts").fetch("reconciliation_blocked")
    end
  end

  private

  def build_coordinator(journal:, opportunities:, clock: nil)
    RubyRouting::State::Coordinator.new(
      journal: journal,
      opportunities: opportunities,
      clock: clock
    )
  end

  def recover(journal:, clock: nil)
    RubyRouting::State::Coordinator.new(journal: journal, clock: clock)
  end

  def opportunity(provider_id, status_lookup: false)
    RubyRouting::ProviderOpportunity.new(
      provider_id: provider_id,
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: status_lookup)
    )
  end

  def policy(id, targets: { "A" => 1 }, ttl_seconds: nil)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: targets,
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 2, ttl_seconds: ttl_seconds)
    )
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def observation(commit, status, attribution)
    RubyRouting::ProviderObservation.new(
      observation_id: "crash-campaign:#{commit.proposal.operation_id}:#{status}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(
        status: status,
        attribution: attribution,
        safe_to_release: status == :safe_route_failure
      )
    )
  end

  def campaign_trace(coordinator, boundary)
    payout = coordinator.payout_snapshot(coordinator.facts.last.payout_id)
    "seed=#{CRASH_SEED} boundary=#{boundary} status=#{payout.status} " \
      "owner=#{payout.ownership&.operation_id.inspect} attempts=#{payout.attempts.map(&:operation_id).inspect}"
  end

  def observation_from_started(started)
    RubyRouting::ProviderObservation.new(
      observation_id: "ptz6-independent-release",
      payout_id: started.fetch("payout_id"),
      provider_id: started.fetch("provider_id"),
      operation_id: started.fetch("operation_id"),
      attempt_id: started.fetch("attempt_id"),
      outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider),
      observed_at: Time.utc(2026, 9, 2, 0, 0, 0)
    )
  end

  def callback_coordinator_facts(coordinator, type)
    coordinator.facts.count { |fact| fact.type == type }
  end
end
