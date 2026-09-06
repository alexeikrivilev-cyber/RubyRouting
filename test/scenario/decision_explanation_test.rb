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

  def test_explanation_describes_held_safe_release_without_leaking_causal_hold
    policy = RubyRouting::RoutingPolicy.new(
      id: "held-explanation-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    payout = RubyRouting::PayoutIntent.new(
      id: "held-explanation-payout",
      money: RubyRouting::Money.new(100, "RUB"),
      recipient: { account_number: "recipient-secret" }
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: %w[A B].map { |provider_id| RubyRouting::ProviderOpportunity.new(provider_id: provider_id) }
    )
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    attempt = coordinator.payout_snapshot(payout.id).attempts.fetch(0)
    coordinator.apply_observation(observation_for(
      payout,
      attempt,
      "held-explanation-unknown",
      RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
    ))
    coordinator.apply_observation(observation_for(
      payout,
      attempt,
      "held-explanation-release",
      RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
    ))
    service = RubyRouting::Application::Service.new(coordinator: coordinator, providers: {})

    explanation = service.queries.explanation(payout.id)
    assert_equal :unknown, explanation.result.status
    assert_equal :awaiting_causal_completion, explanation.result.disposition
    assert_equal true, explanation.result.latest_observation.fetch(:safe_to_release)
    assert_equal false, explanation.result.latest_observation.fetch(:applied)
    refute_includes JSON.generate(explanation.to_h), "causal_hold"
    refute_includes JSON.generate(explanation.to_h), "recipient-secret"

    app = RubyRouting::Application::HttpApp.new(service: service)
    response = app.call(
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/v1/payouts/#{payout.id}/explanation",
      "QUERY_STRING" => "",
      "rack.input" => StringIO.new
    )
    body = JSON.parse(response.fetch(2).join)
    assert_equal 200, response.fetch(0)
    assert_equal "awaiting_causal_completion", body.fetch("explanation").fetch("result").fetch("disposition")
    refute_includes response.fetch(2).join, "causal_hold"
    refute_includes response.fetch(2).join, "recipient-secret"
  end

  def test_explanation_does_not_mislabel_a_late_safe_observation_for_an_old_operation
    policy = RubyRouting::RoutingPolicy.new(
      id: "late-explanation-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
    payout = RubyRouting::PayoutIntent.new(
      id: "late-explanation-payout",
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
          steps: [TestSupport::Simulator::Step.unknown]
        )
      }
    )
    service.commands.register_policy(policy)

    result = service.submit(intent: payout)
    assert_equal :unknown, result.status
    old_attempt = result.payout.attempts.fetch(0)
    coordinator.apply_observation(
      observation_for(
        payout,
        old_attempt,
        "late-explanation-release",
        RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      )
    )

    explanation = service.queries.explanation(payout.id)
    assert_equal :unknown, explanation.result.status
    assert_nil explanation.result.disposition
    assert_equal old_attempt.operation_id, explanation.result.latest_observation.fetch(:operation_id)
    assert_equal false, explanation.result.latest_observation.fetch(:applied)
  end

  private

  def observation_for(payout, attempt, observation_id, outcome)
    RubyRouting::ProviderObservation.new(
      observation_id: observation_id,
      payout_id: payout.id,
      provider_id: attempt.provider_id,
      operation_id: attempt.operation_id,
      attempt_id: attempt.attempt_id,
      outcome: outcome
    )
  end
end
