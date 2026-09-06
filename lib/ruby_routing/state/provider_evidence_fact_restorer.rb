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
        routing_context = normalized_routing_context(payload[:routing_context])
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
        expected_transition = @pending_health_transitions.call.delete(
          health_state_key(provider_id, routing_context)
        )
        unless expected_transition == [from, to]
          raise RubyRouting::State::DurableCorruptionError,
            "health state transition does not match preceding signal for #{provider_id}"
        end
        current = health_controller.snapshot(provider_id, routing_context: routing_context)
        unless current.state == to
          raise RubyRouting::State::DurableCorruptionError,
            "health state change does not match provider #{provider_id}"
        end
      rescue KeyError, ArgumentError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed health state change: #{error.message}"
      end

      def restore_health_signal!(fact)
        payload = fact.payload
        provider_id = @provider_identity.call(payload, :provider_id)
        routing_context = normalized_routing_context(payload[:routing_context])
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
          payout_state = @payout_state.call(payload.fetch(:source_payout_id))
          expected_context = normalized_routing_context(payout_state.intent.routing_context)
          unless expected_context == routing_context
            raise RubyRouting::State::DurableCorruptionError,
              "health signal route context does not match source observation #{source_key.inspect}"
          end
          expected_signal = health_signal_for_observation_payload(observation)
          expected_attribution = health_attribution_for_observation_payload(observation)
          signal = @enum_value.call(
            payload,
            :signal,
            RubyRouting::Routing::HealthController::SIGNALS,
            "health signal"
          )
          attribution = @enum_value.call(
            payload,
            :attribution,
            RubyRouting::Routing::HealthController::ATTRIBUTIONS,
            "health attribution"
          )
          unless observation[:provider_id] == provider_id &&
                 expected_signal == signal &&
                 expected_attribution == attribution &&
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
          release_exposure: release_exposure,
          routing_context: routing_context
        )
        @restored_health_signal_sources.call[source_key] = true if source_key
        transition_key = health_state_key(provider_id, routing_context)
        if before.state == after.state
          @pending_health_transitions.call.delete(transition_key)
        else
          @pending_health_transitions.call[transition_key] = [before.state, after.state]
        end
      rescue KeyError, ArgumentError, TypeError, NoMethodError => error
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
        if payload.key?(:observed_at) && observation[:observed_at] && observation[:observed_at] != payload[:observed_at]
          raise RubyRouting::State::DurableCorruptionError,
            "quality signal timestamp does not match source observation #{source_key.inspect}"
        end
        source_state = @payout_state.call(payload.fetch(:source_payout_id))
        source_currency = source_state.intent.money.currency
        if payload.key?(:currency) && payload[:currency] != source_currency
          raise RubyRouting::State::DurableCorruptionError,
            "quality signal currency does not match source payout #{source_key.inspect}"
        end
        if @restored_quality_signal_sources.call.key?(source_key)
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate quality signal for observation #{source_key.inspect}"
        end
        quality_controller.observe(
          provider_id: provider_id,
          context_key: payload.fetch(:context_key, []),
          routing_context: payload[:routing_context],
          currency: payload[:currency],
          observed_at: payload[:observed_at],
          outcome: RubyRouting::NormalizedOutcome.new(
            status: payload.fetch(:status),
            attribution: payload.fetch(:attribution),
            safe_to_release: payload[:safe_to_release]
          )
        )
        after = quality_controller.evidence_snapshot(
          provider_id,
          context_key: payload.fetch(:context_key, []),
          routing_context: payload[:routing_context],
          currency: payload[:currency]
        )
        unless after.successful_samples == payload.fetch(:successful_samples, after.successful_samples) &&
               after.failed_samples == payload.fetch(:failed_samples, after.failed_samples) &&
               after.sample_count == payload.fetch(:sample_count) &&
               after.score == payload.fetch(:score) &&
               after.minimum_samples == payload.fetch(:minimum_samples, after.minimum_samples) &&
               after.prior_successes == payload.fetch(:prior_successes, after.prior_successes) &&
               after.prior_failures == payload.fetch(:prior_failures, after.prior_failures) &&
               after.evidence_window == payload.fetch(:evidence_window, after.evidence_window) &&
               after.context_key == payload.fetch(:context_key, []) &&
               (!payload.key?(:routing_context) || after.routing_context&.to_h == payload[:routing_context]) &&
               (!payload.key?(:currency) || after.currency == payload[:currency]) &&
               (!payload.key?(:observed_at) || after.last_observed_at == payload[:observed_at]) &&
               (!payload.key?(:last_observed_at) || after.last_observed_at == payload[:last_observed_at]) &&
               (!payload.key?(:max_evidence_age_seconds) ||
                after.max_evidence_age_seconds == payload[:max_evidence_age_seconds]) &&
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
      rescue ArgumentError, KeyError, TypeError, NoMethodError => error
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
        transport_kind = payload[:transport_kind]
        if transport_kind
          normalized_transport_kind = @enum_value.call(
            payload,
            :transport_kind,
            RubyRouting::ProviderTransportResult::KINDS,
            "transport kind"
          )
          return :transport_failure if normalized_transport_kind == :definitely_not_sent
          return :timeout_pressure if normalized_transport_kind == :ambiguous_after_possible_send
        end

        outcome = RubyRouting::NormalizedOutcome.new(
          status: payload.fetch(:status),
          attribution: payload.fetch(:attribution),
          safe_to_release: payload.fetch(:safe_to_release)
        )
        signal = if outcome.status == :temporary_provider_failure && outcome.attribution == :provider
          :provider_service_error
        elsif outcome.provider_failure?
          :provider_failure
        elsif outcome.success? && outcome.attribution == :provider
          :operational_success
        elsif outcome.status == :unknown && outcome.attribution == :provider
          :timeout
        end
        if latency_pressure_for_observation_payload?(payload) && (signal.nil? || signal == :operational_success)
          signal = :latency_pressure
        end
        signal
      rescue KeyError, ArgumentError, TypeError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed source observation outcome: #{error.message}"
      end

      def health_attribution_for_observation_payload(payload)
        # Transport-derived health attribution is intentionally independent
        # from the observation's economic attribution. Ambiguous send state is
        # still UNKNOWN for payout ownership, but is provider evidence for
        # future admission protection.
        return :provider if payload[:transport_kind]

        @enum_value.call(
          payload,
          :attribution,
          RubyRouting::Routing::HealthController::ATTRIBUTIONS,
          "health attribution"
        )
      rescue KeyError, ArgumentError, TypeError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed source observation attribution: #{error.message}"
      end

      def latency_pressure_for_observation_payload?(payload)
        threshold_ms = health_controller.policy.latency_threshold_ms
        duration = payload[:interaction_duration_seconds]
        duration && threshold_ms && duration * 1000 > threshold_ms &&
          payload.fetch(:attribution) == :provider
      rescue KeyError, ArgumentError, TypeError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed source observation interaction duration: #{error.message}"
      end

      def normalized_routing_context(value)
        RubyRouting::Routing::HealthController.canonical_routing_context(value)
      rescue ArgumentError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed health routing context: #{error.message}"
      end

      def health_state_key(provider_id, routing_context)
        return provider_id unless routing_context

        [provider_id, routing_context.to_h].freeze
      end
    end
  end
end
