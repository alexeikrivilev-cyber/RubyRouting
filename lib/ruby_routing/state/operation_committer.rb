# frozen_string_literal: true

module RubyRouting
  module State
    # Owns the fact-producing operation lifecycle writes that sit between a
    # routing decision and provider observation. The coordinator remains the
    # atomic transaction facade, but assignment, retry/resolve transitions and
    # ownership release no longer form part of its implementation surface.
    class OperationCommitter
      def initialize(
        admission_ledger:,
        allocation_ledger:,
        lifecycle_ledger:,
        health_controller:,
        append_fact:,
        current_time:,
        current_monotonic:,
        snapshot_for:,
        contract_payload:,
        attempt_state:
      )
        @admission_ledger = admission_ledger
        @allocation_ledger = allocation_ledger
        @lifecycle_ledger = lifecycle_ledger
        @health_controller = health_controller
        @append_fact = append_fact
        @current_time = current_time
        @current_monotonic = current_monotonic
        @snapshot_for = snapshot_for
        @contract_payload = contract_payload
        @attempt_state = attempt_state
      end

      def commit_assignment(state, intent, policy, proposal, eligibility, allocation_snapshot)
        state.recovery_schedule = nil
        next_number = state.attempts.length + 1
        attempt_id = "#{intent.id}:attempt:#{next_number}".freeze
        operation_id = "#{intent.id}:operation:#{next_number}".freeze
        committed_at = current_time
        committed_monotonic_at = current_monotonic
        committed_proposal = proposal.with_identifiers(operation_id: operation_id, attempt_id: attempt_id)
        measure = policy.measure_for(intent.money)
        allocation_key = policy.allocation_key(
          opportunity_provider_ids: eligibility.functional_provider_ids
        )
        contract = RubyRouting::ProviderOperationContract.from_capabilities(
          provider_id: committed_proposal.provider_id,
          payout_id: intent.id,
          operation_id: operation_id,
          capabilities: eligibility.opportunities
            .find { |opportunity| opportunity.provider_id == committed_proposal.provider_id }
            .capabilities,
          ttl_seconds: policy.recovery.ttl_seconds || :inherit,
          deadline_seconds: policy.recovery.deadline_seconds || :inherit
        )
        provider_opportunity = eligibility.opportunities.find do |opportunity|
          opportunity.provider_id == committed_proposal.provider_id
        end
        health_before_commit = @health_controller.snapshot(provider_opportunity.provider_id)
        unless @health_controller.reserve_exposure(
          provider_opportunity.provider_id,
          owner: operation_id
        )
          raise ArgumentError, "provider health exposure became unavailable before commit"
        end
        health_probe_reserved = health_before_commit.state == :probing
        begin
          capacity_reserved = reserve_capacity!(state, provider_opportunity, intent, operation_id)
          throughput_event = @admission_ledger.reserve_throughput!(provider_opportunity)
        rescue StandardError
          release_capacity_reservation!(state, operation_id) if state.capacity_reservations.key?(operation_id)
          @health_controller.release_exposure(provider_opportunity.provider_id, owner: operation_id)
          raise
        end
        state.health_exposure_reservations[operation_id] = true if health_probe_reserved

        append_fact(
          :decision_committed,
          intent.id,
          action: committed_proposal.action,
          provider_id: committed_proposal.provider_id,
          operation_id: operation_id,
          attempt_id: attempt_id,
          role: committed_proposal.role,
          policy_epoch: policy.epoch,
          reasons: committed_proposal.reasons,
          reason_codes: committed_proposal.reason_codes,
          snapshot_revision: allocation_snapshot.revision,
          allocation_discrepancy: committed_proposal.allocation_decision.discrepancy,
          allocation_candidates: committed_proposal.allocation_decision.candidate_trace,
          allocation_deviation_cause: committed_proposal.allocation_decision.deviation_cause,
          allocation_deviation_recoverability: committed_proposal.allocation_decision.deviation_recoverability,
          allocation_tolerance: committed_proposal.allocation_decision.tolerance,
          allocation_share_violations: committed_proposal.allocation_decision.share_violations,
          optimization_trace: committed_proposal.allocation_decision.optimization_trace,
          runtime_feasibility: committed_proposal.runtime_feasibility&.to_h,
          soft_constraint_violations: eligibility.soft_violations.fetch(committed_proposal.provider_id, []),
          measure: measure,
          measure_kind: policy.measure,
          currency: policy.currency,
          allocation_key: allocation_key,
          committed_at: committed_at,
          committed_monotonic_at: committed_monotonic_at,
          contract: contract_payload(contract)
        )
        append_fact(
          :allocation_committed,
          intent.id,
          policy_id: policy.id,
          policy_scope: policy.scope,
          policy_fingerprint: policy.fingerprint,
          allocation_key: allocation_key,
          policy_epoch: policy.epoch,
          measure_kind: policy.measure,
          currency: policy.currency,
          provider_id: committed_proposal.provider_id,
          operation_id: operation_id,
          attempt_id: attempt_id,
          measure: measure,
          role: committed_proposal.role,
          capacity_reserved: capacity_reserved
        )
        if health_probe_reserved
          append_fact(
            :health_exposure_reserved,
            intent.id,
            provider_id: provider_opportunity.provider_id,
            operation_id: operation_id,
            attempt_id: attempt_id
          )
        end
        if throughput_event
          append_fact(
            :throughput_consumed,
            intent.id,
            provider_id: provider_opportunity.provider_id,
            operation_id: operation_id,
            consumed_at: throughput_event.consumed_at,
            consumed_monotonic_at: throughput_event.monotonic_at,
            budget: provider_opportunity.throughput.to_h
          )
        end
        ownership = RubyRouting::EconomicOwnership.new(
          payout_id: intent.id,
          provider_id: committed_proposal.provider_id,
          operation_id: operation_id,
          attempt_id: attempt_id
        )
        append_fact(
          :ownership_acquired,
          intent.id,
          provider_id: ownership.provider_id,
          operation_id: ownership.operation_id,
          attempt_id: ownership.attempt_id,
          acquired_at: committed_at
        )

        state.ownership = ownership
        state.status = :pending
        state.policy_epoch = policy.epoch
        state.primary_provider_id ||= committed_proposal.provider_id if committed_proposal.role == :primary
        attempt = @attempt_state.call(
          attempt_id: attempt_id,
          operation_id: operation_id,
          provider_id: committed_proposal.provider_id,
          role: committed_proposal.role,
          measure: measure,
          phase: :committed,
          contract: contract,
          committed_at: committed_at,
          committed_monotonic_at: committed_monotonic_at
        )
        state.attempts << attempt
        state.operations[operation_id] = attempt
        state.dispatch_pending[operation_id] = true
        state.operation_actions[operation_id] = :assign
        if throughput_event
          state.throughput_reservations[operation_id] = [
            provider_opportunity.provider_id,
            throughput_event.consumed_at,
            throughput_event.monotonic_at
          ].freeze
        end
        if committed_proposal.role == :primary && policy.accounting_point == :primary_assignment
          @allocation_ledger.commit(
            key: allocation_key,
            provider_id: committed_proposal.provider_id,
            measure: measure
          )
        end
        RubyRouting::State::DecisionCommit.new(
          proposal: committed_proposal,
          request: RubyRouting::ProviderOperationRequest.from_intent(
            intent: intent,
            provider_id: committed_proposal.provider_id,
            operation_id: operation_id,
            attempt_id: attempt_id,
            contract: contract
          ),
          payout: snapshot_for(state)
        )
      end

      def commit_resolution(state, intent, policy, proposal)
        state.recovery_schedule = nil
        attempt = state.operations.fetch(proposal.operation_id)
        append_fact(
          :decision_committed,
          intent.id,
          action: proposal.action,
          provider_id: proposal.provider_id,
          operation_id: proposal.operation_id,
          attempt_id: proposal.attempt_id,
          role: proposal.role,
          policy_epoch: policy.epoch,
          reasons: proposal.reasons,
          reason_codes: proposal.reason_codes
        )
        if proposal.action == :resolve
          set_operation_phase(state, proposal.operation_id, :resolving)
          state.dispatch_pending[proposal.operation_id] = :resolution
        elsif proposal.action == :retry_same
          set_operation_phase(state, proposal.operation_id, :dispatching)
          state.dispatch_pending[proposal.operation_id] = true
        end
        state.operation_actions[proposal.operation_id] = proposal.action
        RubyRouting::State::DecisionCommit.new(
          proposal: proposal,
          request: RubyRouting::ProviderOperationRequest.from_intent(
            intent: intent,
            provider_id: proposal.provider_id,
            operation_id: proposal.operation_id,
            attempt_id: proposal.attempt_id,
            contract: attempt.contract
          ),
          payout: snapshot_for(state)
        )
      end

      def apply_outcome(state, attempt, outcome)
        transition = @lifecycle_ledger.apply_outcome(state, attempt, outcome)
        return unless transition

        append_phase_change(state, transition.phase_change) if transition.phase_change
        if transition.settled?
          state.settlement_provider_id = attempt.provider_id
          state.settlement_operation_id = attempt.operation_id
          release_ownership(state, attempt, outcome)
          append_fact(
            :settlement_recorded,
            state.intent.id,
            provider_id: attempt.provider_id,
            operation_id: attempt.operation_id,
            outcome: outcome.status,
            measure: attempt.measure,
            settled_at: current_time
          )
        elsif transition.release_ownership?
          release_ownership(state, attempt, outcome)
        end
      end

      def set_operation_phase(state, operation_id, phase)
        attempt = state.operations.fetch(operation_id)
        normalized_phase = RubyRouting::Enum.normalize(
          phase,
          RubyRouting::State::AttemptSnapshot::PHASES,
          "operation phase"
        )
        return if attempt.phase == normalized_phase

        phase_change = @lifecycle_ledger.apply_phase_change(
          state,
          operation_id,
          from: attempt.phase,
          to: normalized_phase
        )
        append_phase_change(state, phase_change)
      end

      def append_phase_change(state, phase_change)
        return unless phase_change

        append_fact(
          :operation_phase_changed,
          state.intent.id,
          operation_id: phase_change.operation_id,
          attempt_id: phase_change.attempt_id,
          provider_id: phase_change.provider_id,
          from: phase_change.from,
          to: phase_change.to,
          changed_at: current_time
        )
      end

      private

      def release_ownership(state, attempt, outcome)
        state.dispatch_pending.delete(attempt.operation_id)
        release_capacity_reservation!(state, attempt.operation_id)
        health_probe_released = state.health_exposure_reservations.delete(attempt.operation_id)
        @health_controller.release_exposure(attempt.provider_id, owner: attempt.operation_id) if health_probe_released
        if health_probe_released
          append_fact(
            :health_exposure_released,
            state.intent.id,
            provider_id: attempt.provider_id,
            operation_id: attempt.operation_id,
            attempt_id: attempt.attempt_id
          )
        end
        append_fact(
          :ownership_released,
          state.intent.id,
          provider_id: attempt.provider_id,
          operation_id: attempt.operation_id,
          attempt_id: attempt.attempt_id,
          reason: outcome.status
        )
        state.ownership = nil
      end

      def reserve_capacity!(state, opportunity, intent, operation_id)
        return false unless opportunity.capacity

        @admission_ledger.reserve_capacity!(opportunity, intent)
        state.capacity_reservations[operation_id] = [opportunity.provider_id, intent.money]
        append_fact(
          :capacity_reserved,
          intent.id,
          provider_id: opportunity.provider_id,
          operation_id: operation_id,
          amount: intent.money
        )
        true
      end

      def release_capacity_reservation!(state, operation_id)
        reservation = state.capacity_reservations.delete(operation_id)
        return unless reservation

        provider_id, money = reservation
        @admission_ledger.release_capacity!(provider_id, money)
        append_fact(
          :capacity_released,
          state.intent.id,
          provider_id: provider_id,
          operation_id: operation_id,
          amount: money
        )
      end

      def append_fact(type, payout_id, payload)
        @append_fact.call(type, payout_id, payload)
      end

      def current_time
        @current_time.call
      end

      def current_monotonic
        @current_monotonic.call
      end

      def snapshot_for(state)
        @snapshot_for.call(state)
      end

      def contract_payload(contract)
        @contract_payload.call(contract)
      end

    end
  end
end
