# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "stringio"

class DecisionExplanationTest < Minitest::Test
  def test_application_and_http_explanation_projects_routing_evidence_without_recipient_data
    policy = RubyRouting::RoutingPolicy.new(
      id: "explanation-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    intent = RubyRouting::PayoutIntent.new(
      id: "explanation-payout",
      money: RubyRouting::Money.new(100, "RUB"),
      recipient: { account_number: "recipient-secret" },
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
    service.commands.register_policy(policy)
    result = service.submit(intent: intent)

    explanation = service.queries.explanation(intent.id)
    entry = explanation.decisions.fetch(0)
    assert_equal :success, result.status
    assert_equal 1, entry.configuration_revision
    assert_equal "explanation-policy", entry.policy.fetch(:id)
    assert_equal ["A"], entry.opportunities.fetch(:provider_ids)
    assert_equal ["A"], entry.opportunities.fetch(:feasible_provider_ids)
    assert_equal :primary, entry.decision.fetch(:role)
    assert_equal "A", entry.decision.fetch(:provider_id)
    assert_equal :deterministic_routing_reason, entry.decision.fetch(:rationale).fetch(:kind)
    assert entry.optimization.fetch(:trace).fetch("A").fetch(:selected)
    assert_equal :success, explanation.result.status
    assert_equal false, explanation.result.unresolved
    assert_equal :success, explanation.result.latest_observation.fetch(:status)
    refute_includes JSON.generate(explanation.to_h), "recipient-secret"

    app = RubyRouting::Application::HttpApp.new(service: service)
    response = app.call(
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/v1/payouts/#{intent.id}/explanation",
      "QUERY_STRING" => "",
      "rack.input" => StringIO.new
    )
    body = JSON.parse(response.fetch(2).join)
    assert_equal 200, response.fetch(0)
    assert_equal "success", body.fetch("explanation").fetch("result").fetch("status")
    refute_includes response.fetch(2).join, "recipient-secret"
  end

  def test_explanation_links_recovery_decision_to_the_previous_provider_outcome
    policy = RubyRouting::RoutingPolicy.new(
      id: "recovery-explanation-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    intent = RubyRouting::PayoutIntent.new(
      id: "recovery-explanation-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: %w[A B].map { |provider_id| RubyRouting::ProviderOpportunity.new(provider_id: provider_id) }
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: {
        "A" => TestSupport::Simulator::ScriptedProvider.new(
          provider_id: "A",
          steps: [TestSupport::Simulator::Step.safe_failure]
        ),
        "B" => TestSupport::Simulator::ScriptedProvider.new(
          provider_id: "B",
          steps: [TestSupport::Simulator::Step.success]
        )
      }
    )
    service.commands.register_policy(policy)

    result = service.submit(intent: intent)
    explanation = service.queries.explanation(intent.id)
    primary, recovery = explanation.decisions

    assert_equal :success, result.status
    assert_equal 2, explanation.decisions.length
    assert_equal :primary, primary.decision.fetch(:role)
    assert_equal "A", primary.decision.fetch(:provider_id)
    assert_equal :recovery, recovery.decision.fetch(:role)
    assert_equal "B", recovery.decision.fetch(:provider_id)
    assert_equal :safe_route_failure, recovery.recovery.fetch(:previous_outcome).fetch(:status)
    assert_equal :success, explanation.result.status
    assert_equal 2, explanation.result.observations.length
  end
end
