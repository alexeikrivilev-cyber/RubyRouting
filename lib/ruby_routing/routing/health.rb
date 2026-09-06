# frozen_string_literal: true

module RubyRouting
  module Routing
    class HealthPolicy
      attr_reader :degrade_after, :quarantine_after, :recover_after, :probe_limit

      def initialize(degrade_after: 2, quarantine_after: 3, recover_after: 2, probe_limit: 1)
        @degrade_after = normalize_positive(degrade_after, "degrade_after")
        @quarantine_after = normalize_positive(quarantine_after, "quarantine_after")
        @recover_after = normalize_positive(recover_after, "recover_after")
        @probe_limit = normalize_positive(probe_limit, "probe_limit")
        raise ArgumentError, "quarantine_after must not be below degrade_after" if quarantine_after < degrade_after
        freeze
      end

      def to_h
        {
          degrade_after: degrade_after,
          quarantine_after: quarantine_after,
          recover_after: recover_after,
          probe_limit: probe_limit
        }.freeze
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
                  :probe_in_flight, :probe_limit

      def initialize(provider_id:, state: :healthy, operational_failure_count: 0,
                     consecutive_failure_count: 0, consecutive_success_count: 0,
                     probe_in_flight: 0, probe_limit: 1)
        @provider_id = normalize_provider_id(provider_id)
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
        {
          provider_id: provider_id,
          state: state,
          operational_failure_count: operational_failure_count,
          consecutive_failure_count: consecutive_failure_count,
          consecutive_success_count: consecutive_success_count,
          probe_in_flight: probe_in_flight,
          probe_limit: probe_limit
        }.freeze
      end

      private

      def normalize_provider_id(provider_id)
        normalized = provider_id.to_s.strip
        raise ArgumentError, "provider id must be non-empty" if normalized.empty?

        normalized.freeze
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
      SIGNALS = %i[operational_failure operational_success timeout provider_failure recipient_failure].freeze
      ATTRIBUTIONS = %i[provider recipient downstream policy unknown].freeze

      attr_reader :policy

      def initialize(policy: HealthPolicy.new)
        unless policy.is_a?(HealthPolicy)
          raise ArgumentError, "policy must be HealthPolicy"
        end

        @policy = policy
        @states = {}
      end

      def snapshot(provider_id)
        normalized_provider_id = normalize_provider_id(provider_id)
        state = @states[normalized_provider_id]
        return default_snapshot(normalized_provider_id) unless state

        state.snapshot
      end

      def provider_ids
        @states.keys.sort.freeze
      end

      def ensure_provider(provider_id)
        normalized_provider_id = normalize_provider_id(provider_id)
        @states[normalized_provider_id] ||= MutableState.new(normalized_provider_id, @policy.probe_limit)
        nil
      end

      def reserve_exposure(provider_id, owner: nil)
        normalized_provider_id = normalize_provider_id(provider_id)
        normalized_owner = normalize_owner(owner) unless owner.nil?
        ensure_provider(normalized_provider_id)
        state = @states[normalized_provider_id]
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

      def release_exposure(provider_id, owner: nil)
        state = @states[normalize_provider_id(provider_id)]
        return unless state

        if owner
          state.release_operation_probe(normalize_owner(owner))
        else
          state.release_direct_probe
        end
        promote_if_recovered(state)
      end

      def observe(provider_id:, signal:, attribution: :unknown, release_exposure: true)
        normalized_release_exposure = normalize_boolean(release_exposure, "release_exposure")
        normalized_signal = normalize_enum(signal, SIGNALS, "health signal")
        normalized_attribution = normalize_enum(attribution, ATTRIBUTIONS, "health attribution")

        normalized_provider_id = normalize_provider_id(provider_id)
        ensure_provider(normalized_provider_id)
        state = @states[normalized_provider_id]
        before = state.snapshot
        if normalized_signal == :recipient_failure || normalized_attribution != :provider
          return [before, before]
        end

        if %i[operational_failure timeout provider_failure].include?(normalized_signal)
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

        [before, state.snapshot]
      end

      private

      def normalize_provider_id(provider_id)
        normalized = provider_id.to_s.strip
        raise ArgumentError, "provider id must be non-empty" if normalized.empty?

        normalized
      end

      def normalize_owner(owner)
        normalized = owner.to_s.strip
        raise ArgumentError, "probe owner must be non-empty" if normalized.empty?

        normalized
      end

      def normalize_boolean(value, label)
        return value if value == true || value == false

        raise ArgumentError, "#{label} must be boolean"
      end

      def normalize_enum(value, allowed, label)
        RubyRouting::Enum.normalize(value, allowed, label)
      end

      def default_snapshot(provider_id)
        ProviderHealthSnapshot.new(provider_id: provider_id, probe_limit: @policy.probe_limit)
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
          @provider_id = provider_id.to_s
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

        def snapshot
          ProviderHealthSnapshot.new(
            provider_id: provider_id,
            state: state,
            operational_failure_count: operational_failure_count,
            consecutive_failure_count: consecutive_failure_count,
            consecutive_success_count: consecutive_success_count,
            probe_in_flight: probe_in_flight,
            probe_limit: @probe_limit
          )
        end
      end
    end
  end
end
