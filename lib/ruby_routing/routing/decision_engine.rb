# frozen_string_literal: true

module RubyRouting
  module Routing
    module DecisionEngine
      module_function

      def decide(intent:, policy:, opportunities:, allocation_snapshot:, payout_state:,
                 available_provider_ids: nil, quality: nil)
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
          return proposal(
            :defer,
            policy,
            classification.reason,
            classification.reason_code,
            role: :recovery
          ) unless payout_state.ownership
        end

        if payout_state.ownership
          return proposal(:defer, policy, classification.reason, classification.reason_code) if classification.action == :defer

          normalized_available_provider_ids = available_provider_ids &&
            normalize_provider_ids(available_provider_ids, "available_provider_ids")
          if normalized_available_provider_ids && !normalized_available_provider_ids.include?(payout_state.ownership.provider_id)
            return DecisionProposal.new(
              action: :defer,
              role: :resolution,
              policy_epoch: policy.epoch,
              reasons: ["existing operation adapter is unavailable"],
              reason_codes: [:adapter_unavailable]
            )
          end

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

        if classification.action == :defer
          return proposal(
            :defer,
            policy,
            classification.reason,
            classification.reason_code,
            role: :recovery
          )
        end

        if payout_state.attempt_count.positive? &&
           payout_state.respond_to?(:provider_switch_count) &&
           payout_state.provider_switch_count >= policy.recovery.max_switches
          return proposal(
            :defer,
            policy,
            "provider switch budget exhausted",
            :switch_budget_exhausted,
            role: :recovery
          )
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
        attempted_provider_ids = normalize_provider_ids(attempted_provider_ids, "attempted_provider_ids")
        candidates = eligibility.feasible_provider_ids - attempted_provider_ids
        allocation_exclusions = policy_measure_exclusions(
          eligibility: eligibility,
          policy: policy,
          incoming_measure: policy.measure_for(intent.money)
        )

        allocation = RubyRouting::Routing::Allocation.choose(
          policy: policy,
          candidates: candidates,
          snapshot: allocation_snapshot,
          incoming_measure: policy.measure_for(intent.money),
          accounting_provider_ids: eligibility.functional_provider_ids
        )
        runtime_feasibility = RubyRouting::Routing::RuntimeFeasibility.assess(
          policy: policy,
          eligibility: eligibility,
          attempted_provider_ids: attempted_provider_ids,
          measure_exclusions: allocation_exclusions
        )

        if allocation.no_route?
          deviation = no_route_deviation(
            eligibility: eligibility,
            allocation_exclusions: allocation_exclusions,
            runtime_feasibility: runtime_feasibility
          )
          return DecisionProposal.new(
            action: :defer,
            role: :recovery,
            policy_epoch: policy.epoch,
            reasons: no_route_reasons(eligibility, allocation_exclusions, runtime_feasibility),
            reason_codes: [
              :no_safe_route,
              (:runtime_policy_infeasible if runtime_feasibility.policy_infeasible?),
              *runtime_feasibility.reason_codes,
              *eligibility.exclusion_codes.values.uniq,
              *allocation_exclusions.values.uniq
            ].compact,
            runtime_feasibility: runtime_feasibility,
            deviation_cause: deviation.fetch(:cause),
            deviation_recoverability: deviation.fetch(:recoverability)
          )
        end

        assignment_proposal(
          policy: policy,
          allocation: allocation,
          eligibility: eligibility,
          payout_state: payout_state,
          quality: quality,
          runtime_feasibility: runtime_feasibility
        )
      end

      def assignment_proposal(policy:, allocation:, eligibility:, payout_state:, quality:, runtime_feasibility:)
        allocation_provider_before_optimization = allocation.chosen_provider
        allocation = RubyRouting::Routing::ConstrainedOptimizer.choose(
          policy: policy,
          allocation: allocation,
          quality: quality
        )

        role = payout_state.attempt_count.zero? ? :primary : :recovery
        cause = if allocation.share_corridor_satisfied?
          deviation_cause(eligibility: eligibility, payout_state: payout_state)
        else
          :allocation_share_constraint
        end
        allocation = allocation.with_deviation_cause(
          cause,
          recoverability: RubyRouting::Routing::Deviation.recoverability(
            allocation: allocation,
            cause: cause,
            role: role
          )
        )
        reason_codes = [:allocation_choice]
        reason_codes << :quality_optimization if quality &&
          allocation.chosen_provider != allocation_provider_before_optimization
        reason_codes << :tolerance_exceeded if allocation.deviation_exceeded?
        reason_codes << :allocation_share_corridor_exceeded unless allocation.share_corridor_satisfied?
        reason_codes << :soft_constraint_relaxed unless eligibility.soft_violations
          .fetch(allocation.chosen_provider, []).empty?

        DecisionProposal.new(
          action: :assign,
          provider_id: allocation.chosen_provider,
          role: role,
          policy_epoch: policy.epoch,
          reasons: ["selected by post-decision #{policy.measure} allocation"],
          reason_codes: reason_codes,
          allocation_decision: allocation,
          runtime_feasibility: runtime_feasibility
        )
      end

      # A deferred no-route decision still represents a missed target. Keep
      # that causal evidence on the decision itself so analytics can account
      # for blocked traffic even though no allocation was committed.
      def no_route_deviation(eligibility:, allocation_exclusions:, runtime_feasibility:)
        cause = no_route_deviation_cause(
          eligibility: eligibility,
          allocation_exclusions: allocation_exclusions,
          runtime_feasibility: runtime_feasibility
        )
        recoverability = if RubyRouting::Routing::Deviation::RECOVERABLE_CAUSES.include?(cause)
          :recoverable
        else
          :unavoidable
        end
        { cause: cause, recoverability: recoverability }.freeze
      end

      def no_route_deviation_cause(eligibility:, allocation_exclusions:, runtime_feasibility:)
        allocation_codes = allocation_exclusions.values
        exclusion_codes = eligibility.exclusion_codes.values
        runtime_codes = runtime_feasibility&.reason_codes || []

        return :policy_measure_constraint if allocation_codes.include?(:policy_measure_constraint)
        return :recovery_exclusion if runtime_codes.include?(:recovery_provider_exhausted)
        return :hard_policy_constraint if exclusion_codes.include?(:hard_policy_constraint)
        return :functional_ineligibility if exclusion_codes.include?(:functionally_ineligible)
        return :health_quarantine if exclusion_codes.include?(:quarantined)
        return :disabled if exclusion_codes.include?(:disabled)
        return :availability if exclusion_codes.include?(:unavailable)
        return :capacity if exclusion_codes.include?(:capacity_exhausted)
        return :throughput if exclusion_codes.include?(:throughput_exhausted)
        return :operational_infeasibility if runtime_codes.include?(:operational_infeasibility)
        return :functional_ineligibility if runtime_codes.include?(:no_functional_target_opportunity)
        return :policy_measure_constraint if runtime_codes.include?(:policy_measure_infeasibility)

        :no_feasible_candidate
      end

      def proposal(action, policy, reason, reason_code = nil, role: :resolution)
        DecisionProposal.new(
          action: action,
          role: role,
          policy_epoch: policy.epoch,
          reasons: [reason],
          reason_codes: [reason_code].compact
        )
      end
      private_class_method :proposal

      def deviation_cause(eligibility:, payout_state:)
        codes = eligibility.exclusion_codes.values.map do |code|
          code.is_a?(Symbol) ? code : code.to_s.freeze
        end
        return :hard_policy_constraint if codes.include?(:hard_policy_constraint)
        return :functional_ineligibility if codes.include?(:functionally_ineligible)
        return :capacity if codes.include?(:capacity_exhausted)
        return :health_quarantine if codes.include?(:quarantined)
        return :availability if (codes & %i[unavailable disabled]).any?
        return :recovery_exclusion if payout_state.attempt_count.positive?

        :optimizer_choice
      end
      private_class_method :deviation_cause

      def no_route_reasons(eligibility, measure_exclusions = {}, runtime_feasibility = nil)
        reasons = ["no safe feasible provider"]
        reasons << "excluded=#{eligibility.exclusions.inspect}" unless eligibility.exclusions.empty?
        reasons << "allocation_limits=#{measure_exclusions.inspect}" unless measure_exclusions.empty?
        reasons << "runtime_feasibility=#{runtime_feasibility.to_h.inspect}" if runtime_feasibility
        reasons
      end
      private_class_method :no_route_reasons

      def policy_measure_exclusions(eligibility:, policy:, incoming_measure:)
        policy.measure_exclusions(eligibility.feasible_provider_ids, incoming_measure)
      end
      private_class_method :policy_measure_exclusions

      def normalize_provider_ids(provider_ids, label)
        RubyRouting::Collection.to_array(provider_ids, label).map do |provider_id|
          normalized = provider_id.to_s.strip
          raise ArgumentError, "provider id must be non-empty" if normalized.empty?

          normalized
        end.uniq.sort
      end
      private_class_method :normalize_provider_ids
    end
  end
end
