# frozen_string_literal: true

require_relative "../test_helper"

class DemoScenarioTest < Minitest::Test
  def test_demo_is_explicitly_simulated_and_exercises_safe_fallback
    demo = RubyRouting::Demo::Scenario.run
    result = demo.fetch(:result)
    payout = result.payout

    assert_equal :success, result.status
    assert_equal "simulated-recovery", payout.settlement_provider_id
    assert_equal %w[simulated-primary simulated-recovery], payout.attempts.map(&:provider_id)
    assert_equal [:primary, :recovery], payout.attempts.map(&:role)
    assert_equal 1, demo.fetch(:service).queries.analytics.fallback_recovery_count
    assert_equal [
      [:initiate, "demo-payout-1:demo-payout-1:operation:1"]
    ], demo.fetch(:providers).fetch(:primary).calls
  end

  def test_demo_accepts_typed_configuration_without_creating_a_second_routing_path
    configuration = RubyRouting::Application::RoutingConfiguration.new(
      policies: [
        RubyRouting::RoutingPolicy.new(
          id: "configured-demo-policy",
          epoch: "4",
          measure: :count,
          targets: { "configured-provider" => 1 },
          selector: { payment_method: "card" },
          recovery: RubyRouting::RecoveryPolicy.new(
            max_operations: 2,
            initial_delay_seconds: 3,
            backoff_seconds: 2
          )
        )
      ],
      provider_opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "configured-provider",
          route_capabilities: RubyRouting::ProviderRouteCapabilities.new(
            supported_payment_methods: ["card"]
          ),
          capacity: RubyRouting::CapacityBudget.new(max_slots: 2)
        )
      ]
    )
    provider = RubyRouting::Demo::ScriptedProvider.new(
      provider_id: "configured-provider",
      outcomes: [RubyRouting::NormalizedOutcome.success(attribution: :provider)]
    )
    intent = RubyRouting::PayoutIntent.new(
      id: "configured-demo-payout",
      money: RubyRouting::Money.new(250, "RUB"),
      context: { payment_method: "card" }
    )

    demo = RubyRouting::Demo::Scenario.run(
      configuration: configuration,
      providers: { "configured-provider" => provider },
      intent: intent
    )

    assert_same configuration, demo.fetch(:configuration)
    assert_equal :success, demo.fetch(:result).status
    assert_equal "configured-provider", demo.fetch(:result).payout.settlement_provider_id
    assert_equal 3, demo.fetch(:configuration).policies.first.recovery.initial_delay_seconds
    assert_equal ["card"], demo.fetch(:configuration).provider_opportunities.first
      .route_capabilities.supported_payment_methods
    assert_equal [[:initiate, "configured-demo-payout:configured-demo-payout:operation:1"]], provider.calls
  end

  def test_case_demo_reports_canonical_count_volume_fallback_unknown_recovery_and_analytics
    demo = RubyRouting::Demo::Scenario.case_run
    report = demo.fetch(:report)
    analytics = demo.fetch(:service).queries.analytics

    assert_equal 1, report.fetch(:configuration).fetch(:revision)
    assert_equal %w[demo-count demo-unknown demo-volume],
      report.fetch(:configuration).fetch(:policy_ids)
    assert_equal %w[A B], report.fetch(:configuration).fetch(:provider_ids)
    assert_equal({ "A" => Rational(2), "B" => Rational(2) },
      report.fetch(:strategies).fetch(:count).fetch(:target))
    assert_equal({ "A" => 2, "B" => 2 },
      report.fetch(:strategies).fetch(:count).fetch(:primary_actual))
    assert_equal({ "A" => Rational(600), "B" => Rational(600) },
      report.fetch(:strategies).fetch(:volume).fetch(:target))
    assert_equal({ "A" => 900, "B" => 300 },
      report.fetch(:strategies).fetch(:volume).fetch(:primary_actual))
    assert_equal 1, report.fetch(:analytics).fetch(:recovery).fetch(:fallback_recovery_count)
    assert_equal 1, report.fetch(:analytics).fetch(:recovery).fetch(:recovery_attempt_count)
    assert_equal 2, report.fetch(:analytics).fetch(:recovery).fetch(:settlement_measure_by_dimension).length
    assert_equal 2, analytics.settlement_measure_by_dimension.length
    assert_equal :unknown, report.fetch(:payouts).fetch("demo-unknown").fetch(:status_before_recovery)
    assert_equal :success, report.fetch(:payouts).fetch("demo-unknown").fetch(:status)
    assert_equal %w[A B], report.fetch(:payouts).fetch("demo-fallback").fetch(:attempts)
      .map { |attempt| attempt.fetch(:provider_id) }
    assert_equal :success, demo.fetch(:service).queries.payout("demo-unknown").status
    assert_equal 1, analytics.fallback_recovery_count
    volume_analytics = demo.fetch(:strategy_runs).fetch(:volume).fetch(:service).queries.analytics
    actual_volume = volume_analytics.primary_assignment_measure_by_dimension.each_with_object({}) do |(dimension, value), values|
      values[dimension.provider_id] = value if dimension.policy_id == "demo-volume"
    end
    assert_equal actual_volume, report.fetch(:strategies).fetch(:volume).fetch(:primary_actual)
  end

  def test_case_demo_report_is_deterministic_and_contains_no_runtime_timestamps
    first = RubyRouting::Demo::Scenario.case_run.fetch(:report)
    second = RubyRouting::Demo::Scenario.case_run.fetch(:report)

    assert_equal JSON.generate(first), JSON.generate(second)
    refute_match(/2026-/, JSON.generate(first))
    refute_match(/due_at|as_of/, JSON.generate(first))
  end

  def test_case_demo_isolates_count_vs_volume_on_the_same_skewed_workload
    report = RubyRouting::Demo::Scenario.case_run.fetch(:report)
    count = report.fetch(:strategies).fetch(:count)
    volume = report.fetch(:strategies).fetch(:volume)

    assert_equal [900, 100, 100, 100], count.fetch(:input_amounts_minor)
    assert_equal count.fetch(:input_amounts_minor), volume.fetch(:input_amounts_minor)
    assert_equal({ "A" => Rational(2), "B" => Rational(2) }, count.fetch(:target))
    assert_equal({ "A" => Rational(600), "B" => Rational(600) }, volume.fetch(:target))
    assert_equal 4, count.fetch(:primary_actual).values.sum
    assert_equal 1_200, volume.fetch(:primary_actual).values.sum
    refute_equal(
      count.fetch(:primary_actual).transform_values { |value| Rational(value, 4) },
      volume.fetch(:primary_actual).transform_values { |value| Rational(value, 1_200) }
    )

    demo = RubyRouting::Demo::Scenario.case_run
    analytics = demo.fetch(:strategy_runs).fetch(:count).fetch(:service).queries.analytics
    assert_equal(
      count.fetch(:primary_actual),
      analytics.primary_assignment_measure_by_dimension.each_with_object({}) do |(dimension, value), values|
        values[dimension.provider_id] = value if dimension.policy_id == count.fetch(:policy_id)
      end
    )
    assert_equal 1, report.fetch(:analytics).fetch(:recovery).fetch(:fallback_recovery_count)
    assert_equal 1, report.fetch(:analytics).fetch(:recovery).fetch(:recovery_attempt_count)
  end

  def test_case_demo_uses_distinct_fresh_runtimes_for_strategy_evidence
    demo = RubyRouting::Demo::Scenario.case_run
    runs = demo.fetch(:strategy_runs)
    count_run = runs.fetch(:count)
    volume_run = runs.fetch(:volume)

    refute_same count_run.fetch(:service), volume_run.fetch(:service)
    refute_same count_run.fetch(:service).queries.analytics, volume_run.fetch(:service).queries.analytics
    refute_same count_run.fetch(:providers).fetch("A"), volume_run.fetch(:providers).fetch("A")
    refute_same count_run.fetch(:providers).fetch("B"), volume_run.fetch(:providers).fetch("B")
    assert_equal 4, count_run.fetch(:results).length
    assert_equal 4, volume_run.fetch(:results).length
    assert_equal 4, count_run.fetch(:providers).values.sum { |provider| provider.calls.length }
    assert_equal 4, volume_run.fetch(:providers).values.sum { |provider| provider.calls.length }
    assert_equal :fresh_independent, demo.fetch(:report).fetch(:strategies).fetch(:count).fetch(:runtime)
    assert_equal :fresh_independent, demo.fetch(:report).fetch(:strategies).fetch(:volume).fetch(:runtime)
  end
end
