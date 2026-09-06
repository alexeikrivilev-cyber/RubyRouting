# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseAmountBandNeutralityTest < Minitest::Test
  def provider(id, priority:)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: 50, priority: priority,
      limit_amount_min: 1, limit_amount_max: 10_000, daily_amount_limit: 1_000_000,
      daily_approved_amount: 0, in_progress_count_limit: 100, in_progress_count: 0,
      in_progress_amount_limit: 1_000_000, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def operation
    RubyRouting::Case::Operation.new(
      operation_id: "missing-band", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def test_missing_preferred_band_is_neutral_instead_of_maximum_preference
    states = [provider("a", priority: 0), provider("b", priority: 1)].map do |item|
      RubyRouting::Case::ProviderCaseState.new(item)
    end
    resolver = RubyRouting::Case::ConflictResolver.new(
      weights: { amount: 1 }, preferred_amount_ranges: { a: { min: 1_000, max: 1_000 } }
    )
    ledger = RubyRouting::Case::TrafficLedger.new(%w[a b])

    resolution = resolver.resolve(
      candidates: states, normalization_candidates: states,
      operation: operation, traffic: ledger, as_of: operation.created_at
    )

    assert_equal "a", resolution.selected_provider
    assert_equal Rational(0, 1), resolution.traces.fetch("a").first.raw
    assert_equal Rational(0, 1), resolution.traces.fetch("b").first.raw
    assert_equal Rational(0, 1), resolution.traces.fetch("a").first.contribution
    assert_includes resolution.traces.fetch("b").first.reason, "non-discriminating"
  end
end
