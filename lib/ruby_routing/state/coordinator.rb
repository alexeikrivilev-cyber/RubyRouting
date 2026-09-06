# frozen_string_literal: true

module RubyRouting
  module State
    class Coordinator
      def initialize(opportunities: [])
        @mutex = Thread::Mutex.new
        @payouts = {}
        @provider_opportunities = {}
        @allocation_snapshots = {}
        @allocation_cohort_keys = {}
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
          @payouts[intent.id] = state
          append_fact(:intent_registered, intent.id, money: intent.money, recipient: intent.recipient)
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
          @provider_opportunities = normalized.to_h { |opportunity| [opportunity.provider_id, opportunity] }
        end
        nil
      end

      def set_provider_availability(provider_id, available:, capacity_available: nil)
        synchronize do
          current = @provider_opportunities.fetch(provider_id.to_s) do
            raise ArgumentError, "unknown provider opportunity"
          end
          replacement = RubyRouting::ProviderOpportunity.new(
            provider_id: current.provider_id,
            functional_eligible: current.functional_eligible,
            available: available,
            capacity_available: capacity_available.nil? ? current.capacity_available : capacity_available,
            capabilities: current.capabilities,
            exclusion_reason: current.exclusion_reason
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
      def prepare_and_commit_decision(intent:, policy:)
        unless intent.is_a?(RubyRouting::PayoutIntent)
          raise ArgumentError, "intent must be PayoutIntent"
        end
        unless policy.is_a?(RubyRouting::RoutingPolicy)
          raise ArgumentError, "policy must be RoutingPolicy"
        end

        synchronize do
          state = @payouts[intent.id]
          unless state
            state = PayoutState.new(intent)
            @payouts[intent.id] = state
            append_fact(:intent_registered, intent.id, money: intent.money, recipient: intent.recipient)
          end
          unless same_intent?(state.intent, intent)
            raise ArgumentError, "payout id is already registered with different intent"
          end

          opportunities = @provider_opportunities.values.sort_by(&:provider_id)
          eligibility = RubyRouting::Routing::Eligibility.evaluate(opportunities)
          allocation_snapshot = allocation_snapshot_for(policy, eligibility.feasible_provider_ids)
          proposal = RubyRouting::Routing::DecisionEngine.decide(
            intent: intent,
            policy: policy,
            opportunities: opportunities,
            allocation_snapshot: allocation_snapshot,
            payout_state: snapshot_for(state)
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
              reasons: proposal.reasons
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
          unless state.operations.key?(operation_id)
            raise ArgumentError, "unknown committed operation"
          end
          if decision_commit.proposal.action == :retry_same || !state.attempt_started.key?(operation_id)
            state.attempt_started[operation_id] = true
            state.provider_interaction_count += 1
            append_fact(
              :attempt_started,
              state.intent.id,
              attempt_id: decision_commit.proposal.attempt_id,
              operation_id: operation_id,
              provider_id: decision_commit.proposal.provider_id,
              action: decision_commit.proposal.action
            )
          end
          snapshot_for(state)
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

          previous_outcome = state.operation_outcomes[observation.operation_id]
          current_operation = state.ownership && state.ownership.operation_id == observation.operation_id
          applies = !!(current_operation &&
            (previous_outcome.nil? || outcome_rank(observation.outcome) >= outcome_rank(previous_outcome)))
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
            applied: applies
          )
          return ObservationApplication.new(
            payout: snapshot_for(state),
            next_action: next_action_for(state),
            duplicate: false
          ) unless applies

          state.operation_outcomes[observation.operation_id] = observation.outcome
          attempt.outcome = observation.outcome
          apply_current_outcome(state, attempt, observation.outcome)
          ObservationApplication.new(
            payout: snapshot_for(state),
            next_action: next_action_for(state),
            duplicate: false
          )
        end
      end

      def payout_snapshot(payout_id)
        synchronize { snapshot_for(@payouts.fetch(payout_id.to_s)) }
      end

      def allocation_snapshot(policy:)
        synchronize do
          @allocation_snapshots.fetch(
            policy.scope_key,
            RubyRouting::Routing::AllocationSnapshot.empty(revision: @revision)
          )
        end
      end

      def facts
        synchronize { @facts.dup.freeze }
      end

      def active_unresolved_owners
        synchronize { @payouts.values.count { |state| !state.ownership.nil? } }
      end

      private

      def synchronize(&block)
        @mutex.synchronize(&block)
      end

      def allocation_snapshot_for(policy, feasible_provider_ids)
        key = policy.scope_key
        cohort = feasible_provider_ids.map(&:to_s).sort.freeze
        if @allocation_cohort_keys[key] != cohort
          @allocation_cohort_keys[key] = cohort
          @allocation_snapshots[key] = RubyRouting::Routing::AllocationSnapshot.empty(revision: @revision)
        end

        @allocation_snapshots.fetch(key)
      end

      def commit_assignment(state, intent, policy, proposal, eligibility, allocation_snapshot)
        next_number = state.attempts.length + 1
        attempt_id = "#{intent.id}:attempt:#{next_number}".freeze
        operation_id = "#{intent.id}:operation:#{next_number}".freeze
        committed_proposal = proposal.with_identifiers(operation_id: operation_id, attempt_id: attempt_id)
        measure = policy.measure_for(intent.money)
        scope_key = policy.scope_key

        append_fact(
          :opportunity_evaluated,
          intent.id,
          policy_epoch: policy.epoch,
          opportunities: eligibility.opportunities.select(&:functional_eligible).map(&:provider_id),
          feasible_provider_ids: eligibility.feasible_provider_ids,
          exclusions: eligibility.exclusions
        )
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
          snapshot_revision: allocation_snapshot.revision
        )
        append_fact(
          :allocation_committed,
          intent.id,
          policy_scope: scope_key,
          policy_epoch: policy.epoch,
          provider_id: committed_proposal.provider_id,
          measure: measure,
          role: committed_proposal.role
        )
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
          attempt_id: ownership.attempt_id
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
          measure: measure
        )
        state.attempts << attempt
        state.operations[operation_id] = attempt
        @allocation_snapshots[scope_key] = allocation_snapshot.with_commit(committed_proposal.provider_id, measure)
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
          reasons: proposal.reasons
        )
        if proposal.action == :resolve
          state.provider_interaction_count += 1
          append_fact(
            :attempt_started,
            intent.id,
            attempt_id: proposal.attempt_id,
            operation_id: proposal.operation_id,
            provider_id: proposal.provider_id,
            action: proposal.action
          )
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
          state.last_outcome = outcome
          case outcome.status
          when :success
            state.status = :success
            state.settlement_provider_id = attempt.provider_id
            release_ownership(state, attempt, outcome)
            append_fact(
              :settlement_recorded,
              state.intent.id,
              provider_id: attempt.provider_id,
              operation_id: attempt.operation_id,
              outcome: outcome.status,
              measure: attempt.measure
            )
          when :pending
            state.status = :pending
          when :unknown
            state.status = :unknown
          when :safe_route_failure, :temporary_provider_failure
            if outcome.safe_to_release?
              state.status = outcome.status
              release_ownership(state, attempt, outcome)
            else
              state.status = :unknown
            end
          when :terminal_payout_failure
            state.status = :terminal_payout_failure
            release_ownership(state, attempt, outcome)
          end
        end
      end

      def release_ownership(state, attempt, outcome)
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

      def next_action_for(state)
        return :stop if %i[success terminal_payout_failure].include?(state.status)
        return :reroute if state.status == :safe_route_failure && state.ownership.nil?
        return :reroute if state.status == :temporary_provider_failure && state.ownership.nil?
        return :wait if state.ownership

        :defer
      end

      def outcome_rank(outcome)
        {
          pending: 1,
          unknown: 2,
          safe_route_failure: 3,
          temporary_provider_failure: 3,
          terminal_payout_failure: 4,
          success: 5
        }.fetch(outcome.status)
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
          policy_epoch: state.policy_epoch,
          provider_interaction_count: state.provider_interaction_count,
          revision: @revision
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
          observation.outcome.safe_to_release?
        ].freeze
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
                      :settlement_provider_id, :policy_epoch, :provider_interaction_count
        attr_reader :intent, :attempts, :operations, :seen_observations,
                    :operation_outcomes, :attempt_started

        def initialize(intent)
          @intent = intent
          @status = :new
          @ownership = nil
          @last_outcome = nil
          @attempts = []
          @operations = {}
          @seen_observations = {}
          @operation_outcomes = {}
          @attempt_started = {}
          @provider_interaction_count = 0
          @primary_provider_id = nil
          @settlement_provider_id = nil
          @policy_epoch = nil
        end
      end

      class AttemptState
        attr_reader :attempt_id, :operation_id, :provider_id, :role, :measure
        attr_accessor :outcome

        def initialize(attempt_id:, operation_id:, provider_id:, role:, measure:)
          @attempt_id = attempt_id
          @operation_id = operation_id
          @provider_id = provider_id
          @role = role
          @measure = measure
          @outcome = nil
        end

        def to_snapshot
          AttemptSnapshot.new(
            attempt_id: attempt_id,
            operation_id: operation_id,
            provider_id: provider_id,
            role: role,
            outcome: outcome,
            measure: measure
          )
        end
      end
    end
  end
end
