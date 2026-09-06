# frozen_string_literal: true

module RubyRouting
  module Application
    # The command surface is the only application entry point for mutating
    # routing state. It delegates business decisions to the coordinator and
    # orchestrator rather than reimplementing routing semantics.
    class Commands
      attr_reader :policy_registry

      def initialize(coordinator:, orchestrator:, policy_registry:)
        @coordinator = coordinator
        @orchestrator = orchestrator
        @policy_registry = policy_registry
        freeze
      end

      def register_policy(policy)
        policy_registry.register(policy)
      end

      def replace_provider_opportunities(opportunities)
        @coordinator.replace_provider_opportunities(opportunities)
      end

      def set_provider_availability(provider_id, available:, capacity_available: nil)
        @coordinator.set_provider_availability(
          provider_id,
          available: available,
          capacity_available: capacity_available
        )
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

        normalized_provider_id = provider_id.to_s.strip
        raise ArgumentError, "provider id must be non-empty" if normalized_provider_id.empty?

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
    end
  end
end
