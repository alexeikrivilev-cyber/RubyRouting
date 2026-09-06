# frozen_string_literal: true

module RubyRouting
  class StaticPolicyInfeasibilityError < ArgumentError
    attr_reader :reason_codes

    def initialize(message, reason_codes:)
      @reason_codes = RubyRouting::Collection.to_array(
        reason_codes,
        "policy infeasibility reason codes"
      ).map { |reason_code| reason_code.is_a?(Symbol) ? reason_code : reason_code.to_s.freeze }.uniq.freeze
      super(message)
    end
  end

  class RoutingConstraints
    attr_reader :allowed_provider_ids, :excluded_provider_ids, :required_context_labels,
                :minimum_amount_minor, :maximum_amount_minor

    def initialize(allowed_provider_ids: nil, excluded_provider_ids: [], required_context_labels: [],
                   minimum_amount_minor: nil, maximum_amount_minor: nil)
      @allowed_provider_ids = normalize_ids(allowed_provider_ids, "allowed_provider_ids")
      @excluded_provider_ids = normalize_ids(excluded_provider_ids, "excluded_provider_ids") || [].freeze
      @required_context_labels = normalize_labels(required_context_labels)
      @minimum_amount_minor = normalize_limit(minimum_amount_minor, "minimum_amount_minor")
      @maximum_amount_minor = normalize_limit(maximum_amount_minor, "maximum_amount_minor")
      if @minimum_amount_minor && @maximum_amount_minor && @minimum_amount_minor > @maximum_amount_minor
        raise ArgumentError, "constraint minimum cannot exceed maximum"
      end
      freeze
    end

    def allows?(intent:, provider_id:)
      violations(intent: intent, provider_id: provider_id).empty?
    end

    def violations(intent:, provider_id:)
      violations = []
      normalized_provider_id = provider_id.to_s.strip
      violations << :provider_not_allowed if allowed_provider_ids && !allowed_provider_ids.include?(normalized_provider_id)
      violations << :provider_excluded if excluded_provider_ids.include?(normalized_provider_id)
      if intent.is_a?(RubyRouting::PayoutIntent)
        violations << :amount_below_policy_minimum if minimum_amount_minor && intent.money.amount_minor < minimum_amount_minor
        violations << :amount_above_policy_maximum if maximum_amount_minor && intent.money.amount_minor > maximum_amount_minor
        labels = context_labels(intent)
        violations << :required_context_missing unless required_context_labels.all? { |label| labels.include?(label) }
      end
      violations.freeze
    end

    def to_h
      {
        allowed_provider_ids: allowed_provider_ids,
        excluded_provider_ids: excluded_provider_ids,
        required_context_labels: required_context_labels,
        minimum_amount_minor: minimum_amount_minor,
        maximum_amount_minor: maximum_amount_minor
      }.freeze
    end

    private

    def normalize_ids(value, label)
      return nil if value.nil?

      RubyRouting::Collection.to_array(value, label).map do |provider_id|
        normalized = provider_id.to_s.strip
        raise ArgumentError, "#{label} must contain non-empty ids" if normalized.empty?

        normalized.freeze
      end.uniq.freeze
    end

    def normalize_labels(value)
      RubyRouting::RoutingContext.normalize_labels(value)
    end

    def normalize_limit(value, label)
      return nil if value.nil?
      unless value.is_a?(Integer) && value >= 0
        raise ArgumentError, "#{label} must be a non-negative Integer or nil"
      end

      value
    end

    def context_labels(context)
      return [] unless context.is_a?(RubyRouting::PayoutIntent)

      context.routing_context.labels
    end
  end

  class RecoveryObjective
    MODES = %i[allocation_constrained].freeze
    DEFAULT_MODE = :allocation_constrained

    attr_reader :mode

    def initialize(mode: DEFAULT_MODE)
      @mode = RubyRouting::Enum.normalize(mode, MODES, "recovery objective")
      freeze
    end

    def default?
      mode == DEFAULT_MODE
    end

    def to_h
      { mode: mode }.freeze
    end

    def ==(other)
      other.is_a?(self.class) && mode == other.mode
    end
    alias eql? ==

    def hash
      mode.hash
    end
  end

  class RecoveryPolicy
    attr_reader :max_operations, :max_switches, :max_resolution_interactions,
                :ttl_seconds, :deadline_seconds, :initial_delay_seconds,
                :backoff_seconds, :max_delay_seconds

    def initialize(max_operations: 3, max_switches: 2, max_resolution_interactions: nil,
                   ttl_seconds: nil, deadline_seconds: nil, initial_delay_seconds: 0,
                   backoff_seconds: 0, max_delay_seconds: nil)
      @max_operations = normalize_positive(max_operations, "max_operations")
      @max_switches = normalize_non_negative(max_switches, "max_switches")
      max_resolution_interactions ||= [@max_operations - 1, 0].max
      @max_resolution_interactions = normalize_non_negative(
        max_resolution_interactions,
        "max_resolution_interactions"
      )
      @ttl_seconds = normalize_positive_or_nil(ttl_seconds, "ttl_seconds")
      @deadline_seconds = normalize_positive_or_nil(deadline_seconds, "deadline_seconds")
      @initial_delay_seconds = normalize_non_negative(initial_delay_seconds, "initial_delay_seconds")
      @backoff_seconds = normalize_non_negative(backoff_seconds, "backoff_seconds")
      @max_delay_seconds = normalize_positive_or_nil(max_delay_seconds, "max_delay_seconds")
      if @max_delay_seconds && @max_delay_seconds < @initial_delay_seconds
        raise ArgumentError, "max_delay_seconds cannot be below initial_delay_seconds"
      end
      freeze
    end

    def to_h
      values = {
        max_operations: max_operations,
        max_switches: max_switches,
        max_resolution_interactions: max_resolution_interactions,
        ttl_seconds: ttl_seconds,
        deadline_seconds: deadline_seconds
      }
      if schedule_configured?
        values.merge!(
          initial_delay_seconds: initial_delay_seconds,
          backoff_seconds: backoff_seconds,
          max_delay_seconds: max_delay_seconds
        )
      end
      values.freeze
    end

    def delay_for(interaction_index:)
      unless interaction_index.is_a?(Integer) && interaction_index >= 0
        raise ArgumentError, "interaction_index must be a non-negative Integer"
      end

      delay = initial_delay_seconds + (backoff_seconds * interaction_index)
      max_delay_seconds ? [delay, max_delay_seconds].min : delay
    end

    def schedule_configured?
      initial_delay_seconds.positive? || backoff_seconds.positive? || !max_delay_seconds.nil?
    end

    private

    def normalize_positive(value, label)
      unless value.is_a?(Integer) && value.positive?
        raise ArgumentError, "#{label} must be a positive Integer"
      end

      value
    end

    def normalize_non_negative(value, label)
      unless value.is_a?(Integer) && value >= 0
        raise ArgumentError, "#{label} must be a non-negative Integer"
      end

      value
    end

    def normalize_positive_or_nil(value, label)
      return nil if value.nil?

      normalize_positive(value, label)
    end
  end

  class RankingPolicy
    attr_reader :priority_by_provider, :cost_minor_by_provider, :latency_ms_by_provider

    def initialize(priority_by_provider: {}, cost_minor_by_provider: {}, latency_ms_by_provider: {})
      @priority_by_provider = normalize_metrics(priority_by_provider, "priority", allow_zero: true)
      @cost_minor_by_provider = normalize_metrics(cost_minor_by_provider, "cost", allow_zero: true)
      @latency_ms_by_provider = normalize_metrics(latency_ms_by_provider, "latency", allow_zero: true)
      freeze
    end

    def priority_for(provider_id)
      priority_by_provider.fetch(provider_id.to_s.strip, 0)
    end

    def cost_for(provider_id)
      cost_minor_by_provider.fetch(provider_id.to_s.strip, 0)
    end

    def latency_for(provider_id)
      latency_ms_by_provider.fetch(provider_id.to_s.strip, 0)
    end

    def to_h
      {
        priority_by_provider: priority_by_provider,
        cost_minor_by_provider: cost_minor_by_provider,
        latency_ms_by_provider: latency_ms_by_provider
      }.freeze
    end

    private

    def normalize_metrics(value, label, allow_zero:)
      unless value.is_a?(Hash)
        raise ArgumentError, "#{label} metrics must be a Hash"
      end

      value.each_with_object({}) do |(provider_id, metric), copy|
        normalized_id = provider_id.to_s.strip
        raise ArgumentError, "provider id must be non-empty" if normalized_id.empty?
        unless metric.is_a?(Integer) && (allow_zero ? metric >= 0 : metric.positive?)
          raise ArgumentError, "#{label} metrics must be non-negative Integers"
        end

        raise ArgumentError, "#{label} metrics contain duplicate provider id" if copy.key?(normalized_id)

        copy[normalized_id.freeze] = metric
      end.freeze
    end
  end

  class RoutingPolicy
    MEASURES = %i[count volume].freeze
    ACCOUNTING_POINTS = %i[primary_assignment].freeze
    WINDOWS = %i[opportunity_cohort policy_epoch].freeze

    attr_reader :id, :epoch, :measure, :targets, :currency, :scope, :accounting_point,
                :window, :tolerance, :minimum_measures, :maximum_measures,
                :minimum_shares, :maximum_shares, :recovery, :recovery_objective, :ranking,
                :hard_constraints, :soft_constraints, :selector, :fingerprint

    def initialize(id:, epoch:, measure:, targets:, currency: nil, scope: :default,
                   accounting_point: :primary_assignment, window: :opportunity_cohort,
                   max_attempts: 3, tolerance: nil, minimum_measures: nil,
                   maximum_measures: nil, minimum_shares: {}, maximum_shares: {},
                   recovery: nil, recovery_objective: nil, ranking: nil,
                   hard_constraints: nil, soft_constraints: nil,
                   selector: nil)
      @id = normalize_id(id, "policy id")
      @epoch = normalize_id(epoch, "policy epoch")
      @measure = normalize_measure(measure)
      @targets = normalize_targets(targets)
      @currency = normalize_currency(currency)
      @scope = normalize_id(scope, "policy scope")
      @selector = RubyRouting::PolicySelector.from(selector)
      if @currency && @selector.currency && @currency != @selector.currency
        raise ArgumentError, "policy currency does not match selector currency"
      end
      @accounting_point = normalize_symbol(accounting_point, ACCOUNTING_POINTS, "accounting point")
      @window = normalize_symbol(window, WINDOWS, "window")
      # Tolerance is an absolute post-decision L1 discrepancy in this
      # policy's allocation measure units. Count policies therefore measure
      # tolerance in payout-count units; volume policies measure it in exact
      # minor units of `currency`. It is never a normalized share error or a
      # per-provider corridor.
      @tolerance = normalize_tolerance(tolerance)
      @minimum_measures = normalize_measure_limits(minimum_measures || {}, "minimum_measures")
      @maximum_measures = normalize_measure_limits(maximum_measures || {}, "maximum_measures")
      @minimum_shares = normalize_share_limits(minimum_shares, "minimum_shares")
      @maximum_shares = normalize_share_limits(maximum_shares, "maximum_shares")
      @recovery = recovery || RecoveryPolicy.new(max_operations: max_attempts)
      unless @recovery.is_a?(RecoveryPolicy)
        raise ArgumentError, "recovery must be RecoveryPolicy"
      end
      @recovery_objective = recovery_objective || RecoveryObjective.new
      unless @recovery_objective.is_a?(RecoveryObjective)
        raise ArgumentError, "recovery_objective must be RecoveryObjective"
      end
      @ranking = ranking || RankingPolicy.new
      unless @ranking.is_a?(RankingPolicy)
        raise ArgumentError, "ranking must be RankingPolicy"
      end
      @hard_constraints = normalize_constraints(hard_constraints)
      @soft_constraints = normalize_constraints(soft_constraints)

      if @minimum_measures.any? { |provider_id, minimum|
        @maximum_measures.key?(provider_id) && minimum > @maximum_measures.fetch(provider_id)
      }
        raise StaticPolicyInfeasibilityError.new(
          "provider measure minimum cannot exceed maximum",
          reason_codes: [:measure_minimum_above_maximum]
        )
      end

      if @minimum_shares.any? { |provider_id, minimum| minimum > maximum_share_for(provider_id) }
        raise StaticPolicyInfeasibilityError.new(
          "provider share minimum cannot exceed maximum",
          reason_codes: [:share_minimum_above_maximum]
        )
      end

      if @minimum_shares.values.sum > 1
        raise StaticPolicyInfeasibilityError.new(
          "provider share minimums are statically infeasible",
          reason_codes: [:share_minimums_exceed_total]
        )
      end
      if targets.keys.sum { |provider_id| maximum_share_for(provider_id) } < 1
        raise StaticPolicyInfeasibilityError.new(
          "provider share maximums are statically infeasible",
          reason_codes: [:share_maximums_below_total]
        )
      end

      if @measure == :volume && @currency.nil?
        raise ArgumentError, "volume policies require a currency"
      end

      @fingerprint = Digest::SHA256.hexdigest(Marshal.dump(canonical_fingerprint_value(fingerprint_material))).freeze
      freeze
    end

    def max_attempts
      recovery.max_operations
    end

    def to_h
      values = {
        id: id,
        epoch: epoch,
        measure: measure,
        targets: targets,
        currency: currency,
        scope: scope,
        accounting_point: accounting_point,
        window: window,
        tolerance: tolerance,
        minimum_measures: minimum_measures,
        maximum_measures: maximum_measures,
        minimum_shares: minimum_shares,
        maximum_shares: maximum_shares,
        selector: selector.to_h,
        recovery: recovery.to_h,
        ranking: ranking.to_h,
        hard_constraints: hard_constraints.to_h,
        soft_constraints: soft_constraints.to_h
      }
      # The default objective is the historical behavior. Omitting it keeps
      # old durable policy definitions and fingerprints compatible while the
      # typed runtime value makes the current recovery rule explicit.
      values[:recovery_objective] = recovery_objective.to_h unless recovery_objective.default?
      values.freeze
    end

    def static_feasibility
      target_provider_ids = targets.keys
      target_provider_ids &= hard_constraints.allowed_provider_ids if hard_constraints.allowed_provider_ids
      target_provider_ids -= hard_constraints.excluded_provider_ids
      reason_codes = []
      reason_codes << :no_hard_constraint_eligible_target if target_provider_ids.empty?

      ineligible_minimums = minimum_shares.any? do |provider_id, minimum|
        minimum.positive? && !target_provider_ids.include?(provider_id)
      end
      reason_codes << :share_minimum_on_hard_ineligible_target if ineligible_minimums

      if target_provider_ids.any? &&
         target_provider_ids.sum { |provider_id| maximum_share_for(provider_id) } < 1
        reason_codes << :share_maximums_below_hard_constraint_capacity
      end

      {
        status: reason_codes.empty? ? :feasible : :infeasible,
        reason_codes: reason_codes.freeze
      }.freeze
    end

    def scope_key
      [id, epoch, scope].freeze
    end

    # `policy_epoch` keeps one ledger for the immutable policy identity. The
    # `opportunity_cohort` window starts an explicit ledger for each functional
    # target-provider cohort, so a payout that could not legally use a target
    # cannot create hidden debt in a different cohort.
    def allocation_key(opportunity_provider_ids: nil)
      return scope_key if window == :policy_epoch

      cohort = RubyRouting::Collection.to_array(
        opportunity_provider_ids || targets.keys,
        "opportunity_provider_ids"
      ).map { |provider_id| provider_id.to_s.strip }.uniq.select do |provider_id|
        targets.key?(provider_id)
      end.sort.freeze
      [id, epoch, scope, cohort].freeze
    end

    def weight_for(provider_id)
      targets.fetch(provider_id.to_s.strip, 0)
    end

    def weights_for(provider_ids)
      RubyRouting::Collection.to_array(provider_ids, "provider_ids").each_with_object({}) do |provider_id, weights|
        normalized = provider_id.to_s.strip
        weight = weight_for(normalized)
        weights[normalized] = weight if weight.positive?
      end.freeze
    end

    def measure_for(money)
      unless money.is_a?(RubyRouting::Money)
        raise ArgumentError, "measure requires RubyRouting::Money"
      end

      if measure == :count
        1
      else
        unless money.currency == currency
          raise ArgumentError, "policy currency does not match payout currency"
        end
        money.amount_minor
      end
    end

    def applies_to?(intent)
      return false unless intent.is_a?(RubyRouting::PayoutIntent)
      return false if currency && intent.money.currency != currency

      selector.matches?(intent)
    end

    def minimum_measure_for(provider_id)
      minimum_measures.fetch(provider_id.to_s.strip, 0)
    end

    def maximum_measure_for(provider_id)
      maximum_measures.fetch(provider_id.to_s.strip, nil)
    end

    def allows_measure?(provider_id, measure)
      return false if measure < minimum_measure_for(provider_id)

      maximum = maximum_measure_for(provider_id)
      maximum.nil? || measure <= maximum
    end

    def measure_exclusions(provider_ids, measure)
      RubyRouting::Collection.to_array(provider_ids, "provider_ids").each_with_object({}) do |provider_id, exclusions|
        normalized = provider_id.to_s.strip
        exclusions[normalized] = :policy_measure_constraint unless
          allows_measure?(provider_id, measure)
      end.freeze
    end

    def minimum_share_for(provider_id)
      minimum_shares.fetch(provider_id.to_s.strip, Rational(0, 1))
    end

    def maximum_share_for(provider_id)
      maximum_shares.fetch(provider_id.to_s.strip, Rational(1, 1))
    end

    # Returns only positive exact violations. Share obligations are part of
    # allocation authority; when indivisible work makes the corridor
    # impossible, the caller can choose the least-violating state and expose
    # the typed deviation instead of silently dropping the obligation.
    def share_violations(measures, total_measure: nil, provider_ids: targets.keys)
      unless measures.is_a?(Hash)
        raise ArgumentError, "measures must be a Hash"
      end

      total = total_measure || measures.values.sum
      unless total.is_a?(Integer) && total >= 0
        raise ArgumentError, "total_measure must be a non-negative Integer"
      end
      return {}.freeze if total.zero?

      RubyRouting::Collection.to_array(provider_ids, "provider_ids").map { |provider_id| provider_id.to_s.strip }.uniq.sort.each_with_object({}) do |provider_id, violations|
        share = Rational(measures.fetch(provider_id, 0), total)
        provider_violations = {}
        minimum = minimum_share_for(provider_id)
        maximum = maximum_share_for(provider_id)
        provider_violations[:minimum] = minimum - share if share < minimum
        provider_violations[:maximum] = share - maximum if share > maximum
        violations[provider_id] = provider_violations.freeze unless provider_violations.empty?
      end.freeze
    end

    private

    def normalize_id(value, label)
      unless value.is_a?(String) || value.is_a?(Symbol)
        raise ArgumentError, "#{label} must be a non-empty String or Symbol"
      end

      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized.freeze
    end

    def normalize_measure(value)
      RubyRouting::Enum.normalize(value, MEASURES, "measure")
    end

    def normalize_targets(value)
      unless value.is_a?(Hash) && !value.empty?
        raise ArgumentError, "targets must be a non-empty Hash"
      end

      normalized = value.each_with_object({}) do |(provider_id, weight), copy|
        id = normalize_id(provider_id, "provider id")
        unless weight.is_a?(Integer) && weight.positive?
          raise ArgumentError, "provider weights must be positive Integers"
        end
        raise ArgumentError, "duplicate provider id" if copy.key?(id)

        copy[id] = weight
      end
      normalized.freeze
    end

    def normalize_currency(value)
      return nil if value.nil?
      unless value.is_a?(String)
        raise ArgumentError, "currency must be a String"
      end

      normalized = value.strip.upcase
      unless /\A[A-Z]{3}\z/.match?(normalized)
        raise ArgumentError, "currency must be a three-letter code"
      end

      normalized.freeze
    end

    def normalize_symbol(value, allowed, label)
      RubyRouting::Enum.normalize(value, allowed, label)
    end

    def normalize_tolerance(value)
      return nil if value.nil?
      return value if value.is_a?(Rational) && value >= 0
      return Rational(value, 1) if value.is_a?(Integer) && value >= 0
      if value.is_a?(String)
        parsed = Rational(value)
        return parsed if parsed >= 0
      end

      raise ArgumentError, "tolerance must be a non-negative Integer, Rational, String or nil"
    rescue ArgumentError, ZeroDivisionError
      raise ArgumentError, "tolerance must be a non-negative Integer, Rational, String or nil"
    end

    def normalize_measure_limits(value, label)
      unless value.is_a?(Hash)
        raise ArgumentError, "#{label} must be a Hash"
      end

      value.each_with_object({}) do |(provider_id, measure), copy|
        normalized_id = normalize_id(provider_id, "provider id")
        unless measure.is_a?(Integer) && measure >= 0
          raise ArgumentError, "#{label} must contain non-negative Integer measures"
        end

        raise ArgumentError, "#{label} contain duplicate provider id" if copy.key?(normalized_id)

        copy[normalized_id] = measure
      end.freeze
    end

    def normalize_share_limits(value, label)
      unless value.is_a?(Hash)
        raise ArgumentError, "#{label} must be a Hash"
      end

      value.each_with_object({}) do |(provider_id, share), copy|
        normalized_id = normalize_id(provider_id, "provider id")
        unless targets.key?(normalized_id)
          raise ArgumentError, "#{label} references an unknown target provider"
        end

        raise ArgumentError, "#{label} contain duplicate provider id" if copy.key?(normalized_id)

        copy[normalized_id] = normalize_share(share, label)
      end.freeze
    end

    def normalize_share(value, label)
      normalized = case value
      when Rational
        value
      when Integer
        Rational(value, 1)
      when String
        Rational(value)
      end
      unless normalized && normalized >= 0 && normalized <= 1
        raise ArgumentError, "#{label} must contain exact shares between 0 and 1"
      end

      normalized
    rescue ArgumentError, ZeroDivisionError
      raise ArgumentError, "#{label} must contain exact shares between 0 and 1"
    end

    def fingerprint_material
      material = [
        id,
        epoch,
        measure,
        targets.sort,
        currency,
        scope,
        accounting_point,
        window,
        tolerance,
        minimum_measures.sort,
        maximum_measures.sort,
        minimum_shares.sort,
        maximum_shares.sort,
        recovery.to_h,
        ranking_material,
        constraints_material(hard_constraints),
        constraints_material(soft_constraints)
      ]
      material << recovery_objective.to_h unless recovery_objective.default?
      material << selector.to_h unless selector.empty?
      material
    end

    def ranking_material
      {
        priority_by_provider: ranking.priority_by_provider.sort,
        cost_minor_by_provider: ranking.cost_minor_by_provider.sort,
        latency_ms_by_provider: ranking.latency_ms_by_provider.sort
      }
    end

    def constraints_material(constraints)
      values = constraints.to_h
      {
        allowed_provider_ids: values.fetch(:allowed_provider_ids)&.sort,
        excluded_provider_ids: values.fetch(:excluded_provider_ids).sort,
        required_context_labels: values.fetch(:required_context_labels).sort,
        minimum_amount_minor: values.fetch(:minimum_amount_minor),
        maximum_amount_minor: values.fetch(:maximum_amount_minor)
      }
    end

    # Marshal includes a String's encoding, although routing policy identity
    # is about the definition's value rather than whether a caller supplied an
    # ASCII-only literal as US-ASCII or UTF-8. Durable JSON round-trips choose
    # their own string encoding, so canonicalize before hashing to keep the
    # immutable policy fingerprint stable across restart.
    def canonical_fingerprint_value(value)
      case value
      when String
        value.encode(Encoding::UTF_8)
      when Array
        value.map { |nested| canonical_fingerprint_value(nested) }
      when Hash
        value.map do |key, nested|
          [canonical_fingerprint_value(key), canonical_fingerprint_value(nested)]
        end.sort_by { |entry| Marshal.dump(entry.first) }
      else
        value
      end
    end

    def normalize_constraints(value)
      return RoutingConstraints.new if value.nil?
      return value if value.is_a?(RoutingConstraints)
      return RoutingConstraints.new(**value) if value.is_a?(Hash)

      raise ArgumentError, "constraints must be RoutingConstraints, Hash or nil"
    end
  end
end
