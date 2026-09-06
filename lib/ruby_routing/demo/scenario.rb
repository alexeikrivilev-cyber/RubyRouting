# frozen_string_literal: true

module RubyRouting
  module Demo
    module Scenario
      module_function

      def run
        policy = RubyRouting::RoutingPolicy.new(
          id: "demo-policy",
          epoch: "1",
          measure: :count,
          targets: { "simulated-primary" => 1, "simulated-recovery" => 1 }
        )
        primary = RubyRouting::Demo::ScriptedProvider.new(
          provider_id: "simulated-primary",
          outcomes: [RubyRouting::NormalizedOutcome.safe_route_failure]
        )
        recovery = RubyRouting::Demo::ScriptedProvider.new(
          provider_id: "simulated-recovery",
          outcomes: [RubyRouting::NormalizedOutcome.success(attribution: :provider)]
        )
        coordinator = RubyRouting::State::Coordinator.new(
          opportunities: [
            RubyRouting::ProviderOpportunity.new(provider_id: primary.provider_id),
            RubyRouting::ProviderOpportunity.new(provider_id: recovery.provider_id)
          ]
        )
        service = RubyRouting::Application::Service.new(
          coordinator: coordinator,
          providers: {
            primary.provider_id => primary,
            recovery.provider_id => recovery
          }
        )
        service.commands.register_policy(policy)
        intent = RubyRouting::PayoutIntent.new(
          id: "demo-payout-1",
          money: RubyRouting::Money.new(100, "RUB"),
          context: { labels: ["demo"] }
        )
        result = service.submit(intent: intent)

        {
          result: result,
          service: service,
          providers: { primary: primary, recovery: recovery }
        }.freeze
      end
    end
  end
end
