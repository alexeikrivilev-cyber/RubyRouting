# frozen_string_literal: true

module RubyRouting
  module Routing
    class RecoveryDecision
      ACTIONS = %i[retry_same resolve fallback defer terminate].freeze

      attr_reader :action, :reason, :reason_code

      def initialize(action:, reason:, reason_code: nil)
        @action = action.to_sym
        raise ArgumentError, "unsupported recovery action" unless ACTIONS.include?(@action)

        @reason = reason.to_s.freeze
        @reason_code = reason_code&.to_sym
        freeze
      end
    end

    class RecoveryClassification
      ACTIONS = %i[already_final terminate resolve retry_same defer continue].freeze

      attr_reader :action, :reason, :reason_code

      def initialize(action:, reason:, reason_code:)
        @action = action.to_sym
        raise ArgumentError, "unsupported recovery classification" unless ACTIONS.include?(@action)

        @reason = reason.to_s.freeze
        @reason_code = reason_code&.to_sym
        freeze
      end
    end

    module Recovery
      module_function

      def classify(status:, ownership:, capabilities:, operation_phase: nil, attempts:, policy:,
                   resolution_interactions: 0)
        if %i[success reversed].include?(status.to_sym)
          return RecoveryClassification.new(
            action: :already_final,
            reason: "payout already succeeded",
            reason_code: :already_final
          )
        end
        if status.to_sym == :terminal_payout_failure
          return RecoveryClassification.new(
            action: :terminate,
            reason: "terminal payout failure",
            reason_code: :terminal
          )
        end
        if status.to_sym == :reconciliation_blocked
          return RecoveryClassification.new(
            action: :defer,
            reason: "automatic recovery is reconciliation-blocked",
            reason_code: :reconciliation_blocked
          )
        end

        if ownership
          if %i[committed dispatching resolving].include?(operation_phase&.to_sym)
            return RecoveryClassification.new(
              action: :defer,
              reason: "provider operation dispatch is in progress",
              reason_code: :dispatch_in_progress
            )
          end
          if resolution_interactions >= policy.max_resolution_interactions
            return RecoveryClassification.new(
              action: :defer,
              reason: "resolution interaction budget exhausted",
              reason_code: :resolution_budget_exhausted
            )
          end
          if capabilities&.status_lookup
            return RecoveryClassification.new(
              action: :resolve,
              reason: "unresolved ownership requires same-provider resolution",
              reason_code: :status_resolution
            )
          end
          if capabilities&.idempotent_retry
            return RecoveryClassification.new(
              action: :retry_same,
              reason: "provider permits idempotent same-operation retry",
              reason_code: :same_provider_retry
            )
          end

          return RecoveryClassification.new(
            action: :defer,
            reason: "unresolved ownership blocks cross-provider fallback",
            reason_code: :ownership_blocked
          )
        end

        if attempts >= policy.max_operations
          return RecoveryClassification.new(
            action: :defer,
            reason: "money-moving operation budget exhausted",
            reason_code: :operation_budget_exhausted
          )
        end

        RecoveryClassification.new(action: :continue, reason: "fresh routing decision required", reason_code: nil)
      end

      def choose(status:, ownership:, capabilities:, attempts:, max_attempts:)
        policy = RubyRouting::RecoveryPolicy.new(
          max_operations: max_attempts,
          max_switches: max_attempts,
          max_resolution_interactions: max_attempts
        )
        classification = classify(
          status: status,
          ownership: ownership,
          capabilities: capabilities,
          attempts: attempts,
          policy: policy
        )
        action = if classification.action == :continue
          :fallback
        elsif classification.action == :already_final
          :terminate
        else
          classification.action
        end
        RecoveryDecision.new(
          action: action,
          reason: classification.reason,
          reason_code: classification.reason_code
        )
      end
    end
  end
end
