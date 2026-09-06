# frozen_string_literal: true

require_relative "../test_helper"

class CapacityTest < Minitest::Test
  def test_slot_reservation_is_atomic_and_released_after_safe_failure
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capacity: RubyRouting::CapacityBudget.new(max_slots: 1)
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity])
    policy = policy_for("capacity")

    first = coordinator.prepare_and_commit_decision(intent: intent("capacity-1"), policy: policy)
    blocked = coordinator.prepare_and_commit_decision(intent: intent("capacity-2"), policy: policy)

    assert first.proposal.assignment?
    assert_equal :defer, blocked.proposal.action
    assert_includes blocked.proposal.reasons.join(" "), "capacity_exhausted"
    assert_equal 1, coordinator.capacity_snapshot("A").used_slots
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    assert_equal({ "A" => 1 }, analytics.capacity_exclusion_count_by_provider)
    assert_equal 1, analytics.exclusion_count_by_code.fetch(:capacity_exhausted)
    replayed = coordinator.capacity_projection.snapshot("A")
    live = coordinator.capacity_snapshot("A")
    assert_equal [live.used_slots, live.used_count, live.used_amount_minor],
      [replayed.used_slots, replayed.used_count, replayed.used_amount_minor]

    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, "release", :safe_route_failure))

    retried = coordinator.prepare_and_commit_decision(intent: intent("capacity-2"), policy: policy)
    assert retried.proposal.assignment?
    assert_equal 1, coordinator.capacity_snapshot("A").used_slots
  end

  def test_duplicate_observation_does_not_release_capacity_twice
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capacity: RubyRouting::CapacityBudget.new(max_count: 1, max_amount_minor: 100, currency: "RUB")
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity])
    policy = policy_for("capacity-duplicate")
    payout = intent("capacity-duplicate")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    success = observation(commit, "success", :success)

    coordinator.apply_observation(success)
    coordinator.apply_observation(success)

    snapshot = coordinator.capacity_snapshot("A")
    assert_equal 0, snapshot.used_slots
    assert_equal 0, snapshot.used_count
    assert_equal 0, snapshot.used_amount_minor
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :capacity_released }
  end

  def test_unconfigured_capacity_is_unbounded_in_read_projection
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )

    assert coordinator.capacity_snapshot("A").available_for?(intent("unbounded").money)
  end

  private

  def policy_for(id)
    RubyRouting::RoutingPolicy.new(id: id, epoch: "1", measure: :count, targets: { "A" => 1 })
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def observation(commit, label, status)
    RubyRouting::ProviderObservation.new(
      observation_id: "capacity:#{label}:#{commit.proposal.operation_id}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(status: status, attribution: :provider)
    )
  end
end
