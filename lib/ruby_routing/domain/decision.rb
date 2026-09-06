# frozen_string_literal: true

module RubyRouting
  class DecisionProposal
    ACTIONS = %i[assign retry_same resolve defer terminate already_final].freeze
    ROLES = %i[primary recovery resolution].freeze

    attr_reader :action, :provider_id, :operation_id, :attempt_id, :role, :policy_epoch,
                :reasons, :allocation_decision

    def initialize(action:, provider_id: nil, operation_id: nil, attempt_id: nil,
                   role:, policy_epoch:, reasons: [], allocation_decision: nil)
      @action = normalize(action, ACTIONS, "decision action")
      @provider_id = provider_id&.to_s&.freeze
      @operation_id = operation_id&.to_s&.freeze
      @attempt_id = attempt_id&.to_s&.freeze
      @role = normalize(role, ROLES, "decision role")
      @policy_epoch = policy_epoch.to_s.freeze
      @reasons = reasons.map(&:to_s).map(&:freeze).freeze
      @allocation_decision = allocation_decision
      validate_shape!
      freeze
    end

    def assignment?
      %i[assign retry_same].include?(action)
    end

    def resolution?
      action == :resolve
    end

    def no_route?
      action == :defer
    end

    def with_identifiers(operation_id:, attempt_id:)
      self.class.new(
        action: action,
        provider_id: provider_id,
        operation_id: operation_id,
        attempt_id: attempt_id,
        role: role,
        policy_epoch: policy_epoch,
        reasons: reasons,
        allocation_decision: allocation_decision
      )
    end

    private

    def validate_shape!
      if %i[assign retry_same].include?(action) && provider_id.nil?
        raise ArgumentError, "assignment decisions require a provider id"
      end
      if action == :resolve && (provider_id.nil? || operation_id.nil? || attempt_id.nil?)
        raise ArgumentError, "resolution decisions require owner identifiers"
      end
    end

    def normalize(value, allowed, label)
      normalized = value.to_sym
      raise ArgumentError, "unsupported #{label}" unless allowed.include?(normalized)

      normalized
    rescue NoMethodError
      raise ArgumentError, "unsupported #{label}"
    end
  end

  class Fact
    TYPES = %i[
      intent_registered
      opportunity_evaluated
      decision_committed
      allocation_committed
      ownership_acquired
      attempt_started
      provider_observed
      ownership_released
      settlement_recorded
      payout_state_changed
    ].freeze

    attr_reader :sequence, :type, :fact_id, :payout_id, :payload

    def initialize(sequence:, type:, fact_id:, payout_id:, payload: {})
      unless sequence.is_a?(Integer) && sequence.positive?
        raise ArgumentError, "fact sequence must be a positive Integer"
      end
      @sequence = sequence
      @type = normalize_type(type)
      @fact_id = normalize_id(fact_id, "fact id")
      @payout_id = normalize_id(payout_id, "payout id")
      @payload = freeze_nested(payload)
      freeze
    end

    private

    def normalize_type(value)
      normalized = value.to_sym
      raise ArgumentError, "unsupported fact type" unless TYPES.include?(normalized)

      normalized
    rescue NoMethodError
      raise ArgumentError, "unsupported fact type"
    end

    def normalize_id(value, label)
      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized.freeze
    end

    def freeze_nested(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), copy|
          copy[key.freeze] = freeze_nested(nested)
        end.freeze
      when Array
        value.map { |nested| freeze_nested(nested) }.freeze
      when String
        value.dup.freeze
      else
        value.freeze
      end
    end
  end
end
