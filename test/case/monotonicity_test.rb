# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseMonotonicityTest < Minitest::Test
  def test_router_preference_factors_do_not_make_an_improved_provider_worse
    assert_factor_improvement(
      "priority",
      base: route(
        providers: [provider("a", priority: 2), provider("b", priority: 1)],
        weights: { priority: 1 }
      ),
      improved: route(
        providers: [provider("a", priority: 0), provider("b", priority: 1)],
        weights: { priority: 1 }
      )
    )

    assert_factor_improvement(
      "amount",
      base: route(
        providers: [provider("a"), provider("b")],
        weights: { amount: 1 },
        preferred_amount_ranges: {
          a: { min: 700, max: 800 }, b: { min: 100, max: 200 }
        }
      ),
      improved: route(
        providers: [provider("a"), provider("b")],
        weights: { amount: 1 },
        preferred_amount_ranges: {
          a: { min: 100, max: 200 }, b: { min: 100, max: 200 }
        }
      )
    )

    assert_factor_improvement(
      "conversion_24h",
      base: route(
        providers: [provider("a", conversion: Rational(1, 10)), provider("b", conversion: Rational(1, 2))],
        weights: { conversion_24h: 1 }
      ),
      improved: route(
        providers: [provider("a", conversion: Rational(9, 10)), provider("b", conversion: Rational(1, 2))],
        weights: { conversion_24h: 1 }
      )
    )

    assert_factor_improvement(
      "load",
      base: route(
        providers: [provider("a", daily_limit: 2_000, daily_approved: 900), provider("b", daily_limit: 2_000, daily_approved: 100)],
        weights: { load: 1 }
      ),
      improved: route(
        providers: [provider("a", daily_limit: 2_000, daily_approved: 100), provider("b", daily_limit: 2_000, daily_approved: 100)],
        weights: { load: 1 }
      )
    )

    assert_factor_improvement(
      "turnover_min",
      base: route(
        providers: [provider("a", daily_approved: 100), provider("b", daily_approved: 250)],
        weights: { turnover_min: 1 }, min_turnovers: { a: 0, b: 500 }
      ),
      improved: route(
        providers: [provider("a", daily_approved: 100), provider("b", daily_approved: 250)],
        weights: { turnover_min: 1 }, min_turnovers: { a: 1_000, b: 500 }
      )
    )

    base = route(
      providers: [provider("a"), provider("b")],
      operations: operations(3), weights: { intensity: 1 }, rpm_limits: { a: 1, b: 2 }
    )
    improved = route(
      providers: [provider("a"), provider("b")],
      operations: operations(3), weights: { intensity: 1 }, rpm_limits: { a: 3, b: 2 }
    )
    assert_equal "b", base.fetch(2).fetch(:selected), "base intensity scenario"
    assert_equal "a", improved.fetch(2).fetch(:selected), "improved intensity scenario"
  end

  private

  def assert_factor_improvement(factor, base:, improved:)
    base_entry = base.fetch(0)
    improved_entry = improved.fetch(0)
    assert_equal "b", base_entry.fetch(:selected), "#{factor} base scenario"
    assert_equal "a", improved_entry.fetch(:selected), "#{factor} improved scenario"
    base_raw = factor_raw(base_entry, factor)
    improved_raw = factor_raw(improved_entry, factor)
    assert_operator improved_raw, :>, base_raw, "#{factor} must improve provider a's raw evidence"
  end

  def factor_raw(entry, factor)
    factors = entry.fetch(:selection).fetch(:factors)
    provider_factors = factors["a"] || factors[:a]
    provider_factors.find do |trace|
      trace.fetch(:factor).to_s == factor
    end.fetch(:raw)
  end

  def route(providers:, weights:, operations: [operation], preferred_amount_ranges: {},
            min_turnovers: {}, rpm_limits: {})
    terminal = provider(
      "spacepayments", priority: 99, traffic_percentage: 0, min: nil, max: nil,
      daily_limit: nil, daily_approved: 0, in_progress_count_limit: nil,
      in_progress_amount_limit: nil, conversion: Rational(1, 1)
    )
    all_providers = providers + [terminal]
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: all_providers, history: [], operations: operations
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: all_providers.map(&:payment_system), weights: weights,
      preferred_amount_ranges: preferred_amount_ranges, min_turnovers: min_turnovers,
      rpm_limits: rpm_limits, terminal_provider_id: terminal.payment_system
    )
    decisions = RubyRouting::Case::Router.new(dataset, configuration: configuration).run
    decisions.map.with_index do |decision, index|
      selected_attempt = decision.attempts.find { |attempt| attempt.decision == :selected }
      {
        selected: decision.selected_provider,
        selection: selected_attempt&.selection,
        operation_id: operations.fetch(index).operation_id
      }
    end
  end

  def operation
    RubyRouting::Case::Operation.new(
      operation_id: "monotonic-operation", created_at: Time.utc(2026, 7, 30, 9), amount: 150,
      bank: "sberbank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def operations(count)
    count.times.map do |index|
      RubyRouting::Case::Operation.new(
        operation_id: "monotonic-#{index}", created_at: Time.utc(2026, 7, 30, 9, 0, index), amount: 150,
        bank: "sberbank", card_brand: nil,
        payout_requisite: { "sbp" => { "phone" => "79000000000" } }
      )
    end
  end

  def provider(id, priority: 1, conversion: Rational(1, 2), min: 1, max: 1_000,
               traffic_percentage: 50, daily_limit: 1_000, daily_approved: 0,
               in_progress_count_limit: 100, in_progress_amount_limit: 100_000)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: traffic_percentage, priority: priority,
      limit_amount_min: min, limit_amount_max: max, daily_amount_limit: daily_limit,
      daily_approved_amount: daily_approved, in_progress_count_limit: in_progress_count_limit, in_progress_count: 0,
      in_progress_amount_limit: in_progress_amount_limit, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: conversion, avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end
end
