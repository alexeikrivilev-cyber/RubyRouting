# frozen_string_literal: true

module RubyRouting
  # Generic provider support for route dimensions owned by RoutingContext.
  # Nil means that a provider has not declared a boundary for that dimension;
  # an explicit empty set means that no value in the dimension is supported.
  class ProviderRouteCapabilities
    DIMENSION_KEYS = %i[
      supported_payment_methods supported_rails supported_destination_kinds
    ].freeze

    attr_reader :supported_payment_methods, :supported_rails,
                :supported_destination_kinds

    def initialize(supported_payment_methods: nil, supported_rails: nil,
                   supported_destination_kinds: nil)
      @supported_payment_methods = normalize_dimension(
        supported_payment_methods, "supported payment methods"
      )
      @supported_rails = normalize_dimension(supported_rails, "supported rails")
      @supported_destination_kinds = normalize_dimension(
        supported_destination_kinds, "supported destination kinds"
      )
      freeze
    end

    def self.from(value)
      return new if value.nil?
      return value if value.is_a?(self)

      values = RubyRouting::HashKeys.symbolize(
        value,
        DIMENSION_KEYS,
        "provider route capabilities"
      )
      new(**values)
    end

    def matches?(routing_context)
      exclusion_reason(routing_context).nil?
    end

    def exclusion_reason(routing_context)
      unless routing_context.is_a?(RubyRouting::RoutingContext)
        raise ArgumentError, "routing_context must be RubyRouting::RoutingContext"
      end

      dimension_mismatch(
        supported_payment_methods,
        routing_context.payment_method,
        :unsupported_payment_method
      ) || dimension_mismatch(
        supported_rails,
        routing_context.rail,
        :unsupported_rail
      ) || dimension_mismatch(
        supported_destination_kinds,
        routing_context.destination_kind,
        :unsupported_destination_kind
      )
    end

    def to_h
      {
        supported_payment_methods: supported_payment_methods,
        supported_rails: supported_rails,
        supported_destination_kinds: supported_destination_kinds
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

    def normalize_dimension(value, label)
      return nil if value.nil?

      RubyRouting::Collection.to_array(value, label).map do |item|
        RubyRouting::RoutingContext.normalize_token(item, label)
      end.uniq.sort.freeze
    end

    def dimension_mismatch(supported, actual, reason)
      return nil if supported.nil?
      return nil if actual && supported.include?(actual)

      reason
    end
  end
end
