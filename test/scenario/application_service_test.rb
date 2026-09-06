# frozen_string_literal: true

require_relative "../test_helper"

class ApplicationServiceTest < Minitest::Test
  def test_commands_and_queries_share_the_canonical_routing_surface
    policy = RubyRouting::RoutingPolicy.new(
      id: "application-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    intent = RubyRouting::PayoutIntent.new(
      id: "application-payout",
      money: RubyRouting::Money.new(100, "RUB"),
      context: { labels: ["retail"] }
    )
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )

    assert_equal policy, service.commands.register_policy(policy)
    result = service.submit(intent: intent)

    assert_equal :success, result.status
    assert_equal result.payout.status, service.queries.get_payout(intent.id).status
    assert_equal result.payout.settlement_operation_id, service.queries.get_payout(intent.id).settlement_operation_id
    assert_equal policy, service.queries.policies.fetch(0)
    assert_equal ["A"], service.queries.providers.map(&:provider_id)
    assert_equal :success, service.queries.lifecycle.payout(intent.id).status
    assert_equal 1, service.queries.audit_facts(payout_id: intent.id, type: :settlement_recorded).length
    assert_equal 1, service.queries.analytics.eventual_success_count
  end

  def test_public_payout_identity_is_canonicalized_for_queries_and_policy_lookup
    policy = RubyRouting::RoutingPolicy.new(
      id: "payout-identity-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    intent = RubyRouting::PayoutIntent.new(
      id: " payout-identity ",
      money: RubyRouting::Money.new(100, "RUB")
    )
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy)

    result = service.submit(intent: intent)

    assert_equal :success, service.queries.get_payout(" payout-identity ").status
    assert_equal policy, service.queries.policy_for(" payout-identity ")
    assert_equal :success, service.queries.lifecycle.payout(" payout-identity ").status
    assert_equal "A", service.queries.capacity.snapshot(" A ").provider_id
    assert_equal "A", service.queries.throughput.snapshot(" A ").provider_id
    assert_equal 1, service.queries.audit_facts(
      payout_id: " payout-identity ",
      type: :intent_registered
    ).count
    assert_equal result.payout.id, coordinator.payout_snapshot(" payout-identity ").id
  end

  def test_provider_configuration_commands_update_only_provider_state
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: {
        "A" => TestSupport::Simulator::ScriptedProvider.new(provider_id: "A", steps: [])
      }
    )

    assert_nil service.commands.set_provider_availability("A", available: false)
    assert_equal :unavailable, service.queries.provider("A").reason
    assert_equal 1, service.queries.audit_facts(type: :provider_runtime_changed).length
    assert_equal 1, service.queries.audit_facts(type: :provider_opportunity_registered).length
  end

  def test_typed_configuration_is_applied_and_queryable_as_one_active_snapshot
    policy = RubyRouting::RoutingPolicy.new(
      id: "active-config-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      selector: { payment_method: "card", priority: 3 }
    )
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
      route_capabilities: RubyRouting::ProviderRouteCapabilities.new(
        supported_payment_methods: ["card"]
      ),
      capacity: RubyRouting::CapacityBudget.new(max_slots: 2)
    )
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: { "A" => TestSupport::Simulator::ScriptedProvider.new(provider_id: "A", steps: []) }
    )
    configuration = RubyRouting::Application::RoutingConfiguration.new(
      policies: [policy],
      provider_opportunities: [opportunity]
    )

    applied = service.apply_configuration(configuration)

    assert_same configuration, applied
    assert_same configuration, service.queries.configuration
    assert configuration.frozen?
    assert_equal configuration.to_h, service.queries.configuration.to_h
    assert_equal ["active-config-policy"], service.queries.policies.map(&:id)
    assert_equal ["A"], service.queries.providers.map(&:provider_id)
    assert_equal 2, service.queries.providers.first.capacity.max_slots
    assert_empty service.queries.audit_facts(type: :policy_registered)
  end

  def test_active_configuration_change_does_not_rewrite_an_unresolved_pinned_route
    clock = TestSupport::ControlledClock.new
    provider_a = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      clock: clock,
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
      steps: [TestSupport::Simulator::Step.unknown, TestSupport::Simulator::Step.success]
    )
    provider_b = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "B",
      clock: clock,
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(clock: clock)
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b }
    )
    policy_a = RubyRouting::RoutingPolicy.new(
      id: "historical-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    policy_b = RubyRouting::RoutingPolicy.new(
      id: "current-policy",
      epoch: "1",
      measure: :count,
      targets: { "B" => 1 }
    )
    opportunity_a = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    opportunity_b = RubyRouting::ProviderOpportunity.new(provider_id: "B")

    service.apply_configuration(
      RubyRouting::Application::RoutingConfiguration.new(
        policies: [policy_a], provider_opportunities: [opportunity_a]
      )
    )
    payout = RubyRouting::PayoutIntent.new(
      id: "config-pinned-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )
    first = service.submit(intent: payout)

    service.apply_configuration(
      RubyRouting::Application::RoutingConfiguration.new(
        policies: [policy_b], provider_opportunities: [opportunity_b]
      )
    )
    resumed = service.resume(payout_id: payout.id)

    assert_equal :unknown, first.status
    assert_equal :success, resumed.status
    assert_equal policy_a, coordinator.policy_for(payout.id)
    assert_equal ["current-policy"], service.queries.policies.map(&:id)
    assert_equal ["B"], service.queries.providers.map(&:provider_id)
    assert_equal [
      [:initiate, "config-pinned-payout:config-pinned-payout:operation:1"],
      [:resolve, "config-pinned-payout:config-pinned-payout:operation:1"]
    ], provider_a.calls
    assert_empty provider_b.calls
  end

  def test_invalid_configuration_is_rejected_before_provider_catalog_mutation
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    invalid = RubyRouting::Application::RoutingConfiguration.allocate

    assert_raises(ArgumentError) { service.apply_configuration(invalid) }
    assert_empty service.queries.providers
    assert_empty service.queries.policies
  end

  def test_provider_event_boundary_canonicalizes_provider_id_before_normalization
    adapter = Class.new do
      include RubyRouting::Ports::Provider

      def initiate(_request)
        RubyRouting::ProviderTransportResult.ambiguous_after_possible_send
      end

      def resolve(_request)
        raise "not used"
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => adapter }
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "webhook-canonical-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    service.commands.register_policy(policy)
    payout = RubyRouting::PayoutIntent.new(
      id: "webhook-canonical-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )
    result = service.submit(intent: payout)
    attempt = result.payout.current_operation
    normalizer = Class.new do
      define_method(:normalize) do |raw:, provider_id:|
        RubyRouting::ProviderObservation.new(
          observation_id: raw.fetch(:observation_id),
          payout_id: raw.fetch(:payout_id),
          provider_id: provider_id,
          operation_id: raw.fetch(:operation_id),
          attempt_id: raw.fetch(:attempt_id),
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end
    end.new

    application = service.commands.reconcile_provider_event(
      provider_id: " A ",
      raw: {
        observation_id: "canonical-webhook-success",
        payout_id: payout.id,
        operation_id: attempt.operation_id,
        attempt_id: attempt.attempt_id
      },
      normalizer: normalizer
    )

    assert_equal :success, application.payout.status
    assert_equal "A", application.payout.settlement_provider_id
  end

  def test_audit_type_validation_prevents_transport_values_from_becoming_domain_facts
    coordinator = RubyRouting::State::Coordinator.new
    service = RubyRouting::Application::Service.new(coordinator: coordinator, providers: {})

    assert_raises(ArgumentError) { service.queries.audit_facts(type: :made_up_fact) }
  end

  def test_reconcile_command_requires_provider_normalization
    coordinator = RubyRouting::State::Coordinator.new
    service = RubyRouting::Application::Service.new(coordinator: coordinator, providers: {})

    assert_raises(ArgumentError) do
      service.commands.reconcile(observation: { safe_to_release: true })
    end

    forged = RubyRouting::ProviderObservation.new(
      observation_id: "forged-application-observation",
      payout_id: "forged-application-payout",
      provider_id: "A",
      operation_id: "forged-operation",
      attempt_id: "forged-attempt",
      outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
    )
    assert_raises(ArgumentError) do
      service.commands.reconcile(observation: forged)
    end
  end
end
