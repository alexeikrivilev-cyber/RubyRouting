# frozen_string_literal: true

module RubyRouting
  # Immutable, provider-agnostic route identity. The raw payout context is
  # intentionally kept on PayoutIntent for adapter metadata; this value owns
  # the small set of dimensions the routing kernel is allowed to interpret.
  class RoutingContext
    INPUT_KEYS = %i[
      payment_method rail destination_kind destination_type labels segment segments
    ].freeze

    attr_reader :payment_method, :rail, :destination_kind, :labels

    def initialize(payment_method: nil, rail: nil, destination_kind: nil, labels: [])
      @payment_method = self.class.normalize_token(payment_method, "payment_method")
      @rail = self.class.normalize_token(rail, "rail")
      @destination_kind = self.class.normalize_token(destination_kind, "destination_kind")
      @labels = self.class.normalize_labels(labels)
      freeze
    end

    def self.from(value = nil, strict: true, **keyword_values)
      unless keyword_values.empty?
        if value.nil?
          value = keyword_values
        else
          raise ArgumentError, "routing context accepts either a value or keyword dimensions"
        end
      end
      return value if value.is_a?(self)
      return new if value.nil?
      unless value.is_a?(Hash)
        raise ArgumentError, "routing context must be a Hash, RoutingContext or nil"
      end

      validate_input_keys!(value) if strict
      values = recognized_values(value)
      destination_kind = coalesced_alias(values, :destination_kind, :destination_type)
      labels = []
      %i[labels segment segments].each do |key|
        labels.concat(normalize_labels(values.fetch(key))) if values.key?(key)
      end

      new(
        payment_method: values[:payment_method],
        rail: values[:rail],
        destination_kind: destination_kind,
        labels: labels
      )
    end

    class << self
      alias from_context from

      def normalize_token(value, label)
        return nil if value.nil?
        unless value.is_a?(String) || value.is_a?(Symbol)
          raise ArgumentError, "#{label} must be a String, Symbol or nil"
        end

        normalized = value.to_s.strip.downcase
        raise ArgumentError, "#{label} must be non-empty when provided" if normalized.empty?

        normalized.freeze
      end

      def normalize_labels(value)
        return [].freeze if value.nil?

        values = value.is_a?(String) || value.is_a?(Symbol) ? [value] :
          RubyRouting::Collection.to_array(value, "routing context labels")
        values.map do |label|
          unless label.is_a?(String) || label.is_a?(Symbol)
            raise ArgumentError, "routing context labels must be String or Symbol values"
          end

          normalized = label.to_s.strip.downcase
          raise ArgumentError, "routing context labels must be non-empty" if normalized.empty?

          normalized.freeze
        end.uniq.sort.freeze
      end

      private

      def validate_input_keys!(value)
        value.each_key do |key|
          next if (key.is_a?(String) || key.is_a?(Symbol)) &&
            INPUT_KEYS.any? { |candidate| candidate.to_s == key.to_s }

          raise ArgumentError, "routing context contains unknown key #{key.inspect}"
        end
      end

      def recognized_values(value)
        value.each_with_object({}) do |(key, nested), values|
          next unless key.is_a?(String) || key.is_a?(Symbol)

          canonical_key = INPUT_KEYS.find { |candidate| candidate.to_s == key.to_s }
          next unless canonical_key
          if values.key?(canonical_key)
            raise ArgumentError, "routing context contains duplicate #{canonical_key}"
          end

          values[canonical_key] = nested
        end
      end

      def coalesced_alias(values, *keys)
        present = keys.filter_map { |key| values[key] if values.key?(key) }
        return nil if present.empty?

        normalized = present.map { |value| normalize_token(value, keys.first.to_s) }.uniq
        if normalized.length > 1
          raise ArgumentError, "routing context contains conflicting #{keys.first} aliases"
        end

        normalized.first
      end
    end

    def empty?
      payment_method.nil? && rail.nil? && destination_kind.nil? && labels.empty?
    end

    def to_h
      {
        payment_method: payment_method,
        rail: rail,
        destination_kind: destination_kind,
        labels: labels
      }.freeze
    end

    def ==(other)
      other.is_a?(self.class) && to_h == other.to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end
  end
end
