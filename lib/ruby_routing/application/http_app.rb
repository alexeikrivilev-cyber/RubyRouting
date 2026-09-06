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
          normalized_id = provider_id.to_s.strip
          raise ArgumentError, "provider id must be non-empty" if normalized_id.empty?
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
        return { body: { status: "ok" } } if method == "GET" && segments == ["health"]

        case segments
        when ["v1", "payouts"]
          return submit_payout(env) if method == "POST"
        when ["v1", "analytics"]
          return analytics(env) if method == "GET"
        when ["v1", "providers"]
          return { body: { providers: @service.queries.providers.map(&:to_h) } } if method == "GET"
        when ["v1", "quality"]
          return { body: { providers: @service.queries.quality.to_h } } if method == "GET"
        when ["v1", "audit", "facts"]
          return audit_facts(env) if method == "GET"
        else
          if method == "GET" && segments.length == 3 && segments[0, 2] == ["v1", "payouts"]
            return { body: { payout: snapshot_payload(@service.queries.payout(segments[2])) } }
          end
          if method == "GET" && segments.length == 4 && segments[0, 2] == ["v1", "payouts"] && segments[3] == "explanation"
            return { body: { explanation: @service.queries.explanation(segments[2]).to_h } }
          end
          if method == "POST" && segments.length == 4 && segments[0, 2] == ["v1", "payouts"] && segments[3] == "resume"
            result = @service.resume(payout_id: segments[2])
            return { body: route_result_payload(result) }
          end
          if method == "POST" && segments.length == 4 && segments[0, 2] == ["v1", "providers"] && segments[3] == "webhook"
            return reconcile_webhook(segments[2], env)
          end
        end

        raise KeyError, "route not found"
      end

      def submit_payout(env)
        body = json_body(env)
        intent = RubyRouting::PayoutIntent.new(
          id: required_body_value(body, "id"),
          money: RubyRouting::Money.new(
            required_body_value(body, "amount_minor"),
            required_body_value(body, "currency")
          ),
          recipient: body.fetch("recipient", {}),
          context: body.fetch("context", {})
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
        query_string = bounded_string(
          env.fetch("QUERY_STRING", ""),
          MAX_QUERY_STRING_BYTES,
          "query string"
        )
        query = URI.decode_www_form(query_string).to_h
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
        query_string = bounded_string(
          env.fetch("QUERY_STRING", ""),
          MAX_QUERY_STRING_BYTES,
          "query string"
        )
        query = URI.decode_www_form(query_string).to_h
        as_of = query.key?("as_of") ? Time.iso8601(query.fetch("as_of")) : nil
        analytics = if query.key?("as_of")
          @service.queries.analytics(as_of: as_of)
        else
          @service.queries.analytics
        end
        { body: analytics.to_h }
      end

      def json_body(env)
        input = env.fetch("rack.input") { StringIO.new }
        raise RequestError, "request body must be readable" unless input.respond_to?(:read)

        raw = input.read(MAX_REQUEST_BODY_BYTES + 1)
        raw = "" if raw.nil?
        raise RequestError, "request body must be a String" unless raw.is_a?(String)
        raise PayloadTooLarge, "request body is too large" if raw.bytesize > MAX_REQUEST_BODY_BYTES

        parsed = JSON.parse(raw)
        raise RequestError, "request body must be an object" unless parsed.is_a?(Hash)

        parsed
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
