# frozen_string_literal: true

require_relative "../test_helper"

class AdmissionTest < Minitest::Test
  def test_throughput_is_consumed_on_commit_and_returns_only_after_window_expiry
    clock = TestSupport::ControlledClock.new
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)
    )
    coordinator = RubyRouting::State::Coordinator.new(clock: clock, opportunities: [provider])
    policy = policy_for("throughput")

    first = coordinator.prepare_and_commit_decision(intent: intent("first"), policy: policy)
    state = coordinator.instance_variable_get(:@payouts).fetch("first")

    assert_equal ["A", clock.current_time, clock.monotonic],
      state.throughput_reservations.fetch(first.proposal.operation_id)

    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, "first-success", :success))

    blocked = coordinator.prepare_and_commit_decision(intent: intent("blocked"), policy: policy)

    assert_equal :defer, blocked.proposal.action
    assert_includes blocked.proposal.reason_codes, :throughput_exhausted
    assert_equal 1, coordinator.throughput_snapshot("A").consumed_count
    refute coordinator.throughput_snapshot("A").available?
    assert_equal coordinator.throughput_snapshot("A").to_h,
      coordinator.throughput_projection.snapshot("A").to_h

    clock.advance(60)
    available = coordinator.prepare_and_commit_decision(intent: intent("after-window"), policy: policy)

    assert_equal :assign, available.proposal.action
    assert_equal "A", available.proposal.provider_id
    assert_equal 1, coordinator.throughput_snapshot("A").consumed_count
  end

  def test_capacity_release_does_not_release_throughput_budget
    clock = TestSupport::ControlledClock.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capacity: RubyRouting::CapacityBudget.new(max_slots: 1),
          throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)
        )
      ]
    )
    policy = policy_for("separate")

    first = coordinator.prepare_and_commit_decision(intent: intent("separate-first"), policy: policy)
    interaction_token = coordinator.mark_attempt_started(first)
    coordinator.apply_observation(
      observation(first, "separate-failure", :safe_route_failure),
      interaction_token: interaction_token
    )

    second = coordinator.prepare_and_commit_decision(intent: intent("separate-second"), policy: policy)

    assert_equal 0, coordinator.capacity_snapshot("A").used_slots
    assert_equal 1, coordinator.throughput_snapshot("A").consumed_count
    assert_equal :defer, second.proposal.action
    assert_includes second.proposal.reason_codes, :throughput_exhausted
  end

  def test_throughput_budget_uses_a_system_clock_when_no_clock_is_supplied
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)
    )

    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    result = coordinator.prepare_and_commit_decision(
      intent: intent("system-clock-throughput"),
      policy: policy_for("system-clock-throughput")
    )

    assert_equal :assign, result.proposal.action
    assert_equal 1, coordinator.throughput_snapshot("A").consumed_count
  end

  def test_explicit_throughput_gate_is_hard_even_without_a_budget
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A", throughput_available: false)]
    )

    result = coordinator.prepare_and_commit_decision(
      intent: intent("throughput-gate"),
      policy: policy_for("throughput-gate")
    )

    assert_equal :defer, result.proposal.action
    assert_includes result.proposal.reason_codes, :throughput_exhausted
    assert_empty result.payout.attempts
  end

  def test_explicit_throughput_gate_is_hard_before_window_budget
    clock = TestSupport::ControlledClock.new
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 2, window_seconds: 60),
      throughput_available: false
    )
    coordinator = RubyRouting::State::Coordinator.new(clock: clock, opportunities: [provider])

    result = coordinator.prepare_and_commit_decision(
      intent: intent("throughput-gate-budget"),
      policy: policy_for("throughput-gate-budget")
    )

    assert_equal :defer, result.proposal.action
    assert_includes result.proposal.reason_codes, :throughput_exhausted
    assert_equal 0, coordinator.throughput_snapshot("A").consumed_count
  end

  def test_clock_must_return_time_values
    bad_clock = Object.new
    bad_clock.define_singleton_method(:now) { "not-a-time" }

    assert_raises(ArgumentError) do
      RubyRouting::State::Coordinator.new(
        clock: bad_clock,
        opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
      ).register_intent(
        RubyRouting::PayoutIntent.new(
          id: "clock-type",
          money: RubyRouting::Money.new(1, "RUB")
        )
      )
    end
  end

  private

  def policy_for(id)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(
      id: id,
      money: RubyRouting::Money.new(100, "RUB")
    )
  end

  def observation(commit, id, status)
    RubyRouting::ProviderObservation.new(
      observation_id: id,
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(
        status: status,
        attribution: :provider,
        safe_to_release: status == :safe_route_failure
      )
    )
  end
end
