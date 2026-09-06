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
    assert_equal ["message", "outcome_provider_reference", "provider_reference"],
      observation_fact.fetch("redacted_fields").sort
    refute_includes JSON.generate(body), "recipient-secret"
    refute_includes JSON.generate(body), "context-secret"
    refute_includes JSON.generate(body), "provider-secret"
    refute_includes JSON.generate(body), "outcome-secret"
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
