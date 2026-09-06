# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/reference/allocation_oracle"

class AllocationOracleTest < Minitest::Test
  DEFAULT_SEED = 41_902

  def test_generated_small_states_match_independent_oracle
    seed = Integer(ENV.fetch("RUBY_ROUTING_SEED", DEFAULT_SEED.to_s))
    random = Random.new(seed)

    250.times do |iteration|
      provider_ids = (0...random.rand(1..4)).map { |index| "p#{index}" }
      weights = provider_ids.to_h { |provider_id| [provider_id, random.rand(1..5)] }
      measures = provider_ids.to_h { |provider_id| [provider_id, random.rand(0..30)] }
      candidates = provider_ids.select { random.rand(2).zero? }
      candidates = [provider_ids.first] if candidates.empty?
      incoming_measure = random.rand(1..12)
      measure = random.rand(2).zero? ? :count : :volume
      policy = RubyRouting::RoutingPolicy.new(
        id: "generated",
        epoch: "#{iteration}",
        measure: measure,
        targets: weights,
        currency: measure == :volume ? "RUB" : nil
      )
      production = RubyRouting::Routing::Allocation.choose(
        policy: policy,
        candidates: candidates,
        snapshot: RubyRouting::Routing::AllocationSnapshot.new(measures: measures),
        incoming_measure: incoming_measure
      )
      expected = Reference::AllocationOracle.choose(
        weights: weights,
        measures: measures,
        candidates: candidates,
        incoming_measure: incoming_measure
      )

      assert_equal expected, production.chosen_provider, "seed=#{seed} iteration=#{iteration}"
    end
  end
end
