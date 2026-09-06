# frozen_string_literal: true

module RubyRouting
  module Routing
    module DecisionEngine
      module_function

      def decide(intent:, policy:, opportunities:, allocation_snapshot:, payout_state:)
        unless intent.is_a?(RubyRouting::PayoutIntent)
          raise ArgumentError, "intent must be PayoutIntent"
        end
        unless payout_state.respond_to?(:status) && payout_state.respond_to?(:ownership)
          raise ArgumentError, "payout_state must expose lifecycle state"
        end

        if payout_state.status == :success
          return proposal(:already_final, policy, "payout already succeeded")
        end
        if payout_state.status == :terminal_payout_failure
          return proposal(:terminate, policy, "terminal payout failure")
        end

        if payout_state.ownership
          owner_opportunity = opportunities.find do |opportunity|
            opportunity.provider_id == payout_state.ownership.provider_id
          end
          capabilities = owner_opportunity&.capabilities
          if capabilities&.status_lookup
            return DecisionProposal.new(
              action: :resolve,
              provider_id: payout_state.ownership.provider_id,
              operation_id: payout_state.ownership.operation_id,
              attempt_id: payout_state.ownership.attempt_id,
              role: :resolution,
              policy_epoch: policy.epoch,
              reasons: ["unresolved ownership requires same-provider resolution"]
            )
          end
          interaction_count = if payout_state.respond_to?(:provider_interaction_count)
            payout_state.provider_interaction_count
          else
            payout_state.attempt_count
          end
          if capabilities&.idempotent_retry && interaction_count < policy.max_attempts
            return DecisionProposal.new(
              action: :retry_same,
              provider_id: payout_state.ownership.provider_id,
              operation_id: payout_state.ownership.operation_id,
              attempt_id: payout_state.ownership.attempt_id,
              role: :resolution,
              policy_epoch: policy.epoch,
              reasons: ["provider permits idempotent same-operation retry"]
            )
          end

          return proposal(:defer, policy, "unresolved ownership blocks cross-provider fallback")
        end

        if payout_state.attempt_count >= policy.max_attempts
          return proposal(:defer, policy, "attempt budget exhausted")
        end

        eligibility = RubyRouting::Routing::Eligibility.evaluate(opportunities)
        allocation = RubyRouting::Routing::Allocation.choose(
          policy: policy,
          candidates: eligibility.feasible_provider_ids,
          snapshot: allocation_snapshot,
          incoming_measure: policy.measure_for(intent.money)
        )
        if allocation.no_route?
          return DecisionProposal.new(
            action: :defer,
            role: :recovery,
            policy_epoch: policy.epoch,
            reasons: no_route_reasons(eligibility)
          )
        end

        role = payout_state.attempt_count.zero? ? :primary : :recovery
        DecisionProposal.new(
          action: :assign,
          provider_id: allocation.chosen_provider,
          role: role,
          policy_epoch: policy.epoch,
          reasons: ["selected by post-decision #{policy.measure} allocation"],
          allocation_decision: allocation
        )
      end

      def proposal(action, policy, reason)
        DecisionProposal.new(
          action: action,
          role: :resolution,
          policy_epoch: policy.epoch,
          reasons: [reason]
        )
      end
      private_class_method :proposal

      def no_route_reasons(eligibility)
        reasons = ["no safe feasible provider"]
        reasons << "excluded=#{eligibility.exclusions.inspect}" unless eligibility.exclusions.empty?
        reasons
      end
      private_class_method :no_route_reasons
    end
  end
end
