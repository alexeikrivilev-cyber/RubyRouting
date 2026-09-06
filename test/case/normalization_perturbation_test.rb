# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseNormalizationPerturbationTest < Minitest::Test
  CANONICAL_WEIGHTS = {
    count: 2, volume: 2, priority: 1, amount: 1, conversion_24h: 2, load: 1
  }.freeze

  def provider(id, priority:, conversion:, daily:, traffic: 40)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: traffic, priority: priority,
      limit_amount_min: 1, limit_amount_max: 10_000, daily_amount_limit: 10_000,
      daily_approved_amount: daily, in_progress_count_limit: 100, in_progress_count: 0,
      in_progress_amount_limit: 10_000, in_progress_amount: 0, available_requisites: 100,
      conversion_24h: conversion, avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def operation
    RubyRouting::Case::Operation.new(
      operation_id: "normalization-probe", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def targets
    RubyRouting::Case::TrafficTargets.new(
      provider_ids: %w[a b c spacepayments],
      count_share: { a: Rational(4, 10), b: Rational(5, 10), c: Rational(1, 10) },
      volume_share: { a: Rational(4, 10), b: Rational(5, 10), c: Rational(1, 10) }
    )
  end

  def ledger
    value = RubyRouting::Case::TrafficLedger.new(targets.provider_ids, targets: targets)
    10.times do |index|
      value.record_assignment!(
        provider_id: index.even? ? "a" : "b", amount: index.even? ? 100 : 1_000
      )
    end
    value
  end

  def resolution(candidates, normalization_candidates: nil)
    states = candidates.map { |provider| RubyRouting::Case::ProviderCaseState.new(provider) }
    normalization_states = normalization_candidates&.map do |provider|
      RubyRouting::Case::ProviderCaseState.new(provider)
    end
    RubyRouting::Case::ConflictResolver.new(
      weights: CANONICAL_WEIGHTS,
      preferred_amount_ranges: {
        a: { min: 50, max: 200 }, b: { min: 100, max: 500 }, c: { min: 500, max: 1_000 }
      }
    ).resolve(
      candidates: states, normalization_candidates: normalization_states,
      operation: operation, traffic: ledger, as_of: operation.created_at
    )
  end

  def test_adding_non_winning_candidate_does_not_rescale_a_b_into_a_different_winner
    a = provider("a", priority: 0, conversion: Rational(1, 2), daily: 0)
    b = provider("b", priority: 1, conversion: Rational(9, 10), daily: 0)
    c = provider("c", priority: 0, conversion: Rational(1, 10), daily: 0)
    normalization_pool = [a, b, c]

    base = resolution([a, b], normalization_candidates: normalization_pool)
    expanded = resolution([a, b, c], normalization_candidates: normalization_pool)

    refute_equal "c", expanded.selected_provider
    assert_equal base.selected_provider, expanded.selected_provider
    %w[a b].each do |provider_id|
      assert_equal raw_factors(base, provider_id), raw_factors(expanded, provider_id)
    end
    %i[count volume priority amount conversion_24h load].each do |factor|
      assert_equal normalized_difference(base, factor), normalized_difference(expanded, factor)
    end
  end

  def test_resolver_rejects_an_implicit_candidate_set_normalization_authority
    states = [
      RubyRouting::Case::ProviderCaseState.new(provider("a", priority: 0, conversion: Rational(1, 2), daily: 0)),
      RubyRouting::Case::ProviderCaseState.new(provider("b", priority: 1, conversion: Rational(9, 10), daily: 0))
    ]

    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::ConflictResolver.new(weights: CANONICAL_WEIGHTS).resolve(
        candidates: states, operation: operation, traffic: ledger, as_of: operation.created_at
      )
    end
  end

  private

  def raw_factors(resolution, provider_id)
    resolution.traces.fetch(provider_id).to_h { |evidence| [evidence.factor, evidence.raw] }
  end

  def normalized_difference(resolution, factor)
    a = resolution.traces.fetch("a").find { |item| item.factor == factor }
    b = resolution.traces.fetch("b").find { |item| item.factor == factor }
    a.normalized - b.normalized
  end
end
