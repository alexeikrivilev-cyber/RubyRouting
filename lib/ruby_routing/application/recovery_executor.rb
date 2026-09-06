# frozen_string_literal: true

module RubyRouting
  module Application
    # Executes one explicitly bounded pass over work already made actionable
    # by Queries. It is deliberately not a scheduler, lease owner, or routing
    # engine: every continuation goes back through Service#resume.
    class RecoveryExecutor
      MAX_BATCH_SIZE = 256
      SAFE_PROVIDER_ERROR_MESSAGE = "provider execution failed"

      Error = Data.define(:class_name, :message) do
        def to_h
          { class: class_name, message: message }.freeze
        end
      end

      ItemResult = Data.define(:work_item, :result, :error) do
        def status
          result ? result.status : :error
        end

        def action
          result ? result.action : :error
        end

        def error?
          !error.nil?
        end

        def to_h
          {
            work_item: work_item.to_h,
            status: status,
            action: action,
            error: error&.to_h
          }.freeze
        end
      end

      PassResult = Data.define(:as_of, :limit, :items) do
        # `as_of` is the due-work scan timestamp. It is not a claim that every
        # canonical Service#resume call ran at this timestamp.
        alias scan_as_of as_of

        def processed_count
          items.length
        end

        def error_count
          items.count(&:error?)
        end

        def success?
          error_count.zero?
        end

        def to_h
          {
            as_of: as_of,
            limit: limit,
            items: items.map(&:to_h).freeze
          }.freeze
        end
      end

      def initialize(service:)
        unless service.is_a?(RubyRouting::Application::Service)
          raise ArgumentError, "service must be Application::Service"
        end

        @service = service
        freeze
      end

      # Run exactly one bounded pass. `as_of` is the due-work scan timestamp;
      # canonical Service#resume continues to use the Coordinator's current
      # clock. A future scan is rejected because it would select work that the
      # mutating execution clock has not made due.
      # Only the typed provider-boundary failure is reported per item. The
      # canonical Service has already left that operation resumable. Durable
      # corruption and all failures outside that boundary abort the pass and
      # remain visible to the operator.
      def run(limit:, as_of: nil)
        validate_limit!(limit)
        normalized_current_time = normalize_as_of(@service.queries.current_time)
        unless normalized_current_time
          raise ArgumentError, "service current time must be a Time"
        end

        normalized_as_of = normalize_as_of(as_of.nil? ? normalized_current_time : as_of)
        if normalized_as_of > normalized_current_time
          raise ArgumentError, "as_of cannot be later than the service current time"
        end
        work = @service.queries.due_work(as_of: normalized_as_of, limit: limit)
        items = work.map { |work_item| execute(work_item) }.freeze
        PassResult.new(
          as_of: normalized_as_of,
          limit: limit,
          items: items
        )
      end

      private

      def execute(work_item)
        result = @service.resume(payout_id: work_item.payout_id)
        ItemResult.new(work_item: work_item, result: result, error: nil)
      rescue RubyRouting::ProviderExecutionError => error
        ItemResult.new(
          work_item: work_item,
          result: nil,
          # Provider exception messages are adapter-controlled and may contain
          # recipient or provider secrets. Keep the typed taxonomy while
          # exposing only a stable operator-safe message.
          error: Error.new(
            class_name: error.class.name.freeze,
            message: SAFE_PROVIDER_ERROR_MESSAGE
          )
        )
      end

      def validate_limit!(limit)
        unless limit.is_a?(Integer) && !limit.is_a?(TrueClass) && limit >= 0
          raise ArgumentError, "limit must be a non-negative Integer"
        end
        raise ArgumentError, "limit must not exceed #{MAX_BATCH_SIZE}" if limit > MAX_BATCH_SIZE
      end

      def normalize_as_of(as_of)
        return nil if as_of.nil?
        raise ArgumentError, "as_of must be a Time" unless as_of.is_a?(Time)

        as_of.utc.freeze
      end
    end
  end
end
