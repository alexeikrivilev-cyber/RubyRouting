# frozen_string_literal: true

module RubyRouting
  # Small typed selector for automatic policy resolution. It deliberately
  # models only bounded generic route dimensions rather than introducing a
  # general rules language before the authoritative TZ exists.
  class PolicySelector
    KEYS = %i[
      currency payment_method rail destination_kind destination_type labels segment segments
      minimum_amount_minor maximum_amount_minor priority
    ].freeze

    attr_reader :currency, :payment_method, :rail, :destination_kind, :labels,
                :minimum_amount_minor, :maximum_amount_minor, :priority

    def initialize(currency: nil, payment_method: nil, rail: nil, destination_kind: nil,
                   destination_type: nil, labels: [], segment: nil, segments: nil,
                   minimum_amount_minor: nil, maximum_amount_minor: nil, priority: 0)
      @currency = normalize_currency(currency)
      @payment_method = RubyRouting::RoutingContext.normalize_token(payment_method, "selector payment_method")
      @rail = RubyRouting::RoutingContext.normalize_token(rail, "selector rail")
      @destination_kind = normalize_destination_kind(destination_kind, destination_type)
      @labels = normalize_labels(labels, segment, segments)
      @minimum_amount_minor = normalize_amount_bound(minimum_amount_minor, "minimum_amount_minor")
      @maximum_amount_minor = normalize_amount_bound(maximum_amount_minor, "maximum_amount_minor")
      if (@minimum_amount_minor || @maximum_amount_minor) && @currency.nil?
        raise ArgumentError, "amount bands require an explicit selector currency"
      end
      if @minimum_amount_minor && @maximum_amount_minor && @minimum_amount_minor > @maximum_amount_minor
        raise ArgumentError, "minimum_amount_minor cannot exceed maximum_amount_minor"
      end
      unless priority.is_a?(Integer) && priority >= 0
        raise ArgumentError, "selector priority must be a non-negative Integer"
      end

      @priority = priority
      freeze
    end

    def self.from(value)
      return new if value.nil?
      return value if value.is_a?(self)

      values = RubyRouting::HashKeys.symbolize(value, KEYS, "policy selector")
      new(**values)
    end

    def matches?(intent)
      return false unless intent.is_a?(RubyRouting::PayoutIntent)
      return false if currency && intent.money.currency != currency

      context = intent.routing_context
      return false if payment_method && context.payment_method != payment_method
      return false if rail && context.rail != rail
      return false if destination_kind && context.destination_kind != destination_kind
      amount_minor = intent.money.amount_minor
      return false if minimum_amount_minor && amount_minor < minimum_amount_minor
      return false if maximum_amount_minor && amount_minor > maximum_amount_minor

      labels.all? { |label| context.labels.include?(label) }
    end

    # Kept as a diagnostic compatibility key. PolicyRegistry uses semantic
    # subsumption for same-priority matches instead of treating this field
    # count as a business tie-break.
    def precedence_key
      [priority, specificity].freeze
    end

    def specificity
      [
        currency, payment_method, rail, destination_kind,
        minimum_amount_minor, maximum_amount_minor
      ].count { |value| !value.nil? } + labels.length
    end

    # Returns true when this selector is a strict semantic narrowing of the
    # other selector. This is a partial order: incomparable matches must stay
    # ambiguous rather than being resolved by registration order or field
    # count. Priority is intentionally excluded from narrowing authority.
    def strictly_narrows?(other)
      other.is_a?(self.class) && priority == other.priority &&
        narrows_or_equals?(other) && self != other
    end

    def empty?
      priority.zero? && specificity.zero?
    end

    def to_h
      values = {
        currency: currency,
        payment_method: payment_method,
        rail: rail,
        destination_kind: destination_kind,
        labels: labels,
        priority: priority
      }
      values[:minimum_amount_minor] = minimum_amount_minor unless minimum_amount_minor.nil?
      values[:maximum_amount_minor] = maximum_amount_minor unless maximum_amount_minor.nil?
      values.freeze
    end

    def ==(other)
      other.is_a?(self.class) && to_h == other.to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end

    private

    def normalize_currency(value)
      return nil if value.nil?
      unless value.is_a?(String)
        raise ArgumentError, "selector currency must be a String"
      end

      normalized = value.strip.upcase
      raise ArgumentError, "selector currency must be a three-letter code" unless /\A[A-Z]{3}\z/.match?(normalized)

      normalized.freeze
    end

    def normalize_amount_bound(value, label)
      return nil if value.nil?
      unless value.is_a?(Integer) && value >= 0
        raise ArgumentError, "selector #{label} must be a non-negative Integer"
      end

      value
    end

    def normalize_destination_kind(destination_kind, destination_type)
      values = [destination_kind, destination_type].compact.map do |value|
        RubyRouting::RoutingContext.normalize_token(value, "selector destination_kind")
      end.uniq
      if values.length > 1
        raise ArgumentError, "selector contains conflicting destination aliases"
      end

      values.first
    end

    def normalize_labels(labels, segment, segments)
      values = [labels, segment, segments].compact.flat_map do |value|
        RubyRouting::RoutingContext.normalize_labels(value)
      end
      RubyRouting::RoutingContext.normalize_labels(values)
    end

    def narrows_or_equals?(other)
      value_narrows_or_equals?(currency, other.currency) &&
        value_narrows_or_equals?(payment_method, other.payment_method) &&
        value_narrows_or_equals?(rail, other.rail) &&
        value_narrows_or_equals?(destination_kind, other.destination_kind) &&
        (other.labels - labels).empty? &&
        lower_bound_narrows_or_equals?(minimum_amount_minor, other.minimum_amount_minor) &&
        upper_bound_narrows_or_equals?(maximum_amount_minor, other.maximum_amount_minor)
    end

    def value_narrows_or_equals?(value, broader_value)
      broader_value.nil? || value == broader_value
    end

    def lower_bound_narrows_or_equals?(value, broader_value)
      broader_value.nil? || (!value.nil? && value >= broader_value)
    end

    def upper_bound_narrows_or_equals?(value, broader_value)
      broader_value.nil? || (!value.nil? && value <= broader_value)
    end
  end
end
