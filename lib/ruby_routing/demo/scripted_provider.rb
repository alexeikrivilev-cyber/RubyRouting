# frozen_string_literal: true

module RubyRouting
  module Demo
    # A deterministic in-process provider for demonstrations and examples. It
    # is intentionally named simulated: it is not a real PSP integration.
    class ScriptedProvider
      include RubyRouting::Ports::Provider

      attr_reader :provider_id, :calls

      def initialize(provider_id:, outcomes:, capabilities: RubyRouting::ProviderCapabilities.new, clock: nil)
        @provider_id = provider_id.to_s.strip.freeze
        raise ArgumentError, "provider id must be non-empty" if @provider_id.empty?
        normalized_outcomes = RubyRouting::Collection.to_array(outcomes, "demo outcomes")
        unless normalized_outcomes.all? { |outcome| outcome.is_a?(RubyRouting::NormalizedOutcome) }
          raise ArgumentError, "demo outcomes must contain NormalizedOutcome values"
        end
        unless capabilities.is_a?(RubyRouting::ProviderCapabilities)
          raise ArgumentError, "capabilities must be ProviderCapabilities"
        end

        @outcomes = normalized_outcomes.dup
        @capabilities = capabilities
        @clock = clock
        @operations = {}
        @calls = []
        @sequence = 0
      end

      def initiate(request)
        validate_request!(request)
        @calls << [:initiate, request.idempotency_key].freeze
        operation = @operations[request.idempotency_key]
        unless operation
          operation = { outcome: next_outcome }
          @operations[request.idempotency_key] = operation
        end
        observation_for(request, operation.fetch(:outcome), "initiate")
      end

      def resolve(request)
        validate_request!(request)
        @calls << [:resolve, request.idempotency_key].freeze
        operation = @operations.fetch(request.idempotency_key) do
          raise ArgumentError, "demo cannot resolve an unknown operation"
        end
        operation[:outcome] = next_outcome
        observation_for(request, operation.fetch(:outcome), "resolve")
      end

      private

      def next_outcome
        @outcomes.shift || RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
      end

      def validate_request!(request)
        unless request.is_a?(RubyRouting::ProviderOperationRequest)
          raise ArgumentError, "request must be ProviderOperationRequest"
        end
        raise ArgumentError, "request provider does not match demo provider" unless request.provider_id == provider_id
      end

      def observation_for(request, outcome, source)
        @sequence += 1
        RubyRouting::ProviderObservation.new(
          observation_id: "demo:#{provider_id}:#{@sequence}:#{source}",
          payout_id: request.payout_id,
          provider_id: provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: outcome,
          sequence: @sequence,
          observed_at: @clock.respond_to?(:now) ? @clock.now : nil
        )
      end
    end
  end
end
