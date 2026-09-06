# frozen_string_literal: true

require_relative "../test_helper"

class ProjectionReplayTest < Minitest::Test
  def test_primary_assignment_and_settlement_are_distinct_and_replayable
    provider_a = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.safe_failure]
    )
    provider_b = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "B",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities("A", "B"))
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    ).submit(intent: intent("analytics-1"), policy: policy)

    live = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    replay = RubyRouting::Projections::Replay.analytics(coordinator.facts)
    lifecycle = RubyRouting::Projections::Replay.lifecycle(coordinator.facts)
    replayed_payout = lifecycle.payout("analytics-1")

    assert_equal :success, result.status
    assert_equal result.payout.status, replayed_payout.status
    assert_equal result.payout.attempts.map(&:provider_id), replayed_payout.attempts.map(&:provider_id)
    assert_equal result.payout.settlement_provider_id, replayed_payout.settlement_provider_id
    assert_equal payout_signature(result.payout), payout_signature(replayed_payout)
    assert_equal coordinator.lifecycle_projection.to_h, lifecycle.to_h
    assert_equal({ "A" => 1 }, live.primary_assignment_measure_by_provider)
    assert_equal({ "A" => 1, "B" => 1 }, live.assignment_measure_by_provider)
    assert_equal({ "B" => 1 }, live.settlement_measure_by_provider)
    assert_equal({ "A" => 1, "B" => 1 }, live.attempt_count_by_provider)
    assert_equal({ "A" => Rational(1, 2), "B" => Rational(1, 2) }, live.primary_target_measure_by_provider)
    assert_equal({ "A" => Rational(1, 2), "B" => Rational(1, 2) }, live.primary_deviation_measure_by_provider)
    assert_equal({ "analytics-1" => 2 }, live.attempt_count_by_payout)
    assert_equal({ "analytics-1" => 2 }, live.provider_interaction_count_by_payout)
    assert_equal({ "analytics-1" => 1 }, live.provider_switch_count_by_payout)
    assert_equal({ provider: 1 }, live.failure_count_by_attribution)
    assert_equal({ optimizer_choice: { count: 1, measure: 1 } }, live.deviation_by_cause)
    assert_equal 0, live.first_attempt_success_count
    assert_equal 1, live.eventual_success_count
    assert_equal 1, live.fallback_recovery_count
    assert_equal({ "A" => 1 }, live.provider_failure_count)
    assert_equal live.to_h, replay.to_h
  end

  def test_analytics_keeps_typed_transport_failure_and_unresolved_projection
    transport = RubyRouting::ProviderTransportResult.ambiguous_after_possible_send(message: "timeout")
    provider = Class.new do
      define_method(:initiate) { |_request| transport }
      define_method(:resolve) { |_request| transport }
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    app = RubyRouting::Application::Orchestrator.new(coordinator: coordinator, providers: { "A" => provider })

    result = app.submit(intent: intent("analytics-transport"), policy: one_provider_policy)
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)

    assert_equal :unknown, result.status
    assert_equal({ ambiguous_after_possible_send: 1 }, analytics.transport_count_by_kind)
    assert_equal({ unknown: 1 }, analytics.unresolved_count_by_status)
    assert_equal({ "analytics-transport" => 1 }, analytics.attempt_count_by_payout)
  end

  def test_analytics_distinguishes_fallback_attempt_from_successful_recovery
    provider_a = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.safe_failure]
    )
    provider_b = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "B",
      steps: [TestSupport::Simulator::Step.terminal]
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities("A", "B"))
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    ).submit(intent: intent("analytics-fallback-failure"), policy: policy)

    live = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    replay = RubyRouting::Projections::Replay.analytics(coordinator.facts)

    assert_equal :terminal_payout_failure, result.status
    assert_equal 1, live.fallback_recovery_count
    assert_equal 0, live.successful_fallback_recovery_count
    assert_equal 1, live.recovery_attempt_count
    assert_equal live.to_h, replay.to_h
  end

  def test_analytics_preserves_fallback_role_across_idempotent_retry
    provider_a = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    provider_b = RubyRouting::ProviderOpportunity.new(
      provider_id: "B",
      capabilities: RubyRouting::ProviderCapabilities.new(idempotent_retry: true)
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider_a, provider_b])
    payout = intent("analytics-fallback-retry")

    primary = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(primary)
    coordinator.apply_observation(observation(primary, "fallback-retry-primary-failure", :safe_route_failure))

    fallback = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(fallback)
    coordinator.apply_observation(observation(fallback, "fallback-retry-unknown", :unknown, :provider))

    retry_commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assert_equal :retry_same, retry_commit.proposal.action
    coordinator.mark_attempt_started(retry_commit)
    coordinator.apply_observation(observation(retry_commit, "fallback-retry-success", :success, :provider))

    live = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    replay = RubyRouting::Projections::Replay.analytics(coordinator.facts)

    assert_equal :success, coordinator.payout_snapshot(payout.id).status
    assert_equal 1, live.fallback_recovery_count
    assert_equal 1, live.successful_fallback_recovery_count
    assert_equal 1, live.recovery_attempt_count
    assert_equal live.to_h, replay.to_h
  end

  def test_analytics_is_idempotent_for_an_exact_duplicate_observation_fact
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    payout = intent("analytics-duplicate-observation")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation(commit, "duplicate-observation", :success))

    observation_fact = coordinator.facts.find { |fact| fact.type == :provider_observed }
    duplicate = RubyRouting::Fact.new(
      sequence: coordinator.facts.length + 1,
      type: observation_fact.type,
      fact_id: "fact:#{coordinator.facts.length + 1}",
      payout_id: observation_fact.payout_id,
      payload: observation_fact.payload
    )
    analytics = RubyRouting::Projections::Replay.analytics(coordinator.facts)
    duplicated_analytics = RubyRouting::Projections::Replay.analytics(
      coordinator.facts + [duplicate]
    )

    assert_equal 1, analytics.first_attempt_success_count
    assert_equal analytics.to_h, duplicated_analytics.to_h
  end

  def test_analytics_projects_age_for_pending_and_unknown_at_explicit_as_of
    clock = TestSupport::ControlledClock.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    payout = intent("analytics-age")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation(commit, "unknown-age", :unknown, :provider))

    clock.advance(7)
    live = RubyRouting::Projections::Analytics.from_facts(coordinator.facts, as_of: clock.now)
    replay = RubyRouting::Projections::Replay.analytics(coordinator.facts, as_of: clock.now)

    assert_equal({ "analytics-age" => 7 }, live.unresolved_age_seconds_by_payout)
    assert_equal live.to_h, replay.to_h
  end

  def test_lifecycle_replay_preserves_controlled_intent_and_operation_timestamps
    clock = TestSupport::ControlledClock.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    payout = intent("timestamped-lifecycle")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    coordinator.mark_attempt_started(commit)

    live = coordinator.payout_snapshot(payout.id)
    replayed = coordinator.lifecycle_projection.payout(payout.id)

    assert_equal live.created_at, replayed.created_at
    assert_equal live.attempts.first.committed_at, replayed.attempts.first.committed_at
    assert_equal live.attempts.first.phase, replayed.attempts.first.phase
  end

  def test_lifecycle_replay_preserves_policy_identity_for_deferred_route
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A", available: false)]
    )
    payout = intent("deferred-policy-replay")

    result = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    replayed = coordinator.lifecycle_projection.payout(payout.id)

    assert_equal :defer, result.proposal.action
    assert_equal :deferred, result.payout.status
    assert_equal payout_signature(result.payout), payout_signature(replayed)
    assert_equal :deferred, replayed.status
    assert_equal result.payout.policy_epoch, replayed.policy_epoch
    assert_equal result.payout.policy_fingerprint, replayed.policy_fingerprint
  end

  def test_lifecycle_replay_preserves_status_resolution_counters_and_contract
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    payout = intent("resolution-replay")
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, "unknown", :unknown, :provider))
    resolution = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    assert_equal :resolve, resolution.proposal.action
    assert coordinator.mark_resolution_started(resolution)
    coordinator.apply_observation(observation(resolution, "resolved", :success, :provider))

    live = coordinator.payout_snapshot(payout.id)
    replayed = coordinator.lifecycle_projection.payout(payout.id)

    assert_equal payout_signature(live), payout_signature(replayed)
    assert_equal 2, live.provider_interaction_count
    assert_equal 1, live.resolution_interaction_count
  end

  def test_soft_constraint_relaxation_is_typed_in_opportunity_and_decision_facts
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities("A"))
    policy = RubyRouting::RoutingPolicy.new(
      id: "soft-trace",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      soft_constraints: { required_context_labels: ["preferred"] }
    )

    commit = coordinator.prepare_and_commit_decision(intent: intent("soft-trace"), policy: policy)
    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }
    decision = coordinator.facts.find { |fact| fact.type == :decision_committed }

    assert_equal :assign, commit.proposal.action
    assert_includes commit.proposal.reason_codes, :soft_constraint_relaxed
    assert_equal({ "A" => [:required_context_missing] }, evaluation.payload.fetch(:soft_violations))
    assert_equal [:required_context_missing], decision.payload.fetch(:soft_constraint_violations)
  end

  def test_out_of_order_observation_is_recorded_without_regressing_derived_state
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    payout = intent("ordering-1")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    coordinator.mark_attempt_started(commit)

    success = observation(commit, "success", :success)
    delayed_pending = observation(commit, "pending", :pending)
    coordinator.apply_observation(success)
    coordinator.apply_observation(delayed_pending)

    snapshot = coordinator.payout_snapshot(payout.id)
    assert_equal :success, snapshot.status
    assert_nil snapshot.ownership
    assert_equal 2, coordinator.facts.count { |fact| fact.type == :provider_observed }
    assert_equal 1, coordinator.facts.count { |fact| fact.payload[:applied] == false }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :settlement_recorded }
  end

  def test_unordered_pending_after_unknown_cannot_regress_unresolved_state
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    payout = intent("ordering-unknown-1")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    coordinator.mark_attempt_started(commit)

    coordinator.apply_observation(observation(commit, "unknown-first", :unknown))
    delayed_pending = coordinator.apply_observation(observation(commit, "pending-late", :pending))

    assert_equal :unknown, delayed_pending.payout.status
    assert_equal :unknown, delayed_pending.payout.last_outcome.status
    assert_equal 1, coordinator.facts.count { |fact| fact.payload[:applied] == false }
  end

  def test_authoritative_provider_sequence_controls_observation_order
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(authoritative_sequence: true)
      )]
    )
    payout = intent("ordered-sequence")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    coordinator.mark_attempt_started(commit)

    coordinator.apply_observation(observation_with_sequence(commit, "unknown-2", :unknown, 2))
    old = coordinator.apply_observation(observation_with_sequence(commit, "success-1", :success, 1))
    unsequenced = coordinator.apply_observation(observation(commit, "success-without-sequence", :success))
    current = coordinator.apply_observation(observation_with_sequence(commit, "success-3", :success, 3))

    assert_equal :unknown, old.payout.status
    assert_equal :unknown, unsequenced.payout.status
    assert_equal :success, current.payout.status
    assert_equal 2, coordinator.facts.count { |fact| fact.payload[:applied] == false }
  end

  def test_authoritative_provider_rejects_unsequenced_first_event_but_accepts_transport_classification
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(authoritative_sequence: true)
      )]
    )
    payout = intent("unsequenced-first")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    coordinator.mark_attempt_started(commit)

    unsequenced = coordinator.apply_observation(observation(commit, "unsequenced", :success))
    sequenced = coordinator.apply_observation(observation_with_sequence(commit, "sequenced", :success, 1))

    assert_equal :pending, unsequenced.payout.status
    assert_equal :success, sequenced.payout.status
    assert_equal 1, coordinator.facts.count { |fact| fact.payload[:applied] == false }

    transport_payout = intent("transport-first")
    transport_commit = coordinator.prepare_and_commit_decision(
      intent: transport_payout,
      policy: one_provider_policy
    )
    coordinator.mark_attempt_started(transport_commit)
    transport = RubyRouting::ProviderObservation.new(
      observation_id: "obs:transport-first",
      payout_id: transport_payout.id,
      provider_id: "A",
      operation_id: transport_commit.proposal.operation_id,
      attempt_id: transport_commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :unknown),
      transport_kind: :ambiguous_after_possible_send
    )
    transport_application = coordinator.apply_observation(transport)
    assert_equal :unknown, transport_application.payout.status
    assert_equal "A", transport_application.payout.ownership.provider_id
  end

  def test_late_observation_from_released_operation_cannot_change_settlement_analytics
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities("A", "B"))
    payout = intent("late-operation-1")
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, "safe", :safe_route_failure))
    second = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(second)
    coordinator.apply_observation(observation(second, "success", :success))

    late_success = observation(first, "late-success", :success)
    application = coordinator.apply_observation(late_success)
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)

    assert_equal :success, coordinator.payout_snapshot(payout.id).status
    assert_equal({ "B" => 1 }, analytics.settlement_measure_by_provider)
    assert_equal 0, analytics.first_attempt_success_count
    assert_equal 1, coordinator.facts.count { |fact| fact.payload[:applied] == false }
    assert application.conflict
    assert_equal 1, application.payout.conflicts.length
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :economic_conflict }
    replayed = coordinator.lifecycle_projection.payout(payout.id)
    assert_equal application.payout.conflicts.map(&:reason), replayed.conflicts.map(&:reason)
  end

  def test_late_success_after_terminal_release_is_also_an_economic_conflict
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    payout = intent("late-terminal-operation")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation(commit, "terminal", :terminal_payout_failure, :recipient))

    application = coordinator.apply_observation(observation(commit, "late-success", :success, :provider))

    assert application.conflict
    assert_equal :terminal_payout_failure, application.payout.status
    assert_equal 1, application.payout.conflicts.length
  end

  def test_recipient_failure_is_not_counted_as_provider_failure
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    payout = intent("recipient-attribution-1")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation(commit, "recipient-failure", :terminal_payout_failure, :recipient))

    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)

    assert_equal 1, analytics.terminal_failure_count
    assert_empty analytics.provider_failure_count
  end

  def test_post_settlement_reversal_is_separate_and_does_not_reopen_routing
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    payout = intent("reversal-1")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation(commit, "settled", :success))

    reversed = coordinator.record_reversal(
      payout_id: payout.id,
      reversal_id: "return-1",
      provider_id: "A",
      operation_id: commit.proposal.operation_id,
      amount: payout.money,
      reason: :returned
    )

    assert_equal :reversed, reversed.status
    assert_equal :success, reversed.last_outcome.status
    assert_equal 1, reversed.reversals.length
    assert_equal :already_final,
      coordinator.prepare_and_commit_decision(intent: payout, policy: one_provider_policy).proposal.action
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :reversal_recorded }
    replayed = coordinator.lifecycle_projection.payout(payout.id)
    assert_equal payout_signature(coordinator.payout_snapshot(payout.id)), payout_signature(replayed)
    assert_equal :reversed, replayed.status
    assert_equal 1, replayed.reversals.length
  end

  private

  def opportunities(*ids)
    ids.map { |id| RubyRouting::ProviderOpportunity.new(provider_id: id) }
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def policy
    RubyRouting::RoutingPolicy.new(id: "policy", epoch: "1", measure: :count, targets: { "A" => 1, "B" => 1 })
  end

  def one_provider_policy
    RubyRouting::RoutingPolicy.new(id: "policy", epoch: "1", measure: :count, targets: { "A" => 1 })
  end

  def observation(commit, label, status, attribution = :provider)
    RubyRouting::ProviderObservation.new(
      observation_id: "obs:#{label}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(status: status, attribution: attribution)
    )
  end

  def observation_with_sequence(commit, label, status, sequence)
    RubyRouting::ProviderObservation.new(
      observation_id: "obs:#{label}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      sequence: sequence,
      outcome: RubyRouting::NormalizedOutcome.new(status: status, attribution: :provider)
    )
  end

  def payout_signature(payout)
    [
      payout.status,
      payout.revision,
      ownership_signature(payout.ownership),
      outcome_signature(payout.last_outcome),
      payout.attempts.map do |attempt|
        [
          attempt.attempt_id,
          attempt.operation_id,
          attempt.provider_id,
          attempt.role,
          attempt.phase,
          attempt.measure,
          outcome_signature(attempt.outcome),
          attempt.contract && [
            attempt.contract.provider_id,
            attempt.contract.idempotent_retry,
            attempt.contract.status_lookup,
            attempt.contract.idempotency_key,
            attempt.contract.ttl_seconds,
            attempt.contract.deadline_seconds,
            attempt.contract.version,
            attempt.contract.authoritative_sequence
          ],
          attempt.last_observation_sequence,
          attempt.committed_at
        ]
      end,
      payout.primary_provider_id,
      payout.settlement_provider_id,
      payout.settlement_operation_id,
      payout.policy_epoch,
      payout.policy_scope_key,
      payout.policy_fingerprint,
      payout.provider_interaction_count,
      payout.resolution_interaction_count,
      payout.created_at,
      payout.conflicts.map { |conflict| [conflict.provider_id, conflict.operation_id, conflict.reason] },
      payout.reversals.map { |reversal| [reversal.reversal_id, reversal.amount, reversal.reason] }
    ]
  end

  def ownership_signature(ownership)
    ownership && [ownership.provider_id, ownership.operation_id, ownership.attempt_id]
  end

  def outcome_signature(outcome)
    outcome && [outcome.status, outcome.attribution, outcome.provider_reference, outcome.message, outcome.safe_to_release?]
  end
end
