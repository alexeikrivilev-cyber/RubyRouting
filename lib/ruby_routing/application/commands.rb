# frozen_string_literal: true

module RubyRouting
  module Application
    # The command surface is the only application entry point for mutating
    # routing state. It delegates business decisions to the coordinator and
    # orchestrator rather than reimplementing routing semantics.
    class Commands

      def initialize(coordinator:, orchestrator:, policy_registry:, configuration_store: nil)
        unless policy_registry.is_a?(RubyRouting::PolicyRegistry)
          raise ArgumentError, "policy_registry must be PolicyRegistry"
        end
        @coordinator = coordinator
        @orchestrator = orchestrator
        @policy_registry = policy_registry
        orchestrator_store = orchestrator.respond_to?(:configuration_store) ? orchestrator.configuration_store : nil
        if configuration_store && orchestrator_store && configuration_store != orchestrator_store
          raise ArgumentError, "commands and orchestrator must share one configuration store"
        end
        @configuration_store = configuration_store || orchestrator_store || RubyRouting::Application::ConfigurationStore.new(
          configuration: RubyRouting::Application::RoutingConfiguration.new(
            policies: policy_registry.policies,
            provider_opportunities: coordinator.provider_opportunities
          )
        )
        if !RubyRouting::PolicyRegistry.same_policy_set?(
          policy_registry.policies,
          @configuration_store.current.policies
        )
          raise ArgumentError, "policy_registry and configuration_store must share one active policy set"
        end
        @policy_registry_view = @policy_registry.read_only(
          configuration_store: @configuration_store
        )
        freeze
      end

      def policy_registry
        @policy_registry_view
      end

      def register_policy(policy)
        registered = nil
        update_configuration do |current|
          # The immutable active generation owns the current policy set. The
          # registry is a compatibility/index view and must never be allowed
          # to drop policies that were published through a supplied
          # ConfigurationStore.
          candidate_registry = RubyRouting::PolicyRegistry.new(current.policies + [policy])
          registered = candidate_registry.fetch(
            id: policy.id,
            epoch: policy.epoch,
            scope: policy.scope
          )
          configuration = RubyRouting::Application::RoutingConfiguration.new(
            policies: candidate_registry.policies,
            provider_opportunities: current.provider_opportunities
          )
          configuration.compile.raise_if_invalid!
          begin
            replace_policy_registry!(candidate_registry.policies)
          rescue StandardError => error
            rollback_policy_registry!(current.policies)
            raise error
          end
          configuration
        end
        registered
      end

      def replace_provider_opportunities(opportunities)
        update_configuration do |current|
          configuration = RubyRouting::Application::RoutingConfiguration.new(
            policies: current.policies,
            provider_opportunities: opportunities
          )
          configuration.compile.raise_if_invalid!
          begin
            @coordinator.replace_provider_opportunities(configuration.provider_opportunities)
          rescue StandardError => error
            rollback_provider_catalog!(current.provider_opportunities)
            raise error
          end
          configuration
        end
        nil
      end

      def apply_configuration(configuration)
        unless configuration.is_a?(RubyRouting::Application::RoutingConfiguration)
          raise ArgumentError, "configuration must be Application::RoutingConfiguration"
        end

        update_configuration do |current|
          # Validate the replacement set completely before touching the live
          # provider catalog. The candidate registry is therefore valid before
          # mutation; compensation still protects post-commit failures.
          candidate_registry = RubyRouting::PolicyRegistry.new(configuration.policies)
          configuration.compile.raise_if_invalid!
          begin
            @coordinator.replace_provider_opportunities(configuration.provider_opportunities)
            replace_policy_registry!(candidate_registry.policies)
          rescue StandardError => error
            rollback_configuration!(current)
            raise error
          end
          configuration
        end
        configuration
      end

      def set_provider_availability(provider_id, available:, capacity_available: nil)
        update_configuration do |current|
          normalized_provider_id = RubyRouting::Identity.normalize(provider_id, "provider id")
          opportunity = current.provider_opportunities.find do |candidate|
            candidate.provider_id == normalized_provider_id
          end
          raise ArgumentError, "unknown provider opportunity" unless opportunity

          replacement = opportunity.with_runtime(
            available: available,
            capacity_available: capacity_available.nil? ? opportunity.capacity_available : capacity_available
          )
          configuration = RubyRouting::Application::RoutingConfiguration.new(
            policies: current.policies,
            provider_opportunities: current.provider_opportunities.map do |candidate|
              candidate.provider_id == opportunity.provider_id ? replacement : candidate
            end
          )
          configuration.compile.raise_if_invalid!
          begin
            @coordinator.set_provider_availability(
              provider_id,
              available: available,
              capacity_available: capacity_available
            )
          rescue StandardError => error
            rollback_provider_catalog!(current.provider_opportunities)
            raise error
          end
          configuration
        end
        nil
      end

      def submit(intent:, policy: nil, scope: :default)
        @orchestrator.submit(intent: intent, policy: policy, scope: scope)
      end

      def resume(payout_id:, policy: nil, scope: :default)
        @orchestrator.resume(payout_id: payout_id, policy: policy, scope: scope)
      end

      alias advance resume

      def reconcile(provider_id:, raw:, normalizer:)
        # The application command is deliberately a raw-provider ingress. A
        # generic caller cannot pass a hand-built observation carrying
        # safe_to_release or provider attribution; those values must be
        # produced by an executable provider-specific normalizer.
        reconcile_provider_event(
          provider_id: provider_id,
          raw: raw,
          normalizer: normalizer
        )
      end

      def reconcile_provider_event(provider_id:, raw:, normalizer:)
        unless normalizer.respond_to?(:normalize) &&
               normalizer.method(:normalize).owner != RubyRouting::Ports::ProviderNormalizer
          raise ArgumentError, "provider normalizer must implement executable #normalize"
        end

        normalized_provider_id = RubyRouting::Identity.normalize(provider_id, "provider id")

        observation = normalizer.normalize(raw: raw, provider_id: normalized_provider_id)
        unless observation.is_a?(RubyRouting::ProviderObservation) &&
               observation.provider_id == normalized_provider_id
          raise ArgumentError, "provider normalizer returned invalid observation"
        end

        @orchestrator.reconcile(observation: observation)
      end

      def record_reversal(**attributes)
        @orchestrator.record_reversal(**attributes)
      end

      private

      # ConfigurationStore mutation is deliberately private to prevent a
      # caller holding a store reference from publishing a generation without
      # the matching registry/catalog transaction. Commands are the one
      # coordinated application publication path.
      def update_configuration(&block)
        @configuration_store.__send__(:update, &block)
      end

      def rollback_provider_catalog!(previous_opportunities)
        begin
          current_opportunities = @coordinator.provider_opportunities
          unless same_provider_set?(current_opportunities, previous_opportunities)
            @coordinator.replace_provider_opportunities(previous_opportunities)
          end
        rescue StandardError => rollback_error
          raise RubyRouting::State::DurableCorruptionError,
            "active provider configuration rollback failed: #{rollback_error.message}"
        end
      end

      def rollback_policy_registry!(previous_policies)
        begin
          unless RubyRouting::PolicyRegistry.same_policy_set?(
            @policy_registry.policies,
            previous_policies
          )
            replace_policy_registry!(previous_policies)
          end
        rescue StandardError => rollback_error
          raise RubyRouting::State::DurableCorruptionError,
            "active policy configuration rollback failed: #{rollback_error.message}"
        end
      end

      def rollback_configuration!(previous_configuration)
        rollback_errors = []
        begin
          rollback_policy_registry!(previous_configuration.policies)
        rescue StandardError => error
          rollback_errors << error
        end
        begin
          rollback_provider_catalog!(previous_configuration.provider_opportunities)
        rescue StandardError => error
          rollback_errors << error
        end
        return if rollback_errors.empty?

        raise RubyRouting::State::DurableCorruptionError,
          "active configuration rollback failed: #{rollback_errors.map(&:message).join("; ")}"
      end

      def replace_policy_registry!(policies)
        @policy_registry.__send__(:with_application_mutation) do
          @policy_registry.replace!(policies)
        end
      end

      def same_provider_set?(left, right)
        RubyRouting::Application::RoutingConfiguration.same_provider_opportunity_set?(left, right)
      end

    end
  end
end
