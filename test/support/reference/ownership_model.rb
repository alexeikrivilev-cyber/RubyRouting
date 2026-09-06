# frozen_string_literal: true

module Reference
  class OwnershipModel
    attr_reader :status, :owner, :attempt_count

    def initialize
      @status = :new
      @owner = nil
      @attempt_count = 0
    end

    def assign(provider_id)
      raise ArgumentError, "model cannot assign while an owner exists" if owner
      raise ArgumentError, "model cannot assign after a final state" if %i[success terminal_payout_failure].include?(status)

      @owner = provider_id.to_s
      @attempt_count += 1
      @status = :pending
    end

    def observe(status, safe_to_release: nil, owning_completion: false)
      normalized = status.to_sym
      case normalized
      when :pending
        @status = :pending if owner && @status != :unknown
      when :unknown
        @status = :unknown if owner
      when :safe_route_failure, :temporary_provider_failure
        if owner && owning_completion && (safe_to_release.nil? || safe_to_release)
          @owner = nil
          @status = normalized
        end
      when :terminal_payout_failure
        if owner
          @owner = nil
          @status = normalized
        end
      when :success
        if owner
          @owner = nil
          @status = :success
        end
      else
        raise ArgumentError, "unknown model status"
      end
      self
    end
  end
end
