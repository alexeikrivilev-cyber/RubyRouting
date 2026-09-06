# frozen_string_literal: true

module RubyRouting
  class DecisionProposal
    ACTIONS = %i[assign retry_same resolve defer terminate already_final].freeze
    ROLES = %i[primary recovery resolution].freeze

    attr_reader :action, :provider_id, :operation_id, :attempt_id, :role, :policy_epoch,
                :reasons, :reason_codes, :allocation_decision, :runtime_feasibility,
                :deviation_cause, :deviation_recoverability

    def initialize(action:, provider_id: nil, operation_id: nil, attempt_id: nil,
                   role:, policy_epoch:, reasons: [], reason_codes: [], allocation_decision: nil,
                   runtime_feasibility: nil, deviation_cause: nil, deviation_recoverability: nil)
      @action = normalize(action, ACTIONS, "decision action")
      @provider_id = normalize_optional_id(provider_id, "provider id")
      @operation_id = normalize_optional_id(operation_id, "operation id")
      @attempt_id = normalize_optional_id(attempt_id, "attempt id")
      @role = normalize(role, ROLES, "decision role")
      @policy_epoch = normalize_id(policy_epoch, "policy epoch")
      @reasons = RubyRouting::Collection.to_array(reasons, "decision reasons").map { |reason| reason.to_s.freeze }.freeze
      @reason_codes = RubyRouting::Collection.to_array(reason_codes, "decision reason codes").map do |reason_code|
        reason_code.is_a?(Symbol) ? reason_code : reason_code.to_s.freeze
      end.freeze
      unless allocation_decision.nil? || allocation_decision.is_a?(RubyRouting::Routing::AllocationDecision)
        raise ArgumentError, "allocation_decision must be AllocationDecision or nil"
      end
      @allocation_decision = allocation_decision
      unless runtime_feasibility.nil? || runtime_feasibility.is_a?(RubyRouting::Routing::RuntimeFeasibility)
        raise ArgumentError, "runtime_feasibility must be RuntimeFeasibility or nil"
      end
      @runtime_feasibility = runtime_feasibility
      @deviation_cause = normalize_optional_deviation_cause(deviation_cause)
      @deviation_recoverability = normalize_optional_recoverability(deviation_recoverability)
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
        reason_codes: reason_codes,
        allocation_decision: allocation_decision,
        runtime_feasibility: runtime_feasibility,
        deviation_cause: deviation_cause,
        deviation_recoverability: deviation_recoverability
      )
    end

    private

    def validate_shape!
      if %i[assign retry_same].include?(action) && provider_id.nil?
        raise ArgumentError, "assignment decisions require a provider id"
      end
      if %i[resolve retry_same].include?(action) &&
         (provider_id.nil? || operation_id.nil? || attempt_id.nil?)
        raise ArgumentError, "resolution decisions require owner identifiers"
      end
      if action == :assign && !%i[primary recovery].include?(role)
        raise ArgumentError, "assignment decisions require primary or recovery role"
      end
      if %i[resolve retry_same].include?(action) && role != :resolution
        raise ArgumentError, "resolution decisions require resolution role"
      end
      if action == :defer && !%i[recovery resolution].include?(role)
        raise ArgumentError, "defer decisions require recovery or resolution role"
      end
      if %i[already_final terminate].include?(action) && role != :resolution
        raise ArgumentError, "terminal control decisions require resolution role"
      end
      if %i[defer terminate already_final].include?(action) &&
         [provider_id, operation_id, attempt_id].any?
        raise ArgumentError, "non-operation decisions cannot carry operation identifiers"
      end
    end

    def normalize_optional_id(value, label)
      return nil if value.nil?

      normalize_id(value, label)
    end

    def normalize_id(value, label)
      RubyRouting::Identity.normalize(value, label)
    end

    def normalize(value, allowed, label)
      RubyRouting::Enum.normalize(value, allowed, label)
    end

    def normalize_optional_deviation_cause(value)
      return nil if value.nil?

      RubyRouting::Enum.normalize(
        value,
        RubyRouting::Routing::Deviation::UNAVOIDABLE_CAUSES + RubyRouting::Routing::Deviation::RECOVERABLE_CAUSES,
        "deviation cause"
      )
    end

    def normalize_optional_recoverability(value)
      return nil if value.nil?

      RubyRouting::Enum.normalize(
        value,
        RubyRouting::Routing::Deviation::RECOVERABILITY,
        "deviation recoverability"
      )
    end
  end

  class Fact
    TYPES = %i[
      provider_opportunity_registered
      provider_opportunity_removed
      intent_registered
      policy_registered
      opportunity_evaluated
      decision_committed
      allocation_committed
      capacity_reserved
      capacity_released
      ownership_acquired
      attempt_started
      provider_execution_failed
      provider_observed
      provider_interaction_completed
      ownership_released
      settlement_recorded
      payout_state_changed
      operation_phase_changed
      transport_classified
      economic_conflict
      reversal_recorded
      health_signal
      health_state_changed
      health_exposure_reserved
      health_exposure_released
      quality_signal
      reconciliation_blocked
      throughput_consumed
      provider_runtime_changed
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
      RubyRouting::Enum.normalize(value, TYPES, "fact type")
    end

    def normalize_id(value, label)
      RubyRouting::Identity.normalize(value, label)
    end

    def freeze_nested(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), copy|
          copy[freeze_nested(key)] = freeze_nested(nested)
        end.freeze
      when Array
        value.map { |nested| freeze_nested(nested) }.freeze
      when String
        value.dup.freeze
      else
        if value.respond_to?(:each)
          RubyRouting::Collection.to_array(value, "fact nested collection")
            .map { |nested| freeze_nested(nested) }.freeze
        else
          value.freeze
        end
      end
    end
  end
end
