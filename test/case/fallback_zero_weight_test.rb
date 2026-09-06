# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseFallbackZeroWeightTest < Minitest::Test
  ZERO_WEIGHT_FACTORS = %i[count volume amount conversion_24h load intensity turnover_min].freeze

  def test_zero_weight_factor_is_inert_on_the_canonical_fallback_path
    baseline = route(weights: { priority: 1 })

    ZERO_WEIGHT_FACTORS.each do |factor|
      with_disabled_factor = route(weights: { priority: 1, factor => 0 })

      assert_equal baseline.fetch(:selected), with_disabled_factor.fetch(:selected), factor
      assert_equal baseline.fetch(:providers), with_disabled_factor.fetch(:providers), factor
      assert_equal baseline.fetch(:scores), with_disabled_factor.fetch(:scores), factor
      assert_equal baseline.fetch(:reasons), with_disabled_factor.fetch(:reasons), factor

      with_disabled_factor.fetch(:fallback_selection).fetch(:factors).each_value do |traces|
        trace = traces.find { |entry| entry.fetch(:factor).to_sym == factor }
        refute_nil trace, factor
        assert_equal 0, trace.fetch(:weight), factor
        assert_equal Rational(0, 1), trace.fetch(:contribution), factor
      end
    end
  end

  private

  def route(weights:)
    operation = RubyRouting::Case::Operation.new(
      operation_id: "fallback-zero-weight",
      created_at: Time.utc(2026, 7, 30, 9),
      amount: 100,
      bank: "bank",
      card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    providers = [
      provider("a", priority: 0, traffic: 30),
      provider("b", priority: 9, traffic: 30),
      provider("c", priority: 1, traffic: 30),
      provider("spacepayments", priority: 99, traffic: 0, terminal: true)
    ]
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8),
      gateway: "gateway",
      merchant: "merchant",
      providers: providers,
      history: [],
      operations: [operation]
    )
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: providers.map(&:payment_system),
      count_share: { a: Rational(1, 3), b: Rational(1, 3), c: Rational(1, 3), spacepayments: 0 },
      volume_share: { a: Rational(1, 3), b: Rational(1, 3), c: Rational(1, 3), spacepayments: 0 }
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: providers.map(&:payment_system),
      targets: targets,
      weights: weights,
      terminal_provider_id: "spacepayments"
    )
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: { [operation.operation_id, "a"] => :rejected }
    )
    router = RubyRouting::Case::Router.new(dataset, configuration: configuration, simulator: simulator)
    decision = router.run.fetch(0)
    selections = decision.attempts.filter_map do |attempt|
      next unless attempt.selection

      {
        provider: attempt.provider,
        phase: attempt.selection.fetch(:phase),
        reason: attempt.selection_reason,
        scores: attempt.selection.fetch(:scores),
        factors: attempt.selection.fetch(:factors)
      }
    end

    {
      selected: decision.selected_provider,
      providers: decision.attempts.map(&:provider),
      reasons: decision.attempts.map(&:reason),
      scores: selections.to_h { |selection| [selection.fetch(:phase), selection.fetch(:scores)] },
      fallback_selection: selections.find { |selection| selection.fetch(:phase) == "fallback" }
    }
  end

  def provider(id, priority:, traffic:, terminal: false)
    RubyRouting::Case::Provider.new(
      payment_system: id,
      status: "active",
      traffic_percentage: traffic,
      priority: priority,
      limit_amount_min: terminal ? nil : 1,
      limit_amount_max: terminal ? nil : 10_000,
      daily_amount_limit: terminal ? nil : 1_000_000,
      daily_approved_amount: 0,
      in_progress_count_limit: terminal ? nil : 100,
      in_progress_count: 0,
      in_progress_amount_limit: terminal ? nil : 1_000_000,
      in_progress_amount: 0,
      available_requisites: 10,
      conversion_24h: Rational(1, 1),
      avg_latency_sec: 1,
      banks: [],
      exclude_banks: false,
      provider_margin_pct: terminal ? 0 : 1,
      merchant_margin_pct: 1,
      allow_negative_agreement: false
    )
  end
end
