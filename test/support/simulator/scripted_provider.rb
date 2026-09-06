# frozen_string_literal: true

module TestSupport
  module Simulator
    class Step
      attr_reader :outcome, :accepted, :callback_outcomes

      def initialize(outcome:, accepted: true, callback_outcomes: [])
        unless outcome.is_a?(RubyRouting::NormalizedOutcome)
          raise ArgumentError, "step outcome must be NormalizedOutcome"
        end
        unless callback_outcomes.respond_to?(:to_a) &&
               callback_outcomes.to_a.all? { |callback| callback.is_a?(RubyRouting::NormalizedOutcome) }
          raise ArgumentError, "callback_outcomes must contain NormalizedOutcome values"
        end

        @outcome = outcome
        @accepted = !!accepted
        @callback_outcomes = callback_outcomes.to_a.dup.freeze
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

      def self.delayed(initial: RubyRouting::NormalizedOutcome.pending(attribution: :provider), callbacks:)
        new(outcome: initial, callback_outcomes: callbacks)
      end

      def self.delayed_success(attribution: :provider)
        delayed(
          callbacks: [RubyRouting::NormalizedOutcome.success(attribution: attribution)]
        )
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
        @callbacks = []
        @observation_sequence = 0
      end

      def calls
        @calls.dup.freeze
      end

      def pending_callbacks
        @callbacks.dup.freeze
      end

      def drain_callbacks(order: :fifo)
        callbacks = case order.to_sym
        when :fifo
          @callbacks
        when :lifo
          @callbacks.reverse
        else
          raise ArgumentError, "unsupported callback order #{order.inspect}"
        end
        @callbacks = []
        callbacks.freeze
      end

      def duplicate(observation)
        unless observation.is_a?(RubyRouting::ProviderObservation)
          raise ArgumentError, "observation must be ProviderObservation"
        end

        @calls << [:duplicate, observation.observation_id].freeze
        observation
      end

      def reversal_for(payout:, amount:, reason: :returned, reversal_id: nil)
        unless payout.is_a?(RubyRouting::State::PayoutSnapshot)
          raise ArgumentError, "payout must be State::PayoutSnapshot"
        end
        operation_id = payout.settlement_operation_id
        raise ArgumentError, "payout has no settlement operation" unless operation_id
        unless payout.settlement_provider_id == provider_id
          raise ArgumentError, "payout was not settled by this simulator provider"
        end

        RubyRouting::SettlementReversal.new(
          reversal_id: reversal_id || "#{provider_id}:reversal:#{payout.id}:#{payout.reversals.length + 1}",
          payout_id: payout.id,
          provider_id: provider_id,
          operation_id: operation_id,
          amount: amount,
          reason: reason
        )
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
        observation = observation_for(request, step.outcome, reference, "initiate")
        schedule_callbacks(request, reference, step.callback_outcomes)
        observation
      end

      def resolve(request)
        validate_request!(request)
        @calls << [:resolve, request.idempotency_key].freeze
        operation = @operations.fetch(request.idempotency_key) do
          raise ArgumentError, "cannot resolve an unknown provider operation"
        end
        step = take_step
        operation[:outcome] = step.outcome
        observation = observation_for(request, step.outcome, operation[:reference], "resolve")
        schedule_callbacks(request, operation[:reference], step.callback_outcomes)
        observation
      end

      private

      def take_step
        @steps.shift || raise(ArgumentError, "scripted provider has no response step left")
      end

      def schedule_callbacks(request, reference, outcomes)
        outcomes.each_with_index do |outcome, index|
          @callbacks << observation_for(request, outcome, reference, "callback-#{index + 1}")
        end
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
