# frozen_string_literal: true

module RubyRouting
  module State
    # Validates durable decision traces against the other projections that
    # created them. Applying the decision remains the responsibility of
    # DecisionFactRestorer; this object owns the cross-fact routing proof.
    class DecisionTraceValidator
      def initialize(policies:, provider_catalog:, payout_snapshot:, decision_enum:, same_contract:)
        @policies = policies
        @provider_catalog = provider_catalog
        @payout_snapshot = payout_snapshot
        @decision_enum = decision_enum
        @same_contract = same_contract
      end

      def decision_role(value, action:)
        role = RubyRouting::Enum.normalize(value, RubyRouting::DecisionProposal::ROLES, "decision role")
        unless RubyRouting::DecisionProposal::ROLES.include?(role)
          raise RubyRouting::State::DurableCorruptionError,
            "decision role #{role.inspect} is unsupported for #{action}"
        end
        expected_roles = if action == :assign
          %i[primary recovery]
        elsif action == :defer
          %i[recovery resolution]
        else
          [:resolution]
        end
        unless expected_roles.include?(role)
          raise RubyRouting::State::DurableCorruptionError,
            "decision role #{role.inspect} is invalid for #{action}"
        end

        role
      rescue NoMethodError, ArgumentError
        raise RubyRouting::State::DurableCorruptionError,
          "decision role is malformed for #{action}"
      end

      def validate_policy_binding(state, payload)
        policy_epoch = payload.fetch(:policy_epoch)
        unless policy_epoch.is_a?(String) && !policy_epoch.empty? && policy_epoch == policy_epoch.strip
          raise RubyRouting::State::DurableCorruptionError,
            "decision policy epoch must be a canonical non-empty String"
        end
        unless state.policy_epoch == policy_epoch && state.policy_scope_key && state.policy_fingerprint
          raise RubyRouting::State::DurableCorruptionError,
            "decision policy binding does not match #{state.intent.id}"
        end
      rescue KeyError => error
        raise RubyRouting::State::DurableCorruptionError,
          "decision policy binding is incomplete: #{error.message}"
      end

      def validate_non_operation_decision(state:, action:, payload:)
        role = decision_role(payload.fetch(:role), action: action)
        unless payload[:provider_id].nil? && payload[:attempt_id].nil? && payload[:operation_id].nil?
          raise RubyRouting::State::DurableCorruptionError,
            "non-operation decision carries operation identifiers"
        end

        available_provider_ids = payload[:available_provider_ids]
        unless available_provider_ids.nil? || canonical_provider_id_list?(available_provider_ids)
          raise RubyRouting::State::DurableCorruptionError,
            "non-operation decision has malformed available provider context"
        end
        expected_role = action == :defer && state.ownership.nil? ? :recovery : :resolution
        unless role == expected_role
          raise RubyRouting::State::DurableCorruptionError,
            "decision role #{role.inspect} does not match #{action} state"
        end

        policy = policy_for(state, "non-operation decision")
        classification = recovery_classification_for(state, policy)

        expected = if state.ownership && %i[resolve retry_same].include?(classification.action)
          unless canonical_provider_id_list?(available_provider_ids) &&
                 !available_provider_ids.include?(state.ownership.provider_id)
            raise RubyRouting::State::DurableCorruptionError,
              "adapter-unavailable decision has no matching provider context"
          end
          {
            action: :defer,
            reasons: ["existing operation adapter is unavailable"],
            reason_codes: [:adapter_unavailable],
            runtime_feasibility: nil,
            allocation_deviation_cause: nil,
            allocation_deviation_recoverability: nil,
            measure: nil
          }
        elsif %i[already_final terminate defer].include?(classification.action)
          {
            action: classification.action,
            reasons: [classification.reason],
            reason_codes: [classification.reason_code].compact,
            runtime_feasibility: nil,
            allocation_deviation_cause: nil,
            allocation_deviation_recoverability: nil,
            measure: nil
          }
        elsif state.attempts.length.positive? &&
              provider_switch_count_for(state) >= policy.recovery.max_switches
          {
            action: :defer,
            reasons: ["provider switch budget exhausted"],
            reason_codes: [:switch_budget_exhausted],
            runtime_feasibility: nil,
            allocation_deviation_cause: nil,
            allocation_deviation_recoverability: nil,
            measure: nil
          }
        else
          expected_no_route_decision_trace(state: state, policy: policy)
        end

        unless @decision_enum.call(
          payload,
          :action,
          RubyRouting::DecisionProposal::ACTIONS,
          "decision action"
        ) == expected.fetch(:action) &&
               payload.fetch(:reasons) == expected.fetch(:reasons) &&
               payload.fetch(:reason_codes) == expected.fetch(:reason_codes) &&
               payload[:runtime_feasibility] == expected.fetch(:runtime_feasibility) &&
               payload[:allocation_deviation_cause] == expected.fetch(:allocation_deviation_cause, nil) &&
               payload[:allocation_deviation_recoverability] == expected.fetch(:allocation_deviation_recoverability, nil) &&
               payload[:measure] == expected.fetch(:measure, nil)
          raise RubyRouting::State::DurableCorruptionError,
            "non-operation decision trace does not match #{state.intent.id}"
        end
      rescue KeyError, ArgumentError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed non-operation decision trace: #{error.message}"
      end

      def validate_resolution_trace(state:, attempt:, action:, payload:)
        if restart_recovery_trace?(payload, action)
          return
        end

        policy = policy_for(state, "resolution decision")
        classification = recovery_classification_for(state, policy)
        expected_reason_codes = [classification.reason_code].compact
        unless classification.action == action &&
               payload.fetch(:reasons) == [classification.reason] &&
               payload.fetch(:reason_codes) == expected_reason_codes
          raise RubyRouting::State::DurableCorruptionError,
            "resolution decision trace does not match #{attempt.operation_id}"
        end
      rescue KeyError, ArgumentError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed resolution decision trace: #{error.message}"
      end

      def validate_assignment_trace(state:, payload:, provider_id:)
        evaluation = state.latest_opportunity_evaluation
        unless evaluation
          raise RubyRouting::State::DurableCorruptionError,
            "assignment decision has no preceding opportunity evaluation"
        end

        policy = policy_for(state, "assignment decision")
        _evaluation, allocation = allocation_for_evaluation(state: state, policy: policy)
        quality = evaluation.fetch(:quality).to_h do |evaluation_provider_id, quality_payload|
          [
            evaluation_provider_id,
            RubyRouting::Routing::ProviderQualitySnapshot.new(
              provider_id: quality_payload.fetch(:provider_id),
              successful_samples: quality_payload.fetch(:successful_samples),
              failed_samples: quality_payload.fetch(:failed_samples),
              minimum_samples: quality_payload.fetch(:minimum_samples),
              context_key: quality_payload.fetch(:context_key),
              evidence_scope: quality_payload.fetch(:evidence_scope)
            )
          ]
        end
        eligibility = RubyRouting::Routing::EligibilityResult.new(
          opportunities: evaluation.fetch(:opportunities),
          opportunity_provider_ids: evaluation.fetch(:opportunities),
          functional_provider_ids: evaluation.fetch(:functional_provider_ids),
          feasible_provider_ids: evaluation.fetch(:feasible_provider_ids),
          exclusions: evaluation.fetch(:exclusions),
          exclusion_codes: evaluation.fetch(:exclusion_codes),
          soft_violations: evaluation.fetch(:soft_violations)
        )
        expected_proposal = RubyRouting::Routing::DecisionEngine.assignment_proposal(
          policy: policy,
          allocation: allocation,
          eligibility: eligibility,
          payout_state: @payout_snapshot.call(state),
          quality: quality,
          runtime_feasibility: nil
        )
        optimized = expected_proposal.allocation_decision
        expected_soft_violations = evaluation.fetch(:soft_violations).fetch(provider_id, [])

        unless expected_proposal.reasons == payload.fetch(:reasons) &&
               expected_proposal.reason_codes == payload.fetch(:reason_codes) &&
               optimized.chosen_provider == provider_id &&
               payload.fetch(:snapshot_revision) == optimized.snapshot_revision &&
               payload.fetch(:allocation_discrepancy) == optimized.discrepancy &&
               payload.fetch(:allocation_candidates) == allocation.candidate_trace &&
               payload.fetch(:allocation_deviation_cause) == optimized.deviation_cause &&
               payload.fetch(:allocation_deviation_recoverability) == optimized.deviation_recoverability &&
               payload.fetch(:allocation_tolerance) == optimized.tolerance &&
               payload.fetch(:allocation_share_violations) == optimized.share_violations &&
               payload.fetch(:optimization_trace) == optimized.optimization_trace &&
               payload.fetch(:runtime_feasibility) == evaluation.fetch(:runtime_feasibility) &&
               payload.fetch(:soft_constraint_violations) == expected_soft_violations
          raise RubyRouting::State::DurableCorruptionError,
            "assignment decision trace does not match #{state.intent.id}"
        end
      rescue KeyError, ArgumentError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed assignment decision trace: #{error.message}"
      end

      def validate_assignment(fact:, state:, provider_id:, operation_id:, attempt_id:, role:, measure:, contract:)
        unless state.ownership.nil? && !%i[success reversed terminal_payout_failure].include?(state.status) &&
               state.dispatch_pending[operation_id].nil?
          raise RubyRouting::State::DurableCorruptionError,
            "assignment decision is not valid for current payout state"
        end
        if role == :primary && (state.attempts.any? || state.primary_provider_id)
          raise RubyRouting::State::DurableCorruptionError,
            "duplicate primary assignment decision for #{fact.payout_id}"
        end
        if role == :recovery && state.primary_provider_id.nil?
          raise RubyRouting::State::DurableCorruptionError,
            "recovery assignment has no primary assignment for #{fact.payout_id}"
        end
        unless measure.is_a?(Integer) && measure >= 0
          raise RubyRouting::State::DurableCorruptionError,
            "assignment decision measure is malformed for #{operation_id}"
        end
        unless contract.is_a?(RubyRouting::ProviderOperationContract) &&
               contract.provider_id == provider_id &&
               contract.idempotency_key == "#{fact.payout_id}:#{operation_id}"
          raise RubyRouting::State::DurableCorruptionError,
            "assignment decision contract does not match #{operation_id}"
        end
        provider_opportunity = provider_catalog.fetch(provider_id) do
          raise RubyRouting::State::DurableCorruptionError,
            "assignment decision references unknown provider #{provider_id}"
        end
        evaluation = state.latest_opportunity_evaluation
        unless evaluation && RubyRouting::Collection.to_array(
          evaluation.fetch(:feasible_provider_ids),
          "feasible provider ids"
        ).include?(provider_id)
          raise RubyRouting::State::DurableCorruptionError,
            "assignment decision is outside the evaluated feasible cohort for #{operation_id}"
        end
        capacity_reservation = state.capacity_reservations[operation_id]
        if provider_opportunity.capacity
          unless capacity_reservation == [provider_id, state.intent.money]
            raise RubyRouting::State::DurableCorruptionError,
              "assignment decision is missing its capacity reservation for #{operation_id}"
          end
        elsif capacity_reservation
          raise RubyRouting::State::DurableCorruptionError,
            "assignment decision has an unexpected capacity reservation for #{operation_id}"
        end
        policy = policy_for(state, "assignment decision")
        expected_contract = RubyRouting::ProviderOperationContract.from_capabilities(
          provider_id: provider_id,
          payout_id: fact.payout_id,
          operation_id: operation_id,
          capabilities: provider_opportunity.capabilities,
          ttl_seconds: policy.recovery.ttl_seconds || :inherit,
          deadline_seconds: policy.recovery.deadline_seconds || :inherit
        )
        unless @same_contract.call(contract, expected_contract)
          raise RubyRouting::State::DurableCorruptionError,
            "assignment decision contract does not match provider capabilities for #{operation_id}"
        end
        unless policy.measure_for(state.intent.money) == measure
          raise RubyRouting::State::DurableCorruptionError,
            "assignment decision measure does not match policy for #{operation_id}"
        end
      rescue KeyError, ArgumentError, TypeError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed assignment decision: #{error.message}"
      end

      def validate_resolution(state:, attempt:, action:, payload:, provider_id:, attempt_id:, role:, operation_id:)
        restart_recovery = restart_recovery_trace?(payload, action)
        unless state.ownership&.operation_id == operation_id &&
               attempt.provider_id == provider_id &&
               attempt.attempt_id == attempt_id &&
               role == :resolution &&
               (restart_recovery ? %i[dispatching resolving] : %i[pending unknown]).include?(attempt.phase) &&
               state.dispatch_pending[operation_id].nil?
          raise RubyRouting::State::DurableCorruptionError,
            "#{action} decision does not match unresolved operation #{operation_id}"
        end

        contract = attempt.contract
        allowed = if action == :resolve
          contract&.status_lookup
        else
          contract&.idempotent_retry
        end
        return if allowed

        capability = action == :resolve ? "status_lookup" : "idempotent_retry"
        raise RubyRouting::State::DurableCorruptionError,
          "#{action} decision is not allowed by operation contract (#{capability})"
      end

      private

      def policies
        @policies.call
      end

      def provider_catalog
        @provider_catalog.call
      end

      def policy_for(state, label)
        policies.fetch(state.policy_scope_key) do
          raise RubyRouting::State::DurableCorruptionError,
            "#{label} references missing policy for #{state.intent.id}"
        end
      end

      def expected_no_route_decision_trace(state:, policy:)
        evaluation, allocation = allocation_for_evaluation(state: state, policy: policy)
        unless allocation.no_route?
          raise RubyRouting::State::DurableCorruptionError,
            "deferred decision has an admissible route for #{state.intent.id}"
        end

        runtime_feasibility = evaluation.fetch(:runtime_feasibility)
        runtime_reason_codes = runtime_feasibility.fetch(:reason_codes)
        reasons = ["no safe feasible provider"]
        reasons << "excluded=#{evaluation.fetch(:exclusions).inspect}" unless evaluation.fetch(:exclusions).empty?
        allocation_exclusions = evaluation.fetch(:allocation_exclusions)
        deviation = RubyRouting::Routing::DecisionEngine.no_route_deviation(
          eligibility: RubyRouting::Routing::EligibilityResult.new(
            opportunities: evaluation.fetch(:opportunities),
            opportunity_provider_ids: evaluation.fetch(:opportunities),
            functional_provider_ids: evaluation.fetch(:functional_provider_ids),
            feasible_provider_ids: evaluation.fetch(:feasible_provider_ids),
            exclusions: evaluation.fetch(:exclusions),
            exclusion_codes: evaluation.fetch(:exclusion_codes),
            soft_violations: evaluation.fetch(:soft_violations)
          ),
          allocation_exclusions: allocation_exclusions,
          runtime_feasibility: RubyRouting::Routing::RuntimeFeasibility.new(
            status: runtime_feasibility.fetch(:status),
            reason_codes: runtime_reason_codes,
            functional_target_provider_ids: runtime_feasibility.fetch(:functional_target_provider_ids),
            feasible_target_provider_ids: runtime_feasibility.fetch(:feasible_target_provider_ids),
            unattempted_provider_ids: runtime_feasibility.fetch(:unattempted_provider_ids),
            measure_admissible_provider_ids: runtime_feasibility.fetch(:measure_admissible_provider_ids)
          )
        )
        reasons << "allocation_limits=#{allocation_exclusions.inspect}" unless allocation_exclusions.empty?
        reasons << "runtime_feasibility=#{runtime_feasibility.inspect}"

        {
          action: :defer,
          reasons: reasons,
          reason_codes: [
            :no_safe_route,
            (
              :runtime_policy_infeasible if RubyRouting::Enum.normalize(
                runtime_feasibility.fetch(:status),
                RubyRouting::Routing::RuntimeFeasibility::STATUSES,
                "runtime feasibility status"
              ) == :infeasible &&
                !runtime_reason_codes.include?(:recovery_provider_exhausted)
            ),
            *runtime_reason_codes,
            *evaluation.fetch(:exclusion_codes).values.uniq,
            *allocation_exclusions.values.uniq
          ].compact,
          runtime_feasibility: runtime_feasibility,
          allocation_deviation_cause: deviation.fetch(:cause),
          allocation_deviation_recoverability: deviation.fetch(:recoverability),
          measure: policy.measure_for(state.intent.money)
        }
      end

      def allocation_for_evaluation(state:, policy:)
        evaluation = state.latest_opportunity_evaluation
        unless evaluation
          raise RubyRouting::State::DurableCorruptionError,
            "decision has no preceding opportunity evaluation"
        end

        snapshot_payload = evaluation.fetch(:allocation_snapshot)
        allocation_snapshot = RubyRouting::Routing::AllocationSnapshot.new(
          measures: snapshot_payload.fetch(:measures),
          revision: snapshot_payload.fetch(:revision)
        )
        allocation = RubyRouting::Routing::Allocation.choose(
          policy: policy,
          candidates: evaluation.fetch(:feasible_provider_ids) - state.attempts.map(&:provider_id),
          snapshot: allocation_snapshot,
          incoming_measure: policy.measure_for(state.intent.money),
          accounting_provider_ids: evaluation.fetch(:functional_provider_ids)
        )
        [evaluation, allocation]
      end

      def recovery_classification_for(state, policy)
        current_operation = state.ownership && state.operations[state.ownership.operation_id]
        RubyRouting::Routing::Recovery.classify(
          status: state.status,
          ownership: state.ownership,
          capabilities: current_operation&.contract,
          operation_phase: current_operation&.phase,
          attempts: state.attempts.length,
          policy: policy.recovery,
          resolution_interactions: state.resolution_interaction_count
        )
      end

      def provider_switch_count_for(state)
        state.attempts.map(&:provider_id).each_cons(2).count { |left, right| left != right }
      end

      def canonical_provider_id_list?(value)
        value.is_a?(Array) &&
          value == value.uniq &&
          value.all? { |provider_id| provider_id.is_a?(String) && !provider_id.empty? && provider_id == provider_id.strip }
      end

      def restart_recovery_trace?(payload, action)
        expected_reason = action == :resolve ?
          "reconciled provider operation after restart" :
          "retried idempotent provider operation after restart"
        payload[:reason_codes] == [:restart_recovery] &&
          payload[:reasons] == [expected_reason]
      end
    end
  end
end
