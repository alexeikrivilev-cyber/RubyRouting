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

  def test_policy_measure_limit_is_a_typed_allocation_exclusion
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A")])
    policy = RubyRouting::RoutingPolicy.new(
      id: "measure-limit-policy",
      epoch: "1",
      measure: :volume,
      targets: { "A" => 1 },
      currency: "RUB",
      minimums: { "A" => 200 }
    )
    payout = RubyRouting::PayoutIntent.new(
      id: "measure-limit-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )

    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)

    assert_equal :defer, commit.proposal.action
    assert_includes commit.proposal.reason_codes, :policy_measure_constraint
    assert_equal({ "A" => :policy_measure_constraint }, evaluation.payload.fetch(:allocation_exclusions))
    assert_equal 1, analytics.exclusion_count_by_code.fetch(:policy_measure_constraint)
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

  def test_same_policy_identity_cannot_be_reused_with_changed_definition
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A")])
    first_policy = RubyRouting::RoutingPolicy.new(
      id: "immutable-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    changed_policy = RubyRouting::RoutingPolicy.new(
      id: "immutable-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 2 }
    )

    coordinator.prepare_and_commit_decision(intent: intent("policy-one"), policy: first_policy)

    assert_raises(ArgumentError) do
      coordinator.prepare_and_commit_decision(intent: intent("policy-two"), policy: changed_policy)
    end
  end

  def test_unresolved_payout_cannot_silently_switch_policy_identity
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A")])
    first_policy = policy(epoch: "1")
    changed_epoch = policy(epoch: "2")
    payout = intent("pinned-policy")

    coordinator.prepare_and_commit_decision(intent: payout, policy: first_policy)

    assert_raises(ArgumentError) do
      coordinator.prepare_and_commit_decision(intent: payout, policy: changed_epoch)
    end
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

  def test_skewed_fallback_excludes_provider_used_by_previous_money_moving_operation
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [opportunity("A"), opportunity("B")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "skewed-fallback-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 9, "B" => 1 }
    )
    payout = intent("exclude-used-provider")
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assert_equal "A", first.proposal.provider_id
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "exclude-used-provider-failure",
        payout_id: payout.id,
        provider_id: first.proposal.provider_id,
        operation_id: first.proposal.operation_id,
        attempt_id: first.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )

    second = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

    assert_equal "B", second.proposal.provider_id
    assert_equal :recovery, second.proposal.role
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
