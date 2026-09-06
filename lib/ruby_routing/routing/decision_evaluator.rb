# frozen_string_literal: true

module RubyRouting
  module Routing
    # Builds the fact-free routing evaluation that precedes an atomic commit.
    # It owns no facts or business reservations; the coordinator remains
    # responsible for publishing the evaluation and committing the operation.
    class DecisionEvaluator
      PreparedRoutingInputs = Data.define(
        :eligibility,
        :allocation_exclusions,
        :runtime_feasibility
      ) do
        def initialize(eligibility:, allocation_exclusions:, runtime_feasibility:)
          super(
            eligibility: RubyRouting::ImmutableData.deep_freeze(eligibility),
            allocation_exclusions: RubyRouting::ImmutableData.deep_freeze(allocation_exclusions),
            runtime_feasibility: RubyRouting::ImmutableData.deep_freeze(runtime_feasibility)
          )
        end
      end

      Evaluation = Data.define(
        :opportunities,
        :eligibility,
        :allocation_exclusions,
        :runtime_feasibility,
        :allocation_snapshot,
        :allocation_key,
        :evaluated_at,
        :evaluated_monotonic_at,
        :quality_snapshots,
        :proposal
      ) do
        def initialize(opportunities:, eligibility:, allocation_exclusions:, runtime_feasibility:,
                       allocation_snapshot:, allocation_key:, evaluated_at:,
                       evaluated_monotonic_at:, quality_snapshots:, proposal:)
          super(
            opportunities: RubyRouting::ImmutableData.deep_freeze(opportunities),
            eligibility: RubyRouting::ImmutableData.deep_freeze(eligibility),
            allocation_exclusions: RubyRouting::ImmutableData.deep_freeze(allocation_exclusions),
            runtime_feasibility: RubyRouting::ImmutableData.deep_freeze(runtime_feasibility),
            allocation_snapshot: RubyRouting::ImmutableData.deep_freeze(allocation_snapshot),
            allocation_key: RubyRouting::ImmutableData.deep_freeze(allocation_key),
            evaluated_at: RubyRouting::ImmutableData.deep_freeze(evaluated_at),
            evaluated_monotonic_at: RubyRouting::ImmutableData.deep_freeze(evaluated_monotonic_at),
            quality_snapshots: RubyRouting::ImmutableData.deep_freeze(quality_snapshots),
            proposal: RubyRouting::ImmutableData.deep_freeze(proposal)
          )
        end
      end

      def initialize(
        provider_catalog:,
        admission_ledger:,
        allocation_ledger:,
        health_controller:,
        quality_controller:,
        current_time:,
        current_monotonic:
      )
        @provider_catalog = provider_catalog
        @admission_ledger = admission_ledger
        @allocation_ledger = allocation_ledger
        @health_controller = health_controller
        @quality_controller = quality_controller
        @current_time = current_time
        @current_monotonic = current_monotonic
      end

      def self.prepare(intent:, policy:, opportunities:, attempted_provider_ids:)
        eligibility = RubyRouting::Routing::Eligibility.evaluate(
          opportunities,
          intent: intent,
          policy: policy
        )
        allocation_exclusions = policy.measure_exclusions(
          eligibility.feasible_provider_ids,
          policy.measure_for(intent.money)
        )
        runtime_feasibility = RubyRouting::Routing::RuntimeFeasibility.assess(
          policy: policy,
          eligibility: eligibility,
          attempted_provider_ids: attempted_provider_ids,
          measure_exclusions: allocation_exclusions
        )
        PreparedRoutingInputs.new(
          eligibility: eligibility,
          allocation_exclusions: allocation_exclusions,
          runtime_feasibility: runtime_feasibility
        )
      end

      def evaluate(intent:, policy:, payout_state:, available_provider_ids:, provider_opportunities: nil)
        source_opportunities = provider_opportunities || @provider_catalog.current
        opportunities = source_opportunities.sort_by(&:provider_id).map do |opportunity|
          RubyRouting::Routing::OpportunityRuntime.materialize(
            opportunity: opportunity,
            available_provider_ids: available_provider_ids,
            capacity_available: @admission_ledger.capacity_available?(opportunity, intent),
            health_available: health_available_for?(opportunity.provider_id, intent.routing_context),
            throughput_available: @admission_ledger.throughput_available?(opportunity)
          )
        end
        prepared = self.class.prepare(
          intent: intent,
          policy: policy,
          opportunities: opportunities,
          attempted_provider_ids: payout_state.attempts.map(&:provider_id)
        )
        eligibility = prepared.eligibility
        allocation_exclusions = prepared.allocation_exclusions
        runtime_feasibility = prepared.runtime_feasibility
        allocation_snapshot = @allocation_ledger.snapshot(
          policy: policy,
          opportunity_provider_ids: eligibility.functional_provider_ids
        )
        allocation_key = policy.allocation_key(
          opportunity_provider_ids: eligibility.functional_provider_ids
        )
        evaluated_at = current_time
        evaluated_monotonic_at = current_monotonic
        quality_snapshots = @quality_controller.snapshots(
          eligibility.opportunity_provider_ids,
          context: intent.routing_context,
          routing_context: intent.routing_context,
          currency: intent.money.currency,
          as_of: evaluated_at
        )
        evaluation = Evaluation.new(
          opportunities: opportunities,
          eligibility: eligibility,
          allocation_exclusions: allocation_exclusions,
          runtime_feasibility: runtime_feasibility,
          allocation_snapshot: allocation_snapshot,
          allocation_key: allocation_key,
          evaluated_at: evaluated_at,
          evaluated_monotonic_at: evaluated_monotonic_at,
          quality_snapshots: quality_snapshots,
          proposal: nil
        )
        proposal = RubyRouting::Routing::DecisionEngine.decide(
          intent: intent,
          policy: policy,
          payout_state: payout_state,
          available_provider_ids: available_provider_ids,
          evaluation: evaluation
        )

        evaluation.with(proposal: proposal)
      end

      private

      def health_available_for?(provider_id, routing_context)
        @health_controller.snapshot(provider_id, routing_context: routing_context).exposed?
      end

      def current_time
        @current_time.call
      end

      def current_monotonic
        @current_monotonic.call
      end
    end
  end
end
