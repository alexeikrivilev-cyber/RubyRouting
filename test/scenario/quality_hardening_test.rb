# frozen_string_literal: true

require_relative "../test_helper"

class QualityHardeningTest < Minitest::Test
  def test_full_recent_quality_window_is_durable_and_replayable
    quality_policy = RubyRouting::Routing::QualityPolicy.new(
      minimum_samples: 1,
      evidence_window: 2
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")],
      quality_policy: quality_policy
    )
    routing_policy = RubyRouting::RoutingPolicy.new(
      id: "quality-window",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )

    [
      RubyRouting::NormalizedOutcome.success(attribution: :provider),
      RubyRouting::NormalizedOutcome.success(attribution: :provider),
      RubyRouting::NormalizedOutcome.temporary_provider_failure(
        attribution: :provider,
        safe_to_release: true
      ),
      RubyRouting::NormalizedOutcome.temporary_provider_failure(
        attribution: :provider,
        safe_to_release: true
      )
    ].each_with_index do |outcome, index|
      payout = RubyRouting::PayoutIntent.new(
        id: "quality-window-#{index}",
        money: RubyRouting::Money.new(100, "RUB")
      )
      commit = coordinator.prepare_and_commit_decision(intent: payout, policy: routing_policy)
      coordinator.mark_attempt_started(commit)
      coordinator.apply_observation(
        RubyRouting::ProviderObservation.new(
          observation_id: "quality-window-observation-#{index}",
          payout_id: payout.id,
          provider_id: "A",
          operation_id: commit.proposal.operation_id,
          attempt_id: commit.proposal.attempt_id,
          outcome: outcome
        )
      )
    end

    as_of = coordinator.current_time
    live = coordinator.quality_snapshot("A", as_of: as_of)
    replay = coordinator.quality_projection.snapshot("A", as_of: as_of)

    assert_equal({ successful_samples: 0, failed_samples: 2 },
      live.to_h.slice(:successful_samples, :failed_samples))
    assert_equal Rational(1, 4), live.score
    assert_equal live.to_h, replay.to_h
    assert_equal 4, coordinator.facts.count { |fact| fact.type == :quality_signal }
  end

  def test_sparse_context_quality_fact_preserves_cohort_for_replay
    quality_policy = RubyRouting::Routing::QualityPolicy.new(minimum_samples: 2)
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")],
      quality_policy: quality_policy
    )
    routing_policy = RubyRouting::RoutingPolicy.new(
      id: "quality-context-window",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )

    2.times do |index|
      payout = RubyRouting::PayoutIntent.new(
        id: "quality-context-#{index}",
        money: RubyRouting::Money.new(100, "RUB"),
        context: { labels: ["retail"] }
      )
      commit = coordinator.prepare_and_commit_decision(intent: payout, policy: routing_policy)
      coordinator.mark_attempt_started(commit)
      coordinator.apply_observation(
        RubyRouting::ProviderObservation.new(
          observation_id: "quality-context-observation-#{index}",
          payout_id: payout.id,
          provider_id: "A",
          operation_id: commit.proposal.operation_id,
          attempt_id: commit.proposal.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      )
    end

    quality_fact = coordinator.facts.find { |fact| fact.type == :quality_signal }
    as_of = coordinator.current_time
    live = coordinator.quality_snapshot("A", context: { labels: ["retail"] }, as_of: as_of)
    replay = coordinator.quality_projection.snapshot("A", context: { labels: ["retail"] }, as_of: as_of)

    assert_equal ["retail"], quality_fact.payload.fetch(:context_key)
    assert_equal :context, live.evidence_scope
    assert_equal live.to_h, replay.to_h
  end

  def test_typed_route_quality_timestamp_survives_restart_and_replay
    clock = TestSupport::ControlledClock.new(start_time: Time.utc(2026, 8, 31, 12, 0, 0))
    quality_policy = RubyRouting::Routing::QualityPolicy.new(
      minimum_samples: 1,
      max_evidence_age_seconds: 60
    )
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [provider],
      quality_policy: quality_policy,
      clock: clock
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "quality-route-time",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    context = {
      payment_method: :card,
      rail: :instant,
      destination_kind: :bank_account,
      labels: [:retail]
    }
    payout = RubyRouting::PayoutIntent.new(
      id: "quality-route-time-payout",
      money: RubyRouting::Money.new(100, "RUB"),
      context: context
    )
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "quality-route-time-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )

    route = payout.routing_context
    quality_fact = coordinator.facts.find { |fact| fact.type == :quality_signal }
    restored = RubyRouting::State::Coordinator.from_facts(
      facts: coordinator.facts,
      clock: clock
    )
    as_of = clock.now
    live = restored.quality_snapshot("A", routing_context: route, as_of: as_of)
    replay = restored.quality_projection.snapshot("A", routing_context: route, as_of: as_of)

    assert_equal :route, quality_fact.payload.fetch(:evidence_scope)
    assert_equal route.to_h.merge(labels: []),
      quality_fact.payload.fetch(:routing_context)
    assert_equal clock.now, quality_fact.payload.fetch(:observed_at)
    assert_equal live.to_h, replay.to_h
    assert live.authoritative?

    fresh_payout = RubyRouting::PayoutIntent.new(
      id: "quality-route-time-fresh-evaluation",
      money: RubyRouting::Money.new(100, "RUB"),
      context: context
    )
    fresh_commit = restored.prepare_and_commit_decision(intent: fresh_payout, policy: policy)
    fresh_evaluation = restored.facts.find do |fact|
      fact.type == :opportunity_evaluated && fact.payout_id == fresh_payout.id
    end
    fresh_quality = fresh_evaluation.payload.fetch(:quality).fetch("A")
    assert_equal :route, fresh_quality.fetch(:evidence_scope)
    assert_equal clock.now, fresh_quality.fetch(:last_observed_at)
    assert_equal "A", fresh_commit.proposal.provider_id

    clock.advance(61)
    stale = restored.quality_snapshot("A", routing_context: route)
    refute stale.authoritative?
    assert_equal 0, stale.sample_count

    stale_payout = RubyRouting::PayoutIntent.new(
      id: "quality-route-time-stale-evaluation",
      money: RubyRouting::Money.new(100, "RUB"),
      context: context
    )
    restored.prepare_and_commit_decision(intent: stale_payout, policy: policy)
    stale_evaluation = restored.facts.find do |fact|
      fact.type == :opportunity_evaluated && fact.payout_id == stale_payout.id
    end
    stale_quality = stale_evaluation.payload.fetch(:quality).fetch("A")
    assert_equal 0, stale_quality.fetch(:sample_count)
    assert_equal :global, stale_quality.fetch(:evidence_scope)
  end
end
