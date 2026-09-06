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
      ProviderInvocation = Data.define(:observation, :interaction_token)

      attr_reader :configuration_store

      def initialize(coordinator:, providers:, policy_registry: nil, configuration_store: nil)
        unless coordinator.is_a?(RubyRouting::State::Coordinator)
          raise ArgumentError, "coordinator must be State::Coordinator"
        end
        unless providers.is_a?(Hash)
          raise ArgumentError, "providers must be a Hash"
        end
        if policy_registry && !policy_registry.is_a?(RubyRouting::PolicyRegistry)
          raise ArgumentError, "policy_registry must be PolicyRegistry or nil"
        end
        if configuration_store && !configuration_store.is_a?(RubyRouting::Application::ConfigurationStore)
          raise ArgumentError, "configuration_store must be Application::ConfigurationStore or nil"
        end

        @coordinator = coordinator
        @configuration_store = configuration_store || RubyRouting::Application::ConfigurationStore.new(
          configuration: RubyRouting::Application::RoutingConfiguration.new(
            policies: policy_registry ? policy_registry.policies : [],
            provider_opportunities: coordinator.provider_opportunities
          )
        )
        @policy_registry = if policy_registry
          if configuration_store && !RubyRouting::PolicyRegistry.same_policy_set?(
            policy_registry.policies,
            @configuration_store.current.policies
          )
            raise ArgumentError, "policy_registry and configuration_store must share one active policy set"
          end
          # The supplied registry is the application-owned compatibility
          # source. Cloning it here makes the orchestrator view stale after a
          # coordinated command publishes a new active generation.
          policy_registry
        else
          RubyRouting::PolicyRegistry.new(@configuration_store.current.policies)
        end
        @policy_registry_view = @policy_registry.read_only(
          configuration_store: @configuration_store
        )
        @providers = providers.each_with_object({}) do |(id, provider), copy|
          normalized_id = RubyRouting::Identity.normalize(id, "provider id")
          raise ArgumentError, "provider ids must be unique after normalization" if copy.key?(normalized_id)
          unless executable_provider_method?(provider, :initiate) &&
                 executable_provider_method?(provider, :resolve)
            raise ArgumentError, "provider adapter must implement executable initiate and resolve"
          end

          copy[normalized_id] = provider
        end.freeze
        # Validate the complete adapter boundary before bootstrapping a
        # supplied provider generation into the shared Coordinator. A failed
        # application construction must not leave that Coordinator mutated.
        synchronize_provider_catalog!(coordinator, @configuration_store.current.provider_opportunities) if configuration_store
      end

      # Runtime adapter identity is intentionally separate from the immutable
      # ProviderOpportunity/configuration domain values. Application/operator
      # projections may use this to show whether a configured opportunity is
      # executable in the current process.
      def provider_adapter_ids
        @providers.keys.freeze
      end

      def policy_registry
        @policy_registry_view
      end

      def submit(intent:, policy: nil, scope: :default)
        resolved_policy = policy
        max_steps = nil
        steps = 0

        loop do
          steps += 1
          if max_steps && steps > max_steps
            payout = @coordinator.payout_snapshot(intent.id)
            return RouteResult.new(payout: payout, action: :defer)
          end

          commit, resolved_policy = prepare_decision(
            intent: intent,
            policy: resolved_policy,
            scope: scope
          )
          max_steps ||= resolved_policy.recovery.max_operations +
            resolved_policy.recovery.max_resolution_interactions + 2
          proposal = commit.proposal
          case proposal.action
          when :already_final, :terminate, :defer
            return RouteResult.new(payout: commit.payout, action: proposal.action)
          when :assign, :retry_same
            invocation = initiate(commit)
            next unless invocation
          when :resolve
            invocation = resolve(commit)
            next unless invocation
          else
            raise ArgumentError, "unsupported orchestrator action #{proposal.action.inspect}"
          end

          application = apply_provider_invocation(invocation)
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
        payout, resolved_policy, resumed_operation = @configuration_store.with_snapshot do |snapshot|
          current_payout = @coordinator.payout_snapshot(payout_id)
          current_policy = policy || @coordinator.policy_for(payout_id) ||
            resolve_policy_for(current_payout.intent, scope: scope, configuration: snapshot.configuration)
          [
            current_payout,
            current_policy,
            @coordinator.resume_operation(
              payout_id,
              provider_opportunities: snapshot.provider_opportunities,
              configuration_revision: snapshot.revision
            )
          ]
        end
        if resumed_operation
          unless @providers.key?(resumed_operation.proposal.provider_id)
            return RouteResult.new(payout: resumed_operation.payout, action: :defer)
          end

          invocation = if resumed_operation.proposal.resolution?
            resolve(resumed_operation)
          else
            initiate(resumed_operation)
          end
          return RouteResult.new(payout: resumed_operation.payout, action: :defer) unless invocation

          application = apply_provider_invocation(invocation)
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

      def prepare_decision(intent:, policy:, scope:)
        @configuration_store.with_snapshot do |snapshot|
          resolved_policy = policy || resolve_policy_for(
            intent,
            scope: scope,
            configuration: snapshot.configuration
          )
          unless resolved_policy.is_a?(RubyRouting::RoutingPolicy)
            raise ArgumentError, "policy must be provided or resolvable from policy_registry"
          end

          [
            @coordinator.prepare_and_commit_decision(
              intent: intent,
              policy: resolved_policy,
              available_provider_ids: @providers.keys,
              provider_opportunities: snapshot.provider_opportunities,
              configuration_revision: snapshot.revision
            ),
            resolved_policy
          ]
        end
      end

      def resolve_policy_for(intent, scope:, configuration: nil)
        return nil unless @policy_registry

        resolution = if configuration
          configuration.resolve_policy_for(intent, scope: scope)
        else
          @policy_registry.resolve_for_intent(intent, scope: scope)
        end
        return resolution.policy if resolution.matched?

        error_class = if resolution.ambiguous?
          RubyRouting::AmbiguousPolicyError
        else
          RubyRouting::NoMatchingPolicyError
        end
        message = if resolution.ambiguous?
          "ambiguous policy resolution for scope #{resolution.scope.inspect}"
        else
          "no policy matches payout route for scope #{resolution.scope.inspect}"
        end
        raise error_class.new(message, resolution: resolution)
      end

      def executable_provider_method?(provider, method_name)
        return false unless provider.respond_to?(method_name)

        provider.method(method_name).owner != RubyRouting::Ports::Provider
      rescue NameError
        false
      end

      def synchronize_provider_catalog!(coordinator, desired_opportunities)
        previous_opportunities = coordinator.provider_opportunities
        return if RubyRouting::Application::RoutingConfiguration.same_provider_opportunity_set?(
          previous_opportunities,
          desired_opportunities
        )

        begin
          coordinator.replace_provider_opportunities(desired_opportunities)
        rescue StandardError => error
          begin
            current_opportunities = coordinator.provider_opportunities
            unless RubyRouting::Application::RoutingConfiguration.same_provider_opportunity_set?(
              current_opportunities,
              previous_opportunities
            )
              coordinator.replace_provider_opportunities(previous_opportunities)
            end
          rescue StandardError => rollback_error
            raise RubyRouting::State::DurableCorruptionError,
              "active provider bootstrap rollback failed: #{rollback_error.message}"
          end
          raise error
        end
      end

      def initiate(commit)
        provider = @providers.fetch(commit.proposal.provider_id) do
          raise ArgumentError, "no adapter configured for #{commit.proposal.provider_id}"
        end
        interaction_token = @coordinator.mark_attempt_started(commit)
        return nil unless interaction_token
        invoke_provider_with_guard(
          provider,
          :initiate,
          commit,
          interaction_token,
          interaction: commit.proposal.action
        )
      end

      def resolve(commit)
        provider = @providers.fetch(commit.proposal.provider_id) do
          raise ArgumentError, "no adapter configured for #{commit.proposal.provider_id}"
        end
        interaction_token = @coordinator.mark_resolution_started(commit)
        return nil unless interaction_token
        invoke_provider_with_guard(
          provider,
          :resolve,
          commit,
          interaction_token,
          interaction: :resolve
        )
      end

      def invoke_provider_with_guard(provider, method_name, commit, interaction_token, interaction:)
        invocation_returned = false
        failure_classified = false
        invocation = ProviderInvocation.new(
          observation: invoke_provider(
            provider,
            method_name,
            commit,
            interaction: interaction,
            interaction_token: interaction_token
          ),
          interaction_token: interaction_token
        )
        invocation_returned = true
        invocation
      rescue RubyRouting::ProviderContractError
        failure_classified = true
        @coordinator.provider_interaction_ended(
          interaction_token: interaction_token,
          failure_provenance: :post_return
        )
        raise
      rescue RubyRouting::ProviderExecutionError
        failure_classified = true
        @coordinator.provider_interaction_failed(interaction_token: interaction_token)
        raise
      rescue StandardError => error
        failure_classified = true
        @coordinator.provider_interaction_ended(
          interaction_token: interaction_token,
          failure_provenance: :post_return
        )
        raise RubyRouting::ApplicationProcessingError.new(error)
      ensure
        # Fatal adapter/programming faults (for example ScriptError-derived
        # NotImplementedError) are intentionally not made resumable provider
        # failures, but they must not strand the process-local live guard.
        # StandardError/provider paths are already released by one of the
        # branches; this idempotent cleanup covers every other unwinding path
        # and records fatal live-process provenance without calling it a raw
        # provider execution failure.
        unless invocation_returned
          @coordinator.provider_interaction_ended(
            interaction_token: interaction_token,
            failure_provenance: failure_classified ? nil : :fatal
          )
        end
      end

      def apply_provider_invocation(invocation)
        observation_applied = false
        application = @coordinator.apply_observation(
          invocation.observation,
          interaction_token: invocation.interaction_token
        )
        observation_applied = true
        application
      ensure
        # Observation application may unwind with a fatal ScriptError-derived
        # exception too. Cleanup is unconditional and idempotent; it does not
        # catch or reclassify the fatal error.
        @coordinator.provider_interaction_ended(
          interaction_token: invocation.interaction_token,
          failure_provenance: observation_applied ? nil : :post_return
        )
      end

      def invoke_provider(provider, method_name, commit, interaction:, interaction_token:)
        started_monotonic_at = @coordinator.current_monotonic
        provider_result = begin
          provider.public_send(method_name, commit.request)
        rescue RubyRouting::ProviderTransportError => error
          observation_from_transport(
            commit.request,
            error,
            interaction: interaction,
            interaction_index: interaction_token.interaction_index
          )
        rescue RubyRouting::ProviderExecutionError
          raise
        rescue StandardError => error
          raise RubyRouting::ProviderExecutionError.new(error)
        end
        # The adapter has returned. Interpretation and linkage validation now
        # run under application authority. Contract violations are raised
        # explicitly by the validation code; application programming faults
        # must retain their own provenance rather than being blamed on the
        # provider by a broad rescue around this phase.
        observation = classify_transport(
          provider_result,
          commit.request,
          interaction: interaction,
          interaction_index: interaction_token.interaction_index
        )
        finished_monotonic_at = @coordinator.current_monotonic
        observation.with_interaction_duration(finished_monotonic_at - started_monotonic_at)
      end

      def classify_transport(result, request, interaction:, interaction_index:)
        return validate_observation!(result, request, interaction: interaction) if result.is_a?(RubyRouting::ProviderObservation)
        return observation_from_transport(
          request,
          result,
          interaction: interaction,
          interaction_index: interaction_index
        ) if result.is_a?(RubyRouting::ProviderTransportResult)

        raise provider_contract_violation(
          "provider adapter must return ProviderObservation or ProviderTransportResult"
        )
      end

      def validate_observation!(observation, request, interaction:)
        unless observation.is_a?(RubyRouting::ProviderObservation)
          raise provider_contract_violation("provider adapter must return ProviderObservation")
        end
        unless observation.payout_id == request.payout_id &&
               observation.provider_id == request.provider_id &&
               observation.operation_id == request.operation_id &&
               observation.attempt_id == request.attempt_id
          raise provider_contract_violation("provider observation linkage does not match request")
        end

        return observation unless interaction == :resolve &&
                                observation.transport_kind == :definitely_not_sent &&
                                observation.outcome.safe_to_release?

        # A directly returned observation has already crossed the adapter
        # boundary, but its transport classification still describes this
        # interaction. A definitely-not-sent status lookup does not prove that
        # the original payout initiate was not sent, so normalize a releasable
        # direct observation to conservative UNKNOWN just like the typed
        # transport-result path below.
        RubyRouting::ProviderObservation.new(
          observation_id: observation.observation_id,
          payout_id: observation.payout_id,
          provider_id: observation.provider_id,
          operation_id: observation.operation_id,
          attempt_id: observation.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.unknown(
            attribution: :unknown,
            provider_reference: observation.outcome.provider_reference,
            message: observation.outcome.message ||
              "status lookup was definitely not sent; original payout remains unresolved"
          ),
          provider_reference: observation.provider_reference,
          sequence: observation.sequence,
          observed_at: observation.observed_at,
          transport_kind: observation.transport_kind,
          interaction_duration_seconds: observation.interaction_duration_seconds
        )
      end

      def observation_from_transport(request, transport, interaction:, interaction_index:)
        kind = transport.kind
        # A transport classification describes this exchange, not necessarily
        # the economic operation represented by the request. A definitely-not-
        # sent initiate/retry proves that the money-moving exchange was not
        # sent. The same classification on a status lookup proves only that
        # the lookup was not sent; the original payout operation remains
        # unresolved and must retain ownership.
        original_operation_not_sent = kind == :definitely_not_sent && interaction != :resolve
        status = original_operation_not_sent ? :safe_route_failure : :unknown
        outcome = RubyRouting::NormalizedOutcome.new(
          status: status,
          attribution: original_operation_not_sent ? :provider : :unknown,
          provider_reference: transport.provider_reference,
          message: transport.message || "transport classified as #{kind}",
          safe_to_release: original_operation_not_sent
        )
        RubyRouting::ProviderObservation.new(
          observation_id: "transport:#{request.operation_id}:#{interaction}:#{interaction_index}:#{kind}",
          payout_id: request.payout_id,
          provider_id: request.provider_id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: outcome,
          provider_reference: transport.provider_reference,
          transport_kind: kind
        )
      end

      def provider_contract_violation(message)
        RubyRouting::ProviderContractError.new(ArgumentError.new(message))
      end
    end
  end
end
