# frozen_string_literal: true

require_relative "../test_helper"

class AllocationTest < Minitest::Test
  def test_count_allocation_minimizes_prefix_discrepancy
    policy = count_policy("A" => 1, "B" => 1)
    snapshot = RubyRouting::Routing::AllocationSnapshot.empty
    selected = []

    8.times do
      decision = RubyRouting::Routing::Allocation.choose(
        policy: policy,
        candidates: %w[A B],
        snapshot: snapshot,
        incoming_measure: 1
      )
      selected << decision.chosen_provider
      snapshot = snapshot.with_commit(decision.chosen_provider, 1)
    end

    assert_equal %w[A B A B A B A B], selected
    assert_equal({ "A" => 4, "B" => 4 }, snapshot.measures)
  end

  def test_volume_allocation_uses_amount_not_request_count
    policy = volume_policy("A" => 1, "B" => 1)
    snapshot = RubyRouting::Routing::AllocationSnapshot.new(measures: { "A" => 70, "B" => 0 })

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: snapshot,
      incoming_measure: 30
    )

    assert_equal "B", decision.chosen_provider
    assert_equal Rational(40), decision.discrepancy
  end

  def test_large_indivisible_amount_chooses_least_bad_feasible_state
    policy = count_policy("A" => 3, "B" => 1)

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 100
    )

    assert_equal "A", decision.chosen_provider
    assert_equal Rational(50), decision.discrepancy
    assert_equal Rational(150), decision.candidate_discrepancies.fetch("B")
  end

  def test_only_positive_weight_candidates_are_selected
    policy = count_policy("A" => 1)

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )

    assert_equal "A", decision.chosen_provider
    assert_equal ["A"], decision.candidate_discrepancies.keys
  end

  def test_no_configured_feasible_candidate_is_explicit_no_route
    policy = count_policy("A" => 1)

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: ["B"],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )

    assert decision.no_route?
    assert_empty decision.candidate_discrepancies
  end

  def test_eligibility_precedes_allocation_and_retains_exclusion_reason
    result = RubyRouting::Routing::Eligibility.evaluate([
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B", available: false)
    ])

    assert_equal ["A"], result.feasible_provider_ids
    assert_equal :unavailable, result.exclusions.fetch("B")
  end

  private

  def count_policy(targets)
    RubyRouting::RoutingPolicy.new(id: "policy", epoch: "1", measure: :count, targets: targets)
  end

  def volume_policy(targets)
    RubyRouting::RoutingPolicy.new(
      id: "policy",
      epoch: "1",
      measure: :volume,
      targets: targets,
      currency: "RUB"
    )
  end
end
