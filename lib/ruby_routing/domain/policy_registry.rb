# frozen_string_literal: true

module RubyRouting
  class PolicyRegistry
    def initialize(policies = [])
      @mutex = Thread::Mutex.new
      @policies_by_scope = {}
      values = policies.nil? ? [] : RubyRouting::Collection.to_array(policies, "policies")
      values.each { |policy| register(policy) }
    end

    def register(policy)
      unless policy.is_a?(RubyRouting::RoutingPolicy)
        raise ArgumentError, "policy must be RoutingPolicy"
      end

      @mutex.synchronize do
        key = policy.scope_key
        existing = @policies_by_scope[key]
        if existing && existing.fingerprint != policy.fingerprint
          raise ArgumentError, "policy identity was reused with a different definition"
        end

        @policies_by_scope[key] ||= policy
      end
      policy
    end

    # Replace the active set as one validated registry operation. Payouts keep
    # their durable pinned policy in the coordinator; this object only serves
    # new automatic policy resolution.
    def replace!(policies)
      replacement = self.class.new(policies)
      replacement_values = replacement.policies
      replacement_by_scope = replacement_values.to_h do |policy|
        [policy.scope_key, policy]
      end
      @mutex.synchronize { @policies_by_scope = replacement_by_scope }
      replacement_values
    end

    def fetch(id:, epoch:, scope: :default)
      key = [
        normalize_identity(id, "policy id"),
        normalize_identity(epoch, "policy epoch"),
        normalize_identity(scope, "policy scope")
      ].freeze
      @mutex.synchronize do
        @policies_by_scope.fetch(key) do
          raise KeyError, "no policy registered for #{key.inspect}"
        end
      end
    end

    def resolve_for_intent(intent, scope: :default)
      unless intent.is_a?(RubyRouting::PayoutIntent)
        raise ArgumentError, "intent must be PayoutIntent"
      end

      normalized_scope = normalize_identity(scope, "policy scope")
      @mutex.synchronize do
        matching = @policies_by_scope.values.select do |policy|
          policy.scope == normalized_scope &&
            policy.applies_to?(intent)
        end
        if matching.empty?
          return RubyRouting::PolicyResolution.new(
            status: :no_match,
            candidates: [],
            scope: normalized_scope
          )
        end

        highest_precedence = matching.map(&:selector).map(&:precedence_key).max
        winners = matching.select { |policy| policy.selector.precedence_key == highest_precedence }
        status = winners.length == 1 ? :matched : :ambiguous
        RubyRouting::PolicyResolution.new(
          status: status,
          policy: status == :matched ? winners.first : nil,
          candidates: status == :ambiguous ? winners : matching,
          scope: normalized_scope
        )
      end
    end

    def find_for_intent(intent, scope: :default)
      resolution = resolve_for_intent(intent, scope: scope)
      return resolution.policy if resolution.matched?
      return nil if resolution.no_match?

      raise RubyRouting::AmbiguousPolicyError.new(
        "ambiguous policy resolution for scope #{resolution.scope.inspect}",
        resolution: resolution
      )
    end

    def policies
      @mutex.synchronize { @policies_by_scope.values.sort_by(&:scope_key).freeze }
    end

    private

    def normalize_identity(value, label)
      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized
    end
  end
end
