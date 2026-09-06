# frozen_string_literal: true

module RubyRouting
  class ProviderCapabilities
    attr_reader :idempotent_retry, :status_lookup

    def initialize(idempotent_retry: false, status_lookup: false)
      @idempotent_retry = !!idempotent_retry
      @status_lookup = !!status_lookup
      freeze
    end

    def can_resolve?
      status_lookup || idempotent_retry
    end
  end

  class ProviderOpportunity
    attr_reader :provider_id, :functional_eligible, :available, :capacity_available,
                :capabilities, :exclusion_reason

    def initialize(provider_id:, functional_eligible: true, available: true,
                   capacity_available: true, capabilities: ProviderCapabilities.new,
                   exclusion_reason: nil)
      @provider_id = normalize_id(provider_id)
      @functional_eligible = !!functional_eligible
      @available = !!available
      @capacity_available = !!capacity_available
      unless capabilities.is_a?(ProviderCapabilities)
        raise ArgumentError, "capabilities must be ProviderCapabilities"
      end

      @capabilities = capabilities
      @exclusion_reason = exclusion_reason&.to_s&.freeze
      freeze
    end

    def feasible?
      functional_eligible && available && capacity_available
    end

    def reason
      return exclusion_reason if exclusion_reason
      return :functionally_ineligible unless functional_eligible
      return :unavailable unless available
      return :capacity_exhausted unless capacity_available

      nil
    end

    private

    def normalize_id(value)
      unless value.is_a?(String) || value.is_a?(Symbol)
        raise ArgumentError, "provider id must be a non-empty String or Symbol"
      end

      normalized = value.to_s.strip
      raise ArgumentError, "provider id must be non-empty" if normalized.empty?

      normalized.freeze
    end
  end
end
