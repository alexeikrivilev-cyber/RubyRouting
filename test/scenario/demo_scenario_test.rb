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
end
