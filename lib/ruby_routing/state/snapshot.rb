# frozen_string_literal: true

module RubyRouting
  module State
    class AttemptSnapshot
      PHASES = %i[committed dispatching resolving pending unknown released settled terminated reconciliation_blocked].freeze

      attr_reader :attempt_id, :operation_id, :provider_id, :role, :outcome, :measure,
                  :phase, :contract, :last_observation_sequence, :committed_at

      def initialize(attempt_id:, operation_id:, provider_id:, role:, outcome: nil, measure: nil,
                     phase: :committed, contract: nil, last_observation_sequence: nil,
                     committed_at: nil)
        @attempt_id = normalize_id(attempt_id, "attempt id")
        @operation_id = normalize_id(operation_id, "operation id")
        @provider_id = normalize_id(provider_id, "provider id")
        @role = normalize_role(role)
        @outcome = outcome
        unless outcome.nil? || outcome.is_a?(RubyRouting::NormalizedOutcome)
          raise ArgumentError, "outcome must be NormalizedOutcome or nil"
        end
        unless measure.nil? || (measure.is_a?(Integer) && measure >= 0)
          raise ArgumentError, "measure must be a non-negative Integer or nil"
        end
        @measure = measure
        @phase = RubyRouting::Enum.normalize(phase, PHASES, "operation phase")
        unless contract.nil? || contract.is_a?(RubyRouting::ProviderOperationContract)
          raise ArgumentError, "contract must be ProviderOperationContract"
        end
        if contract && contract.provider_id != @provider_id
          raise ArgumentError, "contract provider id must match attempt provider id"
        end
        @contract = contract
        unless last_observation_sequence.nil? ||
               (last_observation_sequence.is_a?(Integer) && last_observation_sequence >= 0)
          raise ArgumentError, "last_observation_sequence must be a non-negative Integer or nil"
        end
        @last_observation_sequence = last_observation_sequence
        unless committed_at.nil? || committed_at.is_a?(Time)
          raise ArgumentError, "committed_at must be a Time or nil"
        end
        @committed_at = committed_at&.freeze
        freeze
      end

      def with_operation_state(phase:, contract: self.contract)
        self.class.new(
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

      private

      def normalize_id(value, label)
        RubyRouting::Identity.normalize(value, label)
      end

      def normalize_role(value)
        RubyRouting::Enum.normalize(value, %i[primary recovery], "attempt role")
      end
    end

    class PayoutSnapshot
      STATUSES = %i[
        new
        pending
        unknown
        safe_route_failure
        temporary_provider_failure
        terminal_payout_failure
        success
        reversed
        reconciliation_blocked
        deferred
      ].freeze

      attr_reader :intent, :status, :ownership, :last_outcome, :attempts,
                  :primary_provider_id, :settlement_provider_id, :policy_epoch,
                  :policy_scope_key, :policy_fingerprint, :settlement_operation_id,
                  :provider_interaction_count, :resolution_interaction_count, :revision,
                  :conflicts, :reversals, :created_at, :recovery_schedule

      def initialize(intent:, status:, ownership:, last_outcome:, attempts:,
                     primary_provider_id:, settlement_provider_id:, policy_epoch:,
                     policy_scope_key: nil, policy_fingerprint: nil, settlement_operation_id: nil,
                     provider_interaction_count: 0, resolution_interaction_count: 0, revision:,
                     conflicts: [], reversals: [], created_at: nil, recovery_schedule: nil)
        unless intent.is_a?(RubyRouting::PayoutIntent)
          raise ArgumentError, "intent must be PayoutIntent"
        end
        @intent = intent
        @status = RubyRouting::Enum.normalize(status, STATUSES, "payout state")

        unless ownership.nil? || ownership.is_a?(RubyRouting::EconomicOwnership)
          raise ArgumentError, "ownership must be EconomicOwnership or nil"
        end
        if ownership && ownership.payout_id != intent.id
          raise ArgumentError, "ownership payout id must match intent id"
        end
        @ownership = ownership
        unless recovery_schedule.nil? || recovery_schedule.is_a?(RubyRouting::RecoverySchedule)
          raise ArgumentError, "recovery_schedule must be RecoverySchedule or nil"
        end
        if recovery_schedule && ownership.nil?
          raise ArgumentError, "recovery_schedule requires economic ownership"
        end
        if recovery_schedule && !%i[pending unknown].include?(@status)
          raise ArgumentError, "recovery_schedule requires an unresolved payout"
        end
        if recovery_schedule && (
          recovery_schedule.operation_id != ownership.operation_id ||
          recovery_schedule.attempt_id != ownership.attempt_id ||
          recovery_schedule.provider_id != ownership.provider_id
        )
          raise ArgumentError, "recovery_schedule must reference current ownership"
        end
        @recovery_schedule = recovery_schedule
        unless last_outcome.nil? || last_outcome.is_a?(RubyRouting::NormalizedOutcome)
          raise ArgumentError, "last_outcome must be NormalizedOutcome or nil"
        end
        @last_outcome = last_outcome
        @attempts = normalize_attempts(attempts)
        if ownership && !@attempts.any? do |attempt|
          attempt.operation_id == ownership.operation_id && attempt.attempt_id == ownership.attempt_id &&
            attempt.provider_id == ownership.provider_id
        end
          raise ArgumentError, "ownership must reference an attempt in the snapshot"
        end
        @primary_provider_id = normalize_optional_id(primary_provider_id, "primary provider id")
        @settlement_provider_id = normalize_optional_id(settlement_provider_id, "settlement provider id")
        @settlement_operation_id = normalize_optional_id(settlement_operation_id, "settlement operation id")
        @policy_epoch = normalize_optional_id(policy_epoch, "policy epoch")
        @policy_scope_key = normalize_policy_scope_key(policy_scope_key)
        @policy_fingerprint = normalize_optional_id(policy_fingerprint, "policy fingerprint")
        @provider_interaction_count = normalize_non_negative_integer(
          provider_interaction_count,
          "provider_interaction_count"
        )
        @resolution_interaction_count = normalize_non_negative_integer(
          resolution_interaction_count,
          "resolution_interaction_count"
        )
        unless revision.is_a?(Integer) && revision >= 0
          raise ArgumentError, "revision must be a non-negative Integer"
        end
        @revision = revision
        @conflicts = normalize_conflicts(conflicts, intent.id)
        @reversals = normalize_reversals(reversals, intent.id)
        unless created_at.nil? || created_at.is_a?(Time)
          raise ArgumentError, "created_at must be a Time or nil"
        end
        @created_at = created_at&.freeze
        freeze
      end

      def id
        intent.id
      end

      def attempt_count
        attempts.length
      end

      def provider_switch_count
        attempts.map(&:provider_id).each_cons(2).count { |left, right| left != right }
      end

      def money_moving_provider_ids
        attempts.map(&:provider_id).uniq.freeze
      end

      def current_operation
        return nil unless ownership

        attempts.find { |attempt| attempt.operation_id == ownership.operation_id }
      end

      def current_operation_phase
        current_operation&.phase
      end

      def current_operation_contract
        current_operation&.contract
      end

      def unresolved?
        !ownership.nil?
      end

      def next_action
        recovery_schedule&.action
      end

      def next_action_at
        recovery_schedule&.next_action_at
      end

      def next_action_due?(as_of:)
        recovery_schedule ? recovery_schedule.due?(as_of: as_of) : false
      end

      def final?
        %i[success terminal_payout_failure reversed].include?(status)
      end

      private

      def normalize_attempts(value)
        values = RubyRouting::Collection.to_array(value, "attempts")
        unless values.all? { |attempt| attempt.is_a?(AttemptSnapshot) }
          raise ArgumentError, "attempts must contain AttemptSnapshot values"
        end
        attempt_ids = values.map(&:attempt_id)
        operation_ids = values.map(&:operation_id)
        if attempt_ids.uniq.length != attempt_ids.length || operation_ids.uniq.length != operation_ids.length
          raise ArgumentError, "attempts must have unique attempt and operation identities"
        end

        values.freeze
      end

      def normalize_optional_id(value, label)
        return nil if value.nil?

        RubyRouting::Identity.normalize(value, label)
      end

      def normalize_policy_scope_key(value)
        return nil if value.nil?

        values = RubyRouting::Collection.to_array(value, "policy_scope_key")
        unless values.length == 3
          raise ArgumentError, "policy_scope_key must contain policy id, epoch and scope"
        end

        values.map.with_index do |part, index|
          normalize_optional_id(part, "policy scope key part #{index}")
        end.freeze
      end

      def normalize_non_negative_integer(value, label)
        unless value.is_a?(Integer) && value >= 0
          raise ArgumentError, "#{label} must be a non-negative Integer"
        end

        value
      end

      def normalize_conflicts(value, payout_id)
        values = RubyRouting::Collection.to_array(value, "conflicts")
        unless values.all? { |conflict| conflict.is_a?(RubyRouting::EconomicConflict) }
          raise ArgumentError, "conflicts must contain EconomicConflict values"
        end
        unless values.all? { |conflict| conflict.payout_id == payout_id }
          raise ArgumentError, "conflict payout id must match intent id"
        end

        values.freeze
      end

      def normalize_reversals(value, payout_id)
        values = RubyRouting::Collection.to_array(value, "reversals")
        unless values.all? { |reversal| reversal.is_a?(RubyRouting::SettlementReversal) }
          raise ArgumentError, "reversals must contain SettlementReversal values"
        end
        unless values.all? { |reversal| reversal.payout_id == payout_id }
          raise ArgumentError, "reversal payout id must match intent id"
        end

        values.freeze
      end
    end

    class CapacitySnapshot
      attr_reader :provider_id, :budget, :used_slots, :used_count, :used_amount_minor

      def initialize(provider_id:, budget:, used_slots:, used_count:, used_amount_minor:)
        @provider_id = normalize_provider_id(provider_id)
        unless budget.nil? || budget.is_a?(RubyRouting::CapacityBudget)
          raise ArgumentError, "budget must be CapacityBudget or nil"
        end

        @budget = budget
        @used_slots = normalize_non_negative_integer(used_slots, "used_slots")
        @used_count = normalize_non_negative_integer(used_count, "used_count")
        unless @used_slots == @used_count
          raise ArgumentError, "capacity snapshot slots and count must describe the same in-flight exposure"
        end
        @used_amount_minor = normalize_non_negative_integer(used_amount_minor, "used_amount_minor")
        freeze
      end

      def available_for?(money)
        return true if budget.nil?

        budget.allows?(
          money,
          used_slots: used_slots,
          used_count: used_count,
          used_amount_minor: used_amount_minor
        )
      end

      private

      def normalize_provider_id(provider_id)
        RubyRouting::Identity.normalize(provider_id, "provider id")
      end

      def normalize_non_negative_integer(value, label)
        unless value.is_a?(Integer) && value >= 0
          raise ArgumentError, "#{label} must be a non-negative Integer"
        end

        value
      end
    end

    class ThroughputSnapshot
      attr_reader :provider_id, :budget, :consumed_at

      def initialize(provider_id:, budget:, consumed_at:)
        @provider_id = RubyRouting::Identity.normalize(provider_id, "provider id")
        unless budget.nil? || budget.is_a?(RubyRouting::ThroughputBudget)
          raise ArgumentError, "budget must be ThroughputBudget or nil"
        end
        @budget = budget
        @consumed_at = RubyRouting::Collection.to_array(consumed_at, "consumed_at").map do |value|
          unless value.is_a?(Time)
            raise ArgumentError, "consumed_at must contain Time values"
          end

          value.freeze
        end.freeze
        freeze
      end

      def consumed_count
        consumed_at.length
      end

      def remaining_operations
        return nil unless budget

        [budget.max_operations - consumed_count, 0].max
      end

      def available?
        budget.nil? || consumed_count < budget.max_operations
      end

      def to_h
        {
          budget: budget&.to_h,
          consumed_count: consumed_count,
          remaining_operations: remaining_operations,
          consumed_at: consumed_at
        }.freeze
      end
    end

    class DecisionCommit
      attr_reader :proposal, :request, :payout

      def initialize(proposal:, request:, payout:)
        @proposal = proposal
        @request = request
        @payout = payout
        freeze
      end
    end

    class ObservationApplication
      attr_reader :payout, :next_action, :duplicate, :conflict

      def initialize(payout:, next_action:, duplicate: false, conflict: false)
        @payout = payout
        @next_action = next_action.is_a?(Symbol) ? next_action : next_action.to_s.freeze
        @duplicate = !!duplicate
        @conflict = !!conflict
        freeze
      end
    end
  end
end
