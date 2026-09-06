# frozen_string_literal: true

module RubyRouting
  module Projections
    # Renders durable routing evidence into a product-readable, recipient-safe
    # explanation. This projection never recomputes routing or copies the raw
    # fact payload wholesale.
    class DecisionExplanation
      Entry = Data.define(
        :sequence,
        :evaluation_sequence,
        :policy,
        :opportunities,
        :admission,
        :allocation,
        :optimization,
        :decision,
        :recovery
      ) do
        def initialize(sequence:, evaluation_sequence:, policy:, opportunities:, admission:,
                       allocation:, optimization:, decision:, recovery:)
          super(
            sequence: sequence,
            evaluation_sequence: evaluation_sequence,
            policy: RubyRouting::ImmutableData.deep_freeze(policy),
            opportunities: RubyRouting::ImmutableData.deep_freeze(opportunities),
            admission: RubyRouting::ImmutableData.deep_freeze(admission),
            allocation: RubyRouting::ImmutableData.deep_freeze(allocation),
            optimization: RubyRouting::ImmutableData.deep_freeze(optimization),
            decision: RubyRouting::ImmutableData.deep_freeze(decision),
            recovery: RubyRouting::ImmutableData.deep_freeze(recovery)
          )
        end

        def to_h
          {
            sequence: sequence,
            evaluation_sequence: evaluation_sequence,
            policy: policy,
            opportunities: opportunities,
            admission: admission,
            allocation: allocation,
            optimization: optimization,
            decision: decision,
            recovery: recovery
          }.freeze
        end
      end

      Result = Data.define(
        :status,
        :unresolved,
        :latest_observation,
        :observations,
        :settlement,
        :reversals,
        :conflicts,
        :reconciliation_blocked,
        :next_action,
        :next_action_at
      ) do
        def initialize(status:, unresolved:, latest_observation:, observations:, settlement:,
                       reversals:, conflicts:, reconciliation_blocked:, next_action:,
                       next_action_at:)
          super(
            status: status,
            unresolved: unresolved,
            latest_observation: RubyRouting::ImmutableData.deep_freeze(latest_observation),
            observations: RubyRouting::ImmutableData.deep_freeze(observations),
            settlement: RubyRouting::ImmutableData.deep_freeze(settlement),
            reversals: RubyRouting::ImmutableData.deep_freeze(reversals),
            conflicts: RubyRouting::ImmutableData.deep_freeze(conflicts),
            reconciliation_blocked: RubyRouting::ImmutableData.deep_freeze(reconciliation_blocked),
            next_action: next_action,
            next_action_at: next_action_at&.utc&.freeze
          )
        end

        def to_h
          {
            status: status,
            unresolved: unresolved,
            latest_observation: latest_observation,
            observations: observations,
            settlement: settlement,
            reversals: reversals,
            conflicts: conflicts,
            reconciliation_blocked: reconciliation_blocked,
            next_action: next_action,
            next_action_at: next_action_at
          }.freeze
        end
      end

      attr_reader :payout_id, :decisions, :result

      def self.from_facts(facts, payout_id:)
        source = RubyRouting::Collection.to_array(facts, "facts")
        normalized_payout_id = normalize_identity(payout_id, "payout id")
        ordered = source.select { |fact| fact.payout_id == normalized_payout_id }.sort_by(&:sequence)
        latest_evaluation = nil
        decisions = []
        observations = []
        settlement = nil
        reversals = []
        conflicts = []
        reconciliation_blocked = nil

        ordered.each do |fact|
          case fact.type
          when :opportunity_evaluated
            latest_evaluation = fact
          when :decision_committed
            decisions << entry_for(fact, latest_evaluation)
          when :provider_observed
            observations << observation_for(fact)
          when :settlement_recorded
            settlement = settlement_for(fact)
          when :reversal_recorded
            reversals << reversal_for(fact)
          when :economic_conflict
            conflicts << conflict_for(fact)
          when :reconciliation_blocked
            reconciliation_blocked = reconciliation_for(fact)
          end
        end

        current_snapshot = if ordered.any? { |fact| fact.type == :intent_registered }
          RubyRouting::Projections::Replay.payout(source, normalized_payout_id)
        end
        current_status = current_snapshot&.status
        new(
          payout_id: normalized_payout_id,
          decisions: decisions,
          result: result_for(
            current_status: current_status,
            observations: observations,
            settlement: settlement,
            reversals: reversals,
            conflicts: conflicts,
            reconciliation_blocked: reconciliation_blocked,
            next_action: current_snapshot&.next_action,
            next_action_at: current_snapshot&.next_action_at
          )
        )
      end

      def initialize(payout_id:, decisions:, result:)
        @payout_id = self.class.send(:normalize_identity, payout_id, "payout id")
        @decisions = RubyRouting::Collection.to_array(decisions, "explanation decisions")
          .each do |entry|
            unless entry.is_a?(Entry)
              raise ArgumentError, "explanation decisions must be Entry values"
            end
          end
          .freeze
        unless result.is_a?(Result)
          raise ArgumentError, "explanation result must be Result"
        end

        @result = result
        freeze
      end

      def to_h
        {
          payout_id: payout_id,
          decisions: decisions.map(&:to_h),
          result: result.to_h
        }.freeze
      end

      class << self
        private

        def entry_for(fact, evaluation)
          evaluation_payload = evaluation&.payload || {}
          decision_payload = fact.payload
          runtime_feasibility = evaluation_payload[:runtime_feasibility] || decision_payload[:runtime_feasibility]
          Entry.new(
            sequence: fact.sequence,
            evaluation_sequence: evaluation&.sequence,
            policy: {
              id: decision_payload[:policy_id] || evaluation_payload[:policy_id],
              epoch: decision_payload[:policy_epoch] || evaluation_payload[:policy_epoch],
              scope: decision_payload[:policy_scope] || evaluation_payload[:policy_scope],
              fingerprint: evaluation_payload[:policy_fingerprint],
              measure_kind: decision_payload[:measure_kind] || evaluation_payload[:measure_kind],
              currency: decision_payload[:currency] || evaluation_payload[:currency],
              allocation_key: evaluation_payload[:allocation_key] || decision_payload[:allocation_key]
            },
            opportunities: {
              provider_ids: evaluation_payload[:opportunities] || [],
              functional_provider_ids: evaluation_payload[:functional_provider_ids] || [],
              feasible_provider_ids: evaluation_payload[:feasible_provider_ids] || [],
              exclusions: evaluation_payload[:exclusions] || {},
              exclusion_codes: evaluation_payload[:exclusion_codes] || {},
              soft_constraint_violations: evaluation_payload[:soft_violations] || {},
              static_policy_feasibility: evaluation_payload[:static_policy_feasibility],
              available_provider_ids: evaluation_payload[:available_provider_ids]
            },
            admission: {
              capacity: evaluation_payload[:capacity] || {},
              throughput: evaluation_payload[:throughput] || {},
              health: evaluation_payload[:health] || {},
              health_policy: evaluation_payload[:health_policy],
              runtime_feasibility: runtime_feasibility
            },
            allocation: {
              before: evaluation_payload[:allocation_snapshot],
              allocation_key: evaluation_payload[:allocation_key] || decision_payload[:allocation_key],
              exclusions: evaluation_payload[:allocation_exclusions] || {},
              candidates: decision_payload[:allocation_candidates] || {},
              selected_provider_id: decision_payload[:provider_id],
              selected_discrepancy: decision_payload[:allocation_discrepancy],
              tolerance: decision_payload[:allocation_tolerance],
              share_violations: decision_payload[:allocation_share_violations] || {},
              deviation_cause: decision_payload[:allocation_deviation_cause],
              attribution_semantics: :deterministic_routing_reason,
              deviation_recoverability: decision_payload[:allocation_deviation_recoverability]
            },
            optimization: {
              ranking: evaluation_payload[:ranking] || {},
              quality: evaluation_payload[:quality] || {},
              trace: decision_payload[:optimization_trace] || {}
            },
            decision: {
              action: decision_payload[:action],
              role: decision_payload[:role],
              provider_id: decision_payload[:provider_id],
              operation_id: decision_payload[:operation_id],
              attempt_id: decision_payload[:attempt_id],
              measure: decision_payload[:measure],
              rationale: {
                kind: :deterministic_routing_reason,
                reasons: decision_payload[:reasons] || [],
                reason_codes: decision_payload[:reason_codes] || []
              }
            },
            recovery: {
              role: decision_payload[:role],
              previous_outcome: evaluation_payload[:previous_outcome]
            }
          )
        end

        def observation_for(fact)
          payload = fact.payload
          {
            sequence: fact.sequence,
            observation_id: payload[:observation_id],
            provider_id: payload[:provider_id],
            operation_id: payload[:operation_id],
            attempt_id: payload[:attempt_id],
            status: payload[:status],
            attribution: payload[:attribution],
            safe_to_release: payload[:safe_to_release],
            transport_kind: payload[:transport_kind],
            interaction_duration_seconds: payload[:interaction_duration_seconds],
            observed_at: payload[:observed_at],
            applied: payload[:applied],
            conflict: payload[:conflict]
          }
        end

        def settlement_for(fact)
          payload = fact.payload
          {
            sequence: fact.sequence,
            provider_id: payload[:provider_id],
            operation_id: payload[:operation_id],
            outcome: payload[:outcome],
            measure: payload[:measure],
            settled_at: payload[:settled_at]
          }
        end

        def reversal_for(fact)
          payload = fact.payload
          {
            sequence: fact.sequence,
            reversal_id: payload[:reversal_id],
            provider_id: payload[:provider_id],
            operation_id: payload[:operation_id],
            amount: payload[:amount],
            reason: payload[:reason]
          }
        end

        def conflict_for(fact)
          payload = fact.payload
          {
            sequence: fact.sequence,
            provider_id: payload[:provider_id],
            operation_id: payload[:operation_id],
            attempt_id: payload[:attempt_id],
            reason: payload[:reason]
          }
        end

        def reconciliation_for(fact)
          payload = fact.payload
          {
            sequence: fact.sequence,
            operation_id: payload[:operation_id],
            attempt_id: payload[:attempt_id]
          }
        end

        def result_for(current_status:, observations:, settlement:, reversals:, conflicts:,
                       reconciliation_blocked:, next_action:, next_action_at:)
          status = current_status || if reversals.any?
            :reversed
          elsif settlement
            :success
          elsif reconciliation_blocked
            :reconciliation_blocked
          elsif observations.last
            observations.last.fetch(:status)
          else
            :no_observation
          end
          Result.new(
            status: status,
            unresolved: %i[pending unknown reconciliation_blocked].include?(status),
            latest_observation: observations.last,
            observations: observations,
            settlement: settlement,
            reversals: reversals,
            conflicts: conflicts,
            reconciliation_blocked: reconciliation_blocked,
            next_action: next_action,
            next_action_at: next_action_at
          )
        end

        def normalize_identity(value, label)
          normalized = value.to_s.strip
          raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

          normalized.freeze
        end
      end
    end
  end
end
