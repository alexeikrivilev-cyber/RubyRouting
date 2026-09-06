# frozen_string_literal: true

require_relative "../test_helper"

class RoutingContextTest < Minitest::Test
  def test_equivalent_inputs_produce_one_immutable_canonical_route_value
    first = RubyRouting::RoutingContext.from(
      payment_method: " Bank_Transfer ",
      rail: :SEPA,
      destination_kind: " Bank_Account ",
      labels: [" VIP ", "retail"]
    )
    second = RubyRouting::RoutingContext.from(
      "payment_method" => :bank_transfer,
      "rail" => " sepa ",
      "destination_type" => :bank_account,
      "segment" => "RETAIL",
      "segments" => [:vip]
    )

    assert_equal first, second
    assert_equal(
      {
        payment_method: "bank_transfer",
        rail: "sepa",
        destination_kind: "bank_account",
        labels: ["retail", "vip"]
      },
      first.to_h
    )
    assert first.frozen?
    assert first.labels.frozen?
    assert_raises(FrozenError) { first.labels << "wholesale" }
  end

  def test_payout_intent_exposes_canonical_context_without_rewriting_raw_adapter_context
    raw_context = {
      "payment_method" => " BANK_TRANSFER ",
      "rail" => :SEPA,
      "destination_kind" => " Bank_Account ",
      "labels" => [" Retail "],
      "provider_metadata" => { "case" => "preserve" }
    }
    intent = RubyRouting::PayoutIntent.new(
      id: "routing-context-intent",
      money: RubyRouting::Money.new(100, "RUB"),
      context: raw_context
    )

    assert_equal raw_context, intent.context
    assert_equal "bank_transfer", intent.routing_context.payment_method
    assert_equal "sepa", intent.routing_context.rail
    assert_equal "bank_account", intent.routing_context.destination_kind
    assert_equal ["retail"], intent.routing_context.labels
    refute_same intent.context, intent.routing_context.to_h
  end

  def test_persisted_context_is_validated_against_the_raw_context
    assert_raises(ArgumentError) do
      RubyRouting::PayoutIntent.new(
        id: "routing-context-mismatch",
        money: RubyRouting::Money.new(100, "RUB"),
        context: { payment_method: "card" },
        routing_context: { payment_method: "bank_transfer" }
      )
    end
  end

  def test_policy_provider_and_quality_use_the_same_canonical_labels
    intent = RubyRouting::PayoutIntent.new(
      id: "routing-context-consumers",
      money: RubyRouting::Money.new(100, "RUB"),
      context: { labels: [" Retail "] }
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "routing-context-consumers",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      hard_constraints: { required_context_labels: ["RETAIL"] }
    )
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      required_context_labels: ["retail"]
    )
    quality = RubyRouting::Routing::QualityController.new(
      policy: RubyRouting::Routing::QualityPolicy.new(minimum_samples: 1)
    )
    quality.observe(
      provider_id: "A",
      context: intent.routing_context,
      outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
    )

    assert policy.hard_constraints.allows?(intent: intent, provider_id: "A")
    assert provider.functional_eligible_for?(intent: intent, policy: policy)
    assert_equal ["retail"], quality.snapshot("A", context: intent.routing_context).context_key
  end
end
