# frozen_string_literal: true

module RubyRouting
  module Application
    # Immutable active routing configuration. It is an application/control-
    # plane value, not payout history: policies and provider opportunities are
    # validated by their existing domain constructors and serialized in a
    # canonical order for a later transport or judge mapping.
    class RoutingConfiguration
      attr_reader :policies, :provider_opportunities

      def initialize(policies: [], provider_opportunities: [])
        @policies = normalize_policies(policies)
        @provider_opportunities = normalize_provider_opportunities(provider_opportunities)
        freeze
      end

      def to_h
        {
          policies: policies.map(&:to_h).freeze,
          provider_opportunities: provider_opportunities.map(&:to_h).freeze
        }.freeze
      end

      private

      def normalize_policies(value)
        values = RubyRouting::Collection.to_array(value, "configuration policies")
        unless values.all? { |policy| policy.is_a?(RubyRouting::RoutingPolicy) }
          raise ArgumentError, "configuration policies must contain RoutingPolicy values"
        end

        # Let the existing registry own duplicate identity/fingerprint
        # validation and use its canonical ordering for stable serialization.
        RubyRouting::PolicyRegistry.new(values).policies
      end

      def normalize_provider_opportunities(value)
        values = RubyRouting::Collection.to_array(value, "configuration provider opportunities")
        unless values.all? { |opportunity| opportunity.is_a?(RubyRouting::ProviderOpportunity) }
          raise ArgumentError,
            "configuration provider opportunities must contain ProviderOpportunity values"
        end

        provider_ids = values.map(&:provider_id)
        unless provider_ids.uniq.length == provider_ids.length
          raise ArgumentError, "configuration provider opportunities must have unique ids"
        end

        values.sort_by(&:provider_id).freeze
      end
    end

    # Holds only the current active configuration. It is intentionally not a
    # journal and therefore cannot rewrite the durable policy/provider facts
    # already attached to payouts.
    class ConfigurationStore
      def initialize(configuration:)
        validate(configuration)
        @mutex = Thread::Mutex.new
        @configuration = configuration
      end

      def current
        @mutex.synchronize { @configuration }
      end

      def replace(configuration)
        validate(configuration)
        @mutex.synchronize { @configuration = configuration }
        configuration
      end

      private

      def validate(configuration)
        return if configuration.is_a?(RubyRouting::Application::RoutingConfiguration)

        raise ArgumentError, "configuration must be Application::RoutingConfiguration"
      end
    end
  end
end
