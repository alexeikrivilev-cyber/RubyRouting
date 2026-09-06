# frozen_string_literal: true

module RubyRouting
  # Exact non-negative monetary value represented in minor units.
  class Money
    CURRENCY_PATTERN = /\A[A-Z]{3}\z/.freeze

    attr_reader :amount_minor, :currency

    def initialize(amount_minor, currency)
      unless amount_minor.is_a?(Integer) && amount_minor >= 0
        raise ArgumentError, "amount_minor must be a non-negative Integer"
      end

      normalized_currency = normalize_currency(currency)

      @amount_minor = amount_minor
      @currency = normalized_currency
      freeze
    end

    def +(other)
      assert_same_currency!(other)
      self.class.new(amount_minor + other.amount_minor, currency)
    end

    def -(other)
      assert_same_currency!(other)
      result = amount_minor - other.amount_minor
      raise ArgumentError, "money subtraction cannot produce a negative amount" if result.negative?

      self.class.new(result, currency)
    end

    def zero?
      amount_minor.zero?
    end

    def ==(other)
      other.is_a?(self.class) &&
        amount_minor == other.amount_minor &&
        currency == other.currency
    end
    alias eql? ==

    def hash
      [self.class, amount_minor, currency].hash
    end

    def inspect
      "#<#{self.class} #{amount_minor} minor #{currency}>"
    end

    private

    def normalize_currency(currency)
      unless currency.is_a?(String)
        raise ArgumentError, "currency must be a String"
      end

      normalized = currency.strip.upcase
      unless CURRENCY_PATTERN.match?(normalized)
        raise ArgumentError, "currency must be a three-letter code"
      end

      normalized.freeze
    end

    def assert_same_currency!(other)
      unless other.is_a?(self.class)
        raise ArgumentError, "money operation requires Money"
      end
      return if currency == other.currency

      raise ArgumentError, "cannot operate on different currencies"
    end
  end
end
