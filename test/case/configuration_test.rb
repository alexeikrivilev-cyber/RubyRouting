# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseConfigurationTest < Minitest::Test
  def test_configuration_is_typed_exact_and_round_trips_its_case_controls
    configuration = RubyRouting::Case::CaseConfiguration.from(
      {
        "count_share" => { "a" => Rational(1, 2) },
        "volume_share" => { "a" => Rational(1, 2) },
        "weights" => { "count" => 2, "priority" => Rational(1, 2) },
        "rpm_limits" => { "a" => 3 },
        "min_turnovers" => { "a" => 10_000 },
        "terminal_provider_id" => "a",
        "simulation_mode" => "conversion"
      },
      provider_ids: ["a"]
    )

    assert_equal Rational(1, 2), configuration.targets.count_share.fetch("a")
    assert_equal 2, configuration.weights.values.fetch(:count)
    assert_equal 3, configuration.rpm_limits.fetch("a")
    assert_equal :conversion, configuration.simulation_mode
    assert_equal "a", configuration.to_h.fetch(:terminal_provider_id)

    round_trip = RubyRouting::Case::CaseConfiguration.from(
      configuration.to_h, provider_ids: ["a"]
    )
    assert_equal configuration.to_h, round_trip.to_h
  end

  def test_unknown_and_inexact_configuration_values_fail_closed
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.from({ "unknown" => true }, provider_ids: ["a"])
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.from({ "weights" => { "priority" => 0.5 } }, provider_ids: ["a"])
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.from(
        { "provider_ids" => ["other"] }, provider_ids: ["a"]
      )
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.new(provider_ids: ["a"], terminal_provider_id: false)
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::RoutingWeights.new({ "priority" => 1, priority: 2 })
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::ConflictResolver.new(min_turnovers: { "a" => 1, a: 2 })
    end
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: ["other"], count_share: { "other" => 1 }
    )
    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.new(provider_ids: ["a"], targets: targets)
    end
    assert_includes error.message, "target provider ids"
    normalized = RubyRouting::Case::CaseConfiguration.new(provider_ids: [" a "])
    assert_equal ["a"], normalized.provider_ids
  end

  def test_canonical_targets_reject_competing_share_maps
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: %w[a b], count_share: { a: Rational(1, 2) },
      volume_share: { a: Rational(1, 2) }
    )

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.new(
        provider_ids: %w[a b], targets: targets,
        count_share: { b: Rational(1, 1) }
      )
    end
    assert_includes error.message, "cannot be combined"

    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.from(
        { targets: targets, volume_share: { b: Rational(1, 1) } }, provider_ids: %w[a b]
      )
    end

    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.new(
        provider_ids: %w[a b], targets: targets, count_share: nil
      )
    end
  end

  def test_false_targets_cannot_fall_back_to_empty_share_maps
    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.new(provider_ids: %w[a], targets: false)
    end
    assert_includes error.message, "targets must be TrafficTargets"
  end

  def test_configuration_maps_and_terminal_use_canonical_provider_identity
    configuration = RubyRouting::Case::CaseConfiguration.from(
      {
        "count_share" => { " a " => Rational(1, 1) },
        "volume_share" => { :a => Rational(1, 1) },
        "rpm_limits" => { " a " => 3 },
        "min_turnovers" => { :a => 10 },
        "terminal_provider_id" => " a "
      },
      provider_ids: ["a"]
    )

    assert_equal Rational(1, 1), configuration.targets.count_share.fetch("a")
    assert_equal 3, configuration.rpm_limits.fetch("a")
    assert_equal 10, configuration.min_turnovers.fetch("a")
    assert_equal "a", configuration.terminal_provider_id
  end

  def test_prebuilt_configuration_must_match_expected_provider_identity
    configuration = RubyRouting::Case::CaseConfiguration.new(provider_ids: ["other"])

    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.from(configuration, provider_ids: ["a"])
    end
  end
end
