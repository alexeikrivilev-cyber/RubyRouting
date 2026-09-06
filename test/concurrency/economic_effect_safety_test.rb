# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class EconomicEffectSafetyTest < Minitest::Test
  def test_safe_release_callback_cannot_open_provider_b_while_primary_initiate_is_live
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:block, :success]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A"),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz5-initial-live")
    policy = two_provider_policy("ptz5-initial-live-policy")

    primary = Thread.new { app.submit(intent: payout, policy: policy) }
    request_a = Timeout.timeout(3) { provider_a.entered.pop }

    callback = app.reconcile(observation: safe_release_observation(request_a, "ptz5-initial-release"))
    assert_equal :wait, callback.next_action
    assert_equal request_a.operation_id, callback.payout.ownership.operation_id

    duplicate_callback = app.reconcile(
      observation: safe_release_observation(request_a, "ptz5-initial-release")
    )
    assert duplicate_callback.duplicate
    assert_equal :wait, duplicate_callback.next_action
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :provider_observed }

    continuation = Thread.new { app.submit(intent: payout, policy: policy) }
    continuation_result = Timeout.timeout(3) { continuation.value }

    assert_equal :defer, continuation_result.action
    assert_equal [[:initiate, request_a.operation_id]], provider_a.calls
    assert_empty provider_b.calls
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :allocation_committed }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :ownership_acquired }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :attempt_started }
    assert_equal 1, coordinator.active_unresolved_owners

    provider_a.release
    primary_result = Timeout.timeout(3) { primary.value }

    assert_equal :stop, primary_result.action
    assert_equal :success, primary_result.status
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :economic_conflict }
    assert_empty provider_b.calls
  ensure
    provider_a&.release
    primary&.join(3)
  end

  def test_safe_release_callback_cannot_open_provider_b_while_same_provider_retry_is_live
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:return, :unknown], [:block, :success]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(idempotent_retry: true)
        ),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz5-retry-live")
    policy = two_provider_policy("ptz5-retry-live-policy")

    initial = app.submit(intent: payout, policy: policy)
    assert_equal :unknown, initial.status

    retry_thread = Thread.new { app.submit(intent: payout, policy: policy) }
    retry_request = Timeout.timeout(3) { provider_a.entered.pop }
    assert_equal [[:initiate, retry_request.operation_id],
                  [:initiate, retry_request.operation_id]], provider_a.calls

    callback = app.reconcile(observation: safe_release_observation(retry_request, "ptz5-retry-release"))
    assert_equal :wait, callback.next_action
    assert_equal retry_request.operation_id, callback.payout.ownership.operation_id

    continuation = Thread.new { app.submit(intent: payout, policy: policy) }
    continuation_result = Timeout.timeout(3) { continuation.value }

    assert_equal :defer, continuation_result.action
    assert_equal [[:initiate, retry_request.operation_id],
                  [:initiate, retry_request.operation_id]], provider_a.calls
    assert_empty provider_b.calls
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :allocation_committed }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :ownership_acquired }
    assert_equal 2, coordinator.facts.count { |fact| fact.type == :attempt_started }
    assert_equal 1, coordinator.active_unresolved_owners

    provider_a.release
    retry_result = Timeout.timeout(3) { retry_thread.value }

    assert_equal :stop, retry_result.action
    assert_equal :success, retry_result.status
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :economic_conflict }
    assert_empty provider_b.calls
  ensure
    provider_a&.release
    retry_thread&.join(3)
    continuation&.join(3)
  end

  def test_definitely_not_sent_late_completion_allows_fallback_only_after_live_call_ends
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:block, :safe_route_failure]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = coordinator_for(provider_a: "A", provider_b: "B", clock: clock)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz5-safe-failure-live")
    policy = two_provider_policy("ptz5-safe-failure-live-policy")

    primary = Thread.new { app.submit(intent: payout, policy: policy) }
    request_a = Timeout.timeout(3) { provider_a.entered.pop }
    app.reconcile(observation: safe_release_observation(request_a, "ptz5-safe-failure-release"))

    continuation = Thread.new { app.submit(intent: payout, policy: policy) }
    continuation_result = Timeout.timeout(3) { continuation.value }

    assert_equal :defer, continuation_result.action
    assert_empty provider_b.calls

    provider_a.release
    primary_result = Timeout.timeout(3) { primary.value }

    assert_equal :pending, primary_result.status
    assert_equal [[:initiate, "#{payout.id}:operation:2"]], provider_b.calls
    assert_equal 2, coordinator.facts.count { |fact| fact.type == :allocation_committed }
    assert_equal 2, coordinator.facts.count { |fact| fact.type == :ownership_acquired }
    assert_equal 2, coordinator.facts.count { |fact| fact.type == :attempt_started }
    assert_empty coordinator.facts.select { |fact| fact.type == :economic_conflict }
  ensure
    provider_a&.release
    primary&.join(3)
  end

  def test_owning_completion_closes_external_causal_hold_when_provider_reuses_observation_id
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:block, :safe_route_failure]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = coordinator_for(provider_a: "A", provider_b: "B", clock: clock)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz6-duplicate-observation-completion")
    policy = two_provider_policy("ptz6-duplicate-observation-completion-policy")

    primary = Thread.new { app.submit(intent: payout, policy: policy) }
    request_a = Timeout.timeout(3) { provider_a.entered.pop }
    callback = RubyRouting::ProviderObservation.new(
      observation_id: "A:observation:1",
      payout_id: request_a.payout_id,
      provider_id: request_a.provider_id,
      operation_id: request_a.operation_id,
      attempt_id: request_a.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider),
      provider_reference: "A:reference:1",
      observed_at: clock.now,
      interaction_duration_seconds: 0
    )

    callback_result = app.reconcile(observation: callback)
    assert_equal :wait, callback_result.next_action
    assert_equal request_a.operation_id, callback_result.payout.ownership.operation_id

    provider_a.release
    primary_result = Timeout.timeout(3) { primary.value }

    assert_equal :wait, primary_result.action
    assert_equal :pending, primary_result.status
    assert_equal [[:initiate, "#{payout.id}:operation:2"]], provider_b.calls
    assert_equal "B", primary_result.payout.ownership.provider_id
    assert_equal 2, coordinator.facts.count { |fact| fact.type == :ownership_acquired }
    assert_empty coordinator.facts.select { |fact| fact.type == :economic_conflict }

    restored = RubyRouting::State::Coordinator.from_facts(
      facts: coordinator.facts,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A"),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ],
      clock: clock
    )
    assert_equal coordinator.lifecycle_projection.to_h, restored.lifecycle_projection.to_h
  ensure
    provider_a&.release
    primary&.join(3)
  end

  def test_owning_completion_identity_ignores_local_interaction_duration
    clock = TestSupport::ControlledClock.new
    observation_at = clock.now
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      observation_at: observation_at,
      steps: [[:block, :safe_route_failure]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = coordinator_for(provider_a: "A", provider_b: "B", clock: clock)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz6-duplicate-observation-duration")
    policy = two_provider_policy("ptz6-duplicate-observation-duration-policy")

    primary = Thread.new { app.submit(intent: payout, policy: policy) }
    request_a = Timeout.timeout(3) { provider_a.entered.pop }
    callback = RubyRouting::ProviderObservation.new(
      observation_id: "A:observation:1",
      payout_id: request_a.payout_id,
      provider_id: request_a.provider_id,
      operation_id: request_a.operation_id,
      attempt_id: request_a.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider),
      provider_reference: "A:reference:1",
      observed_at: observation_at
    )

    callback_result = app.reconcile(observation: callback)
    assert_equal :wait, callback_result.next_action
    assert_equal request_a.operation_id, callback_result.payout.ownership.operation_id

    clock.advance(1)
    provider_a.release
    primary_result = Timeout.timeout(3) { primary.value }

    assert_equal :wait, primary_result.action
    assert_equal :pending, primary_result.status
    assert_equal [[:initiate, "#{payout.id}:operation:2"]], provider_b.calls
    assert_equal "B", primary_result.payout.ownership.provider_id
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :provider_interaction_completed }
    assert_empty coordinator.facts.select { |fact| fact.type == :economic_conflict }
  ensure
    provider_a&.release
    primary&.join(3)
  end

  def test_independent_safe_release_after_unknown_keeps_cross_provider_fallback_closed
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:return, :unknown]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = coordinator_for(provider_a: "A", provider_b: "B", clock: clock)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz6-safe-release-after-unknown")
    policy = two_provider_policy("ptz6-safe-release-after-unknown-policy")

    initial = app.submit(intent: payout, policy: policy)
    assert_equal :unknown, initial.status
    attempt = initial.payout.attempts.fetch(0)
    callback = app.reconcile(
      observation: RubyRouting::ProviderObservation.new(
        observation_id: "ptz6-safe-release-after-unknown-callback",
        payout_id: payout.id,
        provider_id: attempt.provider_id,
        operation_id: attempt.operation_id,
        attempt_id: attempt.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )

    assert_equal :wait, callback.next_action
    assert_equal :unknown, callback.payout.status
    assert_equal attempt.operation_id, callback.payout.ownership.operation_id
    assert_equal :defer, app.submit(intent: payout, policy: policy).action
    assert_empty provider_b.calls
    observed = coordinator.facts.select { |fact| fact.type == :provider_observed }
    assert_equal [true, false], observed.map { |fact| fact.payload[:applied] }
    assert_equal [false, true], observed.map { |fact| fact.payload[:causal_hold] }
    assert_empty coordinator.facts.select { |fact| fact.type == :ownership_released }
  end

  def test_adapter_exception_releases_fence_only_after_live_initiate_ends
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:block, :adapter_exception]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = coordinator_for(provider_a: "A", provider_b: "B", clock: clock)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz5-adapter-exception-live")
    policy = two_provider_policy("ptz5-adapter-exception-live-policy")

    primary = Thread.new do
      begin
        app.submit(intent: payout, policy: policy)
      rescue StandardError => error
        error
      end
    end
    request_a = Timeout.timeout(3) { provider_a.entered.pop }
    app.reconcile(observation: safe_release_observation(request_a, "ptz5-adapter-exception-release"))

    continuation = Thread.new { app.submit(intent: payout, policy: policy) }
    continuation_result = Timeout.timeout(3) { continuation.value }

    assert_equal :defer, continuation_result.action
    assert_empty provider_b.calls

    provider_a.release
    primary_error = Timeout.timeout(3) { primary.value }
    assert_instance_of RubyRouting::ProviderExecutionError, primary_error
    assert_instance_of RuntimeError, primary_error.original_error

    recovered = app.submit(intent: payout, policy: policy)
    assert_equal :defer, recovered.action
    assert_equal request_a.operation_id, recovered.payout.ownership.operation_id
    assert_empty provider_b.calls
  ensure
    provider_a&.release
    primary&.join(3)
    continuation&.join(3)
  end

  def test_ambiguous_late_completion_does_not_open_fallback_after_live_call_ends
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:block, :ambiguous]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = coordinator_for(provider_a: "A", provider_b: "B", clock: clock)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz5-ambiguous-live")
    policy = two_provider_policy("ptz5-ambiguous-live-policy")

    primary = Thread.new { app.submit(intent: payout, policy: policy) }
    request_a = Timeout.timeout(3) { provider_a.entered.pop }
    app.reconcile(observation: safe_release_observation(request_a, "ptz5-ambiguous-release"))

    continuation = Thread.new { app.submit(intent: payout, policy: policy) }
    continuation_result = Timeout.timeout(3) { continuation.value }

    assert_equal :defer, continuation_result.action
    assert_empty provider_b.calls

    provider_a.release
    primary_result = Timeout.timeout(3) { primary.value }

    assert_equal :wait, primary_result.action
    assert_equal :unknown, primary_result.status
    assert_empty provider_b.calls
    assert_empty coordinator.facts.select { |fact| fact.type == :economic_conflict }
    assert_equal [true, false], coordinator.facts
      .select { |fact| fact.type == :provider_observed }
      .map { |fact| fact.payload[:causal_hold] }

    restored = RubyRouting::State::Coordinator.from_facts(
      facts: coordinator.facts,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A"),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ],
      clock: clock
    )
    assert_empty restored.payout_snapshot(payout.id).conflicts
    assert_equal restored.payout_snapshot(payout.id).conflicts.map(&:reason),
      RubyRouting::Projections::Replay.lifecycle(coordinator.facts).payout(payout.id).conflicts.map(&:reason)
  ensure
    provider_a&.release
    primary&.join(3)
    continuation&.join(3)
  end

  def test_live_read_only_resolution_fences_fresh_assignment_after_release
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingResolveProvider.new(provider_id: "A", clock: clock)
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        ),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz5-read-only-resolution")
    policy = two_provider_policy("ptz5-read-only-resolution-policy")

    initial = app.submit(intent: payout, policy: policy)
    assert_equal :unknown, initial.status

    resolution = Thread.new { app.submit(intent: payout, policy: policy) }
    resolution_request = Timeout.timeout(3) { provider_a.entered.pop }
    assert_equal [[:initiate, resolution_request.operation_id],
                  [:resolve, resolution_request.operation_id]], provider_a.calls

    callback = app.reconcile(observation: safe_release_observation(
      resolution_request,
      "ptz5-read-only-resolution-release"
    ))
    assert_equal :wait, callback.next_action
    assert_equal resolution_request.operation_id, callback.payout.ownership.operation_id

    continuation = app.submit(intent: payout, policy: policy)
    assert_equal :defer, continuation.action
    assert_empty provider_b.calls
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :allocation_committed }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :ownership_acquired }

    provider_a.release
    resolution_result = Timeout.timeout(3) { resolution.value }
    assert_equal :wait, resolution_result.action
    assert_equal :unknown, resolution_result.status
    assert_empty provider_b.calls
  ensure
    provider_a&.release
    resolution&.join(3)
  end

  def test_economically_decisive_live_resolution_cannot_open_provider_b_before_late_success
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingResolveProvider.new(
      provider_id: "A",
      clock: clock,
      resolve_outcome: :success
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        ),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz6-live-decisive-resolution")
    policy = two_provider_policy("ptz6-live-decisive-resolution-policy")

    initial = app.submit(intent: payout, policy: policy)
    assert_equal :unknown, initial.status

    resolution = Thread.new { app.submit(intent: payout, policy: policy) }
    resolution_request = Timeout.timeout(3) { provider_a.entered.pop }
    callback = app.reconcile(observation: safe_release_observation(
      resolution_request,
      "ptz6-live-decisive-release"
    ))
    assert_equal :wait, callback.next_action
    assert_equal resolution_request.operation_id, callback.payout.ownership.operation_id

    continuation = Thread.new { app.submit(intent: payout, policy: policy) }
    continuation_result = Timeout.timeout(3) { continuation.value }

    assert_equal :defer, continuation_result.action
    assert_empty provider_b.calls
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :allocation_committed }
    assert_equal 2, coordinator.facts.count { |fact| fact.type == :attempt_started }

    provider_a.release
    resolution_result = Timeout.timeout(3) { resolution.value }

    assert_equal :stop, resolution_result.action
    assert_equal :success, resolution_result.status
    assert_empty provider_b.calls
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :economic_conflict }
    assert_equal :causal_release_contradiction,
      coordinator.payout_snapshot(payout.id).conflicts.first.reason
  ensure
    provider_a&.release
    resolution&.join(3)
    continuation&.join(3)
  end

  def test_status_lookup_definitely_not_sent_does_not_release_original_unknown
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingResolveProvider.new(
      provider_id: "A",
      clock: clock,
      resolve_outcome: :definitely_not_sent
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        ),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz6-resolve-not-sent")
    policy = two_provider_policy("ptz6-resolve-not-sent-policy")

    initial = app.submit(intent: payout, policy: policy)
    assert_equal :unknown, initial.status

    resolution = Thread.new { app.submit(intent: payout, policy: policy) }
    resolution_request = Timeout.timeout(3) { provider_a.entered.pop }
    assert_equal [[:initiate, resolution_request.operation_id],
                  [:resolve, resolution_request.operation_id]], provider_a.calls

    provider_a.release
    resolution_result = Timeout.timeout(3) { resolution.value }

    assert_equal :wait, resolution_result.action
    assert_equal :unknown, resolution_result.status
    assert_equal :unknown, resolution_result.payout.last_outcome.status
    assert_equal resolution_request.operation_id, resolution_result.payout.ownership.operation_id
    assert_empty provider_b.calls
    transport_fact = coordinator.facts.reverse.find { |fact| fact.type == :transport_classified }
    assert_equal :definitely_not_sent, transport_fact.payload[:kind]
  ensure
    provider_a&.release
    resolution&.join(3)
  end

  def test_direct_definitely_not_sent_resolution_observation_cannot_release_original_unknown
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingResolveProvider.new(
      provider_id: "A",
      clock: clock,
      resolve_outcome: :direct_definitely_not_sent
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        ),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz6-direct-resolution-transport")
    policy = two_provider_policy("ptz6-direct-resolution-transport-policy")

    assert_equal :unknown, app.submit(intent: payout, policy: policy).status
    resolution = Thread.new { app.submit(intent: payout, policy: policy) }
    resolution_request = Timeout.timeout(3) { provider_a.entered.pop }
    callback = app.reconcile(
      observation: safe_release_observation(
        resolution_request,
        "ptz6-direct-resolution-transport-callback"
      )
    )
    assert_equal :wait, callback.next_action
    assert_equal resolution_request.operation_id, callback.payout.ownership.operation_id

    continuation = Thread.new { app.submit(intent: payout, policy: policy) }
    continuation_result = Timeout.timeout(3) { continuation.value }
    assert_equal :defer, continuation_result.action
    assert_empty provider_b.calls

    provider_a.release
    resolution_result = Timeout.timeout(3) { resolution.value }

    assert_equal :wait, resolution_result.action
    assert_equal :unknown, resolution_result.status
    assert_equal resolution_request.operation_id, resolution_result.payout.ownership.operation_id
    assert_empty provider_b.calls
    assert_equal :unknown, resolution_result.payout.last_outcome.status
    assert_equal false, resolution_result.payout.last_outcome.safe_to_release?
  ensure
    provider_a&.release
    resolution&.join(3)
    continuation&.join(3)
  end

  def test_transport_observation_ids_distinguish_initiate_and_resolution_exchanges
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingResolveProvider.new(
      provider_id: "A",
      clock: clock,
      initiate_outcome: :ambiguous_transport,
      resolve_outcome: :ambiguous_transport
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        ),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz6-interaction-transport-identity")
    policy = two_provider_policy("ptz6-interaction-transport-identity-policy")

    initial = app.submit(intent: payout, policy: policy)
    assert_equal :unknown, initial.status
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :provider_observed }

    resolution = Thread.new { app.submit(intent: payout, policy: policy) }
    resolution_request = Timeout.timeout(3) { provider_a.entered.pop }
    provider_a.release
    result = Timeout.timeout(3) { resolution.value }

    assert_equal :unknown, result.status
    assert_equal :wait, result.action
    observations = coordinator.facts.select { |fact| fact.type == :provider_observed }
    assert_equal 2, observations.length
    assert_equal %w[ambiguous_after_possible_send ambiguous_after_possible_send],
      observations.map { |fact| fact.payload[:transport_kind].to_s }
    assert_equal [
      "transport:#{resolution_request.operation_id}:assign:1:ambiguous_after_possible_send",
      "transport:#{resolution_request.operation_id}:resolve:2:ambiguous_after_possible_send"
    ], observations.map { |fact| fact.payload[:observation_id] }
    assert_equal 2, coordinator.facts.count { |fact| fact.type == :transport_classified }
    assert_empty provider_b.calls
  ensure
    provider_a&.release
    resolution&.join(3)
  end

  def test_any_external_safe_release_retains_owner_until_live_resolution_is_classified
    %i[unknown recipient].each do |attribution|
      clock = TestSupport::ControlledClock.new
      provider_a = Ptz5BlockingResolveProvider.new(
        provider_id: "A",
        clock: clock,
        resolve_outcome: :adapter_exception
      )
      provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
      coordinator = RubyRouting::State::Coordinator.new(
        clock: clock,
        opportunities: [
          RubyRouting::ProviderOpportunity.new(
            provider_id: "A",
            capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
          ),
          RubyRouting::ProviderOpportunity.new(provider_id: "B")
        ]
      )
      app = RubyRouting::Application::Orchestrator.new(
        coordinator: coordinator,
        providers: { "A" => provider_a, "B" => provider_b }
      )
      payout = intent("ptz6-safe-release-attribution-#{attribution}")
      policy = two_provider_policy("ptz6-safe-release-attribution-#{attribution}-policy")
      assert_equal :unknown, app.submit(intent: payout, policy: policy).status, attribution

      resolution = Thread.new do
        app.submit(intent: payout, policy: policy)
      rescue StandardError => error
        error
      end
      request = Timeout.timeout(3) { provider_a.entered.pop }
      callback = app.reconcile(observation: observation_with_outcome(
        request,
        "ptz6-safe-release-attribution-#{attribution}-callback",
        RubyRouting::NormalizedOutcome.safe_route_failure(attribution: attribution)
      ))
      assert_equal :wait, callback.next_action, attribution
      assert_equal :unknown, callback.payout.status, attribution
      assert_equal request.operation_id, callback.payout.ownership.operation_id, attribution
      assert_equal true,
        coordinator.facts.reverse.find { |fact| fact.type == :provider_observed }.payload[:causal_hold],
        attribution

      continuation = app.submit(intent: payout, policy: policy)
      assert_equal :defer, continuation.action, attribution
      assert_empty provider_b.calls, attribution

      provider_a.release
      error = Timeout.timeout(3) { resolution.value }
      assert_instance_of RubyRouting::ProviderExecutionError, error, attribution
      assert_instance_of RuntimeError, error.original_error, attribution
      snapshot = coordinator.payout_snapshot(payout.id)
      assert_equal :unknown, snapshot.status, attribution
      assert_equal request.operation_id, snapshot.ownership.operation_id, attribution
      assert_empty provider_b.calls, attribution
    ensure
      provider_a&.release
      resolution&.join(3)
    end
  end

  def test_live_status_lookup_transport_variants_keep_fallback_closed_after_callback
    %i[timeout adapter_exception definitely_not_sent definitely_not_sent_error ambiguous_transport].each do |resolve_outcome|
      clock = TestSupport::ControlledClock.new
      provider_a = Ptz5BlockingResolveProvider.new(
        provider_id: "A",
        clock: clock,
        resolve_outcome: resolve_outcome
      )
      provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
      coordinator = RubyRouting::State::Coordinator.new(
        clock: clock,
        opportunities: [
          RubyRouting::ProviderOpportunity.new(
            provider_id: "A",
            capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
          ),
          RubyRouting::ProviderOpportunity.new(provider_id: "B")
        ]
      )
      app = RubyRouting::Application::Orchestrator.new(
        coordinator: coordinator,
        providers: { "A" => provider_a, "B" => provider_b }
      )
      payout = intent("ptz6-live-resolution-#{resolve_outcome}")
      policy = two_provider_policy("ptz6-live-resolution-#{resolve_outcome}-policy")
      assert_equal :unknown, app.submit(intent: payout, policy: policy).status

      resolution = Thread.new do
        app.submit(intent: payout, policy: policy)
      rescue StandardError => error
        error
      end
      request = Timeout.timeout(3) { provider_a.entered.pop }
      callback = app.reconcile(observation: safe_release_observation(
        request,
        "ptz6-live-resolution-#{resolve_outcome}-callback"
      ))
      assert_equal :wait, callback.next_action, resolve_outcome
      assert_equal request.operation_id, callback.payout.ownership.operation_id, resolve_outcome

      continuation = app.submit(intent: payout, policy: policy)
      assert_equal :defer, continuation.action, resolve_outcome
      assert_empty provider_b.calls, resolve_outcome

      provider_a.release
      result = Timeout.timeout(3) { resolution.value }
      if %i[timeout adapter_exception].include?(resolve_outcome)
        assert_instance_of RubyRouting::ProviderExecutionError, result, resolve_outcome
        expected_error = resolve_outcome == :timeout ? Timeout::Error : RuntimeError
        assert_instance_of expected_error, result.original_error, resolve_outcome
      else
        assert_equal :unknown, result.status, resolve_outcome
        assert_equal :wait, result.action, resolve_outcome
      end
      snapshot = coordinator.payout_snapshot(payout.id)
      assert_equal :unknown, snapshot.status, resolve_outcome
      assert_equal request.operation_id, snapshot.ownership.operation_id, resolve_outcome
      assert_empty provider_b.calls, resolve_outcome
      assert_equal 2, coordinator.facts.count { |fact| fact.type == :attempt_started }, resolve_outcome
    end
  end

  def test_safe_release_after_ttl_keeps_reconciliation_blocked_owner_without_owning_completion
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5ImmediateProvider.new(provider_id: "A", clock: clock, initiate_status: :unknown)
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, ttl_seconds: 1)
        ),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz6-safe-release-after-ttl")
    policy = two_provider_policy("ptz6-safe-release-after-ttl-policy")

    initial = app.submit(intent: payout, policy: policy)
    assert_equal :unknown, initial.status
    request = coordinator.payout_snapshot(payout.id).attempts.fetch(0)
    clock.advance(1)

    blocked = app.submit(intent: payout, policy: policy)
    assert_equal :reconciliation_blocked, blocked.status
    assert_equal request.operation_id, blocked.payout.ownership.operation_id

    callback_request = RubyRouting::ProviderOperationRequest.new(
      payout_id: payout.id,
      provider_id: "A",
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      money: payout.money
    )
    callback = app.reconcile(
      observation: safe_release_observation(callback_request, "ptz6-after-ttl-callback")
    )

    assert_equal :wait, callback.next_action
    assert_equal :reconciliation_blocked, callback.payout.status
    assert_equal request.operation_id, callback.payout.ownership.operation_id
    assert_empty provider_b.calls
    held = coordinator.facts.find do |fact|
      fact.type == :provider_observed && fact.payload[:observation_id] == "ptz6-after-ttl-callback"
    end
    assert_equal true, held.payload[:causal_hold]
    assert_equal false, held.payload[:applied]
    assert_equal 0, coordinator.facts.count { |fact| fact.type == :ownership_released }

    restored = RubyRouting::State::Coordinator.from_facts(
      facts: coordinator.facts,
      opportunities: coordinator.provider_opportunities,
      clock: clock
    )
    replayed = RubyRouting::Projections::Replay.payout(coordinator.facts, payout.id)
    restored_hold = restored.facts.find do |fact|
      fact.type == :provider_observed && fact.payload[:observation_id] == "ptz6-after-ttl-callback"
    end
    assert_equal :reconciliation_blocked, restored.payout_snapshot(payout.id).status
    assert_equal request.operation_id, restored.payout_snapshot(payout.id).ownership.operation_id
    assert_equal false, restored_hold.payload[:applied]
    assert_equal :reconciliation_blocked, replayed.status
    assert_equal request.operation_id, replayed.ownership.operation_id
  end

  def test_unknown_without_resolution_capability_keeps_owner_after_independent_safe_release
    [
      { authoritative_sequence: false, sequence: nil },
      { authoritative_sequence: true, sequence: 2 }
    ].each do |variant|
      clock = TestSupport::ControlledClock.new
      provider_a = Ptz5ImmediateProvider.new(
        provider_id: "A",
        clock: clock,
        initiate_status: :unknown,
        observation_sequence: variant.fetch(:authoritative_sequence) ? 1 : nil
      )
      provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
      coordinator = RubyRouting::State::Coordinator.new(
        clock: clock,
        opportunities: [
          RubyRouting::ProviderOpportunity.new(
            provider_id: "A",
            capabilities: RubyRouting::ProviderCapabilities.new(
              authoritative_sequence: variant.fetch(:authoritative_sequence)
            )
          ),
          RubyRouting::ProviderOpportunity.new(provider_id: "B")
        ]
      )
      app = RubyRouting::Application::Orchestrator.new(
        coordinator: coordinator,
        providers: { "A" => provider_a, "B" => provider_b }
      )
      payout = intent("ptz7-003-no-resolution-#{variant.fetch(:authoritative_sequence)}")
      policy = two_provider_policy("ptz7-003-no-resolution-policy-#{variant.fetch(:authoritative_sequence)}")

      initial = app.submit(intent: payout, policy: policy)
      assert_equal :unknown, initial.status, variant
      assert_equal :wait, initial.action, variant
      request = initial.payout.attempts.fetch(0)
      callback_request = RubyRouting::ProviderOperationRequest.new(
        payout_id: payout.id,
        provider_id: "A",
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        money: payout.money
      )

      callback = app.reconcile(observation: observation_with_outcome(
        callback_request,
        "ptz7-003-independent-release-#{variant.fetch(:authoritative_sequence)}",
        RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider),
        sequence: variant.fetch(:sequence)
      ))
      assert_equal :wait, callback.next_action, variant
      assert_equal :unknown, callback.payout.status, variant
      assert_equal request.operation_id, callback.payout.ownership.operation_id, variant

      continuation = app.submit(intent: payout, policy: policy)
      assert_equal :defer, continuation.action, variant
      assert_equal :unknown, continuation.status, variant
      assert_empty provider_b.calls, variant
      assert_equal [[:initiate, request.operation_id]], provider_a.calls, variant

      observations = coordinator.facts.select { |fact| fact.type == :provider_observed }
      assert_equal 2, observations.length, variant
      assert_equal [true, false], observations.map { |fact| fact.payload[:applied] }, variant
      assert_equal [false, true], observations.map { |fact| fact.payload[:causal_hold] }, variant
      assert_equal 1, coordinator.facts.count { |fact| fact.type == :allocation_committed }, variant
      assert_equal 1, coordinator.facts.count { |fact| fact.type == :ownership_acquired }, variant
      assert_equal 1, coordinator.facts.count { |fact| fact.type == :attempt_started }, variant
      assert_empty coordinator.facts.select { |fact| fact.type == :ownership_released }, variant
      assert_empty coordinator.facts.select { |fact| fact.type == :economic_conflict }, variant

      restored = RubyRouting::State::Coordinator.from_facts(
        facts: coordinator.facts,
        opportunities: coordinator.provider_opportunities,
        clock: clock
      )
      replayed = RubyRouting::Projections::Replay.lifecycle(coordinator.facts).payout(payout.id)
      assert_equal :unknown, restored.payout_snapshot(payout.id).status, variant
      assert_equal request.operation_id, restored.payout_snapshot(payout.id).ownership.operation_id, variant
      assert_equal :unknown, replayed.status, variant
      assert_equal request.operation_id, replayed.ownership.operation_id, variant
    end
  end

  def test_raw_timeout_after_independent_release_does_not_open_cross_provider_fallback
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:block, :timeout]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = coordinator_for(provider_a: "A", provider_b: "B", clock: clock)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz6-raw-timeout-after-release")
    policy = two_provider_policy("ptz6-raw-timeout-after-release-policy")

    primary = Thread.new do
      begin
        app.submit(intent: payout, policy: policy)
      rescue StandardError => error
        error
      end
    end
    request_a = Timeout.timeout(3) { provider_a.entered.pop }
    callback = app.reconcile(observation: safe_release_observation(
      request_a,
      "ptz6-raw-timeout-release"
    ))
    assert_equal :wait, callback.next_action
    assert_equal request_a.operation_id, callback.payout.ownership.operation_id

    provider_a.release
    primary_error = Timeout.timeout(3) { primary.value }
    assert_instance_of RubyRouting::ProviderExecutionError, primary_error
    assert_instance_of Timeout::Error, primary_error.original_error

    continuation = app.submit(intent: payout, policy: policy)

    assert_equal :defer, continuation.action
    assert_empty provider_b.calls
    assert_empty coordinator.facts.select { |fact| fact.type == :economic_conflict }
  ensure
    provider_a&.release
    primary&.join(3)
  end

  def test_explicit_definitely_not_sent_after_independent_release_allows_fallback_after_completion
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:block, :definitely_not_sent]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = coordinator_for(provider_a: "A", provider_b: "B", clock: clock)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz6-explicit-safe-release")
    policy = two_provider_policy("ptz6-explicit-safe-release-policy")

    primary = Thread.new { app.submit(intent: payout, policy: policy) }
    request_a = Timeout.timeout(3) { provider_a.entered.pop }
    app.reconcile(observation: safe_release_observation(request_a, "ptz6-explicit-release"))

    before_completion = Thread.new { app.submit(intent: payout, policy: policy) }
    before_completion_result = Timeout.timeout(3) { before_completion.value }
    assert_equal :defer, before_completion_result.action
    assert_empty provider_b.calls

    provider_a.release
    primary_result = Timeout.timeout(3) { primary.value }

    assert_equal :pending, primary_result.status
    assert_equal [[:initiate, "#{payout.id}:operation:2"]], provider_b.calls
    assert_equal 2, coordinator.facts.count { |fact| fact.type == :attempt_started }
    assert_empty coordinator.facts.select { |fact| fact.type == :economic_conflict }
  ensure
    provider_a&.release
    primary&.join(3)
    before_completion&.join(3)
  end

  def test_explicit_ambiguous_transport_after_independent_release_keeps_fallback_closed
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:block, :ambiguous_transport]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = coordinator_for(provider_a: "A", provider_b: "B", clock: clock)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz6-explicit-ambiguous-release")
    policy = two_provider_policy("ptz6-explicit-ambiguous-release-policy")

    primary = Thread.new { app.submit(intent: payout, policy: policy) }
    request_a = Timeout.timeout(3) { provider_a.entered.pop }
    app.reconcile(observation: safe_release_observation(request_a, "ptz6-ambiguous-release"))

    before_completion = Thread.new { app.submit(intent: payout, policy: policy) }
    before_completion_result = Timeout.timeout(3) { before_completion.value }
    assert_equal :defer, before_completion_result.action
    assert_empty provider_b.calls

    provider_a.release
    primary_result = Timeout.timeout(3) { primary.value }

    assert_equal :wait, primary_result.action
    assert_equal :unknown, primary_result.status
    assert_empty provider_b.calls
    assert_empty coordinator.facts.select { |fact| fact.type == :economic_conflict }
  ensure
    provider_a&.release
    primary&.join(3)
    before_completion&.join(3)
  end

  def test_terminal_callback_during_live_initiate_stops_without_opening_fallback
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:block, :success]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = coordinator_for(provider_a: "A", provider_b: "B", clock: clock)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz5-terminal-callback")
    policy = two_provider_policy("ptz5-terminal-callback-policy")

    primary = Thread.new { app.submit(intent: payout, policy: policy) }
    request_a = Timeout.timeout(3) { provider_a.entered.pop }

    callback = app.reconcile(observation: terminal_observation(
      request_a,
      "ptz5-terminal-callback-observation"
    ))
    assert_equal :stop, callback.next_action
    assert_equal :terminal_payout_failure, callback.payout.status
    assert_nil callback.payout.ownership

    continuation = app.submit(intent: payout, policy: policy)
    assert_equal :terminate, continuation.action
    assert_empty provider_b.calls
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :allocation_committed }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :ownership_acquired }

    provider_a.release
    primary_result = Timeout.timeout(3) { primary.value }
    assert_equal :stop, primary_result.action
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :economic_conflict }
    assert_empty provider_b.calls
  ensure
    provider_a&.release
    primary&.join(3)
  end

  def test_safe_temporary_release_callback_cannot_open_provider_b_while_primary_initiate_is_live
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:block, :success]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = coordinator_for(provider_a: "A", provider_b: "B", clock: clock)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz5-temporary-release-live")
    policy = two_provider_policy("ptz5-temporary-release-live-policy")

    primary = Thread.new { app.submit(intent: payout, policy: policy) }
    request_a = Timeout.timeout(3) { provider_a.entered.pop }

    callback = app.reconcile(observation: temporary_release_observation(
      request_a,
      "ptz5-temporary-release"
    ))
    assert_equal :wait, callback.next_action
    assert_equal :pending, callback.payout.status
    assert_equal request_a.operation_id, callback.payout.ownership.operation_id

    continuation = app.submit(intent: payout, policy: policy)
    assert_equal :defer, continuation.action
    assert_empty provider_b.calls
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :allocation_committed }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :ownership_acquired }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :attempt_started }

    provider_a.release
    primary_result = Timeout.timeout(3) { primary.value }

    assert_equal :stop, primary_result.action
    assert_equal :success, primary_result.status
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :economic_conflict }
    assert_empty provider_b.calls
  ensure
    provider_a&.release
    primary&.join(3)
  end

  def test_authoritative_out_of_order_callbacks_do_not_regress_live_money_movement
    clock = TestSupport::ControlledClock.new
    provider_a = Ptz5BlockingInitiateProvider.new(
      provider_id: "A",
      clock: clock,
      steps: [[:block, :success]]
    )
    provider_b = Ptz5ImmediateProvider.new(provider_id: "B", clock: clock)
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(authoritative_sequence: true)
        ),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    payout = intent("ptz5-authoritative-order-live")
    policy = two_provider_policy("ptz5-authoritative-order-live-policy")

    primary = Thread.new { app.submit(intent: payout, policy: policy) }
    request_a = Timeout.timeout(3) { provider_a.entered.pop }

    pending = app.reconcile(observation: observation_with_outcome(
      request_a,
      "ptz5-authoritative-pending",
      RubyRouting::NormalizedOutcome.pending(attribution: :provider),
      sequence: 2
    ))
    assert_equal :wait, pending.next_action
    assert_equal :pending, pending.payout.status
    assert_equal "A", pending.payout.ownership.provider_id

    stale = app.reconcile(observation: observation_with_outcome(
      request_a,
      "ptz5-authoritative-stale",
      RubyRouting::NormalizedOutcome.unknown(attribution: :provider),
      sequence: 1
    ))
    refute stale.duplicate
    assert_equal :wait, stale.next_action
    assert_equal :pending, stale.payout.status
    assert_equal "A", stale.payout.ownership.provider_id
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :opportunity_evaluated }
    assert_equal 2, coordinator.facts.count { |fact| fact.type == :provider_observed }
    assert_equal [true, false], coordinator.facts
      .select { |fact| fact.type == :provider_observed }
      .map { |fact| fact.payload[:applied] }

    released = app.reconcile(observation: observation_with_outcome(
      request_a,
      "ptz5-authoritative-release",
      RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider),
      sequence: 3
    ))
    assert_equal :wait, released.next_action
    assert_equal request_a.operation_id, released.payout.ownership.operation_id

    continuation = app.submit(intent: payout, policy: policy)
    assert_equal :defer, continuation.action
    assert_empty provider_b.calls

    provider_a.release
    primary_result = Timeout.timeout(3) { primary.value }
    assert_equal :defer, primary_result.action
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :economic_conflict }
    assert_empty provider_b.calls
  ensure
    provider_a&.release
    primary&.join(3)
  end

  private

  def intent(id)
    RubyRouting::PayoutIntent.new(
      id: id,
      money: RubyRouting::Money.new(100, "RUB")
    )
  end

  def coordinator_for(provider_a:, provider_b:, clock:)
    RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: provider_a),
        RubyRouting::ProviderOpportunity.new(provider_id: provider_b)
      ]
    )
  end

  def two_provider_policy(id)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      max_attempts: 2
    )
  end

  def safe_release_observation(request, observation_id)
    observation_with_outcome(
      request,
      observation_id,
      RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
    )
  end

  def temporary_release_observation(request, observation_id)
    observation_with_outcome(
      request,
      observation_id,
      RubyRouting::NormalizedOutcome.temporary_provider_failure(
        attribution: :provider,
        safe_to_release: true
      )
    )
  end

  def observation_with_outcome(request, observation_id, outcome, sequence: nil)
    RubyRouting::ProviderObservation.new(
      observation_id: observation_id,
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: outcome,
      provider_reference: "callback-reference",
      sequence: sequence,
      observed_at: request_observed_at
    )
  end

  def terminal_observation(request, observation_id)
    RubyRouting::ProviderObservation.new(
      observation_id: observation_id,
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.terminal_payout_failure(attribution: :recipient),
      observed_at: request_observed_at
    )
  end

  def request_observed_at
    Time.utc(2026, 9, 1, 0, 0, 0)
  end
