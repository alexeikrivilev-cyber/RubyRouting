# frozen_string_literal: true

require_relative "../test_helper"

class HealthRankingTest < Minitest::Test
  def test_health_uses_hysteresis_and_recipient_failure_is_neutral
    controller = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 2,
        quarantine_after: 3,
        recover_after: 2
      )
    )

    controller.observe(provider_id: "A", signal: :recipient_failure, attribution: :recipient)
    assert_equal :healthy, controller.snapshot("A").state
    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :provider)
    assert_equal :healthy, controller.snapshot("A").state
    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :provider)
    assert_equal :degraded, controller.snapshot("A").state
    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :provider)
    assert_equal :quarantined, controller.snapshot("A").state
    controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)
    assert_equal :probing, controller.snapshot("A").state
    controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)
    assert_equal :healthy, controller.snapshot("A").state
  end

  def test_snapshot_of_unknown_provider_does_not_create_hidden_health_state
    controller = RubyRouting::Routing::HealthController.new

    assert_equal :healthy, controller.snapshot("A").state
    assert_empty controller.provider_ids
  end

  def test_coordinator_rejects_manual_health_signal_for_unknown_provider
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )

    assert_raises(ArgumentError) do
      coordinator.record_health_signal(
        provider_id: "B",
        signal: :provider_failure,
        attribution: :provider
      )
    end
    refute coordinator.facts.any? { |fact| fact.type == :health_signal && fact.payload[:provider_id] == "B" }
  end

  def test_health_rejects_unknown_explicit_route_keys_instead_of_using_global_state
    controller = RubyRouting::Routing::HealthController.new

    assert_raises(ArgumentError) do
      controller.snapshot("A", routing_context: { payment_methd: "card" })
    end
    assert_empty controller.provider_ids
  end

  def test_static_health_exclusion_cannot_be_overridden_by_default_controller_state
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A", health_available: false),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "static-health",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )

    commit = coordinator.prepare_and_commit_decision(intent: intent("static-health"), policy: policy)
    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }

    assert_equal "B", commit.proposal.provider_id
    assert_equal :quarantined, evaluation.payload.fetch(:exclusion_codes).fetch("A")
  end

  def test_unknown_or_downstream_health_attribution_is_neutral
    controller = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(degrade_after: 1, quarantine_after: 1)
    )

    controller.observe(provider_id: "A", signal: :provider_failure)
    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :downstream)

    assert_equal :healthy, controller.snapshot("A").state
    assert_equal 0, controller.snapshot("A").operational_failure_count
  end

  def test_global_health_quarantine_is_a_safety_ceiling_for_scoped_routes
    route = RubyRouting::RoutingContext.new(
      payment_method: :card,
      rail: :bank,
      destination_kind: :bank_account
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 1
      ),
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )

    coordinator.record_health_signal(
      provider_id: "A",
      signal: :provider_failure,
      attribution: :provider
    )

    assert_equal :quarantined, coordinator.health_snapshot("A").state
    assert_equal :quarantined, coordinator.health_snapshot("A", routing_context: route).state
    assert_equal :quarantined, coordinator.health_projection.snapshot("A", routing_context: route).state

    controller = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 1
      )
    )
    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :provider)
    refute controller.reserve_exposure(
      "A",
      owner: "global-quarantine-route-operation",
      routing_context: route
    )

    restored = RubyRouting::State::Coordinator.from_facts(facts: coordinator.facts)
    assert_equal coordinator.health_snapshot("A", routing_context: route).to_h,
      restored.health_snapshot("A", routing_context: route).to_h
    assert_equal :quarantined, restored.health_projection.snapshot("A", routing_context: route).state
  end

  def test_route_assignment_accepts_global_degraded_health_without_bypassing_the_ceiling
    route = RubyRouting::RoutingContext.new(payment_method: :card)
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 2,
        quarantine_after: 3,
        recover_after: 1
      ),
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "global-degraded-route",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    2.times do
      coordinator.record_health_signal(
        provider_id: "A",
        signal: :provider_failure,
        attribution: :provider
      )
    end

    commit = coordinator.prepare_and_commit_decision(
      intent: intent_with_route("global-degraded-route-payout", route),
      policy: policy
    )

    assert_equal :assign, commit.proposal.action
    assert_equal :degraded, coordinator.health_snapshot("A", routing_context: route).state
  end

  def test_route_probe_uses_global_probe_budget_and_recovers_the_global_state
    route = RubyRouting::RoutingContext.new(payment_method: :card)
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 1
      ),
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "global-probe-route",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :provider_failure,
      attribution: :provider
    )
    coordinator.record_health_signal(
      provider_id: "A",
      signal: :operational_success,
      attribution: :provider
    )
    assert_equal :probing, coordinator.health_snapshot("A").state

    commit = coordinator.prepare_and_commit_decision(
      intent: intent_with_route("global-probe-route-payout", route),
      policy: policy
    )

    assert_equal :assign, commit.proposal.action
    assert_equal 1, coordinator.health_snapshot("A").probe_in_flight
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation(commit, :success))

    assert_equal :healthy, coordinator.health_snapshot("A").state
    assert_equal 0, coordinator.health_snapshot("A").probe_in_flight
  end

  def test_generic_provider_operational_signals_share_hysteresis_but_non_provider_evidence_is_neutral
    signals = %i[
      transport_failure
      timeout_pressure
      overload_rejection
      provider_service_error
      latency_pressure
      deadline_pressure
    ]

    signals.each do |signal|
      controller = RubyRouting::Routing::HealthController.new(
        policy: RubyRouting::Routing::HealthPolicy.new(degrade_after: 1, quarantine_after: 1)
      )

      controller.observe(provider_id: "A", signal: signal, attribution: :provider)
      assert_equal :quarantined, controller.snapshot("A").state, signal
      assert_equal 1, controller.snapshot("A").operational_failure_count, signal
      controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)
      assert_equal :probing, controller.snapshot("A").state, signal
      controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)
      assert_equal :healthy, controller.snapshot("A").state, signal

      controller.observe(provider_id: "B", signal: signal, attribution: :recipient)
      assert_equal :healthy, controller.snapshot("B").state, signal
      assert_equal 0, controller.snapshot("B").operational_failure_count, signal
    end
  end

  def test_ambiguous_transport_marks_provider_timeout_pressure_without_releasing_unknown_owner
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 1
    )
    providers = [
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: providers
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "ambiguous-health",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      tolerance: 0
    )
    payout = intent("ambiguous-health-payout")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assert_equal "A", commit.proposal.provider_id
    coordinator.mark_attempt_started(commit)

    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "ambiguous-health-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :unknown),
        transport_kind: :ambiguous_after_possible_send
      )
    )

    snapshot = coordinator.payout_snapshot(payout.id)
    health_fact = coordinator.facts.find do |fact|
      fact.type == :health_signal && fact.payload[:source] == "ambiguous-health-observation"
    end
    next_commit = coordinator.prepare_and_commit_decision(
      intent: intent("ambiguous-health-next"),
      policy: policy
    )

    assert_equal :unknown, snapshot.status
    assert_equal "A", snapshot.ownership.provider_id
    assert_equal :unknown, snapshot.attempts.first.outcome.status
    assert_equal :quarantined, coordinator.health_snapshot("A").state
    assert_equal :timeout_pressure, health_fact.payload[:signal]
    assert_equal :provider, health_fact.payload[:attribution]
    assert_equal "B", next_commit.proposal.provider_id
    assert_equal coordinator.health_snapshot("A").to_h,
      coordinator.health_projection.snapshot("A").to_h
  end

  def test_normalized_provider_service_failure_emits_typed_service_health_signal
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 1
    )
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [provider]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "service-health",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    payout = intent("service-health-payout")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "service-health-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.temporary_provider_failure(attribution: :provider)
      )
    )

    health_fact = coordinator.facts.find do |fact|
      fact.type == :health_signal && fact.payload[:source] == "service-health-observation"
    end

    assert_equal :provider_service_error, health_fact.payload[:signal]
    assert_equal :provider, health_fact.payload[:attribution]
    assert_equal :quarantined, coordinator.health_snapshot("A").state
    snapshot = coordinator.payout_snapshot(payout.id)
    assert_equal :unknown, snapshot.status
    assert_equal :temporary_provider_failure, snapshot.attempts.first.outcome.status
    assert_equal "A", snapshot.ownership.provider_id
  end

  def test_definitely_not_sent_transport_emits_typed_transport_health_signal
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 1
    )
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [provider]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "transport-health",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    payout = intent("transport-health-payout")
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "transport-health-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider),
        transport_kind: :definitely_not_sent
      )
    )

    health_fact = coordinator.facts.find do |fact|
      fact.type == :health_signal && fact.payload[:source] == "transport-health-observation"
    end

    assert_equal :transport_failure, health_fact.payload[:signal]
    assert_equal :quarantined, coordinator.health_snapshot("A").state
    assert_nil coordinator.payout_snapshot(payout.id).ownership
  end

  def test_canonical_provider_path_records_exact_latency_and_replays_provider_health
    clock = TestSupport::ControlledClock.new
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 1,
      latency_threshold_ms: 100
    )
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "canonical-latency",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    provider = TimedProvider.new(
      clock: clock,
      duration_seconds: Rational(101, 1000),
      response: :provider_success
    )

    result = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    ).submit(intent: intent("canonical-latency-payout"), policy: policy)

    assert_equal :success, result.status
    observation = coordinator.facts.find { |fact| fact.type == :provider_observed }
    health = coordinator.facts.find do |fact|
      fact.type == :health_signal && fact.payload[:source] == observation.payload[:observation_id]
    end
    assert_equal Rational(101, 1000), observation.payload[:interaction_duration_seconds]
    assert_equal :latency_pressure, health.payload[:signal]
    assert_equal :provider, health.payload[:attribution]
    assert_equal :quarantined, coordinator.health_snapshot("A").state

    restored = RubyRouting::State::Coordinator.from_facts(
      facts: coordinator.facts,
      clock: clock
    )
    assert_equal coordinator.health_snapshot("A").to_h, restored.health_snapshot("A").to_h
    payout = coordinator.payout_snapshot("canonical-latency-payout")
    restored_payout = restored.payout_snapshot("canonical-latency-payout")
    assert_equal payout.status, restored_payout.status
    assert_equal payout.ownership.to_h, restored_payout.ownership.to_h
  end

  def test_canonical_latency_boundary_is_not_pressure
    clock = TestSupport::ControlledClock.new
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 1,
      latency_threshold_ms: 100
    )
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "latency-boundary",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )

    RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: {
        "A" => TimedProvider.new(
          clock: clock,
          duration_seconds: Rational(1, 10),
          response: :provider_success
        )
      }
    ).submit(intent: intent("latency-boundary-payout"), policy: policy)

    observation = coordinator.facts.find { |fact| fact.type == :provider_observed }
    health = coordinator.facts.find do |fact|
      fact.type == :health_signal && fact.payload[:source] == observation.payload[:observation_id]
    end
    assert_equal Rational(1, 10), observation.payload[:interaction_duration_seconds]
    assert_equal :operational_success, health.payload[:signal]
    assert_equal :healthy, coordinator.health_snapshot("A").state
  end

  def test_recipient_latency_does_not_create_provider_pressure
    clock = TestSupport::ControlledClock.new
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 1,
      latency_threshold_ms: 100
    )
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "latency-boundary",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )

    result = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: {
        "A" => TimedProvider.new(
          clock: clock,
          duration_seconds: Rational(101, 1000),
          response: :recipient_failure
        )
      }
    ).submit(intent: intent("latency-boundary-payout"), policy: policy)

    assert_equal :terminal_payout_failure, result.status
    observation = coordinator.facts.find { |fact| fact.type == :provider_observed }
    assert_equal Rational(101, 1000), observation.payload[:interaction_duration_seconds]
    refute coordinator.facts.any? { |fact|
      fact.type == :health_signal && fact.payload[:source] == observation.payload[:observation_id]
    }
    assert_equal :healthy, coordinator.health_snapshot("A").state
  end

  def test_ambiguous_transport_latency_keeps_unknown_owner_and_transport_health_precedence
    clock = TestSupport::ControlledClock.new
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 1,
      latency_threshold_ms: 100
    )
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "ambiguous-latency",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: {
        "A" => TimedProvider.new(
          clock: clock,
          duration_seconds: Rational(101, 1000),
          response: :ambiguous
        )
      }
    ).submit(intent: intent("ambiguous-latency-payout"), policy: policy)

    observation = coordinator.facts.find { |fact| fact.type == :provider_observed }
    health = coordinator.facts.find do |fact|
      fact.type == :health_signal && fact.payload[:source] == observation.payload[:observation_id]
    end
    assert_equal :unknown, result.status
    assert_equal "A", result.payout.ownership.provider_id
    assert_equal Rational(101, 1000), observation.payload[:interaction_duration_seconds]
    assert_equal :timeout_pressure, health.payload[:signal]
    assert_equal :quarantined, coordinator.health_snapshot("A").state
  end

  def test_provider_health_ids_use_the_same_canonical_form_as_opportunities
    controller = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(degrade_after: 1, quarantine_after: 1)
    )

    controller.observe(provider_id: " A ", signal: :provider_failure, attribution: :provider)

    assert_equal :quarantined, controller.snapshot("A").state
    assert_equal ["A"], controller.provider_ids
  end

  def test_probing_exposure_is_bounded_until_probe_observation_arrives
    controller = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 2,
        probe_limit: 1
      )
    )

    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :provider)
    controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)
    assert_equal :probing, controller.snapshot("A").state
    assert controller.reserve_exposure("A")
    refute controller.reserve_exposure("A")
    refute controller.snapshot("A").exposed?

    controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)
    assert_equal :healthy, controller.snapshot("A").state
    assert_equal 0, controller.snapshot("A").probe_in_flight
  end

  def test_recovery_does_not_become_healthy_while_another_probe_is_in_flight
    controller = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 2,
        probe_limit: 2
      )
    )

    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :provider)
    controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)
    assert controller.reserve_exposure("A", owner: "probe-1")
    assert controller.reserve_exposure("A", owner: "probe-2")

    controller.observe(
      provider_id: "A",
      signal: :operational_success,
      attribution: :provider,
      release_exposure: false
    )
    controller.release_exposure("A", owner: "probe-1")
    assert_equal :probing, controller.snapshot("A").state
    assert_equal 1, controller.snapshot("A").probe_in_flight

    controller.observe(
      provider_id: "A",
      signal: :operational_success,
      attribution: :provider,
      release_exposure: false
    )
    assert_equal :probing, controller.snapshot("A").state
    controller.release_exposure("A", owner: "probe-2")
    assert_equal :healthy, controller.snapshot("A").state
    assert_equal 0, controller.snapshot("A").probe_in_flight
  end

  def test_probe_owner_identity_is_canonicalized_for_reservation_release
    controller = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 2,
        probe_limit: 1
      )
    )
    controller.observe(provider_id: "A", signal: :provider_failure, attribution: :provider)
    controller.observe(provider_id: "A", signal: :operational_success, attribution: :provider)

    assert controller.reserve_exposure(" A ", owner: " probe-1 ")
    controller.release_exposure("A", owner: "probe-1")

    assert_equal 0, controller.snapshot(" A ").probe_in_flight
  end

  def test_health_snapshot_rejects_blank_provider_identity
    assert_raises(ArgumentError) do
      RubyRouting::Routing::ProviderHealthSnapshot.new(provider_id: " ")
    end
  end

  def test_health_enum_inputs_report_argument_errors
    assert_raises(ArgumentError) do
      RubyRouting::Routing::ProviderHealthSnapshot.new(provider_id: "A", state: Object.new)
    end

    controller = RubyRouting::Routing::HealthController.new
    assert_raises(ArgumentError) do
      controller.observe(provider_id: "A", signal: Object.new)
    end
    assert_raises(ArgumentError) do
      controller.observe(provider_id: "A", signal: :provider_failure, attribution: Object.new)
    end
    assert_empty controller.provider_ids
  end

  def test_health_snapshot_rejects_malformed_counters_and_probe_limit
    invalid_values = [
      { operational_failure_count: -1 },
      { consecutive_failure_count: "1" },
      { consecutive_success_count: nil },
      { probe_in_flight: -1 },
      { probe_limit: 0 },
      { probe_limit: "1" },
      { probe_in_flight: 2, probe_limit: 1 }
    ]

    invalid_values.each do |attributes|
      assert_raises(ArgumentError, attributes.inspect) do
        RubyRouting::Routing::ProviderHealthSnapshot.new(
          provider_id: "A",
          **attributes
        )
      end
    end
  end

  def test_health_observation_rejects_truthy_non_boolean_exposure_flag
    controller = RubyRouting::Routing::HealthController.new

    assert_raises(ArgumentError) do
      controller.observe(
        provider_id: "A",
        signal: :operational_failure,
        attribution: :provider,
        release_exposure: "false"
      )
    end
    assert_equal :healthy, controller.snapshot("A").state
  end

  def test_coordinator_persists_probe_reservation_and_blocks_second_probe
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 2,
      probe_limit: 1
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "probe-coordinator",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    coordinator.record_health_signal(provider_id: "A", signal: :provider_failure, attribution: :provider)
    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)

    first = coordinator.prepare_and_commit_decision(intent: intent("probe-first"), policy: policy)
    second = coordinator.prepare_and_commit_decision(intent: intent("probe-second"), policy: policy)

    assert first.proposal.assignment?
    assert_equal :probing, coordinator.health_snapshot("A").state
    assert_equal 1, coordinator.health_snapshot("A").probe_in_flight
    assert_equal :defer, second.proposal.action
    assert_equal :quarantined, second.proposal.reason_codes.last
    assert_equal coordinator.health_projection.snapshot("A").to_h,
      coordinator.health_snapshot("A").to_h
  end

  def test_probe_release_is_owned_by_the_operation_that_reserved_it
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 1,
      probe_limit: 2
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "probe-ownership",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )

    first = coordinator.prepare_and_commit_decision(intent: intent("probe-owner-before-state"), policy: policy)
    coordinator.record_health_signal(provider_id: "A", signal: :provider_failure, attribution: :provider)
    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)

    second = coordinator.prepare_and_commit_decision(intent: intent("probe-owner-one"), policy: policy)
    assert_equal 1, coordinator.health_snapshot("A").probe_in_flight

    coordinator.apply_observation(observation(first, :terminal_payout_failure, attribution: :recipient))
    assert_equal 1, coordinator.health_snapshot("A").probe_in_flight

    third = coordinator.prepare_and_commit_decision(intent: intent("probe-owner-two"), policy: policy)
    assert third.proposal.assignment?
    assert_equal 2, coordinator.health_snapshot("A").probe_in_flight

    fourth = coordinator.prepare_and_commit_decision(intent: intent("probe-owner-three"), policy: policy)
    assert_equal :defer, fourth.proposal.action
    assert_equal :quarantined, fourth.proposal.reason_codes.last
    assert_equal second.proposal.provider_id, third.proposal.provider_id
  end

  def test_multiple_probe_reservations_are_released_once_by_their_own_operations
    health_policy = RubyRouting::Routing::HealthPolicy.new(
      degrade_after: 1,
      quarantine_after: 1,
      recover_after: 4,
      probe_limit: 2
    )
    coordinator = RubyRouting::State::Coordinator.new(
      health_policy: health_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "probe-double-release",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )

    coordinator.record_health_signal(provider_id: "A", signal: :provider_failure, attribution: :provider)
    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)
    first = coordinator.prepare_and_commit_decision(intent: intent("probe-double-release-1"), policy: policy)
    second = coordinator.prepare_and_commit_decision(intent: intent("probe-double-release-2"), policy: policy)
    assert second.proposal.assignment?
    assert_equal 2, coordinator.health_snapshot("A").probe_in_flight

    coordinator.record_health_signal(provider_id: "A", signal: :operational_success, attribution: :provider)
    assert_equal 2, coordinator.health_snapshot("A").probe_in_flight

    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, :success))
    assert_equal 1, coordinator.health_snapshot("A").probe_in_flight

    third = coordinator.prepare_and_commit_decision(intent: intent("probe-double-release-3"), policy: policy)
    fourth = coordinator.prepare_and_commit_decision(intent: intent("probe-double-release-4"), policy: policy)

    assert third.proposal.assignment?
    assert_equal 2, coordinator.health_snapshot("A").probe_in_flight
    assert_equal :defer, fourth.proposal.action
    assert_equal :quarantined, fourth.proposal.reason_codes.last
    assert_equal coordinator.health_projection.snapshot("A").to_h,
      coordinator.health_snapshot("A").to_h
  end

  def test_quarantine_is_hard_exclusion_and_does_not_reset_allocation_history
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A"),
        RubyRouting::ProviderOpportunity.new(provider_id: "B")
      ],
      health_policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 1
      )
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "health-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      tolerance: 0
    )

    first = coordinator.prepare_and_commit_decision(intent: intent("health-first"), policy: policy)
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, :safe_route_failure))
    assert_equal :quarantined, coordinator.health_snapshot("A").state

    second = coordinator.prepare_and_commit_decision(intent: intent("health-second"), policy: policy)

    assert_equal "B", second.proposal.provider_id
    assert_equal :health_quarantine, second.proposal.allocation_decision.deviation_cause
    assert_equal({ "A" => 1, "B" => 1 }, coordinator.allocation_snapshot(policy: policy).measures)
    assert_equal :quarantined, coordinator.health_snapshot("A").state
    live_health = %w[A B].to_h { |provider_id| [provider_id, coordinator.health_snapshot(provider_id).to_h] }
    assert_equal live_health, coordinator.health_projection.to_h
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    assert_equal({ "A" => 1 }, analytics.health_exclusion_count_by_provider)
    assert_equal 1, analytics.exclusion_count_by_code.fetch(:quarantined)
    assert_equal({ optimizer_choice: { count: 1, measure: 1 } }, analytics.deviation_by_cause)
  end

  def test_route_scoped_provider_failure_does_not_quarantine_another_route
    card = RubyRouting::RoutingContext.new(payment_method: :card)
    card_with_label = RubyRouting::RoutingContext.new(
      payment_method: :card,
      labels: ["tenant-a"]
    )
    bank = RubyRouting::RoutingContext.new(payment_method: :bank_transfer)
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          route_capabilities: RubyRouting::ProviderRouteCapabilities.new(
            supported_payment_methods: %i[card bank_transfer]
          )
        )
      ],
      health_policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 1
      )
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "route-scoped-health",
      epoch: "1",
      measure: :count,
      targets: { "A" => 10 }
    )

    first = coordinator.prepare_and_commit_decision(
      intent: intent_with_route("route-scoped-card", card),
      policy: policy
    )
    assert_equal "A", first.proposal.provider_id
    coordinator.mark_attempt_started(first)
    coordinator.apply_observation(observation(first, :safe_route_failure))

    assert_equal :quarantined, coordinator.health_snapshot("A", routing_context: card).state
    assert_equal :quarantined,
      coordinator.health_snapshot("A", routing_context: card_with_label).state
    assert_equal :healthy, coordinator.health_snapshot("A", routing_context: bank).state
    assert_equal :healthy, coordinator.health_snapshot("A").state

    second = coordinator.prepare_and_commit_decision(
      intent: intent_with_route("route-scoped-bank", bank),
      policy: policy
    )
    assert_equal "A", second.proposal.provider_id
    assert_equal :quarantined,
      coordinator.health_projection.snapshot("A", routing_context: card).state
    assert_equal :healthy,
      coordinator.health_projection.snapshot("A", routing_context: bank).state

    restored = RubyRouting::State::Coordinator.from_facts(facts: coordinator.facts)
    assert_equal coordinator.health_snapshot("A", routing_context: card).to_h,
      restored.health_snapshot("A", routing_context: card).to_h
    assert_equal coordinator.health_snapshot("A", routing_context: bank).to_h,
      restored.health_snapshot("A", routing_context: bank).to_h
    assert_equal second.proposal.provider_id,
      restored.payout_snapshot("route-scoped-bank").ownership.provider_id
  end

  def test_route_scoped_health_query_exposes_the_admission_state_without_global_pooling
    route = RubyRouting::RoutingContext.new(payment_method: :card)
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")],
      health_policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 1
      )
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "route-health-query",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    payout = intent_with_route("route-health-query-payout", route)
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(observation(commit, :safe_route_failure))
    queries = RubyRouting::Application::Queries.new(
      coordinator: coordinator,
      policy_registry: RubyRouting::PolicyRegistry.new
    )

    assert_equal :healthy, queries.health.to_h.fetch("A").fetch(:state)
    assert_equal :quarantined,
      queries.health(routing_context: route).snapshot("A").state
    assert_equal :quarantined,
      RubyRouting::State::Coordinator.from_facts(facts: coordinator.facts)
        .health_projection(routing_context: route).snapshot("A").state
  end

  def test_ranking_breaks_only_allocation_ties_inside_feasible_set
    policy = RubyRouting::RoutingPolicy.new(
      id: "ranked",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      ranking: RubyRouting::RankingPolicy.new(priority_by_provider: { "B" => 10, "A" => 1 })
    )

    allocation = RubyRouting::Routing::Allocation.choose(
      policy: policy,
      candidates: %w[A B],
      snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      incoming_measure: 1
    )
    assert_equal "A", allocation.chosen_provider
    assert_equal %w[A B], allocation.allocation_tie_candidates

    decision = RubyRouting::Routing::ConstrainedOptimizer.choose(
      policy: policy,
      allocation: allocation
    )

    assert_equal "B", decision.chosen_provider
  end

  private

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def intent_with_route(id, routing_context)
    RubyRouting::PayoutIntent.new(
      id: id,
      money: RubyRouting::Money.new(100, "RUB"),
      routing_context: routing_context
    )
  end

  def observation(commit, status, attribution: :provider)
    RubyRouting::ProviderObservation.new(
      observation_id: "health:#{commit.proposal.operation_id}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(status: status, attribution: attribution)
    )
  end

  class TimedProvider
    def initialize(clock:, duration_seconds:, response:)
      @clock = clock
      @duration_seconds = duration_seconds
      @response = response
    end

    def initiate(request)
      @clock.advance(@duration_seconds)
      return RubyRouting::ProviderTransportResult.new(kind: :ambiguous_after_possible_send) if @response == :ambiguous

      status, attribution = if @response == :recipient_failure
        [:terminal_payout_failure, :recipient]
      else
        [:success, :provider]
      end
      RubyRouting::ProviderObservation.new(
        observation_id: "timed:#{request.operation_id}",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.new(status: status, attribution: attribution),
        observed_at: @clock.now
      )
    end

    def resolve(request)
      initiate(request)
    end
  end
end
