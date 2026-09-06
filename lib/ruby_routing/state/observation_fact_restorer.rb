# frozen_string_literal: true

module RubyRouting
  module State
    # Replays normalized provider-observation facts. Observation identity and
    # ordering belong to ObservationLedger; lifecycle status remains reduced by
    # LifecycleLedger, while the coordinator supplies the durable stores.
    class ObservationFactRestorer
      def initialize(observation_ledger:, lifecycle_ledger:, payout_state:,
                     restored_observations:, pending_economic_conflicts:,
                     operation_identity:, provider_identity:, policy_for_state: nil)
        @observation_ledger = observation_ledger
        @lifecycle_ledger = lifecycle_ledger
        @payout_state = payout_state
        @restored_observations = restored_observations
        @pending_economic_conflicts = pending_economic_conflicts
        @operation_identity = operation_identity
        @provider_identity = provider_identity
        @policy_for_state = policy_for_state || ->(_state) { RubyRouting::RecoveryPolicy.new }
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
        if !payload[:applied] && payload[:recovery_schedule]
          raise RubyRouting::State::DurableCorruptionError,
            "unapplied observation cannot carry recovery schedule"
        end
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
        if state.respond_to?(:recovery_schedule=)
          state.recovery_schedule = restore_recovery_schedule!(
            payload[:recovery_schedule],
            state: state,
            attempt: attempt,
            outcome: outcome
          )
        end
      end

      def restore_recovery_schedule!(payload, state:, attempt:, outcome:)
        schedule = RubyRouting::RecoverySchedule.from(payload)
        return nil unless schedule

        unless state.ownership&.operation_id == attempt.operation_id &&
               state.ownership.provider_id == attempt.provider_id &&
               state.ownership.attempt_id == attempt.attempt_id
          raise RubyRouting::State::DurableCorruptionError,
            "recovery schedule does not reference current ownership"
        end
        unless outcome.unresolved? || (outcome.provider_failure? && !outcome.safe_to_release?)
          raise RubyRouting::State::DurableCorruptionError,
            "recovery schedule requires unresolved provider outcome"
        end
        unless schedule.provider_id == attempt.provider_id &&
               schedule.operation_id == attempt.operation_id &&
               schedule.attempt_id == attempt.attempt_id
          raise RubyRouting::State::DurableCorruptionError,
            "recovery schedule does not match operation"
        end
        supported = if schedule.action == :resolve
          attempt.contract&.status_lookup
        else
          attempt.contract&.idempotent_retry
        end
        unless supported
          raise RubyRouting::State::DurableCorruptionError,
            "recovery schedule action is unsupported by operation contract"
        end

        policy = @policy_for_state.call(state)
        expected_delay = policy.recovery.delay_for(interaction_index: schedule.interaction_index)
        unless expected_delay == schedule.delay_seconds
          raise RubyRouting::State::DurableCorruptionError,
            "recovery schedule delay does not match pinned policy"
        end
        schedule
      rescue ArgumentError, KeyError, TypeError => error
        raise RubyRouting::State::DurableCorruptionError,
          "invalid recovery schedule history: #{error.message}"
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
