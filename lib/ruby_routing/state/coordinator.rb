# frozen_string_literal: true

module RubyRouting
  module State
    class Coordinator
      ProviderInteractionToken = Data.define(
        :payout_id,
        :operation_id,
        :generation,
        # Durable interaction count, not process-local generation. It gives
        # generated transport observations a restart-safe exchange ordinal.
        :interaction_index,
        :money_moving,
        :economically_decisive
      )

      def self.from_facts(facts:, opportunities: [], health_policy: nil, quality_policy: nil, clock: nil, journal: nil)
        new(
          opportunities: opportunities,
          health_policy: health_policy,
          quality_policy: quality_policy,
          clock: clock,
          journal: journal,
          facts: facts
        )
      end

      def initialize(opportunities: [], health_policy: nil, quality_policy: nil, clock: nil, journal: nil, facts: nil)
        @mutex = Thread::Mutex.new
        @clock = clock || RubyRouting::State::SystemClock.new
        if journal && !journal.respond_to?(:facts)
          raise ArgumentError, "durable journal must expose facts for restart-safe coordinator recovery"
        end
        @payouts = {}
        @provider_catalog = RubyRouting::State::ProviderCatalogLedger.new
        @admission_ledger = RubyRouting::State::AdmissionLedger.new(clock: @clock)
        @allocation_ledger = RubyRouting::State::AllocationLedger.new
        @lifecycle_ledger = RubyRouting::State::LifecycleLedger.new
        @observation_ledger = RubyRouting::State::ObservationLedger.new
        @restored_observations = {}
        @pending_economic_conflicts = {}
        @restored_health_signal_sources = {}
        @restored_quality_signal_sources = {}
        @restored_transport_sources = {}
        @pending_health_transitions = {}
        # Process-local only: durable attempt phase describes crash recovery,
        # while this marker closes the live interval after token consumption
        # and before the provider observation is accepted.
        @provider_interaction_in_flight = {}
        # A provider interaction can unwind in the live process after the
        # durable attempt started but before its observation is accepted. That
        # provenance must not be mistaken for a fresh-process restart merely
        # because the guard ended. Values retain the local failure provenance;
        # the map is intentionally not durable, so a new Coordinator remains
        # the genuine restart boundary and may rediscover the exact pinned
        # operation from facts.
        @live_interaction_failures = {}
        @provider_interaction_generation = 0
        @policies = {}
        source_facts = facts || (journal.respond_to?(:facts) ? journal.facts : [])
        @fact_store = RubyRouting::State::FactStore.new(journal: journal, facts: source_facts)
        source_facts = @fact_store.facts
        persisted_health_policy = RubyRouting::Collection.to_array(source_facts, "facts").reverse.find do |fact|
          fact.type == :provider_opportunity_registered && fact.payload.is_a?(Hash) && fact.payload[:health_policy]
        end&.payload&.fetch(:health_policy)
        persisted_quality_policy = RubyRouting::Collection.to_array(source_facts, "facts").reverse.find do |fact|
          fact.type == :provider_opportunity_registered && fact.payload.is_a?(Hash) && fact.payload[:quality_policy]
        end&.payload&.fetch(:quality_policy)
        configured_health_policy = health_policy || health_policy_from_payload(persisted_health_policy)
        configured_quality_policy = quality_policy || quality_policy_from_payload(persisted_quality_policy)
        @health_controller = RubyRouting::Routing::HealthController.new(policy: configured_health_policy)
        @quality_controller = RubyRouting::Routing::QualityController.new(policy: configured_quality_policy)
        initialize_restored_state_validator!
        initialize_provider_catalog_restorer!
        initialize_admission_fact_restorer!
        initialize_allocation_fact_restorer!
        initialize_lifecycle_fact_restorer!
        initialize_observation_fact_restorer!
        initialize_operation_fact_restorer!
        initialize_provider_evidence_fact_restorer!
        initialize_financial_fact_restorer!
        initialize_payout_fact_restorer!
        initialize_opportunity_evaluation_fact_restorer!
        initialize_decision_trace_validator!
        initialize_decision_fact_restorer!
        initialize_working_state_restorer!
        if @fact_store.facts.empty?
          replace_provider_opportunities(opportunities)
        else
          restore_from_facts!(@fact_store.facts, opportunities: opportunities)
        end
        initialize_routing_components!
      end

      def register_intent(intent)
        unless intent.is_a?(RubyRouting::PayoutIntent)
          raise ArgumentError, "intent must be PayoutIntent"
        end

        atomic_synchronize do
          existing = @payouts[intent.id]
          if existing
            unless same_intent?(existing.intent, intent)
              raise ArgumentError, "payout id is already registered with different intent"
            end
            return snapshot_for(existing)
          end

          state = PayoutState.new(intent)
          state.created_at = current_time
          state.created_monotonic_at = current_monotonic
          @payouts[intent.id] = state
          append_fact(
            :intent_registered,
            intent.id,
            money: intent.money,
            recipient: intent.recipient,
            context: intent.context,
            routing_context: intent.routing_context.to_h,
            created_at: state.created_at,
            created_monotonic_at: state.created_monotonic_at
          )
          snapshot_for(state)
        end
      end

      def replace_provider_opportunities(opportunities)
        normalized = RubyRouting::Collection.to_array(opportunities, "opportunities")
        unless normalized.all? { |opportunity| opportunity.is_a?(RubyRouting::ProviderOpportunity) }
          raise ArgumentError, "opportunities must contain ProviderOpportunity values"
        end

        ids = normalized.map(&:provider_id)
        raise ArgumentError, "provider opportunities must have unique ids" unless ids.uniq.length == ids.length
        atomic_synchronize do
          removed_provider_ids = @provider_catalog.provider_ids - normalized.map(&:provider_id)
          removed_provider_ids.sort.each do |provider_id|
            fact = append_fact(
              :provider_opportunity_removed,
              "system:provider:#{provider_id}",
              provider_id: provider_id,
              removed_at: current_time
            )
            @provider_catalog.remove(provider_id, sequence: fact.sequence)
          end
          normalized.each do |opportunity|
            fact = append_fact(
              :provider_opportunity_registered,
              "system:provider:#{opportunity.provider_id}",
              provider_id: opportunity.provider_id,
              capacity: opportunity.capacity&.to_h,
              throughput: opportunity.throughput&.to_h,
              health_policy: @health_controller.policy.to_h,
              quality_policy: @quality_controller.policy.to_h,
              definition: opportunity.to_h
            )
            @provider_catalog.register(opportunity, sequence: fact.sequence)
          end
          normalized.each do |opportunity|
            @admission_ledger.ensure_provider(opportunity.provider_id)
          end
        end
        nil
      end

      def set_provider_availability(provider_id, available:, capacity_available: nil)
        atomic_synchronize do
          current = @provider_catalog.fetch(normalized_provider_id(provider_id)) do
            raise ArgumentError, "unknown provider opportunity"
          end
          replacement = current.with_runtime(
            available: available,
            capacity_available: capacity_available.nil? ? current.capacity_available : capacity_available,
            throughput_available: current.throughput_available
          )
          @provider_catalog.replace_current(replacement)
          append_fact(
            :provider_runtime_changed,
            "system:provider:#{current.provider_id}",
            provider_id: current.provider_id,
            available: replacement.available,
            capacity_available: replacement.capacity_available,
            enabled: replacement.enabled,
            health_available: replacement.health_available,
            throughput_available: replacement.throughput_available
          )
        end
        nil
      end

      def provider_opportunities
        synchronize { @provider_catalog.current }
      end

      # The returned commit is complete before the caller is allowed to invoke
      # a provider. No provider object is called from this method or its lock.
      def prepare_and_commit_decision(intent:, policy:, available_provider_ids: nil, provider_opportunities: nil,
                                      configuration_revision: nil)
        unless intent.is_a?(RubyRouting::PayoutIntent)
          raise ArgumentError, "intent must be PayoutIntent"
        end
        unless policy.is_a?(RubyRouting::RoutingPolicy)
          raise ArgumentError, "policy must be RoutingPolicy"
        end

        # Validate command-local policy/input values before pinning any policy
        # identity or registering the intent. A malformed volume currency or
        # adapter-id list must not leave a half-pinned payout behind.
        unless policy.applies_to?(intent)
          raise ArgumentError, "policy selector or currency does not match payout route"
        end
        incoming_measure = policy.measure_for(intent.money)
        normalized_available_provider_ids = if available_provider_ids.nil?
          nil
        else
          RubyRouting::Collection.to_array(available_provider_ids, "available_provider_ids")
            .map { |provider_id| normalized_provider_id(provider_id) }
            .uniq
            .freeze
        end
        normalized_provider_opportunities = normalize_provider_opportunities_for_evaluation(provider_opportunities)
        normalized_configuration_revision = normalize_configuration_revision(configuration_revision)

        atomic_synchronize do
          effective_provider_opportunities = if normalized_provider_opportunities.nil?
            nil
          else
            validate_provider_configuration_current!(normalized_provider_opportunities)
            provider_opportunities_with_current_runtime(normalized_provider_opportunities)
          end
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
            state.created_monotonic_at = current_monotonic
            @payouts[intent.id] = state
            append_fact(
              :intent_registered,
              intent.id,
              money: intent.money,
              recipient: intent.recipient,
              context: intent.context,
              routing_context: intent.routing_context.to_h,
              created_at: state.created_at,
              created_monotonic_at: state.created_monotonic_at
            )
          end
          state.created_at ||= current_time
          state.created_monotonic_at ||= current_monotonic
          register_policy!(state, intent, policy)
          if state.ownership.nil? && !%i[success terminal_payout_failure reversed].include?(state.status)
            if money_moving_interaction_in_flight?(intent.id)
              proposal = DecisionProposal.new(
                action: :defer,
                role: :recovery,
                policy_epoch: policy.epoch,
                reasons: ["a live money-moving provider interaction must finish before fresh assignment"],
                reason_codes: [:live_money_moving_interaction]
              )
              return DecisionCommit.new(proposal: proposal, request: nil, payout: snapshot_for(state))
            end
            if economically_decisive_interaction_in_flight?(intent.id)
              proposal = DecisionProposal.new(
                action: :defer,
                role: :recovery,
                policy_epoch: policy.epoch,
                reasons: ["a live economically-decisive provider interaction must finish before fresh assignment"],
                reason_codes: [:live_economically_decisive_interaction]
              )
              return DecisionCommit.new(proposal: proposal, request: nil, payout: snapshot_for(state))
            end
          end
          expire_unresolved_operation!(state)
          schedule_due = if state.recovery_schedule
            state.recovery_schedule.due?(
              as_of: current_time,
              as_of_monotonic: current_monotonic
            )
          end
          if state.recovery_schedule && !schedule_due
            proposal = DecisionProposal.new(
              action: :defer,
              role: :resolution,
              policy_epoch: policy.epoch,
              reasons: [
                "#{state.recovery_schedule.action} is not due until " \
                  "#{state.recovery_schedule.next_action_at.iso8601}"
              ],
              reason_codes: [:recovery_not_due]
            )
            return DecisionCommit.new(proposal: proposal, request: nil, payout: snapshot_for(state))
          end

          # Adapter availability is an operational admission fact, not a
          # functional-opportunity fact. Keep every catalog opportunity in the
          # eligibility/allocation cohort and make providers without a live
          # adapter unavailable for this decision only.
          evaluation = @decision_evaluator.evaluate(
            intent: intent,
            policy: policy,
            payout_state: snapshot_for(state),
            available_provider_ids: normalized_available_provider_ids,
            provider_opportunities: effective_provider_opportunities
          )
          eligibility = evaluation.eligibility
          allocation_exclusions = evaluation.allocation_exclusions
          runtime_feasibility = evaluation.runtime_feasibility
          allocation_snapshot = evaluation.allocation_snapshot
          allocation_key = evaluation.allocation_key
          evaluated_at = evaluation.evaluated_at
          evaluated_monotonic_at = evaluation.evaluated_monotonic_at
          append_fact(
            :opportunity_evaluated,
            intent.id,
            policy_id: policy.id,
            policy_epoch: policy.epoch,
            policy_scope: policy.scope,
            policy_fingerprint: policy.fingerprint,
            configuration_revision: normalized_configuration_revision,
            measure_kind: policy.measure,
            currency: policy.currency,
            opportunities: eligibility.opportunity_provider_ids,
            functional_provider_ids: eligibility.functional_provider_ids,
            feasible_provider_ids: eligibility.feasible_provider_ids,
            exclusions: eligibility.exclusions,
            exclusion_codes: eligibility.exclusion_codes,
            allocation_exclusions: allocation_exclusions,
            static_policy_feasibility: policy.static_feasibility,
            runtime_feasibility: runtime_feasibility.to_h,
            soft_violations: eligibility.soft_violations,
            allocation_snapshot: {
              revision: allocation_snapshot.revision,
              measures: allocation_snapshot.measures,
              key: allocation_key
            },
            allocation_key: allocation_key,
            capacity: eligibility.opportunities.to_h do |opportunity|
              [opportunity.provider_id, capacity_trace_for(
                opportunity,
                as_of: evaluated_at,
                as_of_monotonic: evaluated_monotonic_at
              )]
            end,
            throughput: eligibility.opportunities.to_h do |opportunity|
              [opportunity.provider_id, opportunity.throughput&.to_h]
            end,
            health: eligibility.opportunities.to_h do |opportunity|
              [
                opportunity.provider_id,
                @health_controller.snapshot(
                  opportunity.provider_id,
                  routing_context: state.intent.routing_context
                ).to_h
              ]
            end,
            quality: evaluation.quality_snapshots.transform_values(&:to_h),
            ranking: policy.ranking.to_h,
            health_policy: @health_controller.policy.to_h,
            available_provider_ids: normalized_available_provider_ids,
            previous_outcome: outcome_trace_for(state.last_outcome),
            evaluated_at: evaluated_at,
            evaluated_monotonic_at: evaluated_monotonic_at
          )
          proposal = evaluation.proposal

          case proposal.action
          when :assign
            commit_assignment(
              state,
              intent,
              policy,
              proposal,
              eligibility,
              allocation_snapshot,
              configuration_revision: normalized_configuration_revision
            )
          when :resolve, :retry_same
            commit_resolution(
              state,
              intent,
              policy,
              proposal,
              configuration_revision: normalized_configuration_revision
            )
          else
            append_fact(
              :decision_committed,
              intent.id,
              action: proposal.action,
              role: proposal.role,
              policy_epoch: policy.epoch,
              policy_id: policy.id,
              policy_scope: policy.scope,
              configuration_revision: normalized_configuration_revision,
              measure_kind: policy.measure,
              currency: policy.currency,
              allocation_key: allocation_key,
              provider_id: proposal.provider_id,
               reasons: proposal.reasons,
               reason_codes: proposal.reason_codes,
               runtime_feasibility: proposal.runtime_feasibility&.to_h,
               allocation_deviation_cause: proposal.deviation_cause,
               allocation_deviation_recoverability: proposal.deviation_recoverability,
               measure: proposal.reason_codes.include?(:no_safe_route) ? incoming_measure : nil,
               available_provider_ids: normalized_available_provider_ids
            )
            state.status = :deferred if proposal.action == :defer && state.ownership.nil?
            DecisionCommit.new(proposal: proposal, request: nil, payout: snapshot_for(state))
          end
        end
      end

      def mark_attempt_started(decision_commit)
        unless decision_commit.is_a?(DecisionCommit) &&
               decision_commit.proposal.is_a?(RubyRouting::DecisionProposal) &&
               decision_commit.proposal.assignment?
          raise ArgumentError, "an assignment decision commit is required"
        end

        atomic_synchronize do
          payout_id = decision_commit.payout.respond_to?(:id) ? decision_commit.payout.id : nil
          raise ArgumentError, "decision commit payout is required" if payout_id.nil?

          state = @payouts.fetch(payout_id)
          operation_id = decision_commit.proposal.operation_id
          attempt = state.operations[operation_id]
          unless attempt
            raise ArgumentError, "unknown committed operation"
          end
          validate_start_commit!(
            decision_commit,
            state: state,
            attempt: attempt,
            expected_pending: true
          )
          return false unless validate_start_commit_pending?(
            decision_commit,
            state: state,
            attempt: attempt,
            expected_pending: true
          )
          clear_live_interaction_failure!(state, attempt)
          state.dispatch_pending.delete(operation_id)
          state.provider_execution_failure = nil

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
          mark_provider_interaction_in_flight!(
            payout_id,
            operation_id,
            money_moving: true,
            interaction_index: state.provider_interaction_count
          )
        end
      end

      # Rebuild the next safe provider interaction after a process restart.
      # The original operation identity is reused; no new economic ownership
      # or allocation is created. A dispatch that was already started before
      # the crash is resumed through status lookup or idempotent retry only.
      def resume_operation(payout_id, provider_opportunities: nil, configuration_revision: nil)
        canonical_payout_id = normalized_payout_id(payout_id)
        normalized_provider_opportunities = normalize_provider_opportunities_for_evaluation(provider_opportunities)
        normalized_configuration_revision = normalize_configuration_revision(configuration_revision)
        atomic_synchronize do
          validate_provider_configuration_current!(normalized_provider_opportunities) unless normalized_provider_opportunities.nil?
          state = @payouts.fetch(canonical_payout_id) do
            raise ArgumentError, "unknown payout"
          end
          ownership = state.ownership
          return nil unless ownership
          attempt = state.operations.fetch(ownership.operation_id)
          return nil if provider_interaction_in_flight?(canonical_payout_id, attempt.operation_id)

          # Resume is itself a state-changing entry point. Expiry must be
          # evaluated before rebuilding a dispatch proposal, otherwise a
          # process restart can bypass the operation contract TTL/deadline.
          expire_unresolved_operation!(state)

          return nil if state.recovery_schedule && !state.recovery_schedule.due?(
            as_of: current_time,
            as_of_monotonic: current_monotonic
          )

          pending = state.dispatch_pending[attempt.operation_id]
          if pending != true
            return nil unless same_provider_recovery_action_for(state, attempt)
            if (provider_failure_due_at = provider_execution_failure_due_at_for(state))
              return nil if provider_failure_due_at > current_time
            end
          end
          proposal = restart_proposal_for(state, attempt, pending)
          return nil unless proposal

          if proposal.reason_codes.include?(:restart_recovery)
            append_fact(
              :decision_committed,
              state.intent.id,
              action: proposal.action,
              provider_id: proposal.provider_id,
              operation_id: proposal.operation_id,
              attempt_id: proposal.attempt_id,
              role: proposal.role,
              policy_epoch: proposal.policy_epoch,
              configuration_revision: normalized_configuration_revision,
              reasons: proposal.reasons,
              reason_codes: proposal.reason_codes
            )
            if proposal.action == :resolve
              set_operation_phase(state, attempt.operation_id, :resolving)
              state.dispatch_pending[attempt.operation_id] = :resolution
            else
              set_operation_phase(state, attempt.operation_id, :dispatching)
              state.dispatch_pending[attempt.operation_id] = true
            end
            state.operation_actions[attempt.operation_id] = proposal.action
          end

          decision_commit_for_attempt(state, proposal)
        end
      end

      alias resume_committed_dispatch resume_operation

      def mark_resolution_started(decision_commit)
        unless decision_commit.is_a?(DecisionCommit) &&
               decision_commit.proposal.is_a?(RubyRouting::DecisionProposal) &&
               decision_commit.proposal.resolution?
          raise ArgumentError, "a resolution decision commit is required"
        end

        atomic_synchronize do
          payout_id = decision_commit.payout.respond_to?(:id) ? decision_commit.payout.id : nil
          raise ArgumentError, "decision commit payout is required" if payout_id.nil?

          state = @payouts.fetch(payout_id)
          operation_id = decision_commit.proposal.operation_id
          attempt = state.operations[operation_id]
          unless attempt
            raise ArgumentError, "unknown committed operation"
          end
          validate_start_commit!(
            decision_commit,
            state: state,
            attempt: attempt,
            expected_pending: :resolution
          )
          return false unless validate_start_commit_pending?(
            decision_commit,
            state: state,
            attempt: attempt,
            expected_pending: :resolution
          )
          clear_live_interaction_failure!(state, attempt)
          state.dispatch_pending.delete(operation_id)
          state.provider_execution_failure = nil

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
          mark_provider_interaction_in_flight!(
            payout_id,
            operation_id,
            money_moving: false,
            economically_decisive: true,
            interaction_index: state.provider_interaction_count
          )
        end
      end

      # A raw adapter exception is not a durable provider observation. Release
      # the process-local guard and retain a durable, payload-free provenance
      # marker so due-work can discover the same pinned operation after the
      # caller receives the typed failure or the process restarts.
      def provider_interaction_failed(interaction_token:)
        atomic_synchronize do
          return nil unless provider_interaction_current?(interaction_token)

          state = @payouts.fetch(interaction_token.payout_id) do
            raise RubyRouting::State::DurableCorruptionError,
              "provider failure references unknown payout"
          end
          attempt = state.operations.fetch(interaction_token.operation_id) do
            raise RubyRouting::State::DurableCorruptionError,
              "provider failure references unknown operation"
          end
          action = state.operation_actions.fetch(interaction_token.operation_id) do
            raise RubyRouting::State::DurableCorruptionError,
              "provider failure references operation without action"
          end
          expected_phase = action == :resolve ? :resolving : :dispatching
          unless state.ownership&.operation_id == attempt.operation_id &&
                 state.ownership.provider_id == attempt.provider_id &&
                 state.ownership.attempt_id == attempt.attempt_id &&
                 attempt.phase == expected_phase
            raise RubyRouting::State::DurableCorruptionError,
              "provider failure does not match current operation"
          end

          release_provider_interaction!(interaction_token)
          failure = {
            provider_id: attempt.provider_id,
            operation_id: attempt.operation_id,
            attempt_id: attempt.attempt_id,
            action: action,
            phase: attempt.phase,
            interaction_index: interaction_token.interaction_index,
            failed_at: current_time
          }.freeze
          state.provider_execution_failure = failure
          append_fact(
            :provider_execution_failed,
            state.intent.id,
            **failure
          )
        end
        nil
      end

      # A live-process interaction failure must release the process-local
      # guard without becoming restart-derived recovery work. The marker is
      # deliberately process-local; a fresh Coordinator is the crash boundary.
      def provider_interaction_ended(interaction_token:, failure_provenance: nil)
        synchronize do
          if failure_provenance
            unless %i[post_return fatal].include?(failure_provenance)
              raise ArgumentError, "unsupported live interaction failure provenance"
            end
            if provider_interaction_current?(interaction_token)
              @live_interaction_failures[interaction_identity_for(interaction_token)] = failure_provenance
            end
          end
          release_provider_interaction!(interaction_token)
        end
        nil
      end

      def apply_observation(observation, interaction_token: nil)
        unless observation.is_a?(RubyRouting::ProviderObservation)
          raise ArgumentError, "observation must be ProviderObservation"
        end

        atomic_synchronize do
          state = @payouts.fetch(observation.payout_id) do
            raise ArgumentError, "observation references unknown payout"
          end
          attempt = state.operations.fetch(observation.operation_id) do
            raise ArgumentError, "observation references unknown operation"
          end
          unless attempt.provider_id == observation.provider_id && attempt.attempt_id == observation.attempt_id
            raise ArgumentError, "observation operation linkage does not match"
          end
          owning_completion = provider_interaction_current?(interaction_token)
          causal_hold = !owning_completion && causal_release_hold?(state, attempt, observation)
          observation_decision = @observation_ledger.observe(
            seen_observations: state.seen_observations,
            current_operation_id: state.ownership&.operation_id,
            attempt: attempt,
            observation: observation,
            causal_hold: causal_hold,
            owning_completion: owning_completion
          )
          clear_live_interaction_failure!(state, attempt)
          if observation_decision.duplicate?
            if observation_decision.causal_completion?
              append_fact(
                :provider_interaction_completed,
                state.intent.id,
                observation_id: observation.observation_id,
                operation_id: observation.operation_id,
                attempt_id: observation.attempt_id,
                provider_id: observation.provider_id
              )
              attempt.outcome = observation.outcome
              attempt.last_observation_sequence = observation.sequence unless observation.sequence.nil?
              state.last_outcome = observation.outcome
              record_quality_from_observation(
                observation,
                context: state.intent.routing_context,
                currency: state.intent.money.currency,
                observed_at: observation.observed_at || current_time
              )
              apply_current_outcome(state, attempt, observation.outcome)
              state.recovery_schedule = nil
            end
            release_provider_interaction!(interaction_token)
            return ObservationApplication.new(
              payout: snapshot_for(state),
              next_action: next_action_for(state),
              duplicate: true
            )
          end

          applies = observation_decision.applies?
          conflict = observation_decision.conflict?
          observed_at = observation.observed_at || current_time
          recovery_schedule = if applies
            recovery_schedule_for(state, attempt, observation.outcome)
          end
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
            interaction_duration_seconds: observation.interaction_duration_seconds,
            applied: applies,
            conflict: conflict,
            health_evidence: observation_decision.health_evidence?,
            causal_hold: observation_decision.causal_hold?,
            recovery_schedule: recovery_schedule&.to_h
          )
          if observation.transport_kind
            append_fact(
              :transport_classified,
              state.intent.id,
              observation_id: observation.observation_id,
              source_payout_id: observation.payout_id,
              operation_id: observation.operation_id,
              attempt_id: observation.attempt_id,
              provider_id: observation.provider_id,
              kind: observation.transport_kind
            )
          end
          if conflict
            record_conflict(
              state,
              attempt,
              observation,
              reason: observation_decision.causal_contradiction? ? :causal_release_contradiction : nil
            )
          end
          record_health_from_observation(
            observation,
            routing_context: state.intent.routing_context
          ) if observation_decision.health_evidence?
          record_quality_from_observation(
            observation,
            context: state.intent.routing_context,
            currency: state.intent.money.currency,
            observed_at: observed_at
          ) if applies
          release_provider_interaction!(interaction_token)
          return ObservationApplication.new(
            payout: snapshot_for(state),
            next_action: next_action_for(state),
            duplicate: false,
            conflict: conflict
          ) unless applies

          attempt.outcome = observation.outcome
          attempt.last_observation_sequence = observation.sequence unless observation.sequence.nil?
          apply_current_outcome(state, attempt, observation.outcome)
          state.recovery_schedule = recovery_schedule if state.ownership && recovery_schedule
          state.recovery_schedule = nil unless state.ownership && recovery_schedule
          ObservationApplication.new(
            payout: snapshot_for(state),
            next_action: next_action_for(state),
            duplicate: false,
            conflict: conflict
          )
        end
      end

      def payout_snapshot(payout_id)
        canonical_payout_id = normalized_payout_id(payout_id)
        synchronize { snapshot_for(@payouts.fetch(canonical_payout_id)) }
      end

      # Returns only work that is safe to expose as currently actionable. The
      # caller supplies wall time so an external runner can poll
      # deterministically; no queue or background thread is part of the core.
      def due_recovery_work(as_of: current_time, limit: nil)
        unless as_of.is_a?(Time)
          raise ArgumentError, "as_of must be a Time"
        end
        unless limit.nil? || (limit.is_a?(Integer) && !limit.is_a?(TrueClass) && limit >= 0)
          raise ArgumentError, "limit must be a non-negative Integer or nil"
        end

        normalized_as_of = as_of.utc.freeze
        synchronize do
          work = []
          @payouts.each_value do |state|
            if state.ownership && operation_contract_expired_at?(state, normalized_as_of)
              ownership = state.ownership
              work << RubyRouting::RecoveryWorkItem.new(
                payout_id: state.intent.id,
                action: :reconcile,
                provider_id: ownership.provider_id,
                operation_id: ownership.operation_id,
                attempt_id: ownership.attempt_id,
                due_at: nil,
                reason_code: :operation_contract_expired,
                status: :reconciliation_blocked
              )
            elsif (work_item = provider_execution_failure_work_for(state, as_of: normalized_as_of))
              work << work_item
            elsif state.recovery_schedule&.due?(as_of: normalized_as_of)
              schedule = state.recovery_schedule
              work << RubyRouting::RecoveryWorkItem.new(
                payout_id: state.intent.id,
                action: schedule.action,
                provider_id: schedule.provider_id,
                operation_id: schedule.operation_id,
                attempt_id: schedule.attempt_id,
                due_at: schedule.next_action_at,
                reason_code: schedule.reason_code,
                status: state.status
              )
            elsif (work_item = restart_recovery_work_for(state, as_of: normalized_as_of))
              work << work_item
            elsif state.status == :reconciliation_blocked &&
                  state.ownership &&
                  reconciliation_blocked_visible_at?(state, normalized_as_of)
              work << RubyRouting::RecoveryWorkItem.new(
                payout_id: state.intent.id,
                action: :reconcile,
                provider_id: state.ownership.provider_id,
                operation_id: state.ownership.operation_id,
                attempt_id: state.ownership.attempt_id,
                due_at: nil,
                reason_code: :reconciliation_blocked,
                status: state.status
              )
            end
          end
          work.sort_by!(&:payout_id)
          work = work.first(limit) unless limit.nil?
          work.freeze
        end
      end

      alias due_work due_recovery_work

      def record_reversal(payout_id:, reversal_id:, provider_id:, operation_id:, amount:, reason: :returned)
        canonical_payout_id = normalized_payout_id(payout_id)
        canonical_provider_id = normalized_provider_id(provider_id)
        canonical_operation_id = normalized_operation_id(operation_id)
        canonical_reversal_id = RubyRouting::Identity.normalize(reversal_id, "reversal id")
        atomic_synchronize do
          state = @payouts.fetch(canonical_payout_id) do
            raise ArgumentError, "reversal references unknown payout"
          end
          unless %i[success reversed].include?(state.status)
            raise ArgumentError, "reversal requires a settled payout"
          end
          is_settlement_match = state.settlement_provider_id == canonical_provider_id &&
                                state.settlement_operation_id == canonical_operation_id
          is_conflict_match = state.conflicts.any? do |conflict|
            conflict.provider_id == canonical_provider_id && conflict.operation_id == canonical_operation_id
          end
          unless is_settlement_match || is_conflict_match
            raise ArgumentError, "reversal settlement linkage does not match"
          end
          unless amount.is_a?(RubyRouting::Money) && amount.currency == state.intent.money.currency
            raise ArgumentError, "reversal currency does not match payout"
          end

          existing = state.reversals.find { |reversal| reversal.reversal_id == canonical_reversal_id }
          if existing
            unless existing.provider_id == canonical_provider_id &&
                   existing.operation_id == canonical_operation_id &&
                   existing.amount == amount && existing.reason.to_s == reason.to_s
              raise ArgumentError, "reversal id was reused with different payload"
            end
            return snapshot_for(state)
          end

          operation_reversals = state.reversals.select { |reversal| reversal.operation_id == canonical_operation_id }
          reversed_minor = operation_reversals.sum { |reversal| reversal.amount.amount_minor }
          if reversed_minor + amount.amount_minor > state.intent.money.amount_minor
            raise ArgumentError, "reversals cannot exceed settled payout amount"
          end

          reversal = RubyRouting::SettlementReversal.new(
            reversal_id: reversal_id,
            payout_id: canonical_payout_id,
            provider_id: canonical_provider_id,
            operation_id: canonical_operation_id,
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
          @allocation_ledger.snapshot(
            policy: policy,
            opportunity_provider_ids: @provider_catalog.provider_ids
          )
        end
      end

      def allocation_projection
        RubyRouting::Projections::Replay.allocation(facts)
      end

      def capacity_snapshot(provider_id)
        synchronize do
          provider = @provider_catalog.fetch(normalized_provider_id(provider_id)) do
            raise ArgumentError, "unknown provider opportunity"
          end
          @admission_ledger.capacity_snapshot(provider.provider_id, budget: provider.capacity)
        end
      end

      def capacity_projection
        RubyRouting::Projections::Replay.capacity(facts)
      end

      def throughput_snapshot(provider_id)
        synchronize do
          provider = @provider_catalog.fetch(normalized_provider_id(provider_id)) do
            raise ArgumentError, "unknown provider opportunity"
          end
          @admission_ledger.throughput_snapshot(provider.provider_id, budget: provider.throughput)
        end
      end

      def throughput_projection
        RubyRouting::Projections::Replay.throughput(facts, as_of: current_time)
      end

      def policy_for(payout_id)
        canonical_payout_id = normalized_payout_id(payout_id)
        synchronize do
          state = @payouts.fetch(canonical_payout_id) do
            raise ArgumentError, "unknown payout"
          end
          return nil unless state.policy_scope_key

          @policies.fetch(state.policy_scope_key) do
            raise RubyRouting::State::DurableCorruptionError,
              "missing policy definition for #{state.policy_scope_key.inspect}"
          end
        end
      end

      def health_snapshot(provider_id, routing_context: nil)
        synchronize do
          @health_controller.snapshot(provider_id, routing_context: routing_context)
        end
      end

      def health_projection(routing_context: nil)
        RubyRouting::Projections::Replay.health(facts, routing_context: routing_context)
      end

      def quality_snapshot(provider_id, context: nil, context_key: nil, routing_context: nil, currency: nil, as_of: current_time)
        synchronize do
          @quality_controller.snapshot(
            provider_id,
            context: context,
            context_key: context_key,
            routing_context: routing_context,
            currency: currency,
            as_of: as_of
          )
        end
      end

      def quality_projection(as_of: current_time, context: nil, context_key: nil,
                            routing_context: nil, currency: nil)
        RubyRouting::Projections::Replay.quality(
          facts,
          as_of: as_of,
          context: context,
          context_key: context_key,
          routing_context: routing_context,
          currency: currency
        )
      end

      def record_health_signal(provider_id:, signal:, attribution: :unknown)
        atomic_synchronize do
          record_health_signal_locked(
            provider_id: provider_id,
            signal: signal,
            attribution: attribution
          )
        end
      end

      def current_time
        value = if @clock.respond_to?(:now)
          @clock.now
        elsif @clock.respond_to?(:call)
          @clock.call
        else
          nil
        end
        return nil if value.nil?
        unless value.is_a?(Time)
          raise ArgumentError, "clock must return Time or nil"
        end

        value.utc.freeze
      end

      def current_monotonic
        unless @clock.respond_to?(:monotonic)
          raise ArgumentError, "clock must provide exact monotonic time"
        end

        value = @clock.monotonic
        unless value.is_a?(Integer) || value.is_a?(Rational)
          raise ArgumentError, "clock monotonic value must be exact"
        end

        value
      rescue NoMethodError, TypeError
        raise ArgumentError, "clock must provide exact monotonic time"
      end

      def monotonic_reference_for(value)
        unless value.is_a?(Time) && @clock.respond_to?(:monotonic_reference_for)
          raise ArgumentError, "clock must provide monotonic references for Time values"
        end

        reference = @clock.monotonic_reference_for(value.utc)
        unless reference.is_a?(Integer) || reference.is_a?(Rational)
          raise ArgumentError, "clock monotonic reference must be exact"
        end

        reference
      rescue NoMethodError, TypeError
        raise ArgumentError, "clock must provide exact monotonic references"
      end

      def facts
        synchronize { @fact_store.facts }
      end

      def audit_facts(payout_id: nil, type: nil)
        synchronize do
          @fact_store.query(payout_id: payout_id, type: type)
        end
      end

      def audit_fact_page(payout_id: nil, type: nil, offset:, limit:)
        synchronize do
          @fact_store.page(
            payout_id: payout_id,
            type: type,
            offset: offset,
            limit: limit
          )
        end
      end

      def lifecycle_projection
        RubyRouting::Projections::Replay.lifecycle(facts)
      end

      def active_unresolved_owners
        synchronize { @payouts.values.count { |state| !state.ownership.nil? } }
      end

      private

      def restore_from_facts!(facts, opportunities:)
        @working_state_restorer.restore!(facts: facts, opportunities: opportunities)
      end

      def restart_proposal_for(state, attempt, pending)
        action = if pending == true
          attempt.phase == :committed ? :assign : :retry_same
        elsif pending == :resolution
          same_provider_recovery_action_for(state, attempt)
        elsif pending.nil? && %i[dispatching resolving].include?(attempt.phase)
          same_provider_recovery_action_for(state, attempt)
        end
        return nil unless action

        DecisionProposal.new(
          action: action,
          provider_id: attempt.provider_id,
          operation_id: attempt.operation_id,
          attempt_id: attempt.attempt_id,
          role: action == :assign ? attempt.role : :resolution,
          policy_epoch: state.policy_epoch || "restored",
          reasons: [restart_reason_for(action, pending)],
          reason_codes: [pending.nil? ? :restart_recovery : :restart_dispatch]
        )
      end

      def provider_interaction_in_flight?(payout_id, operation_id)
        @provider_interaction_in_flight.key?([payout_id, operation_id])
      end

      def provider_interaction_current?(interaction_token)
        return false unless interaction_token.is_a?(ProviderInteractionToken)

        @provider_interaction_in_flight[[interaction_token.payout_id, interaction_token.operation_id]]&.equal?(interaction_token)
      end

      def money_moving_interaction_in_flight?(payout_id)
        @provider_interaction_in_flight.any? do |(live_payout_id, _operation_id), token|
          live_payout_id == payout_id && token.money_moving
        end
      end

      def economically_decisive_interaction_in_flight?(payout_id)
        @provider_interaction_in_flight.any? do |(live_payout_id, _operation_id), token|
          live_payout_id == payout_id && token.economically_decisive
        end
      end

      def causal_release_hold?(state, attempt, observation)
        state.ownership&.operation_id == attempt.operation_id &&
          (provider_interaction_in_flight?(state.intent.id, attempt.operation_id) ||
           (observation.outcome.provider_failure? &&
            %i[committed dispatching resolving pending unknown reconciliation_blocked].include?(attempt.phase))) &&
          observation.outcome.safe_to_release? &&
          !observation.outcome.terminal_payout_failure?
      end

      def mark_provider_interaction_in_flight!(payout_id, operation_id, money_moving:, economically_decisive: money_moving,
                                               interaction_index: nil)
        @provider_interaction_generation += 1
        token = ProviderInteractionToken.new(
          payout_id: payout_id,
          operation_id: operation_id,
          generation: @provider_interaction_generation,
          interaction_index: interaction_index,
          money_moving: money_moving,
          economically_decisive: economically_decisive
        )
        @provider_interaction_in_flight[[payout_id, operation_id]] = token
        token
      end

      def release_provider_interaction!(interaction_token)
        return false unless interaction_token.is_a?(ProviderInteractionToken)

        interaction_key = [interaction_token.payout_id, interaction_token.operation_id]
        current = @provider_interaction_in_flight[interaction_key]
        return false unless current&.equal?(interaction_token)

        @provider_interaction_in_flight.delete(interaction_key)
        true
      end

      def restart_reason_for(action, pending)
        return "resumed committed provider operation" if action == :assign
        return "resumed pending provider resolution" if pending == :resolution

        action == :resolve ? "reconciled provider operation after restart" :
          "retried idempotent provider operation after restart"
      end

      def decision_commit_for_attempt(state, proposal)
        attempt = state.operations.fetch(proposal.operation_id)
        DecisionCommit.new(
          proposal: proposal,
          request: RubyRouting::ProviderOperationRequest.from_intent(
            intent: state.intent,
            provider_id: proposal.provider_id,
            operation_id: proposal.operation_id,
            attempt_id: proposal.attempt_id,
            contract: attempt.contract
          ),
          payout: snapshot_for(state)
        )
      end

      def restore_fact!(fact)
        validate_durable_payload_shape!(fact)
        validate_economic_conflict_order!(fact)
        validate_health_transition_order!(fact)
        return if @provider_catalog_restorer.apply(fact)
        return if @admission_fact_restorer.apply(fact)
        return if @allocation_fact_restorer.apply(fact)
        return if @lifecycle_fact_restorer.apply(fact)
        return if @observation_fact_restorer.apply(fact)
        return if @operation_fact_restorer.apply(fact)
        return if @provider_evidence_fact_restorer.apply(fact)
        return if @financial_fact_restorer.apply(fact)
        return if @payout_fact_restorer.apply(fact)
        return if @opportunity_evaluation_fact_restorer.apply(fact)
        return if @decision_fact_restorer.apply(fact)

        case fact.type
        when :payout_state_changed
          raise RubyRouting::State::DurableCorruptionError,
            "unsupported legacy payout_state_changed fact for #{fact.payout_id}"
        else
          raise RubyRouting::State::DurableCorruptionError,
            "unsupported durable fact type #{fact.type.inspect}"
        end
      end

      def durable_decision_identifier!(value, label)
        unless value.is_a?(String) && !value.empty? && value == value.strip
          raise RubyRouting::State::DurableCorruptionError,
            "decision #{label} must be a canonical non-empty String"
        end

        value
      end

      def validate_durable_payload_shape!(fact)
        payload = fact.payload
        unless payload.is_a?(Hash)
          raise RubyRouting::State::DurableCorruptionError,
            "fact #{fact.sequence} payload must be a Hash"
        end

        if payload.key?(:configuration_revision)
          revision = payload[:configuration_revision]
          unless revision.nil? || (revision.is_a?(Integer) && revision >= 0)
            raise RubyRouting::State::DurableCorruptionError,
              "fact #{fact.sequence} configuration revision must be a non-negative Integer"
          end
        end

        if payload.key?(:provider_id)
          provider_id = payload[:provider_id]
          unless provider_id.nil?
            normalized = provider_id.to_s.strip
            unless provider_id.is_a?(String) && provider_id == normalized && !normalized.empty?
              raise RubyRouting::State::DurableCorruptionError,
                "fact #{fact.sequence} provider id must be a canonical string"
            end
          end
        end

        payload.each do |key, value|
          if key.to_s.end_with?("_monotonic_at")
            next if value.nil? || value.is_a?(Integer) || value.is_a?(Rational)

            raise RubyRouting::State::DurableCorruptionError,
              "fact #{fact.sequence} monotonic timestamp #{key} must be exact or nil"
          end
          next unless key.to_s.end_with?("_at")
          next if value.nil? || value.is_a?(Time)

          raise RubyRouting::State::DurableCorruptionError,
            "fact #{fact.sequence} timestamp #{key} must be Time or nil"
        end
      end

      def payout_state_for!(payout_id)
        @payouts.fetch(RubyRouting::Identity.normalize(payout_id, "payout id")) do
          raise RubyRouting::State::DurableCorruptionError, "fact references unknown payout #{payout_id}"
        end
      end

      def provider_opportunity_from_payload(payload)
        definition = payload[:definition] || payload["definition"]
        allowed = %i[
          provider_id functional_eligible available capacity_available capabilities
          exclusion_reason supported_currencies minimum_amount_minor maximum_amount_minor
          required_context_labels enabled capacity health_available throughput throughput_available
          route_capabilities
        ]
        values = RubyRouting::HashKeys.symbolize(
          definition || payload,
          allowed,
          "provider opportunity",
          strict: !definition.nil?
        )
        values[:provider_id] ||= payload.fetch(:provider_id)
        values[:capabilities] = provider_capabilities_from(values[:capabilities])
        values[:route_capabilities] = provider_route_capabilities_from(values[:route_capabilities])
        values[:capacity] = capacity_budget_from(values[:capacity])
        values[:throughput] = throughput_budget_from(values[:throughput])
        RubyRouting::ProviderOpportunity.new(**values.select { |key, _value| allowed.include?(key) })
      rescue KeyError, ArgumentError, TypeError => error
        raise RubyRouting::State::DurableCorruptionError, "invalid provider opportunity history: #{error.message}"
      end

      def provider_route_capabilities_from(value)
        RubyRouting::ProviderRouteCapabilities.from(value)
      end

      def provider_capabilities_from(value)
        return RubyRouting::ProviderCapabilities.new if value.nil?
        return value if value.is_a?(RubyRouting::ProviderCapabilities)

        values = RubyRouting::HashKeys.symbolize(
          value,
          %i[idempotent_retry status_lookup ttl_seconds deadline_seconds version authoritative_sequence],
          "provider capabilities"
        )
        RubyRouting::ProviderCapabilities.new(**values)
      end

      def capacity_budget_from(value)
        return nil if value.nil?
        return value if value.is_a?(RubyRouting::CapacityBudget)

        values = RubyRouting::HashKeys.symbolize(
          value,
          %i[max_slots max_count max_amount_minor currency],
          "capacity budget"
        )
        RubyRouting::CapacityBudget.new(**values)
      end

      def throughput_budget_from(value)
        return nil if value.nil?
        return value if value.is_a?(RubyRouting::ThroughputBudget)

        values = RubyRouting::HashKeys.symbolize(
          value,
          %i[max_operations window_seconds],
          "throughput budget"
        )
        RubyRouting::ThroughputBudget.new(**values)
      end

      def validate_provider_system_fact!(fact, provider_id, require_registered: true)
        expected_payout_id = "system:provider:#{provider_id}"
        unless fact.payout_id == expected_payout_id
          raise RubyRouting::State::DurableCorruptionError,
            "provider fact identity does not match #{provider_id}"
        end
        return unless require_registered
        if require_registered == :historical
          return if provider_registered_in_history?(provider_id, before_sequence: fact.sequence)
        elsif require_registered == :current
          return if provider_current_in_history?(provider_id, before_sequence: fact.sequence)
        else
          return if @provider_catalog.key?(provider_id)
        end

        raise RubyRouting::State::DurableCorruptionError,
          "provider fact references unknown provider #{provider_id}"
      end

      def validate_health_transition_order!(fact)
        return if @pending_health_transitions.empty?
        routing_context = canonical_health_context(fact.payload[:routing_context])
        transition_key = routing_context ?
          [fact.payload[:provider_id], routing_context.to_h].freeze : fact.payload[:provider_id]
        return if fact.type == :health_state_changed &&
          @pending_health_transitions.key?(transition_key)

        raise RubyRouting::State::DurableCorruptionError,
          "health state transition is missing after preceding signal"
      end

      def validate_economic_conflict_order!(fact)
        return if @pending_economic_conflicts.empty?

        source_key = [fact.payout_id, fact.payload[:observation_id] || fact.payload[:source]].freeze
        return if %i[economic_conflict transport_classified].include?(fact.type) &&
          @pending_economic_conflicts.key?(source_key)

        raise RubyRouting::State::DurableCorruptionError,
          "economic conflict fact is missing after conflicting observation"
      end

      def provider_registered_in_history?(provider_id, before_sequence:)
        @provider_catalog.registered_before?(provider_id, sequence: before_sequence)
      end

      def validate_provider_registered_before_fact!(fact, provider_id)
        return if provider_current_in_history?(provider_id, before_sequence: fact.sequence)

        raise RubyRouting::State::DurableCorruptionError,
          "provider-dependent fact precedes provider registration for #{provider_id}"
      end

      def provider_current_in_history?(provider_id, before_sequence:)
        @provider_catalog.current_before?(provider_id, sequence: before_sequence)
      end

      def policy_from_definition(definition)
        values = RubyRouting::HashKeys.symbolize(
          definition,
          %i[
            id epoch measure targets currency scope accounting_point window max_attempts tolerance
            minimum_measures maximum_measures minimum_shares maximum_shares recovery recovery_objective ranking
            hard_constraints soft_constraints selector
          ],
          "policy definition"
        )
        if values[:recovery].is_a?(Hash)
          values[:recovery] = RecoveryPolicy.new(**RubyRouting::HashKeys.symbolize(
            values[:recovery],
            %i[
              max_operations max_switches max_resolution_interactions ttl_seconds deadline_seconds
              initial_delay_seconds backoff_seconds max_delay_seconds
            ],
            "recovery policy"
          ))
        end
        if values[:recovery_objective].is_a?(Hash)
          values[:recovery_objective] = RecoveryObjective.new(**RubyRouting::HashKeys.symbolize(
            values[:recovery_objective],
            %i[mode],
            "recovery objective"
          ))
        end
        if values[:ranking].is_a?(Hash)
          values[:ranking] = RankingPolicy.new(**RubyRouting::HashKeys.symbolize(
            values[:ranking],
            %i[priority_by_provider cost_minor_by_provider latency_ms_by_provider],
            "ranking policy"
          ))
        end
        %i[hard_constraints soft_constraints].each do |key|
          next unless values[key].is_a?(Hash)

          values[key] = RubyRouting::HashKeys.symbolize(
            values[key],
            %i[
              allowed_provider_ids excluded_provider_ids required_context_labels
              minimum_amount_minor maximum_amount_minor
            ],
            "#{key}"
          )
        end
        RubyRouting::RoutingPolicy.new(**values)
      rescue ArgumentError, KeyError, TypeError => error
        raise RubyRouting::State::DurableCorruptionError, "invalid policy history: #{error.message}"
      end

      def health_policy_from_payload(payload)
        return RubyRouting::Routing::HealthPolicy.new if payload.nil?

        values = RubyRouting::HashKeys.symbolize(
          payload,
          %i[degrade_after quarantine_after recover_after probe_limit latency_threshold_ms],
          "health policy"
        )
        RubyRouting::Routing::HealthPolicy.new(**values)
      rescue ArgumentError, KeyError, TypeError => error
        raise RubyRouting::State::DurableCorruptionError, "invalid health policy history: #{error.message}"
      end

      def quality_policy_from_payload(payload)
        return RubyRouting::Routing::QualityPolicy.new if payload.nil?

        values = RubyRouting::HashKeys.symbolize(
          payload,
          %i[minimum_samples prior_successes prior_failures evidence_window max_evidence_age_seconds route_minimum_samples],
          "quality policy"
        )
        RubyRouting::Routing::QualityPolicy.new(**values)
      rescue ArgumentError, KeyError, TypeError => error
        raise RubyRouting::State::DurableCorruptionError, "invalid quality policy history: #{error.message}"
      end

      def contract_from_payload(payload)
        return nil unless payload

        values = RubyRouting::HashKeys.symbolize(
          payload,
          %i[
            provider_id idempotent_retry status_lookup idempotency_key ttl_seconds deadline_seconds
            version authoritative_sequence
          ],
          "provider operation contract"
        )
        RubyRouting::ProviderOperationContract.new(**values)
      end

      def register_policy!(state, intent, policy)
        validate_policy_identity!(state, policy)
        return if state.policy_scope_key

        scope_key = policy.scope_key
        state.policy_scope_key = scope_key
        state.policy_fingerprint = policy.fingerprint
        state.policy_epoch = policy.epoch
        @policies[scope_key] = policy
        append_fact(
          :policy_registered,
          intent.id,
          policy_id: policy.id,
          policy_epoch: policy.epoch,
          policy_scope: policy.scope,
          policy_fingerprint: policy.fingerprint,
          definition: policy.to_h,
          static_feasibility: policy.static_feasibility
        )
      end

      def validate_policy_identity!(state, policy)
        scope_key = policy.scope_key
        registered_fingerprint = @fact_store.facts.reverse_each.find do |fact|
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

      def initialize_working_state_restorer!
        @working_state_restorer ||= RubyRouting::State::WorkingStateRestorer.new(
          prepare_catalog: -> { @provider_catalog = RubyRouting::State::ProviderCatalogLedger.new },
          current_catalog: -> { @provider_catalog },
          restore_fact: ->(fact) { restore_fact!(fact) },
          validate_state: -> { @restored_state_validator.validate! }
        )
      end

      def initialize_restored_state_validator!
        @restored_state_validator ||= RubyRouting::State::RestoredStateValidator.new(
          payouts: -> { @payouts },
          pending_health_transitions: -> { @pending_health_transitions },
          pending_economic_conflicts: -> { @pending_economic_conflicts }
        )
      end

      def initialize_provider_catalog_restorer!
        @provider_catalog_restorer = RubyRouting::State::ProviderCatalogRestorer.new(
          provider_catalog: -> { @provider_catalog },
          admission_ledger: -> { @admission_ledger },
          quality_controller: -> { @quality_controller },
          health_policy: -> { @health_controller.policy },
          quality_policy: -> { @quality_controller.policy },
          provider_identity: ->(payload, key) { durable_provider_identity_value!(payload, key) },
          validate_provider_system_fact: lambda do |fact, provider_id, require_registered:|
            validate_provider_system_fact!(fact, provider_id, require_registered: require_registered)
          end,
          opportunity_from_payload: ->(payload) { provider_opportunity_from_payload(payload) }
        )
      end

      def initialize_admission_fact_restorer!
        @admission_fact_restorer ||= RubyRouting::State::AdmissionFactRestorer.new(
          admission_ledger: -> { @admission_ledger },
          provider_catalog: -> { @provider_catalog },
          payout_state: ->(payout_id) { payout_state_for!(payout_id) },
          provider_identity: ->(payload, key) { durable_provider_identity_value!(payload, key) },
          operation_identity: ->(payload, key) { durable_operation_identity_value!(payload, key) },
          validate_provider_registered_before_fact: lambda do |fact, provider_id|
            validate_provider_registered_before_fact!(fact, provider_id)
          end,
          validate_operation_release_order: lambda do |state, attempt, operation_id, label|
            @restored_state_validator.validate_operation_release_order(state, attempt, operation_id, label)
          end,
          durable_monotonic: ->(payload, key) { durable_monotonic_value!(payload, key) },
          monotonic_reference: ->(value) { monotonic_reference_for(value) }
        )
      end

      def initialize_allocation_fact_restorer!
        @allocation_fact_restorer ||= RubyRouting::State::AllocationFactRestorer.new(
          allocation_ledger: -> { @allocation_ledger },
          payout_state: ->(payout_id) { payout_state_for!(payout_id) },
          policy_for_scope: lambda do |scope_key|
            @policies.fetch(scope_key) do
              raise RubyRouting::State::DurableCorruptionError,
                "allocation references missing policy"
            end
          end,
          policy_identity: ->(payload, key) { durable_policy_identity_value!(payload, key) },
          operation_identity: ->(payload, key) { durable_operation_identity_value!(payload, key) },
          provider_identity: ->(payload, key) { durable_provider_identity_value!(payload, key) },
          enum_value: ->(payload, key, allowed, label) { durable_enum_value!(payload, key, allowed, label) },
          collection_to_array: ->(value, label) { RubyRouting::Collection.to_array(value, label) },
          validate_provider_registered_before_fact: lambda do |fact, provider_id|
            validate_provider_registered_before_fact!(fact, provider_id)
          end
        )
      end

      def initialize_lifecycle_fact_restorer!
        @lifecycle_fact_restorer ||= RubyRouting::State::LifecycleFactRestorer.new(
          lifecycle_ledger: -> { @lifecycle_ledger },
          payout_state: ->(payout_id) { payout_state_for!(payout_id) },
          operation_identity: ->(payload, key) { durable_operation_identity_value!(payload, key) },
          provider_identity: ->(payload, key) { durable_provider_identity_value!(payload, key) },
          enum_value: ->(payload, key, allowed, label) { durable_enum_value!(payload, key, allowed, label) },
          validate_operation_release_order: lambda do |state, attempt, operation_id, label|
            @restored_state_validator.validate_operation_release_order(state, attempt, operation_id, label)
          end
        )
      end

      def initialize_observation_fact_restorer!
        @observation_fact_restorer ||= RubyRouting::State::ObservationFactRestorer.new(
          observation_ledger: -> { @observation_ledger },
          lifecycle_ledger: -> { @lifecycle_ledger },
          payout_state: ->(payout_id) { payout_state_for!(payout_id) },
          restored_observations: -> { @restored_observations },
          pending_economic_conflicts: -> { @pending_economic_conflicts },
          operation_identity: ->(payload, key) { durable_operation_identity_value!(payload, key) },
          provider_identity: ->(payload, key) { durable_provider_identity_value!(payload, key) },
          policy_for_state: lambda do |state|
            @policies.fetch(state.policy_scope_key) do
              raise RubyRouting::State::DurableCorruptionError,
                "recovery schedule references missing policy"
            end
          end,
          monotonic_reference: ->(value) { monotonic_reference_for(value) }
        )
      end

      def initialize_operation_fact_restorer!
        @operation_fact_restorer ||= RubyRouting::State::OperationFactRestorer.new(
          payout_state: ->(payout_id) { payout_state_for!(payout_id) },
          health_controller: -> { @health_controller },
          provider_identity: ->(payload, key) { durable_provider_identity_value!(payload, key) },
          operation_identity: ->(payload, key) { durable_operation_identity_value!(payload, key) },
          enum_value: ->(payload, key, allowed, label) { durable_enum_value!(payload, key, allowed, label) },
          durable_monotonic: ->(payload, key) { durable_monotonic_value!(payload, key) },
          monotonic_reference: ->(value) { monotonic_reference_for(value) },
          elapsed_seconds: ->(later, earlier) { elapsed_seconds(later, earlier) },
          reconciliation_expired_at: ->(state, attempt, blocked_at) {
            reconciliation_expired_at?(state, attempt, blocked_at)
          },
          validate_operation_release_order: lambda do |state, attempt, operation_id, label|
            @restored_state_validator.validate_operation_release_order(state, attempt, operation_id, label)
          end
        )
      end

      def initialize_provider_evidence_fact_restorer!
        @provider_evidence_fact_restorer ||= RubyRouting::State::ProviderEvidenceFactRestorer.new(
          health_controller: -> { @health_controller },
          quality_controller: -> { @quality_controller },
          payout_state: ->(payout_id) { payout_state_for!(payout_id) },
          restored_observations: -> { @restored_observations },
          restored_transport_sources: -> { @restored_transport_sources },
          restored_health_signal_sources: -> { @restored_health_signal_sources },
          restored_quality_signal_sources: -> { @restored_quality_signal_sources },
          pending_health_transitions: -> { @pending_health_transitions },
          provider_identity: ->(payload, key) { durable_provider_identity_value!(payload, key) },
          operation_identity: ->(payload, key) { durable_operation_identity_value!(payload, key) },
          enum_value: ->(payload, key, allowed, label) { durable_enum_value!(payload, key, allowed, label) },
          validate_provider_system_fact: lambda do |fact, provider_id, require_registered:|
            validate_provider_system_fact!(fact, provider_id, require_registered: require_registered)
          end
        )
      end

      def initialize_financial_fact_restorer!
        @financial_fact_restorer ||= RubyRouting::State::FinancialFactRestorer.new(
          payout_state: ->(payout_id) { payout_state_for!(payout_id) },
          pending_economic_conflicts: -> { @pending_economic_conflicts },
          operation_identity: ->(payload, key) { durable_operation_identity_value!(payload, key) },
          provider_identity: ->(payload, key) { durable_provider_identity_value!(payload, key) },
          enum_value: ->(payload, key, allowed, label) { durable_enum_value!(payload, key, allowed, label) },
          optional_operation_identity: lambda do |payload, key, default:|
            durable_optional_operation_identity_value!(payload, key, default: default)
          end
        )
      end

      def initialize_payout_fact_restorer!
        @payout_fact_restorer ||= RubyRouting::State::PayoutFactRestorer.new(
          payouts: -> { @payouts },
          policies: -> { @policies },
          payout_state_factory: ->(intent) { PayoutState.new(intent) },
          payout_state: ->(payout_id) { payout_state_for!(payout_id) },
          same_intent: ->(left, right) { same_intent?(left, right) },
          policy_from_definition: ->(definition) { policy_from_definition(definition) },
          policy_identity: ->(payload, key) { durable_policy_identity_value!(payload, key) },
          monotonic_value: ->(payload, key) { durable_monotonic_value!(payload, key) },
          monotonic_reference: ->(value) { monotonic_reference_for(value) }
        )
      end

      def initialize_opportunity_evaluation_fact_restorer!
        @opportunity_evaluation_fact_restorer ||= RubyRouting::State::OpportunityEvaluationFactRestorer.new(
          provider_catalog: -> { @provider_catalog },
          admission_ledger: -> { @admission_ledger },
          allocation_ledger: -> { @allocation_ledger },
          health_controller: -> { @health_controller },
          quality_controller: -> { @quality_controller },
          policies: -> { @policies },
          payout_state: ->(payout_id) { payout_state_for!(payout_id) },
          policy_identity: ->(payload, key) { durable_policy_identity_value!(payload, key) },
          monotonic_value: ->(payload, key) { durable_monotonic_value!(payload, key) },
          monotonic_reference: ->(value) { monotonic_reference_for(value) },
          validate_provider_registered_before_fact: lambda do |fact, provider_id|
            validate_provider_registered_before_fact!(fact, provider_id)
          end,
          policy_measure_exclusions: lambda do |eligibility:, policy:, incoming_measure:|
            policy_measure_exclusions(
              eligibility: eligibility,
              policy: policy,
              incoming_measure: incoming_measure
            )
          end,
          outcome_trace: ->(outcome) { outcome_trace_for(outcome) }
        )
      end

      def initialize_decision_trace_validator!
        @decision_trace_validator ||= RubyRouting::State::DecisionTraceValidator.new(
          policies: -> { @policies },
          provider_catalog: -> { @provider_catalog },
          payout_snapshot: ->(state) { snapshot_for(state) },
          decision_enum: ->(payload, key, allowed, label) { durable_enum_value!(payload, key, allowed, label) },
          same_contract: ->(left, right) { same_contract?(left, right) }
        )
      end

      def initialize_decision_fact_restorer!
        @decision_fact_restorer ||= RubyRouting::State::DecisionFactRestorer.new(
          payout_state: ->(payout_id) { payout_state_for!(payout_id) },
          enum_value: ->(payload, key, allowed, label) { durable_enum_value!(payload, key, allowed, label) },
          decision_identifier: ->(value, label) { durable_decision_identifier!(value, label) },
          provider_identity: ->(payload, key) { durable_provider_identity_value!(payload, key) },
          decision_role: ->(value, action:) { @decision_trace_validator.decision_role(value, action: action) },
          decision_trace_validator: @decision_trace_validator,
          validate_provider_registered: ->(fact, provider_id) {
            validate_provider_registered_before_fact!(fact, provider_id)
          },
          contract_from_payload: ->(payload) { contract_from_payload(payload) },
          attempt_state_factory: ->(**attributes) { AttemptState.new(**attributes) },
          monotonic_value: ->(payload, key) { durable_monotonic_value!(payload, key) },
          monotonic_reference: ->(value) { monotonic_reference_for(value) }
        )
      end

      def initialize_routing_components!
        @decision_evaluator = RubyRouting::Routing::DecisionEvaluator.new(
          provider_catalog: @provider_catalog,
          admission_ledger: @admission_ledger,
          allocation_ledger: @allocation_ledger,
          health_controller: @health_controller,
          quality_controller: @quality_controller,
          current_time: -> { current_time },
          current_monotonic: -> { current_monotonic }
        )
        @operation_committer = RubyRouting::State::OperationCommitter.new(
          admission_ledger: @admission_ledger,
          allocation_ledger: @allocation_ledger,
          lifecycle_ledger: @lifecycle_ledger,
          health_controller: @health_controller,
          append_fact: ->(type, payout_id, payload) { append_fact(type, payout_id, payload) },
          current_time: -> { current_time },
          current_monotonic: -> { current_monotonic },
          snapshot_for: ->(state) { snapshot_for(state) },
          contract_payload: ->(contract) { contract_payload(contract) },
          attempt_state: ->(**attributes) { AttemptState.new(**attributes) }
        )
      end

      def atomic_synchronize
        @mutex.synchronize do
          begin
            @fact_store.transaction { yield }
          rescue StandardError
            # A mutation can fail after mutable projections have changed but
            # before its fact batch is published. Rebuild from the last
            # accepted fact prefix on every exceptional path, regardless of
            # whether the store has a journal. The normal path must not
            # Marshal-copy the entire payout history for every mutation: that
            # turns lifecycle throughput into O(n^2).
            restore_working_state_from_facts!
            raise
          end
        end
      end

      def restore_working_state_from_facts!
        source_facts = @fact_store.facts
        persisted_health_policy = RubyRouting::Collection.to_array(source_facts, "facts").reverse.find do |fact|
          fact.type == :provider_opportunity_registered && fact.payload[:health_policy]
        end&.payload&.fetch(:health_policy)
        persisted_quality_policy = RubyRouting::Collection.to_array(source_facts, "facts").reverse.find do |fact|
          fact.type == :provider_opportunity_registered && fact.payload[:quality_policy]
        end&.payload&.fetch(:quality_policy)
        @payouts = {}
        @provider_catalog = RubyRouting::State::ProviderCatalogLedger.new
        @admission_ledger = RubyRouting::State::AdmissionLedger.new(clock: @clock)
        @allocation_ledger = RubyRouting::State::AllocationLedger.new
        @lifecycle_ledger = RubyRouting::State::LifecycleLedger.new
        @observation_ledger = RubyRouting::State::ObservationLedger.new
        @restored_observations = {}
        @pending_economic_conflicts = {}
        @restored_health_signal_sources = {}
        @restored_quality_signal_sources = {}
        @restored_transport_sources = {}
        @pending_health_transitions = {}
        @policies = {}
        @health_controller = RubyRouting::Routing::HealthController.new(
          policy: health_policy_from_payload(persisted_health_policy)
        )
        @quality_controller = RubyRouting::Routing::QualityController.new(
          policy: quality_policy_from_payload(persisted_quality_policy)
        )
        initialize_provider_catalog_restorer!
        restore_from_facts!(source_facts, opportunities: [])
        initialize_routing_components!
      end

      def normalized_provider_id(provider_id)
        RubyRouting::Identity.normalize(provider_id, "provider id")
      end

      def normalized_payout_id(payout_id)
        RubyRouting::Identity.normalize(payout_id, "payout id")
      end

      def normalized_operation_id(operation_id)
        RubyRouting::Identity.normalize(operation_id, "operation id")
      end

      def canonical_health_context(value)
        RubyRouting::Routing::HealthController.canonical_routing_context(value)
      end

      def normalize_provider_opportunities_for_evaluation(opportunities)
        return nil if opportunities.nil?

        values = RubyRouting::Collection.to_array(opportunities, "provider opportunities")
        unless values.all? { |opportunity| opportunity.is_a?(RubyRouting::ProviderOpportunity) }
          raise ArgumentError, "provider opportunities must contain ProviderOpportunity values"
        end

        ids = values.map(&:provider_id)
        unless ids.uniq.length == ids.length
          raise ArgumentError, "provider opportunities must have unique ids"
        end

        values.sort_by(&:provider_id).freeze
      end

      def validate_provider_configuration_current!(opportunities)
        return if RubyRouting::Application::RoutingConfiguration.same_provider_definition_set?(
          @provider_catalog.current,
          opportunities
        )

        raise RubyRouting::ConfigurationDriftError,
          "active provider configuration does not match the Coordinator catalog"
      end

      def provider_opportunities_with_current_runtime(opportunities)
        current_by_id = @provider_catalog.current.to_h do |opportunity|
          [opportunity.provider_id, opportunity]
        end
        opportunities.map do |opportunity|
          current = current_by_id.fetch(opportunity.provider_id)
          opportunity.with_runtime(
            available: current.available,
            capacity_available: current.capacity_available,
            enabled: current.enabled,
            health_available: current.health_available,
            throughput_available: current.throughput_available
          )
        end.sort_by(&:provider_id).freeze
      end

      def policy_measure_exclusions(eligibility:, policy:, incoming_measure:)
        policy.measure_exclusions(eligibility.feasible_provider_ids, incoming_measure)
      end

      def policy_scope_key_from_payload(payload)
        [
          durable_policy_identity_value!(payload, :policy_id),
          durable_policy_identity_value!(payload, :policy_epoch),
          durable_policy_identity_value!(payload, :policy_scope)
        ]
      end

      def durable_identity_value!(payload, key, label)
        value = payload.fetch(key)
        unless value.is_a?(String) && !value.empty? && value == value.strip
          raise RubyRouting::State::DurableCorruptionError,
            "#{label} must be a canonical non-empty String"
        end

        value
      end

      def durable_provider_identity_value!(payload, key)
        durable_identity_value!(payload, key, "provider #{key}")
      end

      def durable_policy_identity_value!(payload, key)
        durable_identity_value!(payload, key, "policy #{key}")
      end

      def durable_operation_identity_value!(payload, key)
        durable_identity_value!(payload, key, "operation #{key}")
      end

      def durable_monotonic_value!(payload, key)
        value = payload.fetch(key)
        unless value.is_a?(Integer) || value.is_a?(Rational)
          raise RubyRouting::State::DurableCorruptionError,
            "#{key} must be an exact monotonic value"
        end

        wall_key = "#{key.to_s.delete_suffix("_monotonic_at")}_at".to_sym
        wall_time = payload[wall_key]
        return monotonic_reference_for(wall_time) if wall_time.is_a?(Time)

        value
      end

      def durable_enum_value!(payload, key, allowed, label)
        RubyRouting::Enum.normalize(payload.fetch(key), allowed, label)
      rescue ArgumentError, KeyError
        raise RubyRouting::State::DurableCorruptionError,
          "#{label} is not a supported durable value"
      end

      def durable_optional_operation_identity_value!(payload, key, default:)
        return default unless payload.key?(key)

        durable_operation_identity_value!(payload, key)
      end

      def normalize_configuration_revision(value)
        return nil if value.nil?
        unless value.is_a?(Integer) && value >= 0
          raise ArgumentError, "configuration revision must be a non-negative Integer"
        end

        value
      end

      def commit_assignment(state, intent, policy, proposal, eligibility, allocation_snapshot,
                            configuration_revision: nil)
        @operation_committer.commit_assignment(
          state,
          intent,
          policy,
          proposal,
          eligibility,
          allocation_snapshot,
          configuration_revision: configuration_revision
        )
      end

      def commit_resolution(state, intent, policy, proposal, configuration_revision: nil)
        @operation_committer.commit_resolution(
          state,
          intent,
          policy,
          proposal,
          configuration_revision: configuration_revision
        )
      end

      def apply_current_outcome(state, attempt, outcome)
        @operation_committer.apply_outcome(state, attempt, outcome)
      end
      def validate_start_commit!(decision_commit, state:, attempt:, expected_pending:)
        proposal = decision_commit.proposal
        unless decision_commit.payout.respond_to?(:id) && decision_commit.payout.id == state.intent.id
          raise ArgumentError, "decision commit payout does not match operation state"
        end

        expected_action = expected_pending == :resolution ? :resolve : proposal.action
        unless proposal.operation_id == attempt.operation_id &&
               proposal.attempt_id == attempt.attempt_id &&
               proposal.provider_id == attempt.provider_id &&
               proposal.policy_epoch == state.policy_epoch &&
               proposal.action == expected_action
          raise ArgumentError, "decision commit does not match operation state"
        end

        expected_role = expected_action == :assign ? attempt.role : :resolution
        unless proposal.role == expected_role
          raise ArgumentError, "decision commit role does not match operation state"
        end

        request = decision_commit.request
        expected_request = RubyRouting::ProviderOperationRequest.from_intent(
          intent: state.intent,
          provider_id: attempt.provider_id,
          operation_id: attempt.operation_id,
          attempt_id: attempt.attempt_id,
          contract: attempt.contract
        )
        unless request.is_a?(RubyRouting::ProviderOperationRequest) &&
               request.to_h == expected_request.to_h
          raise ArgumentError, "decision commit request does not match operation state"
        end
      end

      def validate_start_commit_pending?(decision_commit, state:, attempt:, expected_pending:)
        operation_id = attempt.operation_id
        return false unless state.ownership&.operation_id == operation_id
        return false unless state.operation_actions[operation_id] == decision_commit.proposal.action
        return false unless state.dispatch_pending[operation_id] == expected_pending

        expected_phase = expected_pending == :resolution ? :resolving :
          (decision_commit.proposal.action == :assign ? :committed : :dispatching)
        unless attempt.phase == expected_phase
          raise ArgumentError, "decision commit is not pending for operation state"
        end

        true
      end

      def set_operation_phase(state, operation_id, phase)
        @operation_committer.set_operation_phase(state, operation_id, phase)
      end

      def append_phase_change(state, phase_change)
        @operation_committer.append_phase_change(state, phase_change)
      end
      def capacity_available_for?(opportunity, intent)
        @admission_ledger.capacity_available?(opportunity, intent)
      end

      def capacity_trace_for(opportunity, as_of: nil, as_of_monotonic: nil)
        @admission_ledger.capacity_trace(
          opportunity,
          as_of: as_of,
          as_of_monotonic: as_of_monotonic
        )
      end

      def throughput_available_for?(opportunity)
        @admission_ledger.throughput_available?(opportunity)
      end

      def reserve_throughput!(opportunity)
        @admission_ledger.reserve_throughput!(opportunity)
      end

      def elapsed_seconds(later_monotonic, earlier_monotonic)
        elapsed = later_monotonic - earlier_monotonic
        raise ArgumentError, "clock elapsed time cannot be negative" if elapsed.negative?

        elapsed
      rescue NoMethodError, TypeError
        raise ArgumentError, "clock elapsed values must be exact monotonic numbers"
      end

      def reconciliation_expired_at?(state, attempt, blocked_monotonic_at)
        elapsed = elapsed_seconds(blocked_monotonic_at, attempt.committed_monotonic_at)
        operation_ttl = attempt.contract&.ttl_seconds
        deadline = attempt.contract&.deadline_seconds
        (operation_ttl && elapsed >= operation_ttl) ||
          (deadline && state.created_monotonic_at &&
           elapsed_seconds(blocked_monotonic_at, state.created_monotonic_at) >= deadline)
      rescue NoMethodError, TypeError, ArgumentError
        false
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

      def recovery_schedule_for(state, attempt, outcome)
        return nil unless state.ownership&.operation_id == attempt.operation_id
        return nil unless outcome.unresolved? || (outcome.provider_failure? && !outcome.safe_to_release?)

        policy = @policies.fetch(state.policy_scope_key) do
          raise RubyRouting::State::DurableCorruptionError,
            "missing policy definition for recovery schedule"
        end
        classification = RubyRouting::Routing::Recovery.classify(
          status: outcome.status,
          ownership: state.ownership,
          capabilities: attempt.contract,
          operation_phase: :pending,
          attempts: state.attempts.length,
          policy: policy.recovery,
          resolution_interactions: state.resolution_interaction_count
        )
        return nil unless %i[resolve retry_same].include?(classification.action)

        scheduled_at = current_time
        scheduled_monotonic_at = current_monotonic
        delay_seconds = policy.recovery.delay_for(
          interaction_index: state.resolution_interaction_count
        )
        RubyRouting::RecoverySchedule.new(
          action: classification.action,
          provider_id: attempt.provider_id,
          operation_id: attempt.operation_id,
          attempt_id: attempt.attempt_id,
          scheduled_at: scheduled_at,
          scheduled_monotonic_at: scheduled_monotonic_at,
          next_action_at: scheduled_at + delay_seconds,
          next_action_monotonic_at: scheduled_monotonic_at + delay_seconds,
          delay_seconds: delay_seconds,
          interaction_index: state.resolution_interaction_count,
          reason_code: classification.reason_code
        )
      end

      def provider_execution_failure_work_for(state, as_of:)
        failure = state.provider_execution_failure
        ownership = state.ownership
        return nil unless failure && ownership
        failed_at = failure[:failed_at]
        return nil unless failed_at.is_a?(Time)
        return nil if failed_at.utc > as_of
        return nil if provider_interaction_in_flight?(state.intent.id, ownership.operation_id)
        return nil unless failure[:operation_id] == ownership.operation_id &&
          failure[:provider_id] == ownership.provider_id &&
          failure[:attempt_id] == ownership.attempt_id

        attempt = state.operations.fetch(ownership.operation_id)
        action = same_provider_recovery_action_for(state, attempt)
        return nil unless action
        due_at = provider_execution_failure_due_at_for(state)
        return nil if due_at && due_at > as_of

        RubyRouting::RecoveryWorkItem.new(
          payout_id: state.intent.id,
          action: action,
          provider_id: ownership.provider_id,
          operation_id: ownership.operation_id,
          attempt_id: ownership.attempt_id,
          due_at: due_at,
          reason_code: :provider_execution_failure,
          status: state.status
        )
      end

      def restart_recovery_work_for(state, as_of:)
        ownership = state.ownership
        return nil unless ownership
        return nil if provider_interaction_in_flight?(state.intent.id, ownership.operation_id)
        failure = state.provider_execution_failure
        return nil if failure
        if state.recovery_schedule && !state.recovery_schedule.due?(as_of: as_of)
          return nil
        end

        attempt = state.operations.fetch(ownership.operation_id)
        return nil if live_interaction_failure_for?(state, attempt)
        return nil unless %i[dispatching resolving].include?(attempt.phase)

        started_fact = @fact_store.query(
          payout_id: state.intent.id,
          type: :attempt_started
        ).reverse.find do |fact|
          fact.payload[:operation_id] == attempt.operation_id &&
            fact.payload[:attempt_id] == attempt.attempt_id
        end
        started_at = started_fact&.payload&.[](:started_at)
        return nil unless started_at.is_a?(Time) && started_at.utc <= as_of

        proposal = restart_proposal_for(state, attempt, nil)
        return nil unless proposal

        RubyRouting::RecoveryWorkItem.new(
          payout_id: state.intent.id,
          action: proposal.action,
          provider_id: attempt.provider_id,
          operation_id: attempt.operation_id,
          attempt_id: attempt.attempt_id,
          due_at: nil,
          reason_code: :restart_recovery,
          status: state.status
        )
      end

      def operation_contract_expired_at?(state, as_of)
        if state.status == :reconciliation_blocked
          return reconciliation_blocked_visible_at?(state, as_of)
        end

        attempt = state.operations.fetch(state.ownership.operation_id)
        return false unless attempt.committed_monotonic_at

        as_of_monotonic = monotonic_reference_for(as_of)
        return false if as_of_monotonic < attempt.committed_monotonic_at

        elapsed = elapsed_seconds(as_of_monotonic, attempt.committed_monotonic_at)
        operation_ttl = attempt.contract&.ttl_seconds
        deadline = attempt.contract&.deadline_seconds
        (operation_ttl && elapsed >= operation_ttl) ||
          (deadline && state.created_monotonic_at &&
           elapsed_seconds(as_of_monotonic, state.created_monotonic_at) >= deadline)
      end

      def reconciliation_blocked_at_for(state)
        ownership = state.ownership
        return nil unless ownership

        @fact_store.query(
          payout_id: state.intent.id,
          type: :reconciliation_blocked
        ).reverse_each do |fact|
          payload = fact.payload
          next unless payload[:operation_id] == ownership.operation_id &&
                      payload[:attempt_id] == ownership.attempt_id &&
                      payload[:provider_id] == ownership.provider_id

          return payload[:blocked_at]
        end
        nil
      end

      def same_provider_recovery_action_for(state, attempt)
        policy = @policies.fetch(state.policy_scope_key) do
          raise RubyRouting::State::DurableCorruptionError,
            "missing policy definition for recovery authority"
        end
        RubyRouting::Routing::Recovery.same_provider_action(
          capabilities: attempt.contract,
          resolution_interactions: state.resolution_interaction_count,
          policy: policy.recovery
        )
      end

      def provider_execution_failure_due_at_for(state)
        failure = state.provider_execution_failure
        return nil unless failure && failure[:failed_at].is_a?(Time)

        policy = @policies.fetch(state.policy_scope_key) do
          raise RubyRouting::State::DurableCorruptionError,
            "missing policy definition for recovery timing"
        end
        delay = policy.recovery.delay_for(
          interaction_index: state.resolution_interaction_count
        )
        return nil if delay.zero?

        failure[:failed_at].utc + delay
      end

      def interaction_identity_for(interaction_token)
        [interaction_token.payout_id, interaction_token.operation_id].freeze
      end

      def live_interaction_failure_for?(state, attempt)
        @live_interaction_failures.key?([state.intent.id, attempt.operation_id])
      end

      def clear_live_interaction_failure!(state, attempt)
        @live_interaction_failures.delete([state.intent.id, attempt.operation_id])
      end

      def reconciliation_blocked_visible_at?(state, as_of)
        blocked_at = reconciliation_blocked_at_for(state)
        blocked_at.is_a?(Time) && blocked_at.utc <= as_of
      end

      def expire_unresolved_operation!(state)
        return unless state.ownership
        return if state.status == :reconciliation_blocked

        attempt = state.operations.fetch(state.ownership.operation_id)
        now = current_time
        now_monotonic = current_monotonic
        return if now.nil? || now_monotonic.nil? || attempt.committed_monotonic_at.nil?

        elapsed = elapsed_seconds(now_monotonic, attempt.committed_monotonic_at)
        operation_ttl = attempt.contract&.ttl_seconds
        deadline = attempt.contract&.deadline_seconds
        expired = (operation_ttl && elapsed >= operation_ttl) ||
          (deadline && state.created_monotonic_at &&
           elapsed_seconds(now_monotonic, state.created_monotonic_at) >= deadline)
        return unless expired

        state.status = :reconciliation_blocked
        state.recovery_schedule = nil
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
          blocked_at: now,
          blocked_monotonic_at: now_monotonic
        )
      end

      def record_health_from_observation(observation, routing_context: nil)
        outcome = observation.outcome
        # A transport classification is provider operational evidence even
        # when the normalized payout attribution remains unknown. Health may
        # protect future traffic; it must not grant release authority.
        signal, attribution = if observation.transport_kind == :definitely_not_sent
          [:transport_failure, :provider]
        elsif observation.transport_kind == :ambiguous_after_possible_send
          [:timeout_pressure, :provider]
        elsif outcome.status == :temporary_provider_failure && outcome.attribution == :provider
          [:provider_service_error, outcome.attribution]
        elsif outcome.provider_failure?
          [:provider_failure, outcome.attribution]
        elsif outcome.success? && outcome.attribution == :provider
          [:operational_success, outcome.attribution]
        elsif outcome.status == :unknown && outcome.attribution == :provider
          [:timeout, outcome.attribution]
        end
        if latency_pressure?(observation) && (signal.nil? || signal == :operational_success)
          signal = :latency_pressure
          attribution = :provider
        end
        return unless signal

        record_health_signal_locked(
          provider_id: observation.provider_id,
          signal: signal,
          attribution: attribution,
          source: observation.observation_id,
          source_payout_id: observation.payout_id,
          routing_context: routing_context
        )
      end

      def latency_pressure?(observation)
        threshold_ms = @health_controller.policy.latency_threshold_ms
        duration = observation.interaction_duration_seconds
        duration && threshold_ms && duration * 1000 > threshold_ms &&
          observation.outcome.attribution == :provider
      end

      def record_quality_from_observation(observation, context: nil, currency: nil, observed_at: nil)
        @quality_controller.observe(
          provider_id: observation.provider_id,
          outcome: observation.outcome,
          context: context,
          routing_context: context,
          currency: currency,
          observed_at: observed_at
        )
        return unless quality_evidence_outcome?(observation.outcome)
        after = @quality_controller.evidence_snapshot(
          observation.provider_id,
          context: context,
          routing_context: context,
          currency: currency
        )

        append_fact(
          :quality_signal,
          "system:provider:#{observation.provider_id}",
          observation_id: observation.observation_id,
          source_payout_id: observation.payout_id,
          provider_id: observation.provider_id,
          status: observation.outcome.status,
          attribution: observation.outcome.attribution,
          safe_to_release: observation.outcome.safe_to_release?,
          successful_samples: after.successful_samples,
          failed_samples: after.failed_samples,
          sample_count: after.sample_count,
          score: after.score,
          minimum_samples: after.minimum_samples,
          prior_successes: after.prior_successes,
          prior_failures: after.prior_failures,
          evidence_window: after.evidence_window,
          context_key: after.context_key,
          evidence_scope: after.evidence_scope,
          routing_context: after.routing_context&.to_h,
          currency: after.currency,
          observed_at: observed_at,
          last_observed_at: after.last_observed_at,
          max_evidence_age_seconds: after.max_evidence_age_seconds
        )
      end

      def quality_evidence_outcome?(outcome)
        outcome.is_a?(RubyRouting::NormalizedOutcome) &&
          outcome.attribution == :provider && (outcome.success? || outcome.provider_failure?)
      end

      def record_health_signal_locked(provider_id:, signal:, attribution:, source: nil, source_payout_id: nil,
                                      routing_context: nil)
        release_exposure = source.nil?
        provider_id = normalized_provider_id(provider_id)
        normalized_signal = RubyRouting::Enum.normalize(
          signal,
          RubyRouting::Routing::HealthController::SIGNALS,
          "health signal"
        )
        normalized_attribution = RubyRouting::Enum.normalize(
          attribution,
          RubyRouting::Routing::HealthController::ATTRIBUTIONS,
          "health attribution"
        )
        if source.nil? && !@provider_catalog.key?(provider_id)
          raise ArgumentError, "unknown provider opportunity"
        end
        canonical_context = canonical_health_context(routing_context)
        before, after = @health_controller.observe(
          provider_id: provider_id,
          signal: normalized_signal,
          attribution: normalized_attribution,
          release_exposure: release_exposure,
          routing_context: canonical_context
        )
        normalized_context = canonical_context || RubyRouting::RoutingContext.new
        health_payload = {
          provider_id: provider_id.to_s,
          signal: normalized_signal,
          attribution: normalized_attribution,
          source_kind: source.nil? ? :manual : :observation,
          source: source,
          source_payout_id: source_payout_id,
          release_exposure: release_exposure,
          policy: @health_controller.policy.to_h
        }
        health_payload[:routing_context] = normalized_context.to_h unless normalized_context.empty?
        append_fact(
          :health_signal,
          "system:provider:#{provider_id}",
          **health_payload
        )
        if before.state != after.state
          transition_payload = {
            provider_id: provider_id.to_s,
            from: before.state,
            to: after.state
          }
          transition_payload[:routing_context] = normalized_context.to_h unless normalized_context.empty?
          append_fact(
            :health_state_changed,
            "system:provider:#{provider_id}",
            **transition_payload
          )
        end
        after
      end

      def reserve_capacity!(opportunity, intent, operation_id)
        return false unless opportunity.capacity
        @admission_ledger.reserve_capacity!(opportunity, intent)
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
        release_capacity_reservation!(state, attempt.operation_id)
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

      def next_action_for(state)
        return :stop if %i[success terminal_payout_failure reversed].include?(state.status)
        return :defer if state.conflicts.any?
        return :reroute if state.status == :safe_route_failure && state.ownership.nil?
        return :reroute if state.status == :temporary_provider_failure && state.ownership.nil?
        return :wait if state.ownership

        :defer
      end

      def record_conflict(state, attempt, observation, reason: nil)
        reason ||= if observation.outcome.success?
          :late_old_operation_success
        else
          :late_old_operation_ambiguity
        end
        conflict = RubyRouting::EconomicConflict.new(
          payout_id: state.intent.id,
          provider_id: attempt.provider_id,
          operation_id: attempt.operation_id,
          attempt_id: attempt.attempt_id,
          reason: reason
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
          revision: @fact_store.revision,
          created_at: state.created_at,
          recovery_schedule: state.recovery_schedule
        )
      end

      def same_intent?(left, right)
        left.id == right.id && left.money == right.money && left.recipient == right.recipient &&
          left.context == right.context && left.routing_context == right.routing_context
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

      def same_contract?(left, right)
        return true if left.nil? && right.nil?
        return false unless left && right

        [
          left.provider_id,
          left.idempotent_retry,
          left.status_lookup,
          left.idempotency_key,
          left.ttl_seconds,
          left.deadline_seconds,
          left.version,
          left.authoritative_sequence
        ] == [
          right.provider_id,
          right.idempotent_retry,
          right.status_lookup,
          right.idempotency_key,
          right.ttl_seconds,
          right.deadline_seconds,
          right.version,
          right.authoritative_sequence
        ]
      end

      def append_fact(type, payout_id, payload)
        @fact_store.append(type: type, payout_id: payout_id, payload: payload)
      end

      class PayoutState
        attr_accessor :status, :ownership, :last_outcome, :primary_provider_id,
                      :settlement_provider_id, :settlement_operation_id, :policy_epoch,
                      :provider_interaction_count, :policy_scope_key, :policy_fingerprint,
                      :created_at, :resolution_interaction_count,
                      :created_monotonic_at, :latest_opportunity_evaluation,
                      :provider_execution_failure,
                      :recovery_schedule
        attr_reader :intent, :attempts, :operations, :seen_observations,
                    :conflicts, :conflict_observation_ids, :reversals,
                    :capacity_reservations, :health_exposure_reservations,
                    :dispatch_pending, :throughput_reservations,
                    :allocation_fact_operations, :operation_actions,
                    :operation_action_fact_sequences, :applied_observation_fact_sequences

        def initialize(intent)
          @intent = intent
          @status = :new
          @ownership = nil
          @last_outcome = nil
          @attempts = []
          @operations = {}
          @seen_observations = {}
          @conflicts = []
          @conflict_observation_ids = []
          @provider_interaction_count = 0
          @resolution_interaction_count = 0
          @primary_provider_id = nil
          @settlement_provider_id = nil
          @settlement_operation_id = nil
          @reversals = []
          @capacity_reservations = {}
          @health_exposure_reservations = {}
          @dispatch_pending = {}
          @throughput_reservations = {}
          @allocation_fact_operations = {}
          @operation_actions = {}
          @operation_action_fact_sequences = {}
          @applied_observation_fact_sequences = {}
          @policy_epoch = nil
          @policy_scope_key = nil
          @policy_fingerprint = nil
          @created_at = nil
          @created_monotonic_at = nil
          @provider_execution_failure = nil
          @recovery_schedule = nil
        end
      end

      class AttemptState
        attr_reader :attempt_id, :operation_id, :provider_id, :role, :measure, :contract,
                    :committed_at, :committed_monotonic_at
        attr_accessor :outcome, :phase, :last_observation_sequence

        def initialize(attempt_id:, operation_id:, provider_id:, role:, measure:, phase:, contract:,
                       committed_at: nil, committed_monotonic_at: nil)
          @attempt_id = attempt_id
          @operation_id = operation_id
          @provider_id = provider_id
          @role = role
          @measure = measure
          @phase = RubyRouting::Enum.normalize(phase, RubyRouting::State::AttemptSnapshot::PHASES, "operation phase")
          @contract = contract
          @committed_at = committed_at
          @committed_monotonic_at = committed_monotonic_at
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

    end
  end
end
