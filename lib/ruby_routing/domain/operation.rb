# frozen_string_literal: true

module RubyRouting
  class ProviderOperationRequest
    attr_reader :payout_id, :provider_id, :operation_id, :attempt_id, :money, :idempotency_key

    def initialize(payout_id:, provider_id:, operation_id:, attempt_id:, money:)
      @payout_id = normalize_id(payout_id, "payout id")
      @provider_id = normalize_id(provider_id, "provider id")
      @operation_id = normalize_id(operation_id, "operation id")
      @attempt_id = normalize_id(attempt_id, "attempt id")
      unless money.is_a?(RubyRouting::Money)
        raise ArgumentError, "money must be RubyRouting::Money"
      end

      @money = money
      @idempotency_key = "#{@payout_id}:#{@operation_id}".freeze
      freeze
    end

    private

    def normalize_id(value, label)
      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized.freeze
    end
  end
end
