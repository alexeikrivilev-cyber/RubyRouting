# frozen_string_literal: true

module RubyRouting
  module Demo
    module Scenario
      module_function

      def run(configuration: nil, providers: nil, intent: nil)
        if configuration.nil?
          default_provider_map_supplied = !providers.nil?
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
          default_providers = {
            primary.provider_id => primary,
            recovery.provider_id => recovery
          }
          providers ||= default_providers
          provider_view = default_provider_map_supplied ? providers : { primary: primary, recovery: recovery }
          configuration = RubyRouting::Application::RoutingConfiguration.new(
            policies: [policy],
            provider_opportunities: [
              RubyRouting::ProviderOpportunity.new(provider_id: primary.provider_id),
              RubyRouting::ProviderOpportunity.new(provider_id: recovery.provider_id)
            ]
          )
        elsif !configuration.is_a?(RubyRouting::Application::RoutingConfiguration)
          raise ArgumentError, "configuration must be Application::RoutingConfiguration"
        elsif providers.nil?
          raise ArgumentError, "providers are required for a custom demo configuration"
        end
        intent ||= RubyRouting::PayoutIntent.new(
          id: "demo-payout-1",
          money: RubyRouting::Money.new(100, "RUB"),
          context: { labels: ["demo"], payment_method: "card" }
        )
        unless intent.is_a?(RubyRouting::PayoutIntent)
          raise ArgumentError, "intent must be PayoutIntent"
        end

        coordinator = RubyRouting::State::Coordinator.new
        service = RubyRouting::Application::Service.new(
          coordinator: coordinator,
          providers: providers
        )
        service.apply_configuration(configuration)
        result = service.submit(intent: intent)

        {
          result: result,
          service: service,
          configuration: configuration,
          providers: provider_view || providers
        }.freeze
      end
    end
  end
end
