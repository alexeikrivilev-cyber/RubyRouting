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
