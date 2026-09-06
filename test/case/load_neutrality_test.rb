# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseLoadNeutralityTest < Minitest::Test
  def test_missing_capacity_limits_are_neutral_instead_of_maximum_headroom
    terminal = provider("spacepayments", traffic: 0, daily_limit: nil, count_limit: nil, amount_limit: nil)
    providers = [
      provider("a", daily_limit: nil, count_limit: nil, amount_limit: nil),
      provider("b", daily_limit: 1_000, count_limit: 100, amount_limit: 10_000),
      terminal
    ]
    operation = RubyRouting::Case::Operation.new(
      operation_id: "missing-load-capacity", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: providers.map(&:payment_system), weights: { load: 1 },
      terminal_provider_id: "spacepayments"
    )

    router = RubyRouting::Case::Router.new(dataset, configuration: configuration)
    decision = router.run.fetch(0)
    selected_attempt = decision.attempts.find(&:status)
    load_evidence = selected_attempt.selection.fetch(:factors).transform_values do |values|
      values.find { |value| value.fetch(:factor) == "load" }
    end

    assert_equal "a", decision.selected_provider
    assert_equal Rational(0, 1), load_evidence.fetch("a").fetch(:raw)
    assert_includes load_evidence.fetch("a").fetch(:reason), "neutral/no load preference"
    assert_operator load_evidence.fetch("b").fetch(:raw), :>, Rational(0, 1)
    assert_equal Rational(0, 1), load_evidence.fetch("b").fetch(:contribution)
  end

  def test_missing_capacity_dimensions_are_neutral_in_partial_configuration
    terminal = provider("spacepayments", traffic: 0, daily_limit: nil, count_limit: nil, amount_limit: nil)
    providers = [
      provider("a", daily_limit: 10_000, count_limit: nil, amount_limit: nil),
      provider("b", daily_limit: 1_000, count_limit: 100, amount_limit: 10_000),
      terminal
    ]
    operation = RubyRouting::Case::Operation.new(
      operation_id: "partial-load-capacity", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: providers.map(&:payment_system), weights: { load: 1 },
      terminal_provider_id: "spacepayments"
    )

    router = RubyRouting::Case::Router.new(dataset, configuration: configuration)
    decision = router.run.fetch(0)
    selected_attempt = decision.attempts.find(&:status)
    load_evidence = selected_attempt.selection.fetch(:factors).transform_values do |values|
      values.find { |value| value.fetch(:factor) == "load" }
    end

    assert_equal "a", decision.selected_provider
    assert_equal Rational(99, 100), load_evidence.fetch("a").fetch(:raw)
    assert_equal Rational(24, 25), load_evidence.fetch("b").fetch(:raw)
  end

  private

  def provider(id, traffic: 50, daily_limit:, count_limit:, amount_limit:)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: traffic, priority: 1,
      limit_amount_min: 1, limit_amount_max: 10_000,
      daily_amount_limit: daily_limit, daily_approved_amount: 0,
      in_progress_count_limit: count_limit, in_progress_count: 0,
      in_progress_amount_limit: amount_limit, in_progress_amount: 0,
      available_requisites: 10, conversion_24h: Rational(1, 2), avg_latency_sec: 1,
      banks: [], exclude_banks: false, provider_margin_pct: 1,
      merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end
end
