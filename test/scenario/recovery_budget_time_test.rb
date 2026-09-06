# frozen_string_literal: true

require_relative "../test_helper"

class RecoveryBudgetTimeTest < Minitest::Test
  def test_switch_budget_is_separate_from_money_moving_operation_budget
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities("A", "B"))
    policy = RubyRouting::RoutingPolicy.new(
      id: "switch-budget",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 3,
        max_switches: 0,
        max_resolution_interactions: 3
      )
    )
    payout = intent("switch-budget")
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, :safe_route_failure))

    second = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

    assert_equal :defer, second.proposal.action
    assert_includes second.proposal.reason_codes, :switch_budget_exhausted
    assert_equal 1, second.payout.attempt_count
  end

  def test_expired_operation_becomes_reconciliation_blocked_but_observation_can_resolve_it
    clock = TestSupport::ControlledClock.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, ttl_seconds: 10)
        )
      ]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "ttl-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 2,
        max_switches: 1,
        max_resolution_interactions: 2
      )
    )
    payout = intent("ttl-payout")
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, :unknown))
    clock.advance(10)

    blocked = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

    assert_equal :defer, blocked.proposal.action
    assert_includes blocked.proposal.reason_codes, :reconciliation_blocked
    assert_equal :reconciliation_blocked, blocked.payout.status
    assert_equal "A", blocked.payout.ownership.provider_id

    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    assert_equal({ reconciliation_blocked: 1 }, analytics.unresolved_count_by_status)
    assert_equal({ "ttl-payout" => 10 }, analytics.unresolved_age_seconds_by_payout)

    resolved = coordinator.apply_observation(observation(first, :success))
    assert_equal :success, resolved.payout.status
    assert_nil resolved.payout.ownership
  end

  def test_conflicting_policy_cannot_expire_old_operation_before_identity_validation
    clock = TestSupport::ControlledClock.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    original = RubyRouting::RoutingPolicy.new(
      id: "deadline-conflict",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 2,
        max_switches: 1,
        max_resolution_interactions: 1,
        deadline_seconds: 100
      )
    )
    conflicting = RubyRouting::RoutingPolicy.new(
      id: "deadline-conflict",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 2,
        max_switches: 1,
        max_resolution_interactions: 1,
        deadline_seconds: 1
      )
    )
    payout = intent("deadline-conflict")
    coordinator.prepare_and_commit_decision(intent: payout, policy: original)
    clock.advance(2)

    assert_raises(ArgumentError) do
      coordinator.prepare_and_commit_decision(intent: payout, policy: conflicting)
    end

    snapshot = coordinator.payout_snapshot(payout.id)
    assert_equal :pending, snapshot.status
    assert_equal :committed, snapshot.current_operation_phase
    assert_equal 100, snapshot.current_operation_contract.deadline_seconds
    refute coordinator.facts.any? { |fact| fact.type == :reconciliation_blocked }
  end

  def test_invalid_policy_command_does_not_mutate_expiry_state
    clock = TestSupport::ControlledClock.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    original = RubyRouting::RoutingPolicy.new(
      id: "atomic-policy-validation",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 2,
        max_switches: 1,
        max_resolution_interactions: 1,
        deadline_seconds: 1
      )
    )
    conflicting = RubyRouting::RoutingPolicy.new(
      id: "atomic-policy-validation",
      epoch: "1",
      measure: :count,
      targets: { "A" => 2 },
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 2,
        max_switches: 1,
        max_resolution_interactions: 1,
        deadline_seconds: 1
      )
    )
    payout = intent("atomic-policy-validation")
    coordinator.prepare_and_commit_decision(intent: payout, policy: original)
    clock.advance(2)

    assert_raises(ArgumentError) do
      coordinator.prepare_and_commit_decision(intent: payout, policy: conflicting)
    end

    snapshot = coordinator.payout_snapshot(payout.id)
    assert_equal :pending, snapshot.status
    assert_equal :committed, snapshot.current_operation_phase
    assert_equal 1, snapshot.current_operation_contract.deadline_seconds
    refute coordinator.facts.any? { |fact| fact.type == :reconciliation_blocked }
  end

  def test_invalid_volume_currency_does_not_pin_policy_or_register_intent
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    payout = intent("invalid-volume-currency")
    policy = RubyRouting::RoutingPolicy.new(
      id: "invalid-volume-currency",
      epoch: "1",
      measure: :volume,
      targets: { "A" => 1 },
      currency: "USD"
    )

    assert_raises(ArgumentError) do
      coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    end

    refute coordinator.facts.any? { |fact| %i[intent_registered policy_registered allocation_committed].include?(fact.type) }
    assert_equal 0, coordinator.active_unresolved_owners
  end

  def test_conflicting_policy_for_new_payout_does_not_register_intent
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    original = policy_for("atomic-new-policy")
    conflicting = RubyRouting::RoutingPolicy.new(
      id: original.id,
      epoch: original.epoch,
      measure: :count,
      targets: { "A" => 2 }
    )
    coordinator.prepare_and_commit_decision(
      intent: intent("policy-seed"),
      policy: original
    )
    new_payout = intent("policy-conflict-new-payout")

    assert_raises(ArgumentError) do
      coordinator.prepare_and_commit_decision(intent: new_payout, policy: conflicting)
    end

    refute coordinator.facts.any? { |fact| fact.type == :intent_registered && fact.payout_id == new_payout.id }
    refute coordinator.facts.any? { |fact| fact.type == :policy_registered && fact.payout_id == new_payout.id }
  end

  def test_application_exposes_resume_and_reconcile_as_distinct_commands
    clock = TestSupport::ControlledClock.new
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [TestSupport::Simulator::Step.unknown, TestSupport::Simulator::Step.success],
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    app = RubyRouting::Application::Orchestrator.new(coordinator: coordinator, providers: { "A" => provider })
    payout = intent("resume-payout")
    first = app.submit(intent: payout, policy: policy_for("resume-policy"))
    resumed = app.resume(payout_id: payout.id, policy: policy_for("resume-policy"))

    assert_equal :unknown, first.status
    assert_equal :success, resumed.status
    assert_equal :success, app.reconcile(observation: observation_from_provider(coordinator, payout.id)).payout.status
  end

  private

  def opportunities(*ids)
    ids.map { |id| RubyRouting::ProviderOpportunity.new(provider_id: id) }
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def policy_for(id)
    RubyRouting::RoutingPolicy.new(id: id, epoch: "1", measure: :count, targets: { "A" => 1 })
  end

  def observation(commit, status)
    RubyRouting::ProviderObservation.new(
      observation_id: "recovery-time:#{commit.proposal.operation_id}:#{status}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(status: status, attribution: :provider)
    )
  end

  def observation_from_provider(coordinator, payout_id)
    snapshot = coordinator.payout_snapshot(payout_id)
    attempt = snapshot.attempts.first
    RubyRouting::ProviderObservation.new(
      observation_id: "recovery-time:manual:#{payout_id}",
      payout_id: payout_id,
      provider_id: attempt.provider_id,
      operation_id: attempt.operation_id,
      attempt_id: attempt.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
    )
  end
end
