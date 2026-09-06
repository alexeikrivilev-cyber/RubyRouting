# frozen_string_literal: true

module RubyRouting
  module State
    # Replays operation ownership, dispatch, reconciliation and health-exposure
    # facts. It mutates only restored working state and supplied controllers;
    # durable publication and atomic transaction ownership stay in Coordinator.
    class OperationFactRestorer
      def initialize(payout_state:, health_controller:, provider_identity:,
                     operation_identity:, enum_value:, durable_monotonic:,
                     monotonic_reference:, elapsed_seconds:,
                     reconciliation_expired_at:, validate_operation_release_order:)
        @payout_state = payout_state
        @health_controller = health_controller
        @provider_identity = provider_identity
        @operation_identity = operation_identity
        @enum_value = enum_value
        @durable_monotonic = durable_monotonic
        @monotonic_reference = monotonic_reference
        @elapsed_seconds = elapsed_seconds
        @reconciliation_expired_at = reconciliation_expired_at
        @validate_operation_release_order = validate_operation_release_order
      end

      def apply(fact)
        case fact.type
        when :ownership_acquired
          restore_ownership_acquired!(fact)
          true
        when :attempt_started
          restore_attempt_started!(fact)
          true
        when :reconciliation_blocked
          restore_reconciliation_blocked!(fact)
          true
        when :health_exposure_reserved
          restore_health_exposure_reserved!(fact)
          true
        when :health_exposure_released
          restore_health_exposure_released!(fact)
          true
        else
          false
        end
      end

      private

      def restore_ownership_acquired!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "ownership references unknown operation #{operation_id}"
        end
        ownership_identity = [
          @provider_identity.call(payload, :provider_id),
          operation_id,
          @operation_identity.call(payload, :attempt_id)
        ]
        unless [attempt.provider_id, attempt.operation_id, attempt.attempt_id] == ownership_identity
          raise RubyRouting::State::DurableCorruptionError,
            "ownership does not match operation #{operation_id}"
        end
        if state.ownership
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate ownership history for #{fact.payout_id}"
        end
        unless attempt.phase == :committed &&
               state.dispatch_pending[operation_id] == true &&
               state.allocation_fact_operations.key?(operation_id) &&
               !%i[success reversed terminal_payout_failure].include?(state.status)
          raise RubyRouting::State::DurableCorruptionError,
            "ownership acquisition is not valid for #{operation_id}"
        end
        evaluation = state.latest_opportunity_evaluation
        throughput = evaluation.fetch(:throughput).fetch(attempt.provider_id)
        if throughput
          unless state.throughput_reservations[operation_id]&.first == attempt.provider_id
            raise RubyRouting::State::DurableCorruptionError,
              "ownership acquisition is missing throughput consumption for #{operation_id}"
          end
        elsif state.throughput_reservations.key?(operation_id)
          raise RubyRouting::State::DurableCorruptionError,
            "ownership acquisition has unexpected throughput consumption for #{operation_id}"
        end
        health = evaluation.fetch(:health).fetch(attempt.provider_id)
        probing = RubyRouting::Enum.normalize(
          health.fetch(:state),
          RubyRouting::Routing::ProviderHealthSnapshot::STATES,
          "health state"
        ) == :probing
        unless state.health_exposure_reservations.key?(operation_id) == probing
          raise RubyRouting::State::DurableCorruptionError,
            "ownership acquisition has inconsistent health exposure reservation for #{operation_id}"
        end
        state.ownership = RubyRouting::EconomicOwnership.new(
          payout_id: fact.payout_id,
          provider_id: payload.fetch(:provider_id),
          operation_id: payload.fetch(:operation_id),
          attempt_id: payload.fetch(:attempt_id)
        )
        state.status = :pending
      end

      def restore_attempt_started!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        attempt = state.operations.fetch(operation_id)
        action = @enum_value.call(
          payload,
          :action,
          RubyRouting::DecisionProposal::ACTIONS,
          "decision action"
        )
        expected_pending = case action
        when :assign, :retry_same
          true
        when :resolve
          :resolution
        else
          raise RubyRouting::State::DurableCorruptionError,
            "unsupported attempt start action #{action.inspect}"
        end
        expected_phase = action == :resolve ? :resolving : :dispatching
        expected_action = state.operation_actions.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "attempt start references operation without a decision #{operation_id}"
        end
        unless action == expected_action &&
               attempt.attempt_id == @operation_identity.call(payload, :attempt_id) &&
               attempt.provider_id == @provider_identity.call(payload, :provider_id) &&
               state.dispatch_pending.fetch(operation_id, nil) == expected_pending &&
               attempt.phase == expected_phase
          raise RubyRouting::State::DurableCorruptionError,
            "attempt start does not match pending operation #{operation_id}"
        end
        state.dispatch_pending.delete(operation_id)
        state.provider_interaction_count += 1
        state.resolution_interaction_count += 1 if %i[resolve retry_same].include?(action)
      end

      def restore_reconciliation_blocked!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "reconciliation block references unknown operation #{operation_id}"
        end
        unless state.ownership&.operation_id == operation_id &&
               attempt.attempt_id == @operation_identity.call(payload, :attempt_id) &&
               attempt.provider_id == @provider_identity.call(payload, :provider_id) &&
               attempt.phase == :reconciliation_blocked
          raise RubyRouting::State::DurableCorruptionError,
            "reconciliation block does not match current operation #{operation_id}"
        end
        if state.status == :reconciliation_blocked
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate reconciliation block for #{operation_id}"
        end
        reason = @enum_value.call(
          payload,
          :reason,
          [:operation_contract_expired],
          "reconciliation reason"
        )
        blocked_at = payload.fetch(:blocked_at)
        elapsed = payload.fetch(:elapsed)
        blocked_monotonic_at = if payload.key?(:blocked_monotonic_at)
          @durable_monotonic.call(payload, :blocked_monotonic_at)
        elsif blocked_at.is_a?(Time)
          @monotonic_reference.call(blocked_at)
        end
        unless reason == :operation_contract_expired &&
               blocked_at.is_a?(Time) &&
               !blocked_monotonic_at.nil? &&
               (elapsed.is_a?(Integer) || elapsed.is_a?(Rational)) &&
               elapsed >= 0 && attempt.committed_monotonic_at &&
               elapsed == @elapsed_seconds.call(blocked_monotonic_at, attempt.committed_monotonic_at) &&
               @reconciliation_expired_at.call(state, attempt, blocked_monotonic_at)
          raise RubyRouting::State::DurableCorruptionError,
            "reconciliation block evidence does not match current operation #{operation_id}"
        end
        state.status = :reconciliation_blocked
        state.recovery_schedule = nil
        state.dispatch_pending.delete(operation_id)
      end

      def restore_health_exposure_reserved!(fact)
        payload = fact.payload
        provider_id = @provider_identity.call(payload, :provider_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        state = @payout_state.call(fact.payout_id)
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "health exposure reservation references unknown operation #{operation_id}"
        end
        if state.health_exposure_reservations.key?(operation_id)
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate health exposure reservation for #{operation_id}"
        end
        unless state.ownership.nil? && attempt.phase == :committed &&
               state.dispatch_pending[operation_id] == true &&
               state.allocation_fact_operations.key?(operation_id) &&
               attempt.provider_id == provider_id &&
               attempt.attempt_id == @operation_identity.call(payload, :attempt_id) &&
               health_controller.snapshot(provider_id).state == :probing &&
               health_controller.reserve_exposure(provider_id, owner: operation_id)
          raise RubyRouting::State::DurableCorruptionError,
            "health exposure reservation does not match operation #{operation_id}"
        end
        state.health_exposure_reservations[operation_id] = true
      end

      def restore_health_exposure_released!(fact)
        payload = fact.payload
        provider_id = @provider_identity.call(payload, :provider_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        state = @payout_state.call(fact.payout_id)
        unless state.health_exposure_reservations.delete(operation_id)
          raise RubyRouting::State::DurableCorruptionError,
            "health exposure release has no reservation for #{operation_id}"
        end
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "health exposure release references unknown operation #{operation_id}"
        end
        unless attempt.provider_id == provider_id &&
               attempt.attempt_id == @operation_identity.call(payload, :attempt_id)
          raise RubyRouting::State::DurableCorruptionError,
            "health exposure release does not match operation #{operation_id}"
        end
        validate_operation_release_order(state, attempt, operation_id, "health exposure release")
        health_controller.release_exposure(provider_id, owner: operation_id)
      end

      def health_controller
        @health_controller.call
      end

      def validate_operation_release_order(state, attempt, operation_id, label)
        @validate_operation_release_order.call(state, attempt, operation_id, label)
      end
    end
  end
end
