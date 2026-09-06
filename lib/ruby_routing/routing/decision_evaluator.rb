# frozen_string_literal: true

module RubyRouting
  module Routing
    # Builds the fact-free routing evaluation that precedes an atomic commit.
    # It owns no facts or business reservations; the coordinator remains
    # responsible for publishing the evaluation and committing the operation.
    class DecisionEvaluator
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
      )

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

      def evaluate(intent:, policy:, payout_state:, available_provider_ids:)
        opportunities = @provider_catalog.current.sort_by(&:provider_id).map do |opportunity|
          opportunity.with_runtime(
            available: opportunity.available &&
              (available_provider_ids.nil? || available_provider_ids.include?(opportunity.provider_id)),
            capacity_available: @admission_ledger.capacity_available?(opportunity, intent),
            health_available: opportunity.health_available && health_available_for?(opportunity.provider_id),
            throughput_available: @admission_ledger.throughput_available?(opportunity)
          )
        end
        eligibility = RubyRouting::Routing::Eligibility.evaluate(
          opportunities,
          intent: intent,
          policy: policy
        )
        incoming_measure = policy.measure_for(intent.money)
        allocation_exclusions = policy.measure_exclusions(
          eligibility.feasible_provider_ids,
          incoming_measure
        )
        runtime_feasibility = RubyRouting::Routing::RuntimeFeasibility.assess(
          policy: policy,
          eligibility: eligibility,
          attempted_provider_ids: payout_state.attempts.map(&:provider_id),
          measure_exclusions: allocation_exclusions
        )
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
          context: intent.context
        )
        proposal = RubyRouting::Routing::DecisionEngine.decide(
          intent: intent,
          policy: policy,
          opportunities: opportunities,
          allocation_snapshot: allocation_snapshot,
          payout_state: payout_state,
          available_provider_ids: available_provider_ids,
          quality: @quality_controller.snapshots(
            eligibility.feasible_provider_ids,
            context: intent.context
          )
        )

        Evaluation.new(
          opportunities: opportunities,
          eligibility: eligibility,
          allocation_exclusions: allocation_exclusions,
          runtime_feasibility: runtime_feasibility,
          allocation_snapshot: allocation_snapshot,
          allocation_key: allocation_key,
          evaluated_at: evaluated_at,
          evaluated_monotonic_at: evaluated_monotonic_at,
          quality_snapshots: quality_snapshots,
          proposal: proposal
        )
      end

      private

      def health_available_for?(provider_id)
        @health_controller.snapshot(provider_id).exposed?
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
