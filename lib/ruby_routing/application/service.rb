# frozen_string_literal: true

module RubyRouting
  module Application
    # Stable product-facing facade. Transport adapters (HTTP, CLI, demo) use
    # this surface and therefore cannot silently create a second routing path.
    class Service
      attr_reader :commands, :queries

      def initialize(coordinator:, providers:, policy_registry: nil, configuration_store: nil)
        unless coordinator.is_a?(RubyRouting::State::Coordinator)
          raise ArgumentError, "coordinator must be State::Coordinator"
        end
        if policy_registry && !policy_registry.is_a?(RubyRouting::PolicyRegistry)
          raise ArgumentError, "policy_registry must be PolicyRegistry or nil"
        end

        if configuration_store &&
           !configuration_store.is_a?(RubyRouting::Application::ConfigurationStore)
          raise ArgumentError, "configuration_store must be Application::ConfigurationStore or nil"
        end

        @configuration_store = configuration_store || RubyRouting::Application::ConfigurationStore.new(
          configuration: RubyRouting::Application::RoutingConfiguration.new(
            policies: policy_registry ? policy_registry.policies : [],
            provider_opportunities: coordinator.provider_opportunities
          )
        )

        @policy_registry = if policy_registry
          if configuration_store && !RubyRouting::PolicyRegistry.same_policy_set?(
            policy_registry.policies,
            @configuration_store.current.policies
          )
            raise ArgumentError, "policy_registry and configuration_store must share one active policy set"
          end
          policy_registry
        else
          # A supplied active configuration is the control-plane source of
          # truth. Seed the compatibility registry from that immutable
          # generation instead of creating a second, empty policy universe.
          RubyRouting::PolicyRegistry.new(@configuration_store.current.policies)
        end
        @policy_registry_view = @policy_registry.read_only(
          configuration_store: @configuration_store
        )
        # Reserve ownership before the orchestrator can bootstrap provider
        # history into the coordinator. A rejected or racing application
        # construction must not leave a second coordinator partially
        # synchronized with the supplied active configuration.
        @policy_registry.__send__(:reserve_application_binding!, self)
        begin
          orchestrator = RubyRouting::Application::Orchestrator.new(
            coordinator: coordinator,
            providers: providers,
            policy_registry: @policy_registry,
            configuration_store: @configuration_store
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
          @policy_registry.__send__(:bind_application!, self)
        rescue StandardError
          @policy_registry.__send__(:release_application_binding!, self)
          raise
        end
        freeze
      end

      def policy_registry
        @policy_registry_view
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
