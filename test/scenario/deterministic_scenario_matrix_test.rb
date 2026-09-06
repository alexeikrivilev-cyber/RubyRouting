# frozen_string_literal: true

require_relative "../test_helper"

class DeterministicScenarioMatrixTest < Minitest::Test
  Scenario = Struct.new(
    :name,
    :provider_a,
    :provider_b,
    :expected_status,
    :expected_action,
    :expected_attempts,
    :expected_b_calls,
    keyword_init: true
  )

  def test_canonical_orchestrator_matrix_preserves_lifecycle_safety
    scenarios.each do |scenario|
      coordinator = RubyRouting::State::Coordinator.new(
        opportunities: [
          RubyRouting::ProviderOpportunity.new(provider_id: "A"),
          RubyRouting::ProviderOpportunity.new(provider_id: "B")
        ]
      )
      providers = { "A" => scenario.provider_a.call, "B" => scenario.provider_b.call }
      result = RubyRouting::Application::Orchestrator.new(
        coordinator: coordinator,
        providers: providers
      ).submit(intent: intent("matrix-#{scenario.name}"), policy: two_provider_policy)

      assert_equal scenario.expected_status, result.status, scenario.name
      assert_equal scenario.expected_action, result.action, scenario.name
      assert_equal scenario.expected_attempts, result.payout.attempts.map(&:provider_id), scenario.name
      assert_equal scenario.expected_b_calls, providers.fetch("B").calls.length, scenario.name
      assert_operator coordinator.active_unresolved_owners, :<=, 1, scenario.name
    end
  end

  private

  def scenarios
    scripted = ->(provider_id, steps:, capabilities: RubyRouting::ProviderCapabilities.new) do
      -> {
        TestSupport::Simulator::ScriptedProvider.new(
          provider_id: provider_id,
          steps: steps,
          capabilities: capabilities
        )
      }
    end

    [
      Scenario.new(
        name: "success",
        provider_a: scripted.call("A", steps: [TestSupport::Simulator::Step.success]),
        provider_b: scripted.call("B", steps: [TestSupport::Simulator::Step.success]),
        expected_status: :success,
        expected_action: :stop,
        expected_attempts: ["A"],
        expected_b_calls: 0
      ),
      Scenario.new(
        name: "pending",
        provider_a: scripted.call("A", steps: [TestSupport::Simulator::Step.pending]),
        provider_b: scripted.call("B", steps: [TestSupport::Simulator::Step.success]),
        expected_status: :pending,
        expected_action: :wait,
        expected_attempts: ["A"],
        expected_b_calls: 0
      ),
      Scenario.new(
        name: "unknown-owner",
        provider_a: scripted.call("A", steps: [TestSupport::Simulator::Step.unknown]),
        provider_b: scripted.call("B", steps: [TestSupport::Simulator::Step.success]),
        expected_status: :unknown,
        expected_action: :wait,
        expected_attempts: ["A"],
        expected_b_calls: 0
      ),
      Scenario.new(
        name: "safe-fallback",
        provider_a: scripted.call("A", steps: [TestSupport::Simulator::Step.safe_failure]),
        provider_b: scripted.call("B", steps: [TestSupport::Simulator::Step.success]),
        expected_status: :success,
        expected_action: :stop,
        expected_attempts: ["A", "B"],
        expected_b_calls: 1
      ),
      Scenario.new(
        name: "temporary-fallback",
        provider_a: scripted.call("A", steps: [TestSupport::Simulator::Step.temporary_failure]),
        provider_b: scripted.call("B", steps: [TestSupport::Simulator::Step.success]),
        expected_status: :success,
        expected_action: :stop,
        expected_attempts: ["A", "B"],
        expected_b_calls: 1
      ),
      Scenario.new(
        name: "terminal-recipient-failure",
        provider_a: scripted.call("A", steps: [TestSupport::Simulator::Step.terminal]),
        provider_b: scripted.call("B", steps: [TestSupport::Simulator::Step.success]),
        expected_status: :terminal_payout_failure,
        expected_action: :stop,
        expected_attempts: ["A"],
        expected_b_calls: 0
      ),
      Scenario.new(
        name: "definitely-not-sent",
        provider_a: -> { TransportProvider.new(:definitely_not_sent) },
        provider_b: scripted.call("B", steps: [TestSupport::Simulator::Step.success]),
        expected_status: :success,
        expected_action: :stop,
        expected_attempts: ["A", "B"],
        expected_b_calls: 1
      ),
      Scenario.new(
        name: "ambiguous-transport",
        provider_a: -> { TransportProvider.new(:ambiguous_after_possible_send) },
        provider_b: scripted.call("B", steps: [TestSupport::Simulator::Step.success]),
        expected_status: :unknown,
        expected_action: :wait,
        expected_attempts: ["A"],
        expected_b_calls: 0
      )
    ]
  end

  def two_provider_policy
    RubyRouting::RoutingPolicy.new(
      id: "deterministic-matrix",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  class TransportProvider
    def initialize(kind)
      @kind = kind
    end

    def initiate(_request)
      RubyRouting::ProviderTransportResult.new(kind: @kind)
    end

    def resolve(_request)
      RubyRouting::ProviderTransportResult.new(kind: @kind)
    end
  end
end
