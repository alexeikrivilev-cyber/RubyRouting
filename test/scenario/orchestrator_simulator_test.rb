# frozen_string_literal: true

require_relative "../test_helper"

class OrchestratorSimulatorTest < Minitest::Test
  def test_immediate_success_has_one_attempt_and_settlement
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    result = orchestrator(coordinator, "A" => provider).submit(intent: intent("success-1"), policy: one_provider_policy)

    assert_equal :success, result.status
    assert_equal 1, result.payout.attempt_count
    assert_equal "A", result.payout.settlement_provider_id
    assert_equal [[:initiate, "success-1:success-1:operation:1"]], provider.calls
  end

  def test_replayed_successful_intent_does_not_initiate_again
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    app = orchestrator(coordinator, "A" => provider)
    first = app.submit(intent: intent("replayed-success-1"), policy: one_provider_policy)
    second = app.submit(intent: intent("replayed-success-1"), policy: one_provider_policy)

    assert_equal :success, first.status
    assert_equal :already_final, second.action
    assert_equal 1, provider.calls.length
    assert_equal 1, second.payout.attempt_count
  end

  def test_safe_failure_is_followed_by_fresh_fallback_and_success
    provider_a = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.safe_failure]
    )
    provider_b = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "B",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities("A", "B"))

    result = orchestrator(coordinator, "A" => provider_a, "B" => provider_b)
      .submit(intent: intent("fallback-2"), policy: two_provider_policy)

    assert_equal :success, result.status
    assert_equal %w[A B], result.payout.attempts.map(&:provider_id)
    assert_equal "A", result.payout.primary_provider_id
    assert_equal "B", result.payout.settlement_provider_id
    assert_equal [[:initiate, "fallback-2:fallback-2:operation:1"]], provider_a.calls
    assert_equal [[:initiate, "fallback-2:fallback-2:operation:2"]], provider_b.calls
  end

  def test_unknown_then_resolution_never_starts_second_provider
    provider_a = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
      steps: [TestSupport::Simulator::Step.unknown, TestSupport::Simulator::Step.success]
    )
    provider_b = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "B",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities("A", "B", lookup_a: true))
    app = orchestrator(coordinator, "A" => provider_a, "B" => provider_b)
    first = app.submit(intent: intent("unknown-2"), policy: two_provider_policy)

    assert_equal :unknown, first.status
    assert_equal :wait, first.action
    second = app.submit(intent: intent("unknown-2"), policy: two_provider_policy)

    assert_equal :success, second.status
    assert_equal [
      [:initiate, "unknown-2:unknown-2:operation:1"],
      [:resolve, "unknown-2:unknown-2:operation:1"]
    ], provider_a.calls
    assert_empty provider_b.calls
    assert_equal 1, second.payout.attempt_count
  end

  def test_idempotent_retry_reuses_same_provider_operation
    provider_a = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(idempotent_retry: true),
      steps: [TestSupport::Simulator::Step.unknown]
    )
    provider_b = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "B",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities("A", "B", idempotent_a: true))
    app = orchestrator(coordinator, "A" => provider_a, "B" => provider_b)
    first = app.submit(intent: intent("retry-1"), policy: two_provider_policy)
    second = app.submit(intent: intent("retry-1"), policy: two_provider_policy)

    assert_equal :wait, first.action
    assert_equal :retry_same, coordinator.facts.select { |fact| fact.type == :decision_committed }[1].payload[:action]
    assert_equal :wait, second.action
    assert_equal 1, second.payout.attempt_count
    assert_equal [
      [:initiate, "retry-1:retry-1:operation:1"],
      [:initiate, "retry-1:retry-1:operation:1"]
    ], provider_a.calls
    assert_empty provider_b.calls
  end

  def test_pending_resolution_can_safely_fail_then_fallback
    provider_a = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
      steps: [TestSupport::Simulator::Step.pending, TestSupport::Simulator::Step.safe_failure]
    )
    provider_b = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "B",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities("A", "B", lookup_a: true))
    app = orchestrator(coordinator, "A" => provider_a, "B" => provider_b)

    first = app.submit(intent: intent("pending-1"), policy: two_provider_policy)
    second = app.submit(intent: intent("pending-1"), policy: two_provider_policy)

    assert_equal :wait, first.action
    assert_equal :success, second.status
    assert_equal %w[A B], second.payout.attempts.map(&:provider_id)
    assert_equal [
      [:initiate, "pending-1:pending-1:operation:1"],
      [:resolve, "pending-1:pending-1:operation:1"]
    ], provider_a.calls
  end

  def test_same_provider_retry_respects_interaction_budget
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(idempotent_retry: true),
      steps: [TestSupport::Simulator::Step.unknown]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(idempotent_retry: true)
        )
      ]
    )
    app = orchestrator(coordinator, "A" => provider)
    policy = RubyRouting::RoutingPolicy.new(
      id: "bounded-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      max_attempts: 2
    )

    app.submit(intent: intent("bounded-retry"), policy: policy)
    app.submit(intent: intent("bounded-retry"), policy: policy)
    third = app.submit(intent: intent("bounded-retry"), policy: policy)

    assert_equal :defer, third.action
    assert_equal 2, provider.calls.length
    assert_equal 2, third.payout.provider_interaction_count
  end

  def test_terminal_recipient_failure_does_not_call_fallback_provider
    provider_a = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.terminal]
    )
    provider_b = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "B",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities("A", "B"))

    result = orchestrator(coordinator, "A" => provider_a, "B" => provider_b)
      .submit(intent: intent("terminal-2"), policy: two_provider_policy)

    assert_equal :terminal_payout_failure, result.status
    assert_equal :stop, result.action
    assert_empty provider_b.calls
  end

  private

  def orchestrator(coordinator, providers)
    RubyRouting::Application::Orchestrator.new(coordinator: coordinator, providers: providers)
  end

  def opportunities(*ids, lookup_a: false, idempotent_a: false)
    ids.map do |provider_id|
      capabilities = if provider_id == "A" && lookup_a
        RubyRouting::ProviderCapabilities.new(status_lookup: true)
      elsif provider_id == "A" && idempotent_a
        RubyRouting::ProviderCapabilities.new(idempotent_retry: true)
      else
        RubyRouting::ProviderCapabilities.new
      end
      RubyRouting::ProviderOpportunity.new(provider_id: provider_id, capabilities: capabilities)
    end
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def one_provider_policy
    RubyRouting::RoutingPolicy.new(id: "policy", epoch: "1", measure: :count, targets: { "A" => 1 })
  end

  def two_provider_policy
    RubyRouting::RoutingPolicy.new(id: "policy", epoch: "1", measure: :count, targets: { "A" => 1, "B" => 1 })
  end
end
