# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseTerminalCausalityTest < Minitest::Test
  def provider(id, traffic:, priority:, banks: [], status: "active")
    RubyRouting::Case::Provider.new(
      payment_system: id, status: status, traffic_percentage: traffic, priority: priority,
      limit_amount_min: 1, limit_amount_max: 10_000, daily_amount_limit: 1_000_000,
      daily_approved_amount: 0, in_progress_count_limit: 10, in_progress_count: 0,
      in_progress_amount_limit: 1_000_000, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: banks, exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def operation(id: "terminal-probe")
    RubyRouting::Case::Operation.new(
      operation_id: id, created_at: Time.utc(2026, 7, 30, 9), amount: 100, bank: "bank",
      card_brand: nil, payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def dataset(terminal_id: "spacepayments")
    RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: [
        provider("a", traffic: 50, priority: 1, banks: ["other"]),
        provider("b", traffic: 50, priority: 2, banks: ["other"]),
        provider(terminal_id, traffic: 0, priority: 99),
        provider(terminal_id == "spacepayments" ? "zero-provider" : "spacepayments", traffic: 0, priority: 100, status: "enabled")
      ],
      history: [], operations: [operation]
    )
  end

  def configuration(dataset, terminal_id)
    RubyRouting::Case::CaseConfiguration.new(
      provider_ids: dataset.providers.map(&:payment_system), weights: { priority: 1 },
      terminal_provider_id: terminal_id
    )
  end

  def report_for(dataset, terminal_id)
    router = RubyRouting::Case::Router.new(dataset, configuration: configuration(dataset, terminal_id))
    decisions = router.run
    RubyRouting::Case::ReportBuilder.new(
      dataset, router.state, router.traffic, router.configuration, decisions,
      attempt_ledger: router.attempt_ledger, settlement_ledger: router.settlement_ledger
    ).call.to_h
  end

  def test_direct_terminal_deviation_explains_safety_fallback_and_excluded_alternatives
    report = report_for(dataset, "spacepayments")

    causes = report.fetch(:deviation_causes).fetch("spacepayments")
    detail = report.fetch(:recommendation_details).find do |candidate|
      candidate[:kind] == "terminal_fallback_deviation"
    end

    assert_equal 1, causes.fetch(:terminal_fallback_assignments)
    refute_nil detail
    assert_equal 1, detail.fetch(:evidence).fetch(:terminal_fallback_assignments)
    assert_equal({ "bank_not_in_list" => 2, "inactive_provider" => 1 }, detail.fetch(:evidence).fetch(:hard_excluded_alternatives))
    assert_includes detail.fetch(:action), "terminal fallback"
    assert report.fetch(:recommendations).any? { |text| text.include?("terminal fallback") }
  end

  def test_terminal_identity_is_explicit_and_zero_provider_is_not_an_external_candidate
    dataset = dataset(terminal_id: "zero-provider")
    report = report_for(dataset, "zero-provider")

    assert_equal 1, report.fetch(:deviation_causes).fetch("zero-provider").fetch(:terminal_fallback_assignments)
    assert_equal 1, report.fetch(:distribution).fetch("zero-provider").fetch(:count)
  end
end
