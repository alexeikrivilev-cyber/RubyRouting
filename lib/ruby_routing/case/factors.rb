# frozen_string_literal: true

module RubyRouting
  module Case
    class FactorEvidence
      attr_reader :factor, :raw, :normalized, :weight, :contribution, :reason

      def initialize(factor:, raw:, normalized:, weight:, reason:)
        @factor = factor.to_sym
        @raw = raw
        @normalized = normalized
        @weight = weight
        @contribution = normalized * weight
        @reason = reason.to_s.freeze
        freeze
      end

      def to_h
        {
          factor: factor.to_s,
          raw: raw,
          normalized: normalized,
          weight: weight,
          contribution: contribution,
          reason: reason
        }.freeze
      end
    end

    class FactorDefinition
      attr_reader :key

      def initialize(key)
        @key = key.to_sym
        freeze
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        raise NotImplementedError, "factor #{key} must implement raw"
      end

      def reason(raw)
        "#{key}=#{raw}"
      end
    end

    class CountShareFactor < FactorDefinition
      def initialize
        super(:count)
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        traffic.counterfactual(provider_id: provider_state.provider.payment_system, amount: operation.amount)
          .fetch(:count).fetch(:deficit_after)
      end
    end

    class VolumeShareFactor < FactorDefinition
      def initialize
        super(:volume)
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        traffic.counterfactual(provider_id: provider_state.provider.payment_system, amount: operation.amount)
          .fetch(:volume).fetch(:deficit_after)
      end
    end

    class PriorityFactor < FactorDefinition
      def initialize
        super(:priority)
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        Rational(1, provider_state.provider.priority + 1)
      end

      def reason(raw)
        "official priority lower-is-higher; preference=#{raw}"
      end
    end

    class AmountPreferenceFactor < FactorDefinition
      def initialize
        super(:amount)
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        return Rational(1, 1) unless preferred_amount_range

        low = preferred_amount_range.fetch(:min)
        high = preferred_amount_range.fetch(:max)
        return operation.amount == low ? Rational(1, 1) : Rational(0, 1) if low == high
        distance = if operation.amount < low
          low - operation.amount
        elsif operation.amount > high
          operation.amount - high
        else
          0
        end
        [Rational(1, 1) - Rational(distance, high - low), Rational(0, 1)].max
      end

      def reason(raw)
        "preferred amount band preference=#{raw}; hard amount gate evaluated separately"
      end
    end

    class ConversionFactor < FactorDefinition
      def initialize
        super(:conversion_24h)
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        provider_state.provider.conversion_24h
      end

      def reason(raw)
        "current conversion_24h=#{raw}"
      end
    end

    class LoadHeadroomFactor < FactorDefinition
      def initialize
        super(:load)
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        provider = provider_state.provider
        values = []
        if provider.daily_amount_limit
          values << Rational(provider.daily_amount_limit - provider_state.daily_approved_amount - operation.amount, provider.daily_amount_limit)
        end
        if provider.in_progress_count_limit
          values << Rational(provider.in_progress_count_limit - provider_state.in_progress_count - 1, provider.in_progress_count_limit)
        end
        if provider.in_progress_amount_limit
          values << Rational(provider.in_progress_amount_limit - provider_state.in_progress_amount - operation.amount, provider.in_progress_amount_limit)
        end
        values.empty? ? Rational(1, 1) : values.sum / values.length
      end

      def reason(raw)
        "current daily/concurrent headroom=#{raw}"
      end
    end

    class IntensityFactor < FactorDefinition
      def initialize
        super(:intensity)
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        return Rational(1, 1) unless provider_state.rpm_limit

        Rational(provider_state.rpm_limit - provider_state.rpm_count(as_of), provider_state.rpm_limit)
      end

      def reason(raw)
        "rolling RPM headroom=#{raw}"
      end
    end

    class TurnoverMinFactor < FactorDefinition
      def initialize
        super(:turnover_min)
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        return Rational(0, 1) if min_turnover.nil? || min_turnover.zero?
        [Rational(min_turnover - provider_state.daily_approved_amount, min_turnover), Rational(0, 1)].max
      end

      def reason(raw)
        "minimum-turnover obligation urgency=#{raw}"
      end
    end

    class FactorRegistry
      DEFINITIONS = [
        CountShareFactor.new,
        VolumeShareFactor.new,
        PriorityFactor.new,
        AmountPreferenceFactor.new,
        ConversionFactor.new,
        LoadHeadroomFactor.new,
        IntensityFactor.new,
        TurnoverMinFactor.new
      ].freeze

      def self.fetch(key)
        unless key.is_a?(String) || key.is_a?(Symbol)
          raise InputError, "unsupported case factor #{key.inspect}"
        end
        definition = DEFINITIONS.find { |item| item.key.to_s == key.to_s }
        raise InputError, "unsupported case factor #{key.inspect}" unless definition
        definition
      end
    end

    class RoutingWeights
      attr_reader :values

      def initialize(values = { priority: Rational(1, 1) })
        unless values.is_a?(Hash)
          raise InputError, "routing weights must be a Hash"
        end
        @values = values.each_with_object({}) do |(key, weight), result|
          unless key.is_a?(String) || key.is_a?(Symbol)
            raise InputError, "routing weight factor keys must be String or Symbol"
          end
          factor = FactorRegistry.fetch(key).key
          raise InputError, "duplicate routing weight factor #{factor}" if result.key?(factor)
          unless weight.is_a?(Integer) || weight.is_a?(Rational)
            raise InputError, "weight #{factor} must be exact Integer or Rational"
          end
          raise InputError, "weight #{factor} must be non-negative" if weight.negative?
          result[factor] = weight
        end.freeze
        raise InputError, "at least one routing factor must have positive weight" if @values.values.none?(&:positive?)
        freeze
      end
    end

    class Resolution
      attr_reader :selected_provider, :scores, :traces, :phase

      def initialize(selected_provider:, scores:, traces:, phase: :primary)
        @selected_provider = Input.assert_id(selected_provider, "selected provider")
        @scores = scores.freeze
        @traces = traces.freeze
        @phase = normalize_phase(phase)
        freeze
      end

      def score_for(provider_id)
        scores.fetch(Input.assert_id(provider_id, "score provider id"))
      end

      def selection_reason(candidate_count:)
        raise InputError, "candidate count must be a positive Integer" unless candidate_count.is_a?(Integer) && candidate_count.positive?
        return "only_eligible_provider" if candidate_count == 1

        maximum = scores.values.max
        if scores.values.count { |score| score == maximum } > 1
          return phase == :fallback ? "fallback_deterministic_tie_break" : "deterministic_tie_break"
        end
        phase == :fallback ? "fallback_highest_composite_score" : "highest_composite_score"
      end

      def to_h
        {
          selected_provider: selected_provider,
          phase: phase.to_s,
          scores: scores,
          factors: traces.transform_values { |values| values.map(&:to_h) }
        }.freeze
      end

      private

      def normalize_phase(value)
        phase = value.to_sym if value.is_a?(String) || value.is_a?(Symbol)
        raise InputError, "unsupported resolution phase #{value.inspect}" unless %i[primary fallback].include?(phase)

        phase
      end
    end

    class ConflictResolver
      PHASES = %i[primary fallback].freeze
      ALLOCATION_FACTORS = %i[count volume].freeze

      attr_reader :weights

      def initialize(weights: RoutingWeights.new, min_turnovers: {}, preferred_amount_ranges: {})
        @weights = weights.is_a?(RoutingWeights) ? weights : RoutingWeights.new(weights)
        unless min_turnovers.is_a?(Hash)
          raise InputError, "min_turnovers must be a Hash"
        end
        @min_turnovers = min_turnovers.each_with_object({}) do |(provider_id, amount), result|
          unless provider_id.is_a?(String) || provider_id.is_a?(Symbol)
            raise InputError, "min_turnover provider keys must be String or Symbol"
          end
          unless amount.is_a?(Integer) && amount >= 0
            raise InputError, "min_turnover values must be non-negative Integers"
          end
          provider_id = Input.assert_id(provider_id, "min_turnover provider id")
          raise InputError, "duplicate min_turnover provider #{provider_id}" if result.key?(provider_id)
          result[provider_id] = amount
        end.freeze
        unless preferred_amount_ranges.is_a?(Hash)
          raise InputError, "preferred_amount_ranges must be a Hash"
        end
        @preferred_amount_ranges = preferred_amount_ranges.each_with_object({}) do |(provider_id, range), result|
          key = Input.assert_id(provider_id, "preferred amount provider id")
          raise InputError, "duplicate preferred amount provider #{key}" if result.key?(key)
          canonical_keys = range.is_a?(Hash) && range.keys.all? { |field| field.is_a?(String) || field.is_a?(Symbol) } ? range.keys.map(&:to_sym) : []
          unless range.is_a?(Hash) && canonical_keys.uniq.length == canonical_keys.length && canonical_keys.uniq.sort == %i[max min]
            raise InputError, "preferred amount range for #{key} must contain min and max"
          end
          low = Input.assert_integer(range.fetch(:min) { range.fetch("min") }, "preferred amount min for #{key}", min: 0)
          high = Input.assert_integer(range.fetch(:max) { range.fetch("max") }, "preferred amount max for #{key}", min: 0)
          raise InputError, "preferred amount min exceeds max for #{key}" if low > high
          result[key] = { min: low, max: high }.freeze
        end.freeze
        freeze
      end

      def resolve(candidates:, operation:, traffic:, as_of:, phase: :primary)
        candidates = candidates.to_a
        raise InputError, "conflict resolver requires candidates" if candidates.empty?
        phase = normalize_phase(phase)
        active_weights = weights_for(phase)
        raw_values = active_weights.each_with_object({}) do |(factor_key, _weight), result|
          factor = FactorRegistry.fetch(factor_key)
          result[factor_key] = candidates.to_h do |state|
            [state.provider.payment_system, factor.raw(
              provider_state: state, operation: operation, traffic: traffic,
              as_of: as_of, min_turnover: @min_turnovers[state.provider.payment_system],
              preferred_amount_range: @preferred_amount_ranges[state.provider.payment_system]
            )]
          end
        end
        traces = candidates.each_with_object({}) do |state, result|
          provider_id = state.provider.payment_system
          result[provider_id] = active_weights.each_with_object([]) do |(factor_key, weight), evidence|
            factor = FactorRegistry.fetch(factor_key)
            raw = raw_values.fetch(factor_key).fetch(provider_id)
            factor_values = raw_values.fetch(factor_key).values
            discriminating = factor_values.uniq.length > 1
            normalized = discriminating ? normalize(raw, factor_values) : Rational(0, 1)
            reason = factor.reason(raw)
            reason = "#{reason}; non-discriminating; no causal contribution" unless discriminating
            evidence << FactorEvidence.new(
              factor: factor_key, raw: raw, normalized: normalized, weight: weight,
              reason: reason
            )
          end.freeze
        end.freeze
        scores = traces.transform_values { |values| values.sum(&:contribution) }.freeze
        selected = candidates.sort_by do |state|
          [-(scores.fetch(state.provider.payment_system)), state.provider.priority, state.provider.payment_system]
        end.first.provider.payment_system
        Resolution.new(selected_provider: selected, scores: scores, traces: traces, phase: phase)
      end

      private

      def normalize_phase(value)
        phase = value.to_sym if value.is_a?(String) || value.is_a?(Symbol)
        raise InputError, "unsupported resolution phase #{value.inspect}" unless PHASES.include?(phase)

        phase
      end

      def weights_for(phase)
        return @weights.values unless phase == :fallback

        @weights.values.reject { |factor_key, _weight| ALLOCATION_FACTORS.include?(factor_key) }
      end

      def normalize(raw, values)
        min = values.min
        max = values.max

        Rational(raw - min, max - min)
      end
    end
  end
end
