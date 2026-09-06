# frozen_string_literal: true

require_relative "../test_helper"

class PolicyTest < Minitest::Test
  def test_volume_policy_measures_exact_minor_units
    policy = RubyRouting::RoutingPolicy.new(
      id: "volume",
      epoch: "1",
      measure: :volume,
      targets: { "A" => 1, "B" => 1 },
      currency: "rub"
    )

    assert_equal 12_345, policy.measure_for(RubyRouting::Money.new(12_345, "RUB"))
    assert_raises(ArgumentError) { policy.measure_for(RubyRouting::Money.new(12_345, "USD")) }
  end

  def test_count_policy_uses_one_for_every_positive_payout
    policy = RubyRouting::RoutingPolicy.new(
      id: "count",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )

    assert_equal 1, policy.measure_for(RubyRouting::Money.new(99_999, "USD"))
  end

  def test_policy_rejects_invalid_targets_and_budget
    assert_raises(ArgumentError) do
      RubyRouting::RoutingPolicy.new(id: "p", epoch: "1", measure: :count, targets: {})
    end
    assert_raises(ArgumentError) do
      RubyRouting::RoutingPolicy.new(id: "p", epoch: "1", measure: :count, targets: { "A" => 0 })
    end
    assert_raises(ArgumentError) do
      RubyRouting::RoutingPolicy.new(id: "p", epoch: "1", measure: :count, targets: { "A" => 1 }, max_attempts: 0)
    end
    assert_raises(ArgumentError) do
      RubyRouting::RoutingPolicy.new(
        id: "p",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1 },
        tolerance: "1/0"
      )
    end
  end

  def test_policy_rejects_provider_key_collisions_after_canonicalization
    assert_raises(ArgumentError) do
      RubyRouting::RankingPolicy.new(priority_by_provider: { "A" => 1, " A " => 2 })
    end

    assert_raises(ArgumentError) do
      RubyRouting::RoutingPolicy.new(
        id: "duplicate-measures",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1 },
        minimum_measures: { "A" => 1, " A " => 2 }
      )
    end

    assert_raises(ArgumentError) do
      RubyRouting::RoutingPolicy.new(
        id: "duplicate-maximums",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1 },
        maximum_measures: { "A" => 3, " A " => 4 }
      )
    end

    assert_raises(ArgumentError) do
      RubyRouting::RoutingPolicy.new(
        id: "duplicate-minimum-shares",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1 },
        minimum_shares: { "A" => "1/2", " A " => "1/2" }
      )
    end

    assert_raises(ArgumentError) do
      RubyRouting::RoutingPolicy.new(
        id: "duplicate-maximum-shares",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1 },
        maximum_shares: { "A" => "1/2", " A " => "1/2" }
      )
    end
  end

  def test_policy_fingerprint_covers_material_definition_and_recovery_budget
    base = RubyRouting::RoutingPolicy.new(
      id: "fingerprinted",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    changed = RubyRouting::RoutingPolicy.new(
      id: "fingerprinted",
      epoch: "1",
      measure: :count,
      targets: { "A" => 2, "B" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 4)
    )

    refute_equal base.fingerprint, changed.fingerprint
    assert_equal base.fingerprint, base.fingerprint.dup
    assert_equal 3, base.recovery.max_operations
  end

  def test_recovery_objective_is_typed_explicit_and_default_compatible
    legacy = RubyRouting::RoutingPolicy.new(
      id: "recovery-objective",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    explicit = RubyRouting::RoutingPolicy.new(
      id: "recovery-objective",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      recovery_objective: RubyRouting::RecoveryObjective.new(mode: :allocation_constrained)
    )

    assert_instance_of RubyRouting::RecoveryObjective, legacy.recovery_objective
    assert_equal :allocation_constrained, legacy.recovery_objective.mode
    assert_predicate legacy.recovery_objective, :frozen?
    assert_equal legacy.to_h, explicit.to_h
    assert_equal legacy.fingerprint, explicit.fingerprint
    assert_raises(ArgumentError) { RubyRouting::RecoveryObjective.new(mode: :reliability_first) }
  end

  def test_policy_fingerprint_is_stable_for_unordered_definition_input
    first = RubyRouting::RoutingPolicy.new(
      id: "canonical",
      epoch: "1",
      measure: :count,
      targets: { "B" => 1, "A" => 2 },
      ranking: RubyRouting::RankingPolicy.new(
        priority_by_provider: { "B" => 1, "A" => 2 },
        cost_minor_by_provider: { "B" => 4, "A" => 3 }
      ),
      hard_constraints: {
        excluded_provider_ids: ["B", "A"],
        required_context_labels: ["wholesale", "retail"]
      }
    )
    second = RubyRouting::RoutingPolicy.new(
      id: "canonical",
      epoch: "1",
      measure: :count,
      targets: { "A" => 2, "B" => 1 },
      ranking: RubyRouting::RankingPolicy.new(
        priority_by_provider: { "A" => 2, "B" => 1 },
        cost_minor_by_provider: { "A" => 3, "B" => 4 }
      ),
      hard_constraints: {
        excluded_provider_ids: ["A", "B"],
        required_context_labels: ["retail", "wholesale"]
      }
    )

    assert_equal first.fingerprint, second.fingerprint
  end

  def test_policy_exposes_exact_tolerance_and_provider_measure_limits
    policy = RubyRouting::RoutingPolicy.new(
      id: "limits",
      epoch: "1",
      measure: :volume,
      targets: { "A" => 1 },
      currency: "RUB",
      tolerance: "1/3",
      minimum_measures: { "A" => 100 },
      maximum_measures: { "A" => 500 }
    )

    assert_equal Rational(1, 3), policy.tolerance
    assert policy.allows_measure?("A", 100)
    refute policy.allows_measure?("A", 99)
    refute policy.allows_measure?("A", 501)
  end

  def test_policy_separates_per_payout_measure_limits_from_share_obligations
    policy = RubyRouting::RoutingPolicy.new(
      id: "share-bounds",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      minimum_measures: { "A" => 1 },
      maximum_measures: { "A" => 3 },
      minimum_shares: { "B" => "1/3" },
      maximum_shares: { "A" => Rational(2, 3) }
    )

    assert_equal({ "A" => 1 }, policy.minimum_measures)
    assert_equal({ "A" => 3 }, policy.maximum_measures)
    assert_equal({ "B" => Rational(1, 3) }, policy.minimum_shares)
    assert_equal({ "A" => Rational(2, 3) }, policy.maximum_shares)
    assert_equal Rational(1, 3), policy.minimum_share_for("B")
    assert_equal Rational(2, 3), policy.maximum_share_for("A")
    assert policy.allows_measure?("A", 2)
    assert_equal({ "A" => { maximum: Rational(1, 6) }, "B" => { minimum: Rational(1, 6) } },
      policy.share_violations({ "A" => 5, "B" => 1 }))
  end

  def test_policy_rejects_invalid_or_statistically_infeasible_share_obligations
    error = assert_raises(RubyRouting::StaticPolicyInfeasibilityError) do
      RubyRouting::RoutingPolicy.new(
        id: "invalid-share",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1, "B" => 1 },
        minimum_shares: { "A" => "2/3" },
        maximum_shares: { "A" => "1/3" }
      )
    end
    assert_equal [:share_minimum_above_maximum], error.reason_codes

    error = assert_raises(RubyRouting::StaticPolicyInfeasibilityError) do
      RubyRouting::RoutingPolicy.new(
        id: "impossible-share",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1, "B" => 1 },
        maximum_shares: { "A" => "1/3", "B" => "1/3" }
      )
    end
    assert_equal [:share_maximums_below_total], error.reason_codes
  end

  def test_policy_infeasibility_error_accepts_each_only_reason_codes
    error = RubyRouting::StaticPolicyInfeasibilityError.new(
      "invalid policy",
      reason_codes: TestSupport::EachOnlyCollection.new([:invalid_policy])
    )

    assert_equal [:invalid_policy], error.reason_codes
  end

  def test_valid_policy_exposes_static_feasibility_and_measure_conflicts_are_typed
    policy = RubyRouting::RoutingPolicy.new(
      id: "static-feasible",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )

    assert_equal({ status: :feasible, reason_codes: [] }, policy.static_feasibility)

    constrained = RubyRouting::RoutingPolicy.new(
      id: "static-hard-constraint",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      hard_constraints: { allowed_provider_ids: ["A"], excluded_provider_ids: ["A"] }
    )
    assert_equal(
      { status: :infeasible, reason_codes: [:no_hard_constraint_eligible_target] },
      constrained.static_feasibility
    )

    hard_share_infeasible = RubyRouting::RoutingPolicy.new(
      id: "hard-share-infeasible",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      hard_constraints: { allowed_provider_ids: ["A"] },
      minimum_shares: { "B" => "1/2" }
    )
    assert_equal(
      { status: :infeasible, reason_codes: [:share_minimum_on_hard_ineligible_target] },
      hard_share_infeasible.static_feasibility
    )

    hard_share_capacity = RubyRouting::RoutingPolicy.new(
      id: "hard-share-capacity",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      hard_constraints: { allowed_provider_ids: ["A"] },
      maximum_shares: { "A" => "1/3" }
    )
    assert_equal(
      { status: :infeasible, reason_codes: [:share_maximums_below_hard_constraint_capacity] },
      hard_share_capacity.static_feasibility
    )

    error = assert_raises(RubyRouting::StaticPolicyInfeasibilityError) do
      RubyRouting::RoutingPolicy.new(
        id: "invalid-measure-corridor",
        epoch: "1",
        measure: :volume,
        targets: { "A" => 1 },
        currency: "RUB",
        minimum_measures: { "A" => 200 },
        maximum_measures: { "A" => 100 }
      )
    end
    assert_equal [:measure_minimum_above_maximum], error.reason_codes
  end

  def test_hard_and_soft_constraints_are_explicit_and_fingerprintable
    policy = RubyRouting::RoutingPolicy.new(
      id: "constraints",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      hard_constraints: { excluded_provider_ids: ["B"] },
      soft_constraints: { required_context_labels: ["preferred"] }
    )

    assert_instance_of RubyRouting::RoutingConstraints, policy.hard_constraints
    assert_equal [:provider_excluded], policy.hard_constraints.violations(intent: nil, provider_id: "B")
    assert_equal ["preferred"], policy.soft_constraints.required_context_labels
    assert policy.fingerprint.frozen?
  end

  def test_policy_window_is_explicit_and_has_an_allocation_key
    policy = RubyRouting::RoutingPolicy.new(
      id: "windowed",
      epoch: "7",
      measure: :count,
      targets: { "A" => 1 },
      window: :policy_epoch
    )

    assert_equal :policy_epoch, policy.window
    assert_equal ["windowed", "7", "default"], policy.allocation_key
  end

  def test_opportunity_cohort_window_keys_the_functional_target_cohort
    policy = RubyRouting::RoutingPolicy.new(
      id: "cohort-window",
      epoch: "7",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )

    assert_equal ["cohort-window", "7", "default", ["A", "B"]], policy.allocation_key
    refute_equal policy.allocation_key(opportunity_provider_ids: ["A"]),
      policy.allocation_key(opportunity_provider_ids: ["A", "B"])
    assert_equal ["cohort-window", "7", "default", ["A"]],
      policy.allocation_key(opportunity_provider_ids: ["A"])
  end

  def test_public_policy_collections_accept_each_only_enumerables
    policy = RubyRouting::RoutingPolicy.new(
      id: "each-only-policy-boundaries",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      minimum_shares: { "A" => "1/2" },
      hard_constraints: RubyRouting::RoutingConstraints.new(
        allowed_provider_ids: TestSupport::EachOnlyCollection.new(["A", "B"]),
        required_context_labels: TestSupport::EachOnlyCollection.new(["retail"])
      )
    )

    assert_equal ["each-only-policy-boundaries", "1", "default", ["A"]],
      policy.allocation_key(opportunity_provider_ids: TestSupport::EachOnlyCollection.new(["A"]))
    assert_equal({ "A" => { minimum: Rational(1, 2) } },
      policy.share_violations({ "A" => 0, "B" => 1 },
                               provider_ids: TestSupport::EachOnlyCollection.new(["A"])))
    assert policy.hard_constraints.allows?(
      intent: RubyRouting::PayoutIntent.new(
        id: "each-only-context",
        money: RubyRouting::Money.new(100, "RUB"),
        context: { labels: TestSupport::EachOnlyCollection.new(["retail"]) }
      ),
      provider_id: "A"
    )
  end

  def test_policy_registry_registers_and_resolves_policies_for_intent_currency
    rub_policy = RubyRouting::RoutingPolicy.new(
      id: "rub-policy",
      epoch: "1",
      measure: :volume,
      targets: { "A" => 1 },
      currency: "RUB"
    )
    usd_policy = RubyRouting::RoutingPolicy.new(
      id: "usd-policy",
      epoch: "1",
      measure: :volume,
      targets: { "B" => 1 },
      currency: "USD"
    )
    registry = RubyRouting::PolicyRegistry.new([rub_policy, usd_policy])

    rub_intent = RubyRouting::PayoutIntent.new(id: "p1", money: RubyRouting::Money.new(1000, "RUB"))
    usd_intent = RubyRouting::PayoutIntent.new(id: "p2", money: RubyRouting::Money.new(500, "USD"))

    assert_equal rub_policy, registry.find_for_intent(rub_intent)
    assert_equal usd_policy, registry.find_for_intent(usd_intent)
    assert_equal rub_policy, registry.fetch(id: "rub-policy", epoch: "1")
    assert_equal 2, registry.policies.length
  end

  def test_policy_registry_accepts_each_only_initial_policies
    policy = RubyRouting::RoutingPolicy.new(
      id: "each-only-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )

    registry = RubyRouting::PolicyRegistry.new(TestSupport::EachOnlyCollection.new([policy]))

    assert_equal [policy], registry.policies
  end

  def test_policy_registry_lookups_canonicalize_identity_inputs
    policy = RubyRouting::RoutingPolicy.new(
      id: "registry-identity",
      epoch: "1",
      scope: "default",
      measure: :count,
      targets: { "A" => 1 }
    )
    registry = RubyRouting::PolicyRegistry.new([policy])
    intent = RubyRouting::PayoutIntent.new(
      id: "payout-identity",
      money: RubyRouting::Money.new(100, "RUB"),
      recipient: {}
    )

    assert_equal policy, registry.fetch(id: " registry-identity ", epoch: " 1 ", scope: " default ")
    assert_equal policy, registry.find_for_intent(intent, scope: " default ")
  end

  def test_policy_registry_rejects_blank_lookup_identity
    registry = RubyRouting::PolicyRegistry.new

    assert_raises(ArgumentError) do
      registry.fetch(id: " ", epoch: "1")
    end
    assert_raises(ArgumentError) do
      registry.find_for_intent(
        RubyRouting::PayoutIntent.new(
          id: "payout-identity",
          money: RubyRouting::Money.new(100, "RUB"),
          recipient: {}
        ),
        scope: " "
      )
    end
  end

  def test_policy_registry_rejects_reusing_identity_with_conflicting_fingerprint
    initial = RubyRouting::RoutingPolicy.new(
      id: "shared-id",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    conflicting = RubyRouting::RoutingPolicy.new(
      id: "shared-id",
      epoch: "1",
      measure: :count,
      targets: { "A" => 2 }
    )
    registry = RubyRouting::PolicyRegistry.new([initial])

    assert_raises(ArgumentError) { registry.register(conflicting) }
  end

  def test_policy_registry_does_not_use_registration_order_for_competing_defaults
    older = RubyRouting::RoutingPolicy.new(
      id: "active-policy",
      epoch: "9",
      measure: :count,
      targets: { "A" => 1 }
    )
    newer = RubyRouting::RoutingPolicy.new(
      id: "active-policy",
      epoch: "10",
      measure: :count,
      targets: { "A" => 1 }
    )
    registry = RubyRouting::PolicyRegistry.new([older, newer])
    intent = RubyRouting::PayoutIntent.new(
      id: "active-policy-intent",
      money: RubyRouting::Money.new(1, "RUB")
    )

    resolution = registry.resolve_for_intent(intent)
    assert resolution.ambiguous?
    assert_nil resolution.policy
    assert_equal [newer, older], resolution.candidates
    error = assert_raises(RubyRouting::AmbiguousPolicyError) do
      registry.find_for_intent(intent)
    end
    assert_equal resolution.to_h, error.resolution.to_h

    registry.register(older)
    assert_equal resolution.to_h, registry.resolve_for_intent(intent).to_h
  end

  def test_public_policy_provider_boundaries_canonicalize_ids_and_support_each_only
    policy = RubyRouting::RoutingPolicy.new(
      id: "canonical-provider-boundaries",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      ranking: RubyRouting::RankingPolicy.new(
        priority_by_provider: { "A" => 7 },
        cost_minor_by_provider: { "A" => 3 },
        latency_ms_by_provider: { "A" => 11 }
      ),
      minimum_measures: { "A" => 2 },
      maximum_measures: { "A" => 5 },
      minimum_shares: { "A" => "1/2" }
    )

    assert_equal 7, policy.ranking.priority_for(" A ")
    assert_equal 3, policy.ranking.cost_for(" A ")
    assert_equal 11, policy.ranking.latency_for(" A ")
    assert_equal 1, policy.weight_for(" A ")
    assert_equal({ "A" => 1 }, policy.weights_for(TestSupport::EachOnlyCollection.new([" A "])))
    assert_equal 2, policy.minimum_measure_for(" A ")
    assert_equal 5, policy.maximum_measure_for(" A ")
    assert_equal({ "A" => :policy_measure_constraint },
      policy.measure_exclusions(TestSupport::EachOnlyCollection.new([" A "]), 1))
    assert_equal Rational(1, 2), policy.minimum_share_for(" A ")
    assert_equal({ "A" => { minimum: Rational(1, 2) } },
      policy.share_violations({ "A" => 0, "B" => 1 }, provider_ids: [" A "]))
    assert_equal policy.allocation_key(opportunity_provider_ids: ["A", "B"]),
      policy.allocation_key(opportunity_provider_ids: TestSupport::EachOnlyCollection.new([" A ", " B "]))
  end

end
