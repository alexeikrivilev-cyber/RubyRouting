# frozen_string_literal: true

module RubyRouting
  module State
    # Validates the cross-fact invariants that must hold after durable replay.
    # Fact restorers own individual fact families; this object owns the final
    # working-state boundary and the release-order contract shared by them.
    class RestoredStateValidator
      def initialize(payouts:, pending_health_transitions:, pending_economic_conflicts:)
        @payouts = payouts
        @pending_health_transitions = pending_health_transitions
        @pending_economic_conflicts = pending_economic_conflicts
      end

      def validate!
        unless pending_health_transitions.call.empty?
          raise RubyRouting::State::DurableCorruptionError,
            "health state transition is missing after preceding signal"
        end
        unless pending_economic_conflicts.call.empty?
          raise RubyRouting::State::DurableCorruptionError,
            "economic conflict fact is missing after a conflicting observation"
        end

        payouts.call.each_value do |state|
          validate_creation_anchor!(state)
          validate_committed_assignment_ownership!(state)
          validate_capacity_reservations!(state)
          validate_throughput_reservations!(state)
          state.operations.each_value { |attempt| validate_attempt!(state, attempt) }
          validate_dispatch_pending!(state)
          validate_recovery_schedule!(state)
          validate_payout!(state)
        end
        nil
      end

      def validate_operation_release_order(state, attempt, operation_id, label)
        unless state.ownership&.operation_id == operation_id &&
               %i[released settled terminated].include?(attempt.phase)
          raise RubyRouting::State::DurableCorruptionError,
            "#{label} is not ordered after a terminal operation outcome for #{operation_id}"
        end
        validate_attempt!(state, attempt)
      end

      private

      attr_reader :payouts, :pending_health_transitions, :pending_economic_conflicts

      def validate_creation_anchor!(state)
        return unless state.created_at && state.created_monotonic_at.nil?

        raise RubyRouting::State::DurableCorruptionError,
          "payout #{state.intent.id} is missing a monotonic creation timestamp"
      end

      def validate_committed_assignment_ownership!(state)
        state.operations.each_value do |attempt|
          next unless attempt.phase == :committed && state.dispatch_pending[attempt.operation_id] == true
          next if state.ownership&.operation_id == attempt.operation_id

          raise RubyRouting::State::DurableCorruptionError,
            "committed assignment is missing ownership for #{state.intent.id}"
        end
      end

      def validate_capacity_reservations!(state)
        state.capacity_reservations.each do |operation_id, (provider_id, money)|
          attempt = state.operations[operation_id]
          next if attempt && attempt.provider_id == provider_id && money == state.intent.money

          raise RubyRouting::State::DurableCorruptionError,
            "capacity reservation is not linked to an operation for #{state.intent.id}"
        end
      end

      def validate_throughput_reservations!(state)
        state.throughput_reservations.each do |operation_id, (provider_id, _consumed_at)|
          attempt = state.operations[operation_id]
          next if attempt && attempt.provider_id == provider_id

          raise RubyRouting::State::DurableCorruptionError,
            "throughput reservation is not linked to an operation for #{state.intent.id}"
        end
      end

      def validate_dispatch_pending!(state)
        state.dispatch_pending.each do |operation_id, pending|
          attempt = state.operations[operation_id]
          next if attempt && (pending == true || pending == :resolution) &&
            ((pending == :resolution && attempt.phase == :resolving) ||
             (pending == true && %i[committed dispatching].include?(attempt.phase)))

          raise RubyRouting::State::DurableCorruptionError,
            "dispatch pending state is not linked to an operation for #{state.intent.id}"
        end
      end

      def validate_recovery_schedule!(state)
        schedule = state.recovery_schedule
        return unless schedule

        attempt = state.operations[schedule.operation_id]
        valid = state.ownership&.operation_id == schedule.operation_id &&
          state.ownership.provider_id == schedule.provider_id &&
          state.ownership.attempt_id == schedule.attempt_id &&
          attempt && attempt.provider_id == schedule.provider_id &&
          attempt.attempt_id == schedule.attempt_id &&
          %i[pending unknown].include?(state.status) &&
          state.dispatch_pending[schedule.operation_id].nil? &&
          (schedule.action == :resolve ? attempt.contract&.status_lookup : attempt.contract&.idempotent_retry)
        return if valid

        raise RubyRouting::State::DurableCorruptionError,
          "recovery schedule is not linked to an unresolved operation for #{state.intent.id}"
      end

      def validate_attempt!(state, attempt)
        if (attempt.contract&.ttl_seconds || attempt.contract&.deadline_seconds) &&
           attempt.committed_monotonic_at.nil?
          raise RubyRouting::State::DurableCorruptionError,
            "operation #{attempt.operation_id} is missing a monotonic commit timestamp"
        end

        valid = case attempt.phase
        when :committed
          state.operation_actions[attempt.operation_id] == :assign && attempt.outcome.nil?
        when :dispatching
          valid_dispatching_attempt?(state, attempt)
        when :resolving
          valid_resolving_attempt?(state, attempt)
        when :settled
          attempt.outcome&.success?
        when :terminated
          attempt.outcome&.terminal_payout_failure?
        when :released
          attempt.outcome &&
            %i[safe_route_failure temporary_provider_failure].include?(attempt.outcome.status) &&
            attempt.outcome.safe_to_release?
        when :pending
          attempt.outcome&.status == :pending
        when :unknown
          attempt.outcome&.status == :unknown ||
            (attempt.outcome && attempt.outcome.provider_failure? && !attempt.outcome.safe_to_release?)
        when :reconciliation_blocked
          attempt.outcome.nil? || attempt.outcome.unresolved?
        else
          true
        end
        return if valid

        raise RubyRouting::State::DurableCorruptionError,
          "operation #{attempt.operation_id} phase #{attempt.phase} has incompatible outcome"
      end

      def valid_dispatching_attempt?(state, attempt)
        action = state.operation_actions[attempt.operation_id]
        if attempt.outcome.nil?
          return %i[assign retry_same].include?(action)
        end

        action == :retry_same &&
          retryable_in_flight_outcome?(attempt.outcome) &&
          no_applied_observation_after_latest_decision?(state, attempt)
      end

      def valid_resolving_attempt?(state, attempt)
        state.operation_actions[attempt.operation_id] == :resolve &&
          (attempt.outcome.nil? ||
           (retryable_in_flight_outcome?(attempt.outcome) &&
            no_applied_observation_after_latest_decision?(state, attempt)))
      end

      def no_applied_observation_after_latest_decision?(state, attempt)
        decision_sequence = state.operation_action_fact_sequences[attempt.operation_id]
        observation_sequence = state.applied_observation_fact_sequences[attempt.operation_id]
        decision_sequence &&
          (observation_sequence.nil? || observation_sequence < decision_sequence)
      end

      def retryable_in_flight_outcome?(outcome)
        outcome.unresolved? ||
          (%i[safe_route_failure temporary_provider_failure].include?(outcome.status) &&
           !outcome.safe_to_release?)
      end

      def validate_payout!(state)
        valid = case state.status
        when :success, :reversed
          settlement = state.settlement_operation_id && state.operations[state.settlement_operation_id]
          state.ownership.nil? && state.last_outcome&.success? && settlement &&
            settlement.phase == :settled &&
            state.settlement_provider_id == settlement.provider_id &&
            (state.status != :reversed || !state.reversals.empty?)
        when :terminal_payout_failure
          state.ownership.nil? && state.last_outcome&.terminal_payout_failure? &&
            state.attempts.any? { |attempt| attempt.phase == :terminated }
        when :safe_route_failure, :temporary_provider_failure
          state.ownership.nil? && state.last_outcome&.status == state.status &&
            state.last_outcome.safe_to_release? &&
            state.attempts.any? { |attempt| attempt.phase == :released }
        when :pending, :unknown, :reconciliation_blocked
          !state.ownership.nil?
        else
          state.ownership.nil?
        end
        return if valid

        raise RubyRouting::State::DurableCorruptionError,
          "payout #{state.intent.id} has inconsistent restored lifecycle state"
      end
    end
  end
end
