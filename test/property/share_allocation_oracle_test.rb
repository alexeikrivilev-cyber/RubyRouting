# frozen_string_literal: true

require_relative "../test_helper"

class ShareAllocationOracleTest < Minitest::Test
  DEFAULT_SEED = 91_204

  def test_generated_share_corridors_match_an_independent_exact_oracle
    seed = Integer(ENV.fetch("RUBY_ROUTING_SEED", DEFAULT_SEED.to_s))
    random = Random.new(seed)

    300.times do |iteration|
      provider_ids = %w[A B C]
      weights = provider_ids.to_h { |provider_id| [provider_id, random.rand(1..5)] }
      measures = provider_ids.to_h { |provider_id| [provider_id, random.rand(0..20)] }
      candidates = provider_ids.select { random.rand(2).zero? }
      candidates = [provider_ids.first] if candidates.empty?
      incoming_measure = random.rand(1..8)
      minimum_shares = random_share_limits(random, provider_ids)
      maximum_shares = provider_ids.to_h { |provider_id| [provider_id, Rational(1, 2)] }
      minimum_shares = {} if minimum_shares.values.sum > 1
      minimum_shares.delete_if { |provider_id, minimum| minimum > maximum_shares.fetch(provider_id, Rational(1, 1)) }
      policy = RubyRouting::RoutingPolicy.new(
        id: "share-oracle",
        epoch: iteration.to_s,
        measure: :count,
        targets: weights,
        minimum_shares: minimum_shares,
        maximum_shares: maximum_shares
      )
      allocation = RubyRouting::Routing::Allocation.choose(
        policy: policy,
        candidates: candidates,
        snapshot: RubyRouting::Routing::AllocationSnapshot.new(measures: measures),
        incoming_measure: incoming_measure,
        accounting_provider_ids: provider_ids
      )

      expected = independent_choice(
        weights: weights,
        measures: measures,
        candidates: candidates,
        incoming_measure: incoming_measure,
        minimum_shares: minimum_shares,
        maximum_shares: maximum_shares
      )

      assert_equal expected, allocation.chosen_provider,
        "seed=#{seed} iteration=#{iteration} weights=#{weights.inspect} measures=#{measures.inspect} " \
        "candidates=#{candidates.inspect} minimum=#{minimum_shares.inspect} maximum=#{maximum_shares.inspect} " \
        "incoming=#{incoming_measure} discrepancies=#{allocation.candidate_discrepancies.inspect} " \
        "post=#{allocation.post_measures.inspect} violations=#{allocation.candidate_share_violations.inspect}"
    end
  end

  private

  def random_share_limits(random, provider_ids)
    provider_ids.each_with_object({}) do |provider_id, limits|
      next if random.rand(2).zero?

      limits[provider_id] = Rational(1, 2)
    end
  end

  def independent_choice(weights:, measures:, candidates:, incoming_measure:, minimum_shares:, maximum_shares:)
    total_weight = weights.values.sum
    candidates.map(&:to_s).uniq.sort.min_by do |provider_id|
      proposed = measures.merge(provider_id => measures.fetch(provider_id, 0) + incoming_measure)
      total_measure = proposed.values.sum
      maximum_violation = 0
      minimum_violation = 0
      discrepancy = proposed.sum do |candidate_provider, actual_measure|
        share = Rational(actual_measure, total_measure)
        maximum = maximum_shares.fetch(candidate_provider, Rational(1, 1))
        minimum = minimum_shares.fetch(candidate_provider, Rational(0, 1))
        maximum_violation += share - maximum if share > maximum
        minimum_violation += minimum - share if share < minimum
        target = Rational(total_measure * weights.fetch(candidate_provider), total_weight)
        (actual_measure - target).abs
      end
      [maximum_violation, minimum_violation, discrepancy, provider_id]
    end
  end
end
