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
      @safe_to_release = safe_to_release.nil? ? default_safe_to_release? : normalize_boolean(safe_to_release, "safe_to_release")
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
      RubyRouting::Enum.normalize(value, allowed, label)
    end

    def normalize_boolean(value, label)
      return value if value == true || value == false

      raise ArgumentError, "#{label} must be boolean"
    end
  end

  class ProviderObservation
    DEFINITELY_NOT_SENT_STATUSES = %i[
      safe_route_failure
      temporary_provider_failure
      terminal_payout_failure
    ].freeze

    attr_reader :observation_id, :payout_id, :provider_id, :operation_id, :attempt_id,
                :outcome, :provider_reference, :sequence, :observed_at,
                :transport_kind, :interaction_duration_seconds

    def initialize(observation_id:, payout_id:, provider_id:, operation_id:, attempt_id:,
                   outcome:, provider_reference: nil, sequence: nil, observed_at: nil,
                   transport_kind: nil, interaction_duration_seconds: nil)
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
      unless observed_at.nil? || observed_at.is_a?(Time)
        raise ArgumentError, "observed_at must be a Time or nil"
      end

      @outcome = outcome
      @provider_reference = provider_reference&.to_s&.freeze
      @sequence = sequence
      @observed_at = observed_at&.utc&.freeze
      @transport_kind = normalize_transport_kind(transport_kind)
      @interaction_duration_seconds = normalize_exact_duration(interaction_duration_seconds)
      validate_transport_outcome!
      freeze
    end

    def with_interaction_duration(duration_seconds)
      normalized_duration = normalize_exact_duration(duration_seconds)
      return self if normalized_duration == interaction_duration_seconds

      self.class.new(
        observation_id: observation_id,
        payout_id: payout_id,
        provider_id: provider_id,
        operation_id: operation_id,
        attempt_id: attempt_id,
        outcome: outcome,
        provider_reference: provider_reference,
        sequence: sequence,
        observed_at: observed_at,
        transport_kind: transport_kind,
        interaction_duration_seconds: normalized_duration
      )
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

    def validate_transport_outcome!
      return unless transport_kind

      valid = case transport_kind
      when :definitely_not_sent
        DEFINITELY_NOT_SENT_STATUSES.include?(outcome.status) && outcome.safe_to_release?
      when :ambiguous_after_possible_send
        %i[pending unknown].include?(outcome.status) && !outcome.safe_to_release?
      else
        false
      end
      return if valid

      raise ArgumentError, "transport kind is inconsistent with normalized outcome"
    end

    def normalize_transport_kind(value)
      return nil if value.nil?

      RubyRouting::Enum.normalize(value, RubyRouting::ProviderTransportResult::KINDS, "transport kind")
    end

    def normalize_exact_duration(value)
      return nil if value.nil?
      unless value.is_a?(Integer) || value.is_a?(Rational)
        raise ArgumentError, "interaction duration must be an exact non-negative Integer or Rational"
      end
      raise ArgumentError, "interaction duration must be non-negative" if value.negative?

      value
    end
  end

  class EconomicConflict
    attr_reader :payout_id, :provider_id, :operation_id, :attempt_id, :reason

    def initialize(payout_id:, provider_id:, operation_id:, attempt_id:, reason:)
      @payout_id = normalize_id(payout_id, "payout id")
      @provider_id = normalize_id(provider_id, "provider id")
      @operation_id = normalize_id(operation_id, "operation id")
      @attempt_id = normalize_id(attempt_id, "attempt id")
      @reason = reason.is_a?(Symbol) ? reason : reason.to_s.freeze
      freeze
    end

    private

    def normalize_id(value, label)
      RubyRouting::Identity.normalize(value, label)
    end
  end
end
