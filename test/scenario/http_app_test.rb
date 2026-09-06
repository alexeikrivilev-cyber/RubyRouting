# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "stringio"

class HttpAppTest < Minitest::Test
  def test_http_adapter_exposes_submit_query_and_analytics_without_routing_logic
    policy = one_provider_policy("http-policy")
    provider = Class.new do
      include RubyRouting::Ports::Provider

      def initiate(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "http-success",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end

      def resolve(_request)
        raise "resolve should not be called"
      end
    end.new
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new(
        opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
      ),
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy)
    app = RubyRouting::Application::HttpApp.new(service: service)

    health = call(app, method: "GET", path: "/health")
    submitted = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: { "id" => "http-payout", "amount_minor" => 100, "currency" => "RUB" }
    )
    fetched = call(app, method: "GET", path: "/v1/payouts/http-payout")
    analytics = call(app, method: "GET", path: "/v1/analytics")
    analytics_query = call(
      app,
      method: "GET",
      path: "/v1/analytics",
      query: "metric=settlement_measure&measure=count&group_by=provider_id"
    )

    assert_equal 200, health.fetch(0)
    assert_equal "ok", parse(health).fetch("status")
    assert_equal 201, submitted.fetch(0)
    assert_equal "success", parse(submitted).fetch("status")
    assert_equal 200, fetched.fetch(0)
    assert_equal "success", parse(fetched).fetch("payout").fetch("status")
    assert_equal 200, analytics.fetch(0)
    assert_equal 1, parse(analytics).fetch("eventual_success_count")
    assert_equal 200, analytics_query.fetch(0)
    assert_equal "settlement_measure", parse(analytics_query).fetch("metric")
    assert_equal [{ "group" => { "provider_id" => "A" }, "value" => 1 }],
      parse(analytics_query).fetch("rows")
  end

  def test_http_does_not_report_post_provider_contract_failure_as_invalid_request
    policy = one_provider_policy("http-post-provider-contract")
    provider = Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def initiate(request)
        @calls << [request.operation_id, request.attempt_id]
        RubyRouting::ProviderObservation.new(
          observation_id: "http-malformed-observation",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: "wrong-operation",
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
        )
      end

      def resolve(_request)
        raise "resolve should not be called"
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy)
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: { "id" => "http-post-provider-contract-payout", "amount_minor" => 100, "currency" => "RUB" }
    )

    snapshot = service.queries.payout("http-post-provider-contract-payout")
    owner = snapshot.ownership
    facts = service.queries.audit_facts(payout_id: snapshot.id)

    assert_equal 502, response.fetch(0)
    assert_equal({ "error" => "provider_contract_error" }, parse(response))
    refute_includes response.join, "wrong-operation"
    assert_equal 1, provider.calls.length
    assert_equal [owner.operation_id, owner.attempt_id], provider.calls.fetch(0)
    assert_equal :pending, snapshot.status
    assert_equal :dispatching, snapshot.current_operation_phase
    assert_equal "A", owner.provider_id
    assert_equal 1, snapshot.provider_interaction_count
    refute coordinator.__send__(:provider_interaction_in_flight?, snapshot.id, owner.operation_id)
    assert_equal 0, facts.count { |fact| fact.type == :provider_interaction_completed }
    assert_equal 0, facts.count { |fact| fact.type == :provider_observed }
    assert_equal 0, facts.count { |fact| fact.type == :provider_execution_failed }
  end

  def test_http_reports_post_return_application_fault_as_internal_error
    observation_class = Class.new(RubyRouting::ProviderObservation) do
      def with_interaction_duration(_duration_seconds)
        raise RuntimeError, "application-only processing detail"
      end
    end
    provider = Class.new do
      define_method(:initiate) do |request|
        observation_class.new(
          observation_id: "http-application-fault",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end

      def resolve(_request)
        raise "resolve must not be called"
      end
    end.new
    policy = one_provider_policy("http-application-fault")
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy)
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: { "id" => "http-application-fault-payout", "amount_minor" => 100, "currency" => "RUB" }
    )

    snapshot = service.queries.payout("http-application-fault-payout")
    assert_equal 500, response.fetch(0)
    assert_equal({ "error" => "internal_error" }, parse(response))
    assert_equal :pending, snapshot.status
    assert_equal :dispatching, snapshot.current_operation_phase
    assert_equal "A", snapshot.ownership.provider_id
    refute coordinator.__send__(
      :provider_interaction_in_flight?,
      snapshot.id,
      snapshot.ownership.operation_id
    )
    assert_empty coordinator.facts.select { |fact| fact.type == :provider_execution_failed }
    assert_empty coordinator.facts.select { |fact| fact.type == :provider_observed }
    refute_includes response.join, "application-only processing detail"
  end

  def test_http_raw_provider_failure_is_generic_non_leaking_and_keeps_canonical_due_work
    clock = TestSupport::ControlledClock.new
    calls = []
    provider = Class.new do
      define_method(:initiate) do |request|
        calls << [:initiate, request.operation_id, request.attempt_id]
        raise Timeout::Error, "provider-secret raw failure"
      end

      define_method(:resolve) do |request|
        calls << [:resolve, request.operation_id, request.attempt_id]
        raise "resolve must be invoked only by an explicit canonical continuation"
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    policy = one_provider_policy("http-raw-provider-failure")
    service.commands.register_policy(policy)
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: { "id" => "http-raw-provider-failure-payout", "amount_minor" => 100, "currency" => "RUB" }
    )

    snapshot = service.queries.payout("http-raw-provider-failure-payout")
    due = service.queries.due_work(as_of: clock.now, limit: 1)
    assert_equal 500, response.fetch(0)
    assert_equal({ "error" => "internal_error" }, parse(response))
    refute_includes response.join, "provider-secret"
    assert_equal :pending, snapshot.status
    assert_equal :dispatching, snapshot.current_operation_phase
    assert_equal 1, snapshot.provider_interaction_count
    assert_equal [[:initiate, snapshot.ownership.operation_id, snapshot.ownership.attempt_id]], calls
    assert_equal 1, due.length
    assert_equal :resolve, due.first.action
    assert_equal :provider_execution_failure, due.first.reason_code
    assert_equal snapshot.ownership.operation_id, due.first.operation_id
    assert_equal snapshot.ownership.attempt_id, due.first.attempt_id
  end

  def test_http_exposes_configuration_diagnostics_and_due_recovery_work
    clock = TestSupport::ControlledClock.new
    provider = Class.new do
      def initiate(_request)
        RubyRouting::ProviderTransportResult.ambiguous_after_possible_send
      end

      def resolve(_request)
        RubyRouting::ProviderTransportResult.ambiguous_after_possible_send
      end
    end.new
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    coordinator = RubyRouting::State::Coordinator.new(clock: clock, opportunities: [opportunity])
    policy = one_provider_policy("http-control-plane-policy")
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy)
    app = RubyRouting::Application::HttpApp.new(service: service)

    configuration = call(app, method: "GET", path: "/v1/configuration")
    assert_equal 200, configuration.fetch(0)
    configuration_body = parse(configuration)
    assert_equal 1, configuration_body.fetch("revision")
    assert_equal "valid", configuration_body.fetch("status")
    assert_empty configuration_body.fetch("diagnostics")

    payout = RubyRouting::PayoutIntent.new(
      id: "http-due-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )
    result = service.submit(intent: payout)
    assert_equal :unknown, result.status
    due = call(
      app,
      method: "GET",
      path: "/v1/recovery/due-work",
      query: "as_of=#{URI.encode_www_form_component(clock.now.iso8601(9))}"
    )

    assert_equal 200, due.fetch(0)
    due_body = parse(due)
    assert_equal clock.now.iso8601(9), due_body.fetch("as_of")
    assert_equal [
      {
        "payout_id" => payout.id,
        "action" => "resolve",
        "provider_id" => "A",
        "operation_id" => result.payout.ownership.operation_id,
        "attempt_id" => result.payout.ownership.attempt_id,
        "due_at" => clock.now.iso8601(9),
        "reason_code" => "status_resolution",
        "status" => "unknown"
      }
    ], due_body.fetch("due_work")
  end

  def test_http_put_configuration_uses_the_canonical_decoder_and_application_publication
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new(
        opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
      ),
      providers: {}
    )
    service.commands.register_policy(one_provider_policy("http-put-configuration"))
    app = RubyRouting::Application::HttpApp.new(service: service)
    before = parse(call(app, method: "GET", path: "/v1/configuration"))
    configuration = before.fetch("configuration")

    response = call(app, method: "PUT", path: "/v1/configuration", body: configuration)

    assert_equal 200, response.fetch(0)
    body = parse(response)
    assert_equal before.fetch("revision") + 1, body.fetch("revision")
    assert_equal "valid", body.fetch("status")
    assert_equal configuration, body.fetch("configuration")
    assert_empty body.fetch("diagnostics")
    assert_equal body.fetch("revision"), service.queries.configuration_revision
    assert_equal configuration, JSON.parse(JSON.generate(service.queries.configuration.to_h))
  end

  def test_http_due_work_is_bounded_by_default_and_explicit_limit
    clock = TestSupport::ControlledClock.new
    provider = Class.new do
      def initiate(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "due-initiation-#{request.payout_id}",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :unknown)
        )
      end

      def resolve(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "due-resolution-#{request.payout_id}",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :unknown)
        )
      end
    end.new
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    coordinator = RubyRouting::State::Coordinator.new(clock: clock, opportunities: [opportunity])
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(one_provider_policy("http-due-bounded"))
    257.times do |index|
      service.submit(
        intent: RubyRouting::PayoutIntent.new(
          id: format("due-payout-%03d", index),
          money: RubyRouting::Money.new(100, "RUB")
        )
      )
    end
    app = RubyRouting::Application::HttpApp.new(service: service)

    default_response = call(app, method: "GET", path: "/v1/recovery/due-work")
    explicit_response = call(
      app,
      method: "GET",
      path: "/v1/recovery/due-work",
      query: "as_of=#{URI.encode_www_form_component(clock.now.iso8601(9))}&limit=1"
    )

    assert_equal 200, default_response.fetch(0)
    default_body = parse(default_response)
    assert_equal RubyRouting::Application::HttpApp::MAX_RECOVERY_BATCH_SIZE,
      default_body.fetch("due_work").length
    assert_equal "due-payout-000", default_body.fetch("due_work").first.fetch("payout_id")

    assert_equal 200, explicit_response.fetch(0)
    explicit_body = parse(explicit_response)
    assert_equal 1, explicit_body.fetch("due_work").length
    assert_equal "due-payout-000", explicit_body.fetch("due_work").first.fetch("payout_id")
    assert_equal clock.now.iso8601(9), explicit_body.fetch("as_of")
  end

  def test_http_due_work_rejects_invalid_bounds_before_querying
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    queries = [
      "limit=0",
      "limit=-1",
      "limit=#{RubyRouting::Application::HttpApp::MAX_RECOVERY_BATCH_SIZE + 1}",
      "limit=not-a-number",
      "limit=1&limit=2",
      "limit=1&unknown=value"
    ]

    queries.each do |query|
      response = call(app, method: "GET", path: "/v1/recovery/due-work", query: query)

      assert_equal 400, response.fetch(0), query
      assert_equal({ "error" => "invalid_request" }, parse(response), query)
    end
  end

  def test_http_provider_projection_exposes_configured_but_uncallable_adapters
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: []
    )
    configuration = RubyRouting::Application::RoutingConfiguration.new(
      provider_opportunities: %w[A B].map do |provider_id|
        RubyRouting::ProviderOpportunity.new(provider_id: provider_id)
      end
    )
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: { "A" => provider }
    )
    service.apply_configuration(configuration)
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(app, method: "GET", path: "/v1/providers")

    assert_equal 200, response.fetch(0)
    rows = parse(response).fetch("providers")
    availability = rows.to_h { |row| [row.fetch("provider_id"), row.fetch("adapter_available")] }
    assert_equal({ "A" => true, "B" => false }, availability)
    refute service.queries.configuration.provider_opportunities.any? { |opportunity| opportunity.to_h.key?(:adapter_available) }
  end

  def test_http_put_configuration_rejects_malformed_input_without_mutating_the_active_generation
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)
    before_revision = service.queries.configuration_revision
    before_configuration = service.queries.configuration.to_h
    malformed = [
      { "policies" => [], "provider_opportunities" => [], "unexpected" => true },
      { "policies" => [], "provider_opportunities" => [], "tolerance" => 0.5 }
    ]

    malformed.each do |body|
      response = call(app, method: "PUT", path: "/v1/configuration", body: body)

      assert_equal 400, response.fetch(0), body
      assert_equal({ "error" => "invalid_request" }, parse(response), body)
      assert_equal before_revision, service.queries.configuration_revision, body
      assert_equal before_configuration, service.queries.configuration.to_h, body
      assert_empty service.queries.providers, body
    end
  end

  def test_http_configuration_surface_round_trips_exact_rational_values
    configuration = RubyRouting::Application::RoutingConfiguration.new(
      policies: [RubyRouting::RoutingPolicy.new(
        id: "http-rational-configuration",
        epoch: "1",
        measure: :volume,
        targets: { "A" => 1 },
        currency: "USD",
        tolerance: Rational(1, 3),
        minimum_shares: { "A" => Rational(1, 4) }
      )],
      provider_opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    service.apply_configuration(configuration)
    app = RubyRouting::Application::HttpApp.new(service: service)

    before = parse(call(app, method: "GET", path: "/v1/configuration"))
    response = call(app, method: "PUT", path: "/v1/configuration", body: before.fetch("configuration"))

    assert_equal 200, response.fetch(0)
    assert_equal before.fetch("configuration"), parse(response).fetch("configuration")
    assert_equal Rational(1, 3), service.queries.configuration.policies.first.tolerance
    assert_equal Rational(1, 4), service.queries.configuration.policies.first.minimum_shares.fetch("A")
  end

  def test_http_put_configuration_returns_bounded_compiler_diagnostics_without_partial_publication
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)
    invalid = RubyRouting::Application::RoutingConfiguration.new(
      policies: [RubyRouting::RoutingPolicy.new(
        id: "http-invalid-configuration",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1 },
        hard_constraints: { excluded_provider_ids: ["A"] }
      )],
      provider_opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )

    response = call(app, method: "PUT", path: "/v1/configuration", body: invalid.to_h)

    assert_equal 422, response.fetch(0)
    body = parse(response)
    assert_equal "invalid_configuration", body.fetch("error")
    assert_equal "invalid", body.fetch("status")
    assert_equal ["policy_static_infeasible"], body.fetch("diagnostics").map { |diagnostic| diagnostic.fetch("code") }
    assert_equal 0, service.queries.configuration_revision
    assert_empty service.queries.providers
    assert_empty service.queries.policies
  end

  def test_http_recovery_run_delegates_to_the_bounded_executor_and_resolves_the_pinned_provider
    clock = TestSupport::ControlledClock.new
    provider = Class.new do
      attr_reader :calls

      def initialize(clock)
        @clock = clock
        @calls = []
      end

      def initiate(request)
        @calls << [:initiate, request.operation_id]
        RubyRouting::ProviderTransportResult.ambiguous_after_possible_send
      end

      def resolve(request)
        @calls << [:resolve, request.operation_id]
        RubyRouting::ProviderObservation.new(
          observation_id: "http-recovery-success",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider),
          observed_at: @clock.now
        )
      end
    end.new(clock)
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new(
        clock: clock,
        opportunities: [RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        )]
      ),
      providers: { "A" => provider }
    )
    service.commands.register_policy(one_provider_policy("http-recovery-run"))
    payout = RubyRouting::PayoutIntent.new(
      id: "http-recovery-run-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )
    initial = service.submit(intent: payout)
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(app, method: "POST", path: "/v1/recovery/run", body: { "limit" => 1 })

    assert_equal :unknown, initial.status
    assert_equal 200, response.fetch(0)
    body = parse(response)
    assert_equal 1, body.fetch("limit")
    assert_equal 1, body.fetch("items").length
    item = body.fetch("items").fetch(0)
    assert_equal "success", item.fetch("status")
    assert_equal "stop", item.fetch("action")
    assert_nil item.fetch("error")
    assert_equal "resolve", item.fetch("work_item").fetch("action")
    assert_equal [[:initiate, initial.payout.attempts.fetch(0).operation_id],
                  [:resolve, initial.payout.attempts.fetch(0).operation_id]], provider.calls
    assert_equal :success, service.queries.payout(payout.id).status
    assert_nil service.queries.payout(payout.id).ownership
  end

  def test_http_recovery_run_rejects_unbounded_or_malformed_controls_without_execution
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)
    requests = [
      [nil, "empty body"],
      [{}, "missing limit"],
      [{ "limit" => -1 }, "negative limit"],
      [{ "limit" => 1.5 }, "float limit"],
      [{ "limit" => true }, "boolean limit"],
      [{ "limit" => 257 }, "limit above endpoint bound"],
      [{ "limit" => 0, "unexpected" => true }, "unknown field"]
    ]

    requests.each do |body, label|
      response = call(app, method: "POST", path: "/v1/recovery/run", body: body)

      assert_equal 400, response.fetch(0), label
      assert_equal({ "error" => "invalid_request" }, parse(response), label)
      assert_empty service.queries.audit_facts, label
    end

    response = call(
      app,
      method: "POST",
      path: "/v1/recovery/run",
      query: "as_of=2026-09-01T00%3A00%3A00Z",
      body: { "limit" => 1 }
    )
    assert_equal 400, response.fetch(0)
    assert_equal({ "error" => "invalid_request" }, parse(response))
  end

  def test_http_recovery_run_does_not_expose_raw_provider_exception_messages
    clock = TestSupport::ControlledClock.new
    provider = Class.new do
      def initiate(_request)
        RubyRouting::ProviderTransportResult.ambiguous_after_possible_send
      end

      def resolve(_request)
        raise RuntimeError, "recipient-secret from provider response"
      end
    end.new
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new(
        clock: clock,
        opportunities: [RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        )]
      ),
      providers: { "A" => provider }
    )
    service.commands.register_policy(one_provider_policy("http-recovery-error-privacy"))
    service.submit(
      intent: RubyRouting::PayoutIntent.new(
        id: "http-recovery-error-privacy-payout",
        money: RubyRouting::Money.new(100, "RUB")
      )
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(app, method: "POST", path: "/v1/recovery/run", body: { "limit" => 1 })

    assert_equal 200, response.fetch(0)
    body = parse(response)
    assert_equal "RubyRouting::ProviderExecutionError", body.fetch("items").fetch(0).fetch("error").fetch("class")
    refute_includes JSON.generate(body), "recipient-secret"
  end

  def test_http_quality_query_replays_evidence_as_of_injected_time
    clock = TestSupport::ControlledClock.new
    quality_policy = RubyRouting::Routing::QualityPolicy.new(
      minimum_samples: 1,
      max_evidence_age_seconds: 10
    )
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      quality_policy: quality_policy,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = one_provider_policy("http-quality-time")
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.success]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    result = service.submit(
      intent: RubyRouting::PayoutIntent.new(
        id: "http-quality-time-payout",
        money: RubyRouting::Money.new(1, "RUB")
      ),
      policy: policy
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "GET",
      path: "/v1/quality",
      query: "currency=RUB&as_of=#{URI.encode_www_form_component(clock.now.iso8601(9))}"
    )

    assert_equal :success, result.status
    assert_equal 200, response.fetch(0)
    assert_equal 1, parse(response).fetch("providers").fetch("A").fetch("successful_samples")
    assert_equal false, parse(response).fetch("providers").fetch("A").fetch("stale")
  end

  def test_http_health_query_exposes_route_scoped_admission_state
    route = RubyRouting::RoutingContext.new(payment_method: :card)
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")],
      health_policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 1,
        recover_after: 1
      )
    )
    policy = one_provider_policy("http-route-health")
    payout = RubyRouting::PayoutIntent.new(
      id: "http-route-health-payout",
      money: RubyRouting::Money.new(1, "RUB"),
      routing_context: route
    )
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "http-route-health-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )
    service = RubyRouting::Application::Service.new(coordinator: coordinator, providers: {})
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(app, method: "GET", path: "/v1/health", query: "payment_method=card")

    assert_equal 200, response.fetch(0)
    assert_equal "quarantined", parse(response).fetch("providers").fetch("A").fetch("state")
  end

  def test_http_rejects_unknown_health_route_query_parameters_instead_of_using_global_state
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new(
        opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
      ),
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(app, method: "GET", path: "/v1/health", query: "payment_methd=card")

    assert_equal 400, response.fetch(0)
    assert_equal({ "error" => "invalid_request" }, parse(response))
  end

  def test_http_rejects_alias_health_route_query_parameters_instead_of_silently_broadening
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new(
        opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
      ),
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(app, method: "GET", path: "/v1/health", query: "destination_type=bank")

    assert_equal 400, response.fetch(0)
    assert_equal({ "error" => "invalid_request" }, parse(response))
  end

  def test_http_rejects_malformed_route_filters_even_when_projections_are_empty
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    requests = [
      ["/v1/health", "payment_method="],
      ["/v1/quality", "rail="],
      ["/v1/quality", "currency=US"],
      ["/v1/quality", "currency=%20%20"]
    ]

    requests.each do |path, query|
      response = call(app, method: "GET", path: path, query: query)

      assert_equal 400, response.fetch(0), path
      assert_equal({ "error" => "invalid_request" }, parse(response), path)
    end
  end

  def test_http_query_endpoints_reject_unsupported_parameters_instead_of_broadening
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    requests = [
      ["/v1/analytics", "metric=settlement_measure&provder_id=A"],
      ["/v1/recovery/due-work", "as_o=2026-09-01T00%3A00%3A00Z"],
      ["/v1/audit/facts", "limt=1"],
      ["/v1/configuration", "revision=0"],
      ["/v1/providers", "provider_id=A"]
    ]

    requests.each do |path, query|
      response = call(app, method: "GET", path: path, query: query)

      assert_equal 400, response.fetch(0), path
      assert_equal({ "error" => "invalid_request" }, parse(response), path)
    end
  end

  def test_http_routes_without_query_semantics_reject_parameters
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    requests = [
      ["GET", "/health", "status=ok"],
      ["POST", "/v1/payouts", "scope=default"],
      ["GET", "/v1/payouts/missing", "include=history"],
      ["GET", "/v1/payouts/missing/explanation", "format=full"],
      ["POST", "/v1/payouts/missing/resume", "force=true"],
      ["POST", "/v1/providers/A/webhook", "version=2"]
    ]

    requests.each do |method, path, query|
      response = call(app, method: method, path: path, query: query)

      assert_equal 400, response.fetch(0), [method, path].join(" ")
      assert_equal({ "error" => "invalid_request" }, parse(response), [method, path].join(" "))
    end
    assert_empty service.queries.audit_facts
  end

  def test_http_resume_rejects_a_body_because_it_has_no_body_semantics
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts/missing/resume",
      body: { "force" => true }
    )

    assert_equal 400, response.fetch(0)
    assert_equal({ "error" => "invalid_request" }, parse(response))
    assert_empty service.queries.audit_facts
  end

  def test_http_rejects_a_scalar_routing_context_instead_of_broadening_the_route
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: {
        "id" => "malformed-http-context",
        "amount_minor" => 1,
        "currency" => "RUB",
        "context" => false
      }
    )

    assert_equal 400, response.fetch(0)
    assert_equal({ "error" => "invalid_request" }, parse(response))
    assert_empty service.queries.audit_facts
  end

  def test_http_submit_uses_and_exposes_explicit_canonical_routing_context
    provider = Class.new do
      def initiate(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "http-explicit-route-success",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end

      def resolve(_request)
        raise "resolve should not be called"
      end
    end.new
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      route_capabilities: RubyRouting::ProviderRouteCapabilities.new(
        supported_payment_methods: [:card]
      )
    )
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new(opportunities: [opportunity]),
      providers: { "A" => provider }
    )
    service.commands.register_policy(one_provider_policy("http-explicit-route"))
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: {
        "id" => "http-explicit-route-payout",
        "amount_minor" => 100,
        "currency" => "RUB",
        "routing_context" => { "payment_method" => "card" }
      }
    )

    assert_equal 201, response.fetch(0)
    body = parse(response)
    assert_equal "success", body.fetch("status")
    assert_equal(
      { "payment_method" => "card", "rail" => nil,
        "destination_kind" => nil, "labels" => [] },
      body.fetch("payout").fetch("routing_context")
    )
  end

  def test_http_rejects_unknown_explicit_routing_context_keys
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: {
        "id" => "http-unknown-route-key",
        "amount_minor" => 1,
        "currency" => "RUB",
        "routing_context" => { "payment_methd" => "card" }
      }
    )

    assert_equal 400, response.fetch(0)
    assert_equal({ "error" => "invalid_request" }, parse(response))
    assert_empty service.queries.audit_facts
  end

  def test_http_preserves_typed_no_matching_policy_error
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: { "id" => "http-no-policy", "amount_minor" => 1, "currency" => "RUB" }
    )

    assert_equal 422, response.fetch(0)
    body = parse(response)
    assert_equal "no_matching_policy", body.fetch("error")
    assert_equal "default", body.fetch("resolution").fetch("scope")
    assert_equal "no_match", body.fetch("resolution").fetch("status")
    assert_empty service.queries.audit_facts
  end

  def test_http_preserves_typed_ambiguous_policy_error
    policy_a = one_provider_policy("http-ambiguous-a")
    policy_b = one_provider_policy("http-ambiguous-b")
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    service.commands.register_policy(policy_a)
    service.commands.register_policy(policy_b)
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: { "id" => "http-ambiguous-policy", "amount_minor" => 1, "currency" => "RUB" }
    )

    assert_equal 409, response.fetch(0)
    body = parse(response)
    assert_equal "ambiguous_policy", body.fetch("error")
    assert_equal "ambiguous", body.fetch("resolution").fetch("status")
    assert_equal ["http-ambiguous-a", "http-ambiguous-b"],
      body.fetch("resolution").fetch("candidates").map { |candidate| candidate.fetch("id") }
    assert_empty service.queries.audit_facts
  end

  def test_http_reports_configuration_drift_without_registering_a_payout
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: {}
    )
    service.commands.register_policy(one_provider_policy("http-configuration-drift"))
    coordinator.replace_provider_opportunities([
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ])
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: {
        "id" => "http-configuration-drift-payout",
        "amount_minor" => 1,
        "currency" => "RUB"
      }
    )

    assert_equal 503, response.fetch(0)
    assert_equal({ "error" => "configuration_drift" }, parse(response))
    assert_empty coordinator.audit_facts(payout_id: "http-configuration-drift-payout")
  end

  def test_http_rejects_duplicate_json_keys_before_registering_a_payout
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)
    response = app.call(
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => "/v1/payouts",
      "QUERY_STRING" => "",
      "rack.input" => StringIO.new(
        '{"id":"first","id":"second","amount_minor":1,"currency":"RUB"}'
      )
    )

    assert_equal 400, response.fetch(0)
    assert_equal({ "error" => "invalid_request" }, parse(response))
    assert_empty service.queries.audit_facts
  end

  def test_http_rejects_unknown_payout_fields_before_route_broadening
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: {
        "id" => "http-unknown-payout-field",
        "amount_minor" => 1,
        "currency" => "RUB",
        "routeing_context" => { "payment_method" => "card" }
      }
    )

    assert_equal 400, response.fetch(0)
    assert_equal({ "error" => "invalid_request" }, parse(response))
    assert_empty service.queries.audit_facts
  end

  def test_http_analytics_exposes_current_pending_age
    clock = TestSupport::ControlledClock.new
    policy = one_provider_policy("http-age-policy")
    provider = Class.new do
      include RubyRouting::Ports::Provider

      def initiate(_request)
        RubyRouting::ProviderTransportResult.ambiguous_after_possible_send
      end

      def resolve(_request)
        RubyRouting::ProviderTransportResult.ambiguous_after_possible_send
      end
    end.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy)
    payout = RubyRouting::PayoutIntent.new(
      id: "http-age-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )
    result = service.submit(intent: payout)
    assert_equal :unknown, result.status

    clock.advance(7)
    app = RubyRouting::Application::HttpApp.new(service: service)
    response = call(app, method: "GET", path: "/v1/analytics")

    assert_equal 200, response.fetch(0)
    assert_equal 7, parse(response).fetch("unresolved_age_seconds_by_payout").fetch(payout.id)
  end

  def test_webhook_must_cross_provider_normalizer_and_cannot_forge_safe_release
    policy = one_provider_policy("webhook-policy")
    adapter = Class.new do
      include RubyRouting::Ports::Provider

      def initiate(request)
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
    service.commands.register_policy(policy)
    payout = RubyRouting::PayoutIntent.new(
      id: "webhook-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )
    result = service.submit(intent: payout)
    attempt = result.payout.current_operation
    normalizer = Class.new do
      define_method(:normalize) do |raw:, provider_id:|
        RubyRouting::ProviderObservation.new(
          observation_id: raw.fetch("observation_id"),
          payout_id: raw.fetch("payout_id"),
          provider_id: provider_id,
          operation_id: raw.fetch("operation_id"),
          attempt_id: raw.fetch("attempt_id"),
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end
    end.new
    app = RubyRouting::Application::HttpApp.new(
      service: service,
      provider_normalizers: { " A " => normalizer }
    )

    response = call(
      app,
      method: "POST",
      path: "/v1/providers/ A /webhook",
      body: {
        "observation_id" => "webhook-success",
        "payout_id" => payout.id,
        "operation_id" => attempt.operation_id,
        "attempt_id" => attempt.attempt_id,
        "status" => "success",
        "safe_to_release" => false
      }
    )

    assert_equal 200, response.fetch(0)
    assert_equal "success", parse(response).fetch("payout").fetch("status")
    assert_equal true, coordinator.payout_snapshot(payout.id).last_outcome.success?
  end

  def test_normalizer_configuration_rejects_colliding_canonical_provider_ids
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    normalizer = Object.new

    assert_raises(ArgumentError) do
      RubyRouting::Application::HttpApp.new(
        service: service,
        provider_normalizers: { "A" => normalizer, " A " => normalizer }
      )
    end
  end

  def test_normalizer_configuration_rejects_arbitrary_provider_id_coercion
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    normalizer = Class.new do
      def normalize(**)
        raise "not invoked"
      end
    end.new
    spoofed_provider_id = Object.new
    def spoofed_provider_id.to_s
      "A"
    end

    assert_raises(ArgumentError) do
      RubyRouting::Application::HttpApp.new(
        service: service,
        provider_normalizers: { spoofed_provider_id => normalizer }
      )
    end
  end

  def test_normalizer_configuration_rejects_non_executable_provider_normalizer
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    normalizer = Class.new do
      include RubyRouting::Ports::ProviderNormalizer
    end.new

    error = assert_raises(ArgumentError) do
      RubyRouting::Application::HttpApp.new(
        service: service,
        provider_normalizers: { "A" => normalizer }
      )
    end

    assert_equal "provider normalizer must implement executable #normalize", error.message
  end

  def test_http_errors_do_not_expose_ruby_exception_details
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(app, method: "POST", path: "/v1/payouts", body: { "amount_minor" => 1 })

    assert_equal 400, response.fetch(0)
    assert_equal({ "error" => "invalid_request" }, parse(response))
    refute_includes response.join, "KeyError"
  end

  def test_http_boundary_rejects_oversized_body_path_and_query
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)
    oversized_body = "x" * (RubyRouting::Application::HttpApp::MAX_REQUEST_BODY_BYTES + 1)

    body_response = app.call(
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => "/v1/payouts",
      "QUERY_STRING" => "",
      "rack.input" => StringIO.new(oversized_body)
    )
    path_response = app.call(
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/" + ("x" * RubyRouting::Application::HttpApp::MAX_PATH_BYTES),
      "QUERY_STRING" => "",
      "rack.input" => StringIO.new
    )
    query_response = app.call(
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/v1/audit/facts",
      "QUERY_STRING" => "x=" + ("y" * RubyRouting::Application::HttpApp::MAX_QUERY_STRING_BYTES),
      "rack.input" => StringIO.new
    )

    assert_equal 413, body_response.fetch(0)
    assert_equal 413, path_response.fetch(0)
    assert_equal 413, query_response.fetch(0)
    assert_equal({ "error" => "request_too_large" }, parse(body_response))
  end

  def test_http_audit_is_bounded_and_paginated
    coordinator = RubyRouting::State::Coordinator.new
    300.times do |index|
      coordinator.register_intent(
        RubyRouting::PayoutIntent.new(
          id: "audit-payout-#{index}",
          money: RubyRouting::Money.new(1, "RUB")
        )
      )
    end
    service = RubyRouting::Application::Service.new(coordinator: coordinator, providers: {})
    app = RubyRouting::Application::HttpApp.new(service: service)

    first = call(app, method: "GET", path: "/v1/audit/facts")
    first_body = parse(first)
    second = call(
      app,
      method: "GET",
      path: "/v1/audit/facts",
      query: "limit=3&offset=#{first_body.fetch("next_offset")}"
    )
    second_body = parse(second)
    invalid = [
      call(app, method: "GET", path: "/v1/audit/facts", query: "limit=0"),
      call(app, method: "GET", path: "/v1/audit/facts", query: "limit=257"),
      call(app, method: "GET", path: "/v1/audit/facts", query: "limit=not-a-number"),
      call(app, method: "GET", path: "/v1/audit/facts", query: "offset=1000001")
    ]

    assert_equal 200, first.fetch(0)
    assert_equal RubyRouting::Application::HttpApp::MAX_AUDIT_PAGE_SIZE,
      first_body.fetch("facts").length
    assert_equal 0, first_body.fetch("offset")
    assert_equal RubyRouting::Application::HttpApp::MAX_AUDIT_PAGE_SIZE,
      first_body.fetch("limit")
    assert_equal 300, first_body.fetch("total")
    assert_equal RubyRouting::Application::HttpApp::MAX_AUDIT_PAGE_SIZE,
      first_body.fetch("next_offset")
    assert_equal 200, second.fetch(0)
    assert_equal 3, second_body.fetch("facts").length
    assert_equal 256, second_body.fetch("offset")
    assert_equal 259, second_body.fetch("next_offset")
    invalid.each do |response|
      assert_equal 400, response.fetch(0)
      assert_equal({ "error" => "invalid_request" }, parse(response))
    end
  end

  def test_http_rejects_ambiguous_duplicate_query_parameters
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: {}
    )
    app = RubyRouting::Application::HttpApp.new(service: service)

    responses = [
      call(app, method: "GET", path: "/v1/audit/facts", query: "limit=1&limit=2"),
      call(app, method: "GET", path: "/v1/analytics", query: "metric=settlement_measure&metric=assignment_measure"),
      call(app, method: "GET", path: "/v1/recovery/due-work", query: "as_of=2026-08-31T12:00:00Z&as_of=2026-08-31T12:00:01Z")
    ]

    responses.each do |response|
      assert_equal 400, response.fetch(0)
      assert_equal({ "error" => "invalid_request" }, parse(response))
    end
  end

  def test_http_public_audit_omits_recipient_and_raw_provider_fields
    policy = one_provider_policy("public-audit-policy")
    provider = Class.new do
      include RubyRouting::Ports::Provider

      def initiate(request)
        RubyRouting::ProviderObservation.new(
          observation_id: "public-audit-observation",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          provider_reference: "provider-secret-reference",
          outcome: RubyRouting::NormalizedOutcome.success(
            attribution: :provider,
            provider_reference: "outcome-secret-reference",
            message: "provider-secret-message"
          )
        )
      end

      def resolve(_request)
        raise "resolve should not be called"
      end
    end.new
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new(
        opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
      ),
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy)
    app = RubyRouting::Application::HttpApp.new(service: service)

    response = call(
      app,
      method: "POST",
      path: "/v1/payouts",
      body: {
        "id" => "public-audit-payout",
        "amount_minor" => 100,
        "currency" => "RUB",
        "recipient" => { "account_number" => "recipient-secret" },
        "context" => { "private_label" => "context-secret" }
      }
    )
    audit = call(app, method: "GET", path: "/v1/audit/facts", query: "payout_id=public-audit-payout")
    body = parse(audit)
    facts = body.fetch("facts")
    intent_fact = facts.find { |fact| fact.fetch("type") == "intent_registered" }
    evaluation_fact = facts.find { |fact| fact.fetch("type") == "opportunity_evaluated" }
    observation_fact = facts.find { |fact| fact.fetch("type") == "provider_observed" }

    assert_equal 201, response.fetch(0)
    assert_equal 200, audit.fetch(0)
    assert_equal "RUB", intent_fact.fetch("payload").fetch("money").fetch("currency")
    assert_includes intent_fact.fetch("redacted_fields"), "context"
    assert_includes intent_fact.fetch("redacted_fields"), "recipient"
    assert_equal "A", evaluation_fact.fetch("payload").fetch("feasible_provider_ids").first
    assert_equal false, observation_fact.fetch("payload").fetch("conflict")
    assert_equal ["causal_hold", "health_evidence", "message", "outcome_provider_reference", "provider_reference"],
      observation_fact.fetch("redacted_fields").sort
    refute_includes JSON.generate(body), "recipient-secret"
    refute_includes JSON.generate(body), "context-secret"
    refute_includes JSON.generate(body), "provider-secret"
    refute_includes JSON.generate(body), "outcome-secret"
  end

  def test_http_payout_surfaces_allowlist_outcomes_but_preserve_internal_provider_evidence
    policy = one_provider_policy("public-payout-policy")
    provider = Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def initiate(request)
        @calls << :initiate
        RubyRouting::ProviderObservation.new(
          observation_id: "public-payout-unknown",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          provider_reference: "initiate-reference-SECRET",
          outcome: RubyRouting::NormalizedOutcome.unknown(
            attribution: :provider,
            provider_reference: "unknown-reference-SECRET",
            message: "unknown-diagnostic-SECRET"
          )
        )
      end

      def resolve(request)
        @calls << :resolve
        RubyRouting::ProviderObservation.new(
          observation_id: "public-payout-success",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          provider_reference: "resolve-reference-SECRET",
          outcome: RubyRouting::NormalizedOutcome.success(
            attribution: :provider,
            provider_reference: "success-reference-SECRET",
            message: "success-diagnostic-SECRET"
          )
        )
      end
    end.new
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new(opportunities: [opportunity]),
      providers: { "A" => provider }
    )
    service.commands.register_policy(policy)
    app = RubyRouting::Application::HttpApp.new(service: service)
    body = {
      "id" => "public-payout-boundary",
      "amount_minor" => 100,
      "currency" => "RUB"
    }

    submitted = call(app, method: "POST", path: "/v1/payouts", body: body)
    fetched = call(app, method: "GET", path: "/v1/payouts/public-payout-boundary")
    resumed = call(app, method: "POST", path: "/v1/payouts/public-payout-boundary/resume")

    public_responses = [submitted, fetched, resumed]
    public_responses.each do |response|
      assert_equal 200, response.fetch(0) if response.equal?(fetched) || response.equal?(resumed)
      refute_includes response.join, "SECRET"
      parsed = parse(response)
      payload = parsed.fetch("payout")
      payload.fetch("attempts").each do |attempt|
        next unless attempt.fetch("outcome")

        assert_equal %w[attribution safe_to_release status], attempt.fetch("outcome").keys.sort
      end
    end

    assert_equal 201, submitted.fetch(0)
    assert_equal %i[initiate resolve], provider.calls
    internal_attempts = service.queries.payout("public-payout-boundary").attempts
    assert_equal "success-diagnostic-SECRET", internal_attempts.fetch(0).outcome.message
    assert_equal "success-reference-SECRET", internal_attempts.fetch(0).outcome.provider_reference
    internal_observations = service.queries.audit_facts(payout_id: "public-payout-boundary")
      .select { |fact| fact.type == :provider_observed }
    assert_equal ["unknown-diagnostic-SECRET", "success-diagnostic-SECRET"],
      internal_observations.map { |fact| fact.payload.fetch(:message) }
    assert_equal ["unknown-reference-SECRET", "success-reference-SECRET"],
      internal_observations.map { |fact| fact.payload.fetch(:outcome_provider_reference) }
  end

  private

  def one_provider_policy(id)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
  end

  def call(app, method:, path:, body: nil, query: "")
    app.call(
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "QUERY_STRING" => query,
      "rack.input" => StringIO.new(body ? JSON.generate(body) : "")
    )
  end

  def parse(response)
    JSON.parse(response.fetch(2).join)
  end
end
