# frozen_string_literal: true

require_relative "../test_helper"

class CrossFeatureHardeningTest < Minitest::Test
  def test_capacity_outage_quarantine_and_allocation_pressure_compose_safely
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 1
      ),
      opportunities: [
        opportunity("A", capacity: RubyRouting::CapacityBudget.new(max_slots: 1)),
        opportunity("B", capacity: RubyRouting::CapacityBudget.new(max_slots: 1)),
        opportunity("C")
      ]
    )
    policy = policy_for("pressure", targets: { "A" => 1, "B" => 1, "C" => 1 })

    first = coordinator.prepare_and_commit_decision(intent: intent("pressure-1"), policy: policy)
    second = coordinator.prepare_and_commit_decision(intent: intent("pressure-2"), policy: policy)
    assert_equal "A", first.proposal.provider_id
    assert_equal "B", second.proposal.provider_id

    coordinator.set_provider_availability("B", available: false)
    third = coordinator.prepare_and_commit_decision(intent: intent("pressure-3"), policy: policy)
    assert_equal "C", third.proposal.provider_id

    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, "safe", :safe_route_failure))
    assert_equal :quarantined, coordinator.health_snapshot("A").state

    coordinator.set_provider_availability("C", available: false)
    no_route = coordinator.prepare_and_commit_decision(intent: intent("pressure-4"), policy: policy)

    assert_equal :defer, no_route.proposal.action
    assert_includes no_route.proposal.reason_codes, :no_safe_route
    assert_equal 0, coordinator.capacity_snapshot("A").used_slots
    assert_equal 1, coordinator.capacity_snapshot("B").used_slots
    assert_equal 0, coordinator.capacity_snapshot("C").used_slots
    assert_equal({ "A" => 1, "B" => 1, "C" => 1 },
      coordinator.allocation_snapshot(policy: policy).measures)
    live_allocation = coordinator.allocation_snapshot(policy: policy)
    replayed_allocation = coordinator.allocation_projection.snapshot(policy)
    assert_equal [live_allocation.measures, live_allocation.revision],
      [replayed_allocation.measures, replayed_allocation.revision]

    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    assert_equal 1, analytics.no_safe_route_count
    assert_equal 2, analytics.capacity_exclusion_count_by_provider.fetch("A")
    assert_equal 1, analytics.health_exclusion_count_by_provider.fetch("A")
    assert_equal coordinator.capacity_projection.to_h,
      RubyRouting::Projections::Replay.capacity(coordinator.facts).to_h
  end

  def test_unknown_duplicate_and_ttl_boundary_never_release_ownership
    clock = TestSupport::ControlledClock.new
    capability = RubyRouting::ProviderCapabilities.new(status_lookup: true, ttl_seconds: 5)
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        opportunity("A", capacity: RubyRouting::CapacityBudget.new(max_slots: 1), capabilities: capability)
      ]
    )
    policy = policy_for("unknown-ttl", targets: { "A" => 1 })
    payout = intent("unknown-ttl")

    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(first)
    unknown = coordinator.apply_observation(observation(first, "unknown", :unknown))
    duplicate_command = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

    assert_equal :unknown, unknown.payout.status
    assert_equal :resolve, duplicate_command.proposal.action
    assert_equal 1, duplicate_command.payout.attempt_count
    assert_equal "A", duplicate_command.payout.ownership.provider_id
    assert_equal 1, coordinator.capacity_snapshot("A").used_slots

    clock.advance(5)
    expired = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

    assert_equal :defer, expired.proposal.action
    assert_includes expired.proposal.reason_codes, :reconciliation_blocked
    assert_equal :reconciliation_blocked, expired.payout.status
    assert_equal "A", expired.payout.ownership.provider_id
    assert_equal 1, coordinator.capacity_snapshot("A").used_slots

    resolved = coordinator.apply_observation(observation(first, "resolved", :success))
    assert_equal :success, resolved.payout.status
    assert_nil resolved.payout.ownership
    assert_equal 0, coordinator.capacity_snapshot("A").used_slots
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :capacity_released }
  end

  def test_policy_fingerprint_registration_is_atomic_under_concurrent_decisions
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A"), opportunity("B")])
    policy_a = policy_for("policy-race", targets: { "A" => 1, "B" => 1 })
    policy_b = policy_for("policy-race", targets: { "A" => 1 })
    payouts = [intent("policy-race-a"), intent("policy-race-b")]
    policies = [policy_a, policy_b]
    barrier = TestSupport::Synchronization::Barrier.new(2)
    results = Array.new(2)
    errors = []
    error_mutex = Thread::Mutex.new

    threads = payouts.each_with_index.map do |payout, index|
      Thread.new do
        barrier.wait
        results[index] = coordinator.prepare_and_commit_decision(intent: payout, policy: policies[index])
      rescue StandardError => error
        error_mutex.synchronize { errors << error }
      end
    end
    threads.each(&:join)

    assert_equal 1, results.compact.length
    assert_equal 1, errors.length
    assert_instance_of ArgumentError, errors.first
    assert_equal 1, coordinator.active_unresolved_owners
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :policy_registered }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :allocation_committed }
  end

  def test_late_success_after_fallback_does_not_leak_capacity_or_settlement
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        opportunity("A", capacity: RubyRouting::CapacityBudget.new(max_slots: 1)),
        opportunity("B", capacity: RubyRouting::CapacityBudget.new(max_slots: 1))
      ]
    )
    policy = policy_for("late-capacity", targets: { "A" => 1, "B" => 1 })
    payout = intent("late-capacity")

    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, "safe", :safe_route_failure))
    second = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(second)
    coordinator.apply_observation(observation(second, "success", :success))

    conflict = coordinator.apply_observation(observation(first, "late-success", :success))
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)

    assert conflict.conflict
    assert_equal :success, conflict.payout.status
    assert_equal({ "B" => 1 }, analytics.settlement_measure_by_provider)
    assert_equal 1, analytics.economic_conflict_count
    assert_equal 0, coordinator.capacity_snapshot("A").used_slots
    assert_equal 0, coordinator.capacity_snapshot("B").used_slots
    assert_equal coordinator.capacity_projection.to_h,
      RubyRouting::Projections::Replay.capacity(coordinator.facts).to_h
  end

  def test_reversal_replay_and_analytics_preserve_settlement_separation
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A")])
    policy = policy_for("reversal-analytics", targets: { "A" => 1 })
    payout = intent("reversal-analytics")
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, "success", :success))

    coordinator.record_reversal(
      payout_id: " #{payout.id} ",
      reversal_id: "return-analytics",
      provider_id: " A ",
      operation_id: " #{first.proposal.operation_id} ",
      amount: payout.money
    )

    live = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    replay = RubyRouting::Projections::Replay.analytics(coordinator.facts)
    lifecycle = RubyRouting::Projections::Replay.lifecycle(coordinator.facts)

    assert_equal :reversed, coordinator.payout_snapshot(payout.id).status
    assert_equal({ "A" => 1 }, live.settlement_measure_by_provider)
    assert_equal({ "RUB" => 100 }, live.reversal_measure_by_currency)
    assert_equal 1, live.reversal_count
    assert_equal live.to_h, replay.to_h
    assert_equal :reversed, lifecycle.payout(payout.id).status
    assert_equal 1, lifecycle.payout(payout.id).reversals.length

    repeated = coordinator.record_reversal(
      payout_id: " #{payout.id} ",
      reversal_id: " return-analytics ",
      provider_id: "A",
      operation_id: first.proposal.operation_id,
      amount: payout.money
    )
    assert_equal 1, repeated.reversals.length
  end

  def test_reversal_canonicalizes_provider_and_operation_identity_before_linkage
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A")])
    policy = policy_for("reversal-identity", targets: { "A" => 1 })
    payout = intent("reversal-identity")
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, "success", :success))

    recorded = coordinator.record_reversal(
      payout_id: payout.id,
      reversal_id: "return-identity",
      provider_id: " A ",
      operation_id: " #{first.proposal.operation_id} ",
      amount: payout.money
    )

    assert_equal "A", recorded.reversals.first.provider_id
    assert_equal first.proposal.operation_id, recorded.reversals.first.operation_id
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :reversal_recorded }
    reversal_fact = coordinator.facts.find { |fact| fact.type == :reversal_recorded }
    assert_equal "A", reversal_fact.payload.fetch(:provider_id)
    assert_equal first.proposal.operation_id, reversal_fact.payload.fetch(:operation_id)

    repeated = coordinator.record_reversal(
      payout_id: payout.id,
      reversal_id: " return-identity ",
      provider_id: " A ",
      operation_id: " #{first.proposal.operation_id} ",
      amount: payout.money
    )
    assert_equal 1, repeated.reversals.length
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :reversal_recorded }
  end

  def test_health_recovery_probe_budget_and_allocation_deviation_remain_typed
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 2,
      probe_limit: 1
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [opportunity("A"), opportunity("B")]
    )
    policy = policy_for("health-deviation", targets: { "A" => 9, "B" => 1 })

    coordinator.record_health_signal(provider_id: "A", signal: :provider_failure, attribution: :provider)
    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)
    first = coordinator.prepare_and_commit_decision(intent: intent("health-deviation-1"), policy: policy)
    second = coordinator.prepare_and_commit_decision(intent: intent("health-deviation-2"), policy: policy)

    assert first.proposal.assignment?
    assert second.proposal.assignment?
    assert_equal "B", second.proposal.provider_id
    assert_equal 1, coordinator.health_snapshot("A").probe_in_flight

    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, "probe-success", :success))
    assert_equal :healthy, coordinator.health_snapshot("A").state
    assert_equal 0, coordinator.health_snapshot("A").probe_in_flight

    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    assert_equal coordinator.health_projection.to_h, %w[A B].to_h { |id| [id, coordinator.health_snapshot(id).to_h] }
    assert_equal 1, analytics.deviation_by_cause.fetch(:optimizer_choice).fetch(:count)
    assert_equal 1, analytics.deviation_by_cause.fetch(:health_quarantine).fetch(:count)
    assert_equal 2, analytics.deviation_by_recoverability.fetch(:recoverable).fetch(:count)
    assert_equal({ "A" => 1, "B" => 1 }, analytics.primary_assignment_measure_by_provider)
  end

  def test_provider_capacity_and_health_configuration_replay_without_a_payout
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 2,
      recover_after: 2,
      probe_limit: 1
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [opportunity("A", capacity: RubyRouting::CapacityBudget.new(max_slots: 1))]
    )

    coordinator.replace_provider_opportunities([
      opportunity("A", capacity: RubyRouting::CapacityBudget.new(max_slots: 2))
    ])

    assert_equal coordinator.capacity_snapshot("A").budget.to_h,
      RubyRouting::Projections::Replay.capacity(coordinator.facts).snapshot("A").budget.to_h
    assert_equal coordinator.capacity_projection.to_h,
      RubyRouting::Projections::Replay.capacity(coordinator.facts).to_h
    coordinator.health_snapshot("A")
    assert_equal coordinator.health_projection.to_h,
      %w[A].to_h { |id| [id, coordinator.health_snapshot(id).to_h] }
  end

  def test_capacity_replay_reflects_removing_a_previous_budget
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [opportunity("A", capacity: RubyRouting::CapacityBudget.new(max_slots: 1))]
    )

    coordinator.replace_provider_opportunities([opportunity("A")])

    live = coordinator.capacity_projection.to_h
    replay = RubyRouting::Projections::Replay.capacity(coordinator.facts).to_h
    assert_equal live, replay
    assert_nil replay.fetch("A").fetch(:budget)
    assert_equal 0, replay.fetch("A").fetch(:used_slots)
  end

  def test_remediation_of_conflicted_operation_via_reversal_fact
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [opportunity("A"), opportunity("B")]
    )
    policy = policy_for("remediation", targets: { "A" => 1, "B" => 1 })
    payout_intent = intent("remediation-1")

    first = coordinator.prepare_and_commit_decision(intent: payout_intent, policy: policy)
    coordinator.mark_attempt_started(first)
    # A safe-fails and ownership is released
    coordinator.apply_observation(observation(first, "safe-fail", :safe_route_failure))

    # B fallback is assigned and succeeds
    second = coordinator.prepare_and_commit_decision(intent: payout_intent, policy: policy)
    coordinator.mark_attempt_started(second)
    coordinator.apply_observation(observation(second, "success", :success))

    assert_equal :success, coordinator.payout_snapshot("remediation-1").status
    assert_equal "B", coordinator.payout_snapshot("remediation-1").settlement_provider_id

    # Late success arrives from A, creating an economic conflict
    conflict_obs = RubyRouting::ProviderObservation.new(
      observation_id: "remediation:late-A-success",
      payout_id: payout_intent.id,
      provider_id: "A",
      operation_id: first.proposal.operation_id,
      attempt_id: first.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
    )
    coordinator.apply_observation(conflict_obs)

    assert_equal 1, coordinator.payout_snapshot("remediation-1").conflicts.length
    assert_equal "A", coordinator.payout_snapshot("remediation-1").conflicts.first.provider_id

    # Remediate the conflict on operation 1 via record_reversal
    reversal_snapshot = coordinator.record_reversal(
      payout_id: payout_intent.id,
      reversal_id: "rev:A:1",
      provider_id: " A ",
      operation_id: " #{first.proposal.operation_id} ",
      amount: payout_intent.money,
      reason: :returned
    )

    assert_equal :reversed, reversal_snapshot.status
    assert_equal 1, reversal_snapshot.reversals.length
    assert_equal "rev:A:1", reversal_snapshot.reversals.first.reversal_id
    assert_equal "A", reversal_snapshot.reversals.first.provider_id

    # Replay must match
    replayed = RubyRouting::Projections::Replay.lifecycle(coordinator.facts).payout("remediation-1")
    assert_equal :reversed, replayed.status
    assert_equal 1, replayed.reversals.length
  end

  def test_orchestrator_multi_currency_routing_via_policy_registry
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        opportunity("A-RUB"),
        opportunity("B-USD")
      ]
    )
    rub_policy = RubyRouting::RoutingPolicy.new(
      id: "rub-volume",
      epoch: "1",
      measure: :volume,
      targets: { "A-RUB" => 1 },
      currency: "RUB"
    )
    usd_policy = RubyRouting::RoutingPolicy.new(
      id: "usd-volume",
      epoch: "1",
      measure: :volume,
      targets: { "B-USD" => 1 },
      currency: "USD"
    )
    registry = RubyRouting::PolicyRegistry.new([rub_policy, usd_policy])

    scripted_a = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A-RUB",
      steps: [TestSupport::Simulator::Step.success]
    )
    scripted_b = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "B-USD",
      steps: [TestSupport::Simulator::Step.success]
    )
    orchestrator = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A-RUB" => scripted_a, "B-USD" => scripted_b },
      policy_registry: registry
    )

    rub_payout = RubyRouting::PayoutIntent.new(id: "multi-rub", money: RubyRouting::Money.new(1000, "RUB"))
    usd_payout = RubyRouting::PayoutIntent.new(id: "multi-usd", money: RubyRouting::Money.new(500, "USD"))

    res_rub = orchestrator.submit(intent: rub_payout)
    res_usd = orchestrator.submit(intent: usd_payout)

    assert_equal :success, res_rub.status
    assert_equal "A-RUB", res_rub.payout.settlement_provider_id

    assert_equal :success, res_usd.status
    assert_equal "B-USD", res_usd.payout.settlement_provider_id
  end

  private

  def opportunity(provider_id, capacity: nil, capabilities: RubyRouting::ProviderCapabilities.new)
    RubyRouting::ProviderOpportunity.new(
      provider_id: provider_id,
      capacity: capacity,
      capabilities: capabilities
    )
  end

  def policy_for(id, targets:)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: targets,
      tolerance: 0
    )
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def observation(commit, label, status)
    RubyRouting::ProviderObservation.new(
      observation_id: "cross-feature:#{label}:#{commit.proposal.operation_id}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(status: status, attribution: :provider)
    )
  end
end
