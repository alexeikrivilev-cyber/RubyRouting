# frozen_string_literal: true

module RubyRouting
  module Application
    # Stable product-facing facade. Transport adapters (HTTP, CLI, demo) use
    # this surface and therefore cannot silently create a second routing path.
    class Service
      attr_reader :commands, :queries, :policy_registry

      def initialize(coordinator:, providers:, policy_registry: nil)
        unless coordinator.is_a?(RubyRouting::State::Coordinator)
          raise ArgumentError, "coordinator must be State::Coordinator"
        end

        @policy_registry = policy_registry || RubyRouting::PolicyRegistry.new
        @configuration_store = RubyRouting::Application::ConfigurationStore.new(
          configuration: RubyRouting::Application::RoutingConfiguration.new(
            policies: @policy_registry.policies,
            provider_opportunities: coordinator.provider_opportunities
          )
        )
        orchestrator = RubyRouting::Application::Orchestrator.new(
          coordinator: coordinator,
          providers: providers,
          policy_registry: @policy_registry
        )
        @commands = RubyRouting::Application::Commands.new(
          coordinator: coordinator,
          orchestrator: orchestrator,
          policy_registry: @policy_registry,
          configuration_store: @configuration_store
        )
        @queries = RubyRouting::Application::Queries.new(
          coordinator: coordinator,
          policy_registry: @policy_registry,
          configuration_store: @configuration_store
        )
        freeze
      end

      def submit(**attributes)
        commands.submit(**attributes)
      end

      def resume(**attributes)
        commands.resume(**attributes)
      end

      alias advance resume

      def reconcile(**attributes)
        commands.reconcile(**attributes)
      end

      def apply_configuration(configuration)
        commands.apply_configuration(configuration)
      end
    end
  end
end
