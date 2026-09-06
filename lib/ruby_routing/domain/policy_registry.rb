# frozen_string_literal: true

module RubyRouting
  class PolicyRegistry
    def initialize(policies = [])
      @mutex = Thread::Mutex.new
      @policies_by_scope = {}
      @activation_sequence = 0
      @activation_order = {}
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

        @policies_by_scope[key] = policy
        @activation_sequence += 1
        @activation_order[key] = @activation_sequence
      end
      policy
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

    def find_for_intent(intent, scope: :default)
      unless intent.is_a?(RubyRouting::PayoutIntent)
        raise ArgumentError, "intent must be PayoutIntent"
      end

      currency = intent.money.currency
      normalized_scope = normalize_identity(scope, "policy scope")
      @mutex.synchronize do
        matching = @policies_by_scope.values.select do |policy|
          policy.scope == normalized_scope && (policy.currency.nil? || policy.currency == currency)
        end
        return matching.first if matching.length == 1
        return nil if matching.empty?

        matching.max_by { |policy| @activation_order.fetch(policy.scope_key) }
      end
    end

    def policies
      @mutex.synchronize { @policies_by_scope.values.freeze }
    end

    private

    def normalize_identity(value, label)
      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized
    end
  end
end
