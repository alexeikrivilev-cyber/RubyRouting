# frozen_string_literal: true

module RubyRouting
  module Application
    # Queries expose snapshots and projections only. They never make a
    # routing decision or mutate coordinator state.
    class Queries
      attr_reader :policy_registry

      def initialize(coordinator:, policy_registry:)
        @coordinator = coordinator
        @policy_registry = policy_registry
        freeze
      end

      def payout(payout_id)
        @coordinator.payout_snapshot(payout_id)
      end

      alias get_payout payout

      def providers
        @coordinator.provider_opportunities
      end

      def provider(provider_id)
        providers.find { |opportunity| opportunity.provider_id == provider_id.to_s.strip }
      end

      def policies
        policy_registry.policies
      end

      def policy_for(payout_id)
        @coordinator.policy_for(payout_id)
      end

      def analytics(as_of: @coordinator.current_time)
        RubyRouting::Projections::Replay.analytics(@coordinator.facts, as_of: as_of)
      end

      def audit_facts(payout_id: nil, type: nil)
        normalized_payout_id = if payout_id.nil?
          nil
        else
          value = payout_id.to_s.strip
          raise ArgumentError, "payout id must be non-empty" if value.empty?

          value
        end
        normalized_type = if type.nil?
          nil
        else
          type_name = type.to_s
          RubyRouting::Fact::TYPES.find { |fact_type| fact_type.to_s == type_name }
        end
        if type && normalized_type.nil?
          raise ArgumentError, "unsupported audit fact type"
        end

        @coordinator.facts.select do |fact|
          (normalized_payout_id.nil? || fact.payout_id == normalized_payout_id) &&
            (normalized_type.nil? || fact.type == normalized_type)
        end.freeze
      end

      def lifecycle
        @coordinator.lifecycle_projection
      end

      def allocation
        @coordinator.allocation_projection
      end

      def capacity
        @coordinator.capacity_projection
      end

      def throughput
        @coordinator.throughput_projection
      end

      def health
        @coordinator.health_projection
      end

      def quality
        @coordinator.quality_projection
      end
    end
  end
end
