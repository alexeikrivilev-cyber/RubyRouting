# frozen_string_literal: true

module RubyRouting
  module State
    class Coordinator
      def initialize(opportunities: [], health_policy: RubyRouting::Routing::HealthPolicy.new, clock: nil)
        @mutex = Thread::Mutex.new
        @payouts = {}
        @provider_opportunities = {}
        @capacity_usage = {}
        @allocation_snapshots = {}
        @health_controller = RubyRouting::Routing::HealthController.new(policy: health_policy)
        @clock = clock
        @facts = []
        @sequence = 0
        @revision = 0
        replace_provider_opportunities(opportunities)
      end

      def register_intent(intent)
        unless intent.is_a?(RubyRouting::PayoutIntent)
          raise ArgumentError, "intent must be PayoutIntent"
        end

        synchronize do
          existing = @payouts[intent.id]
          if existing
            unless same_intent?(existing.intent, intent)
              raise ArgumentError, "payout id is already registered with different intent"
            end
            return snapshot_for(existing)
          end

          state = PayoutState.new(intent)
          state.created_at = current_time
          @payouts[intent.id] = state
          append_fact(
            :intent_registered,
            intent.id,
            money: intent.money,
            recipient: intent.recipient,
            context: intent.context,
            created_at: state.created_at
          )
          snapshot_for(state)
        end
      end

      def replace_provider_opportunities(opportunities)
        unless opportunities.respond_to?(:each)
          raise ArgumentError, "opportunities must be enumerable"
        end

        normalized = opportunities.to_a
        unless normalized.all? { |opportunity| opportunity.is_a?(RubyRouting::ProviderOpportunity) }
          raise ArgumentError, "opportunities must contain ProviderOpportunity values"
        end

        ids = normalized.map(&:provider_id)
        raise ArgumentError, "provider opportunities must have unique ids" unless ids.uniq.length == ids.length

        synchronize do
          normalized.each do |opportunity|
            append_fact(
              :provider_opportunity_registered,
              "system:provider:#{opportunity.provider_id}",
              provider_id: opportunity.provider_id,
              capacity: opportunity.capacity&.to_h,
              health_policy: @health_controller.policy.to_h
            )
          end
          @provider_opportunities = normalized.to_h { |opportunity| [opportunity.provider_id, opportunity] }
          normalized.each do |opportunity|
            @capacity_usage[opportunity.provider_id] ||= CapacityUsage.new
          end
        end
        nil
      end

      def set_provider_availability(provider_id, available:, capacity_available: nil)
        synchronize do
          current = @provider_opportunities.fetch(normalized_provider_id(provider_id)) do
            raise ArgumentError, "unknown provider opportunity"
          end
          replacement = current.with_runtime(
            available: available,
            capacity_available: capacity_available.nil? ? current.capacity_available : capacity_available
          )
          @provider_opportunities[current.provider_id] = replacement
        end
        nil
      end

      def provider_opportunities
        synchronize { @provider_opportunities.values.sort_by(&:provider_id).freeze }
      end

      # The returned commit is complete before the caller is allowed to invoke
      # a provider. No provider object is called from this method or its lock.
      def prepare_and_commit_decision(intent:, policy:, available_provider_ids: nil)
        unless intent.is_a?(RubyRouting::PayoutIntent)
          raise ArgumentError, "intent must be PayoutIntent"
        end
        unless policy.is_a?(RubyRouting::RoutingPolicy)
          raise ArgumentError, "policy must be RoutingPolicy"
        end

        # Validate command-local policy/input values before pinning any policy
        # identity or registering the intent. A malformed volume currency or
        # adapter-id list must not leave a half-pinned payout behind.
        incoming_measure = policy.measure_for(intent.money)
        normalized_available_provider_ids = available_provider_ids&.map do |provider_id|
          normalized_provider_id(provider_id)
        end&.uniq&.freeze

        synchronize do
          state = @payouts[intent.id]
          if state
            unless same_intent?(state.intent, intent)
              raise ArgumentError, "payout id is already registered with different intent"
            end
            validate_policy_identity!(state, policy)
          else
            validate_policy_identity!(nil, policy)
            state = PayoutState.new(intent)
            state.created_at = current_time
            @payouts[intent.id] = state
            append_fact(
              :intent_registered,
              intent.id,
              money: intent.money,
              recipient: intent.recipient,
              context: intent.context,
              created_at: state.created_at
            )
          end
          state.created_at ||= current_time
          register_policy!(state, intent, policy)
          expire_unresolved_operation!(state)

          opportunities = @provider_opportunities.values
            .select do |opportunity|
              normalized_available_provider_ids.nil? || normalized_available_provider_ids.include?(opportunity.provider_id)
            end
            .sort_by(&:provider_id)
          opportunities = opportunities.map do |opportunity|
            opportunity.with_runtime(
              capacity_available: capacity_available_for?(opportunity, intent),
              health_available: opportunity.health_available && health_available_for?(opportunity.provider_id)
            )
          end
          eligibility = RubyRouting::Routing::Eligibility.evaluate(
            opportunities,
            intent: intent,
            policy: policy
          )
          allocation_exclusions = policy_measure_exclusions(
            eligibility: eligibility,
            policy: policy,
            incoming_measure: incoming_measure
          )
          allocation_snapshot = allocation_snapshot_for(policy)
          append_fact(
            :opportunity_evaluated,
            intent.id,
            policy_id: policy.id,
            policy_epoch: policy.epoch,
            policy_scope: policy.scope,
            policy_fingerprint: policy.fingerprint,
            opportunities: eligibility.opportunity_provider_ids,
            functional_provider_ids: eligibility.functional_provider_ids,
            feasible_provider_ids: eligibility.feasible_provider_ids,
            exclusions: eligibility.exclusions,
            exclusion_codes: eligibility.exclusion_codes,
            allocation_exclusions: allocation_exclusions,
            soft_violations: eligibility.soft_violations,
            allocation_snapshot: {
              revision: allocation_snapshot.revision,
              measures: allocation_snapshot.measures
            },
            capacity: eligibility.opportunities.to_h do |opportunity|
              [opportunity.provider_id, capacity_trace_for(opportunity)]
            end,
            health: eligibility.opportunities.to_h do |opportunity|
              [opportunity.provider_id, @health_controller.snapshot(opportunity.provider_id).to_h]
            end,
            ranking: policy.ranking.to_h,
            health_policy: @health_controller.policy.to_h,
            previous_outcome: outcome_trace_for(state.last_outcome)
          )
          proposal = RubyRouting::Routing::DecisionEngine.decide(
            intent: intent,
            policy: policy,
            opportunities: opportunities,
            allocation_snapshot: allocation_snapshot,
            payout_state: snapshot_for(state),
            available_provider_ids: normalized_available_provider_ids
          )

          case proposal.action
          when :assign
            commit_assignment(state, intent, policy, proposal, eligibility, allocation_snapshot)
          when :resolve, :retry_same
            commit_resolution(state, intent, policy, proposal)
          else
            append_fact(
              :decision_committed,
              intent.id,
              action: proposal.action,
              role: proposal.role,
              policy_epoch: policy.epoch,
              provider_id: proposal.provider_id,
              reasons: proposal.reasons,
              reason_codes: proposal.reason_codes
            )
            DecisionCommit.new(proposal: proposal, request: nil, payout: snapshot_for(state))
          end
        end
      end

      def mark_attempt_started(decision_commit)
        unless decision_commit.is_a?(DecisionCommit) && decision_commit.proposal.assignment?
          raise ArgumentError, "an assignment decision commit is required"
        end

        synchronize do
          state = @payouts.fetch(decision_commit.payout.id)
          operation_id = decision_commit.proposal.operation_id
          attempt = state.operations[operation_id]
          unless attempt
            raise ArgumentError, "unknown committed operation"
          end
          return false unless state.ownership&.operation_id == operation_id
          return false unless state.dispatch_pending.delete(operation_id) == true

          state.provider_interaction_count += 1
          state.resolution_interaction_count += 1 if decision_commit.proposal.action == :retry_same
          set_operation_phase(state, operation_id, :dispatching)
          append_fact(
            :attempt_started,
            state.intent.id,
            attempt_id: decision_commit.proposal.attempt_id,
            operation_id: operation_id,
            provider_id: decision_commit.proposal.provider_id,
            action: decision_commit.proposal.action,
            started_at: current_time
          )
          snapshot_for(state)
        end
      end

      def mark_resolution_started(decision_commit)
        unless decision_commit.is_a?(DecisionCommit) && decision_commit.proposal.resolution?
          raise ArgumentError, "a resolution decision commit is required"
        end

        synchronize do
          state = @payouts.fetch(decision_commit.payout.id)
          operation_id = decision_commit.proposal.operation_id
          return false unless state.ownership&.operation_id == operation_id
          return false unless state.dispatch_pending.delete(operation_id) == :resolution

          state.provider_interaction_count += 1
          state.resolution_interaction_count += 1
          append_fact(
            :attempt_started,
            state.intent.id,
            attempt_id: decision_commit.proposal.attempt_id,
            operation_id: operation_id,
            provider_id: decision_commit.proposal.provider_id,
            action: decision_commit.proposal.action,
            started_at: current_time
          )
          true
        end
      end

      def apply_observation(observation)
        unless observation.is_a?(RubyRouting::ProviderObservation)
          raise ArgumentError, "observation must be ProviderObservation"
        end

        synchronize do
          state = @payouts.fetch(observation.payout_id) do
            raise ArgumentError, "observation references unknown payout"
          end
          attempt = state.operations.fetch(observation.operation_id) do
            raise ArgumentError, "observation references unknown operation"
          end
          unless attempt.provider_id == observation.provider_id && attempt.attempt_id == observation.attempt_id
            raise ArgumentError, "observation operation linkage does not match"
          end

          if state.seen_observations.key?(observation.observation_id)
            unless state.seen_observations.fetch(observation.observation_id) == observation_signature(observation)
              raise ArgumentError, "observation id was reused with different payload"
            end

            return ObservationApplication.new(
              payout: snapshot_for(state),
              next_action: next_action_for(state),
              duplicate: true
            )
          end

          current_operation = state.ownership && state.ownership.operation_id == observation.operation_id
          applies = !!(current_operation && observation_applies?(attempt, observation))
          conflict = !current_operation && late_monetary_conflict?(attempt, observation)
          state.seen_observations[observation.observation_id] = observation_signature(observation)
          append_fact(
            :provider_observed,
            state.intent.id,
            observation_id: observation.observation_id,
            operation_id: observation.operation_id,
            attempt_id: observation.attempt_id,
            provider_id: observation.provider_id,
            status: observation.outcome.status,
            attribution: observation.outcome.attribution,
            provider_reference: observation.provider_reference,
            outcome_provider_reference: observation.outcome.provider_reference,
            message: observation.outcome.message,
            safe_to_release: observation.outcome.safe_to_release?,
            sequence: observation.sequence,
            observed_at: observation.observed_at,
            transport_kind: observation.transport_kind,
            applied: applies,
            conflict: conflict
          )
          if observation.transport_kind
            append_fact(
              :transport_classified,
              state.intent.id,
              operation_id: observation.operation_id,
              attempt_id: observation.attempt_id,
              provider_id: observation.provider_id,
              kind: observation.transport_kind
            )
          end
          if conflict
            record_conflict(state, attempt, observation)
          end
          record_health_from_observation(observation)
          return ObservationApplication.new(
            payout: snapshot_for(state),
            next_action: next_action_for(state),
            duplicate: false,
            conflict: conflict
          ) unless applies

          attempt.outcome = observation.outcome
          attempt.last_observation_sequence = observation.sequence unless observation.sequence.nil?
          apply_current_outcome(state, attempt, observation.outcome)
          ObservationApplication.new(
            payout: snapshot_for(state),
            next_action: next_action_for(state),
            duplicate: false,
            conflict: conflict
          )
        end
      end

      def payout_snapshot(payout_id)
        synchronize { snapshot_for(@payouts.fetch(payout_id.to_s)) }
      end

      def record_reversal(payout_id:, reversal_id:, provider_id:, operation_id:, amount:, reason: :returned)
        synchronize do
          state = @payouts.fetch(payout_id.to_s) do
            raise ArgumentError, "reversal references unknown payout"
          end
          unless %i[success reversed].include?(state.status)
            raise ArgumentError, "reversal requires a settled payout"
          end
          unless state.settlement_provider_id == provider_id.to_s &&
                 state.settlement_operation_id == operation_id.to_s
            raise ArgumentError, "reversal settlement linkage does not match"
          end
          unless amount.is_a?(RubyRouting::Money) && amount.currency == state.intent.money.currency
            raise ArgumentError, "reversal currency does not match payout"
          end

          normalized_reversal_id = reversal_id.to_s.strip
          existing = state.reversals.find { |reversal| reversal.reversal_id == normalized_reversal_id }
          if existing
            unless existing.provider_id == provider_id.to_s &&
                   existing.operation_id == operation_id.to_s &&
                   existing.amount == amount && existing.reason == reason.to_sym
              raise ArgumentError, "reversal id was reused with different payload"
            end
            return snapshot_for(state)
          end

          reversed_minor = state.reversals.sum { |reversal| reversal.amount.amount_minor }
          if reversed_minor + amount.amount_minor > state.intent.money.amount_minor
            raise ArgumentError, "reversals cannot exceed settled payout amount"
          end

          reversal = RubyRouting::SettlementReversal.new(
            reversal_id: reversal_id,
            payout_id: payout_id,
            provider_id: provider_id,
            operation_id: operation_id,
            amount: amount,
            reason: reason
          )
          state.reversals << reversal
          state.status = :reversed
          append_fact(
            :reversal_recorded,
            state.intent.id,
            reversal_id: reversal.reversal_id,
            provider_id: reversal.provider_id,
            operation_id: reversal.operation_id,
            amount: reversal.amount,
            reason: reversal.reason
          )
          snapshot_for(state)
        end
      end

      def allocation_snapshot(policy:)
        synchronize do
          @allocation_snapshots.fetch(
            policy.allocation_key,
            RubyRouting::Routing::AllocationSnapshot.empty
          )
        end
      end

      def allocation_projection
        RubyRouting::Projections::Replay.allocation(facts)
      end

      def capacity_snapshot(provider_id)
        synchronize do
          provider = @provider_opportunities.fetch(normalized_provider_id(provider_id)) do
            raise ArgumentError, "unknown provider opportunity"
          end
          usage = @capacity_usage.fetch(provider.provider_id, CapacityUsage.new)
          CapacitySnapshot.new(
            provider_id: provider.provider_id,
            budget: provider.capacity,
            used_slots: usage.slots,
            used_count: usage.count,
            used_amount_minor: usage.amount_minor
          )
        end
      end

      def capacity_projection
        RubyRouting::Projections::Replay.capacity(facts)
      end

      def health_snapshot(provider_id)
        synchronize { @health_controller.snapshot(provider_id) }
      end

      def health_projection
        RubyRouting::Projections::Replay.health(facts)
      end

      def record_health_signal(provider_id:, signal:, attribution: :unknown)
        synchronize do
          record_health_signal_locked(
            provider_id: provider_id,
            signal: signal,
            attribution: attribution
          )
        end
      end

      def current_time
        return nil unless @clock
        return @clock.now if @clock.respond_to?(:now)

        @clock.call
      end

      def facts
        synchronize { @facts.dup.freeze }
      end

      def lifecycle_projection
        RubyRouting::Projections::Replay.lifecycle(facts)
      end

      def active_unresolved_owners
        synchronize { @payouts.values.count { |state| !state.ownership.nil? } }
      end

      private

      def register_policy!(state, intent, policy)
        validate_policy_identity!(state, policy)
        return if state.policy_scope_key

        scope_key = policy.scope_key
        state.policy_scope_key = scope_key
        state.policy_fingerprint = policy.fingerprint
        state.policy_epoch = policy.epoch
        append_fact(
          :policy_registered,
          intent.id,
          policy_id: policy.id,
          policy_epoch: policy.epoch,
          policy_scope: policy.scope,
          policy_fingerprint: policy.fingerprint,
          definition: policy.to_h
        )
      end

      def validate_policy_identity!(state, policy)
        scope_key = policy.scope_key
        registered_fingerprint = @facts.reverse_each.find do |fact|
          fact.type == :policy_registered &&
            policy_scope_key_from_payload(fact.payload) == scope_key
        end&.payload&.fetch(:policy_fingerprint)
        if registered_fingerprint && registered_fingerprint != policy.fingerprint
          raise ArgumentError, "policy identity was reused with a different definition"
        end

        return unless state

        if state.policy_scope_key && state.policy_scope_key != scope_key
          raise ArgumentError, "payout is pinned to a different policy identity"
        end
        if state.policy_fingerprint && state.policy_fingerprint != policy.fingerprint
          raise ArgumentError, "payout is pinned to a different policy definition"
        end
      end

      def synchronize(&block)
        @mutex.synchronize(&block)
      end

      def normalized_provider_id(provider_id)
        normalized = provider_id.to_s.strip
        raise ArgumentError, "provider id must be non-empty" if normalized.empty?

        normalized
      end

      def policy_measure_exclusions(eligibility:, policy:, incoming_measure:)
        policy.measure_exclusions(eligibility.feasible_provider_ids, incoming_measure)
      end

      def policy_scope_key_from_payload(payload)
        [payload.fetch(:policy_id), payload.fetch(:policy_epoch), payload.fetch(:policy_scope)].map(&:to_s)
      end

      def allocation_snapshot_for(policy)
        key = policy.allocation_key
        unless @allocation_snapshots.key?(key)
          @allocation_snapshots[key] = RubyRouting::Routing::AllocationSnapshot.empty
        end

        @allocation_snapshots.fetch(key)
      end

      def commit_assignment(state, intent, policy, proposal, eligibility, allocation_snapshot)
        next_number = state.attempts.length + 1
        attempt_id = "#{intent.id}:attempt:#{next_number}".freeze
        operation_id = "#{intent.id}:operation:#{next_number}".freeze
        committed_at = current_time
        committed_proposal = proposal.with_identifiers(operation_id: operation_id, attempt_id: attempt_id)
        measure = policy.measure_for(intent.money)
        scope_key = policy.allocation_key
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
          capacity_reserved = reserve_capacity!(provider_opportunity, intent, operation_id)
        rescue StandardError
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
          allocation_deviation_cause: committed_proposal.allocation_decision.deviation_cause,
          allocation_tolerance: committed_proposal.allocation_decision.tolerance,
          soft_constraint_violations: eligibility.soft_violations.fetch(committed_proposal.provider_id, []),
          measure: measure,
          committed_at: committed_at,
          contract: contract_payload(contract)
        )
        append_fact(
          :allocation_committed,
          intent.id,
          policy_scope: scope_key,
          policy_epoch: policy.epoch,
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
        attempt = AttemptState.new(
          attempt_id: attempt_id,
          operation_id: operation_id,
          provider_id: committed_proposal.provider_id,
          role: committed_proposal.role,
          measure: measure,
          phase: :committed,
          contract: contract,
          committed_at: committed_at
        )
        state.attempts << attempt
        state.operations[operation_id] = attempt
        state.dispatch_pending[operation_id] = true
        if committed_proposal.role == :primary && policy.accounting_point == :primary_assignment
          @allocation_snapshots[scope_key] = allocation_snapshot.with_commit(committed_proposal.provider_id, measure)
        end
        DecisionCommit.new(
          proposal: committed_proposal,
          request: RubyRouting::ProviderOperationRequest.new(
            payout_id: intent.id,
            provider_id: committed_proposal.provider_id,
            operation_id: operation_id,
            attempt_id: attempt_id,
            money: intent.money
          ),
          payout: snapshot_for(state)
        )
      end

      def commit_resolution(state, intent, policy, proposal)
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
        DecisionCommit.new(
          proposal: proposal,
          request: RubyRouting::ProviderOperationRequest.new(
            payout_id: intent.id,
            provider_id: proposal.provider_id,
            operation_id: proposal.operation_id,
            attempt_id: proposal.attempt_id,
            money: intent.money
          ),
          payout: snapshot_for(state)
        )
      end

      def apply_current_outcome(state, attempt, outcome)
        if state.ownership && state.ownership.operation_id == attempt.operation_id
          state.dispatch_pending.delete(attempt.operation_id)
          state.last_outcome = outcome
          case outcome.status
          when :success
            set_operation_phase(state, attempt.operation_id, :settled)
            state.status = :success
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
          when :pending
            set_operation_phase(state, attempt.operation_id, :pending)
            state.status = :pending
          when :unknown
            set_operation_phase(state, attempt.operation_id, :unknown)
            state.status = :unknown
          when :safe_route_failure, :temporary_provider_failure
            if outcome.safe_to_release?
              set_operation_phase(state, attempt.operation_id, :released)
              state.status = outcome.status
              release_ownership(state, attempt, outcome)
            else
              set_operation_phase(state, attempt.operation_id, :unknown)
              state.status = :unknown
            end
          when :terminal_payout_failure
            set_operation_phase(state, attempt.operation_id, :terminated)
            state.status = :terminal_payout_failure
            release_ownership(state, attempt, outcome)
          end
        end
      end

      def release_ownership(state, attempt, outcome)
        state.dispatch_pending.delete(attempt.operation_id)
        release_capacity!(state, attempt)
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

      def set_operation_phase(state, operation_id, phase)
        attempt = state.operations.fetch(operation_id)
        return if attempt.phase == phase

        previous_phase = attempt.phase
        attempt.phase = phase
        append_fact(
          :operation_phase_changed,
          state.intent.id,
          operation_id: operation_id,
          attempt_id: attempt.attempt_id,
          provider_id: attempt.provider_id,
          from: previous_phase,
          to: phase,
          changed_at: current_time
        )
      end

      def capacity_available_for?(opportunity, intent)
        return false unless opportunity.capacity_available
        return true unless opportunity.capacity

        usage = @capacity_usage.fetch(opportunity.provider_id, CapacityUsage.new)
        opportunity.capacity.allows?(
          intent.money,
          used_slots: usage.slots,
          used_count: usage.count,
          used_amount_minor: usage.amount_minor
        )
      end

      def capacity_trace_for(opportunity)
        usage = @capacity_usage.fetch(opportunity.provider_id, CapacityUsage.new)
        {
          budget: opportunity.capacity&.to_h,
          used_slots: usage.slots,
          used_count: usage.count,
          used_amount_minor: usage.amount_minor
        }
      end

      def outcome_trace_for(outcome)
        return nil unless outcome

        {
          status: outcome.status,
          attribution: outcome.attribution,
          provider_reference: outcome.provider_reference,
          safe_to_release: outcome.safe_to_release?
        }
      end

      def expire_unresolved_operation!(state)
        return unless state.ownership
        return if state.status == :reconciliation_blocked

        attempt = state.operations.fetch(state.ownership.operation_id)
        now = current_time
        return if now.nil? || attempt.committed_at.nil?

        elapsed = now - attempt.committed_at
        operation_ttl = attempt.contract&.ttl_seconds
        deadline = attempt.contract&.deadline_seconds
        expired = (operation_ttl && elapsed >= operation_ttl) ||
          (deadline && state.created_at && now - state.created_at >= deadline)
        return unless expired

        state.status = :reconciliation_blocked
        state.dispatch_pending.delete(attempt.operation_id)
        set_operation_phase(state, attempt.operation_id, :reconciliation_blocked)
        append_fact(
          :reconciliation_blocked,
          state.intent.id,
          operation_id: attempt.operation_id,
          attempt_id: attempt.attempt_id,
          provider_id: attempt.provider_id,
          reason: :operation_contract_expired,
          elapsed: elapsed,
          blocked_at: now
        )
      end

      def health_available_for?(provider_id)
        @health_controller.snapshot(provider_id).exposed?
      end

      def record_health_from_observation(observation)
        outcome = observation.outcome
        signal = if outcome.provider_failure?
          :provider_failure
        elsif outcome.success? && outcome.attribution == :provider
          :operational_success
        elsif outcome.status == :unknown && outcome.attribution == :provider
          :timeout
        end
        return unless signal

        record_health_signal_locked(
          provider_id: observation.provider_id,
          signal: signal,
          attribution: outcome.attribution,
          source: observation.observation_id
        )
      end

      def record_health_signal_locked(provider_id:, signal:, attribution:, source: nil)
        release_exposure = source.nil?
        provider_id = normalized_provider_id(provider_id)
        before, after = @health_controller.observe(
          provider_id: provider_id,
          signal: signal,
          attribution: attribution,
          release_exposure: release_exposure
        )
        append_fact(
          :health_signal,
          "system:provider:#{provider_id}",
          provider_id: provider_id.to_s,
          signal: signal.to_sym,
          attribution: attribution.to_sym,
          source: source,
          release_exposure: release_exposure,
          policy: @health_controller.policy.to_h
        )
        if before.state != after.state
          append_fact(
            :health_state_changed,
            "system:provider:#{provider_id}",
            provider_id: provider_id.to_s,
            from: before.state,
            to: after.state
          )
        end
        after
      end

      def reserve_capacity!(opportunity, intent, operation_id)
        return false unless opportunity.capacity
        unless capacity_available_for?(opportunity, intent)
          raise ArgumentError, "provider capacity became unavailable before commit"
        end

        usage = @capacity_usage.fetch(opportunity.provider_id) { @capacity_usage[opportunity.provider_id] = CapacityUsage.new }
        usage.reserve(intent.money)
        @payouts.fetch(intent.id).capacity_reservations[operation_id] = [opportunity.provider_id, intent.money]
        append_fact(
          :capacity_reserved,
          intent.id,
          provider_id: opportunity.provider_id,
          operation_id: operation_id,
          amount: intent.money
        )
        true
      end

      def release_capacity!(state, attempt)
        reservation = state.capacity_reservations.delete(attempt.operation_id)
        return unless reservation

        provider_id, money = reservation
        usage = @capacity_usage.fetch(provider_id)
        usage.release(money)
        append_fact(
          :capacity_released,
          state.intent.id,
          provider_id: provider_id,
          operation_id: attempt.operation_id,
          amount: money
        )
      end

      def next_action_for(state)
        return :stop if %i[success terminal_payout_failure reversed].include?(state.status)
        return :reroute if state.status == :safe_route_failure && state.ownership.nil?
        return :reroute if state.status == :temporary_provider_failure && state.ownership.nil?
        return :wait if state.ownership

        :defer
      end

      def observation_applies?(attempt, observation)
        return false if %i[released settled terminated].include?(attempt.phase)

        if attempt.contract&.authoritative_sequence
          # Once a provider declares its sequence authoritative, an
          # unsequenced provider observation cannot safely establish or
          # replace lifecycle order. Transport classification is an exception:
          # it describes the initiating exchange, not a provider event.
          return true if observation.transport_kind && observation.sequence.nil?
          return false if observation.sequence.nil?
          return true if attempt.last_observation_sequence.nil?

          return observation.sequence > attempt.last_observation_sequence
        end

        previous = attempt.outcome
        return true if previous.nil?

        return false if previous.status == :unknown && observation.outcome.status == :pending

        true
      end

      def late_monetary_conflict?(attempt, observation)
        observation.outcome.success? && %i[released terminated].include?(attempt.phase)
      end

      def record_conflict(state, attempt, observation)
        conflict = RubyRouting::EconomicConflict.new(
          payout_id: state.intent.id,
          provider_id: attempt.provider_id,
          operation_id: attempt.operation_id,
          attempt_id: attempt.attempt_id,
          reason: :late_old_operation_success
        )
        state.conflicts << conflict
        append_fact(
          :economic_conflict,
          state.intent.id,
          provider_id: attempt.provider_id,
          operation_id: attempt.operation_id,
          attempt_id: attempt.attempt_id,
          observation_id: observation.observation_id,
          reason: conflict.reason
        )
      end

      def snapshot_for(state)
        PayoutSnapshot.new(
          intent: state.intent,
          status: state.status,
          ownership: state.ownership,
          last_outcome: state.last_outcome,
          attempts: state.attempts.map(&:to_snapshot),
          primary_provider_id: state.primary_provider_id,
          settlement_provider_id: state.settlement_provider_id,
          settlement_operation_id: state.settlement_operation_id,
          policy_epoch: state.policy_epoch,
          policy_scope_key: state.policy_scope_key,
          policy_fingerprint: state.policy_fingerprint,
          provider_interaction_count: state.provider_interaction_count,
          resolution_interaction_count: state.resolution_interaction_count,
          conflicts: state.conflicts,
          reversals: state.reversals,
          revision: @revision,
          created_at: state.created_at
        )
      end

      def same_intent?(left, right)
        left.id == right.id && left.money == right.money && left.recipient == right.recipient && left.context == right.context
      end

      def observation_signature(observation)
        [
          observation.payout_id,
          observation.provider_id,
          observation.operation_id,
          observation.attempt_id,
          observation.provider_reference,
          observation.outcome.status,
          observation.outcome.attribution,
          observation.outcome.provider_reference,
          observation.outcome.message,
          observation.outcome.safe_to_release?,
          observation.sequence,
          observation.observed_at,
          observation.transport_kind
        ].freeze
      end

      def contract_payload(contract)
        {
          provider_id: contract.provider_id,
          idempotent_retry: contract.idempotent_retry,
          status_lookup: contract.status_lookup,
          idempotency_key: contract.idempotency_key,
          ttl_seconds: contract.ttl_seconds,
          deadline_seconds: contract.deadline_seconds,
          version: contract.version,
          authoritative_sequence: contract.authoritative_sequence
        }.freeze
      end

      def append_fact(type, payout_id, payload)
        @sequence += 1
        @revision += 1
        @facts << RubyRouting::Fact.new(
          sequence: @sequence,
          type: type,
          fact_id: "fact:#{@sequence}",
          payout_id: payout_id,
          payload: payload
        )
      end

      class PayoutState
        attr_accessor :status, :ownership, :last_outcome, :primary_provider_id,
                      :settlement_provider_id, :settlement_operation_id, :policy_epoch,
                      :provider_interaction_count, :policy_scope_key, :policy_fingerprint,
                      :created_at, :resolution_interaction_count
        attr_reader :intent, :attempts, :operations, :seen_observations,
                    :conflicts, :reversals,
                    :capacity_reservations, :health_exposure_reservations,
                    :dispatch_pending

        def initialize(intent)
          @intent = intent
          @status = :new
          @ownership = nil
          @last_outcome = nil
          @attempts = []
          @operations = {}
          @seen_observations = {}
          @conflicts = []
          @provider_interaction_count = 0
          @resolution_interaction_count = 0
          @primary_provider_id = nil
          @settlement_provider_id = nil
          @settlement_operation_id = nil
          @reversals = []
          @capacity_reservations = {}
          @health_exposure_reservations = {}
          @dispatch_pending = {}
          @policy_epoch = nil
          @policy_scope_key = nil
          @policy_fingerprint = nil
          @created_at = nil
        end
      end

      class AttemptState
        attr_reader :attempt_id, :operation_id, :provider_id, :role, :measure, :contract,
                    :committed_at
        attr_accessor :outcome, :phase, :last_observation_sequence

        def initialize(attempt_id:, operation_id:, provider_id:, role:, measure:, phase:, contract:,
                       committed_at: nil)
          @attempt_id = attempt_id
          @operation_id = operation_id
          @provider_id = provider_id
          @role = role
          @measure = measure
          @phase = phase.to_sym
          @contract = contract
          @committed_at = committed_at
          @last_observation_sequence = nil
          @outcome = nil
        end

        def to_snapshot
          AttemptSnapshot.new(
            attempt_id: attempt_id,
            operation_id: operation_id,
            provider_id: provider_id,
            role: role,
            outcome: outcome,
            measure: measure,
            phase: phase,
            contract: contract,
            last_observation_sequence: last_observation_sequence,
            committed_at: committed_at
          )
        end
      end

      class CapacityUsage
        attr_reader :slots, :count, :amount_minor

        def initialize
          @slots = 0
          @count = 0
          @amount_minor = 0
        end

        def reserve(money)
          @slots += 1
          @count += 1
          @amount_minor += money.amount_minor
        end

        def release(money)
          @slots -= 1
          @count -= 1
          @amount_minor -= money.amount_minor
          raise ArgumentError, "capacity usage underflow" if @slots.negative? || @count.negative? || @amount_minor.negative?
        end
      end
    end
  end
end