end

class Ptz5BlockingInitiateProvider
  attr_reader :entered

  def initialize(provider_id:, clock:, steps:, observation_at: nil)
    @provider_id = provider_id
    @clock = clock
    @observation_at = observation_at
    @steps = steps.dup
    @calls = []
    @entered = Queue.new
    @release = Queue.new
    @mutex = Thread::Mutex.new
    @sequence = 0
  end

  def calls
    @mutex.synchronize { @calls.dup.freeze }
  end

  def initiate(request)
    mode, outcome_status = @mutex.synchronize do
      @calls << [:initiate, request.operation_id].freeze
      @sequence += 1
      @steps.shift || raise(ArgumentError, "blocking provider has no step left")
    end
    @entered << request if mode == :block
    @release.pop if mode == :block
    raise Timeout::Error, "adapter timeout after callback" if outcome_status == :timeout
    raise "adapter failed after callback" if outcome_status == :adapter_exception
    return RubyRouting::ProviderTransportResult.definitely_not_sent(
      message: "adapter proved request was not sent"
    ) if outcome_status == :definitely_not_sent
    return RubyRouting::ProviderTransportResult.ambiguous_after_possible_send(
      message: "adapter could not classify request"
    ) if outcome_status == :ambiguous_transport

    observation_for(request, outcome_status)
  end

  def resolve(_request)
    raise "unexpected status lookup"
  end

  def release
    @release << true
  end

  private

  def observation_for(request, status)
    if status == :ambiguous
      return RubyRouting::ProviderObservation.new(
        observation_id: "#{@provider_id}:observation:#{@sequence}",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider),
        provider_reference: "#{@provider_id}:reference:#{@sequence}",
        transport_kind: :ambiguous_after_possible_send,
        observed_at: @observation_at || @clock.now
      )
    end

    RubyRouting::ProviderObservation.new(
      observation_id: "#{@provider_id}:observation:#{@sequence}",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.public_send(status, attribution: :provider),
      provider_reference: "#{@provider_id}:reference:#{@sequence}",
      observed_at: @observation_at || @clock.now
    )
  end
