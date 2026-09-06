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

    assert_equal 200, health.fetch(0)
    assert_equal "ok", parse(health).fetch("status")
    assert_equal 201, submitted.fetch(0)
    assert_equal "success", parse(submitted).fetch("status")
    assert_equal 200, fetched.fetch(0)
    assert_equal "success", parse(fetched).fetch("payout").fetch("status")
    assert_equal 200, analytics.fetch(0)
    assert_equal 1, parse(analytics).fetch("eventual_success_count")
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
