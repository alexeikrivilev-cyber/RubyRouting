# frozen_string_literal: true

module RubyRouting
  module Application
    class ConfigurationDiagnostic
      SEVERITIES = %i[warning error].freeze

      attr_reader :severity, :code, :policy_scope_key, :provider_id, :details

      def initialize(severity:, code:, policy_scope_key: nil, provider_id: nil, details: {})
        @severity = RubyRouting::Enum.normalize(severity, SEVERITIES, "configuration diagnostic severity")
        unless code.is_a?(Symbol) && !code.to_s.empty?
          raise ArgumentError, "configuration diagnostic code must be a non-empty Symbol"
        end
        @code = code
        if !policy_scope_key.nil? &&
           (!policy_scope_key.is_a?(Array) || !policy_scope_key.all? { |value| value.is_a?(String) })
          raise ArgumentError, "configuration diagnostic policy scope key must be an Array of Strings or nil"
        end
        @policy_scope_key = policy_scope_key&.map { |value| value.dup.freeze }&.freeze
        if !provider_id.nil? && !(provider_id.is_a?(String) || provider_id.is_a?(Symbol))
          raise ArgumentError, "configuration diagnostic provider id must be a String, Symbol or nil"
        end
        @provider_id = provider_id&.to_s&.strip&.freeze
        raise ArgumentError, "configuration diagnostic provider id must be non-empty" if @provider_id == ""
        unless details.is_a?(Hash)
          raise ArgumentError, "configuration diagnostic details must be a Hash"
        end
        @details = RubyRouting::ImmutableData.deep_freeze(details)
        freeze
      end

      def error?
        severity == :error
      end

      def warning?
        severity == :warning
      end

      def to_h
        values = { severity: severity, code: code }
        values[:policy_scope_key] = policy_scope_key unless policy_scope_key.nil?
        values[:provider_id] = provider_id unless provider_id.nil?
        values[:details] = details unless details.empty?
        values.freeze
      end
    end

    class ConfigurationCompilationError < ArgumentError
      attr_reader :compilation

      def initialize(compilation)
        @compilation = compilation
        super("active routing configuration is statically invalid")
      end
    end

    class ConfigurationCompilation
      STATUSES = %i[valid valid_with_warnings invalid].freeze

      attr_reader :configuration, :diagnostics, :status

      def initialize(configuration:, diagnostics:)
        unless configuration.is_a?(RubyRouting::Application::RoutingConfiguration)
          raise ArgumentError, "configuration must be Application::RoutingConfiguration"
        end
        unless diagnostics.is_a?(Array) && diagnostics.all? do |diagnostic|
          diagnostic.is_a?(RubyRouting::Application::ConfigurationDiagnostic)
        end
          raise ArgumentError, "configuration diagnostics must be typed values"
        end

        @configuration = configuration
        @diagnostics = diagnostics.sort_by do |diagnostic|
          [
            diagnostic.severity.to_s,
            diagnostic.code.to_s,
            diagnostic.policy_scope_key&.join("\u0000").to_s,
            diagnostic.provider_id.to_s
          ]
        end.freeze
        @status = if @diagnostics.any?(&:error?)
          :invalid
        elsif @diagnostics.any?(&:warning?)
          :valid_with_warnings
        else
          :valid
        end
        freeze
      end

      def valid?
        status != :invalid
      end

      def warnings?
        status == :valid_with_warnings
      end

      def errors
        diagnostics.select(&:error?).freeze
      end

      def warnings
        diagnostics.select(&:warning?).freeze
      end

      def raise_if_invalid!
        raise RubyRouting::Application::ConfigurationCompilationError, self unless valid?

        self
      end

      def to_h
        {
          status: status,
          configuration: configuration.to_h,
          diagnostics: diagnostics.map(&:to_h).freeze
        }.freeze
      end
    end

    # Immutable active routing configuration. It is an application/control-
    # plane value, not payout history: policies and provider opportunities are
    # validated by their existing domain constructors and serialized in a
    # canonical order for a later transport or judge mapping.
    class RoutingConfiguration
      attr_reader :policies, :provider_opportunities

      def self.same_provider_opportunity_set?(left, right)
        normalize = lambda do |opportunities|
          RubyRouting::Collection.to_array(opportunities, "provider opportunities")
            .sort_by(&:provider_id)
            .map(&:to_h)
        end

        normalize.call(left) == normalize.call(right)
      end

      def self.same_provider_definition_set?(left, right)
        normalize = lambda do |opportunities|
          RubyRouting::Collection.to_array(opportunities, "provider opportunities")
            .sort_by(&:provider_id)
            .map(&:definition_to_h)
        end

        normalize.call(left) == normalize.call(right)
      end

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

      def resolve_policy_for(intent, scope: :default)
        RubyRouting::PolicyRegistry.new(policies).resolve_for_intent(intent, scope: scope)
      end

      def compile
        RubyRouting::Application::ConfigurationCompiler.compile(self)
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

    class ConfigurationCompiler
      class << self
        def compile(configuration)
          unless configuration.is_a?(RubyRouting::Application::RoutingConfiguration)
            raise ArgumentError, "configuration must be Application::RoutingConfiguration"
          end
          unless configuration.policies.is_a?(Array) &&
                 configuration.provider_opportunities.is_a?(Array)
            raise ArgumentError, "configuration is malformed"
          end
          unless configuration.policies.all? { |policy| policy.is_a?(RubyRouting::RoutingPolicy) } &&
                 configuration.provider_opportunities.all? do |opportunity|
                   opportunity.is_a?(RubyRouting::ProviderOpportunity)
                 end
            raise ArgumentError, "configuration contains untyped values"
          end
          provider_ids = configuration.provider_opportunities.map(&:provider_id)
          unless provider_ids.uniq.length == provider_ids.length
            raise ArgumentError, "configuration provider opportunities must have unique ids"
          end

          providers = configuration.provider_opportunities.to_h do |opportunity|
            [opportunity.provider_id, opportunity]
          end
          diagnostics = configuration.policies.flat_map do |policy|
            diagnostics_for_policy(policy, providers)
          end
          RubyRouting::Application::ConfigurationCompilation.new(
            configuration: configuration,
            diagnostics: diagnostics
          )
        end

        private

        def diagnostics_for_policy(policy, providers)
          diagnostics = []
          static = policy.static_feasibility
          if static[:status] == :infeasible
            diagnostics << RubyRouting::Application::ConfigurationDiagnostic.new(
              severity: :error,
              code: :policy_static_infeasible,
              policy_scope_key: policy.scope_key,
              details: { reason_codes: static[:reason_codes] }
            )
          end

          policy.targets.each_key do |provider_id|
            provider = providers[provider_id]
            if provider.nil?
              diagnostics << RubyRouting::Application::ConfigurationDiagnostic.new(
                severity: :warning,
                code: :target_provider_not_configured,
                policy_scope_key: policy.scope_key,
                provider_id: provider_id
              )
              next
            end

            diagnostics.concat(provider_compatibility_diagnostics(policy, provider))
            unless provider.functional_eligible && provider.enabled && provider.available &&
                   provider.health_available && provider.capacity_available && provider.throughput_available
              diagnostics << RubyRouting::Application::ConfigurationDiagnostic.new(
                severity: :warning,
                code: :target_provider_not_currently_admissible,
                policy_scope_key: policy.scope_key,
                provider_id: provider.provider_id,
                details: { reason: provider.reason }
              )
            end
          end
          diagnostics
        end

        def provider_compatibility_diagnostics(policy, provider)
          diagnostics = []
          selector = policy.selector
          fixed_currency = policy.currency || selector.currency
          if fixed_currency && provider.supported_currencies.any? &&
             !provider.supported_currencies.include?(fixed_currency)
            diagnostics << diagnostic(
              :provider_currency_incompatible,
              policy,
              provider,
              expected_currency: fixed_currency,
              supported_currencies: provider.supported_currencies
            )
          end

          route_dimensions = {
            payment_method: [selector.payment_method, provider.route_capabilities.supported_payment_methods],
            rail: [selector.rail, provider.route_capabilities.supported_rails],
            destination_kind: [selector.destination_kind, provider.route_capabilities.supported_destination_kinds]
          }
          route_dimensions.each do |dimension, (value, supported)|
            next if value.nil? || supported.nil? || supported.include?(value)

            diagnostics << diagnostic(
              :provider_route_incompatible,
              policy,
              provider,
              dimension: dimension,
              value: value,
              supported: supported
            )
          end

          # Provider amount limits are expressed in minor units, so compare
          # them only when the policy fixes a currency. Selector amount bands
          # already require that currency; generic hard constraints do not.
          policy_minimum = selector.minimum_amount_minor
          policy_maximum = selector.maximum_amount_minor
          if fixed_currency
            policy_minimum = [
              policy_minimum,
              policy.hard_constraints.minimum_amount_minor
            ].compact.max
            policy_maximum = [
              policy_maximum,
              policy.hard_constraints.maximum_amount_minor
            ].compact.min
          end
          if amount_ranges_disjoint?(policy_minimum, policy_maximum,
                                     provider.minimum_amount_minor, provider.maximum_amount_minor)
            diagnostics << diagnostic(
              :provider_amount_incompatible,
              policy,
              provider,
              policy_minimum_amount_minor: policy_minimum,
              policy_maximum_amount_minor: policy_maximum,
              provider_minimum_amount_minor: provider.minimum_amount_minor,
              provider_maximum_amount_minor: provider.maximum_amount_minor
            )
          end
          diagnostics
        end

        def amount_ranges_disjoint?(first_minimum, first_maximum, second_minimum, second_maximum)
          return false if first_minimum.nil? && first_maximum.nil?
          return false if second_minimum.nil? && second_maximum.nil?

          (first_maximum && second_minimum && first_maximum < second_minimum) ||
            (second_maximum && first_minimum && second_maximum < first_minimum)
        end

        def diagnostic(code, policy, provider, details)
          RubyRouting::Application::ConfigurationDiagnostic.new(
            severity: :error,
            code: code,
            policy_scope_key: policy.scope_key,
            provider_id: provider.provider_id,
            details: details
          )
        end
      end
    end

    # Immutable publication value for the active control-plane generation.
    # The revision belongs to the publication, not to durable payout history;
    # a payout still pins its own policy and provider-operation semantics.
    class ActiveConfigurationSnapshot
      attr_reader :revision, :configuration

      def initialize(revision:, configuration:, diagnostics: [])
        unless revision.is_a?(Integer) && revision >= 0
          raise ArgumentError, "configuration revision must be a non-negative Integer"
        end
        unless configuration.is_a?(RubyRouting::Application::RoutingConfiguration)
          raise ArgumentError, "configuration must be Application::RoutingConfiguration"
        end
        unless diagnostics.is_a?(Array) && diagnostics.all? do |diagnostic|
          diagnostic.is_a?(RubyRouting::Application::ConfigurationDiagnostic)
        end
          raise ArgumentError, "configuration diagnostics must be typed values"
        end

        @revision = revision
        @configuration = configuration
        @diagnostics = diagnostics.dup.freeze
        freeze
      end

      attr_reader :diagnostics

      def policies
        configuration.policies
      end

      def provider_opportunities
        configuration.provider_opportunities
      end

      def to_h
        {
          revision: revision,
          configuration: configuration.to_h,
          diagnostics: diagnostics.map(&:to_h).freeze
        }.freeze
      end
    end

    # Holds only the current active configuration. It is intentionally not a
    # journal and therefore cannot rewrite the durable policy/provider facts
    # already attached to payouts.
    class ConfigurationStore
      def initialize(configuration:)
        compilation = RubyRouting::Application::ConfigurationCompiler.compile(configuration)
        compilation.raise_if_invalid!
        @mutex = Thread::Mutex.new
        @configuration = compilation.configuration
        @snapshot = RubyRouting::Application::ActiveConfigurationSnapshot.new(
          revision: 0,
          configuration: @configuration,
          diagnostics: compilation.diagnostics
        )
      end

      def current
        @mutex.synchronize { @configuration }
      end

      def current_snapshot
        @mutex.synchronize { @snapshot }
      end

      def revision
        current_snapshot.revision
      end

      # Routing readers and control-plane publishers share this one seam. The
      # yielded immutable snapshot may safely be used after the lock is
      # released, but callers must keep provider I/O outside this block.
      def with_snapshot
        raise ArgumentError, "configuration snapshot block is required" unless block_given?

        @mutex.synchronize { yield @snapshot }
      end

      private

      # Publish one complete configuration generation. The candidate is
      # validated before the publication becomes visible; an exception leaves
      # the previous snapshot current.
      def update
        raise ArgumentError, "configuration update block is required" unless block_given?

        @mutex.synchronize do
          replacement = yield @configuration
          compilation = RubyRouting::Application::ConfigurationCompiler.compile(replacement)
          compilation.raise_if_invalid!
          @configuration = compilation.configuration
          @snapshot = RubyRouting::Application::ActiveConfigurationSnapshot.new(
            revision: @snapshot.revision + 1,
            configuration: @configuration,
            diagnostics: compilation.diagnostics
          )
          @configuration
        end
      end

      def replace(configuration)
        update { |_current| configuration }
      end

    end
  end
end
