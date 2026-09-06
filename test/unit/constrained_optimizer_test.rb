# frozen_string_literal: true

require_relative "../test_helper"

class ConstrainedOptimizerTest < Minitest::Test
  def test_optimizer_prefers_ranking_only_after_allocation_authority_ties
    policy = RubyRouting::RoutingPolicy.new(
      id: "staged-optimizer",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      maximum_shares: { "A" => "1/2" },
      ranking: RubyRouting::RankingPolicy.new(priority_by_provider: { "A" => 100, "B" => 1 })
    )

    allocation = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.new(measures: { "A" => 1, "B" => 1 }),
      incoming_measure: 1
    )
    optimized = RubyRouting::Routing::ConstrainedOptimizer.choose(
      policy: policy,
      allocation: allocation
    )

    assert_equal %w[B], allocation.allocation_tie_candidates
    assert_equal "B", optimized.chosen_provider
    assert_equal false, optimized.optimization_trace.fetch("A").fetch(:allocation_admissible)
    assert_equal true, optimized.optimization_trace.fetch("B").fetch(:allocation_admissible)
    assert_equal true, optimized.optimization_trace.fetch("B").fetch(:selected)
  end

  def test_optimizer_uses_priority_for_an_exact_allocation_tie
    policy = RubyRouting::RoutingPolicy.new(
      id: "priority-tie",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      ranking: RubyRouting::RankingPolicy.new(
        priority_by_provider: { "A" => 1, "B" => 2 },
        cost_minor_by_provider: { "A" => 1, "B" => 100 }
      )
    )

    allocation = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )
    optimized = RubyRouting::Routing::ConstrainedOptimizer.choose(
      policy: policy,
      allocation: allocation
    )

    assert_equal %w[A B], allocation.allocation_tie_candidates
    assert_equal "B", optimized.chosen_provider
    assert_equal %w[A B], optimized.optimization_trace.keys
    assert_equal true, optimized.optimization_trace.fetch("A").fetch(:allocation_admissible)
    assert_equal true, optimized.optimization_trace.fetch("B").fetch(:selected)
  end

  def test_trace_keeps_quality_evidence_and_lexicographic_ranking_key
    policy = RubyRouting::RoutingPolicy.new(
      id: "trace-quality",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    allocation = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )
    quality = {
      " A " => RubyRouting::Routing::ProviderQualitySnapshot.new(
        provider_id: "A", successful_samples: 4, failed_samples: 1
      ),
      "B" => RubyRouting::Routing::ProviderQualitySnapshot.new(
        provider_id: "B", successful_samples: 1, failed_samples: 4
      )
    }

    decision = RubyRouting::Routing::ConstrainedOptimizer.choose(
      policy: policy,
      allocation: allocation,
      quality: quality
    )

    assert_equal "A", decision.chosen_provider
    assert_equal Rational(5, 7), decision.optimization_trace.fetch("A").fetch(:quality).fetch(:score)
    assert_equal decision.optimization_trace.fetch("A").fetch(:ranking_key).first,
      -Rational(5, 7)
    assert_equal false, decision.optimization_trace.fetch("B").fetch(:selected)
  end

  def test_optimizer_rejects_misaligned_or_untyped_quality_evidence
    policy = RubyRouting::RoutingPolicy.new(
      id: "quality-identity",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    allocation = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )

    assert_raises(ArgumentError) do
      RubyRouting::Routing::ConstrainedOptimizer.choose(
        policy: policy,
        allocation: allocation,
        quality: {
          "A" => RubyRouting::Routing::ProviderQualitySnapshot.new(provider_id: "B"),
          "B" => RubyRouting::Routing::ProviderQualitySnapshot.new(provider_id: "B")
        }
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::Routing::ConstrainedOptimizer.choose(
        policy: policy,
        allocation: allocation,
        quality: { "A" => Object.new, "B" => Object.new }
      )
    end
  end
end
