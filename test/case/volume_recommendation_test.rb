# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseVolumeRecommendationTest < Minitest::Test
  def test_small_volume_target_gap_is_reported_as_whole_operation_granularity
    providers = [
      provider("a", priority: 1),
      provider("b", priority: 2),
      provider("spacepayments", priority: 99, traffic_percentage: 0)
    ]
    operation = RubyRouting::Case::Operation.new(
      operation_id: "volume-granularity", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: providers.map(&:payment_system),
      count_share: { a: 1, b: 0, "spacepayments" => 0 },
      volume_share: { a: Rational(1, 2), b: Rational(1, 2), "spacepayments" => 0 }
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: providers.map(&:payment_system), targets: targets,
      weights: { priority: 1 }, terminal_provider_id: "spacepayments"
    )

    router = RubyRouting::Case::Router.new(dataset, configuration: configuration)
    decisions = router.run
    report = RubyRouting::Case::ReportBuilder.new(
      dataset, router.state, router.traffic, router.configuration, decisions,
      attempt_ledger: router.attempt_ledger, settlement_ledger: router.settlement_ledger
    ).call.to_h
    detail = report.fetch(:recommendation_details).find do |candidate|
      candidate[:kind] == "volume_workload_granularity" && candidate[:provider] == "b"
    end

    refute_nil detail
    assert_equal Rational(50, 1), detail.fetch(:evidence).fetch(:target_volume)
    assert_equal 0, detail.fetch(:evidence).fetch(:actual_volume)
    assert_equal 100, detail.fetch(:evidence).fetch(:minimum_operation_amount)
    refute(
      report.fetch(:recommendation_details).any? do |candidate|
        candidate[:kind] == "volume_target_unmet" && candidate[:provider] == "b"
      end
    )
    assert report.fetch(:recommendations).any? { |text| text.include?("volume target") && text.include?("whole-operation granularity") }
  end

  def test_unreachable_volume_target_reports_bounded_subset_sum_evidence
    providers = [
      provider("a", priority: 1),
      provider("b", priority: 2),
      provider("spacepayments", priority: 99, traffic_percentage: 0)
    ]
    operations = [70, 30].each_with_index.map do |amount, index|
      RubyRouting::Case::Operation.new(
        operation_id: "subset-sum-#{index}", created_at: Time.utc(2026, 7, 30, 9) + index,
        amount: amount, bank: "bank", card_brand: nil,
        payout_requisite: { "sbp" => { "phone" => "79000000000" } }
      )
    end
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: operations
    )
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: providers.map(&:payment_system),
      count_share: { a: 1, b: 0, "spacepayments" => 0 },
      volume_share: { a: Rational(1, 2), b: Rational(1, 2), "spacepayments" => 0 }
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: providers.map(&:payment_system), targets: targets,
      weights: { priority: 1 }, terminal_provider_id: "spacepayments"
    )

    router = RubyRouting::Case::Router.new(dataset, configuration: configuration)
    decisions = router.run
    report = RubyRouting::Case::ReportBuilder.new(
      dataset, router.state, router.traffic, router.configuration, decisions,
      attempt_ledger: router.attempt_ledger, settlement_ledger: router.settlement_ledger
    ).call.to_h
    detail = report.fetch(:recommendation_details).find do |candidate|
      candidate[:kind] == "volume_subset_sum_granularity" && candidate[:provider] == "b"
    end

    refute_nil detail
    evidence = detail.fetch(:evidence)
    assert_equal 50, evidence.fetch(:target_volume)
    assert_equal 30, evidence.fetch(:nearest_attainable_volume_below)
    assert_equal 70, evidence.fetch(:nearest_attainable_volume_above)
    refute report.fetch(:recommendation_details).any? { |candidate|
      candidate[:kind] == "volume_target_unmet" && candidate[:provider] == "b"
    }
    assert_includes report.fetch(:recommendations).join(" "), "not reachable"
  end

  private

  def provider(id, priority:, traffic_percentage: 50)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: traffic_percentage, priority: priority,
      limit_amount_min: 1, limit_amount_max: 10_000, daily_amount_limit: 100_000,
      daily_approved_amount: 0, in_progress_count_limit: 100, in_progress_count: 0,
      in_progress_amount_limit: 100_000, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end
end
