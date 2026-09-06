# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class PolicyResolutionTest < Minitest::Test
  def test_specificity_wins_independently_of_registration_order
    generic = policy("generic", selector: {})
    card = policy("card", selector: { payment_method: :card })
    intent = intent_with(payment_method: "card")

    first = RubyRouting::PolicyRegistry.new([generic, card]).resolve_for_intent(intent)
    second = RubyRouting::PolicyRegistry.new([card, generic]).resolve_for_intent(intent)

    assert first.matched?
    assert_equal card, first.policy
    assert_equal first.to_h, second.to_h
    assert_equal 1, first.policy.selector.specificity
  end

  def test_explicit_priority_beats_a_more_specific_lower_priority_selector
    specific = policy("specific", selector: { payment_method: :card, rail: :sepa })
    priority = policy(
      "priority",
      selector: { payment_method: :card, priority: 1 }
    )

    resolution = RubyRouting::PolicyRegistry.new([specific, priority]).resolve_for_intent(
      intent_with(payment_method: "card", rail: "sepa")
    )

    assert_equal priority, resolution.policy
  end

  def test_semantic_subsumption_wins_independently_of_registration_order
    broad = policy("broad-card", selector: { payment_method: :card })
    band = policy(
      "card-band",
      selector: {
        currency: "RUB",
        payment_method: :card,
        minimum_amount_minor: 100,
        maximum_amount_minor: 500
      }
    )
    intent = RubyRouting::PayoutIntent.new(
      id: "banded-intent",
      money: RubyRouting::Money.new(250, "RUB"),
      context: { payment_method: :card }
    )

    first = RubyRouting::PolicyRegistry.new([broad, band]).resolve_for_intent(intent)
    second = RubyRouting::PolicyRegistry.new([band, broad]).resolve_for_intent(intent)

    assert first.matched?
    assert_equal band, first.policy
    assert_equal first.to_h, second.to_h
  end

  def test_equal_priority_incomparable_matches_remain_ambiguous_even_with_different_field_counts
    label_policy = policy(
      "label-narrow",
      selector: { payment_method: :card, labels: %i[priority retail] }
    )
    rail_policy = policy(
      "rail-narrow",
      selector: { payment_method: :card, rail: :sepa }
    )
    intent = RubyRouting::PayoutIntent.new(
      id: "incomparable-intent",
      money: RubyRouting::Money.new(250, "RUB"),
      context: {
        payment_method: :card,
        rail: :sepa,
        labels: %i[priority retail]
      }
    )

    first = RubyRouting::PolicyRegistry.new([label_policy, rail_policy]).resolve_for_intent(intent)
    second = RubyRouting::PolicyRegistry.new([rail_policy, label_policy]).resolve_for_intent(intent)

    assert first.ambiguous?
    assert_equal [label_policy, rail_policy].map(&:scope_key).sort,
      first.candidates.map(&:scope_key).sort
    assert_equal first.to_h, second.to_h
  end

  def test_amount_band_boundaries_and_currency_are_exact
    low = policy(
      "low-band",
      selector: { currency: "RUB", minimum_amount_minor: 0, maximum_amount_minor: 999 }
    )
    high = policy(
      "high-band",
      selector: { currency: "RUB", minimum_amount_minor: 1_000, maximum_amount_minor: 1_999 }
    )
    registry = RubyRouting::PolicyRegistry.new([low, high])

    assert_equal low, registry.find_for_intent(intent_with_amount(999, "RUB"))
    assert_equal high, registry.find_for_intent(intent_with_amount(1_000, "RUB"))
    assert_equal high, registry.find_for_intent(intent_with_amount(1_999, "RUB"))
    assert registry.resolve_for_intent(intent_with_amount(2_000, "RUB")).no_match?
    assert registry.resolve_for_intent(intent_with_amount(1_000, "USD")).no_match?
  end

  def test_equal_precedence_is_ambiguous_under_registration_permutations
    method_policy = policy("method", selector: { payment_method: :card })
    rail_policy = policy("rail", selector: { rail: :sepa })
    intent = intent_with(payment_method: "card", rail: "sepa")

    first = RubyRouting::PolicyRegistry.new([method_policy, rail_policy]).resolve_for_intent(intent)
    second = RubyRouting::PolicyRegistry.new([rail_policy, method_policy]).resolve_for_intent(intent)

    assert first.ambiguous?
    assert_equal first.to_h, second.to_h
    assert_equal [method_policy, rail_policy], first.candidates
  end

  def test_policy_currency_participates_in_semantic_subsumption
    currency_policy = policy("currency", selector: {}, currency: "RUB")
    method_policy = policy("method-currency-overlap", selector: { payment_method: :card })
    intent = intent_with(id: "currency-policy-overlap", payment_method: "card")

    first = RubyRouting::PolicyRegistry.new([currency_policy, method_policy]).resolve_for_intent(intent)
    second = RubyRouting::PolicyRegistry.new([method_policy, currency_policy]).resolve_for_intent(intent)

    assert first.ambiguous?
    assert second.ambiguous?
    assert_equal first.to_h, second.to_h
    assert_equal [currency_policy, method_policy].sort_by(&:scope_key), first.candidates
    assert_equal "RUB", first.to_h.fetch(:candidates).find { |candidate| candidate[:id] == "currency" }.fetch(:currency)
    assert_nil first.to_h.fetch(:candidates).find { |candidate| candidate[:id] == "method-currency-overlap" }.fetch(:currency)
  end

  def test_no_match_is_typed_and_orchestrator_does_not_register_state
    registry = RubyRouting::PolicyRegistry.new([policy("rub", selector: { currency: "RUB" })])
    intent = RubyRouting::PayoutIntent.new(
      id: "policy-no-match",
      money: RubyRouting::Money.new(100, "USD")
    )
    resolution = registry.resolve_for_intent(intent)

    assert resolution.no_match?
    assert_empty resolution.candidates
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    orchestrator = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: {},
      policy_registry: registry
    )

    error = assert_raises(RubyRouting::NoMatchingPolicyError) do
      orchestrator.submit(intent: intent)
    end
    assert_equal resolution.to_h, error.resolution.to_h
    assert_empty coordinator.facts.select { |fact| fact.type == :intent_registered }
    assert_empty coordinator.facts.select { |fact| fact.type == :policy_registered }
  end

  def test_orchestrator_seeds_policy_resolution_from_supplied_configuration_store
    policy = policy("store-policy", selector: { payment_method: :card })
    opportunity = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    store = RubyRouting::Application::ConfigurationStore.new(
      configuration: RubyRouting::Application::RoutingConfiguration.new(
        policies: [policy],
        provider_opportunities: [opportunity]
      )
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity])
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.success]
    )
    orchestrator = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider },
      configuration_store: store
    )

    result = orchestrator.submit(intent: intent_with(id: "store-policy-payout", payment_method: :card))

    assert_equal :success, result.status
    assert_equal ["store-policy"], orchestrator.policy_registry.policies.map(&:id)
  end

  def test_orchestrator_policy_registry_view_tracks_supplied_registry
    initial = policy("orchestrator-initial", selector: {})
    published = policy("orchestrator-published", selector: {})
    registry = RubyRouting::PolicyRegistry.new([initial])
    opportunity = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    store = RubyRouting::Application::ConfigurationStore.new(
      configuration: RubyRouting::Application::RoutingConfiguration.new(
        policies: [initial],
        provider_opportunities: [opportunity]
      )
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [opportunity]
    )
    orchestrator = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: {},
      policy_registry: registry,
      configuration_store: store
    )
    commands = RubyRouting::Application::Commands.new(
      coordinator: coordinator,
      orchestrator: orchestrator,
      policy_registry: registry,
      configuration_store: store
    )

    commands.register_policy(published)

    assert_equal [initial, published].map(&:id), orchestrator.policy_registry.policies.map(&:id)
    refute_respond_to orchestrator.policy_registry, :register
  end

  def test_orchestrator_rejects_mismatched_registry_before_provider_bootstrap
    configuration_policy = policy("store-policy-before-rejection", selector: {})
    registry_policy = policy("registry-policy-before-rejection", selector: {})
    opportunity = RubyRouting::ProviderOpportunity.new(provider_id: "A")
    store = RubyRouting::Application::ConfigurationStore.new(
      configuration: RubyRouting::Application::RoutingConfiguration.new(
        policies: [configuration_policy],
        provider_opportunities: [opportunity]
      )
    )
    coordinator = RubyRouting::State::Coordinator.new

    assert_raises(ArgumentError) do
      RubyRouting::Application::Orchestrator.new(
        coordinator: coordinator,
        providers: {},
        policy_registry: RubyRouting::PolicyRegistry.new([registry_policy]),
        configuration_store: store
      )
    end

    assert_empty coordinator.provider_opportunities
  end

  def test_pinned_policy_wins_over_a_new_ambiguous_active_configuration_on_resume
    pinned = policy("pinned", selector: { payment_method: :card })
    competing = policy("competing", selector: { payment_method: :card })
    registry = RubyRouting::PolicyRegistry.new([pinned])
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [
        TestSupport::Simulator::Step.unknown,
        TestSupport::Simulator::Step.success
      ]
    )
    orchestrator = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => provider },
      policy_registry: registry
    )
    intent = intent_with(id: "policy-pinned", payment_method: "card")

    first = orchestrator.submit(intent: intent)
    registry.register(competing)
    resumed = orchestrator.resume(payout_id: intent.id)

    assert_equal :unknown, first.status
    assert_equal :success, resumed.status
    assert_equal pinned, coordinator.policy_for(intent.id)
  end

  def test_selector_definition_and_fingerprint_survive_durable_restart
    Dir.mktmpdir("ruby-routing-policy-resolution") do |directory|
      path = File.join(directory, "facts.jsonl")
      policy = policy(
        "selector-restart",
        selector: {
          currency: "RUB",
          payment_method: :card,
          rail: :domestic,
          labels: [:retail],
          minimum_amount_minor: 100,
          maximum_amount_minor: 500
        }
      )
      intent = RubyRouting::PayoutIntent.new(
        id: "selector-restart-payout",
        money: RubyRouting::Money.new(100, "RUB"),
        context: { payment_method: :card, rail: :domestic, labels: [:retail] }
      )
      first = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
      )

      first.prepare_and_commit_decision(intent: intent, policy: policy)
      restored = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )

      restored_policy = restored.policy_for(intent.id)
      assert_equal policy.selector, restored_policy.selector
      assert_equal policy.fingerprint, restored_policy.fingerprint
      assert_equal policy.to_h, restored_policy.to_h
    end
  end

  def test_policy_resolution_rejects_non_scalar_scope_input
    registry = RubyRouting::PolicyRegistry.new([policy("strict-scope", selector: {})])

    assert_raises(ArgumentError) do
      registry.resolve_for_intent(intent_with(id: "strict-scope-payout"), scope: [])
    end
    assert_raises(ArgumentError) do
      RubyRouting::PolicyResolution.new(status: :no_match, scope: Object.new)
    end
  end

  def test_selector_aliases_are_canonicalized_and_conflicts_fail_closed
    selector = RubyRouting::PolicySelector.from(
      "destination_type" => "Bank_Account",
      "segment" => "Retail",
      "segments" => [:priority]
    )

    assert_equal "bank_account", selector.destination_kind
    assert_equal %w[priority retail], selector.labels
    assert_raises(ArgumentError) do
      RubyRouting::PolicySelector.new(destination_kind: :card, destination_type: :bank_account)
    end
    assert_raises(ArgumentError) do
      RubyRouting::PolicySelector.new(minimum_amount_minor: 1)
    end
    assert_raises(ArgumentError) do
      RubyRouting::PolicySelector.new(
        currency: "RUB",
        minimum_amount_minor: 2,
        maximum_amount_minor: 1
      )
    end
  end

  def test_explicit_selector_mismatch_is_rejected_before_payout_registration
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = policy("card-only", selector: { payment_method: :card })
    intent = intent_with(id: "selector-mismatch", payment_method: :bank_transfer)

    assert_raises(ArgumentError) do
      coordinator.prepare_and_commit_decision(intent: intent, policy: policy)
    end
    assert_empty coordinator.facts.select { |fact| fact.type == :intent_registered }
    assert_empty coordinator.facts.select { |fact| fact.type == :policy_registered }
  end

  private

  def policy(id, selector:, currency: nil)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      currency: currency,
      selector: selector
    )
  end

  def intent_with(id: "policy-resolution-intent", payment_method: nil, rail: nil)
    RubyRouting::PayoutIntent.new(
      id: id,
      money: RubyRouting::Money.new(100, "RUB"),
      context: { payment_method: payment_method, rail: rail }
    )
  end

  def intent_with_amount(amount_minor, currency)
    RubyRouting::PayoutIntent.new(
      id: "amount-#{amount_minor}-#{currency}",
      money: RubyRouting::Money.new(amount_minor, currency)
    )
  end
end
