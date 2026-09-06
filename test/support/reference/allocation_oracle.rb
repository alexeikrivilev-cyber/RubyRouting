# frozen_string_literal: true

module Reference
  module AllocationOracle
    module_function

    # Deliberately independent from RubyRouting::Routing::Allocation. It
    # enumerates each candidate and computes the resulting weighted L1 error.
    def choose(weights:, measures:, candidates:, incoming_measure:)
      candidate_ids = candidates.map(&:to_s).uniq.sort
      usable = candidate_ids.select { |provider_id| weights.fetch(provider_id, 0).positive? }
      return nil if usable.empty?

      total_weight = usable.sum { |provider_id| weights.fetch(provider_id) }
      scored = usable.map do |candidate|
        proposed = usable.each_with_object({}) do |provider_id, copy|
          copy[provider_id] = measures.fetch(provider_id, 0)
        end
        proposed[candidate] = proposed.fetch(candidate, 0) + incoming_measure
        total_measure = proposed.values.sum
        error = usable.sum do |provider_id|
          actual = proposed.fetch(provider_id)
          expected = Rational(total_measure * weights.fetch(provider_id, 0), total_weight)
          (actual - expected).abs
        end
        [candidate, error]
      end

      scored.min_by { |provider_id, error| [error, provider_id] }.first
    end
  end
end
