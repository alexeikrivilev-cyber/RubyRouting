# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseFactorCampaignTest < Minitest::Test
  def provider(id, priority: 1, conversion: Rational(1, 2), min: 1, max: 1_000,
               daily_limit: 10_000, daily_approved: 0)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: 50, priority: priority,
      limit_amount_min: min, limit_amount_max: max, daily_amount_limit: daily_limit,
      daily_approved_amount: daily_approved, in_progress_count_limit: 100,
      in_progress_count: 0, in_progress_amount_limit: 100_000, in_progress_amount: 0,
      available_requisites: 10, conversion_24h: conversion, avg_latency_sec: 10,
      banks: [], exclude_banks: false, provider_margin_pct: 1,
      merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def operation(amount: 100, id: "factor-campaign")
    RubyRouting::Case::Operation.new(
      operation_id: id, created_at: Time.utc(2026, 7, 30, 9), amount: amount,
      bank: "sberbank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def states(first, second, rpm_limit: nil)
    [
      RubyRouting::Case::ProviderCaseState.new(first, rpm_limit: rpm_limit),
      RubyRouting::Case::ProviderCaseState.new(second, rpm_limit: rpm_limit)
    ]
  end

  def resolve(weights:, provider_states:, traffic: nil, min_turnovers: {})
    item = operation
    ledger = traffic || RubyRouting::Case::TrafficLedger.new(%w[a b])
    RubyRouting::Case::ConflictResolver.new(
      weights: weights, min_turnovers: min_turnovers
    ).resolve(
      candidates: provider_states, operation: item, traffic: ledger, as_of: item.created_at
    )
  end

  def test_each_rubric_factor_can_change_the_winner_among_hard_eligible_providers
    count_targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: %w[a b], count_share: { a: Rational(1, 2), b: Rational(1, 2) }
    )
    count_traffic = RubyRouting::Case::TrafficLedger.new(%w[a b], targets: count_targets)
    2.times { count_traffic.record!(provider_id: "b", amount: 100) }
    assert_equal "a", resolve(
      weights: { count: 1 }, provider_states: states(provider("a"), provider("b")),
      traffic: count_traffic
    ).selected_provider

    volume_targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: %w[a b], volume_share: { a: Rational(1, 2), b: Rational(1, 2) }
    )
    volume_traffic = RubyRouting::Case::TrafficLedger.new(%w[a b], targets: volume_targets)
    volume_traffic.record!(provider_id: "b", amount: 1_000)
    assert_equal "a", resolve(
      weights: { volume: 1 }, provider_states: states(provider("a"), provider("b")),
      traffic: volume_traffic
    ).selected_provider

    assert_equal "a", resolve(
      weights: { priority: 1 }, provider_states: states(provider("a", priority: 1), provider("b", priority: 2))
    ).selected_provider
    assert_equal "a", resolve(
      weights: { amount: 1 },
      provider_states: states(
        provider("a", min: 1, max: 199), provider("b", min: 1, max: 299)
      )
    ).selected_provider
    assert_equal "a", resolve(
      weights: { conversion_24h: 1 },
      provider_states: states(
        provider("a", conversion: Rational(9, 10)), provider("b", conversion: Rational(1, 10))
      )
    ).selected_provider
    assert_equal "a", resolve(
      weights: { load: 1 },
      provider_states: states(
        provider("a", daily_limit: 10_000, daily_approved: 0),
        provider("b", daily_limit: 1_000, daily_approved: 900)
      )
    ).selected_provider

    rpm_item = operation(id: "rpm-factor")
    rpm_states = states(provider("a"), provider("b"), rpm_limit: 10)
    rpm_states.last.reserve!(rpm_item, as_of: rpm_item.created_at)
    rpm_states.last.release!(rpm_item)
    assert_equal "a", RubyRouting::Case::ConflictResolver.new(weights: { intensity: 1 }).resolve(
      candidates: rpm_states, operation: rpm_item,
      traffic: RubyRouting::Case::TrafficLedger.new(%w[a b]), as_of: rpm_item.created_at
    ).selected_provider

    assert_equal "a", resolve(
      weights: { turnover_min: 1 }, provider_states: states(provider("a"), provider("b")),
      min_turnovers: { a: 1_000, b: 0 }
    ).selected_provider
  end

  def test_conflict_weights_change_the_winner_and_preserve_both_traces
    states = self.states(
      provider("a", conversion: Rational(9, 10), daily_limit: 1_000, daily_approved: 900),
      provider("b", conversion: Rational(1, 10), daily_limit: 1_000, daily_approved: 0)
    )
    conversion_first = resolve(
      weights: { conversion_24h: 2, load: 1 }, provider_states: states
    )
    load_first = resolve(
      weights: { conversion_24h: 1, load: 2 }, provider_states: states
    )

    assert_equal "a", conversion_first.selected_provider
    assert_equal "b", load_first.selected_provider
    assert_equal %i[conversion_24h load], conversion_first.traces.fetch("a").map(&:factor)
    assert_equal Rational(2, 1), conversion_first.traces.fetch("a").first.weight
    all_exact = conversion_first.traces.fetch("a").all? do |evidence|
      evidence.raw.is_a?(Integer) || evidence.raw.is_a?(Rational)
    end
    assert all_exact
  end

  def test_preferred_amount_band_changes_ranking_without_changing_hard_eligibility
    operation = operation(amount: 150)
    states = self.states(
      provider("a", min: 1, max: 1_000), provider("b", min: 1, max: 1_000)
    )
    resolver = RubyRouting::Case::ConflictResolver.new(
      weights: { amount: 1 },
      preferred_amount_ranges: {
        a: { min: 100, max: 200 },
        b: { min: 700, max: 800 }
      }
    )
    resolution = resolver.resolve(
      candidates: states, operation: operation,
      traffic: RubyRouting::Case::TrafficLedger.new(%w[a b]), as_of: operation.created_at
    )

    assert_equal "a", resolution.selected_provider
    assert_equal Rational(1, 1), resolution.traces.fetch("a").first.raw
    assert_equal Rational(0, 1), resolution.traces.fetch("b").first.raw
    states.each do |state|
      assert RubyRouting::Case::HardConstraintEvaluator.new.call(
        state, operation, as_of: operation.created_at
      ).eligible?
    end
  end

  def test_preferred_amount_band_configuration_is_typed_and_fails_closed
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::ConflictResolver.new(
        preferred_amount_ranges: { "a" => { min: 1, max: 2 }, a: { min: 3, max: 4 } }
      )
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.new(
        provider_ids: %w[a b], preferred_amount_ranges: { a: { min: 10 } }
      )
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::CaseConfiguration.new(
        provider_ids: %w[a b], preferred_amount_ranges: { a: { min: 100, max: 10 } }
      )
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::ConflictResolver.new(
        weights: { amount: 1 }, preferred_amount_ranges: { a: { min: 10, max: 20, extra: 30 } }
      )
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::ConflictResolver.new(
        weights: { amount: 1 }, preferred_amount_ranges: { a: { min: 10, "min" => 20, max: 30 } }
      )
    end
  end
end
