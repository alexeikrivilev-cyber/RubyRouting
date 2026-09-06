# frozen_string_literal: true

module RubyRouting
  module Case
    class TrafficTargets
      attr_reader :provider_ids, :count_share, :volume_share

      def initialize(provider_ids:, count_share: {}, volume_share: {})
        @provider_ids = normalize_provider_ids(provider_ids)
        @count_share = normalize_targets(count_share, "count_share")
        @volume_share = normalize_targets(volume_share, "volume_share")
        raise InputError, "count_share targets must sum to at most one" if @count_share.values.sum > 1
        raise InputError, "volume_share targets must sum to at most one" if @volume_share.values.sum > 1
        freeze
      end

      private

      def normalize_provider_ids(value)
        unless value.is_a?(Array) && value.all? { |id| id.is_a?(String) || id.is_a?(Symbol) }
          raise InputError, "traffic target provider ids must be an Array of String or Symbol"
        end
        ids = value.map { |id| Input.assert_id(id, "traffic target provider id") }
        raise InputError, "traffic target provider ids contain duplicates" unless ids.uniq.length == ids.length
        raise InputError, "traffic target provider ids must be non-empty" if ids.any?(&:empty?)

        ids.sort.freeze
      end

      def normalize_targets(value, label)
        raise InputError, "#{label} must be a Hash" unless value.is_a?(Hash)
        unless value.keys.all? { |key| key.is_a?(String) || key.is_a?(Symbol) }
          raise InputError, "#{label} provider keys must be String or Symbol"
        end
        canonical_keys = value.keys.map { |key| Input.assert_id(key, "#{label} provider id") }
        raise InputError, "#{label} contains duplicate providers" unless canonical_keys.uniq.length == canonical_keys.length
        unknown = canonical_keys - @provider_ids
        raise InputError, "#{label} contains unknown providers: #{unknown.join(', ')}" unless unknown.empty?
        canonical_values = value.each_with_object({}) do |(key, raw), result|
          result[Input.assert_id(key, "#{label} provider id")] = raw
        end
        @provider_ids.each_with_object({}) do |provider_id, result|
          raw = canonical_values.fetch(provider_id, Rational(0, 1))
          unless raw.is_a?(Integer) || raw.is_a?(Rational)
            raise InputError, "#{label} values must be exact Integer or Rational"
          end
          raise InputError, "#{label} values must be non-negative" if raw.negative?
          raise InputError, "#{label} values must be at most one" if raw > 1
          result[provider_id] = raw
        end.freeze
      end
    end

    class TrafficLedger
      attr_reader :provider_ids, :targets, :total_count, :total_volume

      def initialize(provider_ids, targets: TrafficTargets.new(provider_ids: provider_ids))
        unless provider_ids.is_a?(Array) && provider_ids.all? { |id| id.is_a?(String) || id.is_a?(Symbol) }
          raise InputError, "traffic ledger provider ids must be an Array of String or Symbol"
        end
        ids = provider_ids.map { |id| Input.assert_id(id, "traffic ledger provider id") }
        raise InputError, "traffic ledger requires at least one provider" if ids.empty?
        raise InputError, "traffic ledger provider ids contain duplicates" unless ids.uniq.length == ids.length
        @provider_ids = ids.sort.freeze
        raise InputError, "traffic ledger targets must be TrafficTargets" unless targets.is_a?(TrafficTargets)
        unless targets.provider_ids == @provider_ids
          raise InputError, "traffic ledger target provider ids do not match"
        end
        @targets = targets
        @count_by_provider = @provider_ids.to_h { |provider_id| [provider_id, 0] }
        @volume_by_provider = @provider_ids.to_h { |provider_id| [provider_id, 0] }
        @total_count = 0
        @total_volume = 0
      end

      def count_by_provider
        @count_by_provider.dup.freeze
      end

      def volume_by_provider
        @volume_by_provider.dup.freeze
      end

      # This ledger is the routing-target authority: record the final selected
      # provider once the operation's fallback cascade is complete. Primary
      # assignments are kept in a separate ledger by the Case Router.
      def record_assignment!(provider_id:, amount:)
        provider_id = provider_key(provider_id)
        raise InputError, "traffic amount must be a positive Integer" unless amount.is_a?(Integer) && amount.positive?
        @count_by_provider[provider_id] += 1
        @volume_by_provider[provider_id] += amount
        @total_count += 1
        @total_volume += amount
        nil
      end

      # Kept as a compatibility alias for direct factor/ledger callers. New
      # routing code should use the semantically explicit name above.
      alias record! record_assignment!

      def share(measure, provider_id)
        values = measure_values(measure)
        provider_id = provider_key(provider_id)
        denominator = measure == :count ? total_count : total_volume
        return Rational(0, 1) if denominator.zero?
        Rational(values.fetch(provider_id), denominator)
      end

      def counterfactual(provider_id:, amount:)
        provider_id = provider_key(provider_id)
        raise InputError, "traffic amount must be a positive Integer" unless amount.is_a?(Integer) && amount.positive?
        post_count = @total_count + 1
        post_volume = @total_volume + amount
        post_count_value = @count_by_provider.fetch(provider_id) + 1
        post_volume_value = @volume_by_provider.fetch(provider_id) + amount
        {
          provider: provider_id,
          count: {
            before: @count_by_provider.fetch(provider_id), after: post_count_value,
            total_after: post_count, share_after: Rational(post_count_value, post_count),
            target: @targets.count_share.fetch(provider_id),
            deficit_after: @targets.count_share.fetch(provider_id) - Rational(post_count_value, post_count)
          },
          volume: {
            before: @volume_by_provider.fetch(provider_id), after: post_volume_value,
            total_after: post_volume, share_after: Rational(post_volume_value, post_volume),
            target: @targets.volume_share.fetch(provider_id),
            deficit_after: @targets.volume_share.fetch(provider_id) - Rational(post_volume_value, post_volume)
          }
        }.freeze
      end

      # Return the exact post-decision portfolio loss for one hypothetical
      # assignment. Unlike `counterfactual`, this evaluates every configured
      # provider against the target distribution, not only the candidate being
      # considered. The resolver turns the loss into a higher-is-better raw
      # factor by negating it.
      def post_decision_loss(measure:, provider_id:, amount:)
        provider_id = provider_key(provider_id)
        raise InputError, "traffic amount must be a positive Integer" unless amount.is_a?(Integer) && amount.positive?

        values = measure_values(measure).dup
        if measure == :count
          values[provider_id] += 1
          total = @total_count + 1
          target_values = @targets.count_share
        elsif measure == :volume
          values[provider_id] += amount
          total = @total_volume + amount
          target_values = @targets.volume_share
        else
          raise InputError, "unsupported traffic measure #{measure.inspect}"
        end

        target_values.sum do |candidate_id, target|
          (Rational(values.fetch(candidate_id), total) - target).abs
        end
      end

      def distribution
        @provider_ids.each_with_object({}) do |provider_id, result|
          result[provider_id] = {
            count: @count_by_provider.fetch(provider_id),
            volume: @volume_by_provider.fetch(provider_id),
            count_share: share(:count, provider_id),
            volume_share: share(:volume, provider_id),
            target_count_share: @targets.count_share.fetch(provider_id),
            target_volume_share: @targets.volume_share.fetch(provider_id),
            count_deviation: share(:count, provider_id) - @targets.count_share.fetch(provider_id),
            volume_deviation: share(:volume, provider_id) - @targets.volume_share.fetch(provider_id)
          }.freeze
        end.freeze
      end

      private

      def measure_values(measure)
        case measure
        when :count then @count_by_provider
        when :volume then @volume_by_provider
        else raise InputError, "unsupported traffic measure #{measure.inspect}"
        end
      end

      def provider_key(value)
        provider_id = Input.assert_id(value, "traffic provider id")
        raise InputError, "unknown traffic provider #{provider_id}" unless @provider_ids.include?(provider_id)

        provider_id
      end
    end

    class ProviderAmountLedger
      attr_reader :provider_ids, :total_count, :total_volume

      def initialize(provider_ids)
        unless provider_ids.is_a?(Array) && provider_ids.all? { |id| id.is_a?(String) || id.is_a?(Symbol) }
          raise InputError, "provider ledger ids must be an Array of String or Symbol"
        end
        ids = provider_ids.map { |id| Input.assert_id(id, "provider ledger id") }
        raise InputError, "provider ledger requires at least one provider" if ids.empty?
        raise InputError, "provider ledger provider ids contain duplicates" unless ids.uniq.length == ids.length
        @provider_ids = ids.sort.freeze
        @count_by_provider = @provider_ids.to_h { |provider_id| [provider_id, 0] }
        @volume_by_provider = @provider_ids.to_h { |provider_id| [provider_id, 0] }
        @total_count = 0
        @total_volume = 0
      end

      def count_by_provider
        @count_by_provider.dup.freeze
      end

      def volume_by_provider
        @volume_by_provider.dup.freeze
      end

      def record!(provider_id:, amount:)
        provider_id = provider_key(provider_id)
        raise InputError, "provider ledger amount must be a positive Integer" unless amount.is_a?(Integer) && amount.positive?

        @count_by_provider[provider_id] += 1
        @volume_by_provider[provider_id] += amount
        @total_count += 1
        @total_volume += amount
        nil
      end

      def share(measure, provider_id)
        values = measure == :count ? @count_by_provider : @volume_by_provider
        unless %i[count volume].include?(measure)
          raise InputError, "unsupported provider ledger measure #{measure.inspect}"
        end
        provider_id = provider_key(provider_id)
        denominator = measure == :count ? total_count : total_volume
        return Rational(0, 1) if denominator.zero?

        Rational(values.fetch(provider_id), denominator)
      end

      def distribution
        @provider_ids.each_with_object({}) do |provider_id, result|
          result[provider_id] = {
            count: @count_by_provider.fetch(provider_id),
            volume: @volume_by_provider.fetch(provider_id),
            count_share: share(:count, provider_id),
            volume_share: share(:volume, provider_id)
          }.freeze
        end.freeze
      end

      private

      def provider_key(value)
        provider_id = Input.assert_id(value, "provider ledger provider id")
        raise InputError, "unknown provider ledger provider #{provider_id}" unless @provider_ids.include?(provider_id)

        provider_id
      end
    end

    class AttemptLedger < ProviderAmountLedger
      STATUSES = %i[approved rejected expired].freeze

      attr_reader :outcome_counts

      def initialize(provider_ids)
        super
        @outcome_counts = STATUSES.to_h { |status| [status, 0] }
        @outcome_by_provider = @provider_ids.to_h do |provider_id|
          [provider_id, STATUSES.to_h { |status| [status, 0] }]
        end
      end

      def record!(provider_id:, amount:, status:)
        status = status.to_sym if status.is_a?(String) || status.is_a?(Symbol)
        raise InputError, "unsupported attempt outcome #{status.inspect}" unless STATUSES.include?(status)

        super(provider_id: provider_id, amount: amount)
        @outcome_counts[status] += 1
        @outcome_by_provider.fetch(Input.assert_id(provider_id, "attempt provider"))[status] += 1
        nil
      end

      def by_outcome
        @outcome_counts.dup.freeze
      end

      def distribution
        base = super
        @provider_ids.each_with_object({}) do |provider_id, result|
          result[provider_id] = base.fetch(provider_id).merge(
            outcomes: @outcome_by_provider.fetch(provider_id).dup.freeze
          ).freeze
        end.freeze
      end
    end

    class SettlementLedger < ProviderAmountLedger
      def record!(provider_id:, amount:)
        super(provider_id: provider_id, amount: amount)
      end
    end
  end
end
