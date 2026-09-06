# frozen_string_literal: true

module RubyRouting
  # Immutable, durable description of the next legal same-provider recovery
  # interaction. It deliberately carries both wall-clock and exact monotonic
  # deadlines: wall time is useful to callers, while the coordinator uses the
  # monotonic value to prevent clock movement from bypassing a delay.
  class RecoverySchedule
    ACTIONS = %i[resolve retry_same].freeze

    attr_reader :action, :provider_id, :operation_id, :attempt_id,
                :scheduled_at, :scheduled_monotonic_at, :next_action_at,
                :next_action_monotonic_at, :delay_seconds, :interaction_index,
                :reason_code

    def initialize(action:, provider_id:, operation_id:, attempt_id:,
                   scheduled_at:, scheduled_monotonic_at:, next_action_at:,
                   next_action_monotonic_at:, delay_seconds:, interaction_index:,
                   reason_code:)
      @action = RubyRouting::Enum.normalize(action, ACTIONS, "recovery schedule action")
      @provider_id = normalize_id(provider_id, "provider id")
      @operation_id = normalize_id(operation_id, "operation id")
      @attempt_id = normalize_id(attempt_id, "attempt id")
      @scheduled_at = normalize_time(scheduled_at, "scheduled_at")
      @scheduled_monotonic_at = normalize_exact_time(
        scheduled_monotonic_at,
        "scheduled_monotonic_at"
      )
      @next_action_at = normalize_time(next_action_at, "next_action_at")
      @next_action_monotonic_at = normalize_exact_time(
        next_action_monotonic_at,
        "next_action_monotonic_at"
      )
      @delay_seconds = normalize_non_negative_integer(delay_seconds, "delay_seconds")
      @interaction_index = normalize_non_negative_integer(interaction_index, "interaction_index")
      @reason_code = normalize_reason_code(reason_code)
      validate_deadline_math!
      freeze
    end

    def self.from(value)
      return nil if value.nil?
      return value if value.is_a?(self)

      values = RubyRouting::HashKeys.symbolize(
        value,
        %i[
          action provider_id operation_id attempt_id scheduled_at scheduled_monotonic_at
          next_action_at next_action_monotonic_at delay_seconds interaction_index reason_code
        ],
        "recovery schedule"
      )
      new(**values)
    rescue ArgumentError, KeyError, TypeError => error
      raise ArgumentError, "invalid recovery schedule: #{error.message}"
    end

    def due?(as_of:, as_of_monotonic: nil)
      if as_of_monotonic.nil?
        normalize_time(as_of, "as_of") >= next_action_at
      else
        normalize_exact_time(as_of_monotonic, "as_of_monotonic") >= next_action_monotonic_at
      end
    end

    def to_h
      {
        action: action,
        provider_id: provider_id,
        operation_id: operation_id,
        attempt_id: attempt_id,
        scheduled_at: scheduled_at,
        scheduled_monotonic_at: scheduled_monotonic_at,
        next_action_at: next_action_at,
        next_action_monotonic_at: next_action_monotonic_at,
        delay_seconds: delay_seconds,
        interaction_index: interaction_index,
        reason_code: reason_code
      }.freeze
    end

    private

    def normalize_id(value, label)
      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized.freeze
    end

    def normalize_time(value, label)
      unless value.is_a?(Time)
        raise ArgumentError, "#{label} must be a Time"
      end

      value.getutc.freeze
    end

    def normalize_exact_time(value, label)
      unless value.is_a?(Integer) || value.is_a?(Rational)
        raise ArgumentError, "#{label} must be an exact Integer or Rational"
      end

      value
    end

    def normalize_non_negative_integer(value, label)
      unless value.is_a?(Integer) && value >= 0
        raise ArgumentError, "#{label} must be a non-negative Integer"
      end

      value
    end

    def normalize_reason_code(value)
      unless value.is_a?(String) || value.is_a?(Symbol)
        raise ArgumentError, "recovery schedule reason_code must be a String or Symbol"
      end

      value.is_a?(Symbol) ? value : value.freeze
    end

    def validate_deadline_math!
      wall_delta = next_action_at.to_r - scheduled_at.to_r
      monotonic_delta = next_action_monotonic_at - scheduled_monotonic_at
      unless wall_delta == delay_seconds && monotonic_delta == delay_seconds
        raise ArgumentError, "recovery schedule deadline does not match delay_seconds"
      end
    end
  end

  # Product-facing due-work value. A reconciliation item has no scheduled
  # timestamp because it is immediately actionable only through explicit
  # observation; its nil due_at is intentional and distinct from a delayed
  # recovery action.
  class RecoveryWorkItem
    ACTIONS = (RecoverySchedule::ACTIONS + [:reconcile]).freeze

    attr_reader :payout_id, :action, :provider_id, :operation_id, :attempt_id,
                :due_at, :reason_code, :status

    def initialize(payout_id:, action:, provider_id:, operation_id:, attempt_id:,
                   due_at:, reason_code:, status:)
      @payout_id = normalize_id(payout_id, "payout id")
      @action = RubyRouting::Enum.normalize(action, ACTIONS, "recovery work action")
      @provider_id = normalize_id(provider_id, "provider id")
      @operation_id = normalize_id(operation_id, "operation id")
      @attempt_id = normalize_id(attempt_id, "attempt id")
      unless due_at.nil? || due_at.is_a?(Time)
        raise ArgumentError, "due_at must be a Time or nil"
      end
      @due_at = due_at&.getutc&.freeze
      @reason_code = reason_code.is_a?(Symbol) ? reason_code : reason_code.to_s.freeze
      @status = RubyRouting::Enum.normalize(
        status,
        RubyRouting::State::PayoutSnapshot::STATUSES,
        "recovery work status"
      )
      freeze
    end

    def due?(as_of:)
      return true if due_at.nil?

      unless as_of.is_a?(Time)
        raise ArgumentError, "as_of must be a Time"
      end

      as_of.utc >= due_at
    end

    def to_h
      {
        payout_id: payout_id,
        action: action,
        provider_id: provider_id,
        operation_id: operation_id,
        attempt_id: attempt_id,
        due_at: due_at,
        reason_code: reason_code,
        status: status
      }.freeze
    end

    private

    def normalize_id(value, label)
      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized.freeze
    end
  end
end
