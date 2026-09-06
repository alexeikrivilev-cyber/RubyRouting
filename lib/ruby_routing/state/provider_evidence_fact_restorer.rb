# frozen_string_literal: true

module RubyRouting
  module State
    # Replays provider-derived transport, health and quality evidence. The
    # coordinator supplies current projections and cross-fact validation while
    # retaining durable publication and atomic transaction ownership.
    class ProviderEvidenceFactRestorer
      def initialize(health_controller:, quality_controller:, payout_state:,
                     restored_observations:, restored_transport_sources:,
                     restored_health_signal_sources:, restored_quality_signal_sources:,
                     pending_health_transitions:, provider_identity:, operation_identity:,
                     enum_value:, validate_provider_system_fact:)
        @health_controller = health_controller
        @quality_controller = quality_controller
        @payout_state = payout_state
        @restored_observations = restored_observations
        @restored_transport_sources = restored_transport_sources
        @restored_health_signal_sources = restored_health_signal_sources
        @restored_quality_signal_sources = restored_quality_signal_sources
        @pending_health_transitions = pending_health_transitions
        @provider_identity = provider_identity
        @operation_identity = operation_identity
        @enum_value = enum_value
        @validate_provider_system_fact = validate_provider_system_fact
      end

      def apply(fact)
        case fact.type
        when :transport_classified
          validate_transport_classification!(fact)
          true
        when :health_signal
          restore_health_signal!(fact)
          true
        when :quality_signal
          restore_quality_signal!(fact)
          true
        when :health_state_changed
          validate_health_state_change!(fact)
          true
        else
          false
        end
      end

      private

      def validate_transport_classification!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        operation_id = @operation_identity.call(payload, :operation_id)
        attempt = state.operations.fetch(operation_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "transport classification references unknown operation #{operation_id}"
        end
        kind = @enum_value.call(
          payload,
          :kind,
          RubyRouting::ProviderTransportResult::KINDS,
          "transport kind"
        )
        unless attempt.provider_id == @provider_identity.call(payload, :provider_id) &&
               attempt.attempt_id == @operation_identity.call(payload, :attempt_id)
          raise RubyRouting::State::DurableCorruptionError,
            "transport classification does not match operation #{operation_id}"
        end
        source_key, observation = restored_observation_source!(payload)
        unless observation[:provider_id] == attempt.provider_id &&
               observation[:operation_id] == operation_id &&
               observation[:attempt_id] == @operation_identity.call(payload, :attempt_id) &&
               observation[:transport_kind] == kind
          raise RubyRouting::State::DurableCorruptionError,
            "transport classification does not match source observation #{source_key.inspect}"
        end
        if @restored_transport_sources.call.key?(source_key)
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate transport classification for observation #{source_key.inspect}"
        end
        @restored_transport_sources.call[source_key] = true
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed transport classification: #{error.message}"
      end

      def restored_observation_source!(payload, observation_id_key: :observation_id)
        observation_id = payload.fetch(observation_id_key)
        source_payout_id = payload.fetch(:source_payout_id)
        unless observation_id.is_a?(String) && !observation_id.empty? && observation_id == observation_id.strip &&
               source_payout_id.is_a?(String) && !source_payout_id.empty? && source_payout_id == source_payout_id.strip
          raise RubyRouting::State::DurableCorruptionError,
            "observation-derived fact source must use canonical non-empty strings"
        end

        source_key = [source_payout_id, observation_id].freeze
        observation = @restored_observations.call[source_key]
        unless observation
          raise RubyRouting::State::DurableCorruptionError,
            "observation-derived fact references unknown observation #{source_key.inspect}"
        end

        [source_key, observation]
      end

      def validate_health_state_change!(fact)
        payload = fact.payload
        provider_id = @provider_identity.call(payload, :provider_id)
        validate_provider_system_fact(fact, provider_id, require_registered: :historical)
        from = @enum_value.call(
          payload,
          :from,
          RubyRouting::Routing::ProviderHealthSnapshot::STATES,
          "health state"
        )
        to = @enum_value.call(
          payload,
          :to,
          RubyRouting::Routing::ProviderHealthSnapshot::STATES,
          "health state"
        )
        states = RubyRouting::Routing::ProviderHealthSnapshot::STATES
        unless states.include?(from) && states.include?(to) && from != to
          raise RubyRouting::State::DurableCorruptionError,
            "invalid health state transition #{from.inspect}->#{to.inspect}"
        end
        expected_transition = @pending_health_transitions.call.delete(provider_id)
        unless expected_transition == [from, to]
          raise RubyRouting::State::DurableCorruptionError,
            "health state transition does not match preceding signal for #{provider_id}"
        end
        current = health_controller.snapshot(provider_id)
        unless current.state == to
          raise RubyRouting::State::DurableCorruptionError,
            "health state change does not match provider #{provider_id}"
        end
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed health state change: #{error.message}"
      end

      def restore_health_signal!(fact)
        payload = fact.payload
        provider_id = @provider_identity.call(payload, :provider_id)
        validate_provider_system_fact(fact, provider_id, require_registered: :historical)
        unless payload.fetch(:policy) == health_controller.policy.to_h
          raise RubyRouting::State::DurableCorruptionError,
            "health signal policy does not match #{provider_id}"
        end
        release_exposure = payload.fetch(:release_exposure, true)
        unless release_exposure == true || release_exposure == false
          raise RubyRouting::State::DurableCorruptionError,
            "health signal release_exposure must be boolean for #{provider_id}"
        end
        source_kind = @enum_value.call(
          payload,
          :source_kind,
          %i[manual observation],
          "health signal source kind"
        )
        unless %i[manual observation].include?(source_kind)
          raise RubyRouting::State::DurableCorruptionError,
            "health signal source kind is unsupported for #{provider_id}"
        end
        source_key = nil
        if source_kind == :observation
          source_key, observation = restored_observation_source!(payload, observation_id_key: :source)
          expected_signal = health_signal_for_observation_payload(observation)
          signal = @enum_value.call(
            payload,
            :signal,
            RubyRouting::Routing::HealthController::SIGNALS,
            "health signal"
          )
          observation_attribution = @enum_value.call(
            observation,
            :attribution,
            RubyRouting::Routing::HealthController::ATTRIBUTIONS,
            "health attribution"
          )
          attribution = @enum_value.call(
            payload,
            :attribution,
            RubyRouting::Routing::HealthController::ATTRIBUTIONS,
            "health attribution"
          )
          unless observation[:provider_id] == provider_id &&
                 expected_signal == signal &&
                 observation_attribution == attribution &&
                 release_exposure == false
            raise RubyRouting::State::DurableCorruptionError,
              "health signal does not match source observation #{source_key.inspect}"
          end
          if @restored_health_signal_sources.call.key?(source_key)
            raise RubyRouting::State::DurableCorruptionError,
              "duplicate health signal for observation #{source_key.inspect}"
          end
        elsif payload[:source] || payload[:source_payout_id]
          raise RubyRouting::State::DurableCorruptionError,
            "manual health signal cannot carry an observation source for #{provider_id}"
        end

        before, after = health_controller.observe(
          provider_id: provider_id,
          signal: payload.fetch(:signal),
          attribution: payload.fetch(:attribution),
          release_exposure: release_exposure
        )
        @restored_health_signal_sources.call[source_key] = true if source_key
        if before.state == after.state
          @pending_health_transitions.call.delete(provider_id)
        else
          @pending_health_transitions.call[provider_id] = [before.state, after.state]
        end
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed health signal: #{error.message}"
      end

      def restore_quality_signal!(fact)
        payload = fact.payload
        provider_id = @provider_identity.call(payload, :provider_id)
        validate_provider_system_fact(fact, provider_id, require_registered: :historical)
        source_key, observation = restored_observation_source!(payload)
        status = @enum_value.call(
          payload,
          :status,
          RubyRouting::NormalizedOutcome::STATUSES,
          "outcome status"
        )
        attribution = @enum_value.call(
          payload,
          :attribution,
          RubyRouting::NormalizedOutcome::ATTRIBUTIONS,
          "outcome attribution"
        )
        unless observation[:applied] == true &&
               observation[:provider_id] == provider_id &&
               @enum_value.call(
                 observation,
                 :status,
                 RubyRouting::NormalizedOutcome::STATUSES,
                 "outcome status"
               ) == status &&
               @enum_value.call(
                 observation,
                 :attribution,
                 RubyRouting::NormalizedOutcome::ATTRIBUTIONS,
                 "outcome attribution"
               ) == attribution &&
               observation[:safe_to_release] == payload.fetch(:safe_to_release)
          raise RubyRouting::State::DurableCorruptionError,
            "quality signal does not match source observation #{source_key.inspect}"
        end
        if @restored_quality_signal_sources.call.key?(source_key)
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate quality signal for observation #{source_key.inspect}"
        end
        _before, after = quality_controller.observe(
          provider_id: provider_id,
          context_key: payload.fetch(:context_key, []),
          outcome: RubyRouting::NormalizedOutcome.new(
            status: payload.fetch(:status),
            attribution: payload.fetch(:attribution),
            safe_to_release: payload[:safe_to_release]
          )
        )
        unless after.sample_count == payload.fetch(:sample_count) &&
               after.score == payload.fetch(:score) &&
               after.context_key == payload.fetch(:context_key, []) &&
               after.evidence_scope == @enum_value.call(
                 payload,
                 :evidence_scope,
                 RubyRouting::Routing::ProviderQualitySnapshot::EVIDENCE_SCOPES,
                 "quality evidence scope"
               )
          raise RubyRouting::State::DurableCorruptionError,
            "quality signal projection does not match source observation #{source_key.inspect}"
        end
        @restored_quality_signal_sources.call[source_key] = true
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed quality signal: #{error.message}"
      end

      def health_controller
        @health_controller.call
      end

      def quality_controller
        @quality_controller.call
      end

      def validate_provider_system_fact(fact, provider_id, require_registered:)
        @validate_provider_system_fact.call(
          fact,
          provider_id,
          require_registered: require_registered
        )
      end

      def health_signal_for_observation_payload(payload)
        outcome = RubyRouting::NormalizedOutcome.new(
          status: payload.fetch(:status),
          attribution: payload.fetch(:attribution),
          safe_to_release: payload.fetch(:safe_to_release)
        )
        return :provider_failure if outcome.provider_failure?
        return :operational_success if outcome.success? && outcome.attribution == :provider
        return :timeout if outcome.status == :unknown && outcome.attribution == :provider

        nil
      rescue KeyError, ArgumentError, TypeError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed source observation outcome: #{error.message}"
      end
    end
  end
end
