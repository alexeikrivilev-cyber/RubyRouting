# frozen_string_literal: true

module RubyRouting
  class EconomicOwnership
    attr_reader :payout_id, :provider_id, :operation_id, :attempt_id

    def initialize(payout_id:, provider_id:, operation_id:, attempt_id:)
      @payout_id = normalize_id(payout_id, "payout id")
      @provider_id = normalize_id(provider_id, "provider id")
      @operation_id = normalize_id(operation_id, "operation id")
      @attempt_id = normalize_id(attempt_id, "attempt id")
      freeze
    end

    def unresolved?
      true
    end

    private

    def normalize_id(value, label)
      unless value.is_a?(String) || value.is_a?(Symbol)
        raise ArgumentError, "#{label} must be a non-empty String or Symbol"
      end

      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized.freeze
    end
  end
end
