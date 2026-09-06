# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseTrafficLedgerTest < Minitest::Test
  def test_count_and_volume_are_tracked_together_with_exact_shares
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: %w[a b],
      count_share: { "a" => Rational(1, 2), "b" => Rational(1, 2) },
      volume_share: { "a" => Rational(1, 4), "b" => Rational(3, 4) }
    )
    ledger = RubyRouting::Case::TrafficLedger.new(%w[a b], targets: targets)
    ledger.record!(provider_id: "a", amount: 100)
    ledger.record!(provider_id: "b", amount: 300)

    assert_equal [2, 400], [ledger.total_count, ledger.total_volume]
    assert_equal Rational(1, 2), ledger.share(:count, "a")
    assert_equal Rational(1, 4), ledger.share(:volume, "a")
    assert_equal Rational(2, 3), ledger.counterfactual(provider_id: "b", amount: 100).fetch(:count).fetch(:share_after)
    assert_equal Rational(4, 5), ledger.counterfactual(provider_id: "b", amount: 100).fetch(:volume).fetch(:share_after)
    counts = ledger.count_by_provider
    volumes = ledger.volume_by_provider
    assert counts.frozen?
    assert volumes.frozen?
    assert_raises(FrozenError) { counts["a"] = 99 }
    assert_raises(FrozenError) { volumes["a"] = 99 }
    assert_equal [1, 100], [ledger.count_by_provider.fetch("a"), ledger.volume_by_provider.fetch("a")]
  end

  def test_target_values_are_exact_and_bounded
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::TrafficTargets.new(provider_ids: ["a"], count_share: { "a" => 0.5 })
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::TrafficTargets.new(provider_ids: ["a"], count_share: { "a" => Rational(2, 1) })
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::TrafficTargets.new(provider_ids: ["a"], count_share: { "a" => nil })
    end
    targets = RubyRouting::Case::TrafficTargets.new(provider_ids: ["other"])
    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::TrafficLedger.new(["a"], targets: targets)
    end
    assert_includes error.message, "target provider ids"
    assert_equal ["a"], RubyRouting::Case::TrafficTargets.new(provider_ids: [" a "]).provider_ids
  end

  def test_runner_report_uses_the_same_traffic_ledger_as_routing
    run = RubyRouting::Case::Runner.new.call
    report = run.report.to_h.fetch(:distribution)
    run.traffic.distribution.each do |provider_id, values|
      assert_equal values, report.fetch(provider_id).slice(*values.keys)
    end
    assert_equal run.traffic.total_count, run.decisions.length
    assert_equal 385_800, run.traffic.total_volume
  end

  def test_traffic_provider_operations_reject_structured_identity_coercion
    ledger = RubyRouting::Case::TrafficLedger.new(["a"])
    structured = Object.new
    def structured.to_s
      "a"
    end

    assert_raises(RubyRouting::Case::InputError) do
      ledger.record!(provider_id: structured, amount: 1)
    end
    assert_raises(RubyRouting::Case::InputError) { ledger.share(:count, structured) }
    assert_raises(RubyRouting::Case::InputError) do
      ledger.counterfactual(provider_id: structured, amount: 1)
    end
  end
end
