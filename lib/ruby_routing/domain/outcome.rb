# frozen_string_literal: true

module RubyRouting
  class NormalizedOutcome
    STATUSES = %i[
      success
      pending
      unknown
      safe_route_failure
      temporary_provider_failure
      terminal_payout_failure
    ].freeze
    ATTRIBUTIONS = %i[provider recipient downstream policy unknown].freeze

    attr_reader :status, :attribution, :provider_reference, :message

    def initialize(status:, attribution: :unknown, provider_reference: nil, message: nil,
                   safe_to_release: nil)
      @status = normalize(status, STATUSES, "outcome status")
      @attribution = normalize(attribution, ATTRIBUTIONS, "outcome attribution")
      @provider_reference = provider_reference&.to_s&.freeze
      @message = message&.to_s&.freeze
      @safe_to_release = safe_to_release.nil? ? default_safe_to_release? : !!safe_to_release
      freeze
    end

    def self.success(**attributes)
      new(status: :success, **attributes)
    end

    def self.pending(**attributes)
      new(status: :pending, **attributes)
    end

    def self.unknown(**attributes)
      new(status: :unknown, **attributes)
    end

    def self.safe_route_failure(**attributes)
      new(status: :safe_route_failure, safe_to_release: true, **attributes)
    end

    def self.temporary_provider_failure(**attributes)
      new(status: :temporary_provider_failure, **attributes)
    end

    def self.terminal_payout_failure(**attributes)
      new(status: :terminal_payout_failure, safe_to_release: true, **attributes)
    end

    def unresolved?
      %i[pending unknown].include?(status)
    end

    def success?
      status == :success
    end

    def terminal_payout_failure?
      status == :terminal_payout_failure
    end

    def safe_to_release?
      @safe_to_release
    end

    def provider_failure?
      %i[safe_route_failure temporary_provider_failure].include?(status) &&
        attribution == :provider
    end

    private

    def default_safe_to_release?
      %i[safe_route_failure terminal_payout_failure].include?(status)
    end

    def normalize(value, allowed, label)
      normalized = value.to_sym
      raise ArgumentError, "unsupported #{label}" unless allowed.include?(normalized)

      normalized
    rescue NoMethodError
      raise ArgumentError, "unsupported #{label}"
    end
  end

  class ProviderObservation
    attr_reader :observation_id, :payout_id, :provider_id, :operation_id, :attempt_id,
                :outcome, :provider_reference, :sequence, :observed_at,
                :transport_kind

    def initialize(observation_id:, payout_id:, provider_id:, operation_id:, attempt_id:,
                   outcome:, provider_reference: nil, sequence: nil, observed_at: nil,
                   transport_kind: nil)
      @observation_id = normalize_id(observation_id, "observation id")
      @payout_id = normalize_id(payout_id, "payout id")
      @provider_id = normalize_id(provider_id, "provider id")
      @operation_id = normalize_id(operation_id, "operation id")
      @attempt_id = normalize_id(attempt_id, "attempt id")
      unless outcome.is_a?(NormalizedOutcome)
        raise ArgumentError, "outcome must be NormalizedOutcome"
      end
      unless sequence.nil? || (sequence.is_a?(Integer) && sequence >= 0)
        raise ArgumentError, "sequence must be a non-negative Integer"
      end

      @outcome = outcome
      @provider_reference = provider_reference&.to_s&.freeze
      @sequence = sequence
      @observed_at = observed_at&.freeze
      if transport_kind && !RubyRouting::ProviderTransportResult::KINDS.include?(transport_kind.to_sym)
        raise ArgumentError, "unsupported transport kind"
      end
      @transport_kind = transport_kind&.to_sym
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

  class EconomicConflict
    attr_reader :payout_id, :provider_id, :operation_id, :attempt_id, :reason

    def initialize(payout_id:, provider_id:, operation_id:, attempt_id:, reason:)
      @payout_id = normalize_id(payout_id, "payout id")
      @provider_id = normalize_id(provider_id, "provider id")
      @operation_id = normalize_id(operation_id, "operation id")
      @attempt_id = normalize_id(attempt_id, "attempt id")
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
end
