# frozen_string_literal: true

module RubyRouting
  module State
    # Owns the lifecycle reducer for an operation. External effects such as
    # capacity release, health exposure and fact publication remain with the
    # coordinator, which is still the atomic facade.
    class LifecycleLedger
      PHASE_TRANSITIONS = {
        committed: %i[dispatching resolving pending unknown released settled terminated reconciliation_blocked],
        dispatching: %i[resolving pending unknown released settled terminated reconciliation_blocked],
        resolving: %i[dispatching pending unknown released settled terminated reconciliation_blocked],
        pending: %i[dispatching resolving unknown released settled terminated reconciliation_blocked],
        unknown: %i[dispatching resolving released settled terminated reconciliation_blocked],
        reconciliation_blocked: %i[pending unknown released settled terminated]
      }.each_with_object({}) do |(phase, destinations), frozen_transitions|
        frozen_transitions[phase] = destinations.freeze
      end.freeze

      class PhaseChange
        attr_reader :operation_id, :attempt_id, :provider_id, :from, :to

        def initialize(operation_id:, attempt_id:, provider_id:, from:, to:)
          @operation_id = normalize_identity(operation_id, "operation id")
          @attempt_id = normalize_identity(attempt_id, "attempt id")
          @provider_id = normalize_identity(provider_id, "provider id")
          @from = RubyRouting::Enum.normalize(from, AttemptSnapshot::PHASES, "operation phase")
          @to = RubyRouting::Enum.normalize(to, AttemptSnapshot::PHASES, "operation phase")
          freeze
        end

        private

        def normalize_identity(value, label)
          normalized = value.to_s.strip
          raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

          normalized.freeze
        end
      end

      class OutcomeTransition
        attr_reader :phase_change, :status

        def initialize(phase_change:, status:, release_ownership:)
          @phase_change = phase_change
          @status = status.is_a?(Symbol) ? status : status.to_s.freeze
          @release_ownership = !!release_ownership
          freeze
        end

        def release_ownership?
          @release_ownership
        end

        def settled?
          status == :success
        end
      end

      def apply_phase_change(state, operation_id, from:, to:)
        attempt = state.operations.fetch(normalize_identity(operation_id, "operation id"))
        phase_change = change_phase(attempt, from: from, to: to)
        phase_change
      end

      def apply_outcome(state, attempt, outcome)
        return nil unless state.ownership&.operation_id == attempt.operation_id

        state.dispatch_pending.delete(attempt.operation_id)
        state.last_outcome = outcome
        phase, status, release_ownership = outcome_reduction(outcome)
        phase_change = if attempt.phase == phase
          nil
        else
          change_phase(attempt, from: attempt.phase, to: phase)
        end
        state.status = status
        OutcomeTransition.new(
          phase_change: phase_change,
          status: status,
          release_ownership: release_ownership
        )
      end

      def status_for(outcome)
        outcome_reduction(outcome).fetch(1)
      end

      private

      def change_phase(attempt, from:, to:)
        normalized_from = RubyRouting::Enum.normalize(from, AttemptSnapshot::PHASES, "operation phase")
        normalized_to = RubyRouting::Enum.normalize(to, AttemptSnapshot::PHASES, "operation phase")
        unless attempt.phase == normalized_from
          raise ArgumentError,
            "phase change expected #{normalized_from.inspect}, got #{attempt.phase.inspect}"
        end
        unless RubyRouting::State::AttemptSnapshot::PHASES.include?(normalized_to) &&
               normalized_from != normalized_to &&
               PHASE_TRANSITIONS.fetch(normalized_from, []).include?(normalized_to)
          raise ArgumentError,
            "unsupported phase transition #{normalized_from.inspect}->#{normalized_to.inspect}"
        end

        attempt.phase = normalized_to
        PhaseChange.new(
          operation_id: attempt.operation_id,
          attempt_id: attempt.attempt_id,
          provider_id: attempt.provider_id,
          from: normalized_from,
          to: normalized_to
        )
      end

      def normalize_identity(value, label)
        normalized = value.to_s.strip
        raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

        normalized
      end

      def outcome_reduction(outcome)
        case outcome.status
        when :success
          [:settled, :success, true]
        when :pending
          [:pending, :pending, false]
        when :unknown
          [:unknown, :unknown, false]
        when :safe_route_failure, :temporary_provider_failure
          if outcome.safe_to_release?
            [:released, outcome.status, true]
          else
            [:unknown, :unknown, false]
          end
        when :terminal_payout_failure
          [:terminated, :terminal_payout_failure, true]
        else
          raise ArgumentError, "unsupported outcome status #{outcome.status.inspect}"
        end
      end
    end
  end
end
