# frozen_string_literal: true

module RubyRouting
  module Routing
    # Classifies an observed allocation deviation without creating a recovery
    # obligation. A recoverable deviation is merely evidence that a later
    # admissible primary assignment may improve the current window; it never
    # authorizes a historical catch-up burst.
    module Deviation
      RECOVERABILITY = %i[none recoverable unavoidable].freeze

      UNAVOIDABLE_CAUSES = %i[
        functional_ineligibility
        hard_policy_constraint
        policy_measure_constraint
        recovery_exclusion
        safety_unknown
        unknown_owner
        reconciliation_blocked
        no_feasible_candidate
      ].freeze

      RECOVERABLE_CAUSES = %i[
        optimizer_choice
        allocation_share_constraint
        availability
        disabled
        capacity
        throughput
        health_quarantine
        operational_infeasibility
      ].freeze

      module_function

      def recoverability(allocation:, cause:, role: :primary)
        unless allocation.is_a?(RubyRouting::Routing::AllocationDecision)
          raise ArgumentError, "allocation must be AllocationDecision"
        end

        return :none unless material?(allocation)

        normalized_role = RubyRouting::Enum.normalize(role, %i[primary recovery], "deviation role")
        return :unavoidable if normalized_role == :recovery

        normalized_cause = if cause.nil?
          nil
        else
          (UNAVOIDABLE_CAUSES + RECOVERABLE_CAUSES).find { |candidate| candidate.to_s == cause.to_s }
        end
        return :unavoidable if UNAVOIDABLE_CAUSES.include?(normalized_cause)
        return :recoverable if RECOVERABLE_CAUSES.include?(normalized_cause)

        # Unknown causal classifications are conservative. The caller must
        # add an explicit cause before a future policy can treat them as debt.
        :unavoidable
      rescue NoMethodError
        raise ArgumentError, "deviation cause and role must be symbol-like"
      end

      def material?(allocation)
        return false if allocation.no_route?
        return true unless allocation.share_corridor_satisfied?

        if allocation.tolerance.nil?
          allocation.discrepancy.positive?
        else
          allocation.deviation_exceeded?
        end
      end
      private_class_method :material?
    end
  end
end
