# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseStateCampaignTest < Minitest::Test
  def provider(id, daily_limit:, daily_approved:, rpm_limit: nil, priority:)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: id == "spacepayments" ? 0 : 50,
      priority: priority, limit_amount_min: id == "spacepayments" ? nil : 1,
      limit_amount_max: id == "spacepayments" ? nil : 100_000,
      daily_amount_limit: daily_limit, daily_approved_amount: daily_approved,
      in_progress_count_limit: id == "spacepayments" ? nil : 10, in_progress_count: 0,
      in_progress_amount_limit: id == "spacepayments" ? nil : 100_000,
      in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(9, 10), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def operation(id, amount, offset)
    RubyRouting::Case::Operation.new(
      operation_id: id, created_at: Time.utc(2026, 7, 30, 9) + offset, amount: amount,
      bank: "sberbank", card_brand: nil, payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def test_later_operation_observes_approved_daily_turnover_and_reselects
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: [
        provider("a", daily_limit: 100, daily_approved: 90, priority: 1),
        provider("b", daily_limit: 1_000, daily_approved: 0, priority: 2),
        provider("spacepayments", daily_limit: nil, daily_approved: 0, priority: 99)
      ],
      history: [], operations: [operation("first", 10, 0), operation("second", 1, 1)]
    )
    router = RubyRouting::Case::Router.new(
      dataset,
      configuration: RubyRouting::Case::CaseConfiguration.new(
        provider_ids: %w[a b spacepayments], terminal_provider_id: "spacepayments"
      )
    )
    decisions = router.run

    assert_equal %w[a b], decisions.map(&:selected_provider)
    assert_equal 100, router.state.fetch("a").daily_approved_amount
    assert_equal :daily_amount_limit, decisions.last.attempts.find { |attempt| attempt.provider == "a" }.reason.to_sym
    assert_operator router.state.fetch("a").daily_approved_amount, :<=, 100
  end

  def test_rpm_gate_is_reapplied_to_the_next_operation_at_same_provider
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: [
        provider("a", daily_limit: 1_000, daily_approved: 0, rpm_limit: 1, priority: 1),
        provider("b", daily_limit: 1_000, daily_approved: 0, priority: 2),
        provider("spacepayments", daily_limit: nil, daily_approved: 0, priority: 99)
      ],
      history: [], operations: [operation("first", 10, 0), operation("second", 10, 30)]
    )
    router = RubyRouting::Case::Router.new(
      dataset,
      configuration: RubyRouting::Case::CaseConfiguration.new(
        provider_ids: %w[a b spacepayments], rpm_limits: { a: 1 }, terminal_provider_id: "spacepayments"
      )
    )
    decisions = router.run

    assert_equal %w[a b], decisions.map(&:selected_provider)
    assert_equal "rpm_limit", decisions.last.attempts.find { |attempt| attempt.provider == "a" }.reason
  end
end
