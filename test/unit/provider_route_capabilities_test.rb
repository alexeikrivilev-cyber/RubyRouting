# frozen_string_literal: true

require_relative "../test_helper"

class ProviderRouteCapabilitiesTest < Minitest::Test
  def test_supported_dimensions_are_canonicalized_and_immutable
    capabilities = RubyRouting::ProviderRouteCapabilities.new(
      supported_payment_methods: TestSupport::EachOnlyCollection.new([" CARD ", :bank_transfer]),
      supported_rails: [" sepa "],
      supported_destination_kinds: [:bank_account]
    )

    assert_equal ["bank_transfer", "card"], capabilities.supported_payment_methods
    assert_equal ["sepa"], capabilities.supported_rails
    assert_equal ["bank_account"], capabilities.supported_destination_kinds
    assert_equal capabilities, RubyRouting::ProviderRouteCapabilities.from(capabilities.to_h)
    assert capabilities.frozen?
    assert capabilities.supported_payment_methods.frozen?
  end

  def test_each_explicit_route_dimension_is_a_hard_typed_functional_exclusion
    intent = route_intent
    [
      [:supported_payment_methods, :unsupported_payment_method],
      [:supported_rails, :unsupported_rail],
      [:supported_destination_kinds, :unsupported_destination_kind]
    ].each do |keyword, reason|
      provider = RubyRouting::ProviderOpportunity.new(
        provider_id: "provider-#{keyword}",
        keyword => ["other"]
      )

      result = RubyRouting::Routing::Eligibility.evaluate([provider], intent: intent)

      assert_empty result.functional_provider_ids, keyword
      assert_equal reason, result.exclusion_codes.fetch(provider.provider_id)
      assert_equal reason, provider.reason_for(intent: intent)
    end
  end

  def test_nil_is_unconstrained_but_an_explicit_empty_set_fails_closed
    intent = route_intent
    unconstrained = RubyRouting::ProviderOpportunity.new(provider_id: "unconstrained")
    blocked = RubyRouting::ProviderOpportunity.new(
      provider_id: "blocked",
      supported_payment_methods: []
    )

    assert unconstrained.functional_eligible_for?(intent: intent)
    refute blocked.functional_eligible_for?(intent: intent)
    assert_equal :unsupported_payment_method, blocked.reason_for(intent: intent)
  end

  def test_direct_and_typed_route_capability_configuration_cannot_diverge
    capabilities = RubyRouting::ProviderRouteCapabilities.new(
      supported_payment_methods: [:card]
    )
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "provider",
      route_capabilities: capabilities,
      supported_payment_methods: ["CARD"]
    )

    assert_equal capabilities, provider.route_capabilities
    assert_raises(ArgumentError) do
      RubyRouting::ProviderOpportunity.new(
        provider_id: "conflict",
        route_capabilities: capabilities,
        supported_payment_methods: [:bank_transfer]
      )
    end
  end

  private

  def route_intent
    RubyRouting::PayoutIntent.new(
      id: "route-capability-intent",
      money: RubyRouting::Money.new(100, "RUB"),
      context: {
        payment_method: "card",
        rail: "sepa",
        destination_kind: "bank_account"
      }
    )
  end
end
