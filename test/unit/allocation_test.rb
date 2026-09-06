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

  def test_volume_allocation_accepts_zero_amount_without_fractional_arithmetic
    policy = volume_policy("A" => 1, "B" => 1)

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 0
    )
    committed = RubyRouting::Routing::AllocationSnapshot.empty
      .with_commit(decision.chosen_provider, decision.incoming_measure)

    assert_equal "A", decision.chosen_provider
    assert_equal Rational(0), decision.discrepancy
    assert_equal({ "A" => 0 }, committed.measures)
    assert_equal 1, committed.revision
  end

  def test_deviation_uses_full_accounting_universe_when_live_set_is_reduced
    policy = count_policy("A" => 1, "B" => 1)

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: ["B"],
      accounting_provider_ids: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )

    assert_equal "B", decision.chosen_provider
    assert_equal Rational(1), decision.discrepancy
    assert_equal({ "A" => 0, "B" => 1 }, decision.post_measures.fetch("B"))
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

  def test_context_eligibility_is_distinct_from_live_availability
    intent = RubyRouting::PayoutIntent.new(
      id: "contextual",
      money: RubyRouting::Money.new(250, "RUB"),
      context: { labels: ["retail"] }
    )
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      supported_currencies: ["RUB"],
      minimum_amount_minor: 100,
      maximum_amount_minor: 500,
      required_context_labels: ["retail"],
      available: false
    )

    result = RubyRouting::Routing::Eligibility.evaluate([provider], intent: intent)

    assert_equal ["A"], result.opportunity_provider_ids
    assert_equal ["A"], result.functional_provider_ids
    assert_empty result.feasible_provider_ids
    assert_equal :unavailable, result.exclusions.fetch("A")
  end

  def test_context_mismatch_is_a_functional_exclusion
    intent = RubyRouting::PayoutIntent.new(
      id: "contextual-mismatch",
      money: RubyRouting::Money.new(250, "USD"),
      context: { labels: ["wholesale"] }
    )
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      supported_currencies: ["RUB"],
      required_context_labels: ["retail"]
    )

    result = RubyRouting::Routing::Eligibility.evaluate([provider], intent: intent)

    assert_empty result.functional_provider_ids
    assert_equal :functionally_ineligible, result.exclusions.fetch("A")
  end

  def test_hard_policy_constraint_is_evaluated_before_allocation
    intent = RubyRouting::PayoutIntent.new(
      id: "hard-policy",
      money: RubyRouting::Money.new(100, "RUB")
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "hard-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      hard_constraints: { excluded_provider_ids: ["A"] }
    )
    result = RubyRouting::Routing::Eligibility.evaluate(
      [RubyRouting::ProviderOpportunity.new(provider_id: "A"), RubyRouting::ProviderOpportunity.new(provider_id: "B")],
      intent: intent,
      policy: policy
    )

    assert_equal ["B"], result.feasible_provider_ids
    assert_equal :hard_policy_constraint, result.exclusion_codes.fetch("A")
  end

  def test_soft_policy_constraint_is_advisory_and_preserved_in_typed_trace
    intent = RubyRouting::PayoutIntent.new(
      id: "soft-policy",
      money: RubyRouting::Money.new(100, "RUB"),
      context: { labels: ["retail"] }
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "soft-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      soft_constraints: { required_context_labels: ["preferred"] }
    )
    result = RubyRouting::Routing::Eligibility.evaluate(
      [
        RubyRouting::ProviderOpportunity.new(provider_id: "A"),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ],
      intent: intent,
      policy: policy
    )

    assert_equal %w[A B], result.feasible_provider_ids
    assert_equal({ "A" => [:required_context_missing], "B" => [:required_context_missing] }, result.soft_violations)
  end

  def test_hard_context_constraint_treats_non_hash_context_as_missing_labels
    intent = RubyRouting::PayoutIntent.new(
      id: "non-hash-context",
      money: RubyRouting::Money.new(100, "RUB"),
      context: nil
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "non-hash-context",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      hard_constraints: { required_context_labels: ["retail"] }
    )

    result = RubyRouting::Routing::Eligibility.evaluate(
      [RubyRouting::ProviderOpportunity.new(provider_id: "A")],
      intent: intent,
      policy: policy
    )

    assert_empty result.functional_provider_ids
    assert_equal :hard_policy_constraint, result.exclusions.fetch("A")
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
