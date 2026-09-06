# frozen_string_literal: true

require "open3"
require "rbconfig"
require_relative "../test_helper"

class AuthoritativeCaseEvidenceCliTest < Minitest::Test
  ROOT = File.expand_path("../../", __dir__)
  FACTORS = %w[count volume priority amount conversion_24h load intensity turnover_min].freeze

  def evidence
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, File.join(ROOT, "bin/ruby_routing_case_evidence"), chdir: ROOT
    )
    assert status.success?, stderr
    JSON.parse(stdout)
  end

  def test_evidence_cli_exposes_every_typed_factor_through_case_resolver
    payload = evidence
    policy = payload.fetch("canonical_submission_policy")
    source_profile = JSON.parse(File.read(File.join(ROOT, "data/submission_profile.json")))

    assert_equal "RubyRouting::Case::ConflictResolver", payload.fetch("engine")
    assert_equal source_profile.fetch("profile_id"), policy.fetch("profile_id")
    assert_equal source_profile.fetch("source"), policy.fetch("source")
    assert_equal source_profile.fetch("revision"), policy.fetch("revision")
    assert_equal source_profile.fetch("count_target_source"), policy.fetch("count_target_source")
    assert_equal source_profile.fetch("volume_target_source"), policy.fetch("volume_target_source")
    assert_equal source_profile.fetch("weights"), policy.fetch("configuration").fetch("weights")
    assert_equal policy.fetch("source"), policy.fetch("configuration").fetch("source")
    assert_equal policy.fetch("revision"), policy.fetch("configuration").fetch("revision")
    assert_equal({
      "factors" => "synthetic_case_inputs",
      "multi_goal_conflict" => "synthetic_case_inputs",
      "router_multi_goal_conflict" => "canonical_case_data + synthetic_weights",
      "router_optional_factor_conflicts" => "synthetic_case_data + synthetic_weights",
      "router_provider_boundary" => "synthetic_provider_extensibility + provider_traffic_targets",
      "portfolio_conflict" => "synthetic_case_configurations",
      "fallback_and_analytics" => "canonical_submission_profile"
    }, policy.fetch("scenario_policy_scope"))
    assert_equal FACTORS, payload.fetch("factors").keys
    payload.fetch("factors").each_value do |factor_case|
      refute_empty factor_case.fetch("configured_weights")
      refute_empty factor_case.fetch("selected_provider")
      refute_empty factor_case.fetch("factors").values.flatten
      factor_case.fetch("factors").values.flatten.each do |trace|
        assert trace.key?("raw")
        assert trace.key?("normalized")
        assert trace.key?("weight")
        assert trace.key?("contribution")
      end
    end
    assert_equal "a", payload.fetch("multi_goal_conflict").fetch("conversion_first").fetch("selected_provider")
    assert_equal "b", payload.fetch("multi_goal_conflict").fetch("load_first").fetch("selected_provider")
    router_conflict = payload.fetch("router_multi_goal_conflict")
    assert_equal "RubyRouting::Case::Router", router_conflict.fetch("conversion_first").fetch("engine")
    assert_equal "RubyRouting::Case::Router", router_conflict.fetch("load_first").fetch("engine")
    assert_equal "quickpay", router_conflict.fetch("conversion_first").fetch("scenario").fetch("selected_provider")
    assert_equal "quickpay", router_conflict.fetch("load_first").fetch("scenario").fetch("selected_provider")
    assert_equal "vipay", router_conflict.fetch("priority_first").fetch("scenario").fetch("selected_provider")
    assert_equal "quickpay", router_conflict.fetch("load_over_priority").fetch("scenario").fetch("selected_provider")
    assert_equal "op_106", router_conflict.fetch("amount_first").fetch("conflict_operation").fetch("operation_id")
    assert_equal "quickpay", router_conflict.fetch("amount_first").fetch("conflict_operation").fetch("selected_provider")
    assert_equal "vipay", router_conflict.fetch("conversion_over_amount").fetch("conflict_operation").fetch("selected_provider")
    %w[amount_first conversion_over_amount].each do |scenario|
      attempts = router_conflict.fetch(scenario).fetch("conflict_operation").fetch("attempts")
      assert_equal ["payflow", "amount_exceeds_limit"], attempts.first.values_at("provider", "reason")
      evidence = router_conflict.fetch(scenario)
      assert_equal "op_101", evidence.fetch("first_operation").fetch("operation_id")
      assert_equal "op_106", evidence.fetch("scenario").fetch("operation_id")
      assert_equal evidence.fetch("conflict_operation").fetch("selected_provider"),
        evidence.fetch("scenario").fetch("selected_provider")
      assert_equal %w[vipay quickpay].sort,
        router_conflict.fetch(scenario).fetch("conflict_operation").fetch("selection").fetch("scores").keys.sort
    end
    assert_equal(
      { "count" => "provider.traffic_percentage", "volume" => "provider.traffic_percentage" },
      router_conflict.fetch("conversion_first").fetch("target_sources")
    )
    assert_equal 10, router_conflict.fetch("conversion_first").fetch("input").fetch("operation_count")
    refute_equal(
      router_conflict.fetch("conversion_first").fetch("selected_providers"),
      router_conflict.fetch("load_first").fetch("selected_providers")
    )
    refute_equal(
      router_conflict.fetch("priority_first").fetch("selected_providers"),
      router_conflict.fetch("load_over_priority").fetch("selected_providers")
    )
    refute_equal(
      router_conflict.fetch("amount_first").fetch("selected_providers"),
      router_conflict.fetch("conversion_over_amount").fetch("selected_providers")
    )
    comparisons = router_conflict.fetch("comparisons")
    assert_equal ["op_101", "op_102"],
      comparisons.fetch("conversion_vs_load").fetch("changed_operations").map { |change| change.fetch("operation_id") }
    assert_equal ["op_101", "op_105", "op_106", "op_109"],
      comparisons.fetch("priority_vs_load").fetch("changed_operations").map { |change| change.fetch("operation_id") }
    assert_equal ["op_106"],
      comparisons.fetch("amount_vs_conversion").fetch("changed_operations").map { |change| change.fetch("operation_id") }
    comparisons.each_value do |comparison|
      refute_empty comparison.fetch("changed_operations")
      refute_equal comparison.fetch("left_weights"), comparison.fetch("right_weights")
      comparison.fetch("changed_operations").each do |change|
        refute_equal change.fetch("left_provider"), change.fetch("right_provider")
        assert_equal change.fetch("left_provider"), change.fetch("left_selection").fetch("selected_provider")
        assert_equal change.fetch("right_provider"), change.fetch("right_selection").fetch("selected_provider")
        assert_equal "primary", change.fetch("left_selection").fetch("phase")
        assert_equal "primary", change.fetch("right_selection").fetch("phase")
        refute_empty change.fetch("left_selection").fetch("factors")
        refute_empty change.fetch("right_selection").fetch("factors")
      end
    end
    baseline_configuration = router_conflict.fetch("conversion_first").fetch("configuration")
    invariant_configuration = baseline_configuration.reject { |key, _value| %w[weights source].include?(key) }
    %w[load_first priority_first load_over_priority amount_first conversion_over_amount].each do |scenario|
      actual = router_conflict.fetch(scenario).fetch("configuration")
        .reject { |key, _value| %w[weights source].include?(key) }
      assert_equal invariant_configuration, actual,
        "#{scenario} must change only the configured weight strategy"
    end
    assert_equal %w[amount conversion_24h], router_conflict.fetch("amount_first").fetch("conflict_operation").fetch("selection").fetch("factors").fetch("quickpay").map { |factor| factor.fetch("factor") }
    assert_equal %w[amount conversion_24h], router_conflict.fetch("conversion_over_amount").fetch("conflict_operation").fetch("selection").fetch("factors").fetch("vipay").map { |factor| factor.fetch("factor") }
    optional = payload.fetch("router_optional_factor_conflicts")
    assert_equal %w[conversion_over_intensity conversion_over_turnover intensity_first turnover_first], optional.keys.sort
    assert_equal "synthetic_case_data", optional.fetch("intensity_first").fetch("input").fetch("source")
    assert_equal({ "optional-1" => "a", "optional-2" => "b" }, optional.fetch("intensity_first").fetch("selected_providers"))
    assert_equal({ "optional-1" => "a", "optional-2" => "a" }, optional.fetch("conversion_over_intensity").fetch("selected_providers"))
    assert_equal({ "optional-1" => "a", "optional-2" => "b" }, optional.fetch("turnover_first").fetch("selected_providers"))
    assert_equal({ "optional-1" => "a", "optional-2" => "a" }, optional.fetch("conversion_over_turnover").fetch("selected_providers"))
    %w[intensity_first conversion_over_intensity turnover_first conversion_over_turnover].each do |scenario|
      evidence = optional.fetch(scenario)
      warmup_attempts = evidence.fetch("warmup_operation").fetch("attempts")
      assert_equal ["b", "amount_below_minimum"], warmup_attempts.first.values_at("provider", "reason")
      assert_equal %w[a b], evidence.fetch("conflict_operation").fetch("selection").fetch("scores").keys.sort
    end
    boundary = payload.fetch("router_provider_boundary")
    assert_equal %w[canonical_order reversed_order], boundary.keys.sort
    expected_targets = {
      "enabled-shadow" => 0, "newpay" => "1/10", "payflow" => "1/4",
      "quickpay" => "1/4", "spacepayments" => 0, "vipay" => "2/5"
    }
    boundary.each_value do |scenario|
      assert_equal "RubyRouting::Case::Router", scenario.fetch("engine")
      assert_equal expected_targets, scenario.fetch("target_shares").fetch("count")
      assert_equal expected_targets, scenario.fetch("target_shares").fetch("volume")
      assert_equal "provider.traffic_percentage", scenario.fetch("profile").fetch("count_target_source")
      assert_equal "provider.traffic_percentage", scenario.fetch("profile").fetch("volume_target_source")
      refute_empty scenario.fetch("additional_provider").fetch("selected_operations")
      status_variant = scenario.fetch("status_variant")
      assert_equal 0, status_variant.fetch("target_share")
      assert_equal false, status_variant.fetch("selected")
      assert_equal ["inactive_provider"], status_variant.fetch("observed_reasons")
    end
    assert_equal(
      boundary.fetch("canonical_order").fetch("selected_providers"),
      boundary.fetch("reversed_order").fetch("selected_providers")
    )
    assert_equal({ "a" => "1/5", "b" => "4/5" }, payload.fetch("factors").fetch("volume").fetch("target_shares").fetch("volume"))
  end

  def test_evidence_cli_proves_count_volume_conflict_and_is_byte_deterministic
    first = evidence
    second = evidence

    assert_equal first, second
    conflict = first.fetch("portfolio_conflict")
    refute_equal(
      conflict.fetch("count").fetch("selected_providers"),
      conflict.fetch("volume").fetch("selected_providers")
    )
    assert_equal(
      "synthetic independent volume target map",
      conflict.fetch("volume").fetch("target_sources").fetch("volume")
    )
    assert_equal(
      { "payflow" => "3/5", "quickpay" => "1/5", "spacepayments" => 0, "vipay" => "1/5" },
      conflict.fetch("volume").fetch("configuration").fetch("volume_share")
    )
    fallback = first.fetch("fallback_and_analytics")
    assert_equal "spacepayments", fallback.fetch("selected_provider")
    assert_operator fallback.fetch("fallbacks").fetch("count"), :>, 0
    assert_equal({ "approved" => 10, "rejected" => 0, "expired" => 0 }, fallback.fetch("final_outcomes"))
    explanation = fallback.fetch("explanation")
    assert_equal fallback.fetch("selected_provider"), explanation.fetch("selected_provider")
    assert_equal fallback.fetch("attempts").first.fetch("provider"), explanation.fetch("primary_assignment_provider")
    assert_equal true, explanation.fetch("fallback_continued")
    assert_equal true, explanation.fetch("terminal_fallback")
    assert_equal(
      fallback.fetch("attempts").first(3).map { |attempt| attempt.fetch("provider") },
      explanation.fetch("failed_attempts").map { |attempt| attempt.fetch("provider") }
    )
    traces = fallback.fetch("selection_traces")
    assert_equal fallback.fetch("attempts").first(3).map { |attempt| attempt.fetch("provider") },
      traces.map { |trace| trace.fetch("provider") }
    assert_equal %w[primary fallback fallback], traces.map { |trace| trace.fetch("phase") }
    assert_equal traces.map { |trace| trace.fetch("provider") },
      traces.map { |trace| trace.fetch("selected_by_resolver") }
    assert traces.all? { |trace| trace.fetch("factors").values.flatten.any? { |factor| factor.key?("contribution") } }
    assert_equal [
      {
        "provider" => "vipay", "phase" => "primary", "decision" => "selected",
        "selection_authority" => "resolver", "selection_reason" => "highest_composite_score",
        "selected_by_resolver" => "vipay", "outcome" => "expired",
        "outcome_reason" => "provider_expired", "settled" => false
      },
      {
        "provider" => "payflow", "phase" => "fallback", "decision" => "selected",
        "selection_authority" => "resolver", "selection_reason" => "fallback_highest_composite_score",
        "selected_by_resolver" => "payflow", "outcome" => "expired",
        "outcome_reason" => "provider_expired", "settled" => false
      },
      {
        "provider" => "quickpay", "phase" => "fallback", "decision" => "selected",
        "selection_authority" => "resolver", "selection_reason" => "only_eligible_provider",
        "selected_by_resolver" => "quickpay", "outcome" => "expired",
        "outcome_reason" => "provider_expired", "settled" => false
      },
      {
        "provider" => "spacepayments", "phase" => "terminal", "decision" => "selected",
        "selection_authority" => "terminal_policy", "selection_reason" => "external_providers_exhausted",
        "selected_by_resolver" => nil, "outcome" => "approved",
        "outcome_reason" => nil, "settled" => true
      }
    ], fallback.fetch("causal_chain")
    populations = fallback.fetch("accounting_populations")
    primary = populations.fetch("primary_assignment")
    final = populations.fetch("final_selected_provider")
    settlement = populations.fetch("approved_settlement")
    assert_equal primary.fetch("totals"), final.fetch("totals")
    assert_equal 10, primary.fetch("totals").fetch("count")
    assert_equal 385_800, primary.fetch("totals").fetch("volume")
    refute_equal primary.fetch("distribution"), final.fetch("distribution")
    assert_equal final.fetch("distribution"), settlement.fetch("distribution")
    assert_equal 10, settlement.fetch("totals").fetch("count")
    assert_equal 385_800, settlement.fetch("totals").fetch("volume")
    assert_equal 4, primary.fetch("distribution").fetch("vipay").fetch("count")
    assert_equal 1, final.fetch("distribution").fetch("spacepayments").fetch("count")
    assert_equal 1, settlement.fetch("distribution").fetch("spacepayments").fetch("count")
    refute_empty fallback.fetch("recommendations")
    details = fallback.fetch("recommendation_details")
    assert_equal fallback.fetch("recommendations").length, details.length
    details.each do |detail|
      assert detail.key?("provider")
      assert detail.key?("kind")
      assert detail.key?("evidence")
      assert detail.key?("action")
    end
    assert_equal "provider.traffic_percentage", JSON.parse(
      File.read(File.join(ROOT, "data/submission_profile.json"))
    ).fetch("volume_target_source")
  end
end
