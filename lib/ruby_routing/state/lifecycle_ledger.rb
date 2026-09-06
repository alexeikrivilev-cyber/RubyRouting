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

      # Pure outcome semantics shared by live commit, durable restoration and
      # projections. It deliberately does not mutate payout state or release
      # any external resource.
      OutcomeReduction = Data.define(:phase, :status, :release_ownership) do
        def release_ownership?
          release_ownership
        end

        def settled?
          status == :success
        end
      end

      def self.reduce_outcome(outcome)
        normalized_status = RubyRouting::Enum.normalize(
          outcome.status,
          RubyRouting::NormalizedOutcome::STATUSES,
          "outcome status"
        )
        reduced_status = reduce_status(
          normalized_status,
          safe_to_release: outcome.safe_to_release?
        )
        phase = case reduced_status
        when :success then :settled
        when :pending then :pending
        when :unknown then :unknown
        when :safe_route_failure, :temporary_provider_failure then :released
        when :terminal_payout_failure then :terminated
        else
          raise ArgumentError, "unsupported reduced outcome status #{reduced_status.inspect}"
        end

        OutcomeReduction.new(
          phase: phase,
          status: reduced_status,
          release_ownership: %i[settled released terminated].include?(phase)
        )
      end

      def self.reduce_status(status, safe_to_release:)
        normalized_status = RubyRouting::Enum.normalize(
          status,
          RubyRouting::NormalizedOutcome::STATUSES,
          "outcome status"
        )
        if %i[safe_route_failure temporary_provider_failure].include?(normalized_status)
          return normalized_status if safe_to_release == true

          return :unknown
        end

        normalized_status
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
        reduction = self.class.reduce_outcome(outcome)
        phase = reduction.phase
        phase_change = if attempt.phase == phase
          nil
        else
          change_phase(attempt, from: attempt.phase, to: phase)
        end
        state.status = reduction.status
        OutcomeTransition.new(
          phase_change: phase_change,
          status: reduction.status,
          release_ownership: reduction.release_ownership?
        )
      end

      def status_for(outcome)
        self.class.reduce_outcome(outcome).status
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

    end
  end
end
