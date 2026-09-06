# frozen_string_literal: true

module RubyRouting
  module Routing
    class EligibilityResult
      attr_reader :opportunities, :opportunity_provider_ids, :functional_provider_ids,
                  :feasible_provider_ids, :exclusions, :exclusion_codes,
                  :soft_violations

      def initialize(opportunities:, opportunity_provider_ids:, functional_provider_ids:,
                     feasible_provider_ids:, exclusions:, exclusion_codes:, soft_violations:)
        @opportunities = opportunities.dup.freeze
        @opportunity_provider_ids = opportunity_provider_ids.dup.freeze
        @functional_provider_ids = functional_provider_ids.dup.freeze
        @feasible_provider_ids = feasible_provider_ids.dup.freeze
        @exclusions = exclusions.dup.freeze
        @exclusion_codes = exclusion_codes.dup.freeze
        @soft_violations = soft_violations.transform_values(&:dup).transform_values(&:freeze).freeze
        freeze
      end
    end

    module Eligibility
      module_function

      def evaluate(opportunities, intent: nil, policy: nil)
        normalized = opportunities.map do |opportunity|
          unless opportunity.is_a?(RubyRouting::ProviderOpportunity)
            raise ArgumentError, "opportunities must contain ProviderOpportunity values"
          end

          opportunity
        end
        ids = normalized.map(&:provider_id)
        unless ids.uniq.length == ids.length
          raise ArgumentError, "provider opportunities must have unique provider ids"
        end

        opportunity_provider_ids = normalized.map(&:provider_id).sort.freeze
        functional = normalized.select do |opportunity|
          intent.nil? || opportunity.functional_eligible_for?(intent: intent, policy: policy)
        end
        functional_provider_ids = functional.map(&:provider_id).sort.freeze
        feasible = functional.select do |opportunity|
          intent.nil? ? opportunity.feasible? : opportunity.feasible_for?(intent: intent, policy: policy)
        end.map(&:provider_id).sort.freeze
        exclusions = normalized.each_with_object({}) do |opportunity, reasons|
          feasible_for_context = feasible.include?(opportunity.provider_id)
          reason = if intent.nil?
            opportunity.reason unless opportunity.feasible?
          elsif !feasible_for_context
            opportunity.reason_for(intent: intent, policy: policy)
          end
          reasons[opportunity.provider_id] = reason unless reason.nil?
        end.freeze
        exclusion_codes = exclusions.transform_values do |reason|
          reason.is_a?(Symbol) ? reason : :explicit_exclusion
        end.freeze
        soft_violations = if policy
          normalized.each_with_object({}) do |opportunity, violations|
            values = policy.soft_constraints.violations(intent: intent, provider_id: opportunity.provider_id)
            violations[opportunity.provider_id] = values unless values.empty?
          end
        else
          {}
        end.freeze

        EligibilityResult.new(
          opportunities: normalized.sort_by(&:provider_id),
          opportunity_provider_ids: opportunity_provider_ids,
          functional_provider_ids: functional_provider_ids,
          feasible_provider_ids: feasible,
          exclusions: exclusions,
          exclusion_codes: exclusion_codes,
          soft_violations: soft_violations
        )
      end
    end
  end
end
