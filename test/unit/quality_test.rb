# frozen_string_literal: true

require_relative "../test_helper"

class QualityTest < Minitest::Test
  def test_quality_counts_only_mature_provider_attributed_terminal_evidence
    controller = RubyRouting::Routing::QualityController.new(
      policy: RubyRouting::Routing::QualityPolicy.new(minimum_samples: 2)
    )

    controller.observe(
      provider_id: "A",
      outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
    )
    controller.observe(
      provider_id: "A",
      outcome: RubyRouting::NormalizedOutcome.terminal_payout_failure(attribution: :recipient)
    )
    controller.observe(
      provider_id: "A",
      outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
    )
    controller.observe(
      provider_id: "A",
      outcome: RubyRouting::NormalizedOutcome.temporary_provider_failure(attribution: :provider)
    )

    snapshot = controller.snapshot("A")

    assert_equal 1, snapshot.successful_samples
    assert_equal 1, snapshot.failed_samples
    assert_equal 2, snapshot.sample_count
    assert snapshot.mature?
    assert_equal Rational(1, 2), snapshot.score
    assert_equal 2, snapshot.confidence
  end

  def test_quality_is_a_lower_priority_optimizer_stage_inside_allocation_ties
    policy = RubyRouting::RoutingPolicy.new(
      id: "quality-optimizer",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      ranking: RubyRouting::RankingPolicy.new(priority_by_provider: { "B" => 100 })
    )
    allocation = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )
    quality = {
      "A" => RubyRouting::Routing::ProviderQualitySnapshot.new(
        provider_id: "A", successful_samples: 2, failed_samples: 0
      ),
      "B" => RubyRouting::Routing::ProviderQualitySnapshot.new(
        provider_id: "B", successful_samples: 0, failed_samples: 2
      )
    }

    decision = RubyRouting::Routing::ConstrainedOptimizer.choose(
      policy: policy,
      allocation: allocation,
      quality: quality
    )

    assert_equal %w[A B], allocation.allocation_tie_candidates
    assert_equal "A", decision.chosen_provider
  end

  def test_quality_partitions_context_cohorts_and_falls_back_to_mature_global_evidence
    controller = RubyRouting::Routing::QualityController.new(
      policy: RubyRouting::Routing::QualityPolicy.new(minimum_samples: 2)
    )
    success = RubyRouting::NormalizedOutcome.success(attribution: :provider)
    failure = RubyRouting::NormalizedOutcome.temporary_provider_failure(attribution: :provider)

    controller.observe(provider_id: "A", context: { labels: ["retail"] }, outcome: success)
    controller.observe(provider_id: "A", context: { labels: ["wholesale"] }, outcome: failure)

    retail = controller.snapshot("A", context: { labels: ["retail"] })
    wholesale = controller.snapshot("A", context_key: ["wholesale"])

    assert_equal :global, retail.evidence_scope
    assert_equal [], retail.context_key
    assert_equal Rational(1, 2), retail.score
    assert_equal :global, wholesale.evidence_scope
    assert_equal Rational(1, 2), wholesale.score

    controller.observe(provider_id: "A", context: { labels: ["retail"] }, outcome: success)
    retail = controller.snapshot("A", context: { labels: ["retail"] })

    assert_equal :context, retail.evidence_scope
    assert_equal ["retail"], retail.context_key
    assert_equal Rational(1, 1), retail.score
    assert_equal 2, retail.confidence
  end

  def test_quality_public_collections_accept_each_only_enumerables
    controller = RubyRouting::Routing::QualityController.new
    snapshots = controller.snapshots(
      TestSupport::EachOnlyCollection.new(["B", "A"]),
      context_key: TestSupport::EachOnlyCollection.new(["retail"])
    )
    snapshot = RubyRouting::Routing::ProviderQualitySnapshot.new(
      provider_id: "A",
      context_key: TestSupport::EachOnlyCollection.new(["retail"])
    )

    assert_equal %w[A B], snapshots.keys
    assert_equal ["retail"], snapshot.context_key
  end

  def test_quality_provider_snapshot_boundaries_canonicalize_padded_each_only_ids
    controller = RubyRouting::Routing::QualityController.new

    snapshots = controller.snapshots(TestSupport::EachOnlyCollection.new([" A ", "A"]))

    assert_equal ["A"], snapshots.keys
    assert_equal "A", snapshots.fetch("A").provider_id
    assert_equal "A", RubyRouting::Routing::ProviderQualitySnapshot.new(provider_id: " A ").provider_id
    assert_raises(ArgumentError) do
      RubyRouting::Routing::ProviderQualitySnapshot.new(provider_id: " ")
    end
  end

  def test_quality_snapshots_require_valid_counters_and_canonical_context_labels
    snapshot = RubyRouting::Routing::ProviderQualitySnapshot.new(
      provider_id: "A",
      context_key: TestSupport::EachOnlyCollection.new([" retail ", "retail"])
    )

    assert_equal ["retail"], snapshot.context_key
    assert_raises(ArgumentError) do
      RubyRouting::Routing::ProviderQualitySnapshot.new(provider_id: "A", failed_samples: -1)
    end
    assert_raises(ArgumentError) do
      RubyRouting::Routing::ProviderQualitySnapshot.new(provider_id: "A", successful_samples: 1.5)
    end
    assert_raises(ArgumentError) do
      RubyRouting::Routing::ProviderQualitySnapshot.new(provider_id: "A", minimum_samples: 0)
    end
    assert_raises(ArgumentError) do
      RubyRouting::Routing::ProviderQualitySnapshot.new(provider_id: "A", context_key: [" "])
    end
  end

  def test_quality_evidence_scope_reports_argument_errors_for_non_symbol_like_input
    assert_raises(ArgumentError) do
      RubyRouting::Routing::ProviderQualitySnapshot.new(provider_id: "A", evidence_scope: Object.new)
    end
  end

  def test_coordinator_quality_and_replay_remain_separate_from_fast_health
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A"),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "quality-history",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    payout = RubyRouting::PayoutIntent.new(
      id: "quality-history-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "quality-history-success",
        payout_id: payout.id,
        provider_id: commit.proposal.provider_id,
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )

    assert_equal 1, coordinator.quality_snapshot(commit.proposal.provider_id).successful_samples
    assert_equal coordinator.quality_snapshot(commit.proposal.provider_id).to_h,
      coordinator.quality_projection.snapshot(commit.proposal.provider_id).to_h
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :quality_signal }
    quality_fact = coordinator.facts.find { |fact| fact.type == :quality_signal }
    assert_equal [], quality_fact.payload.fetch(:context_key)
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :health_signal }
    refute coordinator.lifecycle_projection.payouts.key?("system:provider:#{commit.proposal.provider_id}")
  end
end
