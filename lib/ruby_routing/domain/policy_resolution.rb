# frozen_string_literal: true

module RubyRouting
  class PolicyResolutionError < ArgumentError
    attr_reader :resolution

    def initialize(message, resolution:)
      @resolution = resolution
      super(message)
    end
  end

  class NoMatchingPolicyError < PolicyResolutionError; end
  class AmbiguousPolicyError < PolicyResolutionError; end

  class PolicyResolution
    STATUSES = %i[matched no_match ambiguous].freeze

    attr_reader :status, :policy, :candidates, :scope

    def initialize(status:, policy: nil, candidates: [], scope:)
      unless STATUSES.include?(status)
        raise ArgumentError, "unsupported policy resolution status"
      end
      if status == :matched && !policy.is_a?(RubyRouting::RoutingPolicy)
        raise ArgumentError, "matched policy resolution requires a RoutingPolicy"
      end
      if status != :matched && !policy.nil?
        raise ArgumentError, "unmatched policy resolution cannot contain a policy"
      end
      unless candidates.is_a?(Array) && candidates.all? { |candidate| candidate.is_a?(RubyRouting::RoutingPolicy) }
        raise ArgumentError, "policy resolution candidates must be RoutingPolicy values"
      end

      @status = status
      @policy = policy
      @candidates = candidates.sort_by(&:scope_key).freeze
      unless scope.is_a?(String) || scope.is_a?(Symbol)
        raise ArgumentError, "policy resolution scope must be a String or Symbol"
      end

      @scope = scope.to_s.strip.freeze
      raise ArgumentError, "policy resolution scope must be non-empty" if @scope.empty?
      freeze
    end

    def matched?
      status == :matched
    end

    def no_match?
      status == :no_match
    end

    def ambiguous?
      status == :ambiguous
    end

    def to_h
      {
        status: status,
        scope: scope,
        policy: policy && policy_identity(policy),
        candidates: candidates.map { |candidate| policy_identity(candidate) }
      }.freeze
    end

    private

    def policy_identity(policy)
      {
        id: policy.id,
        epoch: policy.epoch,
        scope: policy.scope,
        fingerprint: policy.fingerprint,
        currency: policy.currency,
        selector: policy.selector.to_h
      }.freeze
    end
  end
end
