# frozen_string_literal: true

module RubyRouting
  module State
    # Replays capacity and throughput facts through the admission ledger. The
    # coordinator supplies payout/linkage validators and remains the atomic
    # transaction facade; this object owns only admission fact reduction.
    class AdmissionFactRestorer
      def initialize(admission_ledger:, provider_catalog:, payout_state:,
                     provider_identity:, operation_identity:,
                     validate_provider_registered_before_fact:,
                     validate_operation_release_order:, durable_monotonic:,
                     monotonic_reference:)
        @admission_ledger = admission_ledger
        @provider_catalog = provider_catalog
        @payout_state = payout_state
        @provider_identity = provider_identity
        @operation_identity = operation_identity
        @validate_provider_registered_before_fact = validate_provider_registered_before_fact
        @validate_operation_release_order = validate_operation_release_order
        @durable_monotonic = durable_monotonic
        @monotonic_reference = monotonic_reference
      end

      def apply(fact)
        case fact.type
        when :capacity_reserved
          restore_capacity_reserved!(fact)
          true
        when :capacity_released
          restore_capacity_released!(fact)
          true
        when :throughput_consumed
          restore_throughput_consumed!(fact)
          true
        else
          false
        end
      end

      private

      def restore_capacity_reserved!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        provider_id = @provider_identity.call(payload, :provider_id)
        @validate_provider_registered_before_fact.call(fact, provider_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        money = payload.fetch(:amount)
        provider_opportunity = provider_catalog.fetch(provider_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "capacity reservation references unknown provider #{provider_id}"
        end
        unless provider_opportunity.capacity
          raise RubyRouting::State::DurableCorruptionError,
            "capacity reservation references an unbudgeted provider #{provider_id}"
        end
        unless money == state.intent.money
          raise RubyRouting::State::DurableCorruptionError,
            "capacity reservation amount does not match payout #{fact.payout_id}"
        end
        if state.capacity_reservations.key?(operation_id)
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate capacity reservation for #{operation_id}"
        end
        attempt = state.operations[operation_id]
        if attempt
          unless state.ownership.nil? && attempt.phase == :committed &&
                 state.dispatch_pending[operation_id] == true &&
                 attempt.provider_id == provider_id
            raise RubyRouting::State::DurableCorruptionError,
              "capacity reservation does not match committed assignment #{operation_id}"
          end
        elsif state.ownership || %i[success reversed terminal_payout_failure].include?(state.status)
          raise RubyRouting::State::DurableCorruptionError,
            "capacity reservation is not ordered before a live assignment #{operation_id}"
        end
        unless money.is_a?(RubyRouting::Money)
          raise RubyRouting::State::DurableCorruptionError, "capacity reservation amount is not money"
        end
        admission_ledger.restore_capacity_reservation!(provider_id, money)
        state.capacity_reservations[operation_id] = [provider_id, money]
      end

      def restore_capacity_released!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        reservation = state.capacity_reservations.delete(operation_id)
        unless reservation
          raise RubyRouting::State::DurableCorruptionError, "capacity release without reservation for #{operation_id}"
        end
        provider_id, money = reservation
        unless @provider_identity.call(payload, :provider_id) == provider_id && payload.fetch(:amount) == money
          raise RubyRouting::State::DurableCorruptionError,
            "capacity release does not match reservation for #{operation_id}"
        end
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "capacity release references unknown operation #{operation_id}"
        end
        @validate_operation_release_order.call(state, attempt, operation_id, "capacity release")
        admission_ledger.release_capacity!(provider_id, money)
      end

      def restore_throughput_consumed!(fact)
        payload = fact.payload
        provider_id = @provider_identity.call(payload, :provider_id)
        @validate_provider_registered_before_fact.call(fact, provider_id)
        opportunity = provider_catalog.fetch(provider_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "throughput consumption references unknown provider #{provider_id}"
        end
        unless opportunity.throughput && payload.fetch(:budget) == opportunity.throughput.to_h
          raise RubyRouting::State::DurableCorruptionError,
            "throughput consumption budget does not match provider #{provider_id}"
        end
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        consumed_at = payload.fetch(:consumed_at)
        consumed_monotonic_at = if payload.key?(:consumed_monotonic_at)
          @durable_monotonic.call(payload, :consumed_monotonic_at)
        elsif consumed_at.is_a?(Time)
          @monotonic_reference.call(consumed_at)
        end
        unless !operation_id.empty? && consumed_at.is_a?(Time) && !consumed_monotonic_at.nil?
          raise RubyRouting::State::DurableCorruptionError,
            "throughput consumption has malformed operation or timestamp"
        end
        if state.throughput_reservations.key?(operation_id)
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate throughput consumption for #{operation_id}"
        end
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "throughput consumption references unknown operation #{operation_id}"
        end
        unless attempt.provider_id == provider_id &&
               attempt.phase == :committed &&
               state.allocation_fact_operations.key?(operation_id) &&
               state.ownership.nil? &&
               state.dispatch_pending[operation_id] == true
          raise RubyRouting::State::DurableCorruptionError,
            "throughput consumption is not ordered with the committed assignment #{operation_id}"
        end
        state.throughput_reservations[operation_id] = [provider_id, consumed_at, consumed_monotonic_at]
        admission_ledger.restore_throughput!(
          provider_id,
          consumed_at,
          consumed_monotonic_at: consumed_monotonic_at
        )
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed throughput consumption: #{error.message}"
      end

      def admission_ledger
        @admission_ledger.call
      end

      def provider_catalog
        @provider_catalog.call
      end
    end
  end
end
