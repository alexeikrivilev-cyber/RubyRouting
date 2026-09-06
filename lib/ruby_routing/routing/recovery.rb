# frozen_string_literal: true

module RubyRouting
  module Routing
    class RecoveryDecision
      ACTIONS = %i[retry_same resolve fallback defer terminate].freeze

      attr_reader :action, :reason

      def initialize(action:, reason:)
        @action = action.to_sym
        raise ArgumentError, "unsupported recovery action" unless ACTIONS.include?(@action)

        @reason = reason.to_s.freeze
        freeze
      end
    end

    module Recovery
      module_function

      def choose(status:, ownership:, capabilities:, attempts:, max_attempts:)
        if status == :success
          return RecoveryDecision.new(action: :terminate, reason: "payout already succeeded")
        end
        if status == :terminal_payout_failure
          return RecoveryDecision.new(action: :terminate, reason: "terminal payout failure")
        end
        if ownership
          if capabilities && capabilities.can_resolve?
            return RecoveryDecision.new(action: :resolve, reason: "unresolved owner requires status resolution")
          end

          return RecoveryDecision.new(action: :defer, reason: "unresolved owner cannot be safely released")
        end
        if attempts >= max_attempts
          return RecoveryDecision.new(action: :defer, reason: "recovery attempt budget exhausted")
        end
        if %i[safe_route_failure temporary_provider_failure].include?(status)
          return RecoveryDecision.new(action: :fallback, reason: "previous provider failure was safely released")
        end

        RecoveryDecision.new(action: :fallback, reason: "fresh routing decision required")
      end
    end
  end
end
