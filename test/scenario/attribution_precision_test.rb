# frozen_string_literal: true

require_relative "../test_helper"
require "json"

class AttributionPrecisionTest < Minitest::Test
  def test_deviation_cause_is_exposed_as_a_deterministic_reason_not_causal_inference
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A", available: false)]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "attribution-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    payout = RubyRouting::PayoutIntent.new(
      id: "attribution-payout",
      money: RubyRouting::Money.new(1, "RUB")
    )

    decision = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    explanation = RubyRouting::Projections::DecisionExplanation.from_facts(
      coordinator.facts,
      payout_id: payout.id
    )
    payload = JSON.parse(JSON.generate(analytics.to_h))

    assert_equal :defer, decision.proposal.action
    assert_equal :availability, analytics.deviation_by_cause.keys.first
    assert_equal :deterministic_routing_reason, analytics.deviation_attribution_semantics
    assert_equal :deterministic_exclusion_reason, analytics.runtime_infeasibility_attribution_semantics
    assert_equal "deterministic_routing_reason", payload.fetch("deviation_attribution_semantics")
    assert_equal "deterministic_exclusion_reason", payload.fetch("runtime_infeasibility_attribution_semantics")
    assert_equal :deterministic_routing_reason,
      explanation.decisions.first.allocation.fetch(:attribution_semantics)
  end
end
