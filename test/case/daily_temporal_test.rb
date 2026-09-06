# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseDailyTemporalTest < Minitest::Test
  def provider(id, priority:, traffic:, daily_limit:, daily_approved:)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: traffic, priority: priority,
      limit_amount_min: 1, limit_amount_max: 1_000, daily_amount_limit: daily_limit,
      daily_approved_amount: daily_approved, in_progress_count_limit: 100, in_progress_count: 0,
      in_progress_amount_limit: 10_000, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def operation(id, created_at)
    RubyRouting::Case::Operation.new(
      operation_id: id, created_at: created_at, amount: 10, bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def dataset
    RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 12), gateway: "gateway", merchant: "merchant",
      providers: [
        provider("a", priority: 0, traffic: 50, daily_limit: 100, daily_approved: 90),
        provider("b", priority: 1, traffic: 50, daily_limit: 1_000, daily_approved: 0),
        provider("spacepayments", priority: 99, traffic: 0, daily_limit: nil, daily_approved: 0)
      ],
      history: [],
      operations: [
        operation("day-1", Time.utc(2026, 7, 30, 23, 59)),
        operation("day-2", Time.utc(2026, 7, 31, 0, 1))
      ]
    )
  end

  def test_daily_limit_rolls_to_the_operation_date_after_midnight
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: %w[a b spacepayments], weights: { priority: 1 }, terminal_provider_id: "spacepayments"
    )
    router = RubyRouting::Case::Router.new(dataset, configuration: configuration)

    decisions = router.run

    assert_equal %w[a a], decisions.map(&:selected_provider)
    assert_equal 10, router.state.fetch("a").daily_approved_amount
    assert_equal "2026-07-31", router.state.fetch("a").daily_date

    report = RubyRouting::Case::ReportBuilder.new(
      dataset, router.state, router.traffic, router.configuration, decisions,
      attempt_ledger: router.attempt_ledger, settlement_ledger: router.settlement_ledger
    ).call
    assert_equal 10, report.to_h.fetch(:projected_daily_utilization).fetch("a").fetch(:used)
    run = RubyRouting::Case::Run.new(
      dataset: dataset, state: router.state, traffic: router.traffic,
      configuration: router.configuration, simulator: router.simulator,
      resolver: router.resolver, decisions: decisions, report: report,
      attempt_ledger: router.attempt_ledger, settlement_ledger: router.settlement_ledger
    )
    assert RubyRouting::Case::StrictValidator.new(run).call.valid?
  end
end
