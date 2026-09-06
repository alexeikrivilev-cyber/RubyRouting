# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseFallbackOrderInvarianceTest < Minitest::Test
  PROVIDER_IDS = %w[a b c spacepayments].freeze

  def test_rejected_primary_fallback_is_invariant_to_provider_enumeration_order
    canonical = run_with(PROVIDER_IDS)
    reversed = run_with(PROVIDER_IDS.reverse)

    assert_equal canonical, reversed
    assert_equal %w[a c], canonical.fetch(:attempts).map { |attempt| attempt.fetch(:provider) }
    assert_equal "c", canonical.fetch(:selected_provider)
    assert_equal({ "a" => 0, "b" => 0, "c" => 1, "spacepayments" => 0 },
      canonical.fetch(:assignment_counts))
    assert_equal({ "a" => 1, "b" => 0, "c" => 0, "spacepayments" => 0 },
      canonical.fetch(:primary_assignment_counts))
    assert_equal({ "a" => 1, "b" => 0, "c" => 1, "spacepayments" => 0 },
      canonical.fetch(:attempt_counts))
    assert_equal({ "a" => 0, "b" => 0, "c" => 1, "spacepayments" => 0 },
      canonical.fetch(:settlement_counts))
  end

  private

  def run_with(provider_ids)
    providers = provider_ids.map { |provider_id| provider(provider_id) }
    operation = RubyRouting::Case::Operation.new(
      operation_id: "fallback-order", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: PROVIDER_IDS,
      count_share: { a: Rational(3, 10), b: Rational(3, 10), c: Rational(4, 10), spacepayments: 0 },
      volume_share: { a: Rational(3, 10), b: Rational(3, 10), c: Rational(4, 10), spacepayments: 0 }
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: PROVIDER_IDS, targets: targets,
      weights: { priority: 1, conversion_24h: 2, load: 1 }, terminal_provider_id: "spacepayments"
    )
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: { [operation.operation_id, "a"] => :rejected, [operation.operation_id, "c"] => :approved }
    )
    router = RubyRouting::Case::Router.new(dataset, configuration: configuration, simulator: simulator)
    decision = router.run.fetch(0)

    {
      attempts: decision.attempts.select(&:attempted?).map do |attempt|
        {
          provider: attempt.provider,
          decision: attempt.decision,
          reason: attempt.reason,
          status: attempt.status,
          selection_reason: attempt.selection_reason,
          selection: attempt.selection
        }
      end,
      selected_provider: decision.selected_provider,
      assignment_counts: router.traffic.count_by_provider,
      primary_assignment_counts: router.primary_assignment_ledger.count_by_provider,
      attempt_counts: router.attempt_ledger.count_by_provider,
      settlement_counts: router.settlement_ledger.count_by_provider
    }
  end

  def provider(provider_id)
    terminal = provider_id == "spacepayments"
    RubyRouting::Case::Provider.new(
      payment_system: provider_id, status: "active", traffic_percentage: terminal ? 0 : 33,
      priority: { "a" => 0, "b" => 9, "c" => 1, "spacepayments" => 99 }.fetch(provider_id),
      limit_amount_min: terminal ? nil : 1, limit_amount_max: terminal ? nil : 100_000,
      daily_amount_limit: terminal ? nil : 1_000_000, daily_approved_amount: 0,
      in_progress_count_limit: terminal ? nil : 100, in_progress_count: 0,
      in_progress_amount_limit: terminal ? nil : 1_000_000, in_progress_amount: 0,
      available_requisites: 10, conversion_24h: Rational(1, 1), avg_latency_sec: 1,
      banks: [], exclude_banks: false, provider_margin_pct: 1,
      merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end
end
