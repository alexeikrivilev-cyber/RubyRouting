# frozen_string_literal: true

module RubyRouting
  module State
    # Replays operation phase, ownership-release and settlement facts. The
    # lifecycle ledger owns phase/status semantics while the coordinator
    # supplies payout lookup and release-order validation.
    class LifecycleFactRestorer
      def initialize(lifecycle_ledger:, payout_state:, operation_identity:,
                     provider_identity:, enum_value:,
                     validate_operation_release_order:)
        @lifecycle_ledger = lifecycle_ledger
        @payout_state = payout_state
        @operation_identity = operation_identity
        @provider_identity = provider_identity
        @enum_value = enum_value
        @validate_operation_release_order = validate_operation_release_order
      end

      def apply(fact)
        case fact.type
        when :operation_phase_changed
          restore_phase_change!(fact)
          true
        when :ownership_released
          restore_ownership_release!(fact)
          true
        when :settlement_recorded
          restore_settlement!(fact)
          true
        else
          false
        end
      end

      private

      def restore_phase_change!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "phase change references unknown operation #{operation_id}"
        end
        unless attempt.attempt_id == @operation_identity.call(payload, :attempt_id) &&
               attempt.provider_id == @provider_identity.call(payload, :provider_id)
          raise RubyRouting::State::DurableCorruptionError,
            "phase change does not match operation #{operation_id}"
        end

        from = @enum_value.call(
          payload,
          :from,
          RubyRouting::State::AttemptSnapshot::PHASES,
          "operation phase"
        )
        to = @enum_value.call(
          payload,
          :to,
          RubyRouting::State::AttemptSnapshot::PHASES,
          "operation phase"
        )
        phases = RubyRouting::State::AttemptSnapshot::PHASES
        unless phases.include?(from) && phases.include?(to) && from != to && attempt.phase == from
          raise RubyRouting::State::DurableCorruptionError,
            "invalid phase transition #{from.inspect}->#{to.inspect} for #{operation_id}"
        end
        lifecycle_ledger.apply_phase_change(state, operation_id, from: from, to: to)
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed operation phase change: #{error.message}"
      end

      def restore_ownership_release!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "ownership release references unknown operation #{operation_id}"
        end
        expected = [attempt.provider_id, attempt.operation_id, attempt.attempt_id]
        actual = [
          @provider_identity.call(payload, :provider_id),
          operation_id,
          @operation_identity.call(payload, :attempt_id)
        ]
        unless expected == actual && state.ownership &&
               [state.ownership.provider_id, state.ownership.operation_id, state.ownership.attempt_id] == actual
          raise RubyRouting::State::DurableCorruptionError,
            "ownership release does not match current owner #{operation_id}"
        end
        unless @enum_value.call(
          payload,
          :reason,
          RubyRouting::NormalizedOutcome::STATUSES,
          "ownership release reason"
        ) == attempt.outcome&.status
          raise RubyRouting::State::DurableCorruptionError,
            "ownership release reason does not match operation #{operation_id}"
        end
        @validate_operation_release_order.call(state, attempt, operation_id, "ownership release")

        state.ownership = nil
        state.dispatch_pending.delete(operation_id)
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed ownership release: #{error.message}"
      end

      def restore_settlement!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        if state.settlement_operation_id
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate settlement for #{operation_id}"
        end
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "settlement references unknown operation #{operation_id}"
        end
        unless @provider_identity.call(payload, :provider_id) == attempt.provider_id &&
               @enum_value.call(payload, :outcome, [:success], "settlement outcome") == :success &&
               payload.fetch(:measure) == attempt.measure &&
               attempt.phase == :settled && state.ownership.nil? &&
               state.last_outcome&.success?
          raise RubyRouting::State::DurableCorruptionError,
            "settlement does not match settled operation #{operation_id}"
        end

        state.status = :success
        state.settlement_provider_id = attempt.provider_id
        state.settlement_operation_id = operation_id
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed settlement: #{error.message}"
      end

      def lifecycle_ledger
        @lifecycle_ledger.call
      end
    end
  end
end
