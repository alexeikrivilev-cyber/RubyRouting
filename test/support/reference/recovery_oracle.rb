# frozen_string_literal: true

module Reference
  module RecoveryOracle
    module_function

    def choose(status:, owner_present:, resolution_capable:, attempts:, max_attempts:)
      return :terminate if status == :success || status == :terminal_payout_failure
      if owner_present
        return :resolve if resolution_capable

        return :defer
      end
      return :defer if attempts >= max_attempts
      return :fallback if %i[safe_route_failure temporary_provider_failure].include?(status)

      :fallback
    end
  end
end
