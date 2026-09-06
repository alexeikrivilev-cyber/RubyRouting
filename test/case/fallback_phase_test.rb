# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseFallbackPhaseTest < Minitest::Test
  def provider(id, priority, traffic: 30)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: traffic, priority: priority,
      limit_amount_min: 1, limit_amount_max: 100_000, daily_amount_limit: 1_000_000,
      daily_approved_amount: 0, in_progress_count_limit: 100, in_progress_count: 0,
      in_progress_amount_limit: 1_000_000, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def operation
    RubyRouting::Case::Operation.new(
      operation_id: "fallback-phase", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def dataset
    RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: [provider("a", 0), provider("b", 9), provider("c", 1), provider("spacepayments", 99, traffic: 0)],
      history: [], operations: [operation]
    )
  end

  def test_rejected_primary_uses_independent_fallback_ranking_without_phantom_allocation
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: %w[a b c spacepayments],
      count_share: { a: Rational(4, 10), b: Rational(4, 10), c: Rational(2, 10) },
      volume_share: { a: Rational(4, 10), b: Rational(4, 10), c: Rational(2, 10) }
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: %w[a b c spacepayments], targets: targets,
      weights: { count: 10, volume: 10, priority: 1 }, terminal_provider_id: "spacepayments"
    )
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: { ["fallback-phase", "a"] => :rejected }
    )
    router = RubyRouting::Case::Router.new(dataset, configuration: configuration, simulator: simulator)
    decision = router.run.fetch(0)

    assert_equal "c", decision.selected_provider
    assert_equal %w[a c], decision.attempts.map(&:provider)
    assert_equal ["provider_rejected", "fallback_highest_composite_score"], decision.attempts.map(&:reason)
    assert_equal 1, router.traffic.count_by_provider.fetch("a")
    assert_equal 0, router.traffic.count_by_provider.fetch("c")
    assert_equal 1, router.attempt_ledger.count_by_provider.fetch("a")
    assert_equal 1, router.attempt_ledger.count_by_provider.fetch("c")
    assert_equal 1, router.settlement_ledger.count_by_provider.fetch("c")
    assert_equal 0, router.settlement_ledger.count_by_provider.fetch("a")
    assert RubyRouting::Case::StrictValidator.new(
      RubyRouting::Case::Run.new(
        dataset: dataset, state: router.state, traffic: router.traffic,
        configuration: router.configuration, simulator: router.simulator,
        resolver: router.resolver, decisions: [decision], report: RubyRouting::Case::ReportBuilder.new(
          dataset, router.state, router.traffic, router.configuration, [decision],
          attempt_ledger: router.attempt_ledger, settlement_ledger: router.settlement_ledger
        ).call,
        attempt_ledger: router.attempt_ledger, settlement_ledger: router.settlement_ledger
      )
    ).call.valid?
  end

  def test_independent_expected_fallback_is_lower_priority_c_not_legacy_counterfactual_b
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: %w[a b c],
      count_share: { a: Rational(4, 10), b: Rational(4, 10), c: Rational(2, 10) },
      volume_share: { a: Rational(4, 10), b: Rational(4, 10), c: Rational(2, 10) }
    )
    ledger = RubyRouting::Case::TrafficLedger.new(%w[a b c], targets: targets)
    ledger.record_assignment!(provider_id: "a", amount: operation.amount)
    states = [provider("b", 9), provider("c", 1)].map { |item| RubyRouting::Case::ProviderCaseState.new(item) }
    resolver = RubyRouting::Case::ConflictResolver.new(weights: { count: 10, volume: 10, priority: 1 })

    legacy_counterfactual = resolver.resolve(
      candidates: states, operation: operation, traffic: ledger, as_of: operation.created_at
    )
    fallback_resolution = resolver.resolve(
      candidates: states, operation: operation, traffic: ledger, as_of: operation.created_at, phase: :fallback
    )

    expected_fallback_provider = "c" # lower official priority rank: c=1, b=9
    assert_equal expected_fallback_provider, fallback_resolution.selected_provider
    assert_equal "b", legacy_counterfactual.selected_provider
    assert_equal :fallback, fallback_resolution.phase
  end
end
