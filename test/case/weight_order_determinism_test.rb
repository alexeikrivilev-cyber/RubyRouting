# frozen_string_literal: true

require "json"
require_relative "../test_helper"

class CaseWeightOrderDeterminismTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  CANONICAL_KEYS = %i[count volume priority amount conversion_24h load].freeze

  def dataset
    RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
  end

  def run_with(weights = nil, configuration_overrides: {})
    loaded = dataset
    base = RubyRouting::Case::SubmissionProfile.load(
      path: File.join(ROOT, "data/submission_profile.json"), dataset: loaded
    ).configuration
    values = base.to_h.merge(configuration_overrides)
    values[:weights] = weights unless weights.nil?
    configuration = RubyRouting::Case::CaseConfiguration.from(values, provider_ids: base.provider_ids)
    RubyRouting::Case::Runner.new(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json"),
      configuration: configuration
    ).call
  end

  def test_equivalent_weight_maps_have_canonical_configuration_and_artifact_bytes
    first = run_with({
      count: 2, volume: 2, priority: 1, amount: 1, conversion_24h: 2, load: 1
    })
    second = run_with({
      load: 1, conversion_24h: 2, amount: 1, priority: 1, volume: 2, count: 2
    })

    assert_equal CANONICAL_KEYS, first.configuration.weights.values.keys
    assert_equal CANONICAL_KEYS, second.configuration.weights.values.keys
    assert_equal first.configuration.to_h, second.configuration.to_h
    assert_equal first.decisions.map(&:to_h), second.decisions.map(&:to_h)
    assert_equal first.report.to_h, second.report.to_h
    assert_equal(
      JSON.generate(RubyRouting::Case::Serializer.json_value(first.report.to_h)),
      JSON.generate(RubyRouting::Case::Serializer.json_value(second.report.to_h))
    )
  end

  def test_equivalent_provider_maps_have_canonical_configuration_and_artifact_bytes
    left = {
      preferred_amount_ranges: {
        vipay: { min: 5_000, max: 50_000 },
        payflow: { min: 1_000, max: 20_000 },
        quickpay: { min: 20_000, max: 150_000 }
      },
      min_turnovers: { vipay: 100, payflow: 200, quickpay: 300 },
      rpm_limits: { vipay: 10, payflow: 20, quickpay: 30 }
    }
    right = left.transform_values { |value| value.to_a.reverse.to_h }

    first = run_with(nil, configuration_overrides: left)
    second = run_with(nil, configuration_overrides: right)

    assert_equal first.configuration.to_h, second.configuration.to_h
    assert_equal first.decisions.map(&:to_h), second.decisions.map(&:to_h)
    assert_equal first.report.to_h, second.report.to_h
    assert_equal(
      JSON.generate(RubyRouting::Case::Serializer.json_value(first.report.to_h)),
      JSON.generate(RubyRouting::Case::Serializer.json_value(second.report.to_h))
    )
    assert_equal %w[payflow quickpay vipay], first.configuration.preferred_amount_ranges.keys
    assert_equal %w[payflow quickpay vipay], first.configuration.min_turnovers.keys
    assert_equal %w[payflow quickpay vipay], first.configuration.rpm_limits.keys
  end
end
