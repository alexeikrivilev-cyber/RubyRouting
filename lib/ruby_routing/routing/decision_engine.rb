# frozen_string_literal: true

module RubyRouting
  module Routing
    module DecisionEngine
      module_function

      def decide(intent:, policy:, opportunities:, allocation_snapshot:, payout_state:,
                 available_provider_ids: nil)
        unless intent.is_a?(RubyRouting::PayoutIntent)
          raise ArgumentError, "intent must be PayoutIntent"
        end
        unless payout_state.respond_to?(:status) && payout_state.respond_to?(:ownership)
          raise ArgumentError, "payout_state must expose lifecycle state"
        end

        classification = RubyRouting::Routing::Recovery.classify(
          status: payout_state.status,
          ownership: payout_state.ownership,
          capabilities: payout_state.respond_to?(:current_operation_contract) ?
            payout_state.current_operation_contract : nil,
          operation_phase: payout_state.respond_to?(:current_operation_phase) ?
            payout_state.current_operation_phase : nil,
          attempts: payout_state.attempt_count,
          policy: policy.recovery,
          resolution_interactions: payout_state.respond_to?(:resolution_interaction_count) ?
            payout_state.resolution_interaction_count : 0
        )

        case classification.action
        when :already_final
          return proposal(:already_final, policy, classification.reason, classification.reason_code)
        when :terminate
          return proposal(:terminate, policy, classification.reason, classification.reason_code)
        when :defer
          return proposal(:defer, policy, classification.reason, classification.reason_code) unless payout_state.ownership
        end

        if payout_state.ownership
          if classification.action == :defer
            return proposal(:defer, policy, classification.reason, classification.reason_code)
          end

          if available_provider_ids && !available_provider_ids.map(&:to_s).include?(payout_state.ownership.provider_id)
            return DecisionProposal.new(
              action: :defer,
              role: :resolution,
              policy_epoch: policy.epoch,
              reasons: ["existing operation adapter is unavailable"],
              reason_codes: [:adapter_unavailable]
            )
          end

          owner_opportunity = opportunities.find do |opportunity|
            opportunity.provider_id == payout_state.ownership.provider_id
          end
          capabilities = if payout_state.respond_to?(:current_operation_contract)
            payout_state.current_operation_contract
          end
          capabilities ||= owner_opportunity&.capabilities
          if classification.action == :resolve
            return DecisionProposal.new(
              action: :resolve,
              provider_id: payout_state.ownership.provider_id,
              operation_id: payout_state.ownership.operation_id,
              attempt_id: payout_state.ownership.attempt_id,
              role: :resolution,
              policy_epoch: policy.epoch,
              reasons: [classification.reason],
              reason_codes: [classification.reason_code]
            )
          end
          if classification.action == :retry_same
            return DecisionProposal.new(
              action: :retry_same,
              provider_id: payout_state.ownership.provider_id,
              operation_id: payout_state.ownership.operation_id,
              attempt_id: payout_state.ownership.attempt_id,
              role: :resolution,
              policy_epoch: policy.epoch,
              reasons: [classification.reason],
              reason_codes: [classification.reason_code]
            )
          end

          return proposal(:defer, policy, classification.reason, classification.reason_code)
        end

        return proposal(:defer, policy, classification.reason, classification.reason_code) if classification.action == :defer

        if payout_state.attempt_count.positive? &&
           payout_state.respond_to?(:provider_switch_count) &&
           payout_state.provider_switch_count >= policy.recovery.max_switches
          return proposal(:defer, policy, "provider switch budget exhausted", :switch_budget_exhausted)
        end

        eligibility = RubyRouting::Routing::Eligibility.evaluate(
          opportunities,
          intent: intent,
          policy: policy
        )
        attempted_provider_ids = if payout_state.respond_to?(:money_moving_provider_ids)
          payout_state.money_moving_provider_ids
        else
          payout_state.attempts.map(&:provider_id).uniq
        end
        candidates = eligibility.feasible_provider_ids - attempted_provider_ids
        allocation = RubyRouting::Routing::Allocation.choose(
          policy: policy,
          candidates: candidates,
          snapshot: allocation_snapshot,
          incoming_measure: policy.measure_for(intent.money),
          accounting_provider_ids: eligibility.functional_provider_ids
        )
        if allocation.no_route?
          measure_exclusions = policy_measure_exclusions(
            eligibility: eligibility,
            policy: policy,
            incoming_measure: policy.measure_for(intent.money)
          )
          return DecisionProposal.new(
            action: :defer,
            role: :recovery,
            policy_epoch: policy.epoch,
            reasons: no_route_reasons(eligibility, measure_exclusions),
            reason_codes: [
              :no_safe_route,
              *eligibility.exclusion_codes.values.uniq,
              *measure_exclusions.values.uniq
            ]
          )
        end

        role = payout_state.attempt_count.zero? ? :primary : :recovery
        allocation = allocation.with_deviation_cause(
          deviation_cause(eligibility: eligibility, payout_state: payout_state)
        )
        reason_codes = [:allocation_choice]
        reason_codes << :tolerance_exceeded if allocation.deviation_exceeded?
        reason_codes << :soft_constraint_relaxed unless eligibility.soft_violations
          .fetch(allocation.chosen_provider, []).empty?
        DecisionProposal.new(
          action: :assign,
          provider_id: allocation.chosen_provider,
          role: role,
          policy_epoch: policy.epoch,
          reasons: ["selected by post-decision #{policy.measure} allocation"],
          reason_codes: reason_codes,
          allocation_decision: allocation
        )
      end

      def proposal(action, policy, reason, reason_code = nil)
        DecisionProposal.new(
          action: action,
          role: :resolution,
          policy_epoch: policy.epoch,
          reasons: [reason],
          reason_codes: [reason_code].compact
        )
      end
      private_class_method :proposal

      def deviation_cause(eligibility:, payout_state:)
        codes = eligibility.exclusion_codes.values.map(&:to_sym)
        return :hard_policy_constraint if codes.include?(:hard_policy_constraint)
        return :functional_ineligibility if codes.include?(:functionally_ineligible)
        return :capacity if codes.include?(:capacity_exhausted)
        return :health_quarantine if codes.include?(:quarantined)
        return :availability if (codes & %i[unavailable disabled]).any?
        return :recovery_exclusion if payout_state.attempt_count.positive?

        :optimizer_choice
      end
      private_class_method :deviation_cause

      def no_route_reasons(eligibility, measure_exclusions = {})
        reasons = ["no safe feasible provider"]
        reasons << "excluded=#{eligibility.exclusions.inspect}" unless eligibility.exclusions.empty?
        reasons << "allocation_limits=#{measure_exclusions.inspect}" unless measure_exclusions.empty?
        reasons
      end
      private_class_method :no_route_reasons

      def policy_measure_exclusions(eligibility:, policy:, incoming_measure:)
        policy.measure_exclusions(eligibility.feasible_provider_ids, incoming_measure)
      end
      private_class_method :policy_measure_exclusions
    end
  end
end
