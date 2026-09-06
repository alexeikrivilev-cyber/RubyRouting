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
  end
end
