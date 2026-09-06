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
        @attempt_id = attempt_id.to_s.freeze
        @operation_id = operation_id.to_s.freeze
        @provider_id = provider_id.to_s.freeze
        @role = role.to_sym
        @outcome = outcome
        @measure = measure
        @phase = phase.to_sym
        raise ArgumentError, "unsupported operation phase" unless PHASES.include?(@phase)
        unless contract.nil? || contract.is_a?(RubyRouting::ProviderOperationContract)
          raise ArgumentError, "contract must be ProviderOperationContract"
        end
        @contract = contract
        unless last_observation_sequence.nil? ||
               (last_observation_sequence.is_a?(Integer) && last_observation_sequence >= 0)
          raise ArgumentError, "last_observation_sequence must be a non-negative Integer or nil"
        end
        @last_observation_sequence = last_observation_sequence
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
                  :conflicts, :reversals, :created_at

      def initialize(intent:, status:, ownership:, last_outcome:, attempts:,
                     primary_provider_id:, settlement_provider_id:, policy_epoch:,
                     policy_scope_key: nil, policy_fingerprint: nil, settlement_operation_id: nil,
                     provider_interaction_count: 0, resolution_interaction_count: 0, revision:,
                     conflicts: [], reversals: [], created_at: nil)
        @intent = intent
        @status = status.to_sym
        raise ArgumentError, "unsupported payout state" unless STATUSES.include?(@status)

        @ownership = ownership
        @last_outcome = last_outcome
        @attempts = attempts.dup.freeze
        @primary_provider_id = primary_provider_id&.to_s&.freeze
        @settlement_provider_id = settlement_provider_id&.to_s&.freeze
        @settlement_operation_id = settlement_operation_id&.to_s&.freeze
        @policy_epoch = policy_epoch&.to_s&.freeze
        @policy_scope_key = policy_scope_key&.dup&.freeze
        @policy_fingerprint = policy_fingerprint&.to_s&.freeze
        @provider_interaction_count = provider_interaction_count
        @resolution_interaction_count = resolution_interaction_count
        @revision = revision
        @conflicts = conflicts.dup.freeze
        @reversals = reversals.dup.freeze
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

      def final?
        %i[success terminal_payout_failure reversed].include?(status)
      end
    end

    class CapacitySnapshot
      attr_reader :provider_id, :budget, :used_slots, :used_count, :used_amount_minor

      def initialize(provider_id:, budget:, used_slots:, used_count:, used_amount_minor:)
        @provider_id = provider_id.to_s.freeze
        @budget = budget
        @used_slots = used_slots
        @used_count = used_count
        @used_amount_minor = used_amount_minor
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
        @next_action = next_action.to_sym
        @duplicate = !!duplicate
        @conflict = !!conflict
        freeze
      end
    end
  end
end
