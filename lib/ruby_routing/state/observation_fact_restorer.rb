# frozen_string_literal: true

module RubyRouting
  module State
    # Replays normalized provider-observation facts. Observation identity and
    # ordering belong to ObservationLedger; lifecycle status remains reduced by
    # LifecycleLedger, while the coordinator supplies the durable stores.
    class ObservationFactRestorer
      def initialize(observation_ledger:, lifecycle_ledger:, payout_state:,
                     restored_observations:, pending_economic_conflicts:,
                     operation_identity:, provider_identity:)
        @observation_ledger = observation_ledger
        @lifecycle_ledger = lifecycle_ledger
        @payout_state = payout_state
        @restored_observations = restored_observations
        @pending_economic_conflicts = pending_economic_conflicts
        @operation_identity = operation_identity
        @provider_identity = provider_identity
      end

      def apply(fact)
        return false unless fact.type == :provider_observed

        restore!(fact)
        true
      end

      private

      def restore!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        attempt = state.operations.fetch(operation_id)
        unless attempt.provider_id == @provider_identity.call(payload, :provider_id) &&
               attempt.attempt_id == @operation_identity.call(payload, :attempt_id)
          raise RubyRouting::State::DurableCorruptionError,
            "observation does not match operation #{operation_id}"
        end
        observation_decision = observation_ledger.restore(
          seen_observations: state.seen_observations,
          payout_id: fact.payout_id,
          payload: payload,
          current_operation_id: state.ownership&.operation_id,
          attempt: attempt
        )
        return if observation_decision.duplicate?

        source_key = [fact.payout_id, payload.fetch(:observation_id)].freeze
        restored_observations[source_key] = payload
        pending_economic_conflicts[source_key] = true if observation_decision.conflict?
        return unless payload[:applied]

        outcome = RubyRouting::NormalizedOutcome.new(
          status: payload.fetch(:status),
          attribution: payload.fetch(:attribution),
          provider_reference: payload[:outcome_provider_reference],
          message: payload[:message],
          safe_to_release: payload[:safe_to_release]
        )
        attempt.outcome = outcome
        attempt.last_observation_sequence = payload[:sequence] unless payload[:sequence].nil?
        state.last_outcome = outcome
        state.status = lifecycle_ledger.status_for(outcome)
        state.dispatch_pending.delete(operation_id)
        state.applied_observation_fact_sequences[operation_id] = fact.sequence
      end

      def observation_ledger
        @observation_ledger.call
      end

      def lifecycle_ledger
        @lifecycle_ledger.call
      end

      def restored_observations
        @restored_observations.call
      end

      def pending_economic_conflicts
        @pending_economic_conflicts.call
      end
    end
  end
end
