# frozen_string_literal: true

require_relative "../test_helper"

class ProviderAdapterContractTest < Minitest::Test
  def test_universal_executable_port_is_rejected_before_any_payout_work
    provider = Class.new do
      def initiate(_request)
        raise "not used"
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )

    error = assert_raises(ArgumentError) do
      RubyRouting::Application::Orchestrator.new(
        coordinator: coordinator,
        providers: { "A" => provider }
      )
    end

    assert_includes error.message, "initiate and resolve"
    assert_equal [:provider_opportunity_registered], coordinator.facts.map(&:type)
    assert_empty coordinator.facts.select { |fact| fact.type == :intent_registered }
  end

  def test_idempotent_retry_capability_uses_initiate_and_never_resolve
    calls = []
    outcomes = [
      RubyRouting::NormalizedOutcome.unknown(attribution: :provider),
      RubyRouting::NormalizedOutcome.success(attribution: :provider)
    ]
    provider = Class.new do
      define_method(:initiate) do |request|
        calls << [:initiate, request.operation_id, request.attempt_id]
        RubyRouting::ProviderObservation.new(
          observation_id: "idempotent-contract-#{calls.length}",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: outcomes.shift
        )
      end

      define_method(:resolve) do |_request|
        raise "idempotent retry capability must not invoke resolve"
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(idempotent_retry: true)
      )]
    )
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "idempotent-contract-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 2)
    )
    payout = RubyRouting::PayoutIntent.new(
      id: "idempotent-contract-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )

    first = app.submit(intent: payout, policy: policy)
    second = app.resume(payout_id: payout.id, policy: policy)

    assert_equal :unknown, first.status
    assert_equal :success, second.status
    assert_equal [
      [:initiate, "idempotent-contract-payout:operation:1", "idempotent-contract-payout:attempt:1"],
      [:initiate, "idempotent-contract-payout:operation:1", "idempotent-contract-payout:attempt:1"]
    ], calls
    assert_equal 1, second.payout.attempt_count
    assert_equal 2, second.payout.provider_interaction_count
    assert_empty coordinator.facts.select { |fact| fact.type == :provider_execution_failed }
  end
end
