# frozen_string_literal: true

module RubyRouting
  module Application
    class RouteResult
      attr_reader :payout, :action

      def initialize(payout:, action:)
        @payout = payout
        @action = action.is_a?(Symbol) ? action : action.to_s.freeze
        freeze
      end

      def status
        payout.status
      end
    end

    class Orchestrator
      attr_reader :policy_registry

      def initialize(coordinator:, providers:, policy_registry: nil)
        unless coordinator.is_a?(RubyRouting::State::Coordinator)
          raise ArgumentError, "coordinator must be State::Coordinator"
        end
        unless providers.is_a?(Hash)
          raise ArgumentError, "providers must be a Hash"
        end
        if policy_registry && !policy_registry.is_a?(RubyRouting::PolicyRegistry)
          raise ArgumentError, "policy_registry must be PolicyRegistry or nil"
        end

        @coordinator = coordinator
        @policy_registry = policy_registry
        @providers = providers.each_with_object({}) do |(id, provider), copy|
          normalized_id = id.to_s.strip
          raise ArgumentError, "provider id must be non-empty" if normalized_id.empty?
          raise ArgumentError, "provider ids must be unique after normalization" if copy.key?(normalized_id)
          unless executable_provider_method?(provider, :initiate) &&
                 executable_provider_method?(provider, :resolve)
            raise ArgumentError, "provider adapter must implement executable initiate and resolve"
          end

          copy[normalized_id] = provider
        end.freeze
      end

      def submit(intent:, policy: nil, scope: :default)
        resolved_policy = policy || @policy_registry&.find_for_intent(intent, scope: scope)
        unless resolved_policy.is_a?(RubyRouting::RoutingPolicy)
          raise ArgumentError, "policy must be provided or resolvable from policy_registry"
        end

        # Each money-moving operation and each resolution/retry interaction can
        # consume one loop turn. Keep the guard derived from both independent
        # budgets so a deliberately larger resolution budget cannot be cut off
        # by the operation budget.
        max_steps = resolved_policy.recovery.max_operations +
          resolved_policy.recovery.max_resolution_interactions + 2
        steps = 0

        loop do
          steps += 1
          if steps > max_steps
            payout = @coordinator.payout_snapshot(intent.id)
            return RouteResult.new(payout: payout, action: :defer)
          end

          commit = @coordinator.prepare_and_commit_decision(
            intent: intent,
            policy: resolved_policy,
            available_provider_ids: @providers.keys
          )
          proposal = commit.proposal
          case proposal.action
          when :already_final, :terminate, :defer
            return RouteResult.new(payout: commit.payout, action: proposal.action)
          when :assign, :retry_same
            observation = initiate(commit)
            next unless observation
          when :resolve
            observation = resolve(commit, intent)
            next unless observation
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

      def record_reversal(**attributes)
        @coordinator.record_reversal(**attributes)
      end

      def resume(payout_id:, policy: nil, scope: :default)
        payout = @coordinator.payout_snapshot(payout_id)
        resolved_policy = policy || @policy_registry&.find_for_intent(payout.intent, scope: scope) ||
          @coordinator.policy_for(payout_id)
        if (resumed_operation = @coordinator.resume_operation(payout_id))
          unless @providers.key?(resumed_operation.proposal.provider_id)
            return RouteResult.new(payout: resumed_operation.payout, action: :defer)
          end

          observation = if resumed_operation.proposal.resolution?
            resolve(resumed_operation, payout.intent)
          else
            initiate(resumed_operation)
          end
          return RouteResult.new(payout: resumed_operation.payout, action: :defer) unless observation

          application = @coordinator.apply_observation(observation)
          return RouteResult.new(payout: application.payout, action: application.next_action) unless application.next_action == :reroute

          return submit(intent: payout.intent, policy: resolved_policy, scope: scope)
        end

        payout = @coordinator.payout_snapshot(payout_id)
        if payout.ownership && !@providers.key?(payout.ownership.provider_id)
          return RouteResult.new(payout: payout, action: :defer)
        end

        submit(intent: payout.intent, policy: resolved_policy, scope: scope)
      end

      alias advance resume

      def reconcile(observation:)
        @coordinator.apply_observation(observation)
      end

      private

      def executable_provider_method?(provider, method_name)
        return false unless provider.respond_to?(method_name)

        provider.method(method_name).owner != RubyRouting::Ports::Provider
      rescue NameError
        false
      end

      def initiate(commit)
        provider = @providers.fetch(commit.proposal.provider_id) do
          raise ArgumentError, "no adapter configured for #{commit.proposal.provider_id}"
        end
        return nil unless @coordinator.mark_attempt_started(commit)
        begin
          classify_transport(provider.initiate(commit.request), commit.request)
        rescue RubyRouting::ProviderTransportError => error
          observation_from_transport(commit.request, error)
        end
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
        return nil unless @coordinator.mark_resolution_started(commit)
        begin
          classify_transport(provider.resolve(request), request)
        rescue RubyRouting::ProviderTransportError => error
          observation_from_transport(request, error)
        end
      end

      def classify_transport(result, request)
        return validate_observation!(result, request) if result.is_a?(RubyRouting::ProviderObservation)
        return observation_from_transport(request, result) if result.is_a?(RubyRouting::ProviderTransportResult)

        raise ArgumentError, "provider adapter must return ProviderObservation or ProviderTransportResult"
      end

      def validate_observation!(observation, request)
        unless observation.is_a?(RubyRouting::ProviderObservation)
          raise ArgumentError, "provider adapter must return ProviderObservation"
        end
        unless observation.payout_id == request.payout_id &&
               observation.provider_id == request.provider_id &&
               observation.operation_id == request.operation_id &&
               observation.attempt_id == request.attempt_id
          raise ArgumentError, "provider observation linkage does not match request"
        end

        observation
      end

      def observation_from_transport(request, transport)
        kind = transport.kind
        status = kind == :definitely_not_sent ? :safe_route_failure : :unknown
        outcome = RubyRouting::NormalizedOutcome.new(
          status: status,
          attribution: kind == :definitely_not_sent ? :provider : :unknown,
          provider_reference: transport.provider_reference,
          message: transport.message || "transport classified as #{kind}",
          safe_to_release: kind == :definitely_not_sent
        )
        RubyRouting::ProviderObservation.new(
          observation_id: "transport:#{request.operation_id}:#{kind}",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: outcome,
          provider_reference: transport.provider_reference,
          transport_kind: kind
        )
      end
    end
  end
end
