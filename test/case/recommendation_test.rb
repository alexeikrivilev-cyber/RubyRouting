# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseRecommendationTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_near_daily_limit_has_quantitative_recommendation
    run = RubyRouting::Case::Runner.new.call
    details = run.report.to_h.fetch(:recommendation_details)
    near_limit = details.find { |detail| detail[:kind] == "daily_utilization_near_limit" }

    refute_nil near_limit
    assert_equal "payflow", near_limit.fetch(:provider)
    assert_equal 2_988_800, near_limit.fetch(:evidence).fetch(:used)
    assert_equal 3_000_000, near_limit.fetch(:evidence).fetch(:limit)
    assert_equal 11_200, near_limit.fetch(:evidence).fetch(:remaining)
    assert_includes near_limit.fetch(:action), "11200"
    assert run.report.to_h.fetch(:recommendations).any? { |text| text.include?("payflow") && text.include?("daily limit") }
  end

  def test_structural_under_target_exposes_observed_hard_exclusion_causes
    run = RubyRouting::Case::Runner.new.call
    detail = run.report.to_h.fetch(:recommendation_details).find do |candidate|
      candidate[:kind] == "structurally_constrained_under_target" && candidate[:provider] == "payflow"
    end

    refute_nil detail
    evidence = detail.fetch(:evidence)
    assert_operator evidence.fetch(:hard_excluded_operations), :>, 0
    assert_includes evidence.fetch(:hard_exclusion_reasons).keys, "bank_not_in_list"
    assert_includes detail.fetch(:action), "coverage"
  end

  def test_small_workload_mismatch_is_reported_as_granularity_not_infeasibility
    operation = RubyRouting::Case::Operation.new(
      operation_id: "one-operation", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    providers = [provider("a", priority: 1), provider("b", priority: 2), provider("spacepayments", priority: 99, traffic: 0)]
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: providers.map(&:payment_system),
      count_share: { a: Rational(1, 2), b: Rational(1, 2) },
      volume_share: { a: Rational(1, 2), b: Rational(1, 2) }
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
      candidate[:kind] == "workload_granularity" && candidate[:provider] == "b"
    end

    refute_nil detail
    assert_equal Rational(1, 2), detail.fetch(:evidence).fetch(:target_count)
    assert_equal 0, detail.fetch(:evidence).fetch(:actual_count)
    assert_empty report.fetch(:infeasibility)
    assert report.fetch(:recommendations).any? { |text| text.include?("whole-operation granularity") }
  end

  def test_hard_exclusion_does_not_masquerade_as_workload_granularity
    operation = RubyRouting::Case::Operation.new(
      operation_id: "excluded-operation", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    providers = [
      provider("a", priority: 1),
      provider("b", priority: 2).then do |value|
        RubyRouting::Case::Provider.new(**value.to_h.merge(banks: ["other"]))
      end,
      provider("spacepayments", priority: 99, traffic: 0)
    ]
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: providers.map(&:payment_system),
      count_share: { a: Rational(1, 2), b: Rational(1, 2) },
      volume_share: { a: Rational(1, 2), b: Rational(1, 2) }
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
      candidate[:kind] == "structurally_constrained_under_target" && candidate[:provider] == "b"
    end
    refute_nil detail
    granularity_details = report.fetch(:recommendation_details).select do |candidate|
      candidate[:kind] == "workload_granularity"
    end
    assert_empty granularity_details
  end

  private

  def provider(id, priority:, traffic: 50)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: traffic, priority: priority,
      limit_amount_min: 1, limit_amount_max: 100_000, daily_amount_limit: 1_000_000,
      daily_approved_amount: 0, in_progress_count_limit: 10, in_progress_count: 0,
      in_progress_amount_limit: 1_000_000, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end
end
