# frozen_string_literal: true

require_relative "../test_helper"

class LongStateMachineTest < Minitest::Test
  HISTORY_SEED = 20_260_829
  PAYOUT_COUNT = 64
  UNKNOWN_RESOLUTION_STEPS = 7
  PENDING_RESOLUTION_STEPS = 5

  def test_long_histories_preserve_lifecycle_ownership_and_fresh_restore
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
    policy = RubyRouting::RoutingPolicy.new(
      id: "long-state-machine",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1, "C" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 3,
        max_resolution_interactions: 10,
        max_switches: 2
      )
    )

    PAYOUT_COUNT.times do |history_index|
      payout = RubyRouting::PayoutIntent.new(
        id: "long-state-#{history_index}",
        money: RubyRouting::Money.new(100 + history_index, "RUB")
      )
      drive_history(coordinator, policy, payout, history_index)
      snapshot = coordinator.payout_snapshot(payout.id)
      assert_nil snapshot.ownership, trace(history_index, snapshot)
      assert_includes %i[success terminal_payout_failure], snapshot.status, trace(history_index, snapshot)
    end

    facts = coordinator.facts
    assert_equal (1..facts.length).to_a, facts.map(&:sequence)
    assert_equal 0, coordinator.active_unresolved_owners
    replayed = RubyRouting::Projections::Replay.lifecycle(facts)
    restored = RubyRouting::State::Coordinator.from_facts(
      facts: facts,
      opportunities: opportunities
    )

    PAYOUT_COUNT.times do |history_index|
      payout_id = "long-state-#{history_index}"
      live = coordinator.payout_snapshot(payout_id)
      assert_equal live.status, replayed.payout(payout_id).status, trace(history_index, live)
      assert_equal live.attempts.map(&:operation_id), replayed.payout(payout_id).attempts.map(&:operation_id),
        trace(history_index, live)
      assert_equal live.status, restored.payout_snapshot(payout_id).status, trace(history_index, live)
      assert_nil restored.payout_snapshot(payout_id).ownership, trace(history_index, live)
    end

    assert_equal coordinator.lifecycle_projection.to_h, restored.lifecycle_projection.to_h
    live_allocation = coordinator.allocation_snapshot(policy: policy)
    restored_allocation = restored.allocation_snapshot(policy: policy)
    assert_equal live_allocation.measures, restored_allocation.measures
    assert_equal live_allocation.revision, restored_allocation.revision
  end

  private

  def drive_history(coordinator, policy, payout, history_index)
    initial = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assert_equal :assign, initial.proposal.action, trace(history_index, initial.payout)
    initial_token = coordinator.mark_attempt_started(initial)

    case history_index % 4
    when 0
      UNKNOWN_RESOLUTION_STEPS.times do |step|
        apply(coordinator, initial, payout, :unknown, "unknown-#{step}", interaction_token: initial_token)
        resolution = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
        assert_equal :resolve, resolution.proposal.action, trace(history_index, resolution.payout)
        initial_token = coordinator.mark_resolution_started(resolution)
        initial = resolution
      end
      apply(coordinator, initial, payout, :success, "resolved-success", interaction_token: initial_token)
    when 1
      failure = apply(
        coordinator, initial, payout, :safe_route_failure, "safe-release",
        interaction_token: initial_token
      )
      assert_equal :reroute, failure.next_action, trace(history_index, failure.payout)
      fallback = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      assert_equal :assign, fallback.proposal.action, trace(history_index, fallback.payout)
      refute_equal initial.proposal.provider_id, fallback.proposal.provider_id, trace(history_index, fallback.payout)
      fallback_token = coordinator.mark_attempt_started(fallback)
      apply(coordinator, fallback, payout, :success, "fallback-success", interaction_token: fallback_token)
    when 2
      PENDING_RESOLUTION_STEPS.times do |step|
        apply(coordinator, initial, payout, :pending, "pending-#{step}", interaction_token: initial_token)
        resolution = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
        assert_equal :resolve, resolution.proposal.action, trace(history_index, resolution.payout)
        initial_token = coordinator.mark_resolution_started(resolution)
        initial = resolution
      end
      apply(
        coordinator, initial, payout, :terminal_payout_failure, "terminal-recipient",
        interaction_token: initial_token
      )
    when 3
      apply(coordinator, initial, payout, :success, "immediate-success", interaction_token: initial_token)
    end
  end

  def apply(coordinator, commit, payout, status, label, interaction_token: nil)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "long-state:#{payout.id}:#{label}",
        payout_id: payout.id,
        provider_id: commit.proposal.provider_id,
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.new(
          status: status,
          attribution: status == :terminal_payout_failure ? :recipient : :unknown
        )
      ),
      interaction_token: interaction_token
    )
  end

  def opportunities
    %w[A B C].map do |provider_id|
      RubyRouting::ProviderOpportunity.new(
        provider_id: provider_id,
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )
    end
  end

  def trace(history_index, snapshot)
    "seed=#{HISTORY_SEED} history=#{history_index} status=#{snapshot.status} " \
      "owner=#{snapshot.ownership&.provider_id.inspect} attempts=#{snapshot.attempts.map(&:provider_id).inspect}"
  end
end
