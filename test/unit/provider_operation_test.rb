# frozen_string_literal: true

require_relative "../test_helper"

class ProviderOperationTest < Minitest::Test
  def test_request_exposes_an_immutable_generic_executable_payload
    intent = RubyRouting::PayoutIntent.new(
      id: "payload-payout",
      money: RubyRouting::Money.new(1250, "RUB"),
      recipient: { "account" => "recipient-1", "metadata" => { "channel" => "retail" } },
      context: {
        payment_method: :bank_transfer,
        "rail" => " sepa ",
        labels: ["retail"]
      }
    )
    contract = RubyRouting::ProviderOperationContract.new(
      provider_id: "A",
      idempotent_retry: true,
      status_lookup: true,
      idempotency_key: "payload-payout:payload-operation",
      ttl_seconds: 30,
      version: "contract-7"
    )

    request = RubyRouting::ProviderOperationRequest.from_intent(
      intent: intent,
      provider_id: "A",
      operation_id: "payload-operation",
      attempt_id: "payload-attempt",
      contract: contract
    )

    assert_instance_of RubyRouting::PayoutDestination, request.destination
    assert_equal intent.recipient, request.destination.data
    assert_equal intent.context, request.context
    assert_equal intent.routing_context, request.routing_context
    assert_equal intent.routing_context.to_h, request.to_h.fetch(:payload).fetch(:routing_context)
    assert_equal "bank_transfer", request.payment_method
    assert_equal "sepa", request.rail
    assert_equal contract.to_h, request.contract.to_h
    assert_equal "payload-payout:payload-operation", request.idempotency_key
    assert request.frozen?
    assert request.payload.frozen?
    assert request.destination.frozen?
    assert request.destination.data.frozen?
    assert request.destination.data.fetch("metadata").frozen?
    assert request.to_h.frozen?
    assert_equal request.to_h, Marshal.load(Marshal.dump(request.to_h))

    assert_raises(FrozenError) { request.destination.data.fetch("metadata")["channel"] = "wholesale" }
    assert_raises(FrozenError) { request.context.fetch(:labels) << "wholesale" }
  end

  def test_contract_cannot_be_rebound_to_another_operation_identity
    contract = RubyRouting::ProviderOperationContract.new(
      provider_id: "A",
      idempotency_key: "payout:operation"
    )

    assert_raises(ArgumentError) do
      RubyRouting::ProviderOperationRequest.new(
        payout_id: "payout",
        provider_id: "A",
        operation_id: "other-operation",
        attempt_id: "attempt",
        money: RubyRouting::Money.new(1, "RUB"),
        contract: contract
      )
    end

    wrong_provider = RubyRouting::ProviderOperationContract.new(
      provider_id: "B",
      idempotency_key: "payout:operation"
    )
    assert_raises(ArgumentError) do
      RubyRouting::ProviderOperationRequest.new(
        payout_id: "payout",
        provider_id: "A",
        operation_id: "operation",
        attempt_id: "attempt",
        money: RubyRouting::Money.new(1, "RUB"),
        contract: wrong_provider
      )
    end
  end

  def test_direct_payload_rejects_a_second_route_context_interpretation
    assert_raises(ArgumentError) do
      RubyRouting::ProviderOperationPayload.new(
        destination: {},
        context: { payment_method: "card" },
        routing_context: { payment_method: "bank_transfer" }
      )
    end

    assert_raises(ArgumentError) do
      RubyRouting::ProviderOperationPayload.new(
        destination: {},
        context: {},
        routing_context: { payment_method: "card" },
        payment_method: "bank_transfer"
      )
    end
  end

  def test_legacy_direct_payload_dimensions_are_canonicalized_into_the_route_context
    payload = RubyRouting::ProviderOperationPayload.new(
      destination: {},
      context: {},
      payment_method: " BANK_TRANSFER ",
      rail: :SEPA
    )

    assert_equal "bank_transfer", payload.payment_method
    assert_equal "sepa", payload.rail
    assert_equal(
      { payment_method: "bank_transfer", rail: "sepa", destination_kind: nil, labels: [] },
      payload.routing_context.to_h
    )
  end

  def test_legacy_unbound_request_remains_valid_for_boundary_validation_tests
    request = RubyRouting::ProviderOperationRequest.new(
      payout_id: "payout",
      provider_id: "A",
      operation_id: "operation",
      attempt_id: "attempt",
      money: RubyRouting::Money.new(1, "RUB")
    )

    assert_nil request.contract
    assert_equal({}, request.destination.data)
    assert_equal({}, request.context)
  end
end
