# frozen_string_literal: true

require_relative "../test_helper"

class ProviderCatalogLedgerTest < Minitest::Test
  def test_catalog_tracks_current_opportunities_and_ordered_registration_timeline
    ledger = RubyRouting::State::ProviderCatalogLedger.new
    provider_a = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    provider_b = RubyRouting::ProviderOpportunity.new(provider_id: "B")

    ledger.register(provider_a, sequence: 1)
    ledger.register(provider_b, sequence: 2)

    assert_equal %w[A B], ledger.provider_ids
    assert ledger.registered_before?("A", sequence: 2)
    refute ledger.registered_before?("B", sequence: 2)
    assert ledger.current_before?("A", sequence: 3)

    ledger.remove("A", sequence: 3)

    assert_equal ["B"], ledger.provider_ids
    refute ledger.current_before?("A", sequence: 4)

    ledger.register(provider_a, sequence: 5)

    assert ledger.current_before?("A", sequence: 6)
    assert_equal %w[A B], ledger.current.map(&:provider_id)
  end

  def test_supplied_runtime_catalog_is_not_backdated_into_history
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "supplied")
    ledger = RubyRouting::State::ProviderCatalogLedger.new(opportunities: [provider])

    assert ledger.key?("supplied")
    refute ledger.registered_before?("supplied", sequence: 1)
    refute ledger.current_before?("supplied", sequence: 1)
  end

  def test_runtime_replacement_preserves_timeline_and_rejects_unknown_ids
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    replacement = provider.with_runtime(available: false)
    ledger = RubyRouting::State::ProviderCatalogLedger.new
    ledger.register(provider, sequence: 1)

    ledger.replace_current(replacement)

    assert_equal false, ledger.fetch("A").available
    assert ledger.current_before?("A", sequence: 2)
    assert_raises(KeyError) { ledger.replace_current(RubyRouting::ProviderOpportunity.new(provider_id: "B")) }
  end

  def test_timeline_sequences_must_advance_before_mutation
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    ledger = RubyRouting::State::ProviderCatalogLedger.new
    ledger.register(provider, sequence: 3)

    assert_raises(ArgumentError) { ledger.register(provider, sequence: 3) }
    assert_raises(ArgumentError) { ledger.remove("A", sequence: 2) }
    assert ledger.current_before?("A", sequence: 4)
  end

  def test_constructor_rejects_non_enumerable_opportunity_input
    assert_raises(ArgumentError) do
      RubyRouting::State::ProviderCatalogLedger.new(opportunities: nil)
    end
  end

  def test_constructor_accepts_an_each_only_enumerable
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    ledger = RubyRouting::State::ProviderCatalogLedger.new(
      opportunities: TestSupport::EachOnlyCollection.new([provider])
    )

    assert_equal ["A"], ledger.provider_ids
  end

  def test_provider_definitions_reject_truthy_non_boolean_flags
    assert_raises(ArgumentError) do
      RubyRouting::ProviderOpportunity.new(provider_id: "A", available: "false")
    end
    assert_raises(ArgumentError) do
      RubyRouting::ProviderCapabilities.new(status_lookup: "false")
    end
    assert_raises(ArgumentError) do
      RubyRouting::ProviderOperationContract.new(
        provider_id: "A",
        idempotent_retry: "false",
        idempotency_key: "payout:operation"
      )
    end
  end

  def test_provider_opportunity_collections_accept_each_only_enumerables
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      supported_currencies: TestSupport::EachOnlyCollection.new(["RUB"]),
      required_context_labels: TestSupport::EachOnlyCollection.new(["retail"])
    )
    intent = RubyRouting::PayoutIntent.new(
      id: "each-only-opportunity",
      money: RubyRouting::Money.new(100, "RUB"),
      context: { labels: TestSupport::EachOnlyCollection.new(["retail"]) }
    )

    assert opportunity.functional_eligible_for?(intent: intent)
    assert opportunity.feasible_for?(intent: intent)
  end
end
