# frozen_string_literal: true

require_relative "../test_helper"
require "json"

class ConfigurationIngressTest < Minitest::Test
  def test_canonical_count_configuration_round_trips_through_hash_and_json
    configuration = count_configuration

    decoded = RubyRouting::Application::RoutingConfiguration.decode(configuration.to_h)
    decoded_json = RubyRouting::Application::RoutingConfiguration.decode(
      JSON.parse(JSON.generate(configuration.to_h))
    )

    assert_equal configuration.to_h, decoded.to_h
    assert_equal configuration.to_h, decoded_json.to_h
    assert decoded.frozen?
    assert decoded.policies.first.frozen?
    assert decoded.provider_opportunities.first.frozen?
  end

  def test_canonical_volume_configuration_preserves_exact_rational_values
    configuration = volume_configuration

    decoded = RubyRouting::Application::RoutingConfiguration.decode(
      JSON.parse(JSON.generate(configuration.to_h))
    )

    assert_equal configuration.to_h, decoded.to_h
    assert_instance_of Rational, decoded.policies.first.tolerance
    assert_equal Rational(125, 100), decoded.policies.first.tolerance
    assert_equal Rational(1, 3), decoded.policies.first.minimum_shares.fetch("A")
  end

  def test_decoder_rejects_unknown_duplicate_and_malformed_transport_fields
    source = count_configuration.to_h
    policy = source.fetch(:policies).first

    assert_raises(ArgumentError) do
      RubyRouting::Application::RoutingConfiguration.decode(source.merge(unexpected: true))
    end
    assert_raises(ArgumentError) do
      RubyRouting::Application::RoutingConfiguration.decode(
        source.merge(policies: [policy.merge(selector: policy.fetch(:selector).merge(unexpected: true))])
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::Application::RoutingConfiguration.decode(
        { "policies" => source.fetch(:policies), :policies => source.fetch(:policies),
          "provider_opportunities" => source.fetch(:provider_opportunities) }
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::Application::RoutingConfiguration.decode(
        source.merge(policies: [policy.merge(tolerance: 0.5)])
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::Application::RoutingConfiguration.decode(
        source.merge(policies: [policy.merge(targets: { "A" => "1" })])
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::Application::RoutingConfiguration.decode(
        source.merge(policies: [policy.merge(minimum_shares: { "A" => "0.5" })])
      )
    end
  end

  def test_decoded_configuration_publishes_only_through_commands_and_keeps_diagnostics
    provider = TestSupport::Simulator::ScriptedProvider.new(
      provider_id: "A",
      steps: [TestSupport::Simulator::Step.success]
    )
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    configuration = RubyRouting::Application::RoutingConfiguration.decode(
      count_configuration.to_h.merge(
        policies: [count_configuration.to_h.fetch(:policies).first.merge(
          targets: { "A" => 1 },
          maximum_shares: { "A" => Rational(1, 1) },
          selector: count_configuration.to_h.fetch(:policies).first.fetch(:selector).merge(
            payment_method: nil,
            rail: nil,
            destination_kind: nil,
            labels: [],
            minimum_amount_minor: nil,
            maximum_amount_minor: nil
          ),
          hard_constraints: {
            allowed_provider_ids: ["A"],
            excluded_provider_ids: [],
            required_context_labels: [],
            minimum_amount_minor: nil,
            maximum_amount_minor: nil
          },
          soft_constraints: {
            allowed_provider_ids: nil,
            excluded_provider_ids: [],
            required_context_labels: [],
            minimum_amount_minor: nil,
            maximum_amount_minor: nil
          }
        )],
        provider_opportunities: [coordinator.provider_opportunities.first.to_h]
      )
    )

    published = service.apply_configuration(configuration)

    assert_same configuration, published
    assert_equal configuration.to_h, service.queries.configuration.to_h
    assert_equal 1, service.queries.configuration_revision
    assert_equal :valid, service.queries.configuration_status
  end

  def test_configuration_export_is_the_explicit_fresh_bootstrap_input
    configuration = count_configuration
    providers = %w[A B].to_h do |provider_id|
      [provider_id, TestSupport::Simulator::ScriptedProvider.new(
        provider_id: provider_id,
        steps: [TestSupport::Simulator::Step.success]
      )]
    end
    active_store = RubyRouting::Application::ConfigurationStore.new(configuration: configuration)
    active_service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: providers,
      configuration_store: active_store
    )
    active_service.apply_configuration(configuration)
    exported = JSON.parse(JSON.generate(active_service.queries.configuration.to_h))

    fresh_configuration = RubyRouting::Application::RoutingConfiguration.decode(exported)
    fresh_store = RubyRouting::Application::ConfigurationStore.new(configuration: fresh_configuration)
    fresh_service = RubyRouting::Application::Service.new(
      coordinator: RubyRouting::State::Coordinator.new,
      providers: providers,
      configuration_store: fresh_store
    )

    assert_equal JSON.parse(JSON.generate(configuration.to_h)), exported
    assert_equal configuration.to_h, fresh_configuration.to_h
    assert_equal configuration.to_h, fresh_service.queries.configuration.to_h
    assert_equal 1, active_service.queries.configuration_revision
    assert_equal 0, fresh_service.queries.configuration_revision
    assert_equal %w[A B], fresh_service.queries.providers.map(&:provider_id)
  end

  private

  def count_configuration
    RubyRouting::Application::RoutingConfiguration.new(
      policies: [
        RubyRouting::RoutingPolicy.new(
          id: "ingress-count",
          epoch: "1",
          measure: :count,
          targets: { "A" => 2, "B" => 1 },
          currency: "RUB",
          scope: "default",
          tolerance: Rational(1, 1),
          minimum_shares: { "A" => Rational(1, 3) },
          maximum_shares: { "A" => Rational(2, 3), "B" => Rational(2, 3) },
          selector: RubyRouting::PolicySelector.new(
            currency: "RUB",
            payment_method: "card",
            rail: "bank",
            destination_kind: "bank",
            labels: ["retail"],
            minimum_amount_minor: 10,
            maximum_amount_minor: 1_000,
            priority: 2
          ),
          recovery: RubyRouting::RecoveryPolicy.new(
            max_operations: 3,
            max_switches: 2,
            max_resolution_interactions: 1,
            initial_delay_seconds: 2,
            backoff_seconds: 3,
            max_delay_seconds: 8
          ),
          ranking: RubyRouting::RankingPolicy.new(
            priority_by_provider: { "A" => 1, "B" => 2 },
            cost_minor_by_provider: { "A" => 5, "B" => 7 },
            latency_ms_by_provider: { "A" => 20, "B" => 30 }
          ),
          hard_constraints: RubyRouting::RoutingConstraints.new(
            allowed_provider_ids: ["A", "B"],
            required_context_labels: ["retail"],
            minimum_amount_minor: 10,
            maximum_amount_minor: 1_000
          ),
          soft_constraints: RubyRouting::RoutingConstraints.new(
            excluded_provider_ids: ["B"]
          )
        )
      ],
      provider_opportunities: [
        provider("A", supported_currencies: ["RUB"], required_context_labels: ["retail"]),
        provider("B", supported_currencies: ["RUB"])
      ]
    )
  end

  def volume_configuration
    RubyRouting::Application::RoutingConfiguration.new(
      policies: [
        RubyRouting::RoutingPolicy.new(
          id: "ingress-volume",
          epoch: "1",
          measure: :volume,
          targets: { "A" => 1, "B" => 1 },
          currency: "USD",
          tolerance: Rational(125, 100),
          minimum_measures: { "A" => 100 },
          maximum_measures: { "B" => 10_000 },
          minimum_shares: { "A" => Rational(1, 3) },
          selector: { currency: "USD", minimum_amount_minor: 100 }
        )
      ],
      provider_opportunities: [
        provider("A", supported_currencies: ["USD"]),
        provider("B", supported_currencies: ["USD"])
      ]
    )
  end

  def provider(id, supported_currencies:, required_context_labels: [])
    RubyRouting::ProviderOpportunity.new(
      provider_id: id,
      supported_currencies: supported_currencies,
      required_context_labels: required_context_labels,
      capabilities: RubyRouting::ProviderCapabilities.new(
        status_lookup: true,
        ttl_seconds: 60,
        deadline_seconds: 120,
        authoritative_sequence: true
      ),
      route_capabilities: RubyRouting::ProviderRouteCapabilities.new(
        supported_payment_methods: ["card"],
        supported_rails: ["bank"],
        supported_destination_kinds: ["bank"]
      ),
      capacity: RubyRouting::CapacityBudget.new(
        max_slots: 2,
        max_amount_minor: 100_000,
        currency: supported_currencies.first
      ),
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 10, window_seconds: 60)
    )
  end
end
