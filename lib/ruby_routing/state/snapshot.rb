# frozen_string_literal: true

module RubyRouting
  module State
    class AttemptSnapshot
      attr_reader :attempt_id, :operation_id, :provider_id, :role, :outcome, :measure

      def initialize(attempt_id:, operation_id:, provider_id:, role:, outcome: nil, measure: nil)
        @attempt_id = attempt_id.to_s.freeze
        @operation_id = operation_id.to_s.freeze
        @provider_id = provider_id.to_s.freeze
        @role = role.to_sym
        @outcome = outcome
        @measure = measure
        freeze
      end
    end

    class PayoutSnapshot
      STATUSES = %i[
        new
        pending
        unknown
        safe_route_failure
        temporary_provider_failure
        terminal_payout_failure
        success
        deferred
      ].freeze

      attr_reader :intent, :status, :ownership, :last_outcome, :attempts,
                  :primary_provider_id, :settlement_provider_id, :policy_epoch,
                  :provider_interaction_count, :revision

      def initialize(intent:, status:, ownership:, last_outcome:, attempts:,
                     primary_provider_id:, settlement_provider_id:, policy_epoch:,
                     provider_interaction_count: 0, revision:)
        @intent = intent
        @status = status.to_sym
        raise ArgumentError, "unsupported payout state" unless STATUSES.include?(@status)

        @ownership = ownership
        @last_outcome = last_outcome
        @attempts = attempts.dup.freeze
        @primary_provider_id = primary_provider_id&.to_s&.freeze
        @settlement_provider_id = settlement_provider_id&.to_s&.freeze
        @policy_epoch = policy_epoch&.to_s&.freeze
        @provider_interaction_count = provider_interaction_count
        @revision = revision
        freeze
      end

      def id
        intent.id
      end

      def attempt_count
        attempts.length
      end

      def unresolved?
        !ownership.nil?
      end

      def final?
        %i[success terminal_payout_failure].include?(status)
      end
    end

    class DecisionCommit
      attr_reader :proposal, :request, :payout

      def initialize(proposal:, request:, payout:)
        @proposal = proposal
        @request = request
        @payout = payout
        freeze
      end
    end

    class ObservationApplication
      attr_reader :payout, :next_action, :duplicate

      def initialize(payout:, next_action:, duplicate: false)
        @payout = payout
        @next_action = next_action.to_sym
        @duplicate = !!duplicate
        freeze
      end
    end
  end
end
