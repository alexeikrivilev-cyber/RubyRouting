# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class ProviderOperationPayloadScenarioTest < Minitest::Test
  def test_adapter_can_execute_from_canonical_request_and_resolution_reuses_it
    intent = payout_intent("payload-live", payment_method: "bank_transfer", rail: :sepa)
    coordinator = coordinator_for("payload-live-policy")
    requests = []
    adapter = Class.new do
      define_method(:initiate) do |request|
        requests << request
        RubyRouting::ProviderObservation.new(
          observation_id: "payload-unknown",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.unknown
        )
      end

      define_method(:resolve) do |request|
        requests << request
        RubyRouting::ProviderObservation.new(
          observation_id: "payload-resolved",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      end
    end.new
    orchestrator = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => adapter }
    )

    first = orchestrator.submit(intent: intent, policy: policy_for("payload-live-policy"))
    assert_equal :unknown, first.status
    assert_equal 1, requests.length
    initial_request = requests.first
    assert_equal({ "account" => "payload-live-recipient" }, initial_request.destination.data)
    assert_equal "bank_transfer", initial_request.payment_method
    assert_equal "sepa", initial_request.rail
    assert_equal intent.routing_context, initial_request.routing_context
    refute_nil initial_request.contract

    resolved = orchestrator.resume(payout_id: intent.id, policy: policy_for("payload-live-policy"))
    assert_equal :success, resolved.status
    assert_equal 2, requests.length
    assert_equal initial_request.to_h, requests.last.to_h
  end

  def test_restart_reconstructs_the_same_operation_payload
    Dir.mktmpdir("ruby-routing-provider-payload") do |directory|
      path = File.join(directory, "facts.jsonl")
      intent = payout_intent("payload-restart", payment_method: :card, rail: "domestic")
      policy = policy_for("payload-restart-policy")
      opportunity = RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, version: "restart-contract")
      )
      first = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [opportunity]
      )
      committed = first.prepare_and_commit_decision(intent: intent, policy: policy)
      intent_fact = first.facts.find { |fact| fact.type == :intent_registered }

      assert_equal intent.routing_context.to_h, intent_fact.payload.fetch(:routing_context)

      recovered = RubyRouting::State::Coordinator.new(journal: RubyRouting::State::FileJournal.new(path))
      resumed = recovered.resume_operation(intent.id)

      refute_nil resumed
      assert_equal committed.request.to_h, resumed.request.to_h
      assert_equal committed.request.contract.to_h, resumed.request.contract.to_h
      assert_equal intent.recipient, resumed.request.destination.data
      assert_equal intent.context, resumed.request.context
      assert_equal intent.routing_context, resumed.request.routing_context
    end
  end

  private

  def payout_intent(id, payment_method:, rail:)
    RubyRouting::PayoutIntent.new(
      id: id,
      money: RubyRouting::Money.new(100, "RUB"),
      recipient: { "account" => "#{id}-recipient" },
      context: { "payment_method" => payment_method, rail: rail, labels: ["retail"] }
    )
  end

  def coordinator_for(_policy_id)
    RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
  end

  def policy_for(id)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
  end
end
