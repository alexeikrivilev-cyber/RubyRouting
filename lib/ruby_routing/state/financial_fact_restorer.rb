# frozen_string_literal: true

module RubyRouting
  module State
    # Replays post-operation financial evidence: late-success conflicts and
    # settlement reversals. The coordinator supplies working payout state and
    # cross-fact identity validation; financial ownership remains elsewhere.
    class FinancialFactRestorer
      def initialize(payout_state:, pending_economic_conflicts:, operation_identity:,
                     provider_identity:, enum_value:, optional_operation_identity:)
        @payout_state = payout_state
        @pending_economic_conflicts = pending_economic_conflicts
        @operation_identity = operation_identity
        @provider_identity = provider_identity
        @enum_value = enum_value
        @optional_operation_identity = optional_operation_identity
      end

      def apply(fact)
        case fact.type
        when :economic_conflict
          restore_economic_conflict!(fact)
          true
        when :reversal_recorded
          restore_reversal!(fact)
          true
        else
          false
        end
      end

      private

      def restore_economic_conflict!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "economic conflict references unknown operation #{operation_id}"
        end
        observation_id = @operation_identity.call(payload, :observation_id)
        reason = @enum_value.call(
          payload,
          :reason,
          [:late_old_operation_success],
          "economic conflict reason"
        )
        unless attempt.provider_id == @provider_identity.call(payload, :provider_id) &&
               attempt.attempt_id == @operation_identity.call(payload, :attempt_id) &&
               %i[released terminated].include?(attempt.phase) &&
               !observation_id.empty? && state.seen_observations.key?(observation_id) &&
               reason == :late_old_operation_success
          raise RubyRouting::State::DurableCorruptionError,
            "economic conflict does not match released operation #{operation_id}"
        end
        if state.conflict_observation_ids.include?(observation_id)
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate economic conflict for observation #{observation_id}"
        end

        source_key = [fact.payout_id, observation_id].freeze
        unless @pending_economic_conflicts.call.delete(source_key)
          raise RubyRouting::State::DurableCorruptionError,
            "economic conflict has no preceding conflicting observation #{source_key.inspect}"
        end

        state.conflicts << RubyRouting::EconomicConflict.new(
          payout_id: fact.payout_id,
          provider_id: payload.fetch(:provider_id),
          operation_id: operation_id,
          attempt_id: payload.fetch(:attempt_id),
          reason: payload.fetch(:reason)
        )
        state.conflict_observation_ids << observation_id
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed economic conflict: #{error.message}"
      end

      def restore_reversal!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "reversal references unknown operation #{operation_id}"
        end
        provider_id = @provider_identity.call(payload, :provider_id)
        amount = payload.fetch(:amount)
        reversal_id = @operation_identity.call(payload, :reversal_id)
        settlement_match = state.settlement_provider_id == provider_id &&
          state.settlement_operation_id == operation_id
        conflict_match = state.conflicts.any? do |conflict|
          conflict.provider_id == provider_id && conflict.operation_id == operation_id
        end
        attempt_id = @optional_operation_identity.call(
          payload,
          :attempt_id,
          default: attempt.attempt_id
        )
        unless %i[success reversed].include?(state.status) &&
               attempt.provider_id == provider_id &&
               attempt.attempt_id == attempt_id &&
               (settlement_match || conflict_match) &&
               amount.is_a?(RubyRouting::Money) && amount.amount_minor.positive? &&
               amount.currency == state.intent.money.currency && !reversal_id.empty?
          raise RubyRouting::State::DurableCorruptionError,
            "reversal does not match a settled or conflicted operation #{operation_id}"
        end
        if state.reversals.any? { |reversal| reversal.reversal_id == reversal_id }
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate reversal #{reversal_id}"
        end

        reversed_minor = state.reversals
          .select { |reversal| reversal.operation_id == operation_id }
          .sum { |reversal| reversal.amount.amount_minor }
        if reversed_minor + amount.amount_minor > state.intent.money.amount_minor
          raise RubyRouting::State::DurableCorruptionError,
            "reversals exceed payout amount for #{operation_id}"
        end

        state.reversals << RubyRouting::SettlementReversal.new(
          reversal_id: reversal_id,
          payout_id: fact.payout_id,
          provider_id: provider_id,
          operation_id: operation_id,
          amount: amount,
          reason: payload.fetch(:reason)
        )
        state.status = :reversed
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed reversal: #{error.message}"
      end
    end
  end
end
