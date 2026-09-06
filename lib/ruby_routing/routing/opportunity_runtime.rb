# frozen_string_literal: true

module RubyRouting
  module Routing
    # Purely composes a provider definition with the dynamic runtime evidence
    # used by both live evaluation and durable trace validation. Static
    # opportunity gates remain hard gates even when a dynamic source says true.
    module OpportunityRuntime
      module_function

      def materialize(opportunity:, available_provider_ids:, capacity_available:,
                      health_available:, throughput_available:)
        unless opportunity.is_a?(RubyRouting::ProviderOpportunity)
          raise ArgumentError, "opportunity must be ProviderOpportunity"
        end

        available = available_provider_ids.nil? || available_provider_ids.include?(opportunity.provider_id)
        opportunity.with_runtime(
          available: opportunity.available && available,
          capacity_available: opportunity.capacity_available && capacity_available,
          health_available: opportunity.health_available && health_available,
          throughput_available: opportunity.throughput_available && throughput_available
        )
      end
    end
  end
end
