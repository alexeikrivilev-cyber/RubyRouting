# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseFactorsTest < Minitest::Test
  def provider(id, priority:, conversion: Rational(1, 2), daily_amount_limit: 10_000_000,
               daily_approved_amount: 0, in_progress_count_limit: 100,
               in_progress_amount_limit: 10_000_000)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: 50, priority: priority,
      limit_amount_min: 1, limit_amount_max: 100_000, daily_amount_limit: daily_amount_limit,
      daily_approved_amount: daily_approved_amount, in_progress_count_limit: in_progress_count_limit,
      in_progress_count: 0, in_progress_amount_limit: in_progress_amount_limit, in_progress_amount: 0,
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
      normalization_candidates: [
        RubyRouting::Case::ProviderCaseState.new(first),
        RubyRouting::Case::ProviderCaseState.new(second)
      ],
      operation: operation, traffic: ledger, as_of: operation.created_at
    )

    assert_equal "first", resolution.selected_provider
    assert_operator resolution.score_for("first"), :>, resolution.score_for("second")
    assert_equal Rational(1, 2), resolution.traces.fetch("first").first.normalized
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
    ).resolve(candidates: states, normalization_candidates: states,
              operation: operation, traffic: ledger, as_of: operation.created_at)

    assert_equal %i[count volume], resolution.traces.fetch("a").map(&:factor)
    assert_equal %i[count volume], resolution.traces.fetch("b").map(&:factor)
    assert_equal Rational(1, 1), resolution.traces.fetch("a").first.weight
    assert_equal Rational(1, 1), resolution.traces.fetch("a").last.weight
  end

  def test_fallback_phase_reuses_final_portfolio_objectives
    b = provider("b", priority: 9)
    c = provider("c", priority: 1)
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: %w[a b c],
      count_share: { a: 0, b: Rational(4, 5), c: Rational(1, 5) },
      volume_share: { a: 0, b: Rational(4, 5), c: Rational(1, 5) }
    )
    ledger = RubyRouting::Case::TrafficLedger.new(%w[a b c], targets: targets)
    resolver = RubyRouting::Case::ConflictResolver.new(weights: { count: 1, volume: 1 })

    resolution = resolver.resolve(
      candidates: [
        RubyRouting::Case::ProviderCaseState.new(b),
        RubyRouting::Case::ProviderCaseState.new(c)
      ],
      normalization_candidates: [
        RubyRouting::Case::ProviderCaseState.new(b),
        RubyRouting::Case::ProviderCaseState.new(c)
      ],
      operation: operation, traffic: ledger, as_of: operation.created_at, phase: :fallback
    )

    assert_equal :fallback, resolution.phase
    # The final-selected ledger has not recorded this operation yet. Allocation
    # objectives can therefore rank the remaining candidates without counting
    # the rejected primary assignment as a final outcome.
    assert_equal "b", resolution.selected_provider
    assert_equal %i[count volume], resolution.traces.fetch("b").map(&:factor)
    assert_equal %i[count volume], resolution.traces.fetch("c").map(&:factor)
  end

  def test_equal_raw_factor_is_non_discriminating_and_does_not_claim_contribution
    candidates = [
      RubyRouting::Case::ProviderCaseState.new(provider("a", priority: 1)),
      RubyRouting::Case::ProviderCaseState.new(provider("b", priority: 1))
    ]
    resolution = RubyRouting::Case::ConflictResolver.new(weights: { priority: 1 }).resolve(
      candidates: candidates, normalization_candidates: candidates,
      operation: operation, traffic: RubyRouting::Case::TrafficLedger.new(%w[a b]),
      as_of: operation.created_at
    )
    evidence = resolution.traces.fetch("a").first

    assert_equal Rational(1, 2), evidence.raw
    assert_equal Rational(0, 1), evidence.normalized
    assert_equal Rational(0, 1), evidence.contribution
    assert_includes evidence.reason, "non-discriminating"
    assert_equal "a", resolution.selected_provider
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
    resolution = resolver.resolve(candidates: [state], normalization_candidates: [state],
                                  operation: operation, traffic: ledger, as_of: operation.created_at)

    assert_equal 8, resolution.traces.fetch("p").length
    assert resolution.traces.fetch("p").all? { |e| e.raw.is_a?(Integer) || e.raw.is_a?(Rational) }
    assert_equal Rational(0, 1), resolution.score_for("p")
    assert resolution.traces.fetch("p").all? { |evidence| evidence.reason.include?("non-discriminating") }
  end

  def test_zero_rpm_limit_has_no_intensity_headroom_without_dividing_by_zero
    state = RubyRouting::Case::ProviderCaseState.new(provider("p", priority: 1), rpm_limit: 0)
    resolution = RubyRouting::Case::ConflictResolver.new(weights: { intensity: 1 }).resolve(
      candidates: [state], normalization_candidates: [state],
      operation: operation, traffic: RubyRouting::Case::TrafficLedger.new(["p"]),
      as_of: operation.created_at
    )
    evidence = resolution.traces.fetch("p").first

    assert_equal Rational(0, 1), evidence.raw
    assert_equal Rational(0, 1), evidence.normalized
    assert_equal Rational(0, 1), evidence.contribution
    assert_includes evidence.reason, "rolling RPM headroom=0/1"
  end

  def test_zero_capacity_limit_has_no_load_headroom_without_dividing_by_zero
    state = RubyRouting::Case::ProviderCaseState.new(
      provider("p", priority: 1, daily_amount_limit: 0)
    )
    resolution = RubyRouting::Case::ConflictResolver.new(weights: { load: 1 }).resolve(
      candidates: [state], normalization_candidates: [state],
      operation: operation, traffic: RubyRouting::Case::TrafficLedger.new(["p"]),
      as_of: operation.created_at
    )
    evidence = resolution.traces.fetch("p").first

    assert_equal Rational(66_333, 100_000), evidence.raw
    assert_equal Rational(0, 1), evidence.normalized
    assert_equal Rational(0, 1), evidence.contribution
    assert_includes evidence.reason, "current daily/concurrent headroom=66333/100000"
    assert_includes evidence.reason, "non-discriminating"
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
