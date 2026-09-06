# frozen_string_literal: true

module RubyRouting
  module State
    # Replays durable decision facts after their policy and routing traces have
    # been validated by DecisionTraceValidator. This object only mutates the
    # operation/dispatch state for the decision itself.
    class DecisionFactRestorer
      def initialize(payout_state:, enum_value:, decision_identifier:, provider_identity:,
                     decision_role:, decision_trace_validator:, validate_provider_registered:,
                     contract_from_payload:, attempt_state_factory:,
                     monotonic_value:, monotonic_reference:)
        @payout_state = payout_state
        @enum_value = enum_value
        @decision_identifier = decision_identifier
        @provider_identity = provider_identity
        @decision_role = decision_role
        @decision_trace_validator = decision_trace_validator
        @validate_provider_registered = validate_provider_registered
        @contract_from_payload = contract_from_payload
        @attempt_state_factory = attempt_state_factory
        @monotonic_value = monotonic_value
        @monotonic_reference = monotonic_reference
      end

      def apply(fact)
        return false unless fact.type == :decision_committed

        restore_decision!(fact)
        true
      end

      private

      def restore_decision!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        action = @enum_value.call(
          payload,
          :action,
          RubyRouting::DecisionProposal::ACTIONS,
          "decision action"
        )
        unless RubyRouting::DecisionProposal::ACTIONS.include?(action)
          raise RubyRouting::State::DurableCorruptionError,
            "unsupported decision action #{action.inspect}"
        end
        @decision_trace_validator.validate_policy_binding(state, payload)
        @decision_trace_validator.validate_configuration_revision_binding(state, payload)
        operation_id = payload[:operation_id]
        unless operation_id
          @decision_trace_validator.validate_non_operation_decision(
            state: state,
            action: action,
            payload: payload
          )
          state.status = :deferred if action == :defer && state.ownership.nil?
          return
        end
        operation_id = @decision_identifier.call(operation_id, "operation_id")

        if action == :assign
          provider_id = @provider_identity.call(payload, :provider_id)
          @validate_provider_registered.call(fact, provider_id)
          attempt_id = @decision_identifier.call(payload.fetch(:attempt_id), "attempt_id")
          role = @decision_role.call(payload.fetch(:role), action: action)
          measure = payload.fetch(:measure)
          contract = @contract_from_payload.call(payload.fetch(:contract))
          @decision_trace_validator.validate_assignment_trace(
            state: state,
            payload: payload,
            provider_id: provider_id
          )
          @decision_trace_validator.validate_assignment(
            fact: fact,
            state: state,
            provider_id: provider_id,
            operation_id: operation_id,
            attempt_id: attempt_id,
            role: role,
            measure: measure,
            contract: contract
          )
          if state.operations.key?(operation_id)
            raise RubyRouting::State::DurableCorruptionError,
              "duplicate assignment decision for #{operation_id}"
          end
          if state.attempts.any? { |existing_attempt| existing_attempt.attempt_id == attempt_id }
            raise RubyRouting::State::DurableCorruptionError,
              "assignment reuses an existing attempt identity for #{operation_id}"
          end

          attempt = @attempt_state_factory.call(
            attempt_id: attempt_id,
            operation_id: operation_id,
            provider_id: provider_id,
            role: role,
            measure: measure,
            phase: :committed,
            contract: contract,
            committed_at: payload[:committed_at],
            committed_monotonic_at: if payload.key?(:committed_monotonic_at)
              @monotonic_value.call(payload, :committed_monotonic_at)
            elsif payload[:committed_at]
              @monotonic_reference.call(payload[:committed_at])
            end
          )
          state.attempts << attempt
          state.operations[operation_id] = attempt
          state.primary_provider_id = provider_id if role == :primary
          state.dispatch_pending[operation_id] = true
          state.operation_actions[operation_id] = action
          state.operation_action_fact_sequences[operation_id] = fact.sequence
        elsif %i[resolve retry_same].include?(action)
          attempt = state.operations.fetch(operation_id) do
            raise RubyRouting::State::DurableCorruptionError,
              "decision references unknown operation #{operation_id}"
          end
          attempt_id = @decision_identifier.call(payload.fetch(:attempt_id), "attempt_id")
          provider_id = @provider_identity.call(payload, :provider_id)
          role = @decision_role.call(payload.fetch(:role), action: action)
          @decision_trace_validator.validate_resolution_trace(
            state: state,
            attempt: attempt,
            action: action,
            payload: payload
          )
          @decision_trace_validator.validate_resolution(
            state: state,
            attempt: attempt,
            action: action,
            payload: payload,
            provider_id: provider_id,
            attempt_id: attempt_id,
            role: role,
            operation_id: operation_id
          )
          state.recovery_schedule = nil if state.respond_to?(:recovery_schedule=)
          state.dispatch_pending[operation_id] = action == :resolve ? :resolution : true
          state.operation_actions[operation_id] = action
          state.operation_action_fact_sequences[operation_id] = fact.sequence
        end
      end
    end
  end
end
