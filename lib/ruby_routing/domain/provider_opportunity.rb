# frozen_string_literal: true

module RubyRouting
  class CapacityBudget
    attr_reader :max_slots, :max_count, :max_amount_minor, :currency

    def initialize(max_slots: nil, max_count: nil, max_amount_minor: nil, currency: nil)
      @max_slots = normalize_limit(max_slots, "max_slots")
      @max_count = normalize_limit(max_count, "max_count")
      @max_amount_minor = normalize_limit(max_amount_minor, "max_amount_minor")
      if @max_amount_minor && currency.nil?
        raise ArgumentError, "capacity currency is required for amount budgets"
      end
      @currency = currency && normalize_currency(currency)
      freeze
    end

    # A payout operation consumes one concurrent exposure unit. `max_count`
    # remains accepted as a durable/backward-compatible cap, but it is not a
    # second counter: the effective in-flight limit is the stricter configured
    # bound. Time-window counts belong to ThroughputBudget.
    def concurrent_limit
      [max_slots, max_count].compact.min
    end

    def constrained?
      !concurrent_limit.nil? || !max_amount_minor.nil?
    end

    def allows?(money, used_slots:, used_count:, used_amount_minor:)
      return false unless money.is_a?(RubyRouting::Money)
      return false if currency && money.currency != currency
      # Both public snapshot names are retained for durable compatibility, but
      # they must describe one canonical in-flight exposure value.
      return false unless used_slots == used_count
      return false if concurrent_limit && used_slots >= concurrent_limit
      return false if max_amount_minor && used_amount_minor + money.amount_minor > max_amount_minor

      true
    end

    def to_h
      {
        max_slots: max_slots,
        max_count: max_count,
        max_amount_minor: max_amount_minor,
        currency: currency
      }.freeze
    end

    private

    def normalize_limit(value, label)
      return nil if value.nil?
      unless value.is_a?(Integer) && value >= 0
        raise ArgumentError, "#{label} must be a non-negative Integer or nil"
      end

      value
    end

    def normalize_currency(value)
      unless value.is_a?(String) || value.is_a?(Symbol)
        raise ArgumentError, "capacity currency must be a String or Symbol"
      end

      normalized = value.to_s.strip.upcase
      raise ArgumentError, "capacity currency must be a three-letter code" unless /\A[A-Z]{3}\z/.match?(normalized)

      normalized.freeze
    end
  end

  class ProviderCapabilities
    attr_reader :idempotent_retry, :status_lookup, :ttl_seconds, :deadline_seconds,
                :version, :authoritative_sequence

    def initialize(idempotent_retry: false, status_lookup: false, ttl_seconds: nil,
                   deadline_seconds: nil, version: "1", authoritative_sequence: false)
      @idempotent_retry = normalize_boolean(idempotent_retry, "idempotent_retry")
      @status_lookup = normalize_boolean(status_lookup, "status_lookup")
      @ttl_seconds = normalize_duration(ttl_seconds, "ttl_seconds")
      @deadline_seconds = normalize_duration(deadline_seconds, "deadline_seconds")
      @version = RubyRouting::Identity.normalize(version, "provider capability version")
      @authoritative_sequence = normalize_boolean(authoritative_sequence, "authoritative_sequence")
      freeze
    end

    def can_resolve?
      status_lookup || idempotent_retry
    end

    def to_h
      {
        idempotent_retry: idempotent_retry,
        status_lookup: status_lookup,
        ttl_seconds: ttl_seconds,
        deadline_seconds: deadline_seconds,
        version: version,
        authoritative_sequence: authoritative_sequence
      }.freeze
    end

    private

    def normalize_duration(value, label)
      return nil if value.nil?
      unless value.is_a?(Integer) && value.positive?
        raise ArgumentError, "#{label} must be a positive Integer or nil"
      end

      value
    end

    def normalize_boolean(value, label)
      return value if value == true || value == false

      raise ArgumentError, "#{label} must be boolean"
    end
  end

  class ThroughputBudget
    attr_reader :max_operations, :window_seconds

    def initialize(max_operations:, window_seconds:)
      unless max_operations.is_a?(Integer) && max_operations.positive?
        raise ArgumentError, "max_operations must be a positive Integer"
      end
      unless window_seconds.is_a?(Integer) && window_seconds.positive?
        raise ArgumentError, "window_seconds must be a positive Integer"
      end

      @max_operations = max_operations
      @window_seconds = window_seconds
      freeze
    end

    def to_h
      {
        max_operations: max_operations,
        window_seconds: window_seconds
      }.freeze
    end
  end

  class ProviderOpportunity
    # These fields are operational evidence rather than the functional
    # provider definition. They can change inside the Coordinator while an
    # active configuration generation remains valid.
    RUNTIME_FIELDS = %i[
      available
      capacity_available
      enabled
      health_available
      throughput_available
    ].freeze

    attr_reader :provider_id, :functional_eligible, :available, :capacity_available,
                :capabilities, :exclusion_reason, :supported_currencies,
                :minimum_amount_minor, :maximum_amount_minor,
                :required_context_labels, :enabled, :capacity, :health_available,
                :throughput, :throughput_available, :route_capabilities

    def initialize(provider_id:, functional_eligible: true, available: true,
                   capacity_available: true, capabilities: ProviderCapabilities.new,
                   exclusion_reason: nil, supported_currencies: nil,
                   minimum_amount_minor: nil, maximum_amount_minor: nil,
                   required_context_labels: [], enabled: true, capacity: nil,
                   health_available: true, throughput: nil, throughput_available: true,
                   route_capabilities: nil, supported_payment_methods: nil,
                   supported_rails: nil, supported_destination_kinds: nil)
      @provider_id = normalize_id(provider_id)
      @functional_eligible = normalize_boolean(functional_eligible, "functional_eligible")
      @available = normalize_boolean(available, "available")
      @capacity_available = normalize_boolean(capacity_available, "capacity_available")
      unless capabilities.is_a?(ProviderCapabilities)
        raise ArgumentError, "capabilities must be ProviderCapabilities"
      end

      @capabilities = capabilities
      direct_route_values = [
        supported_payment_methods, supported_rails, supported_destination_kinds
      ]
      direct_route_capabilities = ProviderRouteCapabilities.new(
        supported_payment_methods: supported_payment_methods,
        supported_rails: supported_rails,
        supported_destination_kinds: supported_destination_kinds
      )
      configured_route_capabilities = ProviderRouteCapabilities.from(route_capabilities)
      direct_route_values_provided = direct_route_values.any? { |value| !value.nil? }
      if route_capabilities && direct_route_values_provided &&
         configured_route_capabilities != direct_route_capabilities
        raise ArgumentError, "route_capabilities does not match supported route dimensions"
      end
      @route_capabilities = if direct_route_values_provided
        direct_route_capabilities
      else
        configured_route_capabilities
      end
      @exclusion_reason = if exclusion_reason.nil?
        nil
      else
        RubyRouting::Identity.normalize(exclusion_reason, "provider exclusion reason")
      end
      @supported_currencies = normalize_currencies(supported_currencies)
      @minimum_amount_minor = normalize_amount_limit(minimum_amount_minor, "minimum_amount_minor")
      @maximum_amount_minor = normalize_amount_limit(maximum_amount_minor, "maximum_amount_minor")
      if @minimum_amount_minor && @maximum_amount_minor && @minimum_amount_minor > @maximum_amount_minor
        raise ArgumentError, "minimum amount cannot exceed maximum amount"
      end
      @required_context_labels = normalize_labels(required_context_labels)
      @enabled = normalize_boolean(enabled, "enabled")
      unless capacity.nil? || capacity.is_a?(CapacityBudget)
        raise ArgumentError, "capacity must be CapacityBudget"
      end
      @capacity = capacity
      @health_available = normalize_boolean(health_available, "health_available")
      unless throughput.nil? || throughput.is_a?(ThroughputBudget)
        raise ArgumentError, "throughput must be ThroughputBudget"
      end
      @throughput = throughput
      @throughput_available = normalize_boolean(throughput_available, "throughput_available")
      freeze
    end

    def feasible?
      functional_eligible && enabled && health_available && available && capacity_available && throughput_available
    end

    def functional_eligible_for?(intent:, policy: nil)
      return false unless functional_eligible
      return false unless intent.is_a?(RubyRouting::PayoutIntent)
      return false if supported_currencies.any? && !supported_currencies.include?(intent.money.currency)
      return false if minimum_amount_minor && intent.money.amount_minor < minimum_amount_minor
      return false if maximum_amount_minor && intent.money.amount_minor > maximum_amount_minor
      return false if policy && !policy.hard_constraints.allows?(intent: intent, provider_id: provider_id)
      return false unless route_capabilities.matches?(intent.routing_context)

      labels = intent.routing_context.labels
      required_context_labels.all? { |label| labels.include?(label) }
    end

    def feasible_for?(intent:, policy: nil)
      functional_eligible_for?(intent: intent, policy: policy) && enabled && health_available && available && capacity_available && throughput_available
    end

    def with_runtime(available: self.available, capacity_available: self.capacity_available,
                     enabled: self.enabled, health_available: self.health_available,
                     throughput_available: self.throughput_available)
      self.class.new(
        provider_id: provider_id,
        functional_eligible: functional_eligible,
        available: available,
        capacity_available: capacity_available,
        capabilities: capabilities,
        exclusion_reason: exclusion_reason,
        supported_currencies: supported_currencies,
        minimum_amount_minor: minimum_amount_minor,
        maximum_amount_minor: maximum_amount_minor,
        required_context_labels: required_context_labels,
        enabled: enabled,
        capacity: capacity,
        health_available: health_available,
        throughput: throughput,
        throughput_available: throughput_available,
        route_capabilities: route_capabilities
      )
    end

    def to_h
      {
        provider_id: provider_id,
        functional_eligible: functional_eligible,
        available: available,
        capacity_available: capacity_available,
        capabilities: capabilities.to_h,
        exclusion_reason: exclusion_reason,
        supported_currencies: supported_currencies,
        minimum_amount_minor: minimum_amount_minor,
        maximum_amount_minor: maximum_amount_minor,
        required_context_labels: required_context_labels,
        route_capabilities: route_capabilities.to_h,
        enabled: enabled,
        capacity: capacity&.to_h,
        health_available: health_available,
        throughput: throughput&.to_h,
        throughput_available: throughput_available
      }.freeze
    end

    def definition_to_h
      to_h.reject { |key, _value| RUNTIME_FIELDS.include?(key) }.freeze
    end

    def reason_for(intent:, policy: nil)
      return exclusion_reason if exclusion_reason && !functional_eligible
      return :functionally_ineligible unless intent.is_a?(RubyRouting::PayoutIntent)
      if policy && !policy.hard_constraints.allows?(intent: intent, provider_id: provider_id)
        return :hard_policy_constraint
      end
      route_reason = route_capabilities.exclusion_reason(intent.routing_context)
      return route_reason unless route_reason.nil?
      return :functionally_ineligible unless functional_eligible_for?(intent: intent, policy: policy)
      return :disabled unless enabled
      return :quarantined unless health_available
      return :unavailable unless available
      return :capacity_exhausted unless capacity_available
      return :throughput_exhausted unless throughput_available

      nil
    end

    def reason
      return exclusion_reason if exclusion_reason
      return :functionally_ineligible unless functional_eligible
      return :disabled unless enabled
      return :quarantined unless health_available
      return :unavailable unless available
      return :capacity_exhausted unless capacity_available
      return :throughput_exhausted unless throughput_available

      nil
    end

    private

    def normalize_id(value)
      unless value.is_a?(String) || value.is_a?(Symbol)
        raise ArgumentError, "provider id must be a non-empty String or Symbol"
      end

      normalized = value.to_s.strip
      raise ArgumentError, "provider id must be non-empty" if normalized.empty?

      normalized.freeze
    end

    def normalize_boolean(value, label)
      return value if value == true || value == false

      raise ArgumentError, "#{label} must be boolean"
    end

    def normalize_currencies(value)
      return [].freeze if value.nil?

      RubyRouting::Collection.to_array(value, "supported_currencies").map do |currency|
        unless currency.is_a?(String) || currency.is_a?(Symbol)
          raise ArgumentError, "supported currencies must be Strings or Symbols"
        end

        normalized = currency.to_s.strip.upcase
        raise ArgumentError, "supported currencies must be three-letter codes" unless /\A[A-Z]{3}\z/.match?(normalized)

        normalized.freeze
      end.uniq.freeze
    end

    def normalize_amount_limit(value, label)
      return nil if value.nil?
      unless value.is_a?(Integer) && value >= 0
        raise ArgumentError, "#{label} must be a non-negative Integer or nil"
      end

      value
    end

    def normalize_labels(value)
      RubyRouting::RoutingContext.normalize_labels(value)
    end
  end
end
