# frozen_string_literal: true

require_relative "../test_helper"

class HealthRankingTest < Minitest::Test
  def test_health_uses_hysteresis_and_recipient_failure_is_neutral
    controller = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 2,
        quarantine_after: 3,
        recover_after: 2
      )
    )

    controller.observe(provider_id: "A", signal: :recipient_failure, attribution: :recipient)
    assert_equal :healthy, controller.snapshot("A").state
    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :provider)
    assert_equal :healthy, controller.snapshot("A").state
    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :provider)
    assert_equal :degraded, controller.snapshot("A").state
    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :provider)
    assert_equal :quarantined, controller.snapshot("A").state
    controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)
    assert_equal :probing, controller.snapshot("A").state
    controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)
    assert_equal :healthy, controller.snapshot("A").state
  end

  def test_snapshot_of_unknown_provider_does_not_create_hidden_health_state
    controller = RubyRouting::Routing::HealthController.new

    assert_equal :healthy, controller.snapshot("A").state
    assert_empty controller.provider_ids
  end

  def test_static_health_exclusion_cannot_be_overridden_by_default_controller_state
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A", health_available: false),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "static-health",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )

    commit = coordinator.prepare_and_commit_decision(intent: intent("static-health"), policy: policy)
    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }

    assert_equal "B", commit.proposal.provider_id
    assert_equal :quarantined, evaluation.payload.fetch(:exclusion_codes).fetch("A")
  end

  def test_unknown_or_downstream_health_attribution_is_neutral
    controller = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(degrade_after: 1, quarantine_after: 1)
    )

    controller.observe(provider_id: "A", signal: :provider_failure)
    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :downstream)

    assert_equal :healthy, controller.snapshot("A").state
    assert_equal 0, controller.snapshot("A").operational_failure_count
  end

  def test_provider_health_ids_use_the_same_canonical_form_as_opportunities
    controller = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(degrade_after: 1, quarantine_after: 1)
    )

    controller.observe(provider_id: " A ", signal: :provider_failure, attribution: :provider)

    assert_equal :quarantined, controller.snapshot("A").state
    assert_equal ["A"], controller.provider_ids
  end

  def test_probing_exposure_is_bounded_until_probe_observation_arrives
    controller = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 2,
        probe_limit: 1
      )
    )

    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :provider)
    controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)
    assert_equal :probing, controller.snapshot("A").state
    assert controller.reserve_exposure("A")
    refute controller.reserve_exposure("A")
    refute controller.snapshot("A").exposed?

    controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)
    assert_equal :healthy, controller.snapshot("A").state
    assert_equal 0, controller.snapshot("A").probe_in_flight
  end

  def test_coordinator_persists_probe_reservation_and_blocks_second_probe
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 2,
      probe_limit: 1
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "probe-coordinator",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    coordinator.record_health_signal(provider_id: "A", signal: :provider_failure, attribution: :provider)
    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)

    first = coordinator.prepare_and_commit_decision(intent: intent("probe-first"), policy: policy)
    second = coordinator.prepare_and_commit_decision(intent: intent("probe-second"), policy: policy)

    assert first.proposal.assignment?
    assert_equal :probing, coordinator.health_snapshot("A").state
    assert_equal 1, coordinator.health_snapshot("A").probe_in_flight
    assert_equal :defer, second.proposal.action
    assert_equal :quarantined, second.proposal.reason_codes.last
    assert_equal coordinator.health_projection.snapshot("A").to_h,
      coordinator.health_snapshot("A").to_h
  end

  def test_probe_release_is_owned_by_the_operation_that_reserved_it
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 1,
      probe_limit: 2
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "probe-ownership",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )

    first = coordinator.prepare_and_commit_decision(intent: intent("probe-owner-before-state"), policy: policy)
    coordinator.record_health_signal(provider_id: "A", signal: :provider_failure, attribution: :provider)
    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)

    second = coordinator.prepare_and_commit_decision(intent: intent("probe-owner-one"), policy: policy)
    assert_equal 1, coordinator.health_snapshot("A").probe_in_flight

    coordinator.apply_observation(observation(first, :terminal_payout_failure, attribution: :recipient))
    assert_equal 1, coordinator.health_snapshot("A").probe_in_flight

    third = coordinator.prepare_and_commit_decision(intent: intent("probe-owner-two"), policy: policy)
    assert third.proposal.assignment?
    assert_equal 2, coordinator.health_snapshot("A").probe_in_flight

    fourth = coordinator.prepare_and_commit_decision(intent: intent("probe-owner-three"), policy: policy)
    assert_equal :defer, fourth.proposal.action
    assert_equal :quarantined, fourth.proposal.reason_codes.last
    assert_equal second.proposal.provider_id, third.proposal.provider_id
  end

  def test_multiple_probe_reservations_are_released_once_by_their_own_operations
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 4,
      probe_limit: 2
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "probe-double-release",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )

    coordinator.record_health_signal(provider_id: "A", signal: :provider_failure, attribution: :provider)
    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)
    first = coordinator.prepare_and_commit_decision(intent: intent("probe-double-release-1"), policy: policy)
    second = coordinator.prepare_and_commit_decision(intent: intent("probe-double-release-2"), policy: policy)
    assert second.proposal.assignment?
    assert_equal 2, coordinator.health_snapshot("A").probe_in_flight

    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)
    assert_equal 2, coordinator.health_snapshot("A").probe_in_flight

    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, :success))
    assert_equal 1, coordinator.health_snapshot("A").probe_in_flight

    third = coordinator.prepare_and_commit_decision(intent: intent("probe-double-release-3"), policy: policy)
    fourth = coordinator.prepare_and_commit_decision(intent: intent("probe-double-release-4"), policy: policy)

    assert third.proposal.assignment?
    assert_equal 2, coordinator.health_snapshot("A").probe_in_flight
    assert_equal :defer, fourth.proposal.action
    assert_equal :quarantined, fourth.proposal.reason_codes.last
    assert_equal coordinator.health_projection.snapshot("A").to_h,
      coordinator.health_snapshot("A").to_h
  end

  def test_quarantine_is_hard_exclusion_and_does_not_reset_allocation_history
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A"),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ],
      health_policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 1
      )
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "health-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      tolerance: 0
    )

    first = coordinator.prepare_and_commit_decision(intent: intent("health-first"), policy: policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, :safe_route_failure))
    assert_equal :quarantined, coordinator.health_snapshot("A").state

    second = coordinator.prepare_and_commit_decision(intent: intent("health-second"), policy: policy)

    assert_equal "B", second.proposal.provider_id
    assert_equal :health_quarantine, second.proposal.allocation_decision.deviation_cause
    assert_equal({ "A" => 1, "B" => 1 }, coordinator.allocation_snapshot(policy: policy).measures)
    assert_equal :quarantined, coordinator.health_snapshot("A").state
    live_health = %w[A B].to_h { |provider_id| [provider_id, coordinator.health_snapshot(provider_id).to_h] }
    assert_equal live_health, coordinator.health_projection.to_h
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    assert_equal({ "A" => 1 }, analytics.health_exclusion_count_by_provider)
    assert_equal 1, analytics.exclusion_count_by_code.fetch(:quarantined)
    assert_equal({ optimizer_choice: { count: 1, measure: 1 } }, analytics.deviation_by_cause)
  end

  def test_ranking_breaks_only_allocation_ties_inside_feasible_set
    policy = RubyRouting::RoutingPolicy.new(
      id: "ranked",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      ranking: RubyRouting::RankingPolicy.new(priority_by_provider: { "B" => 10, "A" => 1 })
    )

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )

    assert_equal "B", decision.chosen_provider
  end

  private

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def observation(commit, status, attribution: :provider)
    RubyRouting::ProviderObservation.new(
      observation_id: "health:#{commit.proposal.operation_id}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(status: status, attribution: attribution)
    )
  end
end
