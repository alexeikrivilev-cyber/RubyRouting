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
          normalized_id = provider_id.to_s.freeze
          unless measure.is_a?(Integer) && measure >= 0
            raise ArgumentError, "allocation measures must be non-negative Integers"
          end

          copy[normalized_id] = measure
        end.freeze
        @revision = revision
        freeze
      end

      def total_measure
        measures.values.sum
      end

      def measure_for(provider_id)
        measures.fetch(provider_id.to_s, 0)
      end

      def with_commit(provider_id, measure)
        unless measure.is_a?(Integer) && measure >= 0
          raise ArgumentError, "committed measure must be a non-negative Integer"
        end

        next_measures = measures.merge(provider_id.to_s => measure_for(provider_id) + measure)
        self.class.new(measures: next_measures, revision: revision + 1)
      end
    end

    class AllocationDecision
      attr_reader :chosen_provider, :candidate_discrepancies, :post_measures,
                  :incoming_measure, :snapshot_revision, :tolerance, :deviation_cause

      def initialize(chosen_provider:, candidate_discrepancies:, post_measures:,
                     incoming_measure:, snapshot_revision:, tolerance: nil,
                     deviation_cause: nil)
        @chosen_provider = chosen_provider&.to_s&.freeze
        @candidate_discrepancies = candidate_discrepancies.dup.freeze
        @post_measures = post_measures.dup.freeze
        @incoming_measure = incoming_measure
        @snapshot_revision = snapshot_revision
        @tolerance = tolerance
        @deviation_cause = deviation_cause
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
        !tolerance.nil? && !no_route? && discrepancy > tolerance
      end

      def with_deviation_cause(cause)
        self.class.new(
          chosen_provider: chosen_provider,
          candidate_discrepancies: candidate_discrepancies,
          post_measures: post_measures,
          incoming_measure: incoming_measure,
          snapshot_revision: snapshot_revision,
          tolerance: tolerance,
          deviation_cause: cause
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

        normalized_candidates = candidates.map(&:to_s).uniq.sort.select do |provider_id|
          policy.allows_measure?(provider_id, incoming_measure)
        end
        normalized_accounting_provider_ids = (accounting_provider_ids || normalized_candidates)
          .map(&:to_s).uniq.sort
        weights = policy.weights_for(normalized_accounting_provider_ids)
        candidate_weights = weights.select { |provider_id, _weight| normalized_candidates.include?(provider_id) }
        if candidate_weights.empty?
          return AllocationDecision.new(
            chosen_provider: nil,
            candidate_discrepancies: {},
            post_measures: {},
            incoming_measure: incoming_measure,
            snapshot_revision: snapshot.revision,
            tolerance: policy.tolerance,
            deviation_cause: :no_feasible_candidate
          )
        end

        total_weight = weights.values.sum
        candidate_discrepancies = {}
        post_measures = {}

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
        end

        chosen_provider = candidate_discrepancies.min_by do |provider_id, discrepancy|
          [
            discrepancy,
            -policy.ranking.priority_for(provider_id),
            policy.ranking.cost_for(provider_id),
            policy.ranking.latency_for(provider_id),
            provider_id
          ]
        end.first
        AllocationDecision.new(
          chosen_provider: chosen_provider,
          candidate_discrepancies: candidate_discrepancies,
          post_measures: post_measures,
          incoming_measure: incoming_measure,
          snapshot_revision: snapshot.revision,
          tolerance: policy.tolerance,
          deviation_cause: :optimizer_choice
        )
      end
    end
  end
end
