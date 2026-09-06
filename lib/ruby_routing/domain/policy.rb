# frozen_string_literal: true

module RubyRouting
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
        labels = context_labels(intent.context)
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
      unless value.respond_to?(:map)
        raise ArgumentError, "#{label} must be enumerable or nil"
      end

      value.map do |provider_id|
        normalized = provider_id.to_s.strip
        raise ArgumentError, "#{label} must contain non-empty ids" if normalized.empty?

        normalized.freeze
      end.uniq.freeze
    end

    def normalize_labels(value)
      unless value.respond_to?(:map)
        raise ArgumentError, "required_context_labels must be enumerable"
      end

      value.map do |label|
        normalized = label.to_s.strip
        raise ArgumentError, "context labels must be non-empty" if normalized.empty?

        normalized.freeze
      end.uniq.freeze
    end

    def normalize_limit(value, label)
      return nil if value.nil?
      unless value.is_a?(Integer) && value >= 0
        raise ArgumentError, "#{label} must be a non-negative Integer or nil"
      end

      value
    end

    def context_labels(context)
      return [] unless context.is_a?(Hash)

      raw = context[:labels] || context["labels"] || []
      Array(raw).map(&:to_s)
    end
  end

  class RecoveryPolicy
    attr_reader :max_operations, :max_switches, :max_resolution_interactions,
                :ttl_seconds, :deadline_seconds

    def initialize(max_operations: 3, max_switches: 2, max_resolution_interactions: nil,
                   ttl_seconds: nil, deadline_seconds: nil)
      @max_operations = normalize_positive(max_operations, "max_operations")
      @max_switches = normalize_non_negative(max_switches, "max_switches")
      max_resolution_interactions ||= [@max_operations - 1, 0].max
      @max_resolution_interactions = normalize_non_negative(
        max_resolution_interactions,
        "max_resolution_interactions"
      )
      @ttl_seconds = normalize_positive_or_nil(ttl_seconds, "ttl_seconds")
      @deadline_seconds = normalize_positive_or_nil(deadline_seconds, "deadline_seconds")
      freeze
    end

    def to_h
      {
        max_operations: max_operations,
        max_switches: max_switches,
        max_resolution_interactions: max_resolution_interactions,
        ttl_seconds: ttl_seconds,
        deadline_seconds: deadline_seconds
      }.freeze
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
      priority_by_provider.fetch(provider_id.to_s, 0)
    end

    def cost_for(provider_id)
      cost_minor_by_provider.fetch(provider_id.to_s, 0)
    end

    def latency_for(provider_id)
      latency_ms_by_provider.fetch(provider_id.to_s, 0)
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

        copy[normalized_id.freeze] = metric
      end.freeze
    end
  end

  class RoutingPolicy
    MEASURES = %i[count volume].freeze
    ACCOUNTING_POINTS = %i[primary_assignment].freeze
    WINDOWS = %i[opportunity_cohort policy_epoch].freeze

    attr_reader :id, :epoch, :measure, :targets, :currency, :scope, :accounting_point,
                :window, :tolerance, :minimums, :maximums, :recovery, :ranking,
                :hard_constraints, :soft_constraints, :fingerprint

    def initialize(id:, epoch:, measure:, targets:, currency: nil, scope: :default,
                   accounting_point: :primary_assignment, window: :opportunity_cohort,
                   max_attempts: 3, tolerance: nil, minimums: {}, maximums: {},
                   recovery: nil, ranking: nil, hard_constraints: nil, soft_constraints: nil)
      @id = normalize_id(id, "policy id")
      @epoch = normalize_id(epoch, "policy epoch")
      @measure = normalize_measure(measure)
      @targets = normalize_targets(targets)
      @currency = normalize_currency(currency)
      @scope = normalize_id(scope, "policy scope")
      @accounting_point = normalize_symbol(accounting_point, ACCOUNTING_POINTS, "accounting point")
      @window = normalize_symbol(window, WINDOWS, "window")
      @tolerance = normalize_tolerance(tolerance)
      @minimums = normalize_measure_limits(minimums, "minimums")
      @maximums = normalize_measure_limits(maximums, "maximums")
      @recovery = recovery || RecoveryPolicy.new(max_operations: max_attempts)
      unless @recovery.is_a?(RecoveryPolicy)
        raise ArgumentError, "recovery must be RecoveryPolicy"
      end
      @ranking = ranking || RankingPolicy.new
      unless @ranking.is_a?(RankingPolicy)
        raise ArgumentError, "ranking must be RankingPolicy"
      end
      @hard_constraints = normalize_constraints(hard_constraints)
      @soft_constraints = normalize_constraints(soft_constraints)

      if @minimums.any? { |provider_id, minimum| @maximums.key?(provider_id) && minimum > @maximums.fetch(provider_id) }
        raise ArgumentError, "provider minimum cannot exceed maximum"
      end

      if @measure == :volume && @currency.nil?
        raise ArgumentError, "volume policies require a currency"
      end

      @fingerprint = Digest::SHA256.hexdigest(Marshal.dump(fingerprint_material)).freeze
      freeze
    end

    def max_attempts
      recovery.max_operations
    end

    def to_h
      {
        id: id,
        epoch: epoch,
        measure: measure,
        targets: targets,
        currency: currency,
        scope: scope,
        accounting_point: accounting_point,
        window: window,
        tolerance: tolerance,
        minimums: minimums,
        maximums: maximums,
        recovery: recovery.to_h,
        ranking: ranking.to_h,
        hard_constraints: hard_constraints.to_h,
        soft_constraints: soft_constraints.to_h
      }.freeze
    end

    def scope_key
      [id, epoch, scope].freeze
    end

    # `opportunity_cohort` keeps one ledger for the policy identity while the
    # current functional opportunity set controls the live denominator. The
    # provisional `policy_epoch` window uses the same immutable epoch ledger;
    # the explicit value keeps the future TZ mapping from being implicit.
    def allocation_key
      scope_key
    end

    def weight_for(provider_id)
      targets.fetch(provider_id.to_s, 0)
    end

    def weights_for(provider_ids)
      provider_ids.each_with_object({}) do |provider_id, weights|
        normalized = provider_id.to_s
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

    def minimum_for(provider_id)
      minimums.fetch(provider_id.to_s, 0)
    end

    def maximum_for(provider_id)
      maximums.fetch(provider_id.to_s, nil)
    end

    def allows_measure?(provider_id, measure)
      return false if measure < minimum_for(provider_id)

      maximum = maximum_for(provider_id)
      maximum.nil? || measure <= maximum
    end

    def measure_exclusions(provider_ids, measure)
      provider_ids.each_with_object({}) do |provider_id, exclusions|
        exclusions[provider_id.to_s] = :policy_measure_constraint unless
          allows_measure?(provider_id, measure)
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
      normalized = value.to_sym
      raise ArgumentError, "measure must be count or volume" unless MEASURES.include?(normalized)

      normalized
    rescue NoMethodError
      raise ArgumentError, "measure must be count or volume"
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
      normalized = value.to_sym
      raise ArgumentError, "unsupported #{label}" unless allowed.include?(normalized)

      normalized
    rescue NoMethodError
      raise ArgumentError, "unsupported #{label}"
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

        copy[normalized_id] = measure
      end.freeze
    end

    def fingerprint_material
      [
        id,
        epoch,
        measure,
        targets.sort,
        currency,
        scope,
        accounting_point,
        window,
        tolerance,
        minimums.sort,
        maximums.sort,
        recovery.to_h,
        ranking_material,
        constraints_material(hard_constraints),
        constraints_material(soft_constraints)
      ]
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

    def normalize_constraints(value)
      return RoutingConstraints.new if value.nil?
      return value if value.is_a?(RoutingConstraints)
      return RoutingConstraints.new(**value) if value.is_a?(Hash)

      raise ArgumentError, "constraints must be RoutingConstraints, Hash or nil"
    end
  end
end
