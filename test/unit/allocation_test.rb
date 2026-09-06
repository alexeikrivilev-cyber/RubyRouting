# frozen_string_literal: true

require_relative "../test_helper"

class AllocationTest < Minitest::Test
  def test_allocation_decision_canonicalizes_provider_maps_and_rejects_collisions
    decision = RubyRouting::Routing::AllocationDecision.new(
      chosen_provider: " A ",
      candidate_discrepancies: { " A " => Rational(1) },
      post_measures: { " A " => { " B " => 1 } },
      candidate_share_violations: { " A " => { " B " => { minimum: Rational(1, 2) } } },
      incoming_measure: 1,
      snapshot_revision: 0,
      tolerance: Rational(0),
      optimization_trace: { " A " => { selected: true } }
    )

    assert_equal "A", decision.chosen_provider
    assert_equal Rational(1), decision.discrepancy
    assert_equal({ "B" => 1 }, decision.post_measures.fetch("A"))
    assert_equal({ "B" => { minimum: Rational(1, 2) } }, decision.share_violations)
    assert_equal decision.allocation_key_for("A"), decision.allocation_key_for(" A ")
    assert_equal true, decision.candidate_deviation_exceeded?(" A ")
    assert_equal({ "A" => { selected: true } }, decision.optimization_trace)

    assert_raises(ArgumentError) do
      RubyRouting::Routing::AllocationDecision.new(
        chosen_provider: nil,
        candidate_discrepancies: { "A" => Rational(1), " A " => Rational(2) },
        post_measures: {},
        incoming_measure: 1,
        snapshot_revision: 0
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::Routing::AllocationDecision.new(
        chosen_provider: nil,
        candidate_discrepancies: {},
        post_measures: { "A" => { "B" => 1, " B " => 2 } },
        incoming_measure: 1,
        snapshot_revision: 0
      )
    end
  end

  def test_runtime_feasibility_canonicalizes_attempted_provider_identity
    policy = count_policy("A" => 1)
    eligibility = Struct.new(:functional_provider_ids, :feasible_provider_ids).new(
      [" A "],
      [" A "]
    )

    assessed = RubyRouting::Routing::RuntimeFeasibility.assess(
      policy: policy,
      eligibility: eligibility,
      attempted_provider_ids: TestSupport::EachOnlyCollection.new([" A "]),
      measure_exclusions: { " A " => :measure_limit }
    )

    assert_equal :infeasible, assessed.status
    assert_equal [:recovery_provider_exhausted], assessed.reason_codes
    assert_equal ["A"], assessed.functional_target_provider_ids
    assert_equal ["A"], assessed.feasible_target_provider_ids
    assert_empty assessed.unattempted_provider_ids
    assert_empty assessed.measure_admissible_provider_ids
  end

  def test_runtime_feasibility_accepts_each_only_reason_codes
    feasibility = RubyRouting::Routing::RuntimeFeasibility.new(
      status: :infeasible,
      reason_codes: TestSupport::EachOnlyCollection.new([:operational_infeasibility])
    )

    assert_equal [:operational_infeasibility], feasibility.reason_codes
  end

  def test_allocation_choose_canonicalizes_padded_each_only_candidate_ids
    policy = count_policy("A" => 1, "B" => 1)

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: TestSupport::EachOnlyCollection.new([" A ", " B "]),
      accounting_provider_ids: TestSupport::EachOnlyCollection.new([" A ", " B "]),
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )

    assert_equal "A", decision.chosen_provider
    assert_equal %w[A B], decision.candidate_discrepancies.keys
  end

  def test_recovery_selection_excludes_attempted_provider_before_primary_allocation_authority
    policy = count_policy("A" => 9, "B" => 1)

    decision = RubyRouting::Routing::RecoverySelection.choose(
      policy: policy,
      candidates: %w[A B],
      attempted_provider_ids: TestSupport::EachOnlyCollection.new([" A "]),
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1,
      accounting_provider_ids: %w[A B]
    )

    assert_equal "B", decision.chosen_provider
    assert_equal ["B"], decision.candidate_discrepancies.keys
    assert_equal({ "A" => 0, "B" => 1 }, decision.post_measures.fetch("B"))
  end

  def test_recovery_selection_dispatches_through_the_typed_allocation_constrained_objective
    policy = count_policy("A" => 1, "B" => 1)
    assert_equal :allocation_constrained, policy.recovery_objective.mode

    decision = RubyRouting::Routing::RecoverySelection.choose(
      policy: policy,
      candidates: %w[A B],
      attempted_provider_ids: ["A"],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1,
      accounting_provider_ids: %w[A B]
    )

    assert_equal "B", decision.chosen_provider
  end

  def test_recovery_objective_keeps_allocation_authority_before_quality
    policy = RubyRouting::RoutingPolicy.new(
      id: "recovery-objective-order",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      maximum_shares: { "A" => "1/2" }
    )
    allocation = RubyRouting::Routing::RecoverySelection.choose(
      policy: policy,
      candidates: %w[A B],
      attempted_provider_ids: [],
      snapshot: RubyRouting::Routing::AllocationSnapshot.new(measures: { "A" => 1, "B" => 1 }),
      incoming_measure: 1,
      accounting_provider_ids: %w[A B]
    )
    quality = {
      "A" => RubyRouting::Routing::ProviderQualitySnapshot.new(
        provider_id: "A", successful_samples: 10, failed_samples: 0
      ),
      "B" => RubyRouting::Routing::ProviderQualitySnapshot.new(
        provider_id: "B", successful_samples: 0, failed_samples: 10
      )
    }

    optimized = RubyRouting::Routing::ConstrainedOptimizer.choose(
      policy: policy,
      allocation: allocation,
      quality: quality
    )

    assert_equal ["B"], allocation.allocation_tie_candidates
    assert_equal "B", optimized.chosen_provider
    assert_equal false, optimized.optimization_trace.fetch("A").fetch(:allocation_admissible)
  end

  def test_allocation_authority_keeps_primary_and_recovery_paths_explicit
    policy = count_policy("A" => 1, "B" => 1)
    snapshot = RubyRouting::Routing::AllocationSnapshot.empty

    primary = RubyRouting::Routing::AllocationAuthority.choose(
      policy: policy,
      candidates: %w[A B],
      attempted_provider_ids: [],
      snapshot: snapshot,
      incoming_measure: 1,
      accounting_provider_ids: %w[A B]
    )
    recovery = RubyRouting::Routing::AllocationAuthority.choose(
      policy: policy,
      candidates: %w[A B],
      attempted_provider_ids: ["A"],
      snapshot: snapshot,
      incoming_measure: 1,
      accounting_provider_ids: %w[A B]
    )

    assert_equal "A", primary.chosen_provider
    assert_equal "B", recovery.chosen_provider
    assert_equal ["B"], recovery.candidate_discrepancies.keys
  end

  def test_allocation_snapshot_canonicalizes_provider_ids_and_rejects_collisions
    snapshot = RubyRouting::Routing::AllocationSnapshot.new(measures: { " A " => 2 })

    assert_equal({ "A" => 2 }, snapshot.measures)
    assert_equal 2, snapshot.measure_for(" A ")
    assert_equal({ "A" => 5 }, snapshot.with_commit(" A ", 3).measures)
    assert_raises(ArgumentError) { snapshot.measure_for(" ") }
    assert_raises(ArgumentError) { snapshot.with_commit(" ", 1) }
    assert_raises(ArgumentError) do
      RubyRouting::Routing::AllocationSnapshot.new(measures: { " " => 1 })
    end
    assert_raises(ArgumentError) do
      RubyRouting::Routing::AllocationSnapshot.new(measures: { "A" => 1, " A " => 2 })
    end
  end

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

  def test_count_tolerance_is_an_absolute_post_decision_l1_measure
    policy = RubyRouting::RoutingPolicy.new(
      id: "count-tolerance",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      tolerance: 0
    )
    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.new(measures: { "A" => 1, "B" => 0 }),
      incoming_measure: 1
    )

    assert_equal Rational(2), decision.candidate_discrepancies.fetch("A")
    assert_equal Rational(0), decision.candidate_discrepancies.fetch("B")
    assert_equal "B", decision.chosen_provider
    assert_equal false, decision.candidate_trace.fetch("B").fetch(:tolerance_exceeded)
  end

  def test_volume_tolerance_is_in_exact_policy_currency_minor_units
    policy = RubyRouting::RoutingPolicy.new(
      id: "volume-tolerance",
      epoch: "1",
      measure: :volume,
      targets: { "A" => 1, "B" => 1 },
      currency: "RUB",
      tolerance: 40
    )
    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.new(measures: { "A" => 70, "B" => 0 }),
      incoming_measure: 30
    )

    assert_equal Rational(100), decision.candidate_discrepancies.fetch("A")
    assert_equal Rational(40), decision.candidate_discrepancies.fetch("B")
    assert_equal "B", decision.chosen_provider
    assert_equal false, decision.deviation_exceeded?
  end

  def test_indivisible_assignment_can_exceed_tolerance_but_keeps_exact_evidence
    policy = RubyRouting::RoutingPolicy.new(
      id: "indivisible-tolerance",
      epoch: "1",
      measure: :count,
      targets: { "A" => 3, "B" => 1 },
      tolerance: 49
    )
    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 100
    )

    assert_equal "A", decision.chosen_provider
    assert_equal Rational(50), decision.discrepancy
    assert_equal Rational(150), decision.candidate_discrepancies.fetch("B")
    assert_equal true, decision.deviation_exceeded?
    refute_predicate decision, :allocation_corridor_satisfied?
  end

  def test_tolerance_is_an_explicit_allocation_corridor_and_candidate_trace
    policy = count_policy("A" => 1, "B" => 1).then do |base|
      RubyRouting::RoutingPolicy.new(
        id: base.id,
        epoch: base.epoch,
        measure: base.measure,
        targets: base.targets,
        tolerance: 0
      )
    end

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.new(measures: { "A" => 1, "B" => 0 }),
      incoming_measure: 1
    )

    assert_equal "B", decision.chosen_provider
    assert_predicate decision, :allocation_corridor_satisfied?
    assert_equal true, decision.candidate_trace.fetch("A").fetch(:tolerance_exceeded)
    assert_equal false, decision.candidate_trace.fetch("B").fetch(:tolerance_exceeded)
    assert_equal decision.allocation_key_for("A"), decision.candidate_trace.fetch("A").fetch(:allocation_key)
    assert_equal decision.candidate_trace.keys.sort, %w[A B]
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

  def test_share_maximum_is_respected_before_lower_level_ranking
    policy = RubyRouting::RoutingPolicy.new(
      id: "bounded",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      maximum_shares: { "A" => "1/2" }
    )

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.new(measures: { "A" => 1, "B" => 1 }),
      incoming_measure: 1
    )

    assert_equal "B", decision.chosen_provider
    assert_predicate decision, :share_corridor_satisfied?
    assert_empty decision.share_violations
  end

  def test_share_minimum_creates_typed_pressure_for_underrepresented_provider
    policy = RubyRouting::RoutingPolicy.new(
      id: "minimum",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      minimum_shares: { "B" => "1/2" }
    )

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )

    assert_equal "B", decision.chosen_provider
    assert_predicate decision, :share_corridor_satisfied?
  end

  def test_indivisible_assignment_exposes_unsatisfied_share_corridor
    policy = RubyRouting::RoutingPolicy.new(
      id: "indivisible-share",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      maximum_shares: { "A" => "1/2", "B" => "1/2" }
    )

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )

    refute_predicate decision, :share_corridor_satisfied?
    assert_equal Rational(1, 2), decision.chosen_provider_share_violations.fetch(:maximum)
  end

  def test_deviation_classification_is_explicit_and_does_not_change_allocation
    policy = count_policy("A" => 1, "B" => 1)
    allocation = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )

    assert_equal :recoverable,
      RubyRouting::Routing::Deviation.recoverability(
        allocation: allocation,
        cause: :optimizer_choice,
        role: :primary
      )
    assert_equal :unavoidable,
      RubyRouting::Routing::Deviation.recoverability(
        allocation: allocation,
        cause: :recovery_exclusion,
        role: :primary
      )
    assert_equal :unavoidable,
      RubyRouting::Routing::Deviation.recoverability(
        allocation: allocation,
        cause: :optimizer_choice,
        role: :recovery
      )
    assert_equal "A", allocation.chosen_provider
  end

  def test_chosen_provider_share_violations_are_scoped_to_the_chosen_provider
    policy = RubyRouting::RoutingPolicy.new(
      id: "chosen-share-scope",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      maximum_shares: { "A" => "1/3" }
    )

    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.new(measures: { "A" => 2, "B" => 1 }),
      incoming_measure: 1
    )

    assert_equal "B", decision.chosen_provider
    assert_equal({ "A" => { maximum: Rational(1, 6) } }, decision.share_violations)
    assert_empty decision.chosen_provider_share_violations
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

  def test_eligibility_and_allocation_accept_each_only_enumerables
    policy = count_policy("A" => 1, "B" => 1)
    opportunities = TestSupport::EachOnlyCollection.new([
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ])

    eligibility = RubyRouting::Routing::Eligibility.evaluate(opportunities)
    decision = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: TestSupport::EachOnlyCollection.new(eligibility.feasible_provider_ids),
      accounting_provider_ids: TestSupport::EachOnlyCollection.new(eligibility.functional_provider_ids),
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )

    assert_equal %w[A B], eligibility.feasible_provider_ids
    assert_equal "A", decision.chosen_provider
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

  def test_context_labels_are_canonicalized_for_provider_and_policy_eligibility
    intent = RubyRouting::PayoutIntent.new(
      id: "padded-context",
      money: RubyRouting::Money.new(100, "RUB"),
      context: { labels: [" retail "] }
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "padded-context",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      hard_constraints: { required_context_labels: ["retail"] }
    )
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      required_context_labels: ["retail"]
    )

    assert policy.hard_constraints.allows?(intent: intent, provider_id: "A")
    assert provider.functional_eligible_for?(intent: intent, policy: policy)
    assert_equal ["A"], RubyRouting::Routing::Eligibility.evaluate(
      [provider],
      intent: intent,
      policy: policy
    ).feasible_provider_ids
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
