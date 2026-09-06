# frozen_string_literal: true

module RubyRouting
  module State
    # Owns observation identity, deduplication and provider-event ordering.
    # Lifecycle effects and fact publication remain with the coordinator and
    # LifecycleLedger so the atomic facade keeps one transaction boundary.
    class ObservationLedger
      def self.advance_sequence!(attempt, sequence)
        return unless attempt.contract&.authoritative_sequence
        return if sequence.nil?

        previous = attempt.last_observation_sequence
        attempt.last_observation_sequence = sequence if previous.nil? || sequence > previous
      end

      class Decision
        attr_reader :duplicate, :applies, :conflict, :health_evidence,
                    :causal_hold, :causal_contradiction, :causal_completion

        def initialize(duplicate:, applies:, conflict:, health_evidence: false, causal_hold: false,
                       causal_contradiction: false, causal_completion: false)
          @duplicate = !!duplicate
          @applies = !!applies
          @conflict = !!conflict
          @health_evidence = !!health_evidence
          @causal_hold = !!causal_hold
          @causal_contradiction = !!causal_contradiction
          @causal_completion = !!causal_completion
          freeze
        end

        def duplicate?
          duplicate
        end

        def applies?
          applies
        end

        def conflict?
          conflict
        end

        def health_evidence?
          health_evidence
        end

        def causal_hold?
          causal_hold
        end

        def causal_contradiction?
          causal_contradiction
        end

        def causal_completion?
          causal_completion
        end
      end

      def observe(seen_observations:, current_operation_id:, attempt:, observation:, causal_hold: false,
                  owning_completion: false)
        signature = signature_for(observation)
        existing = seen_observations[observation.observation_id]
        if existing
          unless existing_signature(existing) == signature
            raise ArgumentError, "observation id was reused with different payload"
          end

          causal_completion = owning_completion && causal_hold_completion_candidate?(existing, observation)
          if causal_completion
            seen_observations[observation.observation_id] = existing.merge(
              causal_hold_completed: true
            ).freeze
          end
          return Decision.new(
            duplicate: true,
            applies: false,
            conflict: false,
            causal_completion: causal_completion
          )
        end

        unless causal_hold == true || causal_hold == false
          raise ArgumentError, "causal hold must be boolean"
        end
        unless owning_completion == true || owning_completion == false
          raise ArgumentError, "owning completion must be boolean"
        end
        applies = !causal_hold && current_operation_id == observation.operation_id &&
          observation_applies?(attempt, observation)
        causal_contradiction = !causal_hold && causal_hold_conflict?(seen_observations, observation)
        conflict = !causal_hold && (
          (current_operation_id != observation.operation_id && late_monetary_conflict?(attempt, observation)) ||
          causal_contradiction
        )
        health_evidence = observation_health_evidence?(attempt, observation)
        seen_observations[observation.observation_id] = observation_record(
          signature: signature,
          operation_id: observation.operation_id,
          applies: applies,
          conflict: conflict,
          health_evidence: health_evidence,
          causal_hold: causal_hold,
          causal_contradiction: causal_contradiction,
          causal_hold_completed: false
        )
        self.class.advance_sequence!(attempt, observation.sequence)
        Decision.new(
          duplicate: false,
          applies: applies,
          conflict: conflict,
          health_evidence: health_evidence,
          causal_hold: causal_hold,
          causal_contradiction: causal_contradiction,
          causal_completion: false
        )
      end

      def complete_causal_hold!(seen_observations:, payout_id:, observation_payload:)
        observation = observation_from_payload(payout_id, observation_payload)
        existing = seen_observations[observation.observation_id]
        unless existing_signature(existing) == signature_for(observation) &&
               causal_hold_completion_candidate?(existing, observation)
          raise RubyRouting::State::DurableCorruptionError,
            "causal completion does not match an active held observation"
        end

        seen_observations[observation.observation_id] = existing.merge(
          causal_hold_completed: true
        ).freeze
        true
      end

      def restore(seen_observations:, payout_id:, payload:, current_operation_id:, attempt:)
        observation_id = payload.fetch(:observation_id)
        validate_restore_payload!(observation_id, payload)
        observation = observation_from_payload(payout_id, payload)
        signature = signature_from_payload(payload, payout_id: payout_id)
        existing = seen_observations[observation_id]
        if existing
          unless existing_signature(existing) == signature
            raise ArgumentError, "observation id was reused with different payload"
          end
          validate_duplicate_decision!(existing, payload)
          return Decision.new(duplicate: true, applies: false, conflict: false)
        end

        persisted_causal_hold = payload.fetch(:causal_hold, false)
        expected_causal_hold = if persisted_causal_hold &&
                                  current_operation_id == observation.operation_id &&
                                  !payload[:applied] &&
                                  unresolved_phase?(attempt.phase) &&
                                  causal_release_candidate?(observation)
          true
        else
          causal_hold_for(
            current_operation_id: current_operation_id,
            attempt: attempt,
            observation: observation,
            applied: payload[:applied]
          )
        end
        expected_applies = current_operation_id == observation.operation_id &&
          !expected_causal_hold && observation_applies?(attempt, observation)
        expected_causal_contradiction = !expected_causal_hold &&
          causal_hold_conflict?(seen_observations, observation)
        expected_conflict = current_operation_id != observation.operation_id &&
          !expected_causal_hold && late_monetary_conflict?(attempt, observation)
        expected_conflict ||= expected_causal_contradiction
        expected_health_evidence = observation_health_evidence?(attempt, observation)

        unless persisted_causal_hold == expected_causal_hold
          raise ArgumentError, "durable observation causal hold does not match lifecycle state"
        end
        unless payload[:applied] == expected_applies && payload[:conflict] == expected_conflict
          raise ArgumentError, "durable observation decision does not match restored lifecycle state"
        end
        if payload.key?(:health_evidence) && payload[:health_evidence] != expected_health_evidence
          raise ArgumentError, "durable observation health evidence does not match provider ordering"
        end
        seen_observations[observation_id] = observation_record(
          signature: signature,
          operation_id: observation.operation_id,
          applies: expected_applies,
          conflict: expected_conflict,
          health_evidence: expected_health_evidence,
          causal_hold: expected_causal_hold,
          causal_contradiction: expected_causal_contradiction,
          causal_hold_completed: false
        )
        self.class.advance_sequence!(attempt, observation.sequence)
        Decision.new(
          duplicate: false,
          applies: !!payload[:applied],
          conflict: !!payload[:conflict],
          health_evidence: expected_health_evidence,
          causal_hold: expected_causal_hold,
          causal_contradiction: expected_causal_contradiction,
          causal_completion: false
        )
      end

      private

      def validate_restore_payload!(observation_id, payload)
        unless observation_id.is_a?(String) && !observation_id.strip.empty? && observation_id == observation_id.strip
          raise ArgumentError, "durable observation id must be a canonical non-empty String"
        end
        %i[provider_id operation_id attempt_id].each do |field|
          value = payload.fetch(field)
          unless value.is_a?(String) && !value.strip.empty? && value == value.strip
            raise ArgumentError, "durable observation #{field} must be a canonical non-empty String"
          end
        end
        unless [payload.fetch(:applied), payload.fetch(:conflict), payload.fetch(:safe_to_release)]
          .all? { |value| value == true || value == false }
          raise ArgumentError, "durable observation flags must be boolean"
        end
        sequence = payload[:sequence]
        unless sequence.nil? || (sequence.is_a?(Integer) && sequence >= 0)
          raise ArgumentError, "durable observation sequence must be a non-negative Integer or nil"
        end
        observed_at = payload[:observed_at]
        unless observed_at.nil? || observed_at.is_a?(Time)
          raise ArgumentError, "durable observation timestamp must be Time or nil"
        end
        duration = payload[:interaction_duration_seconds]
        unless duration.nil? ||
               ((duration.is_a?(Integer) || duration.is_a?(Rational)) && duration >= 0)
          raise ArgumentError, "durable observation interaction duration must be exact and non-negative"
        end
        health_evidence = payload[:health_evidence]
        unless health_evidence.nil? || health_evidence == true || health_evidence == false
          raise ArgumentError, "durable observation health evidence must be boolean or nil"
        end
        causal_hold = payload[:causal_hold]
        unless causal_hold.nil? || causal_hold == true || causal_hold == false
          raise ArgumentError, "durable observation causal hold must be boolean or nil"
        end
        unless symbol_value?(payload.fetch(:status), RubyRouting::NormalizedOutcome::STATUSES)
          raise ArgumentError, "durable observation status is unsupported"
        end
        unless symbol_value?(payload.fetch(:attribution), RubyRouting::NormalizedOutcome::ATTRIBUTIONS)
          raise ArgumentError, "durable observation attribution is unsupported"
        end
        transport_kind = payload[:transport_kind]
        unless transport_kind.nil? || symbol_value?(transport_kind, RubyRouting::ProviderTransportResult::KINDS)
          raise ArgumentError, "durable observation transport kind is unsupported"
        end
      rescue KeyError => error
        raise ArgumentError, "durable observation payload is incomplete: #{error.message}"
      end

      def symbol_value?(value, allowed)
        return false unless value.is_a?(String) || value.is_a?(Symbol)

        allowed.any? { |candidate| candidate.to_s == value.to_s }
      end

      def observation_applies?(attempt, observation)
        return false if %i[released settled terminated].include?(attempt.phase)

        if attempt.contract&.authoritative_sequence
          # Once a provider declares its sequence authoritative, an
          # unsequenced provider observation cannot safely establish or
          # replace lifecycle order. Transport classification is an exception:
          # it describes the initiating exchange, not a provider event.
          return true if observation.transport_kind && observation.sequence.nil?
          return false if observation.sequence.nil?
          return true if attempt.last_observation_sequence.nil?

          return observation.sequence > attempt.last_observation_sequence
        end

        previous = attempt.outcome
        return true if previous.nil?

        return false if previous.status == :unknown && observation.outcome.status == :pending

        true
      end

      # Provider health may use a late new observation, including a late
      # terminal result from a released operation, but an authoritative
      # provider's stale or unsequenced lifecycle event is not fresh
      # operational evidence. Transport classification remains admissible
      # without a provider event sequence because it describes the initiating
      # exchange itself.
      def observation_health_evidence?(attempt, observation)
        return true if observation.transport_kind
        return true unless attempt.contract&.authoritative_sequence

        sequence = observation.sequence
        return false if sequence.nil?

        previous = attempt.last_observation_sequence
        previous.nil? || sequence > previous
      end

      def late_monetary_conflict?(attempt, observation)
        return false unless %i[released terminated].include?(attempt.phase)

        observation.outcome.success? ||
          observation.transport_kind == :ambiguous_after_possible_send
      end

      def signature_for(observation)
        # Interaction duration is locally measured telemetry, not provider
        # event identity. The same provider observation may arrive once via an
        # external callback and once from the owning invocation with different
        # local timing measurements; retaining duration in the durable payload
        # must not turn that valid causal completion into identity reuse.
        [
          observation.payout_id,
          observation.provider_id,
          observation.operation_id,
          observation.attempt_id,
          observation.provider_reference,
          observation.outcome.status.to_s,
          observation.outcome.attribution.to_s,
          observation.outcome.provider_reference,
          observation.outcome.message,
          observation.outcome.safe_to_release?,
          observation.sequence,
          observation.observed_at,
          observation.transport_kind&.to_s
        ].freeze
      end

      def signature_from_payload(payload, payout_id:)
        [
          payout_id.to_s,
          payload.fetch(:provider_id),
          payload.fetch(:operation_id),
          payload.fetch(:attempt_id),
          payload[:provider_reference]&.to_s,
          payload.fetch(:status).to_s,
          payload.fetch(:attribution).to_s,
          payload[:outcome_provider_reference]&.to_s,
          payload[:message]&.to_s,
          payload[:safe_to_release],
          payload[:sequence],
          payload[:observed_at],
          payload[:transport_kind]&.to_s
        ].freeze
      end

      def observation_record(signature:, operation_id:, applies:, conflict:, health_evidence:, causal_hold:,
                             causal_contradiction:, causal_hold_completed:)
        {
          signature: signature,
          operation_id: operation_id,
          applies: !!applies,
          conflict: !!conflict,
          health_evidence: !!health_evidence,
          causal_hold: !!causal_hold,
          causal_contradiction: !!causal_contradiction,
          causal_hold_completed: !!causal_hold_completed
        }.freeze
      end

      def existing_signature(existing)
        return existing[:signature] if existing.is_a?(Hash) && existing.key?(:signature)

        existing
      end

      def validate_duplicate_decision!(existing, payload)
        return unless existing.is_a?(Hash) && existing.key?(:signature)

        unless payload[:applied] == existing[:applies] && payload[:conflict] == existing[:conflict]
          raise ArgumentError, "duplicate durable observation decision does not match original"
        end
        if payload.key?(:health_evidence) && payload[:health_evidence] != existing[:health_evidence]
          raise ArgumentError, "duplicate durable observation health evidence does not match original"
        end
        if payload.key?(:causal_hold) && payload[:causal_hold] != existing.fetch(:causal_hold, false)
          raise ArgumentError, "duplicate durable observation causal hold does not match original"
        end
      end

      def causal_hold_for(current_operation_id:, attempt:, observation:, applied:)
        current_operation_id == observation.operation_id &&
          !applied &&
          unresolved_phase?(attempt.phase) &&
          observation.outcome.provider_failure? &&
          causal_release_candidate?(observation)
      end

      def unresolved_phase?(phase)
        %i[committed dispatching resolving pending unknown reconciliation_blocked].include?(phase)
      end

      def causal_release_candidate?(observation)
        observation.outcome.safe_to_release? &&
          !observation.outcome.terminal_payout_failure?
      end

      def causal_hold_conflict?(seen_observations, observation)
        return false unless observation.outcome.success?

        seen_observations.values.any? do |record|
          record.is_a?(Hash) && record[:causal_hold] == true &&
            !record[:causal_hold_completed] &&
            record[:operation_id] == observation.operation_id
        end
      end

      def causal_hold_completion_candidate?(existing, observation)
        existing.is_a?(Hash) && existing[:causal_hold] == true &&
          !existing[:causal_hold_completed] &&
          existing[:operation_id] == observation.operation_id &&
          causal_release_candidate?(observation)
      end

      def observation_from_payload(payout_id, payload)
        RubyRouting::ProviderObservation.new(
          observation_id: payload.fetch(:observation_id),
          payout_id: payout_id,
          provider_id: payload.fetch(:provider_id),
          operation_id: payload.fetch(:operation_id),
          attempt_id: payload.fetch(:attempt_id),
          outcome: RubyRouting::NormalizedOutcome.new(
            status: payload.fetch(:status),
            attribution: payload.fetch(:attribution),
            provider_reference: payload[:outcome_provider_reference],
            message: payload[:message],
            safe_to_release: payload[:safe_to_release]
          ),
          provider_reference: payload[:provider_reference],
          sequence: payload[:sequence],
          observed_at: payload[:observed_at],
          transport_kind: payload[:transport_kind],
          interaction_duration_seconds: payload[:interaction_duration_seconds]
        )
      end
    end
  end
end
