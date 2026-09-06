# frozen_string_literal: true

module TestSupport
  module Simulator
    class Step
      attr_reader :outcome, :accepted

      def initialize(outcome:, accepted: true)
        unless outcome.is_a?(RubyRouting::NormalizedOutcome)
          raise ArgumentError, "step outcome must be NormalizedOutcome"
        end

        @outcome = outcome
        @accepted = !!accepted
        freeze
      end

      def self.success(attribution: :provider)
        new(outcome: RubyRouting::NormalizedOutcome.success(attribution: attribution))
      end

      def self.pending(attribution: :provider)
        new(outcome: RubyRouting::NormalizedOutcome.pending(attribution: attribution))
      end

      def self.unknown(attribution: :unknown)
        new(outcome: RubyRouting::NormalizedOutcome.unknown(attribution: attribution))
      end

      def self.safe_failure(attribution: :provider)
        new(outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: attribution))
      end

      def self.temporary_failure(attribution: :provider, safe_to_release: true)
        new(
          outcome: RubyRouting::NormalizedOutcome.temporary_provider_failure(
            attribution: attribution,
            safe_to_release: safe_to_release
          )
        )
      end

      def self.terminal(attribution: :recipient)
        new(outcome: RubyRouting::NormalizedOutcome.terminal_payout_failure(attribution: attribution))
      end
    end

    class ScriptedProvider
      include RubyRouting::Ports::Provider

      attr_reader :provider_id, :capabilities

      def initialize(provider_id:, steps:, clock: TestSupport::ControlledClock.new,
                     capabilities: RubyRouting::ProviderCapabilities.new)
        @provider_id = provider_id.to_s.freeze
        @steps = steps.dup
        unless @steps.all? { |step| step.is_a?(Step) }
          raise ArgumentError, "steps must contain Simulator::Step values"
        end
        @clock = clock
        @capabilities = capabilities
        @operations = {}
        @calls = []
        @observation_sequence = 0
      end

      def calls
        @calls.dup.freeze
      end

      def initiate(request)
        validate_request!(request)
        @calls << [:initiate, request.idempotency_key].freeze
        existing = @operations[request.idempotency_key]
        if existing
          return observation_for(request, existing[:outcome], existing[:reference], "replay")
        end

        step = take_step
        reference = "#{provider_id}:operation:#{@operations.length + 1}".freeze
        @operations[request.idempotency_key] = { reference: reference, outcome: step.outcome }
        observation_for(request, step.outcome, reference, "initiate")
      end

      def resolve(request)
        validate_request!(request)
        @calls << [:resolve, request.idempotency_key].freeze
        operation = @operations.fetch(request.idempotency_key) do
          raise ArgumentError, "cannot resolve an unknown provider operation"
        end
        step = take_step
        operation[:outcome] = step.outcome
        observation_for(request, step.outcome, operation[:reference], "resolve")
      end

      def duplicate(observation)
        observation
      end

      private

      def take_step
        @steps.shift || raise(ArgumentError, "scripted provider has no response step left")
      end

      def validate_request!(request)
        unless request.is_a?(RubyRouting::ProviderOperationRequest)
          raise ArgumentError, "request must be ProviderOperationRequest"
        end
        unless request.provider_id == provider_id
          raise ArgumentError, "request provider does not match adapter"
        end
      end

      def observation_for(request, outcome, reference, source)
        @observation_sequence += 1
        RubyRouting::ProviderObservation.new(
          observation_id: "#{provider_id}:observation:#{@observation_sequence}:#{source}",
          payout_id: request.payout_id,
          provider_id: provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: outcome,
          provider_reference: reference,
          sequence: @observation_sequence,
          observed_at: @clock.now
        )
      end
    end
  end
end
