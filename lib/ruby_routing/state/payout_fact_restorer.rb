# frozen_string_literal: true

module RubyRouting
  module State
    # Replays payout registration and policy-binding facts. The coordinator
    # supplies the payout/policy stores and domain factories so this seam does
    # not become a second owner of the working-state transaction.
    class PayoutFactRestorer
      def initialize(payouts:, policies:, payout_state_factory:, payout_state:,
                     same_intent:, policy_from_definition:, policy_identity:,
                     monotonic_value:, monotonic_reference:)
        @payouts = payouts
        @policies = policies
        @payout_state_factory = payout_state_factory
        @payout_state = payout_state
        @same_intent = same_intent
        @policy_from_definition = policy_from_definition
        @policy_identity = policy_identity
        @monotonic_value = monotonic_value
        @monotonic_reference = monotonic_reference
      end

      def apply(fact)
        case fact.type
        when :intent_registered
          restore_intent!(fact)
          true
        when :policy_registered
          restore_policy!(fact)
          true
        else
          false
        end
      end

      private

      def restore_intent!(fact)
        payload = fact.payload
        existing = @payouts.call[fact.payout_id]
        intent = RubyRouting::PayoutIntent.new(
          id: fact.payout_id,
          money: payload.fetch(:money),
          recipient: payload.fetch(:recipient, {}),
          context: payload.fetch(:context, {})
        )
        if existing
          if @same_intent.call(existing.intent, intent)
            raise RubyRouting::State::DurableCorruptionError,
              "duplicate intent registration for #{fact.payout_id}"
          end

          raise RubyRouting::State::DurableCorruptionError,
            "intent history conflicts for #{fact.payout_id}"
        end

        state = @payout_state_factory.call(intent)
        state.created_at = payload[:created_at]
        state.created_monotonic_at = if payload.key?(:created_monotonic_at)
          @monotonic_value.call(payload, :created_monotonic_at)
        elsif state.created_at
          @monotonic_reference.call(state.created_at)
        end
        @payouts.call[fact.payout_id] = state
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed intent registration: #{error.message}"
      end

      def restore_policy!(fact)
        payload = fact.payload
        state = @payout_state.call(fact.payout_id)
        policy_id = @policy_identity.call(payload, :policy_id)
        policy_epoch = @policy_identity.call(payload, :policy_epoch)
        policy_scope = @policy_identity.call(payload, :policy_scope)
        scope_key = [policy_id, policy_epoch, policy_scope].freeze
        if state.policy_scope_key
          if state.policy_scope_key == scope_key
            raise RubyRouting::State::DurableCorruptionError,
              "duplicate policy registration for #{fact.payout_id}"
          end

          raise RubyRouting::State::DurableCorruptionError,
            "conflicting policy binding for #{fact.payout_id}"
        end
        state.policy_scope_key = scope_key
        state.policy_epoch = policy_epoch
        fingerprint = @policy_identity.call(payload, :policy_fingerprint)
        if state.policy_fingerprint && state.policy_fingerprint != fingerprint
          raise RubyRouting::State::DurableCorruptionError,
            "conflicting policy fingerprint for #{fact.payout_id}"
        end
        state.policy_fingerprint = fingerprint
        definition = payload[:definition]
        unless definition
          raise RubyRouting::State::DurableCorruptionError,
            "policy definition is missing for #{scope_key.inspect}"
        end
        policy = @policy_from_definition.call(definition)
        unless policy.scope_key == scope_key && policy.fingerprint == state.policy_fingerprint
          raise RubyRouting::State::DurableCorruptionError,
            "policy definition fingerprint mismatch for #{scope_key.inspect}"
        end
        unless payload.fetch(:static_feasibility) == policy.static_feasibility
          raise RubyRouting::State::DurableCorruptionError,
            "policy static feasibility does not match its definition for #{scope_key.inspect}"
        end
        existing = @policies.call[scope_key]
        if existing && (existing.fingerprint != policy.fingerprint || existing.to_h != policy.to_h)
          raise RubyRouting::State::DurableCorruptionError,
            "policy scope identity was reused with a different definition for #{scope_key.inspect}"
        end
        @policies.call[scope_key] = policy
      rescue KeyError, TypeError, NoMethodError => error
        raise RubyRouting::State::DurableCorruptionError,
          "malformed policy registration: #{error.message}"
      end
    end
  end
end
