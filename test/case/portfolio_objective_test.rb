# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCasePortfolioObjectiveTest < Minitest::Test
  def provider(id)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: 1, priority: 1,
      limit_amount_min: 1, limit_amount_max: 10_000, daily_amount_limit: 10_000,
      daily_approved_amount: 0, in_progress_count_limit: 100, in_progress_count: 0,
      in_progress_amount_limit: 10_000, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def test_count_and_volume_choose_the_lowest_post_decision_portfolio_loss
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: %w[a b c],
      count_share: { a: 0, b: Rational(1, 5), c: Rational(4, 5) },
      volume_share: { a: 0, b: Rational(1, 5), c: Rational(4, 5) }
    )
    traffic = RubyRouting::Case::TrafficLedger.new(%w[a b c], targets: targets)
    2.times { traffic.record_assignment!(provider_id: "c", amount: 1) }
    operation = RubyRouting::Case::Operation.new(
      operation_id: "portfolio-objective", created_at: Time.utc(2026, 7, 30, 9), amount: 2,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    states = %w[a b c].map { |id| RubyRouting::Case::ProviderCaseState.new(provider(id)) }

    resolution = RubyRouting::Case::ConflictResolver.new(weights: { count: 1, volume: 1 }).resolve(
      candidates: states, normalization_candidates: states,
      operation: operation, traffic: traffic, as_of: operation.created_at
    )

    losses = {
      "a" => Rational(53, 30),
      "b" => Rational(13, 15),
      "c" => Rational(4, 5)
    }
    assert_equal Rational(2, 3), traffic.post_decision_loss(measure: :count, provider_id: "a", amount: 2)
    assert_equal Rational(4, 15), traffic.post_decision_loss(measure: :count, provider_id: "b", amount: 2)
    assert_equal Rational(2, 5), traffic.post_decision_loss(measure: :count, provider_id: "c", amount: 2)
    assert_equal Rational(1, 1), traffic.post_decision_loss(measure: :volume, provider_id: "a", amount: 2)
    assert_equal Rational(3, 5), traffic.post_decision_loss(measure: :volume, provider_id: "b", amount: 2)
    assert_equal Rational(2, 5), traffic.post_decision_loss(measure: :volume, provider_id: "c", amount: 2)
    assert_equal "c", losses.min_by { |provider_id, loss| [loss, provider_id] }.first
    assert_equal "c", resolution.selected_provider
  end
end
