# frozen_string_literal: true

require_relative "../test_helper"

class IdentityTest < Minitest::Test
  def test_core_routing_and_state_identities_reject_structured_values
    invalid_values = [[], Object.new]

    invalid_values.each do |invalid|
      assert_raises(ArgumentError) do
        RubyRouting::DecisionProposal.new(
          action: :assign,
          provider_id: invalid,
          role: :primary,
          policy_epoch: "1"
        )
      end
      assert_raises(ArgumentError) do
        RubyRouting::Fact.new(
          sequence: 1,
          type: :intent_registered,
          fact_id: invalid,
          payout_id: "payout",
          payload: {}
        )
      end
      assert_raises(ArgumentError) do
        RubyRouting::State::AttemptSnapshot.new(
          attempt_id: invalid,
          operation_id: "operation",
          provider_id: "A",
          role: :primary
        )
      end
      assert_raises(ArgumentError) do
        RubyRouting::State::LifecycleLedger::PhaseChange.new(
          operation_id: invalid,
          attempt_id: "attempt",
          provider_id: "A",
          from: :unknown,
          to: :resolving
        )
      end
      assert_raises(ArgumentError) do
        RubyRouting::Routing::AllocationSnapshot.new(measures: { invalid => 1 })
      end
      assert_raises(ArgumentError) do
        RubyRouting::RoutingConstraints.new(allowed_provider_ids: [invalid])
      end
      assert_raises(ArgumentError) do
        RubyRouting::Routing::ProviderHealthSnapshot.new(provider_id: invalid)
      end
      assert_raises(ArgumentError) do
        RubyRouting::Routing::ProviderQualitySnapshot.new(provider_id: invalid)
      end
    end

    catalog = RubyRouting::State::ProviderCatalogLedger.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    assert_raises(ArgumentError) { catalog.key?([]) }
  end

  def test_identity_normalization_preserves_trimmed_strings_and_symbols
    assert_equal "provider", RubyRouting::Identity.normalize(" provider ", "provider id")
    assert_equal "provider", RubyRouting::Identity.normalize(:provider, "provider id")
    assert_raises(ArgumentError) { RubyRouting::Identity.normalize(nil, "provider id") }
  end

  def test_provider_configuration_scalars_reject_arbitrary_string_coercion
    spoofed_currency = Object.new
    def spoofed_currency.to_s
      "RUB"
    end

    spoofed_version = Object.new
    def spoofed_version.to_s
      "capability-7"
    end

    spoofed_reason = Object.new
    def spoofed_reason.to_s
      "disabled-by-policy"
    end

    assert_raises(ArgumentError) do
      RubyRouting::CapacityBudget.new(max_amount_minor: 100, currency: spoofed_currency)
    end
    assert_raises(ArgumentError) do
      RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        supported_currencies: [spoofed_currency]
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::ProviderCapabilities.new(version: spoofed_version)
    end
    assert_raises(ArgumentError) do
      RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        functional_eligible: false,
        exclusion_reason: spoofed_reason
      )
    end
  end
end
