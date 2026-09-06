# frozen_string_literal: true

require_relative "../test_helper"

class RoutingStateMachineTest < Minitest::Test
  DEFAULT_SEED = 62_407

  def test_generated_cross_feature_histories_preserve_invariants_and_replay
    seed = Integer(ENV.fetch("RUBY_ROUTING_SEED", DEFAULT_SEED.to_s))
    random = Random.new(seed)

    30.times do |history_index|
      health_policy = RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 1,
        probe_limit: 1
      )
      coordinator = RubyRouting::State::Coordinator.new(
        health_policy: health_policy,
        opportunities: [
          RubyRouting::ProviderOpportunity.new(
            provider_id: "A",
            capacity: RubyRouting::CapacityBudget.new(max_slots: 1),
            capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
          ),
          RubyRouting::ProviderOpportunity.new(provider_id: "B"),
          RubyRouting::ProviderOpportunity.new(provider_id: "C")
        ]
      )
      policy = RubyRouting::RoutingPolicy.new(
        id: "model-policy",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1, "B" => 1, "C" => 1 },
        recovery: RubyRouting::RecoveryPolicy.new(
          max_operations: 3,
          max_switches: 2,
          max_resolution_interactions: 2
        )
      )
      payout = intent("cross-feature-#{history_index}")
      first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      assert first.proposal.assignment?, trace(seed, history_index, coordinator)
      first_token = coordinator.mark_attempt_started(first)

      case random.rand(4)
      when 0
        coordinator.apply_observation(
          observation(first, "safe", :safe_route_failure, :provider),
          interaction_token: first_token
        )
        coordinator.set_provider_availability("B", available: false)
        fallback = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
        assert_equal "C", fallback.proposal.provider_id, trace(seed, history_index, coordinator)
        fallback_token = coordinator.mark_attempt_started(fallback)
        settled = coordinator.apply_observation(
          observation(fallback, "success", :success, :provider),
          interaction_token: fallback_token
        )
        assert_equal :success, settled.payout.status, trace(seed, history_index, coordinator)
        conflict = coordinator.apply_observation(observation(first, "late-success", :success, :provider))
        assert conflict.conflict, trace(seed, history_index, coordinator)
      when 1
        coordinator.apply_observation(
          observation(first, "unknown", :unknown, :provider),
          interaction_token: first_token
        )
        resolution = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
        assert_equal :resolve, resolution.proposal.action, trace(seed, history_index, coordinator)
        resolution_token = coordinator.mark_resolution_started(resolution)
        settled = coordinator.apply_observation(
          observation(resolution, "resolved", :success, :provider),
          interaction_token: resolution_token
        )
        assert_equal :success, settled.payout.status, trace(seed, history_index, coordinator)
      when 2
        terminal = coordinator.apply_observation(
          observation(first, "terminal", :terminal_payout_failure, :recipient),
          interaction_token: first_token
        )
        assert_equal :terminal_payout_failure, terminal.payout.status, trace(seed, history_index, coordinator)
      when 3
        coordinator.apply_observation(
          observation(first, "pending", :pending, :provider),
          interaction_token: first_token
        )
        resolution = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
        assert_equal :resolve, resolution.proposal.action, trace(seed, history_index, coordinator)
        resolution_token = coordinator.mark_resolution_started(resolution)
        settled = coordinator.apply_observation(
          observation(resolution, "resolved", :success, :provider),
          interaction_token: resolution_token
        )
        assert_equal :success, settled.payout.status, trace(seed, history_index, coordinator)
      end

      snapshot = coordinator.payout_snapshot(payout.id)
      assert_operator coordinator.active_unresolved_owners, :<=, 1, trace(seed, history_index, coordinator)
      assert_equal ["A"], coordinator.allocation_snapshot(policy: policy).measures.keys, trace(seed, history_index, coordinator)
      assert_equal snapshot.status, coordinator.lifecycle_projection.payout(payout.id).status,
        trace(seed, history_index, coordinator)
      assert_equal snapshot.attempts.map(&:provider_id), coordinator.lifecycle_projection.payout(payout.id).attempts.map(&:provider_id),
        trace(seed, history_index, coordinator)
      assert_equal [0, 0, 0], capacity_values(coordinator.capacity_projection.snapshot("A")),
        trace(seed, history_index, coordinator)

      if snapshot.status == :success && random.rand(2).zero?
        coordinator.record_reversal(
          payout_id: payout.id,
          reversal_id: "reversal-#{history_index}",
          provider_id: snapshot.settlement_provider_id,
          operation_id: snapshot.settlement_operation_id,
          amount: payout.money
        )
      end

      assert_equal coordinator.lifecycle_projection.to_h,
        RubyRouting::Projections::Replay.lifecycle(coordinator.facts).to_h,
        trace(seed, history_index, coordinator)
      live_health = %w[A B C].to_h { |provider_id| [provider_id, coordinator.health_snapshot(provider_id).to_h] }
      assert_equal live_health, coordinator.health_projection.to_h, trace(seed, history_index, coordinator)
    end
  end

  private

  def capacity_values(snapshot)
    [snapshot.used_slots, snapshot.used_count, snapshot.used_amount_minor]
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def observation(commit, label, status, attribution)
    RubyRouting::ProviderObservation.new(
      observation_id: "model:#{commit.request.payout_id}:#{label}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(status: status, attribution: attribution)
    )
  end

  def trace(seed, history_index, coordinator)
    payout = coordinator.payout_snapshot("cross-feature-#{history_index}")
    "seed=#{seed} history=#{history_index} status=#{payout.status} " \
      "owner=#{payout.ownership&.provider_id.inspect} attempts=#{payout.attempts.map(&:provider_id).inspect}"
  end
end
