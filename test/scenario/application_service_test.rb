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

  def test_provider_query_projects_current_runtime_over_the_active_definition
    opportunity = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity])
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: {}
    )

    coordinator.set_provider_availability("A", available: false, capacity_available: false)

    provider = service.queries.provider("A")
    refute provider.available
    refute provider.capacity_available
    assert service.queries.configuration.provider_opportunities.first.available
    assert service.queries.configuration.provider_opportunities.first.capacity_available
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

  def test_configuration_store_rejects_uncoordinated_public_mutation
    policy = policy_for("read-only-configuration-store")
    replacement = RubyRouting::Application::RoutingConfiguration.new(
      policies: [policy_for("uncoordinated-replacement", provider_id: "B")]
    )
    store = RubyRouting::Application::ConfigurationStore.new(
      configuration: RubyRouting::Application::RoutingConfiguration.new(policies: [policy])
    )

    assert_raises(NoMethodError) { store.replace(replacement) }
    assert_raises(NoMethodError) { store.update { replacement } }
    assert_equal 0, store.revision
    assert_equal ["read-only-configuration-store"], store.current.policies.map(&:id)
  end

  def test_application_fails_closed_when_coordinator_catalog_drifts_out_of_band
    policy = policy_for("catalog-drift")
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: {
        "A" => TestSupport::Simulator::ScriptedProvider.new(
          provider_id: "A",
          steps: [TestSupport::Simulator::Step.success]
        )
      }
    )
    service.commands.register_policy(policy)

    coordinator.replace_provider_opportunities([
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ])

    error = assert_raises(RubyRouting::ConfigurationDriftError) do
      service.submit(
        intent: RubyRouting::PayoutIntent.new(
          id: "catalog-drift-payout",
          money: RubyRouting::Money.new(1, "RUB")
        )
      )
    end
    assert_equal "active provider configuration does not match the Coordinator catalog", error.message
    assert_raises(RubyRouting::ConfigurationDriftError) { service.queries.providers }
    assert_raises(RubyRouting::ConfigurationDriftError) { service.queries.configuration }
    assert_empty service.queries.audit_facts(payout_id: "catalog-drift-payout")
  end

  def test_application_resume_checks_catalog_drift_before_expiring_unresolved_state
    clock = TestSupport::ControlledClock.new
    policy = RubyRouting::RoutingPolicy.new(
      id: "catalog-drift-resume",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 2, ttl_seconds: 3)
    )
    provider = Class.new do
      def initiate(_request)
        RubyRouting::ProviderTransportResult.ambiguous_after_possible_send
      end

      def resolve(_request)
        RubyRouting::ProviderTransportResult.ambiguous_after_possible_send
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        )
      ]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy)
    payout = RubyRouting::PayoutIntent.new(
      id: "catalog-drift-resume-payout",
      money: RubyRouting::Money.new(1, "RUB")
    )

    assert_equal :unknown, service.submit(intent: payout).status
    before = coordinator.facts.select { |fact| fact.payout_id == payout.id }
    coordinator.replace_provider_opportunities([
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ])
    clock.advance(4)

    assert_raises(RubyRouting::ConfigurationDriftError) do
      service.resume(payout_id: payout.id)
    end
    assert_equal before, coordinator.facts.select { |fact| fact.payout_id == payout.id }
    assert_equal :unknown, coordinator.payout_snapshot(payout.id).status
  end

  def test_configuration_snapshot_exposes_non_blocking_diagnostics
    policy = policy_for("diagnostic-warning")
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    configuration = RubyRouting::Application::RoutingConfiguration.new(policies: [policy])

    service.apply_configuration(configuration)

    snapshot = service.queries.configuration_snapshot
    assert_equal :valid_with_warnings, service.queries.configuration_status
    assert_equal snapshot.diagnostics, service.queries.configuration_diagnostics
    diagnostic = snapshot.diagnostics.find { |value| value.code == :target_provider_not_configured }
    refute_nil diagnostic
    assert_equal :warning, diagnostic.severity
    assert_equal policy.scope_key, diagnostic.policy_scope_key
    assert_equal "A", diagnostic.provider_id
    assert_equal :valid_with_warnings, configuration.compile.status
  end

  def test_configuration_compiler_rejects_static_provider_incompatibility_without_mutation
    policy = RubyRouting::RoutingPolicy.new(
      id: "diagnostic-incompatible",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      selector: { currency: "RUB", payment_method: "card", maximum_amount_minor: 500 }
    )
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      supported_currencies: ["USD"],
      supported_payment_methods: ["bank_transfer"],
      minimum_amount_minor: 1_000
    )
    coordinator = RubyRouting::State::Coordinator.new
    service = RubyRouting::Application::Service.new(coordinator: coordinator, providers: {})
    before_revision = service.queries.configuration_revision
    configuration = RubyRouting::Application::RoutingConfiguration.new(
      policies: [policy], provider_opportunities: [opportunity]
    )

    error = assert_raises(RubyRouting::Application::ConfigurationCompilationError) do
      service.apply_configuration(configuration)
    end

    assert_equal :invalid, error.compilation.status
    assert_equal %i[provider_amount_incompatible provider_currency_incompatible provider_route_incompatible],
      error.compilation.errors.map(&:code)
    assert_equal before_revision, service.queries.configuration_revision
    assert_empty coordinator.provider_opportunities
    assert_empty service.queries.policies
  end

  def test_configuration_compiler_rejects_static_infeasible_policy_before_publish
    policy = RubyRouting::RoutingPolicy.new(
      id: "diagnostic-infeasible",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      hard_constraints: { excluded_provider_ids: ["A"] }
    )
    configuration = RubyRouting::Application::RoutingConfiguration.new(
      policies: [policy], provider_opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )

    compilation = configuration.compile
    assert_equal :invalid, compilation.status
    assert_equal [:policy_static_infeasible], compilation.errors.map(&:code)
    assert_raises(RubyRouting::Application::ConfigurationCompilationError) do
      service.apply_configuration(configuration)
    end
    assert_equal 0, service.queries.configuration_revision
    assert_empty service.queries.providers

    bounded_policy = RubyRouting::RoutingPolicy.new(
      id: "diagnostic-effective-amounts",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      selector: { currency: "RUB", minimum_amount_minor: 100 },
      hard_constraints: { maximum_amount_minor: 500 }
    )
    incompatible = RubyRouting::Application::RoutingConfiguration.new(
      policies: [bounded_policy],
      provider_opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        minimum_amount_minor: 600
      )]
    ).compile

    assert_equal :invalid, incompatible.status
    assert_equal [:provider_amount_incompatible], incompatible.errors.map(&:code)
    assert_equal 100, incompatible.errors.first.details.fetch(:policy_minimum_amount_minor)
    assert_equal 500, incompatible.errors.first.details.fetch(:policy_maximum_amount_minor)
  end

  def test_configuration_compiler_rejects_disjoint_selector_and_hard_amount_ranges
    policy = RubyRouting::RoutingPolicy.new(
      id: "diagnostic-disjoint-amounts",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      selector: { currency: "RUB", minimum_amount_minor: 100 },
      hard_constraints: { maximum_amount_minor: 10 }
    )
    configuration = RubyRouting::Application::RoutingConfiguration.new(
      policies: [policy],
      provider_opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )

    compilation = configuration.compile
    assert_equal :invalid, compilation.status
    assert_equal [:policy_static_infeasible], compilation.errors.map(&:code)
    assert_raises(RubyRouting::Application::ConfigurationCompilationError) do
      service.apply_configuration(configuration)
    end
    assert_equal 0, service.queries.configuration_revision
    assert_empty service.queries.providers
  end

  def test_configuration_publish_rolls_back_provider_catalog_after_post_commit_failure
    coordinator_class = Class.new(RubyRouting::State::Coordinator) do
      def fail_after_next_provider_replacement!
        @fail_after_provider_replacement = true
      end

      def replace_provider_opportunities(opportunities)
        super
        return unless @fail_after_provider_replacement

        @fail_after_provider_replacement = false
        raise "provider replacement acknowledgement failed after commit"
      end
    end
    coordinator = coordinator_class.new
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => TestSupport::Simulator::ScriptedProvider.new(provider_id: "A", steps: []) }
    )
    configuration = RubyRouting::Application::RoutingConfiguration.new(
      policies: [policy_for("rollback-policy")],
      provider_opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    coordinator.fail_after_next_provider_replacement!

    assert_raises(RuntimeError) { service.apply_configuration(configuration) }
    assert_equal 0, service.queries.configuration_revision
    assert_empty service.queries.providers
    assert_empty coordinator.provider_opportunities
    assert_empty service.policy_registry.policies
  end

  def test_invalid_provider_adapter_does_not_bootstrap_supplied_configuration
    policy = policy_for("invalid-adapter-bootstrap")
    opportunity = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    store = RubyRouting::Application::ConfigurationStore.new(
      configuration: RubyRouting::Application::RoutingConfiguration.new(
        policies: [policy],
        provider_opportunities: [opportunity]
      )
    )
    coordinator = RubyRouting::State::Coordinator.new

    assert_raises(ArgumentError) do
      RubyRouting::Application::Service.new(
        coordinator: coordinator,
        providers: { "A" => Object.new },
        configuration_store: store
      )
    end

    assert_empty coordinator.provider_opportunities
    assert_equal 0, store.revision
  end

  def test_policy_registry_post_commit_failure_rolls_back_active_generation
    registry_class = Class.new(RubyRouting::PolicyRegistry) do
      def fail_after_next_replacement!
        @fail_after_replacement = true
      end

      def replace!(policies)
        result = super
        return result unless @fail_after_replacement

        @fail_after_replacement = false
        raise "policy replacement acknowledgement failed after commit"
      end
    end
    registry = registry_class.new
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {},
      policy_registry: registry
    )
    registry.fail_after_next_replacement!

    assert_raises(RuntimeError) { service.commands.register_policy(policy_for("registry-rollback")) }
    assert_equal 0, service.queries.configuration_revision
    assert_empty service.queries.policies
    assert_empty service.policy_registry.policies
  end

  def test_active_configuration_publishes_immutable_monotonic_revisions
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    initial = service.queries.configuration_snapshot
    first_configuration = RubyRouting::Application::RoutingConfiguration.new(
      policies: [policy_for("revision-one")],
      provider_opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    second_configuration = RubyRouting::Application::RoutingConfiguration.new(
      policies: [policy_for("revision-two", provider_id: "B")],
      provider_opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "B")]
    )

    assert_equal 0, initial.revision
    assert initial.frozen?
    assert_equal initial.configuration, service.queries.configuration

    service.apply_configuration(first_configuration)
    first = service.queries.configuration_snapshot
    service.apply_configuration(second_configuration)
    second = service.queries.configuration_snapshot

    assert_equal 1, first.revision
    assert_equal 2, second.revision
    assert_equal 2, service.queries.configuration_revision
    assert_equal first_configuration.to_h, first.configuration.to_h
    assert_equal second_configuration.to_h, second.configuration.to_h
    assert_equal second_configuration, service.queries.configuration
    refute_same first, second
  end

  def test_decision_trace_records_active_configuration_revision_for_explanation_and_audit
    policy = policy_for("trace-revision")
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [provider])
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => TestSupport::Simulator::ScriptedProvider.new(
        provider_id: "A",
        steps: [TestSupport::Simulator::Step.success]
      ) }
    )
    service.commands.register_policy(policy)
    intent = RubyRouting::PayoutIntent.new(
      id: "trace-revision-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )

    service.submit(intent: intent)

    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }
    decision = coordinator.facts.find do |fact|
      fact.type == :decision_committed && fact.payload[:action] == :assign
    end
    refute_nil evaluation
    refute_nil decision
    assert_equal 1, evaluation.payload.fetch(:configuration_revision)
    assert_equal 1, decision.payload.fetch(:configuration_revision)
    assert_equal 1, service.queries.explanation(intent.id).decisions.first.configuration_revision

    public_decision = RubyRouting::Projections::PublicAuditFact.from_fact(decision)
    assert_equal 1, public_decision.payload.fetch(:configuration_revision)
  end

  def test_resume_recovery_decision_records_the_active_configuration_revision
    clock = TestSupport::ControlledClock.new
    policy = RubyRouting::RoutingPolicy.new(
      id: "resume-trace-revision",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    provider = Class.new do
      def initialize
        @first_call = true
      end

      def initiate(request)
        if @first_call
          @first_call = false
          raise "simulated adapter crash after operation commit"
        end

        RubyRouting::ProviderObservation.new(
          observation_id: "resume-trace-revision-success",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end

      def resolve(_request)
        raise "status lookup is not configured"
      end
    end.new
    capabilities = RubyRouting::ProviderCapabilities.new(idempotent_retry: true)
    coordinator = RubyRouting::State::Coordinator.new(clock: clock)
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.apply_configuration(
      RubyRouting::Application::RoutingConfiguration.new(
        policies: [policy],
        provider_opportunities: [RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: capabilities
        )]
      )
    )
    intent = RubyRouting::PayoutIntent.new(
      id: "resume-trace-revision-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )

    assert_raises(RuntimeError) { service.submit(intent: intent) }
    assert_equal :success, service.resume(payout_id: intent.id).status

    restart_decision = coordinator.facts.reverse.find do |fact|
      fact.type == :decision_committed && fact.payload[:reason_codes] == [:restart_recovery]
    end
    refute_nil restart_decision
    assert_equal service.queries.configuration_revision,
      restart_decision.payload.fetch(:configuration_revision)
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

  def test_supplied_configuration_store_seeds_and_remains_the_policy_source_of_truth
    seeded_policy = policy_for("seeded-policy")
    added_policy = policy_for("added-policy", provider_id: "B")
    store = RubyRouting::Application::ConfigurationStore.new(
      configuration: RubyRouting::Application::RoutingConfiguration.new(
        policies: [seeded_policy]
      )
    )
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {},
      configuration_store: store
    )

    assert_equal ["seeded-policy"], service.policy_registry.policies.map(&:id)
    service.commands.register_policy(added_policy)

    assert_equal ["added-policy", "seeded-policy"], service.queries.policies.map(&:id).sort
    assert_equal service.queries.policies.map(&:id).sort, service.policy_registry.policies.map(&:id).sort
  end

  def test_supplied_configuration_store_bootstraps_provider_history_for_restore
    policy = policy_for("bootstrap-policy")
    opportunity = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    store = RubyRouting::Application::ConfigurationStore.new(
      configuration: RubyRouting::Application::RoutingConfiguration.new(
        policies: [policy],
        provider_opportunities: [opportunity]
      )
    )
    coordinator = RubyRouting::State::Coordinator.new
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.success]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider },
      configuration_store: store
    )

    result = service.submit(
      intent: RubyRouting::PayoutIntent.new(
        id: "bootstrap-payout",
        money: RubyRouting::Money.new(100, "RUB")
      )
    )
    restored = RubyRouting::State::Coordinator.from_facts(facts: coordinator.facts)

    assert_equal :success, result.status
    assert_equal ["A"], coordinator.provider_opportunities.map(&:provider_id)
    assert_equal :success, restored.payout_snapshot(result.payout.id).status
    assert_equal result.payout.attempts.map(&:contract).map(&:to_h),
      restored.payout_snapshot(result.payout.id).attempts.map(&:contract).map(&:to_h)
  end

  def test_supplied_policy_registry_cannot_diverge_from_active_configuration
    configuration_policy = policy_for("configuration-policy")
    registry_policy = policy_for("registry-policy")
    store = RubyRouting::Application::ConfigurationStore.new(
      configuration: RubyRouting::Application::RoutingConfiguration.new(
        policies: [configuration_policy]
      )
    )

    error = assert_raises(ArgumentError) do
      RubyRouting::Application::Service.new(
        coordinator: RubyRouting::State::Coordinator.new,
        providers: {},
        policy_registry: RubyRouting::PolicyRegistry.new([registry_policy]),
        configuration_store: store
      )
    end

    assert_equal "policy_registry and configuration_store must share one active policy set", error.message
  end

  def test_application_policy_registry_is_read_only_compatibility_view
    policy = policy_for("read-only-registry-policy")
    registry = RubyRouting::PolicyRegistry.new
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {},
      policy_registry: registry
    )

    refute_respond_to service.policy_registry, :register
    refute_respond_to service.commands.policy_registry, :replace!
    refute_respond_to service.queries.policy_registry, :register
    assert_raises(ArgumentError) { registry.register(policy) }
    assert_empty service.queries.policies

    service.commands.register_policy(policy)

    assert_equal [policy.id], service.queries.policies.map(&:id)
    assert_equal [policy.id], service.policy_registry.policies.map(&:id)
    assert_equal [policy.id], service.queries.policy_registry.policies.map(&:id)
  end

  def test_query_policy_registry_view_tracks_the_active_application_registry
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    policy = policy_for("query-registry-view")

    service.commands.register_policy(policy)

    assert_equal service.queries.policies, service.queries.policy_registry.policies
    refute_respond_to service.queries.policy_registry, :register
  end

  def test_policy_registry_views_do_not_expose_a_partially_published_generation
    registry_class = Class.new(RubyRouting::PolicyRegistry) do
      attr_reader :replacement_started

      def initialize(policies = [])
        super(policies)
        @replacement_started = Queue.new
        @release = Queue.new
      end

      def replace!(policies)
        result = super
        @replacement_started << true
        @release.pop
        result
      end

      def release_replacement!
        @release << true
      end
    end
    store_class = Class.new(RubyRouting::Application::ConfigurationStore) do
      attr_reader :snapshot_attempted

      def initialize(configuration:)
        super(configuration: configuration)
        @snapshot_attempted = Queue.new
      end

      def with_snapshot(&block)
        @snapshot_attempted << true
        super(&block)
      end
    end

    initial = policy_for("atomic-view-initial")
    published = policy_for("atomic-view-published")
    opportunity = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    configuration = RubyRouting::Application::RoutingConfiguration.new(
      policies: [initial],
      provider_opportunities: [opportunity]
    )
    registry = registry_class.new([initial])
    store = store_class.new(configuration: configuration)
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new(opportunities: [opportunity]),
      providers: {},
      policy_registry: registry,
      configuration_store: store
    )

    writer = Thread.new { service.commands.register_policy(published) }
    reader_result = Queue.new
    reader = nil
    released = false

    begin
      registry.replacement_started.pop
      reader = Thread.new do
        reader_result << service.policy_registry.policies.map(&:id)
      end
      Timeout.timeout(2) { store.snapshot_attempted.pop }

      assert_empty reader_result
    ensure
      unless released
        registry.release_replacement!
        released = true
      end
      writer.join
      reader&.join
    end

    assert_equal [initial.id, published.id], reader_result.pop
    assert_equal [initial.id, published.id], service.queries.configuration_snapshot.policies.map(&:id)
  end

  def test_application_cannot_share_a_policy_registry_with_another_active_generation
    registry = RubyRouting::PolicyRegistry.new
    RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {},
      policy_registry: registry
    )

    error = assert_raises(ArgumentError) do
      RubyRouting::Application::Service.new(
        coordinator: RubyRouting::State::Coordinator.new,
        providers: {},
        policy_registry: registry
      )
    end

    assert_equal "policy registry is already bound to another application", error.message
  end

  def test_rejected_application_bootstrap_does_not_mutate_a_second_provider_catalog
    policy = policy_for("bootstrap-ownership", provider_id: "A")
    opportunity = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    store = RubyRouting::Application::ConfigurationStore.new(
      configuration: RubyRouting::Application::RoutingConfiguration.new(
        policies: [policy],
        provider_opportunities: [opportunity]
      )
    )
    registry = RubyRouting::PolicyRegistry.new([policy])
    RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {},
      policy_registry: registry,
      configuration_store: store
    )
    second_coordinator = RubyRouting::State::Coordinator.new

    error = assert_raises(ArgumentError) do
      RubyRouting::Application::Service.new(
        coordinator: second_coordinator,
        providers: {},
        policy_registry: registry,
        configuration_store: store
      )
    end

    assert_equal "policy registry is already bound to another application", error.message
    assert_empty second_coordinator.provider_opportunities
  end

  def test_failed_application_bootstrap_does_not_capture_policy_registry
    registry = RubyRouting::PolicyRegistry.new([policy_for("retryable-bootstrap")])

    assert_raises(ArgumentError) do
      RubyRouting::Application::Service.new(
        coordinator: RubyRouting::State::Coordinator.new,
        providers: { "A" => Object.new },
        policy_registry: registry
      )
    end

    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {},
      policy_registry: registry
    )

    assert_equal ["retryable-bootstrap"], service.policy_registry.policies.map(&:id)
  end

  def policy_for(id, provider_id: "A")
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: { provider_id => 1 }
    )
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
