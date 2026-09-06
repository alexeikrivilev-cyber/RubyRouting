# frozen_string_literal: true

module RubyRouting
  module State
    # Shared pure validation for durable raw-provider-failure evidence. Live
    # restore and replay still own their state transitions, but they must agree
    # on the identity, phase and interaction facts carried by this marker.
    class ProviderExecutionFailureEvidence
      ACTIONS = %i[assign retry_same resolve].freeze

      attr_reader :provider_id, :operation_id, :attempt_id, :action, :phase,
                  :interaction_index, :failed_at

      def self.from_payload(payload,
                            provider_identity: ->(source, key) {
                              RubyRouting::Identity.normalize(source.fetch(key), "provider id")
                            },
                            operation_identity: ->(source, key) {
                              RubyRouting::Identity.normalize(source.fetch(key), key.to_s)
                            },
                            enum: ->(source, key, allowed, label) {
                              RubyRouting::Enum.normalize(source.fetch(key), allowed, label)
                            })
        new(
          provider_id: provider_identity.call(payload, :provider_id),
          operation_id: operation_identity.call(payload, :operation_id),
          attempt_id: operation_identity.call(payload, :attempt_id),
          action: enum.call(payload, :action, ACTIONS, "provider failure action"),
          phase: enum.call(
            payload,
            :phase,
            RubyRouting::State::AttemptSnapshot::PHASES,
            "provider failure phase"
          ),
          interaction_index: payload.fetch(:interaction_index),
          failed_at: payload.fetch(:failed_at)
        )
      end

      def initialize(provider_id:, operation_id:, attempt_id:, action:, phase:, interaction_index:, failed_at:)
        @provider_id = RubyRouting::Identity.normalize(provider_id, "provider id")
        @operation_id = RubyRouting::Identity.normalize(operation_id, "operation id")
        @attempt_id = RubyRouting::Identity.normalize(attempt_id, "attempt id")
        @action = RubyRouting::Enum.normalize(action, ACTIONS, "provider failure action")
        @phase = RubyRouting::Enum.normalize(
          phase,
          RubyRouting::State::AttemptSnapshot::PHASES,
          "provider failure phase"
        )
        unless interaction_index.is_a?(Integer) && interaction_index >= 0
          raise ArgumentError, "provider failure interaction index must be a non-negative Integer"
        end
        unless failed_at.is_a?(Time)
          raise ArgumentError, "provider failure time must be a Time"
        end

        @interaction_index = interaction_index
        @failed_at = failed_at
        freeze
      end

      def matches_current_operation?(ownership:, attempt:, operation_action:, interaction_count:, existing:)
        expected_phase = action == :resolve ? :resolving : :dispatching
        existing.nil? && ownership && attempt &&
          ownership.provider_id == provider_id &&
          ownership.operation_id == operation_id &&
          ownership.attempt_id == attempt_id &&
          attempt.provider_id == provider_id &&
          attempt.operation_id == operation_id &&
          attempt.attempt_id == attempt_id &&
          attempt.phase == phase &&
          phase == expected_phase &&
          operation_action == action &&
          interaction_count == interaction_index
      end

      def to_h
        {
          provider_id: provider_id,
          operation_id: operation_id,
          attempt_id: attempt_id,
          action: action,
          phase: phase,
          interaction_index: interaction_index,
          failed_at: failed_at
        }.freeze
      end
    end
  end
end
