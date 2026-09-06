# frozen_string_literal: true

module RubyRouting
  module Case
    class CaseConfiguration
      KEYS = %i[
        provider_ids count_share volume_share weights min_turnovers rpm_limits
        rpm_window_seconds terminal_provider_id simulation_seed simulation_mode
        preferred_amount_ranges source revision
      ].freeze

      attr_reader :provider_ids, :targets, :weights, :min_turnovers, :rpm_limits,
                  :rpm_window_seconds, :terminal_provider_id, :simulation_seed,
                  :simulation_mode, :preferred_amount_ranges, :source, :revision

      def initialize(provider_ids:, targets: nil, count_share: {}, volume_share: {},
                     weights: RoutingWeights.new, min_turnovers: {}, rpm_limits: {},
                     rpm_window_seconds: 60, terminal_provider_id: nil,
                     simulation_seed: "ruby-routing-v0.4", simulation_mode: :approved,
                     preferred_amount_ranges: {},
                     source: "case-defaults", revision: 1)
        @provider_ids = self.class.normalize_provider_ids(provider_ids)
        unless targets.nil? || targets.is_a?(TrafficTargets)
          raise InputError, "case configuration targets must be TrafficTargets"
        end
        if targets && (!count_share.is_a?(Hash) || !volume_share.is_a?(Hash) ||
                       !count_share.empty? || !volume_share.empty?)
          raise InputError, "case configuration targets cannot be combined with count_share or volume_share"
        end
        @targets = targets || TrafficTargets.new(
          provider_ids: @provider_ids, count_share: count_share, volume_share: volume_share
        )
        unless @targets.provider_ids == @provider_ids
          raise InputError, "case configuration target provider ids do not match"
        end
        @weights = weights.is_a?(RoutingWeights) ? weights : RoutingWeights.new(weights)
        @min_turnovers = exact_provider_numbers(min_turnovers, "min_turnovers")
        @rpm_limits = exact_provider_numbers(rpm_limits, "rpm_limits")
        unless rpm_window_seconds.is_a?(Integer) && rpm_window_seconds.positive?
          raise InputError, "rpm_window_seconds must be a positive Integer"
        end
        @rpm_window_seconds = rpm_window_seconds
        @preferred_amount_ranges = normalize_preferred_amount_ranges(preferred_amount_ranges)
        unless terminal_provider_id.nil? || terminal_provider_id.is_a?(String) || terminal_provider_id.is_a?(Symbol)
          raise InputError, "terminal_provider_id must be a String or Symbol"
        end
        @terminal_provider_id = terminal_provider_id.nil? ? nil : Input.assert_id(terminal_provider_id, "terminal_provider_id")
        if @terminal_provider_id && !@provider_ids.include?(@terminal_provider_id)
          raise InputError, "terminal_provider_id is not in provider ids"
        end
        @simulation_seed = Input.assert_string(simulation_seed, "simulation_seed").freeze
        unless simulation_mode.is_a?(String) || simulation_mode.is_a?(Symbol)
          raise InputError, "simulation_mode must be a String or Symbol"
        end
        @simulation_mode = Input.assert_one_of(simulation_mode.to_s, %w[approved conversion], "simulation_mode").to_sym
        @source = Input.assert_string(source, "configuration source").freeze
        @revision = Input.assert_integer(revision, "configuration revision", min: 1)
        freeze
      end

      def self.default(provider_ids)
        new(provider_ids: provider_ids)
      end

      def self.from(value, provider_ids:)
        if value.is_a?(self)
          expected = normalize_provider_ids(provider_ids)
          raise InputError, "case configuration provider ids do not match" unless value.provider_ids == expected

          return value
        end
        unless value.is_a?(Hash)
          raise InputError, "case configuration must be a Hash or CaseConfiguration"
        end
        normalized = value.each_with_object({}) do |(key, nested), result|
          unless key.is_a?(String) || key.is_a?(Symbol)
            raise InputError, "case configuration keys must be String or Symbol"
          end
          canonical = KEYS.find { |candidate| candidate.to_s == key.to_s }
          raise InputError, "case configuration contains unsupported key #{key.inspect}" unless canonical
          raise InputError, "case configuration contains duplicate key #{canonical}" if result.key?(canonical)
          result[canonical] = nested
        end
        if normalized.key?(:provider_ids)
          declared = normalize_provider_ids(normalized.delete(:provider_ids))
          expected = normalize_provider_ids(provider_ids)
          raise InputError, "case configuration provider ids do not match" unless declared == expected
        end
        new(provider_ids: provider_ids, **normalized)
      end

      private

      def normalize_preferred_amount_ranges(value)
        unless value.is_a?(Hash)
          raise InputError, "preferred_amount_ranges must be a Hash"
        end
        unless value.keys.all? { |key| key.is_a?(String) || key.is_a?(Symbol) }
          raise InputError, "preferred_amount_ranges provider keys must be String or Symbol"
        end
        canonical_keys = value.keys.map { |key| Input.assert_id(key, "preferred amount provider id") }
        raise InputError, "preferred_amount_ranges contains duplicate providers" unless canonical_keys.uniq.length == canonical_keys.length
        unknown = canonical_keys - @provider_ids
        raise InputError, "preferred_amount_ranges contains unknown providers: #{unknown.join(', ')}" unless unknown.empty?

        value.each_with_object({}) do |(provider_id, range), result|
          unless range.is_a?(Hash)
            raise InputError, "preferred amount range for #{provider_id} must be a Hash"
          end
          canonical_range = range.each_with_object({}) do |(key, amount), normalized|
            field = key.to_s
            unless %w[min max].include?(field)
              raise InputError, "preferred amount range for #{provider_id} contains unsupported field #{key.inspect}"
            end
            field = field.to_sym
            raise InputError, "preferred amount range for #{provider_id} contains duplicate field #{field}" if normalized.key?(field)
            normalized[field] = amount
          end
          unless canonical_range.keys.sort == %i[max min]
            raise InputError, "preferred amount range for #{provider_id} requires min and max"
          end
          low = Input.assert_integer(canonical_range.fetch(:min), "preferred amount min for #{provider_id}", min: 0)
          high = Input.assert_integer(canonical_range.fetch(:max), "preferred amount max for #{provider_id}", min: 0)
          raise InputError, "preferred amount min exceeds max for #{provider_id}" if low > high
          result[Input.assert_id(provider_id, "preferred amount provider id")] = { min: low, max: high }.freeze
        end.freeze
      end

      def self.normalize_provider_ids(value)
        unless value.is_a?(Array) && value.all? { |id| id.is_a?(String) || id.is_a?(Symbol) }
          raise InputError, "case configuration provider ids must be an Array of String or Symbol"
        end
        ids = value.map { |id| Input.assert_id(id, "case configuration provider id") }
        raise InputError, "case configuration requires provider ids" if ids.empty?
        raise InputError, "case configuration provider ids contain duplicates" unless ids.uniq.length == ids.length

        ids.sort.freeze
      end

      def exact_provider_numbers(value, label)
        unless value.is_a?(Hash)
          raise InputError, "#{label} must be a Hash"
        end
        unless value.keys.all? { |key| key.is_a?(String) || key.is_a?(Symbol) }
          raise InputError, "#{label} provider keys must be String or Symbol"
        end
        canonical_keys = value.keys.map { |key| Input.assert_id(key, "#{label} provider id") }
        raise InputError, "#{label} contains duplicate providers" unless canonical_keys.uniq.length == canonical_keys.length
        unknown = canonical_keys - @provider_ids
        raise InputError, "#{label} contains unknown providers: #{unknown.join(', ')}" unless unknown.empty?
        value.each_with_object({}) do |(provider_id, amount), result|
          unless amount.is_a?(Integer) && amount >= 0
            raise InputError, "#{label} values must be non-negative Integers"
          end
          result[Input.assert_id(provider_id, "#{label} provider id")] = amount
        end.freeze
      end

      public

      def to_h
        {
          provider_ids: provider_ids,
          count_share: targets.count_share,
          volume_share: targets.volume_share,
          weights: weights.values,
          min_turnovers: min_turnovers,
          rpm_limits: rpm_limits,
          rpm_window_seconds: rpm_window_seconds,
          terminal_provider_id: terminal_provider_id,
          simulation_seed: simulation_seed,
          simulation_mode: simulation_mode,
          preferred_amount_ranges: preferred_amount_ranges,
          source: source,
          revision: revision
        }.freeze
      end
    end

    # Release policy is data/configuration authority, not a library-default
    # convenience.  The profile derives targets from the loaded dataset and
    # carries enough provenance to make the exact submission run auditable.
    class SubmissionProfile
      REQUIRED_KEYS = %w[
        profile_id source revision count_target_source volume_target_source
        weights simulation_seed simulation_mode terminal_provider_id
      ].freeze
      OPTIONAL_KEYS = %w[
        volume_share preferred_amount_ranges min_turnovers rpm_limits
        rpm_window_seconds
      ].freeze
      TRAFFIC_TARGET_SOURCE = "provider.traffic_percentage"

      attr_reader :profile_id, :source, :revision, :count_target_source,
                  :volume_target_source, :configuration

      def initialize(profile_id:, source:, revision:, count_target_source:,
                     volume_target_source:, configuration:)
        @profile_id = Input.assert_string(profile_id, "submission profile id").freeze
        @source = Input.assert_string(source, "submission profile source").freeze
        @revision = Input.assert_integer(revision, "submission profile revision", min: 1)
        @count_target_source = Input.assert_string(count_target_source, "count target source").freeze
        @volume_target_source = Input.assert_string(volume_target_source, "volume target source").freeze
        unless configuration.is_a?(CaseConfiguration)
          raise InputError, "submission profile configuration must be CaseConfiguration"
        end
        @configuration = configuration
        freeze
      end

      def self.load(path:, dataset:)
        value = Input.load_json(path, "submission profile")
        value = Input.assert_hash(value, "submission profile root")
        Input.keys!(value, required: REQUIRED_KEYS, optional: OPTIONAL_KEYS, context: "submission profile root")

        provider_ids = dataset.providers.map(&:payment_system)
        profile_id = Input.assert_string(value.fetch("profile_id"), "submission profile id")
        source = Input.assert_string(value.fetch("source"), "submission profile source")
        raise InputError, "submission profile id must be non-empty" if profile_id.empty?
        raise InputError, "submission profile source must be non-empty" if source.empty?
        revision = Input.assert_integer(value.fetch("revision"), "submission profile revision", min: 1)
        count_source = Input.assert_string(value.fetch("count_target_source"), "count target source")
        volume_source = Input.assert_string(value.fetch("volume_target_source"), "volume target source")
        unless count_source == TRAFFIC_TARGET_SOURCE
          raise InputError, "unsupported count target source #{count_source.inspect}"
        end
        unless [TRAFFIC_TARGET_SOURCE, "configured"].include?(volume_source)
          raise InputError, "unsupported volume target source #{volume_source.inspect}"
        end

        count_share = traffic_targets(dataset)
        volume_share = if volume_source == TRAFFIC_TARGET_SOURCE
          if value.key?("volume_share")
            raise InputError, "volume_share must not be supplied when volume target source is #{TRAFFIC_TARGET_SOURCE}"
          end
          count_share
        else
          unless value.key?("volume_share")
            raise InputError, "configured volume target source requires volume_share"
          end
          value.fetch("volume_share")
        end
        configuration = CaseConfiguration.new(
          provider_ids: provider_ids,
          count_share: count_share,
          volume_share: volume_share,
          weights: value.fetch("weights"),
          preferred_amount_ranges: value.fetch("preferred_amount_ranges", {}),
          min_turnovers: value.fetch("min_turnovers", {}),
          rpm_limits: value.fetch("rpm_limits", {}),
          rpm_window_seconds: value.fetch("rpm_window_seconds", 60),
          terminal_provider_id: value.fetch("terminal_provider_id"),
          simulation_seed: value.fetch("simulation_seed"),
          simulation_mode: value.fetch("simulation_mode"),
          source: source,
          revision: revision
        )
        terminal = dataset.providers.find { |provider| provider.payment_system == configuration.terminal_provider_id }
        unless terminal&.active? && terminal.self_provider?
          raise InputError, "submission profile terminal provider must be an active self-provider"
        end
        if configuration.weights.values.fetch(:count, Rational(0, 1)).positive? &&
           configuration.targets.count_share.values.none?(&:positive?)
          raise InputError, "positive count weight requires a non-zero count target"
        end
        if configuration.weights.values.fetch(:volume, Rational(0, 1)).positive? &&
           configuration.targets.volume_share.values.none?(&:positive?)
          raise InputError, "positive volume weight requires a non-zero volume target"
        end
        new(
          profile_id: profile_id, source: source, revision: revision,
          count_target_source: count_source, volume_target_source: volume_source,
          configuration: configuration
        )
      rescue KeyError => error
        raise InputError, "submission profile missing field #{error.key}"
      end

      def self.traffic_targets(dataset)
        dataset.providers.each_with_object({}) do |provider, result|
          participating = provider.active? && !provider.self_provider? && provider.traffic_percentage.positive?
          result[provider.payment_system] = participating ? Rational(provider.traffic_percentage, 100) : Rational(0, 1)
        end
      end

      def to_h
        {
          profile_id: profile_id,
          source: source,
          revision: revision,
          count_target_source: count_target_source,
          volume_target_source: volume_target_source,
          configuration: configuration.to_h
        }.freeze
      end
    end
  end
end
