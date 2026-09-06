# frozen_string_literal: true

module RubyRouting
  module State
    # Replays and recomputes historical opportunity-evaluation facts against
    # the durable provider, admission, allocation, health and quality state.
    # It records only the validated evaluation on payout state.
    class OpportunityEvaluationFactRestorer
      def initialize(provider_catalog:, admission_ledger:, allocation_ledger:,
                     health_controller:, quality_controller:, policies:, payout_state:,
                     policy_identity:, monotonic_value:, monotonic_reference:,
                     validate_provider_registered_before_fact:, policy_measure_exclusions:,
                     outcome_trace:)
        @provider_catalog = provider_catalog
        @admission_ledger = admission_ledger
        @allocation_ledger = allocation_ledger
        @health_controller = health_controller
        @quality_controller = quality_controller
        @policies = policies
        @payout_state = payout_state
        @policy_identity = policy_identity
        @monotonic_value = monotonic_value
        @monotonic_reference = monotonic_reference
        @validate_provider_registered_before_fact = validate_provider_registered_before_fact
        @policy_measure_exclusions = policy_measure_exclusions
        @outcome_trace = outcome_trace
      end

      def apply(fact)
        return false unless fact.type == :opportunity_evaluated

        validate_opportunity_evaluation!(fact)
        true
      end

      private

      def validate_opportunity_evaluation!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        policy_id = @policy_identity.call(payload, :policy_id)
        policy_epoch = @policy_identity.call(payload, :policy_epoch)
        policy_scope = @policy_identity.call(payload, :policy_scope)
        policy_fingerprint = @policy_identity.call(payload, :policy_fingerprint)
        expected_scope_key = [policy_id, policy_epoch, policy_scope]
        unless state.policy_scope_key == expected_scope_key
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation policy binding does not match #{fact.payout_id}"
        end
        if state.policy_fingerprint && policy_fingerprint != state.policy_fingerprint
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation policy fingerprint does not match #{fact.payout_id}"
        end

        opportunity_ids = provider_id_list(payload.fetch(:opportunities), "opportunity")
        functional_ids = provider_id_list(payload.fetch(:functional_provider_ids), "functional")
        feasible_ids = provider_id_list(payload.fetch(:feasible_provider_ids), "feasible")
        available_provider_ids = payload[:available_provider_ids]
        unless available_provider_ids.nil? || canonical_provider_id_list?(available_provider_ids)
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation has malformed adapter availability context"
        end
        evaluated_at = payload.fetch(:evaluated_at)
        unless evaluated_at.nil? || evaluated_at.is_a?(Time)
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation timestamp must be Time or nil"
        end
        evaluated_monotonic_at = if payload.key?(:evaluated_monotonic_at)
          @monotonic_value.call(payload, :evaluated_monotonic_at)
        elsif evaluated_at
          @monotonic_reference.call(evaluated_at)
        end
        opportunity_ids.each do |provider_id|
          @validate_provider_registered_before_fact.call(fact, provider_id)
        end
        unless (functional_ids - opportunity_ids).empty? && (feasible_ids - functional_ids).empty?
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation provider sets are not nested for #{fact.payout_id}"
        end
        unless payload.fetch(:exclusions).is_a?(Hash) &&
               payload.fetch(:exclusion_codes).is_a?(Hash) &&
               payload.fetch(:allocation_exclusions).is_a?(Hash) &&
               payload.fetch(:capacity).is_a?(Hash) &&
               payload.fetch(:allocation_snapshot).is_a?(Hash)
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation has malformed exclusion or allocation trace"
        end

        capacity = payload.fetch(:capacity)
        unless capacity.keys.sort == opportunity_ids.sort &&
               capacity.values.all? { |trace| trace.is_a?(Hash) }
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation has malformed capacity trace"
        end
        opportunity_ids.each do |provider_id|
          expected = @admission_ledger.call.capacity_trace(
            @provider_catalog.call.fetch(provider_id),
            as_of: evaluated_at,
            as_of_monotonic: evaluated_monotonic_at
          )
          unless capacity.fetch(provider_id) == expected
            raise RubyRouting::State::DurableCorruptionError,
              "opportunity evaluation capacity trace does not match #{provider_id}"
          end
        end

        snapshot = payload.fetch(:allocation_snapshot)
        revision = snapshot.fetch(:revision)
        measures = snapshot.fetch(:measures)
        unless revision.is_a?(Integer) && revision >= 0 && measures.is_a?(Hash) &&
               measures.values.all? { |measure| measure.is_a?(Integer) && measure >= 0 }
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation has malformed allocation snapshot"
        end
        unless snapshot.key?(:key) || payload.key?(:allocation_key)
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation is missing allocation key"
        end
        policy = @policies.call.fetch(state.policy_scope_key) do
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation references missing policy for #{fact.payout_id}"
        end
        expected_key = policy.allocation_key(opportunity_provider_ids: functional_ids)
        recorded_key = snapshot.key?(:key) ? snapshot.fetch(:key) : payload.fetch(:allocation_key)
        expected_snapshot = @allocation_ledger.call.snapshot(
          policy: policy,
          opportunity_provider_ids: functional_ids
        )
        unless recorded_key == expected_key &&
               payload.fetch(:allocation_key) == expected_key &&
               snapshot.fetch(:revision) == expected_snapshot.revision &&
               snapshot.fetch(:measures) == expected_snapshot.measures
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation allocation snapshot does not match #{fact.payout_id}"
        end

        throughput = payload.fetch(:throughput)
        unless throughput.is_a?(Hash) && throughput.keys.sort == opportunity_ids.sort &&
               throughput.values.all? { |budget| budget.nil? || budget.is_a?(Hash) }
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation has malformed throughput trace"
        end
        opportunity_ids.each do |provider_id|
          expected = @provider_catalog.call.fetch(provider_id).throughput&.to_h
          unless throughput.fetch(provider_id) == expected
            raise RubyRouting::State::DurableCorruptionError,
              "opportunity evaluation throughput trace does not match #{provider_id}"
          end
        end

        health = payload.fetch(:health)
        unless health.is_a?(Hash) && health.keys.sort == opportunity_ids.sort &&
               health.values.all? { |snapshot| snapshot.is_a?(Hash) }
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation has malformed health trace"
        end
        opportunity_ids.each do |provider_id|
          unless health.fetch(provider_id) == @health_controller.call.snapshot(provider_id).to_h
            raise RubyRouting::State::DurableCorruptionError,
              "opportunity evaluation health trace does not match #{provider_id}"
          end
        end

        expected_quality = @quality_controller.call.snapshots(
          opportunity_ids,
          context: state.intent.context
        ).transform_values(&:to_h)
        unless payload.fetch(:quality) == expected_quality
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation quality trace does not match #{fact.payout_id}"
        end
        unless payload.fetch(:ranking) == policy.ranking.to_h
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation ranking trace does not match #{fact.payout_id}"
        end
        unless payload.fetch(:health_policy) == @health_controller.call.policy.to_h
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation health policy trace does not match #{fact.payout_id}"
        end
        unless payload.fetch(:static_policy_feasibility) == policy.static_feasibility
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation static policy trace does not match #{fact.payout_id}"
        end
        unless payload.fetch(:previous_outcome) == @outcome_trace.call(state.last_outcome)
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation previous outcome trace does not match #{fact.payout_id}"
        end

        if opportunity_ids.any? { |provider_id| @provider_catalog.call.fetch(provider_id).throughput } &&
           (!evaluated_at.is_a?(Time) || evaluated_monotonic_at.nil?)
          raise RubyRouting::State::DurableCorruptionError,
            "throughput evaluation requires a monotonic evaluation timestamp"
        end

        evaluated_opportunities = opportunity_ids.map do |provider_id|
          opportunity = @provider_catalog.call.fetch(provider_id)
          capacity_trace = capacity.fetch(provider_id)
          throughput_available = opportunity.throughput_available &&
            (opportunity.throughput.nil? ||
             capacity_trace.fetch(:throughput_consumed_count) < opportunity.throughput.max_operations)
          opportunity.with_runtime(
            available: opportunity.available &&
              (available_provider_ids.nil? || available_provider_ids.include?(provider_id)),
            capacity_available: @admission_ledger.call.capacity_available?(opportunity, state.intent),
            health_available: opportunity.health_available && @health_controller.call.snapshot(provider_id).exposed?,
            throughput_available: throughput_available
          )
        end
        expected_eligibility = RubyRouting::Routing::Eligibility.evaluate(
          evaluated_opportunities,
          intent: state.intent,
          policy: policy
        )
        expected_allocation_exclusions = @policy_measure_exclusions.call(
          eligibility: expected_eligibility,
          policy: policy,
          incoming_measure: policy.measure_for(state.intent.money)
        )
        expected_runtime_feasibility = RubyRouting::Routing::RuntimeFeasibility.assess(
          policy: policy,
          eligibility: expected_eligibility,
          attempted_provider_ids: state.attempts.map(&:provider_id),
          measure_exclusions: expected_allocation_exclusions
        )
        unless expected_eligibility.opportunity_provider_ids == opportunity_ids &&
               expected_eligibility.functional_provider_ids == functional_ids &&
               expected_eligibility.feasible_provider_ids == feasible_ids &&
               payload.fetch(:exclusions) == expected_eligibility.exclusions &&
               payload.fetch(:exclusion_codes) == expected_eligibility.exclusion_codes &&
               payload.fetch(:allocation_exclusions) == expected_allocation_exclusions &&
               payload.fetch(:soft_violations) == expected_eligibility.soft_violations &&
               payload.fetch(:runtime_feasibility) == expected_runtime_feasibility.to_h
          raise RubyRouting::State::DurableCorruptionError,
            "opportunity evaluation eligibility does not match #{fact.payout_id}"
        end
        state.latest_opportunity_evaluation = payload
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed opportunity evaluation: #{error.message}"
      end

      def provider_id_list(value, label)
        unless value.is_a?(Array)
          raise RubyRouting::State::DurableCorruptionError,
            "#{label} provider ids must be an array"
        end

        normalized = value.map do |provider_id|
          id = provider_id.to_s.strip
          raise RubyRouting::State::DurableCorruptionError,
            "#{label} provider ids must be non-empty" if id.empty?
          unless provider_id.is_a?(String) && provider_id == id
            raise RubyRouting::State::DurableCorruptionError,
              "#{label} provider ids must be canonical strings"
          end

          id
        end
        unless normalized == normalized.uniq.sort
          raise RubyRouting::State::DurableCorruptionError,
            "#{label} provider ids must be sorted and unique"
        end

        normalized
      end

      def canonical_provider_id_list?(value)
        value.is_a?(Array) &&
          value == value.uniq &&
          value.all? { |provider_id| provider_id.is_a?(String) && !provider_id.empty? && provider_id == provider_id.strip }
      end
    end
  end
end
