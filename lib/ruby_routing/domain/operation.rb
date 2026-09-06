# frozen_string_literal: true

module RubyRouting
  class ProviderOperationContract
    attr_reader :provider_id, :idempotent_retry, :status_lookup, :idempotency_key,
                :ttl_seconds, :deadline_seconds, :version, :authoritative_sequence

    def initialize(provider_id:, idempotent_retry: false, status_lookup: false,
                   idempotency_key:, ttl_seconds: nil, deadline_seconds: nil,
                   version: "1", authoritative_sequence: false)
      @provider_id = normalize_id(provider_id, "provider id")
      @idempotent_retry = normalize_boolean(idempotent_retry, "idempotent_retry")
      @status_lookup = normalize_boolean(status_lookup, "status_lookup")
      @idempotency_key = normalize_id(idempotency_key, "idempotency key")
      @ttl_seconds = normalize_duration(ttl_seconds, "ttl_seconds")
      @deadline_seconds = normalize_duration(deadline_seconds, "deadline_seconds")
      @version = normalize_id(version, "contract version")
      @authoritative_sequence = normalize_boolean(authoritative_sequence, "authoritative_sequence")
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

    def to_h
      {
        provider_id: provider_id,
        idempotent_retry: idempotent_retry,
        status_lookup: status_lookup,
        idempotency_key: idempotency_key,
        ttl_seconds: ttl_seconds,
        deadline_seconds: deadline_seconds,
        version: version,
        authoritative_sequence: authoritative_sequence
      }.freeze
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

  class ProviderTransportResult
    KINDS = %i[definitely_not_sent ambiguous_after_possible_send].freeze

    attr_reader :kind, :message, :provider_reference

    def initialize(kind:, message: nil, provider_reference: nil)
      @kind = normalize_kind(kind, "transport result")

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

    private

    def normalize_kind(value, label)
      RubyRouting::Enum.normalize(value, KINDS, label)
    end
  end

  class ProviderTransportError < StandardError
    attr_reader :kind, :provider_reference

    def initialize(kind:, message: nil, provider_reference: nil)
      @kind = normalize_kind(kind)

      @provider_reference = provider_reference&.to_s&.freeze
      super(message)
    end

    def self.definitely_not_sent(message = nil, provider_reference: nil)
      new(kind: :definitely_not_sent, message: message, provider_reference: provider_reference)
    end

    def self.ambiguous_after_possible_send(message = nil, provider_reference: nil)
      new(kind: :ambiguous_after_possible_send, message: message, provider_reference: provider_reference)
    end

    private

    def normalize_kind(value)
      RubyRouting::Enum.normalize(value, ProviderTransportResult::KINDS, "transport error")
    end
  end

  # Generic, immutable payout destination. The core deliberately does not
  # impose a PSP-specific recipient schema; adapters map this data to their
  # provider contract at the I/O boundary.
  class PayoutDestination
    attr_reader :data
    alias value data

    def initialize(data)
      @data = RubyRouting::ImmutableData.deep_freeze(data)
      freeze
    end

    def to_h
      { data: data }.freeze
    end
  end

  class ProviderOperationPayload
    attr_reader :destination, :context, :routing_context, :payment_method, :rail, :contract

    def initialize(destination:, context:, routing_context: nil, payment_method: nil, rail: nil, contract: nil)
      unless destination.is_a?(RubyRouting::PayoutDestination)
        destination = RubyRouting::PayoutDestination.new(destination)
      end
      unless contract.nil? || contract.is_a?(RubyRouting::ProviderOperationContract)
        raise ArgumentError, "contract must be ProviderOperationContract or nil"
      end

      @destination = destination
      @context = RubyRouting::ImmutableData.deep_freeze(context)
      derived_routing_context = RubyRouting::RoutingContext.from(@context, strict: false)
      @routing_context = if routing_context.nil?
        derived_routing_context
      else
        RubyRouting::RoutingContext.from(routing_context, strict: true)
      end
      unless derived_routing_context.empty? || @routing_context == derived_routing_context
        raise ArgumentError, "routing_context does not match provider operation context"
      end
      explicit_payment_method = RubyRouting::RoutingContext.normalize_token(payment_method, "payment_method")
      explicit_rail = RubyRouting::RoutingContext.normalize_token(rail, "rail")
      ensure_dimension_matches!(explicit_payment_method, @routing_context.payment_method, "payment_method")
      ensure_dimension_matches!(explicit_rail, @routing_context.rail, "rail")
      @payment_method = @routing_context.payment_method || explicit_payment_method
      @rail = @routing_context.rail || explicit_rail
      @routing_context = RubyRouting::RoutingContext.new(
        payment_method: @payment_method,
        rail: @rail,
        destination_kind: @routing_context.destination_kind,
        labels: @routing_context.labels
      )
      @contract = contract
      freeze
    end

    def self.from_intent(intent, contract: nil)
      unless intent.is_a?(RubyRouting::PayoutIntent)
        raise ArgumentError, "intent must be RubyRouting::PayoutIntent"
      end

      new(
        destination: intent.recipient,
        context: intent.context,
        routing_context: intent.routing_context,
        payment_method: intent.routing_context.payment_method,
        rail: intent.routing_context.rail,
        contract: contract
      )
    end

    def to_h
      {
        destination: destination.data,
        context: context,
        routing_context: routing_context.to_h,
        payment_method: payment_method,
        rail: rail,
        contract: contract&.to_h
      }.freeze
    end

    private

    def ensure_dimension_matches!(explicit_value, canonical_value, label)
      return if explicit_value.nil? || canonical_value.nil? || explicit_value == canonical_value

      raise ArgumentError, "#{label} does not match routing context"
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
      @reason = reason.is_a?(Symbol) ? reason : reason.to_s.freeze
      freeze
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

  class ProviderOperationRequest
    attr_reader :payout_id, :provider_id, :operation_id, :attempt_id, :money, :idempotency_key,
                :payload

    def initialize(payout_id:, provider_id:, operation_id:, attempt_id:, money:,
                   destination: {}, context: {}, routing_context: nil,
                   payment_method: nil, rail: nil, contract: nil,
                   payload: nil)
      @payout_id = normalize_id(payout_id, "payout id")
      @provider_id = normalize_id(provider_id, "provider id")
      @operation_id = normalize_id(operation_id, "operation id")
      @attempt_id = normalize_id(attempt_id, "attempt id")
      unless money.is_a?(RubyRouting::Money)
        raise ArgumentError, "money must be RubyRouting::Money"
      end
      unless contract.nil? || contract.is_a?(RubyRouting::ProviderOperationContract)
        raise ArgumentError, "contract must be ProviderOperationContract or nil"
      end

      @money = money
      @idempotency_key = "#{@payout_id}:#{@operation_id}".freeze
      @payload = if payload.nil?
        RubyRouting::ProviderOperationPayload.new(
          destination: destination,
          context: context,
          routing_context: routing_context,
          payment_method: payment_method,
          rail: rail,
          contract: contract
        )
      else
        unless destination == {} && context == {} && routing_context.nil? &&
               payment_method.nil? && rail.nil?
          raise ArgumentError, "payload cannot be combined with legacy operation fields"
        end
        unless payload.is_a?(RubyRouting::ProviderOperationPayload)
          raise ArgumentError, "payload must be ProviderOperationPayload"
        end
        if contract && payload.contract && payload.contract.to_h != contract.to_h
          raise ArgumentError, "contract does not match supplied payload"
        end
        if contract && payload.contract.nil?
          RubyRouting::ProviderOperationPayload.new(
            destination: payload.destination,
            context: payload.context,
            routing_context: payload.routing_context,
            payment_method: payload.payment_method,
            rail: payload.rail,
            contract: contract
          )
        else
          payload
        end
      end
      if @payload.contract &&
         (@payload.contract.provider_id != @provider_id ||
          @payload.contract.idempotency_key != @idempotency_key)
        raise ArgumentError, "operation contract does not match request identity"
      end
      freeze
    end

    def self.from_intent(intent:, provider_id:, operation_id:, attempt_id:, contract: nil)
      unless intent.is_a?(RubyRouting::PayoutIntent)
        raise ArgumentError, "intent must be RubyRouting::PayoutIntent"
      end

      new(
        payout_id: intent.id,
        provider_id: provider_id,
        operation_id: operation_id,
        attempt_id: attempt_id,
        money: intent.money,
        payload: RubyRouting::ProviderOperationPayload.from_intent(intent, contract: contract)
      )
    end

    def contract
      payload.contract
    end

    def destination
      payload.destination
    end

    def context
      payload.context
    end

    def routing_context
      payload.routing_context
    end

    def payment_method
      payload.payment_method
    end

    def rail
      payload.rail
    end

    def to_h
      {
        payout_id: payout_id,
        provider_id: provider_id,
        operation_id: operation_id,
        attempt_id: attempt_id,
        money: { amount_minor: money.amount_minor, currency: money.currency }.freeze,
        idempotency_key: idempotency_key,
        payload: payload.to_h
      }.freeze
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
