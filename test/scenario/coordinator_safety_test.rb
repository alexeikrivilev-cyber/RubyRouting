# frozen_string_literal: true

require_relative "../test_helper"

class CoordinatorSafetyTest < Minitest::Test
  def test_unknown_keeps_owner_and_blocks_cross_provider_fallback
    coordinator = coordinator_with(%w[A B])
    intent = intent("unknown-1")
    policy = count_policy
    first = coordinator.prepare_and_commit_decision(intent: intent, policy: policy)

    assert_equal "A", first.proposal.provider_id
    coordinator.mark_attempt_started(first)
    application = coordinator.apply_observation(observation(first, :unknown))

    assert_equal :unknown, application.payout.status
    assert_equal "A", application.payout.ownership.provider_id
    assert_equal :wait, application.next_action

    second = coordinator.prepare_and_commit_decision(intent: intent, policy: policy)
    assert_equal :defer, second.proposal.action
    assert_equal "unresolved ownership blocks cross-provider fallback", second.proposal.reasons.first
    assert_equal 1, coordinator.payout_snapshot(intent.id).attempt_count
    assert_equal 1, coordinator.active_unresolved_owners
  end

  def test_safe_failure_releases_owner_and_fresh_decision_can_settle_elsewhere
    coordinator = coordinator_with(%w[A B])
    intent = intent("fallback-1")
    policy = count_policy
    first = coordinator.prepare_and_commit_decision(intent: intent, policy: policy)
    coordinator.mark_attempt_started(first)

    failed = coordinator.apply_observation(observation(first, :safe_route_failure, attribution: :provider))
    assert_nil failed.payout.ownership
    assert_equal :reroute, failed.next_action

    second = coordinator.prepare_and_commit_decision(intent: intent, policy: policy)
    assert_equal "B", second.proposal.provider_id
    coordinator.mark_attempt_started(second)
    settled = coordinator.apply_observation(observation(second, :success, attribution: :provider))

    assert_equal :success, settled.payout.status
    assert_nil settled.payout.ownership
    assert_equal "A", settled.payout.primary_provider_id
    assert_equal "B", settled.payout.settlement_provider_id
    assert_equal %w[A B], settled.payout.attempts.map(&:provider_id)
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :settlement_recorded }
  end

  def test_safe_temporary_provider_failure_releases_owner_for_reroute
    coordinator = coordinator_with(%w[A B])
    intent = intent("temporary-failure-1")
    first = coordinator.prepare_and_commit_decision(intent: intent, policy: count_policy)
    coordinator.mark_attempt_started(first)

    application = coordinator.apply_observation(
      observation(
        first,
        :temporary_provider_failure,
        attribution: :provider,
        safe_to_release: true
      )
    )

    assert_equal :temporary_provider_failure, application.payout.status
    assert_nil application.payout.ownership
    assert_equal :reroute, application.next_action
  end

  def test_terminal_recipient_failure_stops_route_hopping
    coordinator = coordinator_with(%w[A B])
    intent = intent("terminal-1")
    first = coordinator.prepare_and_commit_decision(intent: intent, policy: count_policy)
    coordinator.mark_attempt_started(first)

    terminal = coordinator.apply_observation(observation(first, :terminal_payout_failure, attribution: :recipient))
    assert_equal :terminal_payout_failure, terminal.payout.status
    assert_equal :stop, terminal.next_action
    assert_nil terminal.payout.ownership

    next_decision = coordinator.prepare_and_commit_decision(intent: intent, policy: count_policy)
    assert_equal :terminate, next_decision.proposal.action
    assert_equal 1, coordinator.payout_snapshot(intent.id).attempt_count
  end

  def test_duplicate_observation_does_not_double_apply_settlement
    coordinator = coordinator_with(["A"])
    intent = intent("duplicate-observation-1")
    commit = coordinator.prepare_and_commit_decision(intent: intent, policy: count_policy)
    coordinator.mark_attempt_started(commit)
    success = observation(commit, :success)

    first = coordinator.apply_observation(success)
    duplicate = coordinator.apply_observation(success)

    refute duplicate.duplicate == false
    assert duplicate.duplicate
    assert_equal :success, first.payout.status
    assert_equal :success, duplicate.payout.status
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :settlement_recorded }
  end

  def test_observation_id_reuse_with_different_payload_is_rejected
    coordinator = coordinator_with(["A"])
    intent = intent("observation-integrity-1")
    commit = coordinator.prepare_and_commit_decision(intent: intent, policy: count_policy)
    coordinator.mark_attempt_started(commit)
    first = observation(commit, :success)
    coordinator.apply_observation(first)

    conflicting = RubyRouting::ProviderObservation.new(
      observation_id: first.observation_id,
      payout_id: first.payout_id,
      provider_id: first.provider_id,
      operation_id: first.operation_id,
      attempt_id: first.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.terminal_payout_failure(attribution: :recipient)
    )

    assert_raises(ArgumentError) { coordinator.apply_observation(conflicting) }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :provider_observed }
  end

  private

  def coordinator_with(provider_ids)
    RubyRouting::State::Coordinator.new(
      opportunities: provider_ids.map do |provider_id|
        RubyRouting::ProviderOpportunity.new(provider_id: provider_id)
      end
    )
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(
      id: id,
      money: RubyRouting::Money.new(100, "RUB"),
      recipient: { "account" => "recipient-1" }
    )
  end

  def count_policy
    RubyRouting::RoutingPolicy.new(id: "policy", epoch: "1", measure: :count, targets: { "A" => 1, "B" => 1 })
  end

  def observation(commit, status, attribution: :unknown, safe_to_release: nil)
    RubyRouting::ProviderObservation.new(
      observation_id: "obs:#{commit.proposal.operation_id}:#{status}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(
        status: status,
        attribution: attribution,
        safe_to_release: safe_to_release
      )
    )
  end
end
