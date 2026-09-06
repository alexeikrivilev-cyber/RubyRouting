# frozen_string_literal: true

module RubyRouting
  module Application
    # Queries expose snapshots and projections only. They never make a
    # routing decision or mutate coordinator state.
    class Queries
      def initialize(coordinator:, policy_registry:, configuration_store: nil)
        @coordinator = coordinator
        unless policy_registry.is_a?(RubyRouting::PolicyRegistry)
          raise ArgumentError, "policy_registry must be PolicyRegistry"
        end
        # Queries must project the same application-owned compatibility view
        # as Commands. A bootstrap clone would become stale after a
        # coordinated configuration publication and expose a second policy
        # source even though it is read-only.
        @policy_registry = policy_registry
        @configuration_store = configuration_store || RubyRouting::Application::ConfigurationStore.new(
          configuration: RubyRouting::Application::RoutingConfiguration.new(
            policies: policy_registry.policies,
            provider_opportunities: coordinator.provider_opportunities
          )
        )
        @policy_registry_view = @policy_registry.read_only(
          configuration_store: @configuration_store
        )
        # Discardable query state, keyed by the append-only fact revision. The
        # base projection is built without a read-time clock; Analytics then
        # reprojects only unresolved ages for the caller's `as_of` value.
        @analytics_cache_mutex = Thread::Mutex.new
        @analytics_cache = { revision: nil, projection: nil }
        freeze
      end

      def policy_registry
        @policy_registry_view
      end

      def payout(payout_id)
        @coordinator.payout_snapshot(payout_id)
      end

      alias get_payout payout

      def providers
        @configuration_store.with_snapshot do |snapshot|
          current_opportunities = @coordinator.provider_opportunities
          unless RubyRouting::Application::RoutingConfiguration.same_provider_definition_set?(
            snapshot.provider_opportunities,
            current_opportunities
          )
            raise RubyRouting::ConfigurationDriftError,
              "active provider configuration does not match the Coordinator catalog"
          end

          current_by_id = current_opportunities.to_h do |opportunity|
            [opportunity.provider_id, opportunity]
          end
          snapshot.provider_opportunities.map do |opportunity|
            current = current_by_id.fetch(opportunity.provider_id)
            opportunity.with_runtime(
              available: current.available,
              capacity_available: current.capacity_available,
              enabled: current.enabled,
              health_available: current.health_available,
              throughput_available: current.throughput_available
            )
          end.freeze
        end
      end

      def provider(provider_id)
        normalized_provider_id = RubyRouting::Identity.normalize(provider_id, "provider id")
        providers.find { |opportunity| opportunity.provider_id == normalized_provider_id }
      end

      def policies
        configuration_snapshot.policies
      end

      def configuration
        configuration_snapshot.configuration
      end

      def configuration_snapshot
        @configuration_store.with_snapshot do |snapshot|
          current_opportunities = @coordinator.provider_opportunities
          next snapshot if RubyRouting::Application::RoutingConfiguration.same_provider_definition_set?(
            snapshot.provider_opportunities,
            current_opportunities
          )

          raise RubyRouting::ConfigurationDriftError,
            "active provider configuration does not match the Coordinator catalog"
        end
      end

      def configuration_revision
        configuration_snapshot.revision
      end

      def configuration_diagnostics
        configuration_snapshot.diagnostics
      end

      def configuration_status
        return :invalid if configuration_diagnostics.any?(&:error?)
        return :valid_with_warnings unless configuration_diagnostics.empty?

        :valid
      end

      def policy_for(payout_id)
        @coordinator.policy_for(payout_id)
      end

      def analytics(as_of: @coordinator.current_time)
        facts = @coordinator.facts
        base = cached_analytics(facts)
        return base if as_of.nil?

        base.with_as_of(as_of)
      end

      def analytics_query(metric:, filters: {}, group_by: [], as_of: @coordinator.current_time)
        analytics(as_of: as_of).query(metric: metric, filters: filters, group_by: group_by)
      end

      def explanation(payout_id)
        canonical_payout_id = payout(payout_id).id
        RubyRouting::Projections::DecisionExplanation.from_facts(
          @coordinator.audit_facts(payout_id: canonical_payout_id),
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

      def health(routing_context: nil)
        @coordinator.health_projection(routing_context: routing_context)
      end

      def quality(as_of: @coordinator.current_time, context: nil, context_key: nil,
                  routing_context: nil, currency: nil)
        @coordinator.quality_projection(
          as_of: as_of,
          context: context,
          context_key: context_key,
          routing_context: routing_context,
          currency: currency
        )
      end

      def due_work(as_of: @coordinator.current_time, limit: nil)
        @coordinator.due_recovery_work(as_of: as_of, limit: limit)
      end

      alias due_recovery_work due_work

      def current_time
        @coordinator.current_time
      end

      private

      def cached_analytics(facts)
        revision = facts.length
        @analytics_cache_mutex.synchronize do
          return @analytics_cache.fetch(:projection) if @analytics_cache.fetch(:revision) == revision

          projection = RubyRouting::Projections::Replay.analytics(facts, as_of: nil)
          @analytics_cache[:projection] = projection
          @analytics_cache[:revision] = revision
          projection
        end
      end

      def normalize_audit_filters(payout_id:, type:)
        normalized_payout_id = if payout_id.nil?
          nil
        else
          RubyRouting::Identity.normalize(payout_id, "payout id")
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
