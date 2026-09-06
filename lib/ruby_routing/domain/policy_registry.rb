# frozen_string_literal: true

module RubyRouting
  class PolicyRegistry
    class ReadOnlyView
      def initialize(registry, configuration_store: nil)
        @registry = registry
        @configuration_store = configuration_store
        freeze
      end

      def fetch(**attributes)
        with_current_registry { |registry| registry.fetch(**attributes) }
      end

      def resolve_for_intent(intent, scope: :default)
        with_current_registry do |registry|
          registry.resolve_for_intent(intent, scope: scope)
        end
      end

      def find_for_intent(intent, scope: :default)
        with_current_registry do |registry|
          registry.find_for_intent(intent, scope: scope)
        end
      end

      def policies
        return @registry.policies unless @configuration_store

        @configuration_store.with_snapshot(&:policies)
      end

      private

      def with_current_registry
        return yield @registry unless @configuration_store

        @configuration_store.with_snapshot do |snapshot|
          yield RubyRouting::PolicyRegistry.new(snapshot.policies)
        end
      end
    end

    def self.same_policy_set?(left, right)
      signature = lambda do |policies|
        RubyRouting::Collection.to_array(policies, "policies")
          .map { |policy| [policy.scope_key, policy.fingerprint] }
          .sort_by { |scope_key, fingerprint| [scope_key.map(&:to_s), fingerprint] }
      end

      signature.call(left) == signature.call(right)
    end

    def initialize(policies = [])
      @mutex = Thread::Mutex.new
      @policies_by_scope = {}
      @application_mutations_sealed = false
      @application_binding = nil
      @application_mutation_owner = nil
      @application_mutation_depth = 0
      values = policies.nil? ? [] : RubyRouting::Collection.to_array(policies, "policies")
      values.each { |policy| register(policy) }
    end

    def read_only(configuration_store: nil)
      ReadOnlyView.new(self, configuration_store: configuration_store)
    end

    def register(policy)
      unless policy.is_a?(RubyRouting::RoutingPolicy)
        raise ArgumentError, "policy must be RoutingPolicy"
      end

      @mutex.synchronize do
        ensure_mutation_allowed!
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
      @mutex.synchronize do
        ensure_mutation_allowed!
        @policies_by_scope = replacement_by_scope
      end
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

        highest_priority = matching.map { |policy| policy.selector.priority }.max
        priority_matches = matching.select { |policy| policy.selector.priority == highest_priority }
        winners = priority_matches.reject do |candidate|
          priority_matches.any? do |other|
            other != candidate && semantically_narrows?(other, candidate)
          end
        end
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

    def reserve_application_binding!(owner)
      unless owner
        raise ArgumentError, "policy registry application owner is required"
      end

      @mutex.synchronize do
        raise ArgumentError, "policy registry is already bound to another application" if @application_binding

        @application_binding = owner
        @application_mutations_sealed = true
      end
      nil
    end

    def release_application_binding!(owner)
      @mutex.synchronize do
        return unless @application_binding.equal?(owner)

        @application_binding = nil
        @application_mutations_sealed = false
      end
      nil
    end

    def bind_application!(owner)
      @mutex.synchronize do
        if @application_binding && !@application_binding.equal?(owner)
          raise ArgumentError, "policy registry is already bound to another application"
        end

        @application_binding = owner
        @application_mutations_sealed = true
      end
      nil
    end

    # Application publication is the only mutation path for a registry shared
    # with an active configuration. The thread-scoped capability lets the
    # Commands coordinator call the existing public replacement override
    # (including fault-injection subclasses) without exposing that capability
    # through the read-only application view.
    def with_application_mutation
      raise ArgumentError, "application mutation block is required" unless block_given?

      current_thread = Thread.current
      @mutex.synchronize do
        if @application_mutation_owner && @application_mutation_owner != current_thread
          raise ArgumentError, "policy registry application mutation is already in progress"
        end

        @application_mutation_owner = current_thread
        @application_mutation_depth += 1
      end
      yield
    ensure
      @mutex.synchronize do
        next unless @application_mutation_owner == current_thread

        @application_mutation_depth -= 1
        if @application_mutation_depth.zero?
          @application_mutation_owner = nil
        end
      end
    end

    def ensure_mutation_allowed!
      return unless @application_mutations_sealed
      return if @application_mutation_owner == Thread.current && @application_mutation_depth.positive?

      raise ArgumentError, "policy registry mutations must use Application::Commands"
    end

    def semantically_narrows?(candidate, broader)
      candidate_selector = selector_for_resolution(candidate)
      broader_selector = selector_for_resolution(broader)
      candidate_selector.strictly_narrows?(broader_selector)
    end

    def selector_for_resolution(policy)
      selector = policy.selector
      return selector if policy.currency.nil? || selector.currency == policy.currency

      RubyRouting::PolicySelector.new(
        currency: policy.currency,
        payment_method: selector.payment_method,
        rail: selector.rail,
        destination_kind: selector.destination_kind,
        labels: selector.labels,
        minimum_amount_minor: selector.minimum_amount_minor,
        maximum_amount_minor: selector.maximum_amount_minor,
        priority: selector.priority
      )
    end

    def normalize_identity(value, label)
      unless value.is_a?(String) || value.is_a?(Symbol)
        raise ArgumentError, "#{label} must be a non-empty String or Symbol"
      end

      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized
    end
  end
end
