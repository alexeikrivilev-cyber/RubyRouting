# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class ProviderRouteCapabilityScenarioTest < Minitest::Test
  def test_route_capabilities_shape_functional_cohort_explanation_and_restart
    Dir.mktmpdir("ruby-routing-route-capabilities") do |directory|
      path = File.join(directory, "facts.jsonl")
      bank_provider = RubyRouting::ProviderOpportunity.new(
        provider_id: "bank",
        supported_payment_methods: [:bank_transfer],
        supported_rails: [:sepa],
        supported_destination_kinds: [:bank_account]
      )
      card_provider = RubyRouting::ProviderOpportunity.new(
        provider_id: "card",
        supported_payment_methods: [:card],
        supported_rails: [:domestic],
        supported_destination_kinds: [:card]
      )
      coordinator = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [bank_provider, card_provider]
      )
      intent = RubyRouting::PayoutIntent.new(
        id: "route-capability-payout",
        money: RubyRouting::Money.new(100, "RUB"),
        context: {
          payment_method: :bank_transfer,
          rail: "SEPA",
          destination_type: "bank_account"
        }
      )
      policy = RubyRouting::RoutingPolicy.new(
        id: "route-capability-policy",
        epoch: "1",
        measure: :count,
        targets: { "bank" => 1, "card" => 1 }
      )

      committed = coordinator.prepare_and_commit_decision(intent: intent, policy: policy)
      evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }
      explanation = RubyRouting::Projections::DecisionExplanation.from_facts(
        coordinator.facts,
        payout_id: intent.id
      )

      assert committed.proposal.assignment?
      assert_equal "bank", committed.proposal.provider_id
      assert_equal %w[bank card], evaluation.payload.fetch(:opportunities)
      assert_equal ["bank"], evaluation.payload.fetch(:functional_provider_ids)
      assert_equal :unsupported_payment_method,
        evaluation.payload.fetch(:exclusion_codes).fetch("card")
      assert_equal ["bank"], evaluation.payload.fetch(:allocation_key).fetch(3)
      assert_equal :unsupported_payment_method,
        explanation.decisions.last.opportunities.fetch(:exclusion_codes).fetch("card")

      restored = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )
      restored_card = restored.provider_opportunities.find { |provider| provider.provider_id == "card" }
      restored_evaluation = restored.facts.find { |fact| fact.type == :opportunity_evaluated }
      assert_equal card_provider.route_capabilities, restored_card.route_capabilities
      assert_equal :unsupported_payment_method,
        restored_evaluation.payload.fetch(:exclusion_codes).fetch("card")
    end
  end
end
