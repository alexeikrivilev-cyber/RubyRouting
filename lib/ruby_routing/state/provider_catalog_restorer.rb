# frozen_string_literal: true

module RubyRouting
  module State
    # Replays provider-definition and provider-runtime facts without owning
    # fact publication or the coordinator transaction. Provider identity and
    # ordering checks remain supplied by the durable restore facade.
    class ProviderCatalogRestorer
      def initialize(provider_catalog:, admission_ledger:, quality_controller:,
                     health_policy:, quality_policy:, provider_identity:,
                     validate_provider_system_fact:, opportunity_from_payload:)
        @provider_catalog = provider_catalog
        @admission_ledger = admission_ledger
        @quality_controller = quality_controller
        @health_policy = health_policy
        @quality_policy = quality_policy
        @provider_identity = provider_identity
        @validate_provider_system_fact = validate_provider_system_fact
        @opportunity_from_payload = opportunity_from_payload
      end

      def apply(fact)
        case fact.type
        when :provider_opportunity_registered
          restore_registered!(fact)
          true
        when :provider_opportunity_removed
          restore_removed!(fact)
          true
        when :provider_runtime_changed
          restore_runtime!(fact)
          true
        else
          false
        end
      end

      private

      def restore_registered!(fact)
        payload = fact.payload
        provider_id = @provider_identity.call(payload, :provider_id)
        @validate_provider_system_fact.call(fact, provider_id, require_registered: false)
        opportunity = @opportunity_from_payload.call(payload)
        unless opportunity.provider_id == provider_id
          raise RubyRouting::State::DurableCorruptionError,
            "provider registration identity does not match #{provider_id}"
        end
        unless payload.fetch(:health_policy) == health_policy.to_h
          raise RubyRouting::State::DurableCorruptionError,
            "provider registration health policy does not match #{provider_id}"
        end
        unless payload.fetch(:quality_policy) == quality_policy.to_h
          raise RubyRouting::State::DurableCorruptionError,
            "provider registration quality policy does not match #{provider_id}"
        end
        unless payload.fetch(:capacity) == opportunity.capacity&.to_h &&
               payload.fetch(:throughput) == opportunity.throughput&.to_h
          raise RubyRouting::State::DurableCorruptionError,
            "provider registration admission definition does not match #{provider_id}"
        end

        provider_catalog.register(opportunity, sequence: fact.sequence)
        admission_ledger.ensure_provider(provider_id)
        quality_controller.ensure_provider(provider_id)
      end

      def restore_removed!(fact)
        payload = fact.payload
        provider_id = @provider_identity.call(payload, :provider_id)
        @validate_provider_system_fact.call(fact, provider_id, require_registered: :current)
        begin
          provider_catalog.remove(provider_id, sequence: fact.sequence)
        rescue KeyError
          raise RubyRouting::State::DurableCorruptionError,
            "provider removal has no registered provider #{provider_id}"
        end
      end

      def restore_runtime!(fact)
        payload = fact.payload
        provider_id = @provider_identity.call(payload, :provider_id)
        @validate_provider_system_fact.call(fact, provider_id, require_registered: :historical)
        runtime_values = %i[available capacity_available enabled health_available throughput_available]
          .map { |key| payload.fetch(key) }
        unless runtime_values.all? { |value| value == true || value == false }
          raise RubyRouting::State::DurableCorruptionError,
            "provider runtime values must be boolean for #{provider_id}"
        end
        current = provider_catalog.fetch(provider_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "runtime update references unknown provider #{provider_id}"
        end
        provider_catalog.replace_current(current.with_runtime(
          available: payload.fetch(:available),
          capacity_available: payload.fetch(:capacity_available),
          enabled: payload.fetch(:enabled),
          health_available: payload.fetch(:health_available),
          throughput_available: payload.fetch(:throughput_available)
        ))
      end

      def provider_catalog
        @provider_catalog.call
      end

      def admission_ledger
        @admission_ledger.call
      end

      def quality_controller
        @quality_controller.call
      end

      def health_policy
        @health_policy.call
      end

      def quality_policy
        @quality_policy.call
      end
    end
  end
end
