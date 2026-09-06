# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseStrategyCampaignTest < Minitest::Test
  def provider(id, traffic: 50, priority: 1)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: traffic, priority: priority,
      limit_amount_min: 1, limit_amount_max: 10_000, daily_amount_limit: 10_000_000,
      daily_approved_amount: 0, in_progress_count_limit: 100, in_progress_count: 0,
      in_progress_amount_limit: 10_000_000, in_progress_amount: 0,
      available_requisites: 100, conversion_24h: Rational(9, 10), avg_latency_sec: 1,
      banks: [], exclude_banks: false, provider_margin_pct: 1,
      merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def dataset
    operations = [100, 100, 1_000, 1_000].each_with_index.map do |amount, index|
      RubyRouting::Case::Operation.new(
        operation_id: "strategy-#{index}", created_at: Time.utc(2026, 7, 30, 9) + index,
        amount: amount, bank: "sberbank", card_brand: nil,
        payout_requisite: { "sbp" => { "phone" => "79000000000" } }
      )
    end
    RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: [provider("a"), provider("b"), provider("spacepayments", traffic: 0, priority: 99)],
      history: [], operations: operations
    )
  end

  def config(weight, targets)
    RubyRouting::Case::CaseConfiguration.new(
      provider_ids: %w[a b spacepayments], targets: targets, weights: { weight => 1 },
      terminal_provider_id: "spacepayments"
    )
  end

  def test_count_and_volume_strategies_use_fresh_runtimes_and_change_only_strategy
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: %w[a b spacepayments],
      count_share: { a: Rational(1, 2), b: Rational(1, 2) },
      volume_share: { a: Rational(1, 10), b: Rational(9, 10) }
    )
    count_run = RubyRouting::Case::Router.new(dataset, configuration: config(:count, targets))
    volume_run = RubyRouting::Case::Router.new(dataset, configuration: config(:volume, targets))
    count_decisions = count_run.run
    volume_decisions = volume_run.run

    refute_equal count_run.traffic.volume_by_provider, volume_run.traffic.volume_by_provider
    assert_equal [2, 2], [count_run.traffic.count_by_provider.fetch("a"), count_run.traffic.count_by_provider.fetch("b")]
    assert_equal count_decisions.map(&:operation_id), volume_decisions.map(&:operation_id)
    refute_equal count_decisions.map(&:selected_provider), volume_decisions.map(&:selected_provider)
    assert_equal 4, count_run.traffic.total_count
    assert_equal 4, volume_run.traffic.total_count
    assert_equal count_run.traffic.total_volume, volume_run.traffic.total_volume
  end
end
