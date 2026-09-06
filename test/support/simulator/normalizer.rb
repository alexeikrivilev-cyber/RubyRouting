# frozen_string_literal: true

module TestSupport
  module Simulator
    module Normalizer
      module_function

      def normalize(raw_status:, attribution: :unknown, message: nil)
        status = raw_status.to_s.downcase
        normalized_status = {
          "success" => :success,
          "pending" => :pending,
          "accepted" => :pending,
          "unknown" => :unknown,
          "timeout" => :unknown,
          "route_failed" => :safe_route_failure,
          "provider_unavailable" => :temporary_provider_failure,
          "recipient_invalid" => :terminal_payout_failure
        }.fetch(status, :unknown)
        normalized_attribution = normalized_status == :unknown ? :unknown : attribution

        RubyRouting::NormalizedOutcome.new(
          status: normalized_status,
          attribution: normalized_attribution,
          message: message
        )
      end
    end
  end
end