end

class Ptz5BlockingResolveProvider
  attr_reader :entered

  def initialize(provider_id:, clock:, resolve_outcome: :unknown, initiate_outcome: nil)
    @provider_id = provider_id
    @clock = clock
    @resolve_outcome = resolve_outcome
    @initiate_outcome = initiate_outcome
    @calls = []
    @entered = Queue.new
    @release = Queue.new
    @mutex = Thread::Mutex.new
  end

  def calls
    @mutex.synchronize { @calls.dup.freeze }
  end

  def initiate(request)
    record_call(:initiate, request.operation_id)
    return RubyRouting::ProviderTransportResult.ambiguous_after_possible_send(
      message: "initiate outcome is ambiguous"
    ) if @initiate_outcome == :ambiguous_transport

    observation_for(request, :unknown)
  end

  def resolve(request)
    record_call(:resolve, request.operation_id)
    @entered << request
    @release.pop
    raise Timeout::Error, "status lookup timeout after callback" if @resolve_outcome == :timeout
    raise "status lookup adapter failure after callback" if @resolve_outcome == :adapter_exception
    return direct_definitely_not_sent_observation(request) if @resolve_outcome == :direct_definitely_not_sent
    raise RubyRouting::ProviderTransportError.definitely_not_sent("status lookup was not sent") if @resolve_outcome == :definitely_not_sent_error
    return RubyRouting::ProviderTransportResult.definitely_not_sent(
      message: "status lookup was not sent"
    ) if @resolve_outcome == :definitely_not_sent
    return RubyRouting::ProviderTransportResult.ambiguous_after_possible_send(
      message: "status lookup outcome is ambiguous"
    ) if @resolve_outcome == :ambiguous_transport

    observation_for(request, @resolve_outcome)
  end

  def release
    @release << true
  end

  private

  def direct_definitely_not_sent_observation(request)
    RubyRouting::ProviderObservation.new(
      observation_id: "#{@provider_id}:direct-definitely-not-sent:#{@calls.length}",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider),
      provider_reference: "#{@provider_id}:reference:#{@calls.length}",
      transport_kind: :definitely_not_sent,
      observed_at: @clock.now
    )
  end

  def record_call(action, operation_id)
    @mutex.synchronize { @calls << [action, operation_id].freeze }
  end

  def observation_for(request, status)
    RubyRouting::ProviderObservation.new(
      observation_id: "#{@provider_id}:observation:#{@calls.length}",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.public_send(status, attribution: :provider),
      provider_reference: "#{@provider_id}:reference",
      observed_at: @clock.now
    )
  end
end

class Ptz5ImmediateProvider
  attr_reader :calls

  def initialize(provider_id:, clock:, initiate_status: :pending, observation_sequence: nil)
    @provider_id = provider_id
    @clock = clock
    @initiate_status = initiate_status
    @observation_sequence = observation_sequence
    @calls = []
  end

  def initiate(request)
    @calls << [:initiate, request.operation_id].freeze
    RubyRouting::ProviderObservation.new(
      observation_id: "#{@provider_id}:pending:#{@calls.length}",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.public_send(@initiate_status, attribution: :provider),
      provider_reference: "#{@provider_id}:reference",
      sequence: @observation_sequence && @calls.length,
      observed_at: @clock.now
    )
  end

  def resolve(_request)
    raise "unexpected status lookup"
  end
end
