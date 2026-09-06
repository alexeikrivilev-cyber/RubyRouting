# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseTerminalIdentityTest < Minitest::Test
  def test_multiple_zero_participation_providers_require_explicit_terminal_identity
    providers = [provider("zero-provider", traffic: 0), provider("spacepayments", traffic: 0)]
    operation = RubyRouting::Case::Operation.new(
      operation_id: "terminal-identity", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Router.new(dataset).run
    end

    assert_includes error.message, "terminal provider"
    assert_includes error.message, "explicitly configured"
  end

  private

  def provider(id, traffic:)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: traffic, priority: 1,
      limit_amount_min: nil, limit_amount_max: nil, daily_amount_limit: nil,
      daily_approved_amount: 0, in_progress_count_limit: nil, in_progress_count: 0,
      in_progress_amount_limit: nil, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end
end
