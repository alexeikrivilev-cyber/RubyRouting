# frozen_string_literal: true

module RubyRouting
  module Routing
    # Selects quality/cost/latency/priority only within the allocation
    # authority's tied candidate set. This is intentionally lexicographic:
    # lower-priority objectives cannot trade away share obligations.
    module ConstrainedOptimizer
      module_function

      def choose(policy:, allocation:, quality: nil)
        unless policy.is_a?(RubyRouting::RoutingPolicy)
          raise ArgumentError, "policy must be RoutingPolicy"
        end
        unless allocation.is_a?(RubyRouting::Routing::AllocationDecision)
          raise ArgumentError, "allocation must be AllocationDecision"
        end
        return allocation if allocation.no_route?

        quality = normalize_quality(quality) unless quality.nil?
        candidates = allocation.allocation_tie_candidates
        chosen_provider = candidates.min_by do |provider_id|
          ranking_key(policy, quality, provider_id)
        end
        trace = allocation.candidate_discrepancies.keys.sort.each_with_object({}) do |provider_id, copy|
          allocation_admissible = candidates.include?(provider_id)
          copy[provider_id] = {
            allocation_admissible: allocation_admissible,
            allocation_key: allocation.allocation_key_for(provider_id),
            quality: quality&.fetch(provider_id, nil)&.to_h,
            ranking_key: allocation_admissible ? ranking_key(policy, quality, provider_id) : nil,
            selected: provider_id == chosen_provider
          }.freeze
        end.freeze
        allocation.with_chosen_provider(chosen_provider).with_optimization_trace(trace)
      end

      def ranking_key(policy, quality, provider_id)
        [
          *quality_key(quality, provider_id),
          -policy.ranking.priority_for(provider_id),
          policy.ranking.cost_for(provider_id),
          policy.ranking.latency_for(provider_id),
          provider_id
        ].freeze
      end
      private_class_method :ranking_key

      def quality_key(quality, provider_id)
        return [0, 0] unless quality

        snapshot = quality.fetch(provider_id)
        [-snapshot.score, -snapshot.confidence]
      end
      private_class_method :quality_key

      def normalize_quality(quality)
        unless quality.is_a?(Hash)
          raise ArgumentError, "quality must be a Hash or nil"
        end

        quality.each_with_object({}) do |(provider_id, snapshot), copy|
          normalized_provider_id = provider_id.to_s.strip
          raise ArgumentError, "provider id must be non-empty" if normalized_provider_id.empty?
          if copy.key?(normalized_provider_id)
            raise ArgumentError, "quality contains duplicate provider id"
          end
          unless snapshot.is_a?(RubyRouting::Routing::ProviderQualitySnapshot)
            raise ArgumentError, "quality values must be ProviderQualitySnapshot"
          end
          unless snapshot.provider_id == normalized_provider_id
            raise ArgumentError, "quality snapshot provider id must match its map key"
          end

          copy[normalized_provider_id] = snapshot
        end.freeze
      end
      private_class_method :normalize_quality
    end
  end
end
