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

    assert_equal :success, result.status
    assert_equal({ "A" => 1 }, live.primary_assignment_measure_by_provider)
    assert_equal({ "A" => 1, "B" => 1 }, live.assignment_measure_by_provider)
    assert_equal({ "B" => 1 }, live.settlement_measure_by_provider)
    assert_equal({ "A" => 1, "B" => 1 }, live.attempt_count_by_provider)
    assert_equal 0, live.first_attempt_success_count
    assert_equal 1, live.eventual_success_count
    assert_equal 1, live.fallback_recovery_count
    assert_equal({ "A" => 1 }, live.provider_failure_count)
    assert_equal live.to_h, replay.to_h
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
    coordinator.apply_observation(late_success)
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)

    assert_equal :success, coordinator.payout_snapshot(payout.id).status
    assert_equal({ "B" => 1 }, analytics.settlement_measure_by_provider)
    assert_equal 0, analytics.first_attempt_success_count
    assert_equal 1, coordinator.facts.count { |fact| fact.payload[:applied] == false }
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
end
