# frozen_string_literal: true

module RubyRouting
  module Routing
    class AllocationSnapshot
      attr_reader :measures, :revision

      def self.empty(revision: 0)
        new(measures: {}, revision: revision)
      end

      def initialize(measures:, revision: 0)
        unless measures.is_a?(Hash)
          raise ArgumentError, "measures must be a Hash"
        end
        unless revision.is_a?(Integer) && revision >= 0
          raise ArgumentError, "revision must be a non-negative Integer"
        end

        @measures = measures.each_with_object({}) do |(provider_id, measure), copy|
          normalized_id = normalize_provider_id(provider_id).freeze
          unless measure.is_a?(Integer) && measure >= 0
            raise ArgumentError, "allocation measures must be non-negative Integers"
          end
          raise ArgumentError, "allocation measures contain duplicate provider id" if copy.key?(normalized_id)

          copy[normalized_id] = measure
        end.freeze
        @revision = revision
        freeze
      end

      def total_measure
        measures.values.sum
      end

      def measure_for(provider_id)
        measures.fetch(normalize_provider_id(provider_id), 0)
      end

      def with_commit(provider_id, measure)
        unless measure.is_a?(Integer) && measure >= 0
          raise ArgumentError, "committed measure must be a non-negative Integer"
        end

        normalized_provider_id = normalize_provider_id(provider_id)
        next_measures = measures.merge(normalized_provider_id => measure_for(normalized_provider_id) + measure)
        self.class.new(measures: next_measures, revision: revision + 1)
      end

      private

      def normalize_provider_id(provider_id)
        normalized = provider_id.to_s.strip
        raise ArgumentError, "provider id must be non-empty" if normalized.empty?

        normalized
      end
    end

    class AllocationDecision
      attr_reader :chosen_provider, :candidate_discrepancies, :post_measures,
                  :candidate_share_violations, :incoming_measure, :snapshot_revision,
                  :tolerance, :deviation_cause, :deviation_recoverability,
                  :optimization_trace

      def initialize(chosen_provider:, candidate_discrepancies:, post_measures:,
                     candidate_share_violations: {}, incoming_measure:, snapshot_revision:,
                     tolerance: nil, deviation_cause: nil, deviation_recoverability: nil,
                     optimization_trace: {})
        @chosen_provider = chosen_provider.nil? ? nil : normalize_provider_id(chosen_provider).freeze
        @candidate_discrepancies = normalize_provider_map(
          candidate_discrepancies,
          "candidate discrepancies"
        ).freeze
        @post_measures = normalize_nested_provider_map(
          post_measures,
          "post measures"
        ).transform_values { |measures| freeze_nested(measures) }.freeze
        @candidate_share_violations = normalize_nested_provider_map(
          candidate_share_violations,
          "candidate share violations"
        ).transform_values { |violations| freeze_nested(violations) }.freeze
        @incoming_measure = incoming_measure
        @snapshot_revision = snapshot_revision
        @tolerance = tolerance
        @deviation_cause = deviation_cause
        @deviation_recoverability = normalize_recoverability(deviation_recoverability)
        @optimization_trace = normalize_provider_map(
          optimization_trace,
          "optimization trace"
        ).transform_values { |trace| freeze_nested(trace) }.freeze
        freeze
      end

      def no_route?
        chosen_provider.nil?
      end

      def discrepancy
        return nil if no_route?

        candidate_discrepancies.fetch(chosen_provider)
      end

      def deviation_exceeded?
        !tolerance.nil? && !no_route? && candidate_deviation_exceeded?(chosen_provider)
      end

      def allocation_corridor_satisfied?
        !no_route? && !candidate_deviation_exceeded?(chosen_provider)
      end

      def candidate_deviation_exceeded?(provider_id)
        return false if tolerance.nil?

        candidate_discrepancies.fetch(normalize_provider_id(provider_id)) > tolerance
      end

      def share_violations
        return {}.freeze if no_route?

        candidate_share_violations.fetch(chosen_provider, {}).freeze
      end

      def chosen_provider_share_violations
        share_violations.fetch(chosen_provider, {}).freeze
      end

      def share_corridor_satisfied?
        share_violations.empty?
      end

      # Allocation authority is the prefix of the optimization key. A later
      # optimizer may choose only among candidates with the same allocation
      # obligations/discrepancy result.
      def allocation_key_for(provider_id)
        normalized_provider_id = normalize_provider_id(provider_id)
        share_violations = candidate_share_violations.fetch(normalized_provider_id, {})
        [
          share_violation_total(share_violations, :maximum),
          share_violation_total(share_violations, :minimum),
          candidate_deviation_exceeded?(normalized_provider_id) ? 1 : 0,
          candidate_discrepancies.fetch(normalized_provider_id)
        ].freeze
      end

      def candidate_trace
        candidate_discrepancies.keys.sort.each_with_object({}) do |provider_id, trace|
          trace[provider_id] = {
            discrepancy: candidate_discrepancies.fetch(provider_id),
            share_violations: candidate_share_violations.fetch(provider_id, {}),
            tolerance_exceeded: candidate_deviation_exceeded?(provider_id),
            allocation_key: allocation_key_for(provider_id)
          }.freeze
        end.freeze
      end

      def allocation_tie_candidates
        return [].freeze if no_route?

        best_key = candidate_discrepancies.keys.map { |provider_id| allocation_key_for(provider_id) }.min
        candidate_discrepancies.keys.select { |provider_id| allocation_key_for(provider_id) == best_key }.freeze
      end

      def with_chosen_provider(provider_id)
        normalized_provider_id = provider_id.nil? ? nil : normalize_provider_id(provider_id)
        unless normalized_provider_id.nil? || candidate_discrepancies.key?(normalized_provider_id)
          raise ArgumentError, "chosen provider must be one of the allocation candidates"
        end

        self.class.new(
          chosen_provider: normalized_provider_id,
          candidate_discrepancies: candidate_discrepancies,
          post_measures: post_measures,
          candidate_share_violations: candidate_share_violations,
          incoming_measure: incoming_measure,
          snapshot_revision: snapshot_revision,
          tolerance: tolerance,
          deviation_cause: deviation_cause,
          deviation_recoverability: deviation_recoverability,
          optimization_trace: optimization_trace
        )
      end

      def with_deviation_cause(cause, recoverability: deviation_recoverability)
        self.class.new(
          chosen_provider: chosen_provider,
          candidate_discrepancies: candidate_discrepancies,
          post_measures: post_measures,
          candidate_share_violations: candidate_share_violations,
          incoming_measure: incoming_measure,
          snapshot_revision: snapshot_revision,
          tolerance: tolerance,
          deviation_cause: cause,
          deviation_recoverability: recoverability,
          optimization_trace: optimization_trace
        )
      end

      def with_optimization_trace(trace)
        self.class.new(
          chosen_provider: chosen_provider,
          candidate_discrepancies: candidate_discrepancies,
          post_measures: post_measures,
          candidate_share_violations: candidate_share_violations,
          incoming_measure: incoming_measure,
          snapshot_revision: snapshot_revision,
          tolerance: tolerance,
          deviation_cause: deviation_cause,
          deviation_recoverability: deviation_recoverability,
          optimization_trace: trace
        )
      end

      private

      def normalize_nested_provider_map(value, label)
        normalize_provider_map(value, label).transform_values do |nested|
          normalize_provider_map(nested, "#{label} for provider")
        end
      end

      def normalize_provider_map(value, label)
        unless value.is_a?(Hash)
          raise ArgumentError, "#{label} must be a Hash"
        end

        value.each_with_object({}) do |(provider_id, nested), copy|
          normalized_provider_id = normalize_provider_id(provider_id)
          if copy.key?(normalized_provider_id)
            raise ArgumentError, "#{label} contain duplicate provider id"
          end

          copy[normalized_provider_id] = nested
        end
      end

      def normalize_provider_id(provider_id)
        normalized = provider_id.to_s.strip
        raise ArgumentError, "provider id must be non-empty" if normalized.empty?

        normalized
      end

      def share_violation_total(violations, kind)
        violations.sum { |_provider_id, provider_violations| provider_violations.fetch(kind, 0) }
      end

      def freeze_nested(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), copy|
            copy[freeze_nested(key)] = freeze_nested(nested)
          end.freeze
        when Array
          value.map { |nested| freeze_nested(nested) }.freeze
        when String
          value.dup.freeze
        else
          value.freeze
        end
      end

      def normalize_recoverability(value)
        return nil if value.nil?

        RubyRouting::Enum.normalize(
          value,
          RubyRouting::Routing::Deviation::RECOVERABILITY,
          "deviation recoverability"
        )
      end
    end

    module Allocation
      module_function

      # L1 discrepancy is evaluated after adding the incoming assignment. This
      # makes committed work visible and lets indivisible amounts choose the
      # least-bad achievable state with exact Rational arithmetic.
      def choose(policy:, candidates:, snapshot:, incoming_measure:, accounting_provider_ids: nil)
        unless policy.is_a?(RubyRouting::RoutingPolicy)
          raise ArgumentError, "policy must be RoutingPolicy"
        end
        unless snapshot.is_a?(AllocationSnapshot)
          raise ArgumentError, "snapshot must be AllocationSnapshot"
        end
        unless incoming_measure.is_a?(Integer) && incoming_measure >= 0
          raise ArgumentError, "incoming_measure must be a non-negative Integer"
        end

        normalized_candidates = normalize_provider_ids(candidates, "candidates").select do |provider_id|
          policy.allows_measure?(provider_id, incoming_measure)
        end
        normalized_accounting_provider_ids = normalize_provider_ids(
          accounting_provider_ids || normalized_candidates,
          "accounting_provider_ids"
        )
        weights = policy.weights_for(normalized_accounting_provider_ids)
        candidate_weights = weights.select { |provider_id, _weight| normalized_candidates.include?(provider_id) }
        if candidate_weights.empty?
          return AllocationDecision.new(
            chosen_provider: nil,
            candidate_discrepancies: {},
            post_measures: {},
            candidate_share_violations: {},
            incoming_measure: incoming_measure,
            snapshot_revision: snapshot.revision,
            tolerance: policy.tolerance,
            deviation_cause: :no_feasible_candidate
          )
        end

        total_weight = weights.values.sum
        candidate_discrepancies = {}
        post_measures = {}
        candidate_share_violations = {}

        base_measures = weights.each_key.to_h { |provider_id| [provider_id, snapshot.measure_for(provider_id)] }
        candidate_weights.each_key do |provider_id|
          proposed = base_measures.merge(provider_id => snapshot.measure_for(provider_id) + incoming_measure)
          total_measure = proposed.values.sum
          discrepancy = proposed.sum do |candidate_provider, actual_measure|
            target = Rational(total_measure * policy.weight_for(candidate_provider), total_weight)
            (actual_measure - target).abs
          end

          candidate_discrepancies[provider_id] = discrepancy
          post_measures[provider_id] = proposed.freeze
          candidate_share_violations[provider_id] = policy.share_violations(
            proposed,
            total_measure: total_measure,
            provider_ids: weights.keys
          )
        end

        chosen_provider = candidate_discrepancies.min_by do |provider_id, discrepancy|
          share_violations = candidate_share_violations.fetch(provider_id)
          [
            share_violation_total(share_violations, :maximum),
            share_violation_total(share_violations, :minimum),
            policy.tolerance && discrepancy > policy.tolerance ? 1 : 0,
            discrepancy,
            provider_id
          ]
        end.first
        AllocationDecision.new(
          chosen_provider: chosen_provider,
          candidate_discrepancies: candidate_discrepancies,
          post_measures: post_measures,
          candidate_share_violations: candidate_share_violations,
          incoming_measure: incoming_measure,
          snapshot_revision: snapshot.revision,
          tolerance: policy.tolerance,
          deviation_cause: :optimizer_choice
        )
      end

      def share_violation_total(violations, kind)
        violations.sum { |_provider_id, provider_violations| provider_violations.fetch(kind, 0) }
      end
      private_class_method :share_violation_total

      def normalize_provider_ids(provider_ids, label)
        RubyRouting::Collection.to_array(provider_ids, label).map do |provider_id|
          normalized = provider_id.to_s.strip
          raise ArgumentError, "provider id must be non-empty" if normalized.empty?

          normalized
        end.uniq.sort
      end
      private_class_method :normalize_provider_ids
    end
  end
end
