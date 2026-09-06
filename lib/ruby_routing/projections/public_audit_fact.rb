# frozen_string_literal: true

require "time"

module RubyRouting
  module Projections
    # Projects durable facts for the public audit boundary. Durable facts may
    # retain recipient data and provider transport details for recovery, but a
    # public audit response must expose only an explicit, case-relevant safe
    # subset. Unknown or newly-added payload fields are redacted by default.
    class PublicAuditFact
      PAYLOAD_FIELDS = {
        provider_opportunity_registered: %i[provider_id capacity throughput health_policy quality_policy definition],
        provider_opportunity_removed: %i[provider_id removed_at],
        intent_registered: %i[money created_at],
        policy_registered: %i[policy_id policy_epoch policy_scope policy_fingerprint definition static_feasibility],
        opportunity_evaluated: %i[
          policy_id policy_epoch policy_scope policy_fingerprint configuration_revision measure_kind currency
          opportunities functional_provider_ids feasible_provider_ids exclusions exclusion_codes
          allocation_exclusions static_policy_feasibility runtime_feasibility soft_violations
          allocation_snapshot allocation_key capacity throughput health quality ranking health_policy
          available_provider_ids previous_outcome evaluated_at
        ],
        decision_committed: %i[
          action provider_id operation_id attempt_id role policy_epoch policy_id policy_scope
          configuration_revision measure_kind currency reasons reason_codes snapshot_revision allocation_discrepancy
          allocation_candidates allocation_deviation_cause allocation_deviation_recoverability
          allocation_tolerance allocation_share_violations optimization_trace runtime_feasibility
          soft_constraint_violations measure allocation_key committed_at contract available_provider_ids
        ],
        allocation_committed: %i[
          policy_id policy_scope policy_fingerprint allocation_key policy_epoch measure_kind currency
          provider_id operation_id attempt_id measure role capacity_reserved
        ],
        capacity_reserved: %i[provider_id operation_id amount],
        capacity_released: %i[provider_id operation_id amount],
        ownership_acquired: %i[provider_id operation_id attempt_id acquired_at],
        attempt_started: %i[attempt_id operation_id provider_id action started_at],
        provider_execution_failed: %i[provider_id operation_id attempt_id action phase interaction_index failed_at],
        provider_observed: %i[
          observation_id operation_id attempt_id provider_id status attribution safe_to_release sequence
          observed_at transport_kind interaction_duration_seconds applied conflict recovery_schedule
        ],
        provider_interaction_completed: %i[observation_id operation_id attempt_id provider_id],
        ownership_released: %i[provider_id operation_id attempt_id reason],
        settlement_recorded: %i[provider_id operation_id outcome measure settled_at],
        operation_phase_changed: %i[operation_id attempt_id provider_id from to changed_at],
        transport_classified: %i[observation_id source_payout_id operation_id attempt_id provider_id kind],
        economic_conflict: %i[provider_id operation_id attempt_id observation_id reason],
        reversal_recorded: %i[reversal_id provider_id operation_id amount reason],
        health_signal: %i[
          provider_id signal attribution source_kind source source_payout_id release_exposure policy
          routing_context
        ],
        health_state_changed: %i[provider_id from to routing_context],
        health_exposure_reserved: %i[provider_id operation_id attempt_id routing_context],
        health_exposure_released: %i[provider_id operation_id attempt_id routing_context],
        quality_signal: %i[
          observation_id source_payout_id provider_id status attribution safe_to_release successful_samples
          failed_samples sample_count score minimum_samples prior_successes prior_failures evidence_window
          context_key evidence_scope routing_context observed_at last_observed_at
          max_evidence_age_seconds stale
        ],
        reconciliation_blocked: %i[operation_id attempt_id provider_id reason elapsed blocked_at],
        throughput_consumed: %i[provider_id operation_id consumed_at budget],
        provider_runtime_changed: %i[
          provider_id available capacity_available enabled health_available throughput_available
        ],
        payout_state_changed: [].freeze
      }.transform_values(&:freeze).freeze

      attr_reader :sequence, :type, :fact_id, :payout_id, :payload, :redacted_fields

      def self.from_fact(fact)
        new(
          sequence: fact.sequence,
          type: fact.type,
          fact_id: fact.fact_id,
          payout_id: fact.payout_id,
          payload: fact.payload
        )
      end

      def initialize(sequence:, type:, fact_id:, payout_id:, payload:)
        unless payload.is_a?(Hash)
          raise ArgumentError, "public audit fact payload must be a Hash"
        end

        @sequence = sequence
        @type = type
        @fact_id = fact_id
        @payout_id = payout_id
        fields = PAYLOAD_FIELDS.fetch(type, [])
        @payload = fields.each_with_object({}) do |field, copy|
          next unless payload.key?(field) || payload.key?(field.to_s)

          value = payload.key?(field) ? payload.fetch(field) : payload.fetch(field.to_s)
          copy[field] = self.class.send(:safe_value, value)
        end.freeze
        @redacted_fields = payload.keys
          .reject { |key| fields.any? { |field| field.to_s == key.to_s } }
          .map(&:to_s)
          .uniq
          .sort
          .freeze
        freeze
      end

      def to_h
        {
          sequence: sequence,
          type: type,
          fact_id: fact_id,
          payout_id: payout_id,
          payload: payload,
          redacted_fields: redacted_fields
        }.freeze
      end

      class << self
        private

        def safe_value(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, nested), copy|
              copy[safe_key(key)] = safe_value(nested)
            end.freeze
          when Array
            value.map { |nested| safe_value(nested) }.freeze
          when RubyRouting::Money
            { amount_minor: value.amount_minor, currency: value.currency }.freeze
          when Rational
            { numerator: value.numerator, denominator: value.denominator }.freeze
          when Time
            value.iso8601(9).freeze
          when Symbol
            value.to_s.freeze
          when String, Integer, TrueClass, FalseClass, NilClass
            value
          else
            raise ArgumentError, "unsupported public audit value #{value.class}"
          end
        end

        def safe_key(key)
          case key
          when String, Symbol, Integer
            key.is_a?(Symbol) ? key.to_s.freeze : key
          else
            raise ArgumentError, "unsupported public audit key #{key.class}"
          end
        end
      end
    end
  end
end
