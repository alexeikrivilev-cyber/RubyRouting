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
    live = coordinator.quality_snapshot("A", currency: "RUB", as_of: as_of)
    replay = coordinator.quality_projection.snapshot("A", currency: "RUB", as_of: as_of)

    assert_equal({ successful_samples: 0, failed_samples: 2 },
      live.to_h.slice(:successful_samples, :failed_samples))
    assert_equal Rational(1, 4), live.score
    assert_equal live.to_h, replay.to_h
    assert_equal 4, coordinator.facts.count { |fact| fact.type == :quality_signal }
  end

  def test_application_quality_query_uses_current_time_for_staleness
    clock = TestSupport::ControlledClock.new
    quality_policy = RubyRouting::Routing::QualityPolicy.new(
      minimum_samples: 1,
      max_evidence_age_seconds: 10
    )
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      quality_policy: quality_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "quality-query-time",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: {
        "A" => TestSupport::Simulator::ScriptedProvider.new(
          provider_id: "A",
          steps: [TestSupport::Simulator::Step.success]
        )
      }
    )

    result = service.submit(
      intent: RubyRouting::PayoutIntent.new(
        id: "quality-query-time-payout",
        money: RubyRouting::Money.new(1, "RUB")
      ),
      policy: policy
    )

    queried = service.queries.quality(currency: "RUB").snapshot("A")
    assert_equal 1, queried.successful_samples
    assert_equal coordinator.quality_snapshot("A", currency: "RUB", as_of: clock.now).to_h,
      queried.to_h

    clock.advance(11)
    stale = service.queries.quality.snapshot("A", currency: "RUB")
    assert_equal 0, stale.sample_count
    refute stale.authoritative?
    assert_equal :success, result.status
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
    live = coordinator.quality_snapshot("A", context: { labels: ["retail"] }, currency: "RUB", as_of: as_of)
    replay = coordinator.quality_projection.snapshot("A", context: { labels: ["retail"] }, currency: "RUB", as_of: as_of)

    assert_equal ["retail"], quality_fact.payload.fetch(:context_key)
    assert_equal :context, live.evidence_scope
    assert_equal live.to_h, replay.to_h
  end

  def test_typed_route_quality_timestamp_survives_restart_and_replay
    clock = TestSupport::ControlledClock.new(start_time: Time.utc(2026, 8, 31, 12, 0, 0))
    quality_policy = RubyRouting::Routing::QualityPolicy.new(
      minimum_samples: 1,
      max_evidence_age_seconds: 60,
      route_minimum_samples: 1
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
    live = restored.quality_snapshot("A", routing_context: route, currency: "RUB", as_of: as_of)
    replay = restored.quality_projection.snapshot("A", routing_context: route, currency: "RUB", as_of: as_of)

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
    stale = restored.quality_snapshot("A", routing_context: route, currency: "RUB")
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

  def test_mixed_age_route_quality_has_live_replay_restart_parity
    clock = TestSupport::ControlledClock.new(start_time: Time.utc(2026, 8, 31, 12, 0, 0))
    quality_policy = RubyRouting::Routing::QualityPolicy.new(
      minimum_samples: 1,
      evidence_window: 10,
      max_evidence_age_seconds: 10,
      route_minimum_samples: 1
    )
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [provider],
      quality_policy: quality_policy,
      clock: clock
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "quality-mixed-age",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    route = RubyRouting::RoutingContext.new(payment_method: :card, rail: :instant)
    outcomes = [
      RubyRouting::NormalizedOutcome.success(attribution: :provider),
      RubyRouting::NormalizedOutcome.success(attribution: :provider)
    ]

    outcomes.each_with_index do |outcome, index|
      payout = RubyRouting::PayoutIntent.new(
        id: "quality-mixed-age-old-#{index}",
        money: RubyRouting::Money.new(100, "RUB"),
        routing_context: route
      )
      commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      coordinator.mark_attempt_started(commit)
      coordinator.apply_observation(
        RubyRouting::ProviderObservation.new(
          observation_id: "quality-mixed-age-old-observation-#{index}",
          payout_id: payout.id,
          provider_id: "A",
          operation_id: commit.proposal.operation_id,
          attempt_id: commit.proposal.attempt_id,
          outcome: outcome,
          observed_at: clock.now
        )
      )
    end

    clock.advance(20)
    payout = RubyRouting::PayoutIntent.new(
      id: "quality-mixed-age-fresh",
      money: RubyRouting::Money.new(100, "RUB"),
      routing_context: route
    )
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "quality-mixed-age-fresh-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.temporary_provider_failure(attribution: :provider),
        observed_at: clock.now
      )
    )

    as_of = clock.now
    live = coordinator.quality_snapshot("A", routing_context: route, currency: "RUB", as_of: as_of)
    replay = coordinator.quality_projection.snapshot("A", routing_context: route, currency: "RUB", as_of: as_of)
    restored = RubyRouting::State::Coordinator.from_facts(
      facts: coordinator.facts,
      opportunities: [provider],
      clock: clock
    )
    restart = restored.quality_snapshot("A", routing_context: route, currency: "RUB", as_of: as_of)

    assert_equal 0, live.successful_samples
    assert_equal 1, live.failed_samples
    assert_equal Rational(1, 3), live.score
    assert_equal live.to_h, replay.to_h
    assert_equal live.to_h, restart.to_h
  end

  def test_currency_scoped_route_quality_survives_replay_and_restart
    clock = TestSupport::ControlledClock.new(start_time: Time.utc(2026, 8, 31, 12, 0, 0))
    quality_policy = RubyRouting::Routing::QualityPolicy.new(minimum_samples: 2)
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [provider],
      quality_policy: quality_policy,
      clock: clock
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "quality-currency-route",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    route = RubyRouting::RoutingContext.new(payment_method: :card, rail: :instant)
    cases = [
      ["USD", :success],
      ["USD", :success],
      ["EUR", :failure],
      ["EUR", :failure]
    ]

    cases.each_with_index do |(currency, outcome_kind), index|
      payout = RubyRouting::PayoutIntent.new(
        id: "quality-currency-route-#{index}",
        money: RubyRouting::Money.new(100, currency),
        routing_context: route
      )
      commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      coordinator.mark_attempt_started(commit)
      outcome = if outcome_kind == :success
        RubyRouting::NormalizedOutcome.success(attribution: :provider)
      else
        RubyRouting::NormalizedOutcome.temporary_provider_failure(
          attribution: :provider,
          safe_to_release: true
        )
      end
      coordinator.apply_observation(
        RubyRouting::ProviderObservation.new(
          observation_id: "quality-currency-route-observation-#{index}",
          payout_id: payout.id,
          provider_id: "A",
          operation_id: commit.proposal.operation_id,
          attempt_id: commit.proposal.attempt_id,
          outcome: outcome
        )
      )
    end

    as_of = clock.now
    usd = coordinator.quality_snapshot("A", routing_context: route, currency: "USD", as_of: as_of)
    eur = coordinator.quality_snapshot("A", routing_context: route, currency: "EUR", as_of: as_of)
    quality_facts = coordinator.facts.select { |fact| fact.type == :quality_signal }

    assert_equal ["EUR", "EUR", "USD", "USD"], quality_facts.map { |fact| fact.payload.fetch(:currency) }.sort
    assert_equal Rational(3, 4), usd.score
    assert_equal Rational(1, 4), eur.score
    assert_equal :route, usd.evidence_scope
    assert_equal :route, eur.evidence_scope

    replay_usd = coordinator.quality_projection.snapshot("A", routing_context: route, currency: "USD", as_of: as_of)
    replay_eur = coordinator.quality_projection.snapshot("A", routing_context: route, currency: "EUR", as_of: as_of)
    assert_equal usd.to_h, replay_usd.to_h
    assert_equal eur.to_h, replay_eur.to_h

    restored = RubyRouting::State::Coordinator.from_facts(
      facts: coordinator.facts,
      opportunities: [provider],
      clock: clock
    )
    assert_equal usd.to_h, restored.quality_snapshot("A", routing_context: route, currency: "USD", as_of: as_of).to_h
    assert_equal eur.to_h, restored.quality_snapshot("A", routing_context: route, currency: "EUR", as_of: as_of).to_h
    assert_equal 0, restored.quality_snapshot("A", routing_context: route, currency: "GBP", as_of: as_of).sample_count
  end
end
