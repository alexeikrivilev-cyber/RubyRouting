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
      minimums: { "A" => 100 },
      maximums: { "A" => 500 }
    )

    assert_equal Rational(1, 3), policy.tolerance
    assert policy.allows_measure?("A", 100)
    refute policy.allows_measure?("A", 99)
    refute policy.allows_measure?("A", 501)
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
end
