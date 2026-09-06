# frozen_string_literal: true

module RubyRouting
  module Routing
    class EligibilityResult
      attr_reader :opportunities, :feasible_provider_ids, :exclusions

      def initialize(opportunities:, feasible_provider_ids:, exclusions:)
        @opportunities = opportunities.dup.freeze
        @feasible_provider_ids = feasible_provider_ids.dup.freeze
        @exclusions = exclusions.dup.freeze
        freeze
      end
    end

    module Eligibility
      module_function

      def evaluate(opportunities)
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

        feasible = normalized.select(&:feasible?).map(&:provider_id).sort.freeze
        exclusions = normalized.each_with_object({}) do |opportunity, reasons|
          reasons[opportunity.provider_id] = opportunity.reason unless opportunity.feasible?
        end.freeze

        EligibilityResult.new(
          opportunities: normalized.sort_by(&:provider_id),
          feasible_provider_ids: feasible,
          exclusions: exclusions
        )
      end
    end
  end
end
