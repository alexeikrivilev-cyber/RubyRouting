# frozen_string_literal: true

module RubyRouting
  module Routing
    # Slow provider quality is deliberately independent from fast operational
    # health. Only mature provider-attributed success/failure outcomes enter
    # this estimate; pending, UNKNOWN and recipient/downstream outcomes are
    # neutral evidence.
    class QualityPolicy
      attr_reader :minimum_samples

      def initialize(minimum_samples: 1)
        unless minimum_samples.is_a?(Integer) && minimum_samples.positive?
          raise ArgumentError, "minimum_samples must be a positive Integer"
        end

        @minimum_samples = minimum_samples
        freeze
      end

      def to_h
        { minimum_samples: minimum_samples }.freeze
      end
    end

    class ProviderQualitySnapshot
      EVIDENCE_SCOPES = %i[global context].freeze

      attr_reader :provider_id, :successful_samples, :failed_samples, :minimum_samples,
                  :context_key, :evidence_scope

      def initialize(provider_id:, successful_samples: 0, failed_samples: 0, minimum_samples: 1,
                     context_key: [], evidence_scope: :global)
        normalized_provider_id = provider_id.to_s.strip
        raise ArgumentError, "provider id must be non-empty" if normalized_provider_id.empty?

        @provider_id = normalized_provider_id.freeze
        @successful_samples = normalize_non_negative_integer(successful_samples, "successful_samples")
        @failed_samples = normalize_non_negative_integer(failed_samples, "failed_samples")
        @minimum_samples = normalize_positive_integer(minimum_samples, "minimum_samples")
        @context_key = normalize_context_key(context_key)
        @evidence_scope = normalize_enum(evidence_scope, EVIDENCE_SCOPES, "quality evidence scope")
        freeze
      end

      def sample_count
        successful_samples + failed_samples
      end

      def mature?
        sample_count >= minimum_samples
      end

      def score
        return Rational(1, 2) unless mature?

        Rational(successful_samples, sample_count)
      end

      def confidence
        mature? ? sample_count : 0
      end

      def to_h
        {
          provider_id: provider_id,
          successful_samples: successful_samples,
          failed_samples: failed_samples,
          sample_count: sample_count,
          mature: mature?,
          score: score,
          confidence: confidence,
          minimum_samples: minimum_samples,
          context_key: context_key,
          evidence_scope: evidence_scope
        }.freeze
      end

      private

      def normalize_non_negative_integer(value, label)
        unless value.is_a?(Integer) && value >= 0
          raise ArgumentError, "#{label} must be a non-negative Integer"
        end

        value
      end

      def normalize_positive_integer(value, label)
        unless value.is_a?(Integer) && value.positive?
          raise ArgumentError, "#{label} must be a positive Integer"
        end

        value
      end

      def normalize_context_key(value)
        RubyRouting::Collection.to_array(value, "context_key").map do |label|
          normalized = label.to_s.strip
          raise ArgumentError, "context_key labels must be non-empty" if normalized.empty?

          normalized
        end.uniq.sort.freeze
      end

      def normalize_enum(value, allowed, label)
        RubyRouting::Enum.normalize(value, allowed, label)
      end
    end

    class QualityController
      def initialize(policy: QualityPolicy.new)
        unless policy.is_a?(QualityPolicy)
          raise ArgumentError, "policy must be QualityPolicy"
        end

        @policy = policy
        @states = {}
      end

      attr_reader :policy

      def snapshot(provider_id, context: nil, context_key: nil)
        normalized_provider_id = normalize_provider_id(provider_id)
        requested_key = normalize_context_key(context_key || context)
        global_state = @states[[normalized_provider_id, []]]
        context_state = @states[[normalized_provider_id, requested_key]] unless requested_key.empty?
        if context_state&.snapshot&.mature?
          return context_state.snapshot(evidence_scope: :context)
        end
        return global_state.snapshot if global_state

        default_snapshot(normalized_provider_id)
      end

      def snapshots(provider_ids, context: nil, context_key: nil)
        RubyRouting::Collection.to_array(provider_ids, "provider_ids").map { |provider_id| normalize_provider_id(provider_id) }.uniq.sort.to_h do |provider_id|
          [provider_id, snapshot(provider_id, context: context, context_key: context_key)]
        end.freeze
      end

      def provider_ids
        @states.keys.map(&:first).uniq.sort.freeze
      end

      def ensure_provider(provider_id)
        normalized_provider_id = normalize_provider_id(provider_id)
        ensure_state(normalized_provider_id, [])
        nil
      end

      def observe(provider_id:, outcome:, context: nil, context_key: nil)
        unless outcome.is_a?(RubyRouting::NormalizedOutcome)
          raise ArgumentError, "outcome must be NormalizedOutcome"
        end

        normalized_provider_id = normalize_provider_id(provider_id)
        requested_key = normalize_context_key(context_key || context)
        before = snapshot(normalized_provider_id, context_key: requested_key)
        if outcome.attribution == :provider && outcome.success?
          record(normalized_provider_id, requested_key, :success)
        elsif outcome.provider_failure?
          record(normalized_provider_id, requested_key, :failure)
        else
          return [before, before]
        end

        [before, snapshot(normalized_provider_id, context_key: requested_key)]
      end

      private

      def record(provider_id, context_key, kind)
        ensure_state(provider_id, []).public_send("record_#{kind}")
        ensure_state(provider_id, context_key).public_send("record_#{kind}") unless context_key.empty?
      end

      def ensure_state(provider_id, context_key)
        key = [provider_id, context_key.freeze]
        @states[key] ||= MutableState.new(provider_id, @policy.minimum_samples, context_key)
      end

      def normalize_context_key(context)
        labels = if context.is_a?(Array)
          context
        elsif context.is_a?(Hash)
          context[:labels] || context["labels"] || []
        else
          []
        end
        labels = [labels] if labels.is_a?(String) || labels.is_a?(Symbol)
        RubyRouting::Collection.to_array(labels, "quality context labels")
          .map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort.freeze
      end

      def normalize_provider_id(provider_id)
        normalized = provider_id.to_s.strip
        raise ArgumentError, "provider id must be non-empty" if normalized.empty?

        normalized
      end

      def default_snapshot(provider_id)
        ProviderQualitySnapshot.new(
          provider_id: provider_id,
          minimum_samples: @policy.minimum_samples
        )
      end

      class MutableState
        attr_reader :provider_id, :successful_samples, :failed_samples

        def initialize(provider_id, minimum_samples, context_key)
          @provider_id = provider_id.to_s
          @minimum_samples = minimum_samples
          @context_key = context_key
          @successful_samples = 0
          @failed_samples = 0
        end

        def record_success
          @successful_samples += 1
        end

        def record_failure
          @failed_samples += 1
        end

        def snapshot(evidence_scope: context_key.empty? ? :global : :context)
          ProviderQualitySnapshot.new(
            provider_id: provider_id,
            successful_samples: successful_samples,
            failed_samples: failed_samples,
            minimum_samples: @minimum_samples,
            context_key: context_key,
            evidence_scope: evidence_scope
          )
        end

        attr_reader :context_key
      end
    end
  end
end
