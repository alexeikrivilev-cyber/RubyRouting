# frozen_string_literal: true

module RubyRouting
  module State
    # Replays primary allocation facts through the allocation ledger. Policy,
    # payout and provider-history linkage stay supplied by the coordinator so
    # durable replay does not create a second transaction owner.
    class AllocationFactRestorer
      def initialize(allocation_ledger:, payout_state:, policy_for_scope:,
                     policy_identity:, operation_identity:, provider_identity:,
                     enum_value:, collection_to_array:,
                     validate_provider_registered_before_fact:)
        @allocation_ledger = allocation_ledger
        @payout_state = payout_state
        @policy_for_scope = policy_for_scope
        @policy_identity = policy_identity
        @operation_identity = operation_identity
        @provider_identity = provider_identity
        @enum_value = enum_value
        @collection_to_array = collection_to_array
        @validate_provider_registered_before_fact = validate_provider_registered_before_fact
      end

      def apply(fact)
        return false unless fact.type == :allocation_committed

        restore!(fact)
        true
      end

      private

      def restore!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        policy_id = @policy_identity.call(payload, :policy_id)
        policy_scope = @policy_identity.call(payload, :policy_scope)
        policy_fingerprint = @policy_identity.call(payload, :policy_fingerprint)
        policy_epoch = @policy_identity.call(payload, :policy_epoch)
        operation_id = @operation_identity.call(payload, :operation_id)
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "allocation references unknown operation #{operation_id}"
        end
        role = @enum_value.call(payload, :role, %i[primary recovery], "allocation role")
        unless %i[primary recovery].include?(role) &&
               attempt.attempt_id == @operation_identity.call(payload, :attempt_id) &&
               attempt.provider_id == @provider_identity.call(payload, :provider_id) &&
               attempt.role == role && attempt.measure == payload.fetch(:measure)
          raise RubyRouting::State::DurableCorruptionError,
            "allocation does not match operation #{operation_id}"
        end
        @validate_provider_registered_before_fact.call(fact, attempt.provider_id)
        if state.allocation_fact_operations.include?(operation_id)
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate allocation fact for #{operation_id}"
        end
        unless attempt.phase == :committed &&
               state.ownership.nil? &&
               state.dispatch_pending[operation_id] == true
          raise RubyRouting::State::DurableCorruptionError,
            "allocation is not ordered with the committed assignment #{operation_id}"
        end

        evaluation = state.latest_opportunity_evaluation
        recorded_key = payload.fetch(:allocation_key)
        unless evaluation && recorded_key == evaluation.fetch(:allocation_key)
          raise RubyRouting::State::DurableCorruptionError,
            "allocation key does not match the preceding opportunity evaluation for #{operation_id}"
        end

        policy = @policy_for_scope.call(state.policy_scope_key)
        unless policy_id == policy.id &&
               policy_scope == policy.scope &&
               policy_fingerprint == policy.fingerprint &&
               policy_epoch == policy.epoch &&
               payload.fetch(:capacity_reserved) == state.capacity_reservations.key?(operation_id)
          raise RubyRouting::State::DurableCorruptionError,
            "allocation policy or reservation trace does not match #{operation_id}"
        end

        if role == :primary
          key = payload.fetch(:allocation_key)
          unless @collection_to_array.call(key, "allocation key").first(3) == state.policy_scope_key &&
                 policy.weight_for(attempt.provider_id).positive? &&
                 attempt.measure == policy.measure_for(state.intent.money)
            raise RubyRouting::State::DurableCorruptionError,
              "allocation key or measure does not match policy for #{operation_id}"
          end
          allocation_ledger.restore(
            key: key,
            provider_id: payload.fetch(:provider_id),
            measure: payload.fetch(:measure)
          )
        end
        state.allocation_fact_operations[operation_id] = true
      end

      def allocation_ledger
        @allocation_ledger.call
      end
    end
  end
end
