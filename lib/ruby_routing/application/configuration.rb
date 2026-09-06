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

      # Decode only the bounded canonical configuration vocabulary. This is a
      # transport boundary, not a second domain model: every nested value is
      # converted to an existing typed object before the compiler or Commands
      # can observe it.
      def self.decode(value)
        Decoder.new(value).call
      end

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

      class Decoder
        CONFIGURATION_KEYS = %i[policies provider_opportunities].freeze
        POLICY_KEYS = %i[
          id epoch measure targets currency scope accounting_point window tolerance
          minimum_measures maximum_measures minimum_shares maximum_shares selector
          recovery recovery_objective ranking hard_constraints soft_constraints
        ].freeze
        SELECTOR_KEYS = %i[
          currency payment_method rail destination_kind labels priority
          minimum_amount_minor maximum_amount_minor
        ].freeze
        RECOVERY_KEYS = %i[
          max_operations max_switches max_resolution_interactions ttl_seconds deadline_seconds
          initial_delay_seconds backoff_seconds max_delay_seconds
        ].freeze
        RANKING_KEYS = %i[priority_by_provider cost_minor_by_provider latency_ms_by_provider].freeze
        CONSTRAINT_KEYS = %i[
          allowed_provider_ids excluded_provider_ids required_context_labels
          minimum_amount_minor maximum_amount_minor
        ].freeze
        OPPORTUNITY_KEYS = %i[
          provider_id functional_eligible available capacity_available capabilities exclusion_reason
          supported_currencies minimum_amount_minor maximum_amount_minor required_context_labels
          route_capabilities enabled capacity health_available throughput throughput_available
        ].freeze
        CAPABILITY_KEYS = %i[
          idempotent_retry status_lookup ttl_seconds deadline_seconds version authoritative_sequence
        ].freeze
        CAPACITY_KEYS = %i[max_slots max_count max_amount_minor currency].freeze
        THROUGHPUT_KEYS = %i[max_operations window_seconds].freeze
        ROUTE_CAPABILITY_KEYS = %i[
          supported_payment_methods supported_rails supported_destination_kinds
        ].freeze
        OBJECTIVE_KEYS = %i[mode].freeze

        def initialize(value)
          @value = value
        end

        def call
          values = object(@value, CONFIGURATION_KEYS, CONFIGURATION_KEYS, "routing configuration")
          RubyRouting::Application::RoutingConfiguration.new(
            policies: array(values.fetch(:policies), "configuration policies").map { |policy| decode_policy(policy) },
            provider_opportunities: array(
              values.fetch(:provider_opportunities),
              "configuration provider opportunities"
            ).map { |opportunity| decode_opportunity(opportunity) }
          )
        end

        private

        def decode_policy(value)
          values = object(value, POLICY_KEYS - [:recovery_objective], POLICY_KEYS, "routing policy")
          RoutingPolicy.new(
            id: required_string(values, :id, "policy id"),
            epoch: required_string(values, :epoch, "policy epoch"),
            measure: enum(values.fetch(:measure), RoutingPolicy::MEASURES, "policy measure"),
            targets: positive_integer_map(values.fetch(:targets), "policy targets"),
            currency: nullable_string(values[:currency], "policy currency"),
            scope: required_string(values, :scope, "policy scope"),
            accounting_point: enum(
              values.fetch(:accounting_point),
              RoutingPolicy::ACCOUNTING_POINTS,
              "policy accounting point"
            ),
            window: enum(values.fetch(:window), RoutingPolicy::WINDOWS, "policy window"),
            tolerance: rational_or_nil(values[:tolerance], "policy tolerance"),
            minimum_measures: non_negative_integer_map(values.fetch(:minimum_measures), "minimum measures"),
            maximum_measures: non_negative_integer_map(values.fetch(:maximum_measures), "maximum measures"),
            minimum_shares: rational_map(values.fetch(:minimum_shares), "minimum shares"),
            maximum_shares: rational_map(values.fetch(:maximum_shares), "maximum shares"),
            selector: decode_selector(values.fetch(:selector)),
            recovery: decode_recovery(values.fetch(:recovery)),
            recovery_objective: decode_objective(values[:recovery_objective]),
            ranking: decode_ranking(values.fetch(:ranking)),
            hard_constraints: decode_constraints(values.fetch(:hard_constraints), "hard constraints"),
            soft_constraints: decode_constraints(values.fetch(:soft_constraints), "soft constraints")
          )
        end

        def decode_selector(value)
          values = object(value, SELECTOR_KEYS - %i[minimum_amount_minor maximum_amount_minor], SELECTOR_KEYS, "policy selector")
          PolicySelector.new(**{
            currency: nullable_string(values[:currency], "selector currency"),
            payment_method: nullable_string(values[:payment_method], "selector payment method"),
            rail: nullable_string(values[:rail], "selector rail"),
            destination_kind: nullable_string(values[:destination_kind], "selector destination kind"),
            labels: string_array(values.fetch(:labels), "selector labels"),
            priority: non_negative_integer(values.fetch(:priority), "selector priority"),
            minimum_amount_minor: nullable_non_negative_integer(
              values[:minimum_amount_minor],
              "selector minimum amount"
            ),
            maximum_amount_minor: nullable_non_negative_integer(
              values[:maximum_amount_minor],
              "selector maximum amount"
            )
          }.compact)
        end

        def decode_recovery(value)
          values = object(value, RECOVERY_KEYS - %i[initial_delay_seconds backoff_seconds max_delay_seconds], RECOVERY_KEYS, "recovery policy")
          RecoveryPolicy.new(**{
            max_operations: positive_integer(values.fetch(:max_operations), "recovery max operations"),
            max_switches: non_negative_integer(values.fetch(:max_switches), "recovery max switches"),
            max_resolution_interactions: non_negative_integer(
              values.fetch(:max_resolution_interactions),
              "recovery max resolution interactions"
            ),
            ttl_seconds: nullable_positive_integer(values[:ttl_seconds], "recovery ttl"),
            deadline_seconds: nullable_positive_integer(values[:deadline_seconds], "recovery deadline"),
            initial_delay_seconds: non_negative_integer(
              values.fetch(:initial_delay_seconds, 0),
              "recovery initial delay"
            ),
            backoff_seconds: non_negative_integer(
              values.fetch(:backoff_seconds, 0),
              "recovery backoff"
            ),
            max_delay_seconds: nullable_positive_integer(values[:max_delay_seconds], "recovery max delay")
          })
        end

        def decode_objective(value)
          return nil if value.nil?

          values = object(value, OBJECTIVE_KEYS, OBJECTIVE_KEYS, "recovery objective")
          RecoveryObjective.new(
            mode: enum(values.fetch(:mode), RecoveryObjective::MODES, "recovery objective mode")
          )
        end

        def decode_ranking(value)
          values = object(value, RANKING_KEYS, RANKING_KEYS, "ranking policy")
          RankingPolicy.new(
            priority_by_provider: non_negative_integer_map(
              values.fetch(:priority_by_provider),
              "provider priority metrics"
            ),
            cost_minor_by_provider: non_negative_integer_map(
              values.fetch(:cost_minor_by_provider),
              "provider cost metrics"
            ),
            latency_ms_by_provider: non_negative_integer_map(
              values.fetch(:latency_ms_by_provider),
              "provider latency metrics"
            )
          )
        end

        def decode_constraints(value, label)
          values = object(value, CONSTRAINT_KEYS, CONSTRAINT_KEYS, label)
          RoutingConstraints.new(
            allowed_provider_ids: nullable_string_array(values[:allowed_provider_ids], "#{label} allowed providers"),
            excluded_provider_ids: string_array(values.fetch(:excluded_provider_ids), "#{label} excluded providers"),
            required_context_labels: string_array(
              values.fetch(:required_context_labels),
              "#{label} required labels"
            ),
            minimum_amount_minor: nullable_non_negative_integer(
              values[:minimum_amount_minor],
              "#{label} minimum amount"
            ),
            maximum_amount_minor: nullable_non_negative_integer(
              values[:maximum_amount_minor],
              "#{label} maximum amount"
            )
          )
        end

        def decode_opportunity(value)
          values = object(value, OPPORTUNITY_KEYS, OPPORTUNITY_KEYS, "provider opportunity")
          ProviderOpportunity.new(
            provider_id: required_string(values, :provider_id, "provider id"),
            functional_eligible: boolean(values.fetch(:functional_eligible), "functional eligibility"),
            available: boolean(values.fetch(:available), "provider availability"),
            capacity_available: boolean(values.fetch(:capacity_available), "provider capacity availability"),
            capabilities: decode_capabilities(values.fetch(:capabilities)),
            exclusion_reason: nullable_string(values[:exclusion_reason], "provider exclusion reason"),
            supported_currencies: nullable_string_array(values[:supported_currencies], "supported currencies"),
            minimum_amount_minor: nullable_non_negative_integer(
              values[:minimum_amount_minor],
              "provider minimum amount"
            ),
            maximum_amount_minor: nullable_non_negative_integer(
              values[:maximum_amount_minor],
              "provider maximum amount"
            ),
            required_context_labels: string_array(
              values.fetch(:required_context_labels),
              "provider required labels"
            ),
            route_capabilities: decode_route_capabilities(values.fetch(:route_capabilities)),
            enabled: boolean(values.fetch(:enabled), "provider enabled flag"),
            capacity: decode_capacity(values[:capacity]),
            health_available: boolean(values.fetch(:health_available), "provider health availability"),
            throughput: decode_throughput(values[:throughput]),
            throughput_available: boolean(values.fetch(:throughput_available), "provider throughput availability")
          )
        end

        def decode_capabilities(value)
          values = object(value, CAPABILITY_KEYS, CAPABILITY_KEYS, "provider capabilities")
          ProviderCapabilities.new(
            idempotent_retry: boolean(values.fetch(:idempotent_retry), "idempotent retry"),
            status_lookup: boolean(values.fetch(:status_lookup), "status lookup"),
            ttl_seconds: nullable_positive_integer(values[:ttl_seconds], "provider ttl"),
            deadline_seconds: nullable_positive_integer(values[:deadline_seconds], "provider deadline"),
            version: required_string(values, :version, "provider capability version"),
            authoritative_sequence: boolean(values.fetch(:authoritative_sequence), "authoritative sequence")
          )
        end

        def decode_capacity(value)
          return nil if value.nil?

          values = object(value, CAPACITY_KEYS, CAPACITY_KEYS, "capacity budget")
          CapacityBudget.new(
            max_slots: nullable_non_negative_integer(values[:max_slots], "capacity max slots"),
            max_count: nullable_non_negative_integer(values[:max_count], "capacity max count"),
            max_amount_minor: nullable_non_negative_integer(values[:max_amount_minor], "capacity max amount"),
            currency: nullable_string(values[:currency], "capacity currency")
          )
        end

        def decode_throughput(value)
          return nil if value.nil?

          values = object(value, THROUGHPUT_KEYS, THROUGHPUT_KEYS, "throughput budget")
          ThroughputBudget.new(
            max_operations: positive_integer(values.fetch(:max_operations), "throughput max operations"),
            window_seconds: positive_integer(values.fetch(:window_seconds), "throughput window")
          )
        end

        def decode_route_capabilities(value)
          values = object(value, ROUTE_CAPABILITY_KEYS, ROUTE_CAPABILITY_KEYS, "route capabilities")
          ProviderRouteCapabilities.new(
            supported_payment_methods: nullable_string_array(
              values[:supported_payment_methods],
              "supported payment methods"
            ),
            supported_rails: nullable_string_array(values[:supported_rails], "supported rails"),
            supported_destination_kinds: nullable_string_array(
              values[:supported_destination_kinds],
              "supported destination kinds"
            )
          )
        end

        def object(value, required_keys, allowed_keys, label)
          unless value.is_a?(Hash)
            raise ArgumentError, "#{label} must be a Hash"
          end

          values = RubyRouting::HashKeys.symbolize(value, allowed_keys, label)
          missing = required_keys.reject { |key| values.key?(key) }
          raise ArgumentError, "#{label} is missing #{missing.join(", ")}" unless missing.empty?

          values
        end

        def array(value, label)
          raise ArgumentError, "#{label} must be an Array" unless value.is_a?(Array)

          value
        end

        def string_array(value, label)
          array(value, label).map { |item| required_string_value(item, label) }
        end

        def nullable_string_array(value, label)
          return nil if value.nil?

          string_array(value, label)
        end

        def positive_integer_map(value, label)
          integer_map(value, label) { |item| positive_integer(item, label) }
        end

        def non_negative_integer_map(value, label)
          integer_map(value, label) { |item| non_negative_integer(item, label) }
        end

        def rational_map(value, label)
          unless value.is_a?(Hash)
            raise ArgumentError, "#{label} must be a Hash"
          end

          value.each_with_object({}) do |(key, item), result|
            provider_id = required_string_value(key, "#{label} provider id")
            raise ArgumentError, "#{label} contains duplicate provider id" if result.key?(provider_id)

            result[provider_id] = rational(item, label)
          end
        end

        def integer_map(value, label)
          unless value.is_a?(Hash)
            raise ArgumentError, "#{label} must be a Hash"
          end

          value.each_with_object({}) do |(key, item), result|
            provider_id = required_string_value(key, "#{label} provider id")
            raise ArgumentError, "#{label} contains duplicate provider id" if result.key?(provider_id)

            result[provider_id] = yield(item)
          end
        end

        def rational_or_nil(value, label)
          value.nil? ? nil : rational(value, label)
        end

        def rational(value, label)
          return value if value.is_a?(Rational) && value >= 0

          unless value.is_a?(String) && /\A(?:0|[1-9]\d*)\/(?:[1-9]\d*)\z/.match?(value)
            raise ArgumentError, "#{label} must be an exact Rational or canonical numerator/denominator String"
          end

          numerator, denominator = value.split("/", 2).map { |part| Integer(part, 10) }
          Rational(numerator, denominator)
        rescue ArgumentError, TypeError, ZeroDivisionError
          raise ArgumentError, "#{label} must be an exact Rational or canonical numerator/denominator String"
        end

        def required_string(values, key, label)
          required_string_value(values.fetch(key), label)
        end

        def required_string_value(value, label)
          unless value.is_a?(String) && !value.empty? && value == value.strip
            raise ArgumentError, "#{label} must be a canonical non-empty String"
          end

          value
        end

        def nullable_string(value, label)
          return nil if value.nil?

          required_string_value(value, label)
        end

        def boolean(value, label)
          return value if value == true || value == false

          raise ArgumentError, "#{label} must be boolean"
        end

        def enum(value, allowed, label)
          RubyRouting::Enum.normalize(value, allowed, label)
        end

        def positive_integer(value, label)
          unless value.is_a?(Integer) && value.positive?
            raise ArgumentError, "#{label} must be a positive Integer"
          end

          value
        end

        def non_negative_integer(value, label)
          unless value.is_a?(Integer) && value >= 0
            raise ArgumentError, "#{label} must be a non-negative Integer"
          end

          value
        end

        def nullable_positive_integer(value, label)
          value.nil? ? nil : positive_integer(value, label)
        end

        def nullable_non_negative_integer(value, label)
          value.nil? ? nil : non_negative_integer(value, label)
        end
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
