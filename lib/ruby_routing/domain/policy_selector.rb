# frozen_string_literal: true

module RubyRouting
  # Small typed selector for automatic policy resolution. It deliberately
  # models only bounded generic route dimensions rather than introducing a
  # general rules language before the authoritative TZ exists.
  class PolicySelector
    KEYS = %i[
      currency payment_method rail destination_kind destination_type labels segment segments priority
    ].freeze

    attr_reader :currency, :payment_method, :rail, :destination_kind, :labels, :priority

    def initialize(currency: nil, payment_method: nil, rail: nil, destination_kind: nil,
                   destination_type: nil, labels: [], segment: nil, segments: nil, priority: 0)
      @currency = normalize_currency(currency)
      @payment_method = RubyRouting::RoutingContext.normalize_token(payment_method, "selector payment_method")
      @rail = RubyRouting::RoutingContext.normalize_token(rail, "selector rail")
      @destination_kind = normalize_destination_kind(destination_kind, destination_type)
      @labels = normalize_labels(labels, segment, segments)
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

      labels.all? { |label| context.labels.include?(label) }
    end

    # Higher priority wins first; specificity breaks ties deterministically.
    # Every field contributes at most a bounded, explainable amount.
    def precedence_key
      [priority, specificity].freeze
    end

    def specificity
      [currency, payment_method, rail, destination_kind].count { |value| !value.nil? } + labels.length
    end

    def empty?
      priority.zero? && specificity.zero?
    end

    def to_h
      {
        currency: currency,
        payment_method: payment_method,
        rail: rail,
        destination_kind: destination_kind,
        labels: labels,
        priority: priority
      }.freeze
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
  end
end
