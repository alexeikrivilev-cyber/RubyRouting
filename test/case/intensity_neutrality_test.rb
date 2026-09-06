# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseIntensityNeutralityTest < Minitest::Test
  def test_missing_rpm_limit_does_not_claim_maximum_intensity_preference
    providers = [
      provider("a", limit_amount_min: 1),
      provider("z", limit_amount_min: 500),
      provider("spacepayments", traffic_percentage: 0, priority: 99)
    ]
    operations = [
      operation("warm-up", amount: 100),
      operation("candidate", amount: 1_000)
    ]
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: operations
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: providers.map(&:payment_system),
      weights: { intensity: 1 }, rpm_limits: { z: 2 },
      terminal_provider_id: "spacepayments", simulation_mode: :approved
    )

    router = RubyRouting::Case::Router.new(dataset, configuration: configuration)
    decisions = router.run

    assert_equal %w[a a], decisions.map(&:selected_provider)
    traces = decisions.last.attempts.find { |attempt| attempt.status }.selection.fetch(:factors)
    assert_equal Rational(0, 1), traces.fetch("a").first.fetch(:raw)
    assert_includes traces.fetch("a").first.fetch(:reason), "neutral/no intensity preference"
  end

  private

  def provider(id, limit_amount_min: 1, traffic_percentage: 50, priority: 1)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: traffic_percentage, priority: priority,
      limit_amount_min: limit_amount_min, limit_amount_max: 10_000, daily_amount_limit: 100_000,
      daily_approved_amount: 0, in_progress_count_limit: 100, in_progress_count: 0,
      in_progress_amount_limit: 100_000, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def operation(id, amount:)
    RubyRouting::Case::Operation.new(
      operation_id: id, created_at: Time.utc(2026, 7, 30, 9), amount: amount,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end
end
