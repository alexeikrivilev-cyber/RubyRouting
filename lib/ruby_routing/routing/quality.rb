# frozen_string_literal: true

module RubyRouting
  module Routing
    # Slow provider quality is deliberately independent from fast operational
    # health. Only mature provider-attributed success/failure outcomes enter
    # this estimate; pending, UNKNOWN and recipient/downstream outcomes are
    # neutral evidence. The estimate is a deterministic Beta/Laplace posterior
    # over a bounded recent evidence window, not a raw success ratio.
    class QualityPolicy
      attr_reader :minimum_samples, :prior_successes, :prior_failures, :evidence_window,
                  :max_evidence_age_seconds, :route_minimum_samples

      def initialize(minimum_samples: 1, prior_successes: 1, prior_failures: 1, evidence_window: 100,
                     max_evidence_age_seconds: nil, route_minimum_samples: nil)
        unless minimum_samples.is_a?(Integer) && minimum_samples.positive?
          raise ArgumentError, "minimum_samples must be a positive Integer"
        end
        unless prior_successes.is_a?(Integer) && prior_successes >= 0
          raise ArgumentError, "prior_successes must be a non-negative Integer"
        end
        unless prior_failures.is_a?(Integer) && prior_failures >= 0
          raise ArgumentError, "prior_failures must be a non-negative Integer"
        end
        if prior_successes + prior_failures <= 0
          raise ArgumentError, "quality prior must have positive strength"
        end
        unless evidence_window.is_a?(Integer) && evidence_window >= minimum_samples
          raise ArgumentError, "evidence_window must be an Integer at least minimum_samples"
        end
        unless max_evidence_age_seconds.nil? ||
               (max_evidence_age_seconds.is_a?(Integer) && max_evidence_age_seconds.positive?)
          raise ArgumentError, "max_evidence_age_seconds must be a positive Integer or nil"
        end
        normalized_route_minimum_samples = route_minimum_samples || [minimum_samples, 2].max
        unless normalized_route_minimum_samples.is_a?(Integer) && normalized_route_minimum_samples.positive?
          raise ArgumentError, "route_minimum_samples must be a positive Integer"
        end
        unless evidence_window >= normalized_route_minimum_samples
          raise ArgumentError, "evidence_window must be an Integer at least route_minimum_samples"
        end

        @minimum_samples = minimum_samples
        @prior_successes = prior_successes
        @prior_failures = prior_failures
        @evidence_window = evidence_window
        @max_evidence_age_seconds = max_evidence_age_seconds
        @route_minimum_samples = normalized_route_minimum_samples
        freeze
      end

      def to_h
        values = {
          minimum_samples: minimum_samples,
          prior_successes: prior_successes,
          prior_failures: prior_failures,
          evidence_window: evidence_window
        }
        values[:max_evidence_age_seconds] = max_evidence_age_seconds unless max_evidence_age_seconds.nil?
        values[:route_minimum_samples] = route_minimum_samples unless route_minimum_samples == [minimum_samples, 2].max
        values.freeze
      end
    end

    class ProviderQualitySnapshot
      EVIDENCE_SCOPES = %i[global context route].freeze

      attr_reader :provider_id, :successful_samples, :failed_samples, :minimum_samples,
                  :prior_successes, :prior_failures, :evidence_window,
                  :context_key, :evidence_scope, :routing_context, :currency,
                  :last_observed_at, :evidence_age_seconds, :max_evidence_age_seconds

      def initialize(provider_id:, successful_samples: 0, failed_samples: 0, minimum_samples: 1,
                     prior_successes: 1, prior_failures: 1, evidence_window: 100,
                     context_key: [], evidence_scope: :global, routing_context: nil,
                     last_observed_at: nil, as_of: nil, max_evidence_age_seconds: nil,
                     currency: nil)
        @provider_id = RubyRouting::Identity.normalize(provider_id, "provider id")
        @successful_samples = normalize_non_negative_integer(successful_samples, "successful_samples")
        @failed_samples = normalize_non_negative_integer(failed_samples, "failed_samples")
        @minimum_samples = normalize_positive_integer(minimum_samples, "minimum_samples")
        @prior_successes = normalize_non_negative_integer(prior_successes, "prior_successes")
        @prior_failures = normalize_non_negative_integer(prior_failures, "prior_failures")
        if @prior_successes + @prior_failures <= 0
          raise ArgumentError, "quality prior must have positive strength"
        end
        unless evidence_window.is_a?(Integer) && evidence_window >= @minimum_samples
          raise ArgumentError, "evidence_window must be an Integer at least minimum_samples"
        end
        unless max_evidence_age_seconds.nil? ||
               (max_evidence_age_seconds.is_a?(Integer) && max_evidence_age_seconds.positive?)
          raise ArgumentError, "max_evidence_age_seconds must be a positive Integer or nil"
        end
        if sample_count > evidence_window
          raise ArgumentError, "quality samples exceed evidence_window"
        end
        @evidence_window = evidence_window
        @currency = normalize_currency(currency)
        @context_key = normalize_context_key(context_key)
        @evidence_scope = normalize_enum(evidence_scope, EVIDENCE_SCOPES, "quality evidence scope")
        @routing_context = normalize_routing_context(routing_context)
        if @evidence_scope == :route && !route_cohort?(@routing_context)
          raise ArgumentError, "route quality evidence requires a typed route context"
        end
        @last_observed_at = normalize_time(last_observed_at, "last_observed_at")
        normalized_as_of = normalize_time(as_of, "as_of")
        if normalized_as_of && @last_observed_at && normalized_as_of < @last_observed_at
          raise ArgumentError, "quality as_of cannot precede last_observed_at"
        end
        @evidence_age_seconds = if normalized_as_of && @last_observed_at
          Rational(normalized_as_of.to_r - @last_observed_at.to_r)
        end
        @max_evidence_age_seconds = max_evidence_age_seconds
        freeze
      end

      def sample_count
        successful_samples + failed_samples
      end

      def mature?
        sample_count >= minimum_samples
      end

      def stale?
        mature? && !max_evidence_age_seconds.nil? &&
          (evidence_age_seconds.nil? || evidence_age_seconds > max_evidence_age_seconds)
      end

      def authoritative?
        mature? && !stale?
      end

      def score
        return Rational(prior_successes, prior_successes + prior_failures) unless mature?

        Rational(
          successful_samples + prior_successes,
          sample_count + prior_successes + prior_failures
        )
      end

      def confidence
        mature? ? sample_count : 0
      end

      def to_h
        values = {
          provider_id: provider_id,
          successful_samples: successful_samples,
          failed_samples: failed_samples,
          sample_count: sample_count,
          mature: mature?,
          score: score,
          confidence: confidence,
          minimum_samples: minimum_samples,
          prior_successes: prior_successes,
          prior_failures: prior_failures,
          evidence_window: evidence_window,
          context_key: context_key,
          evidence_scope: evidence_scope
        }
        values[:currency] = currency unless currency.nil?
        if routing_context || last_observed_at || !evidence_age_seconds.nil? || !max_evidence_age_seconds.nil?
          values.merge!(
            routing_context: routing_context&.to_h,
            last_observed_at: last_observed_at,
            evidence_age_seconds: evidence_age_seconds,
            max_evidence_age_seconds: max_evidence_age_seconds,
            stale: stale?
          )
        end
        values.freeze
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
          unless label.is_a?(String) || label.is_a?(Symbol)
            raise ArgumentError, "context_key labels must be String or Symbol values"
          end

          normalized = label.to_s.strip
          raise ArgumentError, "context_key labels must be non-empty" if normalized.empty?

          normalized
        end.uniq.sort.freeze
      end

      def normalize_currency(value)
        return nil if value.nil?
        unless value.is_a?(String)
          raise ArgumentError, "currency must be a String"
        end

        normalized = value.strip.upcase
        unless RubyRouting::Money::CURRENCY_PATTERN.match?(normalized)
          raise ArgumentError, "currency must be a three-letter code"
        end

        normalized.freeze
      end

      def normalize_routing_context(value)
        return nil if value.nil?
        unless value.is_a?(RubyRouting::RoutingContext)
          value = RubyRouting::RoutingContext.from(value, strict: true)
        end

        value
      end

      def route_cohort?(value)
        value && (
          !value.payment_method.nil? || !value.rail.nil? || !value.destination_kind.nil?
        )
      end

      def normalize_time(value, label)
        return nil if value.nil?
        unless value.is_a?(Time)
          raise ArgumentError, "#{label} must be a Time or nil"
        end

        value.getutc.freeze
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

      def snapshot(provider_id, context: nil, context_key: nil, routing_context: nil, currency: nil, as_of: nil)
        normalized_provider_id = normalize_provider_id(provider_id)
        requested_key = normalize_context_key(context_key.nil? ? context : context_key)
        requested_route = normalize_requested_routing_context(routing_context, context)
        requested_route_key = route_cohort_key(requested_route)
        normalized_currency = normalize_currency(currency)
        normalized_as_of = normalize_time(as_of, "as_of")
        global_state = @states[[normalized_provider_id, normalized_currency, []]]
        context_state = @states[[normalized_provider_id, normalized_currency, requested_key]] unless requested_key.empty?
        route_state = if requested_route_key
          @states[[normalized_provider_id, normalized_currency, requested_route_key]]
        end
        if route_state
          route_snapshot = route_state.snapshot(
            evidence_scope: :route,
            as_of: normalized_as_of,
            fresh_only: true
          )
          return route_snapshot if route_snapshot.authoritative?
        end
        if context_state
          context_snapshot = context_state.snapshot(
            evidence_scope: :context,
            as_of: normalized_as_of,
            fresh_only: true
          )
          return context_snapshot if context_snapshot.authoritative?
        end
        if global_state
          global_snapshot = global_state.snapshot(
            as_of: normalized_as_of,
            fresh_only: true
          )
          return global_snapshot if global_snapshot.authoritative?
        end

        default_snapshot(normalized_provider_id, currency: normalized_currency, as_of: normalized_as_of)
      end

      # Returns the state of the cohort that received the observation, even
      # while it is immature. Routing callers should use #snapshot so sparse
      # evidence falls back to mature evidence or the prior; durable evidence
      # callers use this method to retain the cohort identity and rolling
      # counters needed for replay.
      def evidence_snapshot(provider_id, context: nil, context_key: nil, routing_context: nil, currency: nil)
        normalized_provider_id = normalize_provider_id(provider_id)
        requested_key = normalize_context_key(context_key.nil? ? context : context_key)
        requested_route = normalize_requested_routing_context(routing_context, context)
        requested_route_key = route_cohort_key(requested_route)
        normalized_currency = normalize_currency(currency)
        state = if requested_route_key
          @states[[normalized_provider_id, normalized_currency, requested_route_key]]
        else
          @states[[normalized_provider_id, normalized_currency, requested_key]]
        end
        if state
          scope = requested_route_key ? :route : (requested_key.empty? ? :global : :context)
          return state.snapshot(evidence_scope: scope)
        end

        ProviderQualitySnapshot.new(
          provider_id: normalized_provider_id,
          prior_successes: @policy.prior_successes,
          prior_failures: @policy.prior_failures,
          evidence_window: @policy.evidence_window,
          minimum_samples: requested_route_key ? @policy.route_minimum_samples : @policy.minimum_samples,
          context_key: requested_route_key ? [] : requested_key,
          evidence_scope: requested_route_key ? :route : (requested_key.empty? ? :global : :context),
          routing_context: requested_route_key && route_cohort_context(requested_route),
          currency: normalized_currency,
          max_evidence_age_seconds: @policy.max_evidence_age_seconds
        )
      end

      def snapshots(provider_ids, context: nil, context_key: nil, routing_context: nil, currency: nil, as_of: nil)
        RubyRouting::Collection.to_array(provider_ids, "provider_ids").map { |provider_id| normalize_provider_id(provider_id) }.uniq.sort.to_h do |provider_id|
          [provider_id, snapshot(
            provider_id,
            context: context,
            context_key: context_key,
            routing_context: routing_context,
            currency: currency,
            as_of: as_of
          )]
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

      def observe(provider_id:, outcome:, context: nil, context_key: nil, routing_context: nil, currency: nil, observed_at: nil)
        unless outcome.is_a?(RubyRouting::NormalizedOutcome)
          raise ArgumentError, "outcome must be NormalizedOutcome"
        end

        normalized_provider_id = normalize_provider_id(provider_id)
        requested_key = normalize_context_key(context_key.nil? ? context : context_key)
        requested_route = normalize_requested_routing_context(routing_context, context)
        normalized_currency = normalize_currency(currency)
        normalized_observed_at = normalize_time(observed_at, "observed_at")
        before = snapshot(
          normalized_provider_id,
          context_key: requested_key,
          routing_context: requested_route,
          currency: normalized_currency
        )
        if outcome.attribution == :provider && outcome.success?
          record(normalized_provider_id, normalized_currency, requested_key, requested_route, :success, normalized_observed_at)
        elsif outcome.provider_failure?
          record(normalized_provider_id, normalized_currency, requested_key, requested_route, :failure, normalized_observed_at)
        else
          return [before, before]
        end

        [before, evidence_snapshot(
          normalized_provider_id,
          context_key: requested_key,
          routing_context: requested_route,
          currency: normalized_currency
        )]
      end

      private

      def record(provider_id, currency, context_key, routing_context, kind, observed_at)
        ensure_state(provider_id, [], currency: currency).public_send("record_#{kind}", observed_at: observed_at)
        unless context_key.empty?
          ensure_state(provider_id, context_key, currency: currency).public_send("record_#{kind}", observed_at: observed_at)
        end
        route_key = route_cohort_key(routing_context)
        if route_key
          ensure_state(
            provider_id,
            route_key,
            currency: currency,
            context_key: [],
            routing_context: route_cohort_context(routing_context),
            minimum_samples: @policy.route_minimum_samples
          )
            .public_send("record_#{kind}", observed_at: observed_at)
        end
      end

      def ensure_state(provider_id, state_key, currency: nil, context_key: state_key, routing_context: nil,
                       minimum_samples: @policy.minimum_samples)
        key = [provider_id, currency, state_key.freeze]
        @states[key] ||= MutableState.new(
          provider_id,
          currency,
          minimum_samples,
          @policy.prior_successes,
          @policy.prior_failures,
          @policy.evidence_window,
          context_key,
          routing_context: routing_context,
          max_evidence_age_seconds: @policy.max_evidence_age_seconds
        )
      end

      def normalize_context_key(context)
        labels = if context.is_a?(RubyRouting::RoutingContext)
          context.labels
        elsif context.is_a?(Array)
          context
        elsif context.is_a?(Hash)
          context[:labels] || context["labels"] || []
        elsif context.nil?
          []
        elsif context.respond_to?(:each)
          context
        else
          raise ArgumentError, "quality context must be a RoutingContext, Hash, Array, String, Symbol or nil"
        end
        labels = [labels] if labels.is_a?(String) || labels.is_a?(Symbol)
        RubyRouting::Collection.to_array(labels, "quality context labels")
          .map do |label|
            unless label.is_a?(String) || label.is_a?(Symbol)
              raise ArgumentError, "quality context labels must be String or Symbol values"
            end

            label.to_s.strip
          end.reject(&:empty?).uniq.sort.freeze
      end

      def normalize_routing_context(context)
        return nil if context.nil?
        return context if context.is_a?(RubyRouting::RoutingContext)

        RubyRouting::RoutingContext.from(context, strict: true)
      end

      def normalize_requested_routing_context(routing_context, context)
        return normalize_routing_context(routing_context) unless routing_context.nil?
        return context if context.is_a?(RubyRouting::RoutingContext)
        return RubyRouting::RoutingContext.from(context, strict: false) if context.is_a?(Hash)

        nil
      end

      def route_cohort?(context)
        !route_cohort_key(context).nil?
      end

      def route_cohort_key(context)
        return nil unless context && (
          !context.payment_method.nil? || !context.rail.nil? || !context.destination_kind.nil?
        )

        {
          payment_method: context.payment_method,
          rail: context.rail,
          destination_kind: context.destination_kind
        }.freeze
      end

      def route_cohort_context(context)
        return nil unless route_cohort?(context)

        RubyRouting::RoutingContext.new(
          payment_method: context.payment_method,
          rail: context.rail,
          destination_kind: context.destination_kind
        )
      end

      def normalize_time(value, label)
        return nil if value.nil?
        unless value.is_a?(Time)
          raise ArgumentError, "#{label} must be a Time or nil"
        end

        value.getutc.freeze
      end

      def normalize_currency(value)
        return nil if value.nil?
        unless value.is_a?(String)
          raise ArgumentError, "currency must be a String"
        end

        normalized = value.strip.upcase
        unless RubyRouting::Money::CURRENCY_PATTERN.match?(normalized)
          raise ArgumentError, "currency must be a three-letter code"
        end

        normalized.freeze
      end

      def normalize_provider_id(provider_id)
        RubyRouting::Identity.normalize(provider_id, "provider id")
      end

      def default_snapshot(provider_id, currency: nil, as_of: nil)
        ProviderQualitySnapshot.new(
          provider_id: provider_id,
          minimum_samples: @policy.minimum_samples,
          prior_successes: @policy.prior_successes,
          prior_failures: @policy.prior_failures,
          evidence_window: @policy.evidence_window,
          currency: currency,
          max_evidence_age_seconds: @policy.max_evidence_age_seconds,
          as_of: as_of
        )
      end

      class MutableState
        attr_reader :provider_id, :context_key, :routing_context

        def initialize(provider_id, currency, minimum_samples, prior_successes, prior_failures, evidence_window,
                       context_key, routing_context: nil, max_evidence_age_seconds: nil)
          @provider_id = RubyRouting::Identity.normalize(provider_id, "provider id")
          @currency = currency
          @minimum_samples = minimum_samples
          @prior_successes = prior_successes
          @prior_failures = prior_failures
          @evidence_window = evidence_window
          @context_key = context_key
          @routing_context = routing_context
          @max_evidence_age_seconds = max_evidence_age_seconds
          @samples = []
        end

        def record_success(observed_at: nil)
          record(true, observed_at)
        end

        def record_failure(observed_at: nil)
          record(false, observed_at)
        end

        def snapshot(evidence_scope: context_key.empty? ? :global : :context, as_of: nil, fresh_only: false)
          # The bounded window is maintained in observation/append order. A
          # routing snapshot then filters that retained window by sample age;
          # durable evidence snapshots deliberately keep the full window for
          # fact validation and replay.
          samples = fresh_only ? fresh_samples(as_of) : @samples
          latest_observed_at = samples.filter_map { |_success, observed_at| observed_at }.max
          ProviderQualitySnapshot.new(
            provider_id: provider_id,
            successful_samples: samples.count { |success, _observed_at| success },
            failed_samples: samples.count { |success, _observed_at| !success },
            minimum_samples: @minimum_samples,
            prior_successes: @prior_successes,
            prior_failures: @prior_failures,
            evidence_window: @evidence_window,
            context_key: context_key,
            evidence_scope: evidence_scope,
            routing_context: routing_context,
            currency: @currency,
            last_observed_at: latest_observed_at,
            as_of: as_of,
            max_evidence_age_seconds: @max_evidence_age_seconds
          )
        end

        private

        def record(success, observed_at)
          @samples << [success, observed_at]
          @samples.shift while @samples.length > @evidence_window
        end

        def fresh_samples(as_of)
          return @samples if as_of.nil? && @max_evidence_age_seconds.nil?
          return [] if as_of.nil?

          @samples.select do |_success, observed_at|
            if observed_at.nil?
              @max_evidence_age_seconds.nil?
            else
              as_of >= observed_at &&
                (@max_evidence_age_seconds.nil? ||
                 Rational(as_of.to_r - observed_at.to_r) <= @max_evidence_age_seconds)
            end
          end
        end
      end
    end
  end
end
