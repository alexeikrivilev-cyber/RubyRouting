# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class RecoveryScheduleTest < Minitest::Test
  def test_policy_delay_is_exact_bounded_and_legacy_defaults_are_fingerprint_compatible
    legacy = RubyRouting::RecoveryPolicy.new(max_operations: 3)
    explicit_legacy = RubyRouting::RecoveryPolicy.new(
      max_operations: 3,
      initial_delay_seconds: 0,
      backoff_seconds: 0
    )
    capped = RubyRouting::RecoveryPolicy.new(
      max_operations: 3,
      initial_delay_seconds: 2,
      backoff_seconds: 3,
      max_delay_seconds: 5
    )

    assert_equal legacy.to_h, explicit_legacy.to_h
    assert_equal 2, capped.delay_for(interaction_index: 0)
    assert_equal 5, capped.delay_for(interaction_index: 1)
    assert_equal 5, capped.delay_for(interaction_index: 9)
    assert capped.frozen?

    base = RubyRouting::RoutingPolicy.new(
      id: "schedule-fingerprint",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    defaulted = RubyRouting::RoutingPolicy.new(
      id: "schedule-fingerprint",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: explicit_legacy
    )
    assert_equal base.fingerprint, defaulted.fingerprint
  end

  def test_early_resume_cannot_bypass_schedule_and_exact_due_boundary_allows_resolution
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
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    policy = policy_for(
      "scheduled-resume",
      initial_delay_seconds: 5,
      backoff_seconds: 0
    )
    payout = intent("scheduled-resume-payout")

    first = app.submit(intent: payout, policy: policy)
    schedule = first.payout.recovery_schedule
    assert_equal :wait, first.action
    assert_equal :resolve, schedule.action
    assert_equal clock.now + 5, schedule.next_action_at
    assert_equal 1, provider.calls.count { |call| call.first == :initiate }
    assert_empty coordinator.due_recovery_work(as_of: clock.now + 4)

    facts_before_early_resume = coordinator.facts.length
    early = app.resume(payout_id: payout.id, policy: policy)
    assert_equal :defer, early.action
    assert_equal :unknown, early.status
    assert_equal facts_before_early_resume, coordinator.facts.length
    assert_equal 0, provider.calls.count { |call| call.first == :resolve }

    due = coordinator.due_recovery_work(as_of: schedule.next_action_at)
    assert_equal [payout.id], due.map(&:payout_id)
    assert_equal [:resolve], due.map(&:action)

    clock.advance(5)
    resolved = app.resume(payout_id: payout.id, policy: policy)
    assert_equal :success, resolved.status
    assert_equal 1, provider.calls.count { |call| call.first == :resolve }
    assert_empty coordinator.due_recovery_work(as_of: clock.now)
  end

  def test_backoff_progression_and_repeated_early_resume_are_deterministic
    clock = TestSupport::ControlledClock.new
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      clock: clock,
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
      steps: [
        TestSupport::Simulator::Step.unknown,
        TestSupport::Simulator::Step.unknown,
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
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    policy = policy_for(
      "scheduled-backoff",
      initial_delay_seconds: 2,
      backoff_seconds: 3,
      max_delay_seconds: 5,
      max_resolution_interactions: 3
    )
    payout = intent("scheduled-backoff-payout")

    first = app.submit(intent: payout, policy: policy)
    assert_equal clock.now + 2, first.payout.next_action_at

    clock.advance(2)
    second = app.resume(payout_id: payout.id, policy: policy)
    assert_equal :unknown, second.status
    assert_equal clock.now + 5, second.payout.next_action_at
    assert_equal 1, provider.calls.count { |call| call.first == :resolve }

    two_early = app.resume(payout_id: payout.id, policy: policy)
    three_early = app.resume(payout_id: payout.id, policy: policy)
    assert_equal [:defer, :defer], [two_early.action, three_early.action]
    assert_equal 1, provider.calls.count { |call| call.first == :resolve }

    clock.advance(5)
    final = app.resume(payout_id: payout.id, policy: policy)
    assert_equal :success, final.status
    assert_equal 2, provider.calls.count { |call| call.first == :resolve }
  end

  def test_retry_same_schedule_uses_the_same_operation_after_due_time
    clock = TestSupport::ControlledClock.new
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      clock: clock,
      capabilities: RubyRouting::ProviderCapabilities.new(idempotent_retry: true),
      steps: [TestSupport::Simulator::Step.unknown, TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(idempotent_retry: true)
      )]
    )
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    policy = policy_for("scheduled-retry", initial_delay_seconds: 3)
    payout = intent("scheduled-retry-payout")

    first = app.submit(intent: payout, policy: policy)
    operation_id = first.payout.ownership.operation_id
    assert_equal :retry_same, first.payout.next_action

    clock.advance(3)
    retry_commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assert_equal :retry_same, retry_commit.proposal.action
    assert_equal operation_id, retry_commit.proposal.operation_id
    coordinator.mark_attempt_started(retry_commit)
    final = coordinator.apply_observation(observation(retry_commit, :success))

    assert_equal :success, final.payout.status
    assert_equal [operation_id], final.payout.attempts.map(&:operation_id)
    assert_nil final.payout.recovery_schedule
  end

  def test_ttl_expiry_precedes_delayed_recovery_and_reconciliation_is_due_immediately
    clock = TestSupport::ControlledClock.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, ttl_seconds: 3)
      )]
    )
    policy = policy_for("schedule-ttl", initial_delay_seconds: 10)
    payout = intent("schedule-ttl-payout")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation(commit, :unknown))
    assert_equal :unknown, coordinator.payout_snapshot(payout.id).status
    future_work = coordinator.due_recovery_work(as_of: clock.now + 3)
    assert_equal [:reconcile], future_work.map(&:action)
    assert_equal :operation_contract_expired, future_work.first.reason_code

    clock.advance(3)
    blocked = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assert_equal :reconciliation_blocked, blocked.payout.status
    assert_nil blocked.payout.recovery_schedule
    work = coordinator.due_recovery_work(as_of: clock.now)
    assert_equal [:reconcile], work.map(&:action)
    assert_nil work.first.due_at
  end

  def test_restart_and_replay_preserve_schedule_and_due_work
    Dir.mktmpdir("ruby-routing-schedule-restart") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      policy = policy_for("schedule-restart", initial_delay_seconds: 4)
      payout = intent("schedule-restart-payout")
      first = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        )]
      )
      commit = first.prepare_and_commit_decision(intent: payout, policy: policy)
      first.mark_attempt_started(commit)
      first.apply_observation(observation(commit, :unknown))
      expected = first.payout_snapshot(payout.id)

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      actual = recovered.payout_snapshot(payout.id)
      assert_equal expected.recovery_schedule.to_h, actual.recovery_schedule.to_h
      assert_equal expected.next_action_at, actual.next_action_at
      assert_equal expected.next_action_due?(as_of: clock.now), actual.next_action_due?(as_of: clock.now)
      assert_empty recovered.due_recovery_work(as_of: clock.now)
      assert_equal [payout.id], recovered.due_recovery_work(as_of: clock.now + 4).map(&:payout_id)

      replayed = RubyRouting::Projections::Replay.payout(recovered.facts, payout.id)
      assert_equal actual.recovery_schedule.to_h, replayed.recovery_schedule.to_h
      explanation = RubyRouting::Projections::DecisionExplanation.from_facts(
        recovered.facts,
        payout_id: payout.id
      )
      assert_equal :resolve, explanation.result.next_action
      assert_equal actual.next_action_at, explanation.result.next_action_at
    end
  end

  private

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def policy_for(id, initial_delay_seconds: 0, backoff_seconds: 0, max_delay_seconds: nil,
                 max_resolution_interactions: 2)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 3,
        max_switches: 2,
        max_resolution_interactions: max_resolution_interactions,
        initial_delay_seconds: initial_delay_seconds,
        backoff_seconds: backoff_seconds,
        max_delay_seconds: max_delay_seconds
      )
    )
  end

  def observation(commit, status)
    RubyRouting::ProviderObservation.new(
      observation_id: "schedule:#{commit.proposal.operation_id}:#{status}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(status: status, attribution: :provider)
    )
  end
end
