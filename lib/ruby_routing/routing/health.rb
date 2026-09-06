# frozen_string_literal: true

module RubyRouting
  module Routing
    class HealthPolicy
      attr_reader :degrade_after, :quarantine_after, :recover_after, :probe_limit,
                  :latency_threshold_ms

      def initialize(degrade_after: 2, quarantine_after: 3, recover_after: 2, probe_limit: 1,
                     latency_threshold_ms: nil)
        @degrade_after = normalize_positive(degrade_after, "degrade_after")
        @quarantine_after = normalize_positive(quarantine_after, "quarantine_after")
        @recover_after = normalize_positive(recover_after, "recover_after")
        @probe_limit = normalize_positive(probe_limit, "probe_limit")
        unless latency_threshold_ms.nil? ||
               (latency_threshold_ms.is_a?(Integer) && latency_threshold_ms.positive?)
          raise ArgumentError, "latency_threshold_ms must be a positive Integer or nil"
        end
        @latency_threshold_ms = latency_threshold_ms
        raise ArgumentError, "quarantine_after must not be below degrade_after" if quarantine_after < degrade_after
        freeze
      end

      def to_h
        values = {
          degrade_after: degrade_after,
          quarantine_after: quarantine_after,
          recover_after: recover_after,
          probe_limit: probe_limit
        }
        values[:latency_threshold_ms] = latency_threshold_ms unless latency_threshold_ms.nil?
        values.freeze
      end

      private

      def normalize_positive(value, label)
        unless value.is_a?(Integer) && value.positive?
          raise ArgumentError, "#{label} must be a positive Integer"
        end

        value
      end
    end

    class ProviderHealthSnapshot
      STATES = %i[healthy degraded quarantined probing].freeze

      attr_reader :provider_id, :state, :operational_failure_count,
                  :consecutive_failure_count, :consecutive_success_count,
                  :probe_in_flight, :probe_limit, :routing_context

      def initialize(provider_id:, state: :healthy, operational_failure_count: 0,
                     consecutive_failure_count: 0, consecutive_success_count: 0,
                     probe_in_flight: 0, probe_limit: 1, routing_context: nil)
        @provider_id = normalize_provider_id(provider_id)
        @routing_context = normalize_routing_context(routing_context)
        @state = normalize_enum(state, STATES, "health state")
        @operational_failure_count = normalize_non_negative_integer(
          operational_failure_count,
          "operational_failure_count"
        )
        @consecutive_failure_count = normalize_non_negative_integer(
          consecutive_failure_count,
          "consecutive_failure_count"
        )
        @consecutive_success_count = normalize_non_negative_integer(
          consecutive_success_count,
          "consecutive_success_count"
        )
        @probe_in_flight = normalize_non_negative_integer(probe_in_flight, "probe_in_flight")
        @probe_limit = normalize_positive_integer(probe_limit, "probe_limit")
        if @probe_in_flight > @probe_limit
          raise ArgumentError, "probe_in_flight must not exceed probe_limit"
        end
        freeze
      end

      def exposed?
        state != :quarantined && (state != :probing || probe_in_flight < probe_limit)
      end

      def to_h
        values = {
          provider_id: provider_id,
          state: state,
          operational_failure_count: operational_failure_count,
          consecutive_failure_count: consecutive_failure_count,
          consecutive_success_count: consecutive_success_count,
          probe_in_flight: probe_in_flight,
          probe_limit: probe_limit
        }
        values[:routing_context] = routing_context.to_h if routing_context
        values.freeze
      end

      private

      def normalize_provider_id(provider_id)
        RubyRouting::Identity.normalize(provider_id, "provider id")
      end

      def normalize_routing_context(value)
        RubyRouting::Routing::HealthController.canonical_routing_context(value)
      end

      def normalize_enum(value, allowed, label)
        RubyRouting::Enum.normalize(value, allowed, label)
      end

      def normalize_non_negative_integer(value, label)
        unless value.is_a?(Integer) && value >= 0
          raise ArgumentError, "#{label} must be a non-negative Integer"
        end

        value
      end

      def normalize_positive_integer(value, label)
        unless value.is_a?(Integer) && value.positive?
          raise ArgumentError, "#{label} must be a positive Integer"
        end

        value
      end
    end

    class HealthController
      SIGNALS = %i[
        operational_failure
        operational_success
        timeout
        provider_failure
        recipient_failure
        transport_failure
        timeout_pressure
        overload_rejection
        provider_service_error
        latency_pressure
        deadline_pressure
      ].freeze
      FAILURE_SIGNALS = %i[
        operational_failure
        timeout
        provider_failure
        transport_failure
        timeout_pressure
        overload_rejection
        provider_service_error
        latency_pressure
        deadline_pressure
      ].freeze
      ATTRIBUTIONS = %i[provider recipient downstream policy unknown].freeze

      def self.canonical_routing_context(value)
        return nil if value.nil?

        context = RubyRouting::RoutingContext.from(value, strict: true)
        return nil if context.payment_method.nil? && context.rail.nil? && context.destination_kind.nil?

        RubyRouting::RoutingContext.new(
          payment_method: context.payment_method,
          rail: context.rail,
          destination_kind: context.destination_kind
        )
      end

      attr_reader :policy

      def initialize(policy: HealthPolicy.new)
        unless policy.is_a?(HealthPolicy)
          raise ArgumentError, "policy must be HealthPolicy"
        end

        @policy = policy
        @states = {}
        @scoped_states = {}
      end

      def snapshot(provider_id, routing_context: nil)
        normalized_provider_id = normalize_provider_id(provider_id)
        normalized_context = normalize_routing_context(routing_context)
        # A provider-wide signal is a safety ceiling for every route. A
        # route-scoped signal must remain isolated, but a known route cannot
        # bypass a global quarantine/probe/degraded state by receiving a
        # fresh default scoped snapshot.
        state = effective_state_for(normalized_provider_id, normalized_context)
        return default_snapshot(normalized_provider_id, routing_context: normalized_context) unless state

        state.snapshot(routing_context: normalized_context)
      end

      def provider_ids
        @states.keys.sort.freeze
      end

      def ensure_provider(provider_id, routing_context: nil)
        normalized_provider_id = normalize_provider_id(provider_id)
        normalized_context = normalize_routing_context(routing_context)
        states_for(normalized_context)[state_key(normalized_provider_id, normalized_context)] ||=
          MutableState.new(normalized_provider_id, @policy.probe_limit)
        nil
      end

      def reserve_exposure(provider_id, owner: nil, routing_context: nil)
        normalized_provider_id = normalize_provider_id(provider_id)
        normalized_owner = normalize_owner(owner) unless owner.nil?
        normalized_context = normalize_routing_context(routing_context)
        ensure_provider(normalized_provider_id, routing_context: normalized_context)
        state = effective_state_for(normalized_provider_id, normalized_context)
        return true if normalized_owner && state.operation_probe_owners.key?(normalized_owner)
        return false if state.state == :quarantined
        return true unless state.state == :probing
        return false if state.probe_in_flight >= @policy.probe_limit

        if normalized_owner
          state.reserve_operation_probe(normalized_owner)
        else
          state.reserve_direct_probe
        end
        true
      end

      def release_exposure(provider_id, owner: nil, routing_context: nil)
        normalized_provider_id = normalize_provider_id(provider_id)
        normalized_context = normalize_routing_context(routing_context)
        scoped_state = state_for(normalized_provider_id, normalized_context)
        global_state = @states[normalized_provider_id]
        states = [scoped_state, global_state].compact.uniq
        return if states.empty?

        if owner
          normalized_owner = normalize_owner(owner)
          states.each do |state|
            state.release_operation_probe(normalized_owner)
          end
        else
          effective_state_for(normalized_provider_id, normalized_context)&.release_direct_probe
        end
        states.each { |state| promote_if_recovered(state) }
      end

      def observe(provider_id:, signal:, attribution: :unknown, release_exposure: true,
                  routing_context: nil)
        normalized_release_exposure = normalize_boolean(release_exposure, "release_exposure")
        normalized_signal = normalize_enum(signal, SIGNALS, "health signal")
        normalized_attribution = normalize_enum(attribution, ATTRIBUTIONS, "health attribution")

        normalized_provider_id = normalize_provider_id(provider_id)
        normalized_context = normalize_routing_context(routing_context)
        ensure_provider(normalized_provider_id, routing_context: normalized_context)
        # Health observations use the same effective state as admission. When
        # a route is carrying a provider-wide degraded/probing operation, its
        # result must not update an isolated route state while the global
        # state remains the safety authority.
        state = effective_state_for(normalized_provider_id, normalized_context)
        before = state.snapshot(routing_context: normalized_context)
        if normalized_signal == :recipient_failure || normalized_attribution != :provider
          return [before, before]
        end

        if FAILURE_SIGNALS.include?(normalized_signal)
          state.release_direct_probe if normalized_release_exposure
          state.record_failure
          if state.consecutive_failure_count >= @policy.quarantine_after
            state.state = :quarantined
          elsif state.consecutive_failure_count >= @policy.degrade_after
            state.state = :degraded
          end
        elsif normalized_signal == :operational_success
          state.release_direct_probe if normalized_release_exposure
          state.record_success
          if state.state == :quarantined
            state.state = :probing
          elsif state.state == :probing
            promote_if_recovered(state)
          elsif state.consecutive_success_count >= @policy.recover_after
            state.state = :healthy
          end
        end

        [before, state.snapshot(routing_context: normalized_context)]
      end

      private

      def state_key(provider_id, routing_context)
        routing_context ? [provider_id, routing_context.to_h].freeze : provider_id
      end

      def states_for(routing_context)
        routing_context ? @scoped_states : @states
      end

      def state_for(provider_id, routing_context)
        states_for(routing_context)[state_key(provider_id, routing_context)]
      end

      def effective_state_for(provider_id, routing_context)
        global_state = @states[provider_id]
        return global_state if routing_context && global_state && global_state.state != :healthy

        state_for(provider_id, routing_context)
      end

      def normalize_provider_id(provider_id)
        RubyRouting::Identity.normalize(provider_id, "provider id")
      end

      def normalize_routing_context(value)
        self.class.canonical_routing_context(value)
      end

      def normalize_owner(owner)
        RubyRouting::Identity.normalize(owner, "probe owner")
      end

      def normalize_boolean(value, label)
        return value if value == true || value == false

        raise ArgumentError, "#{label} must be boolean"
      end

      def normalize_enum(value, allowed, label)
        RubyRouting::Enum.normalize(value, allowed, label)
      end

      def default_snapshot(provider_id, routing_context: nil)
        ProviderHealthSnapshot.new(
          provider_id: provider_id,
          probe_limit: @policy.probe_limit,
          routing_context: routing_context
        )
      end

      def promote_if_recovered(state)
        return unless state.state == :probing
        return unless state.consecutive_success_count >= @policy.recover_after
        return unless state.probe_in_flight.zero?

        state.state = :healthy
      end

      class MutableState
        attr_accessor :state
        attr_reader :provider_id, :operational_failure_count,
                    :consecutive_failure_count, :consecutive_success_count

        def initialize(provider_id, probe_limit)
          @provider_id = RubyRouting::Identity.normalize(provider_id, "provider id")
          @state = :healthy
          @operational_failure_count = 0
          @consecutive_failure_count = 0
          @consecutive_success_count = 0
          @direct_probe_in_flight = 0
          @operation_probe_owners = {}
          @probe_limit = probe_limit
        end

        def probe_in_flight
          @direct_probe_in_flight + @operation_probe_owners.length
        end

        def operation_probe_owners
          @operation_probe_owners
        end

        def reserve_direct_probe
          @direct_probe_in_flight += 1
        end

        def reserve_operation_probe(owner)
          @operation_probe_owners[owner] = true
        end

        def record_failure
          @operational_failure_count += 1
          @consecutive_failure_count += 1
          @consecutive_success_count = 0
        end

        def record_success
          @consecutive_success_count += 1
          @consecutive_failure_count = 0
        end

        def release_direct_probe
          @direct_probe_in_flight -= 1 if @direct_probe_in_flight.positive?
        end

        def release_operation_probe(owner)
          @operation_probe_owners.delete(owner)
        end

        def snapshot(routing_context: nil)
          ProviderHealthSnapshot.new(
            provider_id: provider_id,
            state: state,
            operational_failure_count: operational_failure_count,
            consecutive_failure_count: consecutive_failure_count,
            consecutive_success_count: consecutive_success_count,
            probe_in_flight: probe_in_flight,
            probe_limit: @probe_limit,
            routing_context: routing_context
          )
        end
      end
    end
  end
end
