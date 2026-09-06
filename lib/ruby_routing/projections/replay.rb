# frozen_string_literal: true

module RubyRouting
  module Projections
    module Replay
      module_function

      def analytics(facts, as_of: nil)
        RubyRouting::Projections::Analytics.from_facts(facts, as_of: as_of)
      end

      def capacity(facts)
        states = {}
        facts.to_a.sort_by(&:sequence).each do |fact|
          payload = fact.payload
          if fact.type == :provider_opportunity_registered
            provider_id = payload.fetch(:provider_id)
            state = states[provider_id.to_s] ||= CapacityState.new(provider_id)
            state.set_budget(payload[:capacity])
          elsif fact.type == :opportunity_evaluated
            payload.fetch(:capacity, {}).each do |provider_id, trace|
              state = states[provider_id.to_s] ||= CapacityState.new(provider_id)
              state.set_budget(trace[:budget])
            end
          elsif %i[capacity_reserved capacity_released].include?(fact.type)
            provider_id = payload.fetch(:provider_id)
            state = states[provider_id.to_s] ||= CapacityState.new(provider_id)
            if fact.type == :capacity_reserved
              state.reserve(payload.fetch(:amount))
            else
              state.release(payload.fetch(:amount))
            end
          end
        end
        CapacityProjection.new(states.transform_values(&:snapshot))
      end

      def allocation(facts)
        states = {}
        facts.to_a.sort_by(&:sequence).each do |fact|
          next unless fact.type == :allocation_committed
          next unless fact.payload.fetch(:role).to_sym == :primary

          payload = fact.payload
          key = Array(payload.fetch(:policy_scope)).map(&:to_s).freeze
          state = states[key] ||= AllocationState.new(key)
          state.commit(provider_id: payload.fetch(:provider_id), measure: payload.fetch(:measure))
        end
        AllocationProjection.new(states.transform_values(&:snapshot))
      end

      def health(facts)
        controller = nil
        facts.to_a.sort_by(&:sequence).each do |fact|
          payload = fact.payload
          if fact.type == :provider_opportunity_registered
            controller ||= RubyRouting::Routing::HealthController.new(
              policy: health_policy_from(payload[:health_policy])
            )
            controller.ensure_provider(payload.fetch(:provider_id))
          elsif fact.type == :opportunity_evaluated
            controller ||= RubyRouting::Routing::HealthController.new(
              policy: health_policy_from(payload[:health_policy])
            )
            payload.fetch(:health, {}).each_key { |provider_id| controller.ensure_provider(provider_id) }
          elsif fact.type == :health_signal
            controller ||= RubyRouting::Routing::HealthController.new(policy: health_policy_from(payload[:policy]))
            controller.observe(
              provider_id: payload.fetch(:provider_id),
              signal: payload.fetch(:signal),
              attribution: payload.fetch(:attribution),
              release_exposure: payload.fetch(:release_exposure, true)
            )
          elsif fact.type == :health_exposure_reserved
            controller ||= RubyRouting::Routing::HealthController.new
            controller.reserve_exposure(
              payload.fetch(:provider_id),
              owner: payload.fetch(:operation_id)
            )
          elsif fact.type == :health_exposure_released
            controller&.release_exposure(
              payload.fetch(:provider_id),
              owner: payload.fetch(:operation_id)
            )
          end
        end
        HealthProjection.new(controller || RubyRouting::Routing::HealthController.new)
      end

      def lifecycle(facts)
        states = {}
        ordered_facts = facts.to_a.sort_by(&:sequence)
        revision = ordered_facts.last&.sequence || 0
        ordered_facts.each do |fact|
          next if %i[
            provider_opportunity_registered
            health_signal
            health_state_changed
          ].include?(fact.type)
          state = states[fact.payout_id] ||= LifecycleState.new(fact.payout_id, revision: revision)
          state.apply(fact)
        end
        LifecycleProjection.new(states.transform_values(&:snapshot))
      end

      def payout(facts, payout_id)
        lifecycle(facts).payout(payout_id)
      end

      def health_policy_from(payload)
        return RubyRouting::Routing::HealthPolicy.new unless payload.is_a?(Hash)

        RubyRouting::Routing::HealthPolicy.new(**payload.transform_keys(&:to_sym))
      end

      class CapacityProjection
        attr_reader :providers

        def initialize(providers)
          @providers = providers.dup.freeze
          freeze
        end

        def snapshot(provider_id)
          providers.fetch(provider_id.to_s)
        end

        def to_h
          providers.transform_values do |snapshot|
            {
              budget: snapshot.budget&.to_h,
              used_slots: snapshot.used_slots,
              used_count: snapshot.used_count,
              used_amount_minor: snapshot.used_amount_minor
            }
          end.freeze
        end
      end

      class AllocationProjection
        attr_reader :policies

        def initialize(policies)
          @policies = policies.dup.freeze
          freeze
        end

        def snapshot(policy_or_key)
          key = if policy_or_key.respond_to?(:allocation_key)
            policy_or_key.allocation_key
          else
            Array(policy_or_key).map(&:to_s)
          end
          policies.fetch(key) { RubyRouting::Routing::AllocationSnapshot.empty }
        end

        def to_h
          policies.transform_values do |snapshot|
            { measures: snapshot.measures, revision: snapshot.revision }
          end.freeze
        end
      end

      class AllocationState
        def initialize(key)
          @key = key
          @measures = {}
          @revision = 0
        end

        def commit(provider_id:, measure:)
          normalized_provider_id = provider_id.to_s
          @measures[normalized_provider_id] = @measures.fetch(normalized_provider_id, 0) + measure
          @revision += 1
        end

        def snapshot
          RubyRouting::Routing::AllocationSnapshot.new(
            measures: @measures,
            revision: @revision
          )
        end
      end

      class CapacityState
        def initialize(provider_id)
          @provider_id = provider_id.to_s
          @budget = nil
          @used_slots = 0
          @used_count = 0
          @used_amount_minor = 0
        end

        def set_budget(payload)
          @budget = if payload.nil?
            nil
          else
            values = payload.transform_keys(&:to_sym)
            RubyRouting::CapacityBudget.new(**values)
          end
        end

        def reserve(money)
          @used_slots += 1
          @used_count += 1
          @used_amount_minor += money.amount_minor
        end

        def release(money)
          @used_slots -= 1
          @used_count -= 1
          @used_amount_minor -= money.amount_minor
          raise ArgumentError, "replayed capacity usage underflow" if @used_slots.negative? ||
            @used_count.negative? || @used_amount_minor.negative?
        end

        def snapshot
          RubyRouting::State::CapacitySnapshot.new(
            provider_id: @provider_id,
            budget: @budget,
            used_slots: @used_slots,
            used_count: @used_count,
            used_amount_minor: @used_amount_minor
          )
        end
      end

      class HealthProjection
        def initialize(controller)
          @controller = controller
          freeze
        end

        def snapshot(provider_id)
          @controller.snapshot(provider_id)
        end

        def to_h
          @controller.provider_ids.each_with_object({}) do |provider_id, copy|
            copy[provider_id] = @controller.snapshot(provider_id).to_h
          end.freeze
        end
      end

      class LifecycleProjection
        attr_reader :payouts

        def initialize(payouts)
          @payouts = payouts.dup.freeze
          freeze
        end

        def payout(payout_id)
          payouts.fetch(payout_id.to_s)
        end

        def to_h
          payouts.transform_values do |payout|
            {
              status: payout.status,
              ownership: payout.ownership && [
                payout.ownership.provider_id,
                payout.ownership.operation_id,
                payout.ownership.attempt_id
              ],
              attempts: payout.attempts.map do |attempt|
               [attempt.attempt_id, attempt.operation_id, attempt.provider_id, attempt.role,
                 attempt.phase, attempt.measure, attempt.outcome&.status, attempt.committed_at]
              end,
              primary_provider_id: payout.primary_provider_id,
              settlement_provider_id: payout.settlement_provider_id,
              settlement_operation_id: payout.settlement_operation_id,
              policy_scope_key: payout.policy_scope_key,
              policy_fingerprint: payout.policy_fingerprint,
              provider_interaction_count: payout.provider_interaction_count,
              created_at: payout.created_at,
              conflicts: payout.conflicts.map { |conflict| [conflict.operation_id, conflict.reason] },
              reversals: payout.reversals.map { |reversal| [reversal.reversal_id, reversal.amount] }
            }
          end.freeze
        end
      end

      class LifecycleState
        attr_reader :payout_id

        def initialize(payout_id, revision: 0)
          @payout_id = payout_id
          @revision = revision
          @intent = nil
          @status = :new
          @ownership = nil
          @last_outcome = nil
          @attempts = []
          @operations = {}
          @primary_provider_id = nil
          @settlement_provider_id = nil
          @settlement_operation_id = nil
          @policy_scope_key = nil
          @policy_fingerprint = nil
          @policy_epoch = nil
          @provider_interaction_count = 0
          @resolution_interaction_count = 0
          @conflicts = []
          @reversals = []
          @created_at = nil
        end

        def apply(fact)
          payload = fact.payload
          case fact.type
          when :intent_registered
            @intent = RubyRouting::PayoutIntent.new(
              id: fact.payout_id,
              money: payload.fetch(:money),
              recipient: payload.fetch(:recipient, {}),
              context: payload.fetch(:context, {})
            )
            @created_at = payload[:created_at]
          when :policy_registered
            @policy_scope_key = [
              payload.fetch(:policy_id),
              payload.fetch(:policy_epoch),
              payload.fetch(:policy_scope)
            ].map(&:to_s).freeze
            @policy_epoch = payload.fetch(:policy_epoch).to_s
            @policy_fingerprint = payload.fetch(:policy_fingerprint).to_s.freeze
          when :decision_committed
            @policy_epoch = payload[:policy_epoch]&.to_s
            if %i[assign retry_same].include?(payload[:action].to_sym) && payload[:operation_id]
              ensure_attempt(
                operation_id: payload[:operation_id],
                attempt_id: payload[:attempt_id],
                provider_id: payload[:provider_id],
                role: payload[:role],
                contract: payload[:contract],
                committed_at: payload[:committed_at]
              )
              @primary_provider_id ||= payload[:provider_id].to_s if payload[:role].to_sym == :primary
            end
          when :allocation_committed
            attempt = ensure_attempt(
              operation_id: payload[:operation_id],
              attempt_id: payload[:attempt_id],
              provider_id: payload[:provider_id],
              role: payload[:role]
            )
            attempt.measure = payload[:measure]
          when :ownership_acquired
            @ownership = RubyRouting::EconomicOwnership.new(
              payout_id: fact.payout_id,
              provider_id: payload.fetch(:provider_id),
              operation_id: payload.fetch(:operation_id),
              attempt_id: payload.fetch(:attempt_id)
            )
            @status = :pending
          when :attempt_started
            @provider_interaction_count += 1
            @resolution_interaction_count += 1 if %i[resolve retry_same].include?(payload[:action].to_sym)
          when :operation_phase_changed
            attempt = @operations[payload[:operation_id]]
            attempt.phase = payload[:to].to_sym if attempt
          when :provider_observed
            apply_observation(payload)
          when :ownership_released
            @ownership = nil
          when :settlement_recorded
            @status = :success
            @settlement_provider_id = payload.fetch(:provider_id).to_s
            @settlement_operation_id = payload.fetch(:operation_id).to_s
            @ownership = nil
          when :reconciliation_blocked
            @status = :reconciliation_blocked
          when :economic_conflict
            @conflicts << RubyRouting::EconomicConflict.new(
              payout_id: fact.payout_id,
              provider_id: payload.fetch(:provider_id),
              operation_id: payload.fetch(:operation_id),
              attempt_id: payload.fetch(:attempt_id),
              reason: payload.fetch(:reason)
            )
          when :reversal_recorded
            reversal = RubyRouting::SettlementReversal.new(
              reversal_id: payload.fetch(:reversal_id),
              payout_id: fact.payout_id,
              provider_id: payload.fetch(:provider_id),
              operation_id: payload.fetch(:operation_id),
              amount: payload.fetch(:amount),
              reason: payload.fetch(:reason)
            )
            @reversals << reversal
            @status = :reversed
          end
          self
        end

        def snapshot
          RubyRouting::State::PayoutSnapshot.new(
            intent: @intent,
            status: @status,
            ownership: @ownership,
            last_outcome: @last_outcome,
            attempts: @attempts.map(&:to_snapshot),
            primary_provider_id: @primary_provider_id,
            settlement_provider_id: @settlement_provider_id,
            settlement_operation_id: @settlement_operation_id,
            policy_epoch: @policy_epoch,
            policy_scope_key: @policy_scope_key,
            policy_fingerprint: @policy_fingerprint,
            provider_interaction_count: @provider_interaction_count,
            resolution_interaction_count: @resolution_interaction_count,
            revision: @revision,
            conflicts: @conflicts,
            reversals: @reversals,
            created_at: @created_at
          )
        end

        private

        def ensure_attempt(operation_id:, attempt_id:, provider_id:, role:, contract: nil, committed_at: nil)
          return @operations[operation_id.to_s] if @operations.key?(operation_id.to_s)

          attempt = ReplayAttempt.new(
            attempt_id: attempt_id || "#{@payout_id}:unknown-attempt:#{@attempts.length + 1}",
            operation_id: operation_id,
            provider_id: provider_id,
            role: role,
            contract: contract_from(contract),
            committed_at: committed_at
          )
          @attempts << attempt
          @operations[attempt.operation_id] = attempt
          attempt
        end

        def contract_from(payload)
          return nil unless payload

          RubyRouting::ProviderOperationContract.new(
            provider_id: payload.fetch(:provider_id),
            idempotent_retry: payload.fetch(:idempotent_retry),
            status_lookup: payload.fetch(:status_lookup),
            idempotency_key: payload.fetch(:idempotency_key),
            ttl_seconds: payload[:ttl_seconds],
            deadline_seconds: payload[:deadline_seconds],
            version: payload.fetch(:version),
            authoritative_sequence: payload.fetch(:authoritative_sequence, false)
          )
        end

        def apply_observation(payload)
          return unless payload[:applied]

          attempt = @operations[payload[:operation_id].to_s]
          return unless attempt

          outcome = RubyRouting::NormalizedOutcome.new(
            status: payload.fetch(:status),
            attribution: payload.fetch(:attribution),
            provider_reference: payload[:outcome_provider_reference],
            message: payload[:message],
            safe_to_release: payload.fetch(:safe_to_release)
          )
          attempt.outcome = outcome
          attempt.last_observation_sequence = payload[:sequence] unless payload[:sequence].nil?
          @last_outcome = outcome
          case outcome.status
          when :success
            @status = :success
          when :pending
            @status = :pending
          when :unknown
            @status = :unknown
          when :safe_route_failure, :temporary_provider_failure
            @status = outcome.safe_to_release? ? outcome.status : :unknown
          when :terminal_payout_failure
            @status = :terminal_payout_failure
          end
        end
      end

      class ReplayAttempt
        attr_reader :attempt_id, :operation_id, :provider_id, :role, :contract, :committed_at
        attr_accessor :outcome, :measure, :phase, :last_observation_sequence

        def initialize(attempt_id:, operation_id:, provider_id:, role:, contract:, committed_at: nil)
          @attempt_id = attempt_id.to_s
          @operation_id = operation_id.to_s
          @provider_id = provider_id.to_s
          @role = role.to_sym
          @contract = contract
          @committed_at = committed_at&.freeze
          @measure = nil
          @phase = :committed
          @outcome = nil
          @last_observation_sequence = nil
        end

        def to_snapshot
          RubyRouting::State::AttemptSnapshot.new(
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
