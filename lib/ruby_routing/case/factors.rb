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

      # Optional factor inputs must be distinguishable from an explicit
      # zero-valued policy. A missing input contributes no evidence; a typed
      # zero remains real no-headroom evidence.
      def configured_for?(provider_state:, min_turnover: nil, preferred_amount_range: nil)
        true
      end

      # Built-in preference factors expose a stable unit interval so an
      # unrelated eligible provider cannot redefine the meaning of a weight
      # by changing the candidate-set min/max. Allocation factors override
      # this when their raw value has a stable, dimensionally shared
      # portfolio-loss range.
      def normalization_bounds
        [Rational(0, 1), Rational(1, 1)].freeze
      end

    end

    class CountShareFactor < FactorDefinition
      def initialize
        super(:count)
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        -traffic.post_decision_loss(
          measure: :count, provider_id: provider_state.provider.payment_system, amount: operation.amount
        )
      end

      def reason(raw)
        "post-decision count portfolio L1 loss=#{-raw}"
      end

      def normalization_bounds
        [Rational(-2, 1), Rational(0, 1)].freeze
      end

    end

    class VolumeShareFactor < FactorDefinition
      def initialize
        super(:volume)
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        -traffic.post_decision_loss(
          measure: :volume, provider_id: provider_state.provider.payment_system, amount: operation.amount
        )
      end

      def reason(raw)
        "post-decision volume portfolio L1 loss=#{-raw}"
      end

      def normalization_bounds
        [Rational(-2, 1), Rational(0, 1)].freeze
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
        # Absence of optional soft configuration is no preference. It must not
        # silently outrank a configured provider whose band does not match.
        return Rational(0, 1) unless preferred_amount_range

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

      def reason(raw, preferred_amount_range: nil)
        if preferred_amount_range
          "preferred amount band preference=#{raw}; hard amount gate evaluated separately"
        else
          "preferred amount band absent; neutral/no preference; hard amount gate evaluated separately"
        end
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
        headroom = lambda do |limit, used|
          # A zero capacity is a typed no-headroom boundary. Router normally
          # hard-excludes it before scoring, but direct resolver callers must
          # remain total and exact rather than dividing by zero.
          next Rational(0, 1) if limit.nil? || limit.zero?

          Rational(limit - used, limit)
        end
        values = [
          [provider.daily_amount_limit, provider_state.daily_approved_amount + operation.amount],
          [provider.in_progress_count_limit, provider_state.in_progress_count + 1],
          [provider.in_progress_amount_limit, provider_state.in_progress_amount + operation.amount]
        ].filter_map do |limit, used|
          next if limit.nil?

          headroom.call(limit, used)
        end
        # An absent dimension contributes no evidence; average only typed
        # capacity dimensions. An entirely absent policy is handled as
        # non-discriminating by the resolver rather than as worst headroom.
        values.empty? ? Rational(0, 1) : values.sum / values.length
      end

      def configured_for?(provider_state:, min_turnover: nil, preferred_amount_range: nil)
        provider = provider_state.provider
        [
          provider.daily_amount_limit,
          provider.in_progress_count_limit,
          provider.in_progress_amount_limit
        ].any? { |limit| !limit.nil? }
      end

      def reason(raw, configured: true)
        return "capacity limits absent; neutral/no load preference" unless configured

        "current daily/concurrent headroom=#{raw}"
      end
    end

    class IntensityFactor < FactorDefinition
      def initialize
        super(:intensity)
      end

      def raw(provider_state:, operation:, traffic:, as_of:, min_turnover: nil, preferred_amount_range: nil)
        # An absent optional RPM policy is not evidence of maximum headroom.
        # Keep it at the neutral baseline so a partially configured provider
        # cannot win merely because this factor has no input for it.
        return Rational(0, 1) if provider_state.rpm_limit.nil? || provider_state.rpm_limit.zero?

        Rational(provider_state.rpm_limit - provider_state.rpm_count(as_of), provider_state.rpm_limit)
      end

      def configured_for?(provider_state:, min_turnover: nil, preferred_amount_range: nil)
        !provider_state.rpm_limit.nil?
      end

      def reason(raw, rpm_limit: nil)
        return "RPM limit absent; neutral/no intensity preference" unless rpm_limit

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
        parsed = values.each_with_object({}) do |(key, weight), result|
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
        @values = FactorRegistry::DEFINITIONS.each_with_object({}) do |definition, result|
          factor = definition.key
          result[factor] = parsed.fetch(factor) if parsed.key?(factor)
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
      attr_reader :weights, :min_turnovers, :preferred_amount_ranges

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

      # `normalization_candidates` is an explicit, stable opportunity pool.
      # A resolver must not silently let a caller's subset redefine the scale
      # of a configured weight; Router supplies the complete eligible pool and
      # alternate callers must make their comparison pool explicit.
      def resolve(candidates:, operation:, traffic:, as_of:, phase: :primary,
                  normalization_candidates: nil)
        candidates = candidates.to_a
        raise InputError, "conflict resolver requires candidates" if candidates.empty?
        unless normalization_candidates
          raise InputError, "conflict resolver requires an explicit normalization candidate pool"
        end
        normalization_candidates = normalization_candidates.to_a
        raise InputError, "conflict resolver requires normalization candidates" if normalization_candidates.empty?
        candidate_ids = candidates.map { |state| state.provider.payment_system }
        normalization_ids = normalization_candidates.map { |state| state.provider.payment_system }
        unless candidate_ids.all? { |provider_id| normalization_ids.include?(provider_id) }
          raise InputError, "normalization candidate pool must include every candidate"
        end
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
        configured_values = active_weights.each_with_object({}) do |(factor_key, _weight), result|
          factor = FactorRegistry.fetch(factor_key)
          result[factor_key] = candidates.to_h do |state|
            [state.provider.payment_system, factor.configured_for?(
              provider_state: state, min_turnover: @min_turnovers[state.provider.payment_system],
              preferred_amount_range: @preferred_amount_ranges[state.provider.payment_system]
            )]
          end
        end
        normalization_values = if normalization_candidates.equal?(candidates)
          raw_values
        else
          active_weights.each_with_object({}) do |(factor_key, _weight), result|
            factor = FactorRegistry.fetch(factor_key)
            result[factor_key] = normalization_candidates.to_h do |state|
              [state.provider.payment_system, factor.raw(
                provider_state: state, operation: operation, traffic: traffic,
                as_of: as_of, min_turnover: @min_turnovers[state.provider.payment_system],
                preferred_amount_range: @preferred_amount_ranges[state.provider.payment_system]
              )]
            end
          end
        end
        normalization_configured = if normalization_candidates.equal?(candidates)
          configured_values
        else
          active_weights.each_with_object({}) do |(factor_key, _weight), result|
            factor = FactorRegistry.fetch(factor_key)
            result[factor_key] = normalization_candidates.to_h do |state|
              [state.provider.payment_system, factor.configured_for?(
                provider_state: state, min_turnover: @min_turnovers[state.provider.payment_system],
                preferred_amount_range: @preferred_amount_ranges[state.provider.payment_system]
              )]
            end
          end
        end
        # Zero-weight factors stay available as transparent trace data, but
        # they are not allowed to define the Pareto frontier used to scale a
        # positive objective. Otherwise a disabled business preference can
        # alter a winner indirectly through normalization.
        positive_factor_keys = active_weights.filter_map { |factor_key, weight| factor_key if weight.positive? }
        normalization_provider_ids = non_dominated_provider_ids(
          normalization_candidates, positive_factor_keys, normalization_values
        )
        traces = candidates.each_with_object({}) do |state, result|
          provider_id = state.provider.payment_system
          result[provider_id] = active_weights.each_with_object([]) do |(factor_key, weight), evidence|
            factor = FactorRegistry.fetch(factor_key)
            raw = raw_values.fetch(factor_key).fetch(provider_id)
            factor_values = factor.normalization_bounds
            if factor_values
              # Missing optional inputs are not hidden zero-quality evidence.
              # Only typed values can make a factor discriminating; one
              # configured candidate therefore cannot win solely because all
              # other candidates omitted that optional policy.
              available_values = normalization_values.fetch(factor_key).select do |candidate_id, _value|
                normalization_configured.fetch(factor_key).fetch(candidate_id)
              end.values
              discriminating = available_values.uniq.length > 1
            else
              frontier_values = normalization_provider_ids.map do |normalization_provider_id|
                normalization_values.fetch(factor_key).fetch(normalization_provider_id)
              end
              # A single Pareto-frontier point has no usable range for this
              # factor (for example, one candidate strictly dominates another
              # when priority is the only configured objective). Keep the full
              # raw range in that case so the active factor does not disappear.
              factor_values = if frontier_values.uniq.length > 1
                frontier_values
              else
                normalization_values.fetch(factor_key).values
              end
              discriminating = factor_values.uniq.length > 1
            end
            configured = configured_values.fetch(factor_key).fetch(provider_id)
            normalized = if configured && discriminating
              normalize(raw, factor_values)
            else
              Rational(0, 1)
            end
            reason = if factor_key == :amount
              factor.reason(raw, preferred_amount_range: @preferred_amount_ranges[provider_id])
            elsif factor_key == :intensity
              factor.reason(raw, rpm_limit: state.rpm_limit)
            elsif factor_key == :load
              configured = [
                state.provider.daily_amount_limit,
                state.provider.in_progress_count_limit,
                state.provider.in_progress_amount_limit
              ].any?
              factor.reason(raw, configured: configured)
            else
              factor.reason(raw)
            end
            reason = "#{reason}; non-discriminating; no causal contribution" unless discriminating
            evidence << FactorEvidence.new(
              factor: factor_key, raw: raw, normalized: normalized, weight: weight,
              reason: reason
            )
          end.freeze
        end.freeze
        scores = traces.transform_values { |values| values.sum(&:contribution) }.freeze
        # Once the configured composite score is equal, provider priority is
        # not allowed to re-enter as an implicit business objective. If
        # priority is configured, its factor contribution already participates
        # in `scores`; otherwise the deterministic tie-break is provider id.
        selected = candidates.sort_by do |state|
          [-(scores.fetch(state.provider.payment_system)), state.provider.payment_system]
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
        @weights.values
      end

      # Candidate-relative min/max scaling is retained for the actual
      # opportunity frontier. A provider dominated on every active raw factor
      # cannot change that scale merely by entering the live eligible set.
      def non_dominated_provider_ids(states, factor_keys, values)
        provider_ids = states.map { |state| state.provider.payment_system }
        provider_ids.reject do |provider_id|
          provider_ids.any? do |other_id|
            next false if other_id == provider_id

            factor_keys.all? do |factor_key|
              values.fetch(factor_key).fetch(other_id) >= values.fetch(factor_key).fetch(provider_id)
            end && factor_keys.any? do |factor_key|
              values.fetch(factor_key).fetch(other_id) > values.fetch(factor_key).fetch(provider_id)
            end
          end
        end.freeze
      end

      def normalize(raw, values)
        min = values.min
        max = values.max
        scaled = Rational(raw - min, max - min)
        [[scaled, Rational(0, 1)].max, Rational(1, 1)].min
      end

    end
  end
end
