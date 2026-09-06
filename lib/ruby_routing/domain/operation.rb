# frozen_string_literal: true

module RubyRouting
  class ProviderOperationContract
    attr_reader :provider_id, :idempotent_retry, :status_lookup, :idempotency_key,
                :ttl_seconds, :deadline_seconds, :version, :authoritative_sequence

    def initialize(provider_id:, idempotent_retry: false, status_lookup: false,
                   idempotency_key:, ttl_seconds: nil, deadline_seconds: nil,
                   version: "1", authoritative_sequence: false)
      @provider_id = normalize_id(provider_id, "provider id")
      @idempotent_retry = !!idempotent_retry
      @status_lookup = !!status_lookup
      @idempotency_key = normalize_id(idempotency_key, "idempotency key")
      @ttl_seconds = normalize_duration(ttl_seconds, "ttl_seconds")
      @deadline_seconds = normalize_duration(deadline_seconds, "deadline_seconds")
      @version = normalize_id(version, "contract version")
      @authoritative_sequence = !!authoritative_sequence
      freeze
    end

    def self.from_capabilities(provider_id:, payout_id:, operation_id:, capabilities:,
                               ttl_seconds: :inherit, deadline_seconds: :inherit)
      unless capabilities.is_a?(RubyRouting::ProviderCapabilities)
        raise ArgumentError, "capabilities must be ProviderCapabilities"
      end

      new(
        provider_id: provider_id,
        idempotent_retry: capabilities.idempotent_retry,
        status_lookup: capabilities.status_lookup,
        idempotency_key: "#{payout_id}:#{operation_id}",
        ttl_seconds: ttl_seconds == :inherit ? capabilities.ttl_seconds : ttl_seconds,
        deadline_seconds: deadline_seconds == :inherit ? capabilities.deadline_seconds : deadline_seconds,
        version: capabilities.version,
        authoritative_sequence: capabilities.authoritative_sequence
      )
    end

    def can_resolve?
      status_lookup || idempotent_retry
    end

    private

    def normalize_id(value, label)
      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized.freeze
    end

    def normalize_duration(value, label)
      return nil if value.nil?
      unless value.is_a?(Integer) && value.positive?
        raise ArgumentError, "#{label} must be a positive Integer or nil"
      end

      value
    end
  end

  class ProviderTransportResult
    KINDS = %i[definitely_not_sent ambiguous_after_possible_send].freeze

    attr_reader :kind, :message, :provider_reference

    def initialize(kind:, message: nil, provider_reference: nil)
      @kind = kind.to_sym
      raise ArgumentError, "unsupported transport result" unless KINDS.include?(@kind)

      @message = message&.to_s&.freeze
      @provider_reference = provider_reference&.to_s&.freeze
      freeze
    end

    def self.definitely_not_sent(message: nil, provider_reference: nil)
      new(kind: :definitely_not_sent, message: message, provider_reference: provider_reference)
    end

    def self.ambiguous_after_possible_send(message: nil, provider_reference: nil)
      new(kind: :ambiguous_after_possible_send, message: message, provider_reference: provider_reference)
    end
  end

  class ProviderTransportError < StandardError
    attr_reader :kind, :provider_reference

    def initialize(kind:, message: nil, provider_reference: nil)
      @kind = kind.to_sym
      unless ProviderTransportResult::KINDS.include?(@kind)
        raise ArgumentError, "unsupported transport error"
      end

      @provider_reference = provider_reference&.to_s&.freeze
      super(message)
    end

    def self.definitely_not_sent(message = nil, provider_reference: nil)
      new(kind: :definitely_not_sent, message: message, provider_reference: provider_reference)
    end

    def self.ambiguous_after_possible_send(message = nil, provider_reference: nil)
      new(kind: :ambiguous_after_possible_send, message: message, provider_reference: provider_reference)
    end
  end

  class SettlementReversal
    attr_reader :reversal_id, :payout_id, :provider_id, :operation_id, :amount, :reason

    def initialize(reversal_id:, payout_id:, provider_id:, operation_id:, amount:, reason:)
      @reversal_id = normalize_id(reversal_id, "reversal id")
      @payout_id = normalize_id(payout_id, "payout id")
      @provider_id = normalize_id(provider_id, "provider id")
      @operation_id = normalize_id(operation_id, "operation id")
      unless amount.is_a?(RubyRouting::Money) && amount.amount_minor.positive?
        raise ArgumentError, "reversal amount must be a positive Money"
      end

      @amount = amount
      @reason = reason.to_sym
      freeze
    end

    private

    def normalize_id(value, label)
      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized.freeze
    end
  end

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
