# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseFactorsTest < Minitest::Test
  def provider(id, priority:, conversion: Rational(1, 2))
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: 50, priority: priority,
      limit_amount_min: 1, limit_amount_max: 100_000, daily_amount_limit: 10_000_000,
      daily_approved_amount: 0, in_progress_count_limit: 100, in_progress_count: 0,
      in_progress_amount_limit: 10_000_000, in_progress_amount: 0,
      available_requisites: 10, conversion_24h: conversion, avg_latency_sec: 10,
      banks: [], exclude_banks: false, provider_margin_pct: 1,
      merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def operation
    RubyRouting::Case::Operation.new(
      operation_id: "factor-op", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "sberbank", card_brand: nil, payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def test_official_priority_is_lower_number_is_stronger
    first = provider("first", priority: 1)
    second = provider("second", priority: 2)
    ledger = RubyRouting::Case::TrafficLedger.new(%w[first second])
    resolution = RubyRouting::Case::ConflictResolver.new(
      weights: { priority: Rational(1, 1) }
    ).resolve(
      candidates: [
        RubyRouting::Case::ProviderCaseState.new(first),
        RubyRouting::Case::ProviderCaseState.new(second)
      ],
      operation: operation, traffic: ledger, as_of: operation.created_at
    )

    assert_equal "first", resolution.selected_provider
    assert_operator resolution.score_for("first"), :>, resolution.score_for("second")
    assert_equal Rational(1, 1), resolution.traces.fetch("first").first.normalized
  end

  def test_count_and_volume_are_independent_evidence_in_one_resolution
    a = provider("a", priority: 1)
    b = provider("b", priority: 1)
    ledger = RubyRouting::Case::TrafficLedger.new(
      %w[a b],
      targets: RubyRouting::Case::TrafficTargets.new(
        provider_ids: %w[a b],
        count_share: { a: Rational(1, 2), b: Rational(1, 2) },
        volume_share: { a: Rational(1, 2), b: Rational(1, 2) }
      )
    )
    3.times { ledger.record!(provider_id: "a", amount: 100) }
    ledger.record!(provider_id: "b", amount: 1_000)
    states = [RubyRouting::Case::ProviderCaseState.new(a), RubyRouting::Case::ProviderCaseState.new(b)]
    resolution = RubyRouting::Case::ConflictResolver.new(
      weights: { count: Rational(1, 1), volume: Rational(1, 1) }
    ).resolve(candidates: states, operation: operation, traffic: ledger, as_of: operation.created_at)

    assert_equal %i[count volume], resolution.traces.fetch("a").map(&:factor)
    assert_equal %i[count volume], resolution.traces.fetch("b").map(&:factor)
    assert_equal Rational(1, 1), resolution.traces.fetch("a").first.weight
    assert_equal Rational(1, 1), resolution.traces.fetch("a").last.weight
  end

  def test_all_supported_factors_return_exact_evidence
    state = RubyRouting::Case::ProviderCaseState.new(provider("p", priority: 1, conversion: Rational(9, 10)), rpm_limit: 10)
    ledger = RubyRouting::Case::TrafficLedger.new(%w[p])
    resolver = RubyRouting::Case::ConflictResolver.new(
      weights: {
        count: 1, volume: 1, priority: 1, amount: 1, conversion_24h: 1,
        load: 1, intensity: 1, turnover_min: 1
      },
      min_turnovers: { p: 10_000 }
    )
    resolution = resolver.resolve(candidates: [state], operation: operation, traffic: ledger, as_of: operation.created_at)

    assert_equal 8, resolution.traces.fetch("p").length
    assert resolution.traces.fetch("p").all? { |e| e.raw.is_a?(Integer) || e.raw.is_a?(Rational) }
    assert_equal Rational(8, 1), resolution.score_for("p")
  end

  def test_resolution_provider_identity_does_not_use_structured_to_s_coercion
    resolution = RubyRouting::Case::Resolution.new(
      selected_provider: "a", scores: { "a" => 1 }, traces: { "a" => [] }
    )
    structured = Object.new
    def structured.to_s
      "a"
    end

    assert_raises(RubyRouting::Case::InputError) { resolution.score_for(structured) }
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Resolution.new(selected_provider: structured, scores: {}, traces: {})
    end
  end
end
