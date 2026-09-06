# frozen_string_literal: true

module RubyRouting
  module Application
    class RouteResult
      attr_reader :payout, :action

      def initialize(payout:, action:)
        @payout = payout
        @action = action.to_sym
        freeze
      end

      def status
        payout.status
      end
    end

    class Orchestrator
      def initialize(coordinator:, providers:)
        unless coordinator.is_a?(RubyRouting::State::Coordinator)
          raise ArgumentError, "coordinator must be State::Coordinator"
        end
        unless providers.is_a?(Hash)
          raise ArgumentError, "providers must be a Hash"
        end

        @coordinator = coordinator
        @providers = providers.each_with_object({}) { |(id, provider), copy| copy[id.to_s] = provider }.freeze
      end

      def submit(intent:, policy:)
        @coordinator.register_intent(intent)
        max_steps = (policy.max_attempts * 2) + 2
        steps = 0

        loop do
          steps += 1
          if steps > max_steps
            payout = @coordinator.payout_snapshot(intent.id)
            return RouteResult.new(payout: payout, action: :defer)
          end

          commit = @coordinator.prepare_and_commit_decision(intent: intent, policy: policy)
          proposal = commit.proposal
          case proposal.action
          when :already_final, :terminate, :defer
            return RouteResult.new(payout: commit.payout, action: proposal.action)
          when :assign, :retry_same
            observation = initiate(commit)
          when :resolve
            observation = resolve(commit, intent)
          else
            raise ArgumentError, "unsupported orchestrator action #{proposal.action.inspect}"
          end

          application = @coordinator.apply_observation(observation)
          case application.next_action
          when :reroute
            next
          when :stop, :wait, :defer
            return RouteResult.new(payout: application.payout, action: application.next_action)
          else
            raise ArgumentError, "unsupported next action #{application.next_action.inspect}"
          end
        end
      end

      private

      def initiate(commit)
        provider = @providers.fetch(commit.proposal.provider_id) do
          raise ArgumentError, "no adapter configured for #{commit.proposal.provider_id}"
        end
        @coordinator.mark_attempt_started(commit)
        observation = provider.initiate(commit.request)
        validate_observation!(observation)
      end

      def resolve(commit, intent)
        provider = @providers.fetch(commit.proposal.provider_id) do
          raise ArgumentError, "no adapter configured for #{commit.proposal.provider_id}"
        end
        request = RubyRouting::ProviderOperationRequest.new(
          payout_id: intent.id,
          provider_id: commit.proposal.provider_id,
          operation_id: commit.proposal.operation_id,
          attempt_id: commit.proposal.attempt_id,
          money: intent.money
        )
        observation = provider.resolve(request)
        validate_observation!(observation)
      end

      def validate_observation!(observation)
        unless observation.is_a?(RubyRouting::ProviderObservation)
          raise ArgumentError, "provider adapter must return ProviderObservation"
        end

        observation
      end
    end
  end
end
