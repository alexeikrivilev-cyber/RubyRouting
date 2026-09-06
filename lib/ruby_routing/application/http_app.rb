# frozen_string_literal: true

require "json"
require "stringio"
require "uri"
require "time"

module RubyRouting
  module Application
    # Small Rack-compatible transport adapter for the product surface. It
    # deliberately contains parsing/serialization only; routing decisions and
    # lifecycle transitions remain in Service/Commands and the core facade.
    class HttpApp
      MAX_REQUEST_BODY_BYTES = 1_048_576
      MAX_PATH_BYTES = 8_192
      MAX_QUERY_STRING_BYTES = 16_384
      MAX_AUDIT_PAGE_SIZE = 256
      MAX_AUDIT_OFFSET = 1_000_000
      ANALYTICS_QUERY_FIELDS = %w[
        policy_id policy_epoch policy_scope window cohort measure currency provider_id
        role outcome_class attribution
      ].freeze

      class RequestError < StandardError; end
      class PayloadTooLarge < RequestError; end

      def initialize(service:, provider_normalizers: {})
        unless service.is_a?(RubyRouting::Application::Service)
          raise ArgumentError, "service must be Application::Service"
        end
        unless provider_normalizers.is_a?(Hash)
          raise ArgumentError, "provider_normalizers must be a Hash"
        end

        @service = service
        @provider_normalizers = provider_normalizers.each_with_object({}) do |(provider_id, normalizer), copy|
          normalized_id = RubyRouting::Identity.normalize(provider_id, "provider id")
          raise ArgumentError, "provider normalizer ids must be unique after normalization" if copy.key?(normalized_id)
          unless executable_normalizer?(normalizer)
            raise ArgumentError, "provider normalizer must implement executable #normalize"
          end

          copy[normalized_id] = normalizer
        end.freeze
        freeze
      end

      def call(env)
        method = bounded_string(env.fetch("REQUEST_METHOD", "GET"), 16, "request method").upcase
        path = bounded_string(env.fetch("PATH_INFO", "/"), MAX_PATH_BYTES, "request path").split("?").first
        bounded_string(env.fetch("QUERY_STRING", ""), MAX_QUERY_STRING_BYTES, "query string")
        segments = path.split("/").reject(&:empty?)

        payload = dispatch(method, segments, env)
        json_response(payload.fetch(:status, 200), payload.fetch(:body))
      rescue PayloadTooLarge
        json_response(413, error: "request_too_large")
      rescue RubyRouting::AmbiguousPolicyError => error
        json_response(
          409,
          error: "ambiguous_policy",
          resolution: error.resolution.to_h
        )
      rescue RubyRouting::NoMatchingPolicyError => error
        json_response(
          422,
          error: "no_matching_policy",
          resolution: error.resolution.to_h
        )
      rescue RubyRouting::ConfigurationDriftError
        json_response(503, error: "configuration_drift")
      rescue JSON::ParserError, RequestError, ArgumentError
        json_response(400, error: "invalid_request")
      rescue KeyError
        json_response(404, error: "not_found")
      rescue RubyRouting::State::DurableCorruptionError
        json_response(503, error: "durable_state_unavailable")
      rescue StandardError
        # The transport boundary must not turn implementation details or Ruby
        # backtraces into an external API contract.
        json_response(500, error: "internal_error")
      end

      private

      def dispatch(method, segments, env)
        if method == "GET" && segments == ["health"]
          reject_unknown_query_parameters!(query_parameters(env), allowed: [])
          return { body: { status: "ok" } }
        end

        case segments
        when ["v1", "payouts"]
          return submit_payout(env) if method == "POST"
        when ["v1", "analytics"]
          return analytics(env) if method == "GET"
        when ["v1", "configuration"]
          return configuration(env) if method == "GET"
        when ["v1", "recovery", "due-work"]
          return due_recovery_work(env) if method == "GET"
        when ["v1", "providers"]
          return providers(env) if method == "GET"
        when ["v1", "quality"]
          return quality(env) if method == "GET"
        when ["v1", "health"]
          return provider_health(env) if method == "GET"
        when ["v1", "audit", "facts"]
          return audit_facts(env) if method == "GET"
        else
          if method == "GET" && segments.length == 3 && segments[0, 2] == ["v1", "payouts"]
            reject_unknown_query_parameters!(query_parameters(env), allowed: [])
            return { body: { payout: snapshot_payload(@service.queries.payout(segments[2])) } }
          end
          if method == "GET" && segments.length == 4 && segments[0, 2] == ["v1", "payouts"] && segments[3] == "explanation"
            reject_unknown_query_parameters!(query_parameters(env), allowed: [])
            return { body: { explanation: @service.queries.explanation(segments[2]).to_h } }
          end
          if method == "POST" && segments.length == 4 && segments[0, 2] == ["v1", "payouts"] && segments[3] == "resume"
            reject_unknown_query_parameters!(query_parameters(env), allowed: [])
            reject_nonempty_body!(env)
            result = @service.resume(payout_id: segments[2])
            return { body: route_result_payload(result) }
          end
          if method == "POST" && segments.length == 4 && segments[0, 2] == ["v1", "providers"] && segments[3] == "webhook"
            reject_unknown_query_parameters!(query_parameters(env), allowed: [])
            return reconcile_webhook(segments[2], env)
          end
        end

        raise KeyError, "route not found"
      end

      def submit_payout(env)
        reject_unknown_query_parameters!(query_parameters(env), allowed: [])
        body = json_body(env)
        reject_unknown_body_keys!(
          body,
          allowed: %w[id amount_minor currency recipient context routing_context scope]
        )
        intent = RubyRouting::PayoutIntent.new(
          id: required_body_value(body, "id"),
          money: RubyRouting::Money.new(
            required_body_value(body, "amount_minor"),
            required_body_value(body, "currency")
          ),
          recipient: body.fetch("recipient", {}),
          context: body.fetch("context", {}),
          routing_context: body.fetch("routing_context", nil)
        )
        result = @service.submit(intent: intent, scope: body.fetch("scope", "default"))
        { status: 201, body: route_result_payload(result) }
      end

      def required_body_value(body, key)
        return body[key] if body.key?(key)

        raise RequestError, "missing request field"
      end

      def reconcile_webhook(provider_id, env)
        normalized_provider_id = provider_id.to_s.strip
        raise RequestError, "provider id must be non-empty" if normalized_provider_id.empty?

        normalizer = @provider_normalizers.fetch(normalized_provider_id)
        application = @service.commands.reconcile_provider_event(
          provider_id: normalized_provider_id,
          raw: json_body(env),
          normalizer: normalizer
        )
        {
          body: {
            duplicate: application.duplicate,
            conflict: application.conflict,
            next_action: application.next_action,
            payout: snapshot_payload(application.payout)
          }
        }
      end

      def executable_normalizer?(normalizer)
        return false unless normalizer.respond_to?(:normalize)

        normalizer.method(:normalize).owner != RubyRouting::Ports::ProviderNormalizer
      rescue NameError
        false
      end

      def audit_facts(env)
        query = query_parameters(env)
        reject_unknown_query_parameters!(
          query,
          allowed: %w[payout_id type offset limit]
        )
        limit = bounded_query_integer(
          query["limit"],
          default: MAX_AUDIT_PAGE_SIZE,
          minimum: 1,
          maximum: MAX_AUDIT_PAGE_SIZE
        )
        offset = bounded_query_integer(query["offset"], default: 0, minimum: 0, maximum: nil)
        page = @service.queries.audit_facts_page(
          payout_id: query["payout_id"],
          type: query["type"],
          offset: offset,
          limit: limit
        )
        {
          body: {
            facts: page.facts.map do |fact|
              public_fact = RubyRouting::Projections::PublicAuditFact.from_fact(fact)
              {
                sequence: fact.sequence,
                type: fact.type,
                fact_id: fact.fact_id,
                payout_id: fact.payout_id,
                payload: public_fact.payload,
                redacted_fields: public_fact.redacted_fields
              }
            end,
            offset: page.offset,
            limit: page.limit,
            next_offset: page.next_offset,
            total: page.total
          }
        }
      end

      def bounded_query_integer(value, default:, minimum:, maximum:)
        return default if value.nil?
        unless value.is_a?(String) && /\A[0-9]+\z/.match?(value)
          raise RequestError, "query value must be a non-negative decimal integer"
        end

        parsed = Integer(value, 10)
        raise RequestError, "query value is out of bounds" if parsed < minimum
        raise RequestError, "query value is out of bounds" if maximum && parsed > maximum
        raise RequestError, "query value is out of bounds" if maximum.nil? && parsed > MAX_AUDIT_OFFSET

        parsed
      rescue ArgumentError
        raise RequestError, "query value is out of bounds"
      end

      def analytics(env)
        query = query_parameters(env)
        as_of = query.key?("as_of") ? Time.iso8601(query.fetch("as_of")) : nil
        if query.key?("metric")
          reject_unknown_query_parameters!(
            query,
            allowed: %w[as_of metric group_by] + ANALYTICS_QUERY_FIELDS
          )
          arguments = {
            metric: query.fetch("metric"),
            filters: analytics_filters(query),
            group_by: query.key?("group_by") ? query_list(query.fetch("group_by"), "group_by") : []
          }
          arguments[:as_of] = as_of if query.key?("as_of")
          return { body: @service.queries.analytics_query(**arguments).to_h }
        end

        reject_unknown_query_parameters!(query, allowed: ["as_of"])

        analytics = if query.key?("as_of")
          @service.queries.analytics(as_of: as_of)
        else
          @service.queries.analytics
        end
        { body: analytics.to_h }
      end

      def configuration(env)
        query = query_parameters(env)
        reject_unknown_query_parameters!(query, allowed: [])
        snapshot = @service.queries.configuration_snapshot
        {
          body: {
            revision: snapshot.revision,
            status: @service.queries.configuration_status,
            configuration: snapshot.configuration.to_h,
            diagnostics: snapshot.diagnostics.map(&:to_h)
          }
        }
      end

      def due_recovery_work(env)
        query = query_parameters(env)
        reject_unknown_query_parameters!(query, allowed: ["as_of"])
        as_of = query.key?("as_of") ? Time.iso8601(query.fetch("as_of")) : nil
        work = if query.key?("as_of")
          @service.queries.due_work(as_of: as_of)
        else
          @service.queries.due_work
        end
        body = { due_work: work.map(&:to_h) }
        body[:as_of] = as_of unless as_of.nil?
        { body: body }
      end

      def providers(env)
        query = query_parameters(env)
        reject_unknown_query_parameters!(query, allowed: [])
        { body: { providers: @service.queries.providers.map(&:to_h) } }
      end

      def quality(env)
        query = query_parameters(env)
        as_of = query.key?("as_of") ? Time.iso8601(query.fetch("as_of")) : nil
        routing_context = routing_context_from_query(query, extra_keys: %w[as_of currency])
        currency = query_currency(query)
        quality = if query.key?("as_of")
          @service.queries.quality(
            as_of: as_of,
            routing_context: routing_context,
            currency: currency
          )
        else
          @service.queries.quality(
            routing_context: routing_context,
            currency: currency
          )
        end
        { body: { providers: quality.to_h } }
      end

      def provider_health(env)
        query = query_parameters(env)
        routing_context = routing_context_from_query(query)
        { body: { providers: @service.queries.health(routing_context: routing_context).to_h } }
      end

      def routing_context_from_query(query, extra_keys: [])
        allowed_keys = %w[payment_method rail destination_kind] + extra_keys
        unknown_keys = query.keys - allowed_keys
        raise RequestError, "unsupported routing query parameter" unless unknown_keys.empty?

        route_values = %w[payment_method rail destination_kind].each_with_object({}) do |dimension, values|
          values[dimension.to_sym] = query.fetch(dimension) if query.key?(dimension)
        end
        return nil if route_values.empty?

        RubyRouting::RoutingContext.from(route_values, strict: true)
      rescue ArgumentError => error
        raise RequestError, error.message
      end

      def query_currency(query)
        return nil unless query.key?("currency")

        value = query.fetch("currency")
        unless value.is_a?(String)
          raise RequestError, "currency query parameter must be a String"
        end

        normalized = value.strip.upcase
        unless RubyRouting::Money::CURRENCY_PATTERN.match?(normalized)
          raise RequestError, "currency query parameter must be a three-letter code"
        end

        normalized.freeze
      end

      def reject_unknown_query_parameters!(query, allowed:)
        unknown = query.keys - allowed
        raise RequestError, "unsupported query parameter" unless unknown.empty?
      end

      def reject_unknown_body_keys!(body, allowed:)
        unknown = body.keys - allowed
        raise RequestError, "unsupported request field" unless unknown.empty?
      end

      def analytics_filters(query)
        fields = ANALYTICS_QUERY_FIELDS
        query.each_with_object({}) do |(field, value), filters|
          next unless fields.include?(field)

          filters[field] = field == "cohort" ? query_list(value, "cohort") : value
        end
      end

      def query_parameters(env)
        query_string = bounded_string(
          env.fetch("QUERY_STRING", ""),
          MAX_QUERY_STRING_BYTES,
          "query string"
        )
        URI.decode_www_form(query_string).each_with_object({}) do |(key, value), query|
          if query.key?(key)
            raise RequestError, "query string contains duplicate parameter"
          end

          query[key] = value
        end
      end

      def query_list(value, label)
        unless value.is_a?(String)
          raise RequestError, "analytics query #{label} must be a String"
        end

        if value.lstrip.start_with?("[")
          parsed = JSON.parse(value)
          raise RequestError, "analytics query #{label} must be an Array" unless parsed.is_a?(Array)

          return parsed
        end

        values = value.split(",", -1).map(&:strip)
        raise RequestError, "analytics query #{label} contains an empty value" if values.any?(&:empty?)

        values
      end

      def json_body(env)
        raw = request_body(env)
        parsed = JSON.parse(raw, allow_duplicate_key: false)
        raise RequestError, "request body must be an object" unless parsed.is_a?(Hash)

        parsed
      end

      def reject_nonempty_body!(env)
        raise RequestError, "request body is not supported" unless request_body(env).empty?
      end

      def request_body(env)
        input = env.fetch("rack.input") { StringIO.new }
        raise RequestError, "request body must be readable" unless input.respond_to?(:read)

        raw = input.read(MAX_REQUEST_BODY_BYTES + 1)
        raw = "" if raw.nil?
        raise RequestError, "request body must be a String" unless raw.is_a?(String)
        raise PayloadTooLarge, "request body is too large" if raw.bytesize > MAX_REQUEST_BODY_BYTES

        raw
      end

      def route_result_payload(result)
        {
          action: result.action,
          status: result.status,
          payout: snapshot_payload(result.payout)
        }
      end

      def snapshot_payload(snapshot)
        {
          id: snapshot.id,
          status: snapshot.status,
          money: money_payload(snapshot.intent.money),
          routing_context: snapshot.intent.routing_context.to_h,
          ownership: snapshot.ownership && {
            provider_id: snapshot.ownership.provider_id,
            operation_id: snapshot.ownership.operation_id,
            attempt_id: snapshot.ownership.attempt_id
          },
          attempts: snapshot.attempts.map { |attempt| attempt_payload(attempt) },
          primary_provider_id: snapshot.primary_provider_id,
          settlement_provider_id: snapshot.settlement_provider_id,
          settlement_operation_id: snapshot.settlement_operation_id,
          policy_epoch: snapshot.policy_epoch,
          policy_scope_key: snapshot.policy_scope_key,
          policy_fingerprint: snapshot.policy_fingerprint,
          provider_interaction_count: snapshot.provider_interaction_count,
          resolution_interaction_count: snapshot.resolution_interaction_count,
          next_action: snapshot.next_action,
          next_action_at: snapshot.next_action_at,
          conflicts: snapshot.conflicts.map { |conflict| conflict_payload(conflict) },
          reversals: snapshot.reversals.map { |reversal| reversal_payload(reversal) },
          created_at: snapshot.created_at
        }
      end

      def attempt_payload(attempt)
        {
          attempt_id: attempt.attempt_id,
          operation_id: attempt.operation_id,
          provider_id: attempt.provider_id,
          role: attempt.role,
          phase: attempt.phase,
          measure: attempt.measure,
          outcome: attempt.outcome && outcome_payload(attempt.outcome),
          contract: attempt.contract && {
            provider_id: attempt.contract.provider_id,
            idempotent_retry: attempt.contract.idempotent_retry,
            status_lookup: attempt.contract.status_lookup,
            idempotency_key: attempt.contract.idempotency_key,
            ttl_seconds: attempt.contract.ttl_seconds,
            deadline_seconds: attempt.contract.deadline_seconds,
            version: attempt.contract.version,
            authoritative_sequence: attempt.contract.authoritative_sequence
          },
          last_observation_sequence: attempt.last_observation_sequence,
          committed_at: attempt.committed_at
        }
      end

      def outcome_payload(outcome)
        {
          status: outcome.status,
          attribution: outcome.attribution,
          provider_reference: outcome.provider_reference,
          message: outcome.message,
          safe_to_release: outcome.safe_to_release?
        }
      end

      def conflict_payload(conflict)
        {
          provider_id: conflict.provider_id,
          operation_id: conflict.operation_id,
          attempt_id: conflict.attempt_id,
          reason: conflict.reason
        }
      end

      def reversal_payload(reversal)
        {
          reversal_id: reversal.reversal_id,
          provider_id: reversal.provider_id,
          operation_id: reversal.operation_id,
          amount: money_payload(reversal.amount),
          reason: reversal.reason
        }
      end

      def money_payload(money)
        { amount_minor: money.amount_minor, currency: money.currency }
      end

      def bounded_string(value, limit, label)
        raise RequestError, "#{label} must be a String" unless value.is_a?(String)
        raise PayloadTooLarge, "#{label} is too large" if value.bytesize > limit

        value
      end

      def json_response(status, body)
        serialized = JSON.generate(json_safe(body))
        [status, { "Content-Type" => "application/json", "Content-Length" => serialized.bytesize.to_s }, [serialized]]
      end

      def json_safe(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, nested), copy| copy[key.to_s] = json_safe(nested) }
        when Array
          value.map { |nested| json_safe(nested) }
        when Rational
          { "numerator" => value.numerator, "denominator" => value.denominator }
        when RubyRouting::Money
          money_payload(value)
        when Time
          value.iso8601(9)
        when Symbol
          value.to_s
        else
          value
        end
      end
    end
  end
end
