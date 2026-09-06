# frozen_string_literal: true

require_relative "../test_helper"

class AllocationOpportunityTest < Minitest::Test
  def test_provider_absent_from_opportunity_cohort_does_not_create_catch_up_debt
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("B")])
    policy = RubyRouting::RoutingPolicy.new(
      id: "skewed-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 9 }
    )

    2.times do |index|
      payout = intent("ineligible-#{index}")
      commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      assert_equal "B", commit.proposal.provider_id
      coordinator.mark_attempt_started(commit)
      coordinator.apply_observation(observation(commit, index))
    end

    coordinator.replace_provider_opportunities([opportunity("A"), opportunity("B")])
    next_commit = coordinator.prepare_and_commit_decision(intent: intent("eligible-again"), policy: policy)

    assert_equal "B", next_commit.proposal.provider_id
    assert_equal ["A", "B"], coordinator.provider_opportunities.map(&:provider_id)
  end

  def test_no_safe_route_is_visible_when_all_opportunities_are_unavailable
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A", available: false),
        RubyRouting::ProviderOpportunity.new(provider_id: "B", capacity_available: false)
      ]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "outage-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )

    commit = coordinator.prepare_and_commit_decision(intent: intent("runtime-infeasible"), policy: policy)

    assert_equal :defer, commit.proposal.action
    assert_includes commit.proposal.reasons, "no safe feasible provider"
    assert_empty coordinator.payout_snapshot("runtime-infeasible").attempts
  end

  def test_policy_epoch_has_an_independent_allocation_projection
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A"), opportunity("B")])
    first_policy = policy(epoch: "1")
    second_policy = policy(epoch: "2")

    first = coordinator.prepare_and_commit_decision(intent: intent("epoch-1"), policy: first_policy)
    second = coordinator.prepare_and_commit_decision(intent: intent("epoch-2"), policy: second_policy)

    assert_equal "A", first.proposal.provider_id
    assert_equal "A", second.proposal.provider_id
    assert_equal({ "A" => 1 }, coordinator.allocation_snapshot(policy: first_policy).measures)
    assert_equal({ "A" => 1 }, coordinator.allocation_snapshot(policy: second_policy).measures)
    epochs = coordinator.facts.select { |fact| fact.type == :allocation_committed }.map { |fact| fact.payload[:policy_epoch] }
    assert_equal %w[1 2], epochs
  end

  def test_fallback_recomputes_against_current_provider_availability
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [opportunity("A"), opportunity("B"), opportunity("C")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "fallback-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1, "C" => 1 }
    )
    payout = intent("fresh-fallback")
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "fallback-safe-failure",
        payout_id: payout.id,
        provider_id: first.proposal.provider_id,
        operation_id: first.proposal.operation_id,
        attempt_id: first.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    coordinator.set_provider_availability("A", available: false)
    coordinator.set_provider_availability("B", available: false)

    second = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

    assert_equal "C", second.proposal.provider_id
  end

  private

  def opportunity(id)
    RubyRouting::ProviderOpportunity.new(provider_id: id)
  end

  def policy(epoch:)
    RubyRouting::RoutingPolicy.new(
      id: "epoch-policy",
      epoch: epoch,
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def observation(commit, index)
    RubyRouting::ProviderObservation.new(
      observation_id: "opportunity-observation-#{index}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
    )
  end
end
