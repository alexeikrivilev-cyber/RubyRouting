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
        RubyRouting::Collection.to_array(facts, "facts").sort_by(&:sequence).each do |fact|
          payload = fact.payload
          if fact.type == :provider_opportunity_registered
            provider_id = normalize_identity(payload.fetch(:provider_id), "provider id")
            state = states[provider_id] ||= CapacityState.new(provider_id)
            state.set_budget(payload[:capacity])
          elsif fact.type == :opportunity_evaluated
            payload.fetch(:capacity, {}).each do |provider_id, trace|
              provider_id = normalize_identity(provider_id, "provider id")
              state = states[provider_id] ||= CapacityState.new(provider_id)
              state.set_budget(trace[:budget])
            end
          elsif %i[capacity_reserved capacity_released].include?(fact.type)
            provider_id = normalize_identity(payload.fetch(:provider_id), "provider id")
            state = states[provider_id] ||= CapacityState.new(provider_id)
            if fact.type == :capacity_reserved
              state.reserve(payload.fetch(:amount))
            else
              state.release(payload.fetch(:amount))
            end
          end
        end
        CapacityProjection.new(states.transform_values(&:snapshot))
      end

      def throughput(facts, as_of: nil)
        states = {}
        RubyRouting::Collection.to_array(facts, "facts").sort_by(&:sequence).each do |fact|
          payload = fact.payload
          if fact.type == :provider_opportunity_registered
            provider_id = normalize_identity(payload.fetch(:provider_id), "provider id")
            state = states[provider_id] ||= ThroughputState.new(provider_id)
            state.set_budget(payload[:throughput])
          elsif fact.type == :throughput_consumed
            provider_id = normalize_identity(payload.fetch(:provider_id), "provider id")
            state = states[provider_id] ||= ThroughputState.new(provider_id)
            state.consume(payload.fetch(:consumed_at))
          end
        end
        ThroughputProjection.new(states.transform_values { |state| state.snapshot(as_of: as_of) })
      end

      def allocation(facts)
        states = {}
        RubyRouting::Collection.to_array(facts, "facts").sort_by(&:sequence).each do |fact|
          next unless fact.type == :allocation_committed
          next unless RubyRouting::Enum.normalize(
            fact.payload.fetch(:role),
            %i[primary recovery],
            "allocation role"
          ) == :primary

          payload = fact.payload
          key = if payload[:allocation_key]
            normalize_allocation_key(payload[:allocation_key])
          else
            RubyRouting::Collection.to_array(payload.fetch(:policy_scope), "allocation key").map do |part|
              normalize_identity(part, "allocation key part")
            end.freeze
          end
          state = states[key] ||= AllocationState.new(key)
          state.commit(provider_id: payload.fetch(:provider_id), measure: payload.fetch(:measure))
        end
        AllocationProjection.new(states.transform_values(&:snapshot))
      end

      def health(facts, routing_context: nil)
        controller = nil
        RubyRouting::Collection.to_array(facts, "facts").sort_by(&:sequence).each do |fact|
          payload = fact.payload
          if fact.type == :provider_opportunity_registered
            controller ||= RubyRouting::Routing::HealthController.new(
              policy: health_policy_from(payload[:health_policy])
            )
            controller.ensure_provider(
              normalize_identity(payload.fetch(:provider_id), "provider id")
            )
          elsif fact.type == :opportunity_evaluated
            controller ||= RubyRouting::Routing::HealthController.new(
              policy: health_policy_from(payload[:health_policy])
            )
            payload.fetch(:health, {}).each_key do |provider_id|
              controller.ensure_provider(normalize_identity(provider_id, "provider id"))
            end
          elsif fact.type == :health_signal
            controller ||= RubyRouting::Routing::HealthController.new(policy: health_policy_from(payload[:policy]))
            controller.observe(
              provider_id: normalize_identity(payload.fetch(:provider_id), "provider id"),
              signal: payload.fetch(:signal),
              attribution: payload.fetch(:attribution),
              release_exposure: payload.fetch(:release_exposure, true),
              routing_context: payload[:routing_context]
            )
          elsif fact.type == :health_exposure_reserved
            controller ||= RubyRouting::Routing::HealthController.new
            controller.reserve_exposure(
              normalize_identity(payload.fetch(:provider_id), "provider id"),
              owner: normalize_identity(payload.fetch(:operation_id), "operation id"),
              routing_context: payload[:routing_context]
            )
          elsif fact.type == :health_exposure_released
            provider_id = normalize_identity(payload.fetch(:provider_id), "provider id")
            operation_id = normalize_identity(payload.fetch(:operation_id), "operation id")
            controller&.release_exposure(
              provider_id,
              owner: operation_id,
              routing_context: payload[:routing_context]
            )
          end
        end
        HealthProjection.new(
          controller || RubyRouting::Routing::HealthController.new,
          routing_context: routing_context
        )
      end

      def quality(facts, as_of: nil, context: nil, context_key: nil, routing_context: nil, currency: nil)
        controller = nil
        RubyRouting::Collection.to_array(facts, "facts").sort_by(&:sequence).each do |fact|
          payload = fact.payload
          if fact.type == :provider_opportunity_registered
            controller ||= RubyRouting::Routing::QualityController.new(
              policy: quality_policy_from(payload[:quality_policy])
            )
            controller.ensure_provider(
              normalize_identity(payload.fetch(:provider_id), "provider id")
            )
          elsif fact.type == :quality_signal
            controller ||= RubyRouting::Routing::QualityController.new
            controller.observe(
              provider_id: normalize_identity(payload.fetch(:provider_id), "provider id"),
              context_key: normalize_context_key(payload.fetch(:context_key, [])),
              routing_context: payload[:routing_context],
              currency: payload[:currency],
              observed_at: payload[:observed_at],
              outcome: RubyRouting::NormalizedOutcome.new(
                status: payload.fetch(:status),
                attribution: payload.fetch(:attribution),
                safe_to_release: payload[:safe_to_release]
              )
            )
          end
        end
        QualityProjection.new(
          controller || RubyRouting::Routing::QualityController.new,
          as_of: as_of,
          context: context,
          context_key: context_key,
          routing_context: routing_context,
          currency: currency
        )
      end

      def lifecycle(facts)
        states = {}
        ordered_facts = RubyRouting::Collection.to_array(facts, "facts").sort_by(&:sequence)
        revision = ordered_facts.last&.sequence || 0
        ordered_facts.each do |fact|
          next if %i[
            provider_opportunity_registered
            provider_opportunity_removed
            provider_runtime_changed
            health_signal
            health_state_changed
            throughput_consumed
            quality_signal
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
        return RubyRouting::Routing::HealthPolicy.new if payload.nil?

        values = RubyRouting::HashKeys.symbolize(
          payload,
          %i[degrade_after quarantine_after recover_after probe_limit latency_threshold_ms],
          "health policy"
        )
        RubyRouting::Routing::HealthPolicy.new(**values)
      end

      def quality_policy_from(payload)
        return RubyRouting::Routing::QualityPolicy.new if payload.nil?

        values = RubyRouting::HashKeys.symbolize(
          payload,
          %i[minimum_samples prior_successes prior_failures evidence_window max_evidence_age_seconds route_minimum_samples],
          "quality policy"
        )
        RubyRouting::Routing::QualityPolicy.new(**values)
      end

      def normalize_allocation_key(value)
        case value
        when Array
          value.map { |part| normalize_allocation_key(part) }.freeze
        else
          normalize_identity(value, "allocation key part")
        end
      end
      private_class_method :normalize_allocation_key

      def normalize_context_key(value)
        RubyRouting::Collection.to_array(value, "quality context key").map do |label|
          normalize_identity(label, "quality context label")
        end.uniq.sort.freeze
      end
      private_class_method :normalize_context_key

      def normalize_identity(value, label)
        unless value.is_a?(String) || value.is_a?(Symbol)
          raise ArgumentError, "#{label} must be a String or Symbol"
        end

        normalized = value.to_s.strip
        raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

        normalized.freeze
      end
      private_class_method :normalize_identity

      class CapacityProjection
        attr_reader :providers

        def initialize(providers)
          @providers = providers.dup.freeze
          freeze
        end

        def snapshot(provider_id)
          providers.fetch(Replay.send(:normalize_identity, provider_id, "provider id"))
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
          raw_key = if policy_or_key.respond_to?(:allocation_key)
            policy_or_key.allocation_key
          else
            policy_or_key
          end
          policies.fetch(normalize_allocation_key(raw_key)) { RubyRouting::Routing::AllocationSnapshot.empty }
        end

        def to_h
          policies.transform_values do |snapshot|
            { measures: snapshot.measures, revision: snapshot.revision }
          end.freeze
        end

        private

        def normalize_allocation_key(value)
          case value
          when Array
            value.map { |part| normalize_allocation_key(part) }.freeze
          else
            Replay.send(:normalize_identity, value, "allocation key part")
          end
        end
      end

      class ThroughputProjection
        attr_reader :providers

        def initialize(providers)
          @providers = providers.dup.freeze
          freeze
        end

        def snapshot(provider_id)
          providers.fetch(Replay.send(:normalize_identity, provider_id, "provider id"))
        end

        def to_h
          providers.transform_values(&:to_h).freeze
        end
      end

      class AllocationState
        def initialize(key)
          @key = key
          @measures = {}
          @revision = 0
        end

        def commit(provider_id:, measure:)
          normalized_provider_id = Replay.send(:normalize_identity, provider_id, "provider id")
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
          @provider_id = Replay.send(:normalize_identity, provider_id, "provider id")
          @budget = nil
          @in_flight = 0
          @used_amount_minor_by_currency = Hash.new(0)
        end

        def set_budget(payload)
          @budget = if payload.nil?
            nil
          else
            values = RubyRouting::HashKeys.symbolize(
              payload,
              %i[max_slots max_count max_amount_minor currency],
              "capacity budget"
            )
            RubyRouting::CapacityBudget.new(**values)
          end
        end

        def reserve(money)
          @in_flight += 1
          @used_amount_minor_by_currency[money.currency] += money.amount_minor
        end

        def release(money)
          current_amount = @used_amount_minor_by_currency.fetch(money.currency, 0)
          next_amount = current_amount - money.amount_minor
          raise ArgumentError, "replayed capacity usage underflow" if @in_flight <= 0 || next_amount.negative?

          @in_flight -= 1
          @used_amount_minor_by_currency[money.currency] = next_amount
          @used_amount_minor_by_currency.delete(money.currency) if next_amount.zero?
        end

        def snapshot
          RubyRouting::State::CapacitySnapshot.new(
            provider_id: @provider_id,
            budget: @budget,
            used_slots: @in_flight,
            used_count: @in_flight,
            used_amount_minor: used_amount_minor
          )
        end

        private

        def used_amount_minor
          return @used_amount_minor_by_currency.values.sum if @budget.nil? || @budget.currency.nil?

          @used_amount_minor_by_currency.fetch(@budget.currency, 0)
        end
      end

      class ThroughputState
        def initialize(provider_id)
          @provider_id = Replay.send(:normalize_identity, provider_id, "provider id")
          @budget = nil
          @consumed_at = []
        end

        def set_budget(payload)
          @budget = if payload.nil?
            nil
          else
            values = RubyRouting::HashKeys.symbolize(
              payload,
              %i[max_operations window_seconds],
              "throughput budget"
            )
            RubyRouting::ThroughputBudget.new(**values)
          end
        end

        def consume(consumed_at)
          @consumed_at << consumed_at
        end

        def snapshot(as_of: nil)
          consumed_at = if @budget && as_of
            cutoff = as_of - @budget.window_seconds
            @consumed_at.select { |timestamp| timestamp > cutoff }
          else
            @consumed_at
          end
          RubyRouting::State::ThroughputSnapshot.new(
            provider_id: @provider_id,
            budget: @budget,
            consumed_at: consumed_at
          )
        end
      end

      class HealthProjection
        def initialize(controller, routing_context: nil)
          @controller = controller
          @routing_context = routing_context
          freeze
        end

        def snapshot(provider_id, routing_context: @routing_context)
          @controller.snapshot(
            Replay.send(:normalize_identity, provider_id, "provider id"),
            routing_context: routing_context
          )
        end

        def to_h
          @controller.provider_ids.each_with_object({}) do |provider_id, copy|
            copy[provider_id] = snapshot(provider_id).to_h
          end.freeze
        end
      end

      class QualityProjection
        def initialize(controller, as_of: nil, context: nil, context_key: nil,
                       routing_context: nil, currency: nil)
          @controller = controller
          @as_of = as_of
          @context = context
          @context_key = context_key
          @routing_context = routing_context
          @currency = currency
          freeze
        end

        def snapshot(provider_id, context: @context, context_key: @context_key,
                     routing_context: @routing_context, currency: @currency,
                     as_of: @as_of)
          @controller.snapshot(
            Replay.send(:normalize_identity, provider_id, "provider id"),
            context: context,
            context_key: context_key,
            routing_context: routing_context,
            currency: currency,
            as_of: as_of
          )
        end

        def to_h
          @controller.provider_ids.each_with_object({}) do |provider_id, copy|
            copy[provider_id] = snapshot(provider_id).to_h
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
          payouts.fetch(Replay.send(:normalize_identity, payout_id, "payout id"))
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
              recovery_schedule: payout.recovery_schedule,
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
          @payout_id = Replay.send(:normalize_identity, payout_id, "payout id")
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
          @recovery_schedule = nil
        end

        def apply(fact)
          payload = fact.payload
          case fact.type
          when :intent_registered
            @intent = RubyRouting::PayoutIntent.new(
              id: fact.payout_id,
              money: payload.fetch(:money),
              recipient: payload.fetch(:recipient, {}),
              context: payload.fetch(:context, {}),
              routing_context: payload[:routing_context]
            )
            @created_at = payload[:created_at]
          when :policy_registered
            @policy_scope_key = [
              payload.fetch(:policy_id),
              payload.fetch(:policy_epoch),
              payload.fetch(:policy_scope)
            ].map { |part| Replay.send(:normalize_identity, part, "policy identity") }.freeze
            @policy_epoch = Replay.send(:normalize_identity, payload.fetch(:policy_epoch), "policy epoch")
            @policy_fingerprint = Replay.send(:normalize_identity, payload.fetch(:policy_fingerprint), "policy fingerprint")
          when :decision_committed
            @policy_epoch = payload[:policy_epoch] &&
              Replay.send(:normalize_identity, payload[:policy_epoch], "policy epoch")
            action = RubyRouting::Enum.normalize(
              payload.fetch(:action),
              RubyRouting::DecisionProposal::ACTIONS,
              "decision action"
            )
            if payload[:operation_id]
              Replay.send(:normalize_identity, payload[:operation_id], "operation id")
              Replay.send(:normalize_identity, payload.fetch(:attempt_id), "attempt id")
              Replay.send(:normalize_identity, payload.fetch(:provider_id), "provider id")
            end
            if %i[assign retry_same].include?(action) && payload[:operation_id]
              @recovery_schedule = nil
              ensure_attempt(
                operation_id: payload[:operation_id],
                attempt_id: payload[:attempt_id],
                provider_id: payload[:provider_id],
                role: payload[:role],
                contract: payload[:contract],
                committed_at: payload[:committed_at]
              )
              if RubyRouting::Enum.normalize(payload.fetch(:role), RubyRouting::DecisionProposal::ROLES, "decision role") == :primary
                @primary_provider_id ||= Replay.send(:normalize_identity, payload[:provider_id], "provider id")
              end
            end
            @status = :deferred if action == :defer && @ownership.nil?
            @recovery_schedule = nil if %i[resolve retry_same].include?(action)
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
              provider_id: Replay.send(:normalize_identity, payload.fetch(:provider_id), "provider id"),
              operation_id: Replay.send(:normalize_identity, payload.fetch(:operation_id), "operation id"),
              attempt_id: Replay.send(:normalize_identity, payload.fetch(:attempt_id), "attempt id")
            )
            @status = :pending
          when :attempt_started
            Replay.send(:normalize_identity, payload.fetch(:provider_id), "provider id")
            Replay.send(:normalize_identity, payload.fetch(:operation_id), "operation id")
            Replay.send(:normalize_identity, payload.fetch(:attempt_id), "attempt id")
            @provider_interaction_count += 1
            action = RubyRouting::Enum.normalize(
              payload.fetch(:action),
              RubyRouting::DecisionProposal::ACTIONS,
              "decision action"
            )
            @resolution_interaction_count += 1 if %i[resolve retry_same].include?(action)
          when :operation_phase_changed
            operation_id = Replay.send(:normalize_identity, payload[:operation_id], "operation id")
            Replay.send(:normalize_identity, payload.fetch(:provider_id), "provider id")
            Replay.send(:normalize_identity, payload.fetch(:attempt_id), "attempt id")
            attempt = @operations[operation_id]
            attempt.phase = RubyRouting::Enum.normalize(
              payload.fetch(:to),
              RubyRouting::State::AttemptSnapshot::PHASES,
              "operation phase"
            ) if attempt
          when :provider_observed
            apply_observation(payload)
          when :ownership_released
            Replay.send(:normalize_identity, payload.fetch(:provider_id), "provider id")
            Replay.send(:normalize_identity, payload.fetch(:operation_id), "operation id")
            Replay.send(:normalize_identity, payload.fetch(:attempt_id), "attempt id")
            @ownership = nil
            @recovery_schedule = nil
          when :settlement_recorded
            @status = :success
            @settlement_provider_id = Replay.send(:normalize_identity, payload.fetch(:provider_id), "provider id")
            @settlement_operation_id = Replay.send(:normalize_identity, payload.fetch(:operation_id), "operation id")
            @ownership = nil
            @recovery_schedule = nil
          when :reconciliation_blocked
            @status = :reconciliation_blocked
            # The live expiry transition consumes any delayed recovery work
            # before publishing the terminal reconciliation obligation. Keep
            # replay aligned with that ownership-preserving, fail-closed
            # transition so the snapshot remains valid and deterministic.
            @recovery_schedule = nil
          when :economic_conflict
            @conflicts << RubyRouting::EconomicConflict.new(
              payout_id: fact.payout_id,
              provider_id: Replay.send(:normalize_identity, payload.fetch(:provider_id), "provider id"),
              operation_id: Replay.send(:normalize_identity, payload.fetch(:operation_id), "operation id"),
              attempt_id: Replay.send(:normalize_identity, payload.fetch(:attempt_id), "attempt id"),
              reason: payload.fetch(:reason)
            )
          when :reversal_recorded
            reversal = RubyRouting::SettlementReversal.new(
              reversal_id: Replay.send(:normalize_identity, payload.fetch(:reversal_id), "reversal id"),
              payout_id: fact.payout_id,
              provider_id: Replay.send(:normalize_identity, payload.fetch(:provider_id), "provider id"),
              operation_id: Replay.send(:normalize_identity, payload.fetch(:operation_id), "operation id"),
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
            created_at: @created_at,
            recovery_schedule: @recovery_schedule
          )
        end

        private

        def ensure_attempt(operation_id:, attempt_id:, provider_id:, role:, contract: nil, committed_at: nil)
          normalized_operation_id = Replay.send(:normalize_identity, operation_id, "operation id")
          normalized_attempt_id = attempt_id && Replay.send(:normalize_identity, attempt_id, "attempt id")
          normalized_provider_id = Replay.send(:normalize_identity, provider_id, "provider id")
          normalized_role = RubyRouting::Enum.normalize(
            role,
            RubyRouting::DecisionProposal::ROLES,
            "replay attempt role"
          )
          normalized_contract = contract_from(contract)
          return @operations[normalized_operation_id] if @operations.key?(normalized_operation_id)

          attempt = ReplayAttempt.new(
            attempt_id: normalized_attempt_id || "#{@payout_id}:unknown-attempt:#{@attempts.length + 1}",
            operation_id: normalized_operation_id,
            provider_id: normalized_provider_id,
            role: normalized_role,
            contract: normalized_contract,
            committed_at: committed_at
          )
          @attempts << attempt
          @operations[attempt.operation_id] = attempt
          attempt
        end

        def contract_from(payload)
          return nil unless payload

          RubyRouting::ProviderOperationContract.new(
            provider_id: Replay.send(:normalize_identity, payload.fetch(:provider_id), "provider id"),
            idempotent_retry: payload.fetch(:idempotent_retry),
            status_lookup: payload.fetch(:status_lookup),
            idempotency_key: Replay.send(:normalize_identity, payload.fetch(:idempotency_key), "idempotency key"),
            ttl_seconds: payload[:ttl_seconds],
            deadline_seconds: payload[:deadline_seconds],
            version: Replay.send(:normalize_identity, payload.fetch(:version), "contract version"),
            authoritative_sequence: payload.fetch(:authoritative_sequence, false)
          )
        end

        def apply_observation(payload)
          Replay.send(:normalize_identity, payload.fetch(:observation_id), "observation id")
          Replay.send(:normalize_identity, payload.fetch(:provider_id), "provider id")
          Replay.send(:normalize_identity, payload.fetch(:attempt_id), "attempt id")
          operation_id = Replay.send(:normalize_identity, payload[:operation_id], "operation id")
          schedule = RubyRouting::RecoverySchedule.from(payload[:recovery_schedule])
          if schedule && !payload[:applied]
            raise ArgumentError, "unapplied observation cannot carry recovery schedule"
          end
          return unless payload[:applied]

          attempt = @operations[operation_id]
          if schedule && attempt.nil?
            raise ArgumentError, "recovery schedule references an unknown operation"
          end
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
          validate_recovery_schedule!(schedule, attempt, outcome) if schedule
          @recovery_schedule = schedule
          @status = RubyRouting::State::LifecycleLedger.reduce_status(
            outcome.status,
            safe_to_release: outcome.safe_to_release?
          )
        end

        def validate_recovery_schedule!(schedule, attempt, outcome)
          valid = @ownership &&
            @ownership.operation_id == schedule.operation_id &&
            @ownership.provider_id == schedule.provider_id &&
            @ownership.attempt_id == schedule.attempt_id &&
            attempt.operation_id == schedule.operation_id &&
            attempt.provider_id == schedule.provider_id &&
            attempt.attempt_id == schedule.attempt_id &&
            (outcome.unresolved? || (outcome.provider_failure? && !outcome.safe_to_release?)) &&
            (schedule.action == :resolve ? attempt.contract&.status_lookup : attempt.contract&.idempotent_retry)
          return if valid

          raise ArgumentError, "recovery schedule is not linked to a supported unresolved operation"
        end
      end

      class ReplayAttempt
        attr_reader :attempt_id, :operation_id, :provider_id, :role, :contract, :committed_at
        attr_accessor :outcome, :measure, :phase, :last_observation_sequence

        def initialize(attempt_id:, operation_id:, provider_id:, role:, contract:, committed_at: nil)
          @attempt_id = Replay.send(:normalize_identity, attempt_id, "attempt id")
          @operation_id = Replay.send(:normalize_identity, operation_id, "operation id")
          @provider_id = Replay.send(:normalize_identity, provider_id, "provider id")
          @role = RubyRouting::Enum.normalize(role, RubyRouting::DecisionProposal::ROLES, "replay attempt role")
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
