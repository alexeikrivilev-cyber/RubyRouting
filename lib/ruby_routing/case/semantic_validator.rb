# frozen_string_literal: true

require "json"
require "time"

module RubyRouting
  module Case
    # Recomputes the organizer-facing report from the raw case inputs and the
    # serialized decisions. This is deliberately separate from ReportBuilder,
    # StrictValidator and SerializedArtifactValidator: those validators prove
    # consistency with the implementation, while this class proves the base
    # report's business values independently.
    class OrganizerReportSemanticValidator
      PERCENTAGE_DECIMAL_PLACES = 2

      def initialize(providers_path:, queue_path:, profile_path:, decisions_path:, report_path:)
        @providers_path = providers_path
        @queue_path = queue_path
        @profile_path = profile_path
        @decisions_path = decisions_path
        @report_path = report_path
        @errors = []
      end

      def call
        providers_document = parse(@providers_path, "providers")
        queue = parse(@queue_path, "queue")
        profile = parse(@profile_path, "submission profile")
        decisions = parse(@decisions_path, "decisions")
        report = parse(@report_path, "report")

        unless profile.is_a?(Hash)
          add("submission profile input must be an Object") unless profile.nil?
        end
        add("decisions artifact must be an Array") unless decisions.is_a?(Array) || decisions.nil?
        add("report artifact must be an Object") unless report.is_a?(Hash) || report.nil?

        if providers_document && queue && profile.is_a?(Hash) && decisions.is_a?(Array) && report.is_a?(Hash)
          providers = provider_values(providers_document)
          operations = operation_values(queue)
          if providers && operations
            validate_semantics(providers, operations, profile, decisions, report, providers_document)
          end
        end

        ValidationResult.new(errors: @errors)
      end

      def validate!
        result = call
        return result if result.valid?

        raise OutputError, "organizer report semantic validation failed: #{result.errors.join('; ')}"
      end

      private

      def parse(path, label)
        JSON.parse(
          File.read(path), decimal_class: Rational, create_additions: false,
          allow_duplicate_key: false
        )
      rescue Errno::ENOENT => error
        add("#{label} artifact not found: #{error.message}")
        nil
      rescue JSON::ParserError => error
        add("#{label} artifact is invalid JSON: #{error.message}")
        nil
      rescue SystemCallError => error
        add("#{label} artifact cannot be read: #{error.message}")
        nil
      end

      def provider_values(document)
        unless document.is_a?(Hash) && document["providers"].is_a?(Array)
          add("providers input must contain a providers Array")
          return nil
        end

        providers = document.fetch("providers")
        invalid = false
        ids = providers.map do |provider|
          unless provider.is_a?(Hash)
            add("providers input contains an invalid provider")
            invalid = true
            next
          end

          id = provider["payment_system"]
          unless id.is_a?(String) && !id.empty?
            add("providers input contains a provider without payment_system")
            invalid = true
          end
          id
        end
        if invalid || ids.any?(&:nil?)
          return nil
        end
        if ids.uniq.length != ids.length
          add("providers input contains duplicate payment_system identities")
          return nil
        end
        providers.to_h { |provider| [provider.fetch("payment_system"), provider] }
      rescue KeyError
        add("providers input contains an invalid provider")
        nil
      end

      def operation_values(queue)
        unless queue.is_a?(Array)
          add("queue input must be an Array")
          return nil
        end

        invalid = false
        ids = queue.map do |operation|
          unless operation.is_a?(Hash)
            add("queue input contains an invalid operation")
            invalid = true
            next
          end

          id = operation["operation_id"]
          unless id.is_a?(String) && !id.empty?
            add("queue input contains an operation without operation_id")
            invalid = true
          end
          id
        end
        if invalid || ids.any?(&:nil?)
          return nil
        end
        if ids.uniq.length != ids.length
          add("queue input contains duplicate operation_id identities")
          return nil
        end
        queue.to_h { |operation| [operation.fetch("operation_id"), operation] }
      rescue KeyError
        add("queue input contains an invalid operation")
        nil
      end

      def validate_semantics(providers, operations, profile, decisions, report, providers_document)
        provider_ids = providers.keys.sort
        validate_decisions(operations, provider_ids, decisions)
        validate_total_operations(operations, report)
        validate_distribution(providers, provider_ids, operations, profile, decisions, report)
        validate_utilization(providers, provider_ids, operations, decisions, report, providers_document)
        validate_period(operations, providers_document, report)
      end

      def validate_decisions(operations, provider_ids, decisions)
        decision_ids = decisions.filter_map do |decision|
          id = decision["operation_id"] if decision.is_a?(Hash)
          add("decisions contain an operation without operation_id") unless id.is_a?(String) && !id.empty?
          id
        end
        add("decisions contain duplicate operation_id identities") unless decision_ids.uniq.length == decision_ids.length
        add("decisions coverage differs from queue") unless decision_ids.sort == operations.keys.sort

        decisions.each do |decision|
          next unless decision.is_a?(Hash)

          selected_provider = decision["selected_provider"]
          add("#{decision["operation_id"]}: selected_provider is unknown") unless provider_ids.include?(selected_provider)
          attempts = decision["attempts"]
          unless attempts.is_a?(Array)
            add("#{decision["operation_id"]}: attempts must be an Array")
            next
          end
          selected_attempts = attempts.select { |attempt| attempt.is_a?(Hash) && attempt["decision"] == "selected" }
          add("#{decision["operation_id"]}: no selected attempt") if selected_attempts.empty?
          attempts.each do |attempt|
            next unless attempt.is_a?(Hash)

            add("#{decision["operation_id"]}: attempt provider is unknown") unless provider_ids.include?(attempt["provider"])
          end
        end
      end

      def validate_total_operations(operations, report)
        expected = operations.length
        add("report total_operations #{report["total_operations"]} differs from queue #{expected}") unless report["total_operations"] == expected
      end

      def validate_distribution(providers, provider_ids, operations, profile, decisions, report)
        distribution = report["distribution"]
        unless distribution.is_a?(Hash)
          add("report distribution must be an Object")
          return
        end
        add("report distribution provider set differs from raw providers") unless distribution.keys.sort == provider_ids

        primary_counts = provider_ids.to_h { |provider_id| [provider_id, 0] }
        decisions.each do |decision|
          next unless decision.is_a?(Hash)
          primary = Array(decision["attempts"]).find { |attempt| attempt.is_a?(Hash) && attempt["decision"] == "selected" }
          primary_counts[primary["provider"]] += 1 if primary && primary_counts.key?(primary["provider"])
        end
        add("primary assignment count #{primary_counts.values.sum} differs from queue #{operations.length}") unless primary_counts.values.sum == operations.length

        count_denominator = operations.length
        target_shares = count_targets(providers, profile)
        provider_ids.each do |provider_id|
          entry = distribution[provider_id]
          unless entry.is_a?(Hash)
            add("distribution.#{provider_id} must be an Object")
            next
          end
          expected_count = primary_counts.fetch(provider_id)
          add("distribution.#{provider_id}.count differs from primary assignments") unless entry["count"] == expected_count
          expected_share = percentage(
            count_denominator.zero? ? Rational(0, 1) : Rational(expected_count, count_denominator)
          )
          compare_percentage(entry["share_pct"], expected_share, "distribution.#{provider_id}.share_pct")
          compare_percentage(entry["target_pct"], percentage(target_shares.fetch(provider_id)), "distribution.#{provider_id}.target_pct")
        end
      end

      def count_targets(providers, profile)
        source = profile["count_target_source"]
        unless source == "provider.traffic_percentage"
          add("unsupported count target source #{source.inspect} for semantic report validation")
          return providers.keys.to_h { |provider_id| [provider_id, Rational(0, 1)] }
        end

        providers.each_with_object({}) do |(provider_id, provider), result|
          traffic_percentage = provider["traffic_percentage"]
          unless traffic_percentage.is_a?(Integer) || traffic_percentage.is_a?(Rational)
            add("#{provider_id}: traffic_percentage must be exact")
          end
          participating = provider["status"] == "active" &&
            (traffic_percentage.is_a?(Integer) || traffic_percentage.is_a?(Rational)) &&
            traffic_percentage.positive?
          unless traffic_percentage.is_a?(Integer) || traffic_percentage.is_a?(Rational)
            result[provider_id] = Rational(0, 1)
            next
          end
          target = if traffic_percentage.is_a?(Integer)
            Rational(traffic_percentage, 100)
          else
            traffic_percentage / 100
          end
          result[provider_id] = participating ? target : Rational(0, 1)
        end.freeze
      end

      def validate_utilization(providers, provider_ids, operations, decisions, report, providers_document)
        utilization = report["projected_daily_utilization"]
        unless utilization.is_a?(Hash)
          add("report projected_daily_utilization must be an Object")
          return
        end
        add("report utilization provider set differs from raw providers") unless utilization.keys.sort == provider_ids

        operation_times = operations.values.filter_map do |operation|
          begin
            Time.iso8601(operation.fetch("created_at"))
          rescue KeyError, ArgumentError, TypeError
            nil
          end
        end
        snapshot_time = begin
          Time.iso8601(providers_document.fetch("snapshot_at"))
        rescue KeyError, ArgumentError, TypeError
          nil
        end
        final_day = calendar_day(operation_times.max || snapshot_time) if snapshot_time
        snapshot_day = calendar_day(snapshot_time) if snapshot_time
        approved_volume = provider_ids.to_h { |provider_id| [provider_id, 0] }
        decisions.each do |decision|
          next unless decision.is_a?(Hash) && decision["simulated_result"] == "approved"
          provider_id = decision["selected_provider"]
          operation = operations[decision["operation_id"]]
          next unless operation && approved_volume.key?(provider_id) && operation["amount"].is_a?(Integer)
          operation_day = begin
            calendar_day(Time.iso8601(operation.fetch("created_at")))
          rescue KeyError, ArgumentError, TypeError
            nil
          end
          next unless final_day && operation_day == final_day

          approved_volume[provider_id] += operation["amount"]
        end

        provider_ids.each do |provider_id|
          entry = utilization[provider_id]
          unless entry.is_a?(Hash)
            add("projected_daily_utilization.#{provider_id} must be an Object")
            next
          end
          provider = providers.fetch(provider_id)
          baseline = if snapshot_day && snapshot_day == final_day
            provider["daily_approved_amount"]
          else
            0
          end
          add("#{provider_id}: daily_approved_amount must be an Integer") unless baseline.is_a?(Integer)
          baseline = 0 unless baseline.is_a?(Integer)
          expected_used = baseline + approved_volume.fetch(provider_id)
          expected_limit = provider["daily_amount_limit"]
          add("projected_daily_utilization.#{provider_id}.used differs from initial snapshot plus approved settlements") unless entry["used"] == expected_used
          add("projected_daily_utilization.#{provider_id}.limit differs from provider snapshot") unless entry["limit"] == expected_limit
          expected_percentage = expected_limit.nil? || expected_limit == 0 ? nil : percentage(Rational(expected_used, expected_limit))
          if expected_percentage.nil?
            add("projected_daily_utilization.#{provider_id}.utilization_pct must be nil") unless entry["utilization_pct"].nil?
          else
            compare_percentage(entry["utilization_pct"], expected_percentage, "projected_daily_utilization.#{provider_id}.utilization_pct")
          end
        end
      end

      def validate_period(operations, providers_document, report)
        timestamps = operations.values.filter_map do |operation|
          begin
            Time.iso8601(operation.fetch("created_at"))
          rescue KeyError, ArgumentError, TypeError
            add("queue operation has invalid created_at")
            nil
          end
        end
        snapshot = begin
          Time.iso8601(providers_document.fetch("snapshot_at"))
        rescue KeyError, ArgumentError, TypeError
          add("providers snapshot_at is invalid")
          nil
        end
        return unless timestamps.all? && snapshot

        expected = (timestamps.min || snapshot).utc.strftime("%Y-%m-%d")
        add("report period #{report["period"].inspect} differs from authoritative queue period #{expected}") unless report["period"] == expected
      end

      def calendar_day(value)
        value.utc.strftime("%Y-%m-%d")
      end

      def compare_percentage(actual, expected, label)
        unless actual.is_a?(Numeric) && actual.finite?
          add("#{label} must be a finite numeric percentage")
          return
        end
        add("#{label} #{actual} differs from recomputed #{expected}") unless actual.to_f == expected.to_f
      end

      def percentage(value)
        value = value * 100
        value.round(PERCENTAGE_DECIMAL_PLACES).to_f
      end

      def add(message)
        @errors << message
      end
    end
  end
end
