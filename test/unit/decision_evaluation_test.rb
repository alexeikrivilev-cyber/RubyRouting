# frozen_string_literal: true

require_relative "../test_helper"

class DecisionEvaluationTest < Minitest::Test
  State = Struct.new(
    :status,
    :ownership,
    :attempt_count,
    :attempts,
    :resolution_interaction_count,
    keyword_init: true
  )

  def test_decision_engine_consumes_one_immutable_precomputed_evaluation
    intent = RubyRouting::PayoutIntent.new(
      id: "single-evaluation",
      money: RubyRouting::Money.new(100, "RUB")
    )
    opportunity = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = RubyRouting::RoutingPolicy.new(
      id: "single-evaluation-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    eligibility = RubyRouting::Routing::Eligibility.evaluate(
      [opportunity],
      intent: intent,
      policy: policy
    )
    allocation_exclusions = policy.measure_exclusions(
      eligibility.feasible_provider_ids,
      policy.measure_for(intent.money)
    )
    runtime_feasibility = RubyRouting::Routing::RuntimeFeasibility.assess(
      policy: policy,
      eligibility: eligibility,
      attempted_provider_ids: [],
      measure_exclusions: allocation_exclusions
    )
    quality = RubyRouting::Routing::QualityController.new.snapshots(["A"])
    evaluation = RubyRouting::Routing::DecisionEvaluator::Evaluation.new(
      opportunities: [opportunity],
      eligibility: eligibility,
      allocation_exclusions: allocation_exclusions,
      runtime_feasibility: runtime_feasibility,
      allocation_snapshot: RubyRouting::Routing::AllocationSnapshot.empty,
      allocation_key: policy.allocation_key(opportunity_provider_ids: ["A"]),
      evaluated_at: nil,
      evaluated_monotonic_at: nil,
      quality_snapshots: quality,
      proposal: nil
    )
    payout_state = State.new(
      status: :new,
      ownership: nil,
      attempt_count: 0,
      attempts: [],
      resolution_interaction_count: 0
    )

    proposal = RubyRouting::Routing::DecisionEngine.decide(
      intent: intent,
      policy: policy,
      payout_state: payout_state,
      evaluation: evaluation
    )

    assert evaluation.frozen?
    assert evaluation.opportunities.frozen?
    assert evaluation.quality_snapshots.frozen?
    assert proposal.assignment?
    assert_equal "A", proposal.provider_id
  end

  def test_standalone_decision_engine_uses_the_shared_preparation_contract
    intent = RubyRouting::PayoutIntent.new(
      id: "shared-preparation",
      money: RubyRouting::Money.new(100, "RUB")
    )
    opportunity = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    policy = RubyRouting::RoutingPolicy.new(
      id: "shared-preparation-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    payout_state = State.new(
      status: :new,
      ownership: nil,
      attempt_count: 0,
      attempts: [],
      resolution_interaction_count: 0
    )
    prepared = RubyRouting::Routing::DecisionEvaluator.prepare(
      intent: intent,
      policy: policy,
      opportunities: [opportunity],
      attempted_provider_ids: []
    )

    proposal = RubyRouting::Routing::DecisionEngine.decide(
      intent: intent,
      policy: policy,
      payout_state: payout_state,
      opportunities: [opportunity],
      allocation_snapshot: RubyRouting::Routing::AllocationSnapshot.empty
    )

    assert prepared.frozen?
    assert prepared.eligibility.frozen?
    assert prepared.allocation_exclusions.frozen?
    assert prepared.runtime_feasibility.frozen?
    assert proposal.assignment?
    assert_equal prepared.runtime_feasibility.to_h, proposal.runtime_feasibility.to_h
  end
end
