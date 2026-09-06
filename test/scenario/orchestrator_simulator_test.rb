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

  def test_adapter_ids_are_canonicalized_at_the_application_boundary
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )

    result = orchestrator(coordinator, " A " => provider)
      .submit(intent: intent("canonical-adapter"), policy: one_provider_policy)

    assert_equal :success, result.status
    assert_equal [[:initiate, "canonical-adapter:canonical-adapter:operation:1"]], provider.calls
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

  def test_delayed_callback_is_delivered_without_creating_a_second_operation
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.delayed_success]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    app = orchestrator(coordinator, "A" => provider)
    payout = intent("delayed-callback")

    first = app.submit(intent: payout, policy: one_provider_policy)
    assert_equal 1, provider.pending_callbacks.length
    callback = provider.drain_callbacks.first
    second = app.reconcile(observation: callback)

    assert_equal :pending, first.status
    assert_equal :wait, first.action
    assert_equal :success, second.payout.status
    assert_equal 1, second.payout.attempt_count
    assert_equal [[:initiate, "delayed-callback:delayed-callback:operation:1"]], provider.calls
  end

  def test_duplicate_callback_is_exactly_replayed_and_has_no_second_settlement
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.delayed_success]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    app = orchestrator(coordinator, "A" => provider)
    payout = intent("duplicate-callback")
    app.submit(intent: payout, policy: one_provider_policy)
    callback = provider.drain_callbacks.first

    settled = app.reconcile(observation: callback)
    duplicate = app.reconcile(observation: provider.duplicate(callback))

    assert_equal :success, settled.payout.status
    assert duplicate.duplicate
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :settlement_recorded }
    assert_equal 1, provider.calls.count { |call| call.first == :duplicate }
  end

  def test_out_of_order_callbacks_follow_provider_sequence_without_regressing_lifecycle
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(authoritative_sequence: true),
      steps: [
        TestSupport::Simulator::Step.delayed(
          callbacks: [
            RubyRouting::NormalizedOutcome.pending(attribution: :provider),
            RubyRouting::NormalizedOutcome.success(attribution: :provider)
          ]
        )
      ]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(authoritative_sequence: true)
      )]
    )
    app = orchestrator(coordinator, "A" => provider)
    payout = intent("out-of-order-callback")
    app.submit(intent: payout, policy: one_provider_policy)

    delayed = provider.drain_callbacks(order: :lifo)
    settled_first = app.reconcile(observation: delayed.first)
    old_pending = app.reconcile(observation: delayed.last)

    assert_equal :success, settled_first.payout.status
    assert_equal :success, old_pending.payout.status
    assert_nil old_pending.payout.ownership
    assert_equal 1, coordinator.facts.count { |fact| fact.payload[:applied] == false }
  end

  def test_reversal_helper_preserves_provider_and_settlement_linkage
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    app = orchestrator(coordinator, "A" => provider)
    payout = app.submit(intent: intent("simulated-reversal"), policy: one_provider_policy).payout
    reversal = provider.reversal_for(
      payout: payout,
      amount: RubyRouting::Money.new(40, "RUB"),
      reversal_id: "simulated-return-1"
    )

    reversed = app.record_reversal(**reversal_attributes(reversal))

    assert_equal :reversed, reversed.status
    assert_equal "A", reversal.provider_id
    assert_equal payout.settlement_operation_id, reversal.operation_id
  end

  def test_unresolved_operation_keeps_contract_after_provider_is_disabled_for_new_routes
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
    payout = intent("disabled-after-commit")

    first = app.submit(intent: payout, policy: two_provider_policy)
    coordinator.set_provider_availability("A", available: false)
    second = app.resume(payout_id: payout.id, policy: two_provider_policy)

    assert_equal :unknown, first.status
    assert_equal :success, second.status
    assert_equal [
      [:initiate, "disabled-after-commit:disabled-after-commit:operation:1"],
      [:resolve, "disabled-after-commit:disabled-after-commit:operation:1"]
    ], provider_a.calls
    assert_empty provider_b.calls
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

  def test_non_releasable_provider_failure_enters_unknown_and_can_be_resolved
    provider_a = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
      steps: [
        TestSupport::Simulator::Step.temporary_failure(safe_to_release: false),
        TestSupport::Simulator::Step.success
      ]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    app = orchestrator(coordinator, "A" => provider_a)
    payout = intent("non-releasable-provider-failure")

    first = app.submit(intent: payout, policy: one_provider_policy)
    second = app.resume(payout_id: payout.id, policy: one_provider_policy)

    assert_equal :unknown, first.status
    assert_equal :unknown, first.payout.current_operation_phase
    assert_equal :success, second.status
    assert_equal [
      [:initiate, "non-releasable-provider-failure:non-releasable-provider-failure:operation:1"],
      [:resolve, "non-releasable-provider-failure:non-releasable-provider-failure:operation:1"]
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

  def test_definitely_not_sent_transport_failure_releases_ownership
    provider = TransportProvider.new(
      provider_id: "A",
      result: RubyRouting::ProviderTransportResult.definitely_not_sent(message: "connection rejected")
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )

    result = orchestrator(coordinator, "A" => provider)
      .submit(intent: intent("not-sent"), policy: one_provider_policy)

    assert_equal :defer, result.action
    assert_equal :deferred, result.status
    assert_nil result.payout.ownership
    assert_equal 1, result.payout.attempt_count
  end

  def test_ambiguous_transport_failure_is_unknown_and_keeps_ownership
    provider = TransportProvider.new(
      provider_id: "A",
      result: RubyRouting::ProviderTransportResult.ambiguous_after_possible_send(message: "timeout")
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )

    result = orchestrator(coordinator, "A" => provider)
      .submit(intent: intent("ambiguous-send"), policy: one_provider_policy)

    assert_equal :wait, result.action
    assert_equal :unknown, result.status
    assert_equal "A", result.payout.ownership.provider_id
    assert_equal :unknown, result.payout.current_operation_phase
  end

  def test_explicit_transport_error_is_conservatively_ambiguous_and_resolvable
    provider = Class.new do
      def initialize
        @resolved = false
      end

      def initiate(_request)
        raise RubyRouting::ProviderTransportError.ambiguous_after_possible_send("adapter timeout")
      end

      def resolve(request)
        @resolved = true
        RubyRouting::ProviderObservation.new(
          observation_id: "generic-fault-resolution",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end
    end.new
    capabilities = RubyRouting::ProviderCapabilities.new(status_lookup: true)
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A", capabilities: capabilities)]
    )
    app = orchestrator(coordinator, "A" => provider)
    payout = intent("unclassified-adapter-fault")

    first = app.submit(intent: payout, policy: one_provider_policy)
    second = app.resume(payout_id: payout.id, policy: one_provider_policy)
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)

    assert_equal :unknown, first.status
    assert_equal :unknown, first.payout.current_operation_phase
    assert_equal :success, second.status
    assert_equal({ ambiguous_after_possible_send: 1 }, analytics.transport_count_by_kind)
  end

  def test_unclassified_adapter_fault_surfaces_without_losing_resumable_operation
    provider = Class.new do
      def initiate(_request)
        raise RuntimeError, "adapter exploded"
      end

      def resolve(_request)
        raise "not used"
      end
    end.new
    capabilities = RubyRouting::ProviderCapabilities.new(status_lookup: true)
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A", capabilities: capabilities)]
    )
    app = orchestrator(coordinator, "A" => provider)
    payout = intent("unclassified-adapter-fault")

    assert_raises(RuntimeError) { app.submit(intent: payout, policy: one_provider_policy) }
    snapshot = coordinator.payout_snapshot(payout.id)
    assert_equal :dispatching, snapshot.current_operation_phase
    assert_equal "A", snapshot.ownership.provider_id

    assert_raises(RuntimeError) { app.resume(payout_id: payout.id, policy: one_provider_policy) }
    assert_equal :resolving, coordinator.payout_snapshot(payout.id).current_operation_phase
  end

  def test_raw_adapter_timeout_is_not_guessed_as_definitely_not_sent
    provider = Class.new do
      def initiate(_request)
        raise Timeout::Error, "read deadline exceeded"
      end

      def resolve(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "timeout-resolution",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end
    end.new
    capabilities = RubyRouting::ProviderCapabilities.new(status_lookup: true)
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A", capabilities: capabilities)]
    )
    app = orchestrator(coordinator, "A" => provider)
    payout = intent("raw-adapter-timeout")

    error = assert_raises(RubyRouting::ProviderExecutionError) do
      app.submit(intent: payout, policy: one_provider_policy)
    end
    assert_instance_of Timeout::Error, error.original_error
    assert_instance_of Timeout::Error, error.cause
    snapshot = coordinator.payout_snapshot(payout.id)
    assert_equal :dispatching, snapshot.current_operation_phase
    assert_equal "A", snapshot.ownership.provider_id
    assert_empty RubyRouting::Projections::Analytics.from_facts(coordinator.facts).transport_count_by_kind

    recovered = app.resume(payout_id: payout.id, policy: one_provider_policy)

    assert_equal :success, recovered.status
    assert_equal ["timeout-resolution"], coordinator.facts
      .select { |fact| fact.type == :provider_observed }
      .map { |fact| fact.payload[:observation_id] }
  end

  def test_malformed_provider_observation_surfaces_without_synthetic_unknown
    provider = Class.new do
      def initiate(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "malformed-observation",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: "wrong-operation",
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end

      def resolve(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "malformed-observation-resolution",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end
    end.new
    capabilities = RubyRouting::ProviderCapabilities.new(status_lookup: true)
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A", capabilities: capabilities)]
    )
    app = orchestrator(coordinator, "A" => provider)
    payout = intent("malformed-observation")

    error = assert_raises(RubyRouting::ProviderContractError) do
      app.submit(intent: payout, policy: one_provider_policy)
    end
    assert_instance_of ArgumentError, error.original_error
    assert_equal "provider observation linkage does not match request", error.original_error.message
    snapshot = coordinator.payout_snapshot(payout.id)
    assert_equal :dispatching, snapshot.current_operation_phase
    assert_equal "A", snapshot.ownership.provider_id
    assert_equal 1, snapshot.provider_interaction_count
    assert_equal 0, coordinator.facts.count { |fact| fact.type == :provider_interaction_completed }
    assert_equal 0, coordinator.facts.count { |fact| fact.type == :provider_observed }
    second = app.resume(payout_id: payout.id, policy: one_provider_policy)
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)

    assert_equal :success, second.status
    assert_empty analytics.transport_count_by_kind
  end

  def test_post_return_duration_processing_error_is_not_provider_contract_or_recovery
    observation_class = Class.new(RubyRouting::ProviderObservation) do
      def with_interaction_duration(_duration_seconds)
        raise ArgumentError, "duration enrichment rejected the returned observation"
      end
    end
    provider = Class.new do
      define_method(:initiate) do |request|
        observation_class.new(
          observation_id: "duration-contract-observation",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end

      def resolve(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "duration-contract-resolution",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    app = orchestrator(coordinator, "A" => provider)
    payout = intent("duration-contract")

    error = assert_raises(RubyRouting::ApplicationProcessingError) do
      app.submit(intent: payout, policy: one_provider_policy)
    end
    assert_instance_of ArgumentError, error.original_error
    assert_equal "duration enrichment rejected the returned observation", error.original_error.message
    snapshot = coordinator.payout_snapshot(payout.id)
    assert_equal :pending, snapshot.status
    assert_equal :dispatching, snapshot.current_operation_phase
    refute coordinator.__send__(:provider_interaction_in_flight?, payout.id, snapshot.ownership.operation_id)
    assert_empty coordinator.facts.select { |fact| fact.type == :provider_execution_failed }
    assert_empty coordinator.facts.select { |fact| fact.type == :provider_observed }
  end

  def test_application_fault_after_valid_provider_return_is_not_provider_contract_error
    provider = Class.new do
      def initiate(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "application-fault-after-return",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end

      def resolve(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "application-fault-after-return-resolution",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end
    end.new
    faulting_orchestrator = Class.new(RubyRouting::Application::Orchestrator) do
      private

      def classify_transport(result, request, interaction:, interaction_index:)
        super
        raise RuntimeError, "application classification programming fault"
      end
    end
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    app = faulting_orchestrator.new(coordinator: coordinator, providers: { "A" => provider })
    payout = intent("application-fault-after-return")

    error = assert_raises(RubyRouting::ApplicationProcessingError) do
      app.submit(intent: payout, policy: one_provider_policy)
    end

    assert_instance_of RubyRouting::ApplicationProcessingError, error
    assert_instance_of RuntimeError, error.original_error
    assert_equal "application classification programming fault", error.original_error.message
    snapshot = coordinator.payout_snapshot(payout.id)
    assert_equal :pending, snapshot.status
    assert_equal :dispatching, snapshot.current_operation_phase
    assert_equal "A", snapshot.ownership.provider_id
    refute coordinator.__send__(
      :provider_interaction_in_flight?,
      payout.id,
      snapshot.ownership.operation_id
    )
    assert_empty coordinator.facts.select { |fact| fact.type == :provider_execution_failed }
    assert_empty coordinator.facts.select { |fact| fact.type == :provider_observed }
  end

  def test_fatal_apply_failure_does_not_strand_the_process_local_interaction_guard
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.success]
    )
    fatal_coordinator = Class.new(RubyRouting::State::Coordinator) do
      def apply_observation(*_arguments, **_keywords)
        raise NotImplementedError, "fatal apply-path probe"
      end
    end.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    app = orchestrator(fatal_coordinator, "A" => provider)
    payout = intent("fatal-apply-path")

    assert_raises(NotImplementedError) do
      app.submit(intent: payout, policy: one_provider_policy)
    end

    snapshot = fatal_coordinator.payout_snapshot(payout.id)
    assert_equal :pending, snapshot.status
    assert_equal :dispatching, snapshot.current_operation_phase
    refute fatal_coordinator.__send__(
      :provider_interaction_in_flight?,
      payout.id,
      snapshot.ownership.operation_id
    )
    assert_empty fatal_coordinator.facts.select { |fact| fact.type == :provider_execution_failed }
    assert_empty fatal_coordinator.facts.select { |fact| fact.type == :provider_observed }
    assert_empty fatal_coordinator.due_work(as_of: Time.now.utc),
      "a live fatal apply fault must not masquerade as restart recovery"
  end

  def test_not_implemented_adapter_fault_releases_guard_without_provider_failure_marker
    provider = Class.new do
      def initiate(_request)
        raise NotImplementedError, "adapter has no initiate implementation"
      end

      def resolve(_request)
        raise NotImplementedError, "adapter has no resolve implementation"
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )

    assert_raises(NotImplementedError) do
      orchestrator(coordinator, "A" => provider)
        .submit(intent: intent("not-implemented-adapter"), policy: one_provider_policy)
    end
    snapshot = coordinator.payout_snapshot("not-implemented-adapter")
    refute coordinator.__send__(
      :provider_interaction_in_flight?,
      snapshot.id,
      snapshot.ownership.operation_id
    )
    assert_empty coordinator.facts.select { |fact| fact.type == :provider_execution_failed }
    assert_empty coordinator.due_work(as_of: Time.now.utc),
      "a live fatal adapter fault must not masquerade as restart recovery"
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

  def reversal_attributes(reversal)
    {
      payout_id: reversal.payout_id,
      reversal_id: reversal.reversal_id,
      provider_id: reversal.provider_id,
      operation_id: reversal.operation_id,
      amount: reversal.amount,
      reason: reversal.reason
    }
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

  class TransportProvider
    def initialize(provider_id:, result:)
      @provider_id = provider_id
      @result = result
    end

    def initiate(request)
      unless request.provider_id == @provider_id
        raise ArgumentError, "request provider does not match adapter"
      end

      @result
    end

    def resolve(_request)
      @result
    end
  end
end
