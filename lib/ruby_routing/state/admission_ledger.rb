# frozen_string_literal: true

module RubyRouting
  module State
    # Owns operational admission counters. The coordinator remains the atomic
    # facade and records the facts, while this ledger keeps concurrent exposure
    # separate from time-window throughput consumption.
    class AdmissionLedger
      ThroughputEvent = Data.define(:consumed_at, :monotonic_at)

      def initialize(clock:)
        @clock = clock
        @capacity_usage = {}
        @throughput_events = {}
      end

      def ensure_provider(provider_id)
        normalized_provider_id = normalize_provider_id(provider_id)
        @capacity_usage[normalized_provider_id] ||= CapacityUsage.new
        @throughput_events[normalized_provider_id] ||= []
        nil
      end

      def capacity_snapshot(provider_id, budget:)
        normalized_provider_id = normalize_provider_id(provider_id)
        usage = @capacity_usage.fetch(normalized_provider_id, CapacityUsage.new)
        RubyRouting::State::CapacitySnapshot.new(
          provider_id: normalized_provider_id,
          budget: budget,
          used_slots: usage.slots,
          used_count: usage.count,
          used_amount_minor: usage.amount_minor
        )
      end

      def capacity_available?(opportunity, intent)
        return false unless opportunity.capacity_available
        return true unless opportunity.capacity

        usage = @capacity_usage.fetch(opportunity.provider_id, CapacityUsage.new)
        opportunity.capacity.allows?(
          intent.money,
          used_slots: usage.slots,
          used_count: usage.count,
          used_amount_minor: usage.amount_minor
        )
      end

      def capacity_trace(opportunity, as_of: nil, as_of_monotonic: nil)
        validate_monotonic!(as_of_monotonic, "as_of_monotonic") unless as_of_monotonic.nil?
        prune_throughput_events!(
          opportunity.provider_id,
          opportunity.throughput,
          as_of: as_of,
          as_of_monotonic: as_of_monotonic
        ) if
          opportunity.throughput && as_of
        usage = @capacity_usage.fetch(opportunity.provider_id, CapacityUsage.new)
        {
          budget: opportunity.capacity&.to_h,
          used_slots: usage.slots,
          used_count: usage.count,
          used_amount_minor: usage.amount_minor,
          throughput: opportunity.throughput&.to_h,
          throughput_consumed_count: throughput_events_for(opportunity).length
        }
      end

      def reserve_capacity!(opportunity, intent)
        unless capacity_available?(opportunity, intent)
          raise ArgumentError, "provider capacity became unavailable before commit"
        end

        usage = @capacity_usage.fetch(opportunity.provider_id) do
          @capacity_usage[opportunity.provider_id] = CapacityUsage.new
        end
        usage.reserve(intent.money)
        true
      end

      def restore_capacity_reservation!(provider_id, money)
        validate_money!(money)
        normalized_provider_id = normalize_provider_id(provider_id)
        usage = @capacity_usage.fetch(normalized_provider_id) do
          @capacity_usage[normalized_provider_id] = CapacityUsage.new
        end
        usage.reserve(money)
      end

      def release_capacity!(provider_id, money)
        validate_money!(money)
        usage = @capacity_usage.fetch(normalize_provider_id(provider_id))
        usage.release(money)
      end

      def throughput_snapshot(provider_id, budget:)
        normalized_provider_id = normalize_provider_id(provider_id)
        prune_throughput_events!(normalized_provider_id, budget) if budget
        RubyRouting::State::ThroughputSnapshot.new(
          provider_id: normalized_provider_id,
          budget: budget,
          consumed_at: throughput_events_for_id(normalized_provider_id).map(&:consumed_at)
        )
      end

      def throughput_available?(opportunity)
        return false unless opportunity.throughput_available
        return true unless opportunity.throughput

        budget = opportunity.throughput
        provider_id = opportunity.provider_id
        prune_throughput_events!(provider_id, budget)
        throughput_events_for(opportunity).length < budget.max_operations
      end

      def reserve_throughput!(opportunity)
        return nil unless opportunity.throughput
        ensure_monotonic_clock!
        unless throughput_available?(opportunity)
          raise ArgumentError, "provider throughput budget became unavailable before commit"
        end

        event = ThroughputEvent.new(
          consumed_at: current_time,
          monotonic_at: current_monotonic
        )
        throughput_events_for(opportunity) << event
        event
      end

      def restore_throughput!(provider_id, consumed_at, consumed_monotonic_at: nil)
        unless consumed_at.is_a?(Time)
          raise ArgumentError, "consumed_at must be a Time"
        end

        normalized_provider_id = normalize_provider_id(provider_id)
        ensure_provider(normalized_provider_id)
        monotonic_at = if consumed_monotonic_at.nil?
          monotonic_reference_for(consumed_at)
        else
          validate_monotonic!(consumed_monotonic_at, "consumed_monotonic_at")
        end
        throughput_events_for_id(normalized_provider_id) << ThroughputEvent.new(
          consumed_at: consumed_at.utc.freeze,
          monotonic_at: monotonic_at
        )
      end

      private

      def throughput_events_for(opportunity)
        throughput_events_for_id(opportunity.provider_id)
      end

      def throughput_events_for_id(provider_id)
        normalized_provider_id = normalize_provider_id(provider_id)
        @throughput_events.fetch(normalized_provider_id) do
          @throughput_events[normalized_provider_id] = []
        end
      end

      def normalize_provider_id(provider_id)
        normalized = provider_id.to_s.strip
        raise ArgumentError, "provider id must be non-empty" if normalized.empty?

        normalized
      end

      def current_time
        value = if @clock.respond_to?(:now)
          @clock.now
        elsif @clock.respond_to?(:call)
          @clock.call
        end
        unless value.is_a?(Time)
          raise ArgumentError, "throughput budgets require a Time clock value"
        end

        value.utc.freeze
      end

      def validate_money!(money)
        unless money.is_a?(RubyRouting::Money)
          raise ArgumentError, "admission reservations require Money"
        end
      end

      def prune_throughput_events!(provider_id, budget, as_of: nil, as_of_monotonic: nil)
        now_monotonic = if as_of_monotonic.nil?
          as_of ? monotonic_reference_for(as_of) : current_monotonic
        else
          validate_monotonic!(as_of_monotonic, "as_of_monotonic")
        end
        throughput_events_for_id(provider_id).reject! do |event|
          elapsed_seconds(now_monotonic, event.monotonic_at) >= budget.window_seconds
        end
      end

      def elapsed_seconds(later_monotonic, earlier_monotonic)
        validate_monotonic!(later_monotonic, "later monotonic time")
        validate_monotonic!(earlier_monotonic, "earlier monotonic time")
        elapsed = later_monotonic - earlier_monotonic
        raise ArgumentError, "throughput clock elapsed time cannot be negative" if elapsed.negative?

        elapsed
      rescue NoMethodError, TypeError
        raise ArgumentError, "throughput clock must provide exact monotonic elapsed seconds"
      end

      def ensure_monotonic_clock!
        return if @clock.respond_to?(:monotonic) && @clock.respond_to?(:monotonic_reference_for)

        raise ArgumentError, "throughput clock must provide monotonic and monotonic_reference_for"
      end

      def current_monotonic
        ensure_monotonic_clock!
        validate_monotonic!(@clock.monotonic, "throughput clock monotonic value")
      rescue NoMethodError, TypeError
        raise ArgumentError, "throughput clock must provide exact monotonic time"
      end

      def monotonic_reference_for(value)
        ensure_monotonic_clock!
        validate_monotonic!(
          @clock.monotonic_reference_for(value),
          "throughput clock monotonic reference"
        )
      rescue NoMethodError, TypeError
        raise ArgumentError, "throughput clock must provide exact monotonic references"
      end

      def validate_monotonic!(value, label)
        unless value.is_a?(Integer) || value.is_a?(Rational)
          raise ArgumentError, "#{label} must be an exact monotonic value"
        end

        value
      end

      class CapacityUsage
        attr_reader :amount_minor

        def initialize
          @in_flight = 0
          @amount_minor = 0
        end

        def slots
          @in_flight
        end

        def count
          @in_flight
        end

        def reserve(money)
          @in_flight += 1
          @amount_minor += money.amount_minor
        end

        def release(money)
          @in_flight -= 1
          @amount_minor -= money.amount_minor
          if @in_flight.negative? || @amount_minor.negative?
            raise ArgumentError, "capacity usage underflow"
          end
        end
      end
    end
  end
end
