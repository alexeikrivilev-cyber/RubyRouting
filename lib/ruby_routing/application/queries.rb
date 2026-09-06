# frozen_string_literal: true

module RubyRouting
  module Application
    # Queries expose snapshots and projections only. They never make a
    # routing decision or mutate coordinator state.
    class Queries
      attr_reader :policy_registry

      def initialize(coordinator:, policy_registry:, configuration_store: nil)
        @coordinator = coordinator
        @policy_registry = policy_registry
        @configuration_store = configuration_store || RubyRouting::Application::ConfigurationStore.new(
          configuration: RubyRouting::Application::RoutingConfiguration.new(
            policies: policy_registry.policies,
            provider_opportunities: coordinator.provider_opportunities
          )
        )
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

      def configuration
        @configuration_store.current
      end

      def policy_for(payout_id)
        @coordinator.policy_for(payout_id)
      end

      def analytics(as_of: @coordinator.current_time)
        RubyRouting::Projections::Replay.analytics(@coordinator.facts, as_of: as_of)
      end

      def analytics_query(metric:, filters: {}, group_by: [], as_of: @coordinator.current_time)
        analytics(as_of: as_of).query(metric: metric, filters: filters, group_by: group_by)
      end

      def explanation(payout_id)
        canonical_payout_id = payout(payout_id).id
        RubyRouting::Projections::DecisionExplanation.from_facts(
          @coordinator.facts,
          payout_id: canonical_payout_id
        )
      end

      def audit_facts(payout_id: nil, type: nil)
        normalized_payout_id, normalized_type = normalize_audit_filters(payout_id: payout_id, type: type)
        @coordinator.audit_facts(payout_id: normalized_payout_id, type: normalized_type)
      end

      def audit_facts_page(payout_id: nil, type: nil, offset:, limit:)
        normalized_payout_id, normalized_type = normalize_audit_filters(payout_id: payout_id, type: type)
        @coordinator.audit_fact_page(
          payout_id: normalized_payout_id,
          type: normalized_type,
          offset: offset,
          limit: limit
        )
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

      def due_work(as_of: @coordinator.current_time)
        @coordinator.due_recovery_work(as_of: as_of)
      end

      alias due_recovery_work due_work

      private

      def normalize_audit_filters(payout_id:, type:)
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

        [normalized_payout_id, normalized_type]
      end
    end
  end
end
