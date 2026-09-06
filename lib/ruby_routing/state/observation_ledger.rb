# frozen_string_literal: true

module RubyRouting
  module State
    # Owns observation identity, deduplication and provider-event ordering.
    # Lifecycle effects and fact publication remain with the coordinator and
    # LifecycleLedger so the atomic facade keeps one transaction boundary.
    class ObservationLedger
      class Decision
        attr_reader :duplicate, :applies, :conflict

        def initialize(duplicate:, applies:, conflict:)
          @duplicate = !!duplicate
          @applies = !!applies
          @conflict = !!conflict
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
      end

      def observe(seen_observations:, current_operation_id:, attempt:, observation:)
        signature = signature_for(observation)
        existing = seen_observations[observation.observation_id]
        if existing
          unless existing == signature
            raise ArgumentError, "observation id was reused with different payload"
          end

          return Decision.new(duplicate: true, applies: false, conflict: false)
        end

        applies = current_operation_id == observation.operation_id && observation_applies?(attempt, observation)
        conflict = current_operation_id != observation.operation_id && late_monetary_conflict?(attempt, observation)
        seen_observations[observation.observation_id] = signature
        Decision.new(duplicate: false, applies: applies, conflict: conflict)
      end

      def restore(seen_observations:, payout_id:, payload:, current_operation_id:, attempt:)
        observation_id = payload.fetch(:observation_id)
        validate_restore_payload!(observation_id, payload)
        observation = observation_from_payload(payout_id, payload)
        expected_applies = current_operation_id == observation.operation_id &&
          observation_applies?(attempt, observation)
        expected_conflict = current_operation_id != observation.operation_id &&
          late_monetary_conflict?(attempt, observation)
        unless payload[:applied] == expected_applies && payload[:conflict] == expected_conflict
          raise ArgumentError, "durable observation decision does not match restored lifecycle state"
        end
        signature = signature_from_payload(payload, payout_id: payout_id)
        existing = seen_observations[observation_id]
        if existing
          unless existing == signature
            raise ArgumentError, "observation id was reused with different payload"
          end

          return Decision.new(duplicate: true, applies: false, conflict: false)
        end

        seen_observations[observation_id] = signature
        Decision.new(duplicate: false, applies: !!payload[:applied], conflict: !!payload[:conflict])
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

      def late_monetary_conflict?(attempt, observation)
        observation.outcome.success? && %i[released terminated].include?(attempt.phase)
      end

      def signature_for(observation)
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
          transport_kind: payload[:transport_kind]
        )
      end
    end
  end
end
