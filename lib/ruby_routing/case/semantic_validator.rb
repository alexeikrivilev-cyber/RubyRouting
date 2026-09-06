# frozen_string_literal: true

require "json"
require "csv"
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
      SUBSET_SUM_MAX_OPERATIONS = 64
      SUBSET_SUM_MAX_VOLUME = 250_000
      ATTEMPT_REASON_CODES = %w[
        inactive_provider zero_participation amount_below_minimum amount_exceeds_limit
        daily_amount_limit in_progress_count_limit in_progress_amount_limit
        bank_excluded bank_not_in_list negative_margin_without_agreement
        no_available_requisite rpm_limit
        provider_rejected provider_expired
        only_eligible_provider highest_composite_score deterministic_tie_break
        fallback_highest_composite_score fallback_deterministic_tie_break
        terminal_fallback external_providers_exhausted
      ].freeze
      FACTOR_KEYS = %w[count volume priority amount conversion_24h load intensity turnover_min].freeze
      FACTOR_NORMALIZATION_BOUNDS = {
        "count" => [Rational(-2, 1), Rational(0, 1)].freeze,
        "volume" => [Rational(-2, 1), Rational(0, 1)].freeze
      }.freeze
      RECOMMENDATION_KINDS = %w[
        count_target_unmet volume_target_unmet target_infeasible_hard_forced
        structurally_constrained_under_target workload_granularity
        volume_workload_granularity volume_subset_sum_granularity
        daily_utilization_near_limit terminal_fallback_deviation
      ].freeze
      PROVIDER_REQUIRED_KEYS = %w[
        payment_system status traffic_percentage priority
        limit_amount_min limit_amount_max daily_amount_limit daily_approved_amount
        in_progress_count_limit in_progress_count in_progress_amount_limit in_progress_amount
        available_requisites conversion_24h avg_latency_sec banks exclude_banks
        provider_margin_pct merchant_margin_pct allow_negative_agreement
      ].freeze
      PROVIDER_OPTIONAL_KEYS = %w[note].freeze
      PROVIDER_STATUSES = %w[active enabled inactive disabled].freeze
      PROVIDER_EXACT_RATIO_KEYS = %w[
        traffic_percentage conversion_24h provider_margin_pct merchant_margin_pct
      ].freeze
      OPERATION_REQUIRED_KEYS = %w[
        operation_id created_at amount bank card_brand payout_requisite
      ].freeze
      PROVIDER_ROOT_REQUIRED_KEYS = %w[snapshot_at gateway merchant providers].freeze
      PARSE_FAILURE = Object.new.freeze

      def initialize(providers_path:, queue_path:, profile_path:, decisions_path:, report_path:, history_path: nil)
        @providers_path = providers_path
        @history_path = history_path
        @queue_path = queue_path
        @profile_path = profile_path
        @decisions_path = decisions_path
        @report_path = report_path
        @errors = []
      end

      def call
        providers_document = parse(@providers_path, "providers")
        history = parse_history(@history_path) if @history_path
        queue = parse(@queue_path, "queue")
        profile = parse(@profile_path, "submission profile")
        decisions = parse(@decisions_path, "decisions")
        report = parse(@report_path, "report")

        roots_valid = [
          valid_root?(providers_document, Hash, "providers artifact", "Object"),
          history.nil? || valid_root?(history, Array, "history artifact", "Array"),
          valid_root?(queue, Array, "queue artifact", "Array"),
          valid_root?(profile, Hash, "submission profile input", "Object"),
          valid_root?(decisions, Array, "decisions artifact", "Array"),
          valid_root?(report, Hash, "report artifact", "Object")
        ].all?

        if roots_valid
          providers = provider_values(providers_document)
          operations = operation_values(queue)
          if providers && operations
            validate_semantics(providers, operations, history, profile, decisions, report, providers_document)
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
        PARSE_FAILURE
      rescue JSON::ParserError => error
        add("#{label} artifact is invalid JSON: #{error.message}")
        PARSE_FAILURE
      rescue SystemCallError => error
        add("#{label} artifact cannot be read: #{error.message}")
        PARSE_FAILURE
      end

      def valid_root?(value, expected_class, label, expected_name)
        return false if value.equal?(PARSE_FAILURE)
        return true if value.is_a?(expected_class)

        add("#{label} must be an #{expected_name}")
        false
      end

      def parse_history(path)
        text = File.read(path)
        table = CSV.parse(text, headers: true, return_headers: false)
        expected = %w[operation_id created_at amount bank card_brand payment_system status latency_sec]
        unless table.headers == expected
          add("history input header must be #{expected.join(', ')}")
          return PARSE_FAILURE
        end
        table.map.with_index do |row, index|
          {
            "operation_id" => history_string(row["operation_id"], "operation_id", index),
            "created_at" => history_time(row["created_at"], index),
            "amount" => history_integer(row["amount"], "amount", index, min: 1),
            "bank" => history_string(row["bank"], "bank", index, non_empty: false),
            "card_brand" => history_string(row["card_brand"] || "", "card_brand", index, non_empty: false),
            "payment_system" => history_string(row["payment_system"], "payment_system", index),
            "status" => history_status(row["status"], index),
            "latency_sec" => history_integer(row["latency_sec"], "latency_sec", index, min: 0)
          }
        end
      rescue Errno::ENOENT => error
        add("history input not found: #{error.message}")
        PARSE_FAILURE
      rescue CSV::MalformedCSVError => error
        add("history input is invalid CSV: #{error.message}")
        PARSE_FAILURE
      rescue SystemCallError => error
        add("history input cannot be read: #{error.message}")
        PARSE_FAILURE
      end

      def history_string(value, field, index, non_empty: true)
        unless value.is_a?(String) && (!non_empty || !value.empty?)
          qualifier = non_empty ? "non-empty " : ""
          add("history row #{index + 2} #{field} must be a #{qualifier}String")
          return ""
        end
        value
      end

      def history_time(value, index)
        return Time.iso8601(value).iso8601 if value.is_a?(String)

        add("history row #{index + 2} created_at must be an ISO-8601 String")
        ""
      rescue ArgumentError
        add("history row #{index + 2} created_at must be an ISO-8601 String")
        ""
      end

      def history_integer(value, field, index, min:)
        if value.is_a?(String) && value.match?(/\A\d+\z/) && value.to_i >= min
          return value.to_i
        end

        add("history row #{index + 2} #{field} must be an integer CSV value >= #{min}")
        0
      end

      def history_status(value, index)
        return value if %w[approved rejected expired].include?(value)

        add("history row #{index + 2} status is unsupported")
        ""
      end

      def provider_values(document)
        unless document.is_a?(Hash)
          add("providers input must contain a providers Array")
          return nil
        end
        missing = PROVIDER_ROOT_REQUIRED_KEYS - document.keys
        unknown = document.keys - PROVIDER_ROOT_REQUIRED_KEYS
        add("providers input root missing fields: #{missing.join(', ')}") unless missing.empty?
        add("providers input root contains unsupported fields: #{unknown.join(', ')}") unless unknown.empty?
        valid = missing.empty? && unknown.empty?
        valid &&= add_provider_root_error("snapshot_at", valid_timestamp?(document["snapshot_at"]))
        valid &&= add_provider_root_error("gateway", document["gateway"].is_a?(String))
        valid &&= add_provider_root_error("merchant", document["merchant"].is_a?(String))
        unless document["providers"].is_a?(Array)
          add("providers input must contain a providers Array")
          valid = false
        end
        return nil unless valid

        providers = document.fetch("providers")
        invalid = false
        ids = providers.map do |provider|
          unless provider.is_a?(Hash)
            add("providers input contains an invalid provider")
            invalid = true
            next
          end

          normalize_provider_exact_ratios!(provider)
          invalid = true unless valid_provider_shape?(provider)

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

      def add_provider_root_error(field, condition)
        return true if condition

        add("providers input root #{field} has an invalid value")
        false
      end

      def normalize_provider_exact_ratios!(provider)
        PROVIDER_EXACT_RATIO_KEYS.each do |field|
          value = provider[field]
          next unless value.is_a?(String)
          next unless (match = /\A(-?\d+)\/([1-9]\d*)\z/.match(value))

          provider[field] = Rational(match[1].to_i, match[2].to_i)
        end
        provider
      end

      def valid_provider_shape?(provider)
        missing = PROVIDER_REQUIRED_KEYS - provider.keys
        unknown = provider.keys - PROVIDER_REQUIRED_KEYS - PROVIDER_OPTIONAL_KEYS
        add("providers input provider #{provider["payment_system"].inspect} missing fields: #{missing.join(', ')}") unless missing.empty?
        add("providers input provider #{provider["payment_system"].inspect} contains unsupported fields: #{unknown.join(', ')}") unless unknown.empty?
        valid = missing.empty? && unknown.empty?

        valid &&= add_provider_error(provider, "payment_system", provider["payment_system"].is_a?(String) && !provider["payment_system"].strip.empty?)
        valid &&= add_provider_error(provider, "status", PROVIDER_STATUSES.include?(provider["status"]))
        unless exact_number?(provider["traffic_percentage"], min: 0, max: 100)
          # Keep this diagnostic precise: the value is also the independent
          # provider-derived target input.
          add("providers input provider #{provider["payment_system"].inspect} traffic_percentage must be exact")
          valid = false
        end
        valid &&= add_provider_error(provider, "priority", non_negative_integer?(provider["priority"]))
        %w[limit_amount_min limit_amount_max daily_amount_limit in_progress_count_limit in_progress_amount_limit].each do |field|
          valid &&= add_provider_error(provider, field, optional_non_negative_integer?(provider[field]))
        end
        %w[daily_approved_amount in_progress_count in_progress_amount available_requisites avg_latency_sec].each do |field|
          valid &&= add_provider_error(provider, field, non_negative_integer?(provider[field]))
        end
        valid &&= add_provider_error(provider, "conversion_24h", exact_number?(provider["conversion_24h"], min: 0, max: 1))
        valid &&= add_provider_error(provider, "provider_margin_pct", exact_number?(provider["provider_margin_pct"], min: 0))
        valid &&= add_provider_error(provider, "merchant_margin_pct", exact_number?(provider["merchant_margin_pct"], min: 0))
        valid &&= add_provider_error(
          provider, "banks",
          provider["banks"].is_a?(Array) &&
            provider["banks"].all? { |bank| bank.is_a?(String) && !bank.strip.empty? } &&
            provider["banks"].uniq.length == provider["banks"].length
        )
        valid &&= add_provider_error(provider, "exclude_banks", boolean?(provider["exclude_banks"]))
        valid &&= add_provider_error(provider, "allow_negative_agreement", boolean?(provider["allow_negative_agreement"]))
        valid &&= add_provider_error(provider, "note", provider["note"].nil? || provider["note"].is_a?(String))
        if non_negative_integer?(provider["limit_amount_min"]) &&
           non_negative_integer?(provider["limit_amount_max"]) &&
           provider["limit_amount_min"] > provider["limit_amount_max"]
          add("providers input provider #{provider["payment_system"].inspect} limit_amount_min exceeds limit_amount_max")
          valid = false
        end
        if non_negative_integer?(provider["daily_amount_limit"]) &&
           non_negative_integer?(provider["daily_approved_amount"]) &&
           provider["daily_approved_amount"] > provider["daily_amount_limit"]
          add("providers input provider #{provider["payment_system"].inspect} daily_approved_amount exceeds daily_amount_limit")
          valid = false
        end
        if non_negative_integer?(provider["in_progress_count_limit"]) &&
           non_negative_integer?(provider["in_progress_count"]) &&
           provider["in_progress_count"] > provider["in_progress_count_limit"]
          add("providers input provider #{provider["payment_system"].inspect} in_progress_count exceeds in_progress_count_limit")
          valid = false
        end
        if non_negative_integer?(provider["in_progress_amount_limit"]) &&
           non_negative_integer?(provider["in_progress_amount"]) &&
           provider["in_progress_amount"] > provider["in_progress_amount_limit"]
          add("providers input provider #{provider["payment_system"].inspect} in_progress_amount exceeds in_progress_amount_limit")
          valid = false
        end
        valid
      end

      def add_provider_error(provider, field, condition)
        return true if condition

        add("providers input provider #{provider["payment_system"].inspect} #{field} has an invalid value")
        false
      end

      def exact_number?(value, min: nil, max: nil)
        return false unless value.is_a?(Integer) || value.is_a?(Rational)
        return false if min && value < min
        return false if max && value > max

        true
      end

      def non_negative_integer?(value)
        value.is_a?(Integer) && value >= 0
      end

      def optional_non_negative_integer?(value)
        value.nil? || non_negative_integer?(value)
      end

      def boolean?(value)
        value == true || value == false
      end

      def operation_values(queue)
        unless queue.is_a?(Array)
          add("queue input must be an Array")
          return nil
        end

        invalid = false
        timestamps = []
        ids = queue.map.with_index do |operation, index|
          unless operation.is_a?(Hash)
            add("queue input contains an invalid operation")
            invalid = true
            next
          end

          invalid = true unless valid_operation_shape?(operation, index)
          if operation["created_at"].is_a?(String)
            begin
              timestamps << Time.iso8601(operation.fetch("created_at"))
            rescue ArgumentError, KeyError
              # The shape error below is the useful diagnostic for malformed
              # timestamps; do not leak a parser exception from the oracle.
            end
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
        if timestamps.length == queue.length && timestamps.each_cons(2).any? { |previous, current| current < previous }
          add("queue input operations must be ordered by non-decreasing created_at")
          invalid = true
        end
        return nil if invalid

        queue.to_h { |operation| [operation.fetch("operation_id"), operation] }
      rescue KeyError
        add("queue input contains an invalid operation")
        nil
      end

      def valid_operation_shape?(operation, index)
        missing = OPERATION_REQUIRED_KEYS - operation.keys
        unknown = operation.keys - OPERATION_REQUIRED_KEYS
        add("queue operation #{index} missing fields: #{missing.join(', ')}") unless missing.empty?
        add("queue operation #{index} contains unsupported fields: #{unknown.join(', ')}") unless unknown.empty?
        valid = missing.empty? && unknown.empty?

        valid &&= add_operation_error(index, "operation_id", operation["operation_id"].is_a?(String) && !operation["operation_id"].empty?)
        valid &&= add_operation_error(index, "created_at", valid_timestamp?(operation["created_at"]))
        valid &&= add_operation_error(index, "amount", operation["amount"].is_a?(Integer) && operation["amount"] >= 1)
        valid &&= add_operation_error(index, "bank", operation["bank"].is_a?(String))
        valid &&= add_operation_error(index, "card_brand", operation["card_brand"].nil? || operation["card_brand"].is_a?(String))
        valid &&= add_operation_error(index, "payout_requisite", operation["payout_requisite"].is_a?(Hash) && !operation["payout_requisite"].empty?)
        valid
      end

      def add_operation_error(index, field, condition)
        return true if condition

        add("queue operation #{index} #{field} has an invalid value")
        false
      end

      def valid_timestamp?(value)
        return false unless value.is_a?(String)

        Time.iso8601(value)
        true
      rescue ArgumentError
        false
      end

      def validate_semantics(providers, operations, history, profile, decisions, report, providers_document)
        business_calendar = business_calendar_for(providers_document)
        provider_ids = providers.keys.sort
        validate_decisions(operations, provider_ids, decisions)
        validate_total_operations(operations, report)
        validate_population_analytics(provider_ids, operations, decisions, report)
        validate_distribution(providers, provider_ids, operations, profile, decisions, report)
        validate_utilization(providers, provider_ids, operations, decisions, report, business_calendar)
        validate_configuration(providers, provider_ids, profile, report)
        validate_submission_profile(profile, report)
        validate_dataset_metadata(providers_document, operations, history, report)
        validate_provider_state(providers, provider_ids, operations, profile, decisions, report, business_calendar)
        validate_deviation_causes(provider_ids, profile, decisions, report)
        validate_infeasibility(provider_ids, decisions, report)
        validate_history(history, @history_path, report) if history
        validate_explanations(providers, decisions, report)
        validate_recommendations(provider_ids, operations, decisions, report)
        validate_period(operations, business_calendar, report)
        validate_period_window(operations, report)
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
          selected_attempts.each do |attempt|
            unless %w[approved rejected expired].include?(attempt["simulated_result"])
              add("#{decision["operation_id"]}: selected attempt must contain a valid simulated_result")
            end
          end
          if selected_attempts.any? && selected_provider != selected_attempts.last["provider"]
            add("#{decision["operation_id"]}: selected_provider must match the last selected attempt")
          end
          if selected_attempts.any? && decision["simulated_result"] != selected_attempts.last["simulated_result"]
            add("#{decision["operation_id"]}: simulated_result must match the last selected attempt")
          end
          if selected_attempts.any? && attempts.last != selected_attempts.last
            add("#{decision["operation_id"]}: final attempt must be selected")
          end
          seen_attempt_providers = []
          attempts.each do |attempt|
            unless attempt.is_a?(Hash)
              add("#{decision["operation_id"]}: attempt must be an Object")
              next
            end

            provider_id = attempt["provider"]
            if provider_ids.include?(provider_id)
              add("#{decision["operation_id"]}: duplicate attempt provider") if seen_attempt_providers.include?(provider_id)
              seen_attempt_providers << provider_id
            else
              add("#{decision["operation_id"]}: attempt provider is unknown")
            end
          end
        end
      end

      def validate_total_operations(operations, report)
        expected = operations.length
        add("report total_operations #{report["total_operations"]} differs from queue #{expected}") unless report["total_operations"] == expected
      end

      def validate_population_analytics(provider_ids, operations, decisions, report)
        skip_reasons = Hash.new(0)
        attempt_outcomes = %w[approved rejected expired].to_h { |status| [status, 0] }
        final_outcomes = %w[approved rejected expired].to_h { |status| [status, 0] }
        attempt_counts = provider_ids.to_h { |provider_id| [provider_id, 0] }
        attempt_volumes = provider_ids.to_h { |provider_id| [provider_id, 0] }
        attempt_outcomes_by_provider = provider_ids.to_h do |provider_id|
          [provider_id, %w[approved rejected expired].to_h { |status| [status, 0] }]
        end
        primary_counts = provider_ids.to_h { |provider_id| [provider_id, 0] }
        primary_volumes = provider_ids.to_h { |provider_id| [provider_id, 0] }
        final_selection_counts = provider_ids.to_h { |provider_id| [provider_id, 0] }
        final_selection_volumes = provider_ids.to_h { |provider_id| [provider_id, 0] }
        settlement_counts = provider_ids.to_h { |provider_id| [provider_id, 0] }
        settlement_volumes = provider_ids.to_h { |provider_id| [provider_id, 0] }
        fallback_count = 0

        decisions.each do |decision|
          next unless decision.is_a?(Hash)

          operation = operations[decision["operation_id"]]
          attempts = decision["attempts"]
          next unless operation && attempts.is_a?(Array)

          selected_attempts = attempts.select do |attempt|
            attempt.is_a?(Hash) && attempt["decision"] == "selected"
          end
          primary = selected_attempts.first
          if primary && provider_ids.include?(primary["provider"]) && operation["amount"].is_a?(Integer)
            primary_counts[primary["provider"]] += 1
            primary_volumes[primary["provider"]] += operation["amount"]
          end
          final_provider = decision["selected_provider"]
          if provider_ids.include?(final_provider) && operation["amount"].is_a?(Integer)
            final_selection_counts[final_provider] += 1
            final_selection_volumes[final_provider] += operation["amount"]
          end

          attempts.each do |attempt|
            next unless attempt.is_a?(Hash)

            unless %w[skipped selected].include?(attempt["decision"])
              add("#{decision["operation_id"]}: attempt decision must be skipped or selected")
              next
            end

            if attempt["decision"] == "skipped"
              reason = attempt["reason"]
              if reason.is_a?(String) && !reason.empty?
                skip_reasons[reason] += 1
                add("#{decision["operation_id"]}: attempt reason must be supported") unless ATTEMPT_REASON_CODES.include?(reason)
              else
                add("#{decision["operation_id"]}: skipped attempt reason must be a non-empty String")
              end
              add("#{decision["operation_id"]}: skipped attempt must not contain simulated_result") if attempt.key?("simulated_result")
            elsif attempt["decision"] == "selected"
              reason = attempt["reason"]
              add("#{decision["operation_id"]}: selected attempt reason must be a non-empty String") unless reason.is_a?(String) && !reason.empty?
              add("#{decision["operation_id"]}: attempt reason must be supported") if reason.is_a?(String) && !reason.empty? && !ATTEMPT_REASON_CODES.include?(reason)
              status = attempt["simulated_result"]
              if attempt_outcomes.key?(status)
                attempt_outcomes[status] += 1
                provider_id = attempt["provider"]
                if provider_ids.include?(provider_id) && operation["amount"].is_a?(Integer)
                  attempt_counts[provider_id] += 1
                  attempt_volumes[provider_id] += operation["amount"]
                  attempt_outcomes_by_provider.fetch(provider_id)[status] += 1
                end
              end
            end
          end

          final_status = decision["simulated_result"]
          final_outcomes[final_status] += 1 if final_outcomes.key?(final_status)
          if final_status == "approved" && provider_ids.include?(decision["selected_provider"]) && operation["amount"].is_a?(Integer)
            settlement_counts[decision["selected_provider"]] += 1
            settlement_volumes[decision["selected_provider"]] += operation["amount"]
          end

          final_index = attempts.each_index.select { |index| attempts[index].is_a?(Hash) && attempts[index]["decision"] == "selected" }.last
          fallback_count += 1 if final_index && attempts.first(final_index).any? do |attempt|
            attempt.is_a?(Hash) && attempt["decision"] == "selected" && attempt.key?("simulated_result")
          end
        end

        validate_hash_counts(report["skip_reasons"], skip_reasons, "report skip_reasons")
        validate_hash_counts(report["outcomes"], attempt_outcomes, "report outcomes")
        validate_hash_counts(report["final_outcomes"], final_outcomes, "report final_outcomes")
        validate_nested_count(report["fallbacks"], fallback_count, "report fallbacks", "count")
        validate_nested_count(report["assignment_totals"], primary_counts.values.sum, "report assignment_totals", "count")
        validate_nested_count(report["assignment_totals"], primary_volumes.values.sum, "report assignment_totals", "volume")
        validate_nested_count(report["traffic_totals"], primary_counts.values.sum, "report traffic_totals", "count")
        validate_nested_count(report["traffic_totals"], primary_volumes.values.sum, "report traffic_totals", "volume")
        validate_nested_count(report["attempt_totals"], attempt_counts.values.sum, "report attempt_totals", "count")
        validate_nested_count(report["attempt_totals"], attempt_volumes.values.sum, "report attempt_totals", "volume")
        validate_nested_count(report["final_selection_totals"], final_selection_counts.values.sum,
          "report final_selection_totals", "count")
        validate_nested_count(report["final_selection_totals"], final_selection_volumes.values.sum,
          "report final_selection_totals", "volume")
        validate_nested_count(report["settlement_totals"], settlement_counts.values.sum, "report settlement_totals", "count")
        validate_nested_count(report["settlement_totals"], settlement_volumes.values.sum, "report settlement_totals", "volume")
        validate_attempt_distribution(
          provider_ids, report["attempt_distribution"], attempt_counts, attempt_volumes,
          attempt_outcomes_by_provider
        )
        validate_provider_amount_distribution(
          provider_ids, report["final_selection_distribution"], final_selection_counts,
          final_selection_volumes, "final_selection_distribution", "final selected providers"
        )
        validate_settlement_distribution(
          provider_ids, report["settlement_distribution"], settlement_counts, settlement_volumes
        )

        success_metrics = report["success_metrics"]
        if success_metrics.is_a?(Hash)
          approved = final_outcomes.fetch("approved")
          total = operations.length
          add("report success_metrics.approved differs from final outcomes") unless success_metrics["approved"] == approved
          add("report success_metrics.total differs from queue") unless success_metrics["total"] == total
          expected_rate = total.zero? ? Rational(0, 1) : Rational(approved, total)
          compare_exact(success_metrics["rate"], expected_rate, "report success_metrics.rate")
        else
          add("report success_metrics must be an Object")
        end
      end

      def validate_hash_counts(actual, expected, label)
        unless actual.is_a?(Hash)
          add("#{label} must be an Object")
          return
        end

        add("#{label} differs from serialized decision populations") unless actual == expected
      end

      def validate_nested_count(actual, expected, label, field)
        unless actual.is_a?(Hash)
          add("#{label} must be an Object")
          return
        end

        add("#{label}.#{field} differs from serialized decision populations") unless actual[field] == expected
      end

      def validate_attempt_distribution(provider_ids, actual, counts, volumes, outcomes)
        unless actual.is_a?(Hash)
          add("report attempt_distribution must be an Object")
          return
        end
        add("report attempt_distribution provider set differs from raw providers") unless actual.keys.sort == provider_ids

        total_count = counts.values.sum
        total_volume = volumes.values.sum
        provider_ids.each do |provider_id|
          entry = actual[provider_id]
          unless entry.is_a?(Hash)
            add("attempt_distribution.#{provider_id} must be an Object")
            next
          end
          add("attempt_distribution.#{provider_id}.count differs from selected attempts") unless entry["count"] == counts.fetch(provider_id)
          add("attempt_distribution.#{provider_id}.volume differs from selected attempts") unless entry["volume"] == volumes.fetch(provider_id)
          count_share = total_count.zero? ? Rational(0, 1) : Rational(counts.fetch(provider_id), total_count)
          volume_share = total_volume.zero? ? Rational(0, 1) : Rational(volumes.fetch(provider_id), total_volume)
          compare_exact(entry["count_share"], count_share, "attempt_distribution.#{provider_id}.count_share")
          compare_exact(entry["volume_share"], volume_share, "attempt_distribution.#{provider_id}.volume_share")
          validate_hash_counts(entry["outcomes"], outcomes.fetch(provider_id), "attempt_distribution.#{provider_id}.outcomes")
        end
      end

      def validate_settlement_distribution(provider_ids, actual, counts, volumes)
        unless actual.is_a?(Hash)
          add("report settlement_distribution must be an Object")
          return
        end
        add("report settlement_distribution provider set differs from raw providers") unless actual.keys.sort == provider_ids

        total_count = counts.values.sum
        total_volume = volumes.values.sum
        provider_ids.each do |provider_id|
          entry = actual[provider_id]
          unless entry.is_a?(Hash)
            add("settlement_distribution.#{provider_id} must be an Object")
            next
          end
          add("settlement_distribution.#{provider_id}.count differs from approved final decisions") unless entry["count"] == counts.fetch(provider_id)
          add("settlement_distribution.#{provider_id}.volume differs from approved final decisions") unless entry["volume"] == volumes.fetch(provider_id)
          count_share = total_count.zero? ? Rational(0, 1) : Rational(counts.fetch(provider_id), total_count)
          volume_share = total_volume.zero? ? Rational(0, 1) : Rational(volumes.fetch(provider_id), total_volume)
          compare_exact(entry["count_share"], count_share, "settlement_distribution.#{provider_id}.count_share")
          compare_exact(entry["volume_share"], volume_share, "settlement_distribution.#{provider_id}.volume_share")
        end
      end

      def validate_provider_amount_distribution(provider_ids, actual, counts, volumes, label, population)
        unless actual.is_a?(Hash)
          add("report #{label} must be an Object")
          return
        end
        add("report #{label} provider set differs from raw providers") unless actual.keys.sort == provider_ids

        total_count = counts.values.sum
        total_volume = volumes.values.sum
        provider_ids.each do |provider_id|
          entry = actual[provider_id]
          unless entry.is_a?(Hash)
            add("#{label}.#{provider_id} must be an Object")
            next
          end
          add("#{label}.#{provider_id}.count differs from #{population}") unless entry["count"] == counts.fetch(provider_id)
          add("#{label}.#{provider_id}.volume differs from #{population}") unless entry["volume"] == volumes.fetch(provider_id)
          count_share = total_count.zero? ? Rational(0, 1) : Rational(counts.fetch(provider_id), total_count)
          volume_share = total_volume.zero? ? Rational(0, 1) : Rational(volumes.fetch(provider_id), total_volume)
          compare_exact(entry["count_share"], count_share, "#{label}.#{provider_id}.count_share")
          compare_exact(entry["volume_share"], volume_share, "#{label}.#{provider_id}.volume_share")
        end
      end

      def validate_distribution(providers, provider_ids, operations, profile, decisions, report)
        distribution = report["distribution"]
        unless distribution.is_a?(Hash)
          add("report distribution must be an Object")
          return
        end
        add("report distribution provider set differs from raw providers") unless distribution.keys.sort == provider_ids

        final_selection_counts = provider_ids.to_h { |provider_id| [provider_id, 0] }
        final_selection_volumes = provider_ids.to_h { |provider_id| [provider_id, 0] }
        primary_counts = provider_ids.to_h { |provider_id| [provider_id, 0] }
        primary_volumes = provider_ids.to_h { |provider_id| [provider_id, 0] }
        decisions.each do |decision|
          next unless decision.is_a?(Hash)
          final_provider = decision["selected_provider"]
          amount = operations.fetch(decision["operation_id"], {})["amount"]
          if final_selection_counts.key?(final_provider)
            final_selection_counts[final_provider] += 1
            final_selection_volumes[final_provider] += amount if amount.is_a?(Integer) && amount >= 1
          end

          primary = Array(decision["attempts"]).find { |attempt| attempt.is_a?(Hash) && attempt["decision"] == "selected" }
          if primary && primary_counts.key?(primary["provider"])
            provider_id = primary["provider"]
            primary_counts[provider_id] += 1
            primary_volumes[provider_id] += amount if amount.is_a?(Integer) && amount >= 1
          end
        end
        add("final selected provider count #{final_selection_counts.values.sum} differs from queue #{operations.length}") unless final_selection_counts.values.sum == operations.length

        count_denominator = operations.length
        volume_denominator = operations.values.sum { |operation| operation["amount"].is_a?(Integer) ? operation["amount"] : 0 }
        target_shares = count_targets(providers, profile)
        volume_target_shares = volume_targets(providers, profile)
        provider_ids.each do |provider_id|
          entry = distribution[provider_id]
          unless entry.is_a?(Hash)
            add("distribution.#{provider_id} must be an Object")
            next
          end
          expected_count = final_selection_counts.fetch(provider_id)
          add("distribution.#{provider_id}.count differs from final selected providers") unless entry["count"] == expected_count
          expected_share = percentage(
            count_denominator.zero? ? Rational(0, 1) : Rational(expected_count, count_denominator)
          )
          expected_volume = final_selection_volumes.fetch(provider_id)
          expected_volume_share = volume_denominator.zero? ? Rational(0, 1) : Rational(expected_volume, volume_denominator)
          compare_percentage(entry["share_pct"], expected_share, "distribution.#{provider_id}.share_pct")
          add("distribution.#{provider_id}.volume differs from final selected providers") unless entry["volume"] == expected_volume
          compare_exact(entry["volume_share"], expected_volume_share, "distribution.#{provider_id}.volume_share")
          compare_percentage(entry["target_pct"], percentage(target_shares.fetch(provider_id)), "distribution.#{provider_id}.target_pct")
          compare_exact(entry["target_count_share"], target_shares.fetch(provider_id), "distribution.#{provider_id}.target_count_share")
          compare_exact(entry["target_volume_share"], volume_target_shares.fetch(provider_id), "distribution.#{provider_id}.target_volume_share")
          compare_exact(
            entry["count_deviation"],
            (count_denominator.zero? ? Rational(0, 1) : Rational(expected_count, count_denominator)) - target_shares.fetch(provider_id),
            "distribution.#{provider_id}.count_deviation"
          )
          compare_exact(
            entry["volume_deviation"],
            expected_volume_share - volume_target_shares.fetch(provider_id),
            "distribution.#{provider_id}.volume_deviation"
          )
        end
        validate_assignment_distribution(
          providers, provider_ids, operations, profile, decisions, report,
          primary_counts: primary_counts, primary_volumes: primary_volumes,
          count_targets: target_shares
        )
      end

      def validate_assignment_distribution(providers, provider_ids, operations, profile, decisions, report,
                                           primary_counts:, primary_volumes:, count_targets:)
        distribution = report["assignment_distribution"]
        unless distribution.is_a?(Hash)
          add("report assignment_distribution must be an Object")
          return
        end
        add("report assignment_distribution provider set differs from raw providers") unless distribution.keys.sort == provider_ids

        total_count = operations.length
        total_volume = operations.values.sum { |operation| operation["amount"].is_a?(Integer) ? operation["amount"] : 0 }
        volume_targets = volume_targets(providers, profile)
        provider_ids.each do |provider_id|
          entry = distribution[provider_id]
          unless entry.is_a?(Hash)
            add("assignment_distribution.#{provider_id} must be an Object")
            next
          end
          expected = {
            "count" => primary_counts.fetch(provider_id),
            "volume" => primary_volumes.fetch(provider_id),
            "count_share" => total_count.zero? ? Rational(0, 1) : Rational(primary_counts.fetch(provider_id), total_count),
            "volume_share" => total_volume.zero? ? Rational(0, 1) : Rational(primary_volumes.fetch(provider_id), total_volume),
            "target_count_share" => count_targets.fetch(provider_id),
            "target_volume_share" => volume_targets.fetch(provider_id)
          }
          expected["count_deviation"] = expected.fetch("count_share") - expected.fetch("target_count_share")
          expected["volume_deviation"] = expected.fetch("volume_share") - expected.fetch("target_volume_share")
          expected.each do |field, value|
            compare_exact(entry[field], value, "assignment_distribution.#{provider_id}.#{field}")
          end
        end
      end

      def count_targets(providers, profile)
        source = profile["count_target_source"]
        unless source == "provider.traffic_percentage"
          add("unsupported count target source #{source.inspect} for semantic report validation")
          return providers.keys.to_h { |provider_id| [provider_id, Rational(0, 1)] }
        end

        configuration = profile["configuration"]
        terminal_provider_id = configuration.is_a?(Hash) ? configuration["terminal_provider_id"] : nil
        targets = providers.each_with_object({}) do |(provider_id, provider), result|
          traffic_percentage = provider["traffic_percentage"]
          unless traffic_percentage.is_a?(Integer) || traffic_percentage.is_a?(Rational)
            add("#{provider_id}: traffic_percentage must be exact")
          end
          participating = provider["status"] == "active" && provider_id != terminal_provider_id &&
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
        end
        validate_target_mass(targets, "count")
        add("count traffic targets must sum exactly to one") unless targets.values.sum == Rational(1, 1)
        targets.freeze
      end

      def volume_targets(providers, profile)
        source = profile["volume_target_source"]
        case source
        when "provider.traffic_percentage"
          count_targets(providers, profile)
        when "configured"
          raw = profile["volume_share"]
          unless raw.is_a?(Hash)
            add("configured volume target source requires a volume_share Object")
            return providers.keys.to_h { |provider_id| [provider_id, Rational(0, 1)] }
          end
          unknown = raw.keys - providers.keys
          add("configured volume_share contains unknown providers: #{unknown.join(', ')}") unless unknown.empty?
          targets = providers.keys.to_h do |provider_id|
            value = raw.fetch(provider_id, Rational(0, 1))
            unless value.is_a?(Integer) || value.is_a?(Rational)
              add("configured volume_share.#{provider_id} must be exact")
              value = Rational(0, 1)
            end
            [provider_id, value]
          end
          validate_target_mass(targets, "volume")
          targets.freeze
        else
          add("unsupported volume target source #{source.inspect} for semantic report validation")
          providers.keys.to_h { |provider_id| [provider_id, Rational(0, 1)] }
        end
      end

      def validate_target_mass(targets, label)
        add("#{label} target shares must be non-negative") if targets.values.any?(&:negative?)
        add("#{label} target shares must sum to at most one") if targets.values.sum > 1
      end

      def validate_utilization(providers, provider_ids, operations, decisions, report, business_calendar)
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
        snapshot_time = business_calendar && business_calendar[:snapshot_time]
        final_day = calendar_day(operation_times.max || snapshot_time, business_calendar) if snapshot_time
        snapshot_day = calendar_day(snapshot_time, business_calendar) if snapshot_time
        approved_volume = provider_ids.to_h { |provider_id| [provider_id, 0] }
        decisions.each do |decision|
          next unless decision.is_a?(Hash) && decision["simulated_result"] == "approved"
          provider_id = decision["selected_provider"]
          operation = operations[decision["operation_id"]]
          next unless operation && approved_volume.key?(provider_id) && operation["amount"].is_a?(Integer)
          operation_day = begin
            calendar_day(Time.iso8601(operation.fetch("created_at")), business_calendar)
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

      def validate_period(operations, business_calendar, report)
        timestamps = operations.values.filter_map do |operation|
          begin
            Time.iso8601(operation.fetch("created_at"))
          rescue KeyError, ArgumentError, TypeError
            add("queue operation has invalid created_at")
            nil
          end
        end
        snapshot = business_calendar && business_calendar[:snapshot_time]
        return unless timestamps.all? && snapshot

        expected = calendar_day(timestamps.min || snapshot, business_calendar)
        add("report period #{report["period"].inspect} differs from authoritative queue period #{expected}") unless report["period"] == expected
      end

      def validate_period_window(operations, report)
        actual = report["period_window"]
        unless actual.is_a?(Hash)
          add("report period_window must be an Object")
          return
        end
        timestamps = operations.values.filter_map do |operation|
          begin
            Time.iso8601(operation.fetch("created_at"))
          rescue KeyError, ArgumentError, TypeError
            nil
          end
        end
        expected = {
          "from" => timestamps.min&.utc&.iso8601,
          "to" => timestamps.max&.utc&.iso8601
        }
        expected.each do |field, value|
          add("report period_window.#{field} differs from raw queue") unless actual[field] == value
        end
      end

      def validate_configuration(providers, provider_ids, profile, report)
        actual = report["configuration"]
        unless actual.is_a?(Hash)
          add("report configuration must be an Object")
          return
        end
        expected_keys = %w[
          provider_ids count_share volume_share weights min_turnovers rpm_limits
          rpm_window_seconds terminal_provider_id simulation_seed simulation_mode
          preferred_amount_ranges source revision
        ]
        add("report configuration contains unsupported or missing fields") unless actual.keys.sort == expected_keys.sort
        add("report configuration.provider_ids differs from raw providers") unless actual["provider_ids"] == provider_ids

        count_target_values = count_targets(providers, profile)
        volume_target_values = volume_targets(providers, profile)
        validate_exact_provider_map(actual["count_share"], count_target_values, "configuration.count_share")
        validate_exact_provider_map(actual["volume_share"], volume_target_values, "configuration.volume_share")

        source_configuration = profile["configuration"] if profile.is_a?(Hash)
        source_configuration = profile unless source_configuration.is_a?(Hash)
        validate_exact_provider_map(actual["weights"], source_configuration["weights"], "configuration.weights")
        validate_exact_provider_map(actual["min_turnovers"], source_configuration.fetch("min_turnovers", {}), "configuration.min_turnovers")
        validate_exact_provider_map(actual["rpm_limits"], source_configuration.fetch("rpm_limits", {}), "configuration.rpm_limits")
        add("report configuration.rpm_window_seconds differs from profile") unless
          actual["rpm_window_seconds"] == source_configuration.fetch("rpm_window_seconds", 60)
        add("report configuration.terminal_provider_id differs from profile") unless
          actual["terminal_provider_id"] == source_configuration["terminal_provider_id"]
        add("report configuration.simulation_seed differs from profile") unless
          actual["simulation_seed"] == source_configuration["simulation_seed"]
        add("report configuration.simulation_mode differs from profile") unless
          actual["simulation_mode"] == source_configuration["simulation_mode"].to_s
        validate_amount_ranges(actual["preferred_amount_ranges"], source_configuration.fetch("preferred_amount_ranges", {}))
        add("report configuration.source differs from profile") unless actual["source"] == profile["source"]
        add("report configuration.revision differs from profile") unless actual["revision"] == profile["revision"]
      rescue KeyError, ArgumentError, TypeError
        add("report configuration cannot be recomputed from the raw profile and providers")
      end

      def validate_submission_profile(profile, report)
        actual = report["submission_profile"]
        unless actual.is_a?(Hash)
          add("report submission_profile must be an Object")
          return
        end
        expected_keys = %w[
          profile_id source revision count_target_source volume_target_source configuration
        ]
        add("report submission_profile contains unsupported or missing fields") unless
          actual.keys.sort == expected_keys.sort
        %w[profile_id source revision count_target_source volume_target_source].each do |field|
          add("report submission_profile.#{field} differs from raw profile") unless
            actual[field] == profile[field]
        end
        add("report submission_profile.configuration differs from report configuration") unless
          actual["configuration"] == report["configuration"]
      rescue TypeError
        add("report submission_profile cannot be recomputed from the raw profile")
      end

      def validate_exact_provider_map(actual, expected, label)
        unless actual.is_a?(Hash) && expected.is_a?(Hash)
          add("report #{label} must be an Object")
          return
        end
        expected_keys = expected.keys.map(&:to_s).sort
        add("report #{label} provider set differs from profile") unless actual.keys.sort == expected_keys
        expected.each do |provider_id, value|
          compare_exact(actual[provider_id.to_s], value, "report #{label}.#{provider_id}")
        end
      end

      def validate_amount_ranges(actual, expected)
        unless actual.is_a?(Hash) && expected.is_a?(Hash)
          add("report configuration.preferred_amount_ranges must be an Object")
          return
        end
        expected_keys = expected.keys.map(&:to_s).sort
        add("report configuration.preferred_amount_ranges provider set differs from profile") unless actual.keys.sort == expected_keys
        expected.each do |provider_id, range|
          entry = actual[provider_id.to_s]
          unless entry.is_a?(Hash)
            add("report configuration.preferred_amount_ranges.#{provider_id} must be an Object")
            next
          end
          add("report configuration.preferred_amount_ranges.#{provider_id}.min differs from profile") unless entry["min"] == range["min"] || entry["min"] == range[:min]
          add("report configuration.preferred_amount_ranges.#{provider_id}.max differs from profile") unless entry["max"] == range["max"] || entry["max"] == range[:max]
        end
      end

      def validate_dataset_metadata(providers_document, operations, history, report)
        dataset = report["dataset"]
        unless dataset.is_a?(Hash)
          add("report dataset must be an Object")
          return
        end
        expected = {
          "snapshot_at" => Time.iso8601(providers_document.fetch("snapshot_at")).utc.iso8601,
          "gateway" => providers_document.fetch("gateway"),
          "merchant" => providers_document.fetch("merchant"),
          "operation_count" => operations.length,
          "queue_volume" => operations.values.sum { |operation| operation["amount"] }
        }
        expected.each do |field, value|
          add("report dataset.#{field} differs from raw inputs") unless dataset[field] == value
        end
        expected_history_rows = history ? history.length : nil
        if expected_history_rows
          add("report dataset.history_rows differs from raw history") unless dataset["history_rows"] == expected_history_rows
        else
          add("report dataset.history_rows must be a non-negative Integer") unless
            dataset["history_rows"].is_a?(Integer) && dataset["history_rows"] >= 0
        end
      rescue KeyError, ArgumentError, TypeError
        add("report dataset cannot be recomputed from raw inputs")
      end

      def validate_history(history, history_path, report)
        actual = report["history"]
        unless actual.is_a?(Hash)
          add("report history must be an Object")
          return
        end
        expected_source = File.basename(history_path.to_s)
        add("report history.source differs from raw history path") unless actual["source"] == expected_source
        add("report history.rows differs from raw history") unless actual["rows"] == history.length
        total_volume = history.sum { |row| row.fetch("amount") }
        add("report history.volume differs from raw history") unless actual["volume"] == total_volume
        add("report history.role is not the canonical non-authoritative role") unless
          actual["role"] == "calibration/trends only; not current eligibility truth"

        expected_by_provider = history.group_by { |row| row.fetch("payment_system") }
        by_provider = actual["by_provider"]
        unless by_provider.is_a?(Hash)
          add("report history.by_provider must be an Object")
          return
        end
        add("report history.by_provider provider set differs from raw history") unless
          by_provider.keys.sort == expected_by_provider.keys.sort

        expected_by_provider.each do |provider_id, rows|
          entry = by_provider[provider_id]
          unless entry.is_a?(Hash)
            add("report history.by_provider.#{provider_id} must be an Object")
            next
          end
          approved_rows = rows.select { |row| row.fetch("status") == "approved" }
          expected = {
            "rows" => rows.length,
            "volume" => rows.sum { |row| row.fetch("amount") },
            "approved" => approved_rows.length,
            "approved_volume" => approved_rows.sum { |row| row.fetch("amount") },
            "rejected" => rows.count { |row| row.fetch("status") == "rejected" },
            "expired" => rows.count { |row| row.fetch("status") == "expired" },
            "p95_latency_sec" => history_percentile(rows.map { |row| row.fetch("latency_sec") }, 95)
          }
          expected.each do |field, value|
            add("report history.by_provider.#{provider_id}.#{field} differs from raw history") unless entry[field] == value
          end
          compare_exact(
            entry["count_share"],
            history.empty? ? Rational(0, 1) : Rational(rows.length, history.length),
            "report history.by_provider.#{provider_id}.count_share"
          )
          compare_exact(
            entry["volume_share"],
            total_volume.zero? ? Rational(0, 1) : Rational(expected.fetch("volume"), total_volume),
            "report history.by_provider.#{provider_id}.volume_share"
          )
          compare_exact(
            entry["approval_rate"],
            rows.empty? ? Rational(0, 1) : Rational(expected.fetch("approved"), rows.length),
            "report history.by_provider.#{provider_id}.approval_rate"
          )
          compare_exact(
            entry["average_latency_sec"],
            rows.empty? ? Rational(0, 1) : Rational(rows.sum { |row| row.fetch("latency_sec") }, rows.length),
            "report history.by_provider.#{provider_id}.average_latency_sec"
          )
        end
      rescue KeyError, ArgumentError, TypeError
        add("report history cannot be recomputed from raw history")
      end

      def history_percentile(values, percentile)
        return 0 if values.empty?

        sorted = values.sort
        index = ((sorted.length * percentile) + 99) / 100 - 1
        sorted.fetch([index, sorted.length - 1].min)
      end

      def validate_provider_state(providers, provider_ids, operations, profile, decisions, report, business_calendar)
        actual = report["provider_state"]
        unless actual.is_a?(Hash)
          add("report provider_state must be an Object")
          return
        end
        add("report provider_state provider set differs from raw providers") unless actual.keys.sort == provider_ids

        profile_configuration = profile["configuration"] if profile.is_a?(Hash)
        profile_configuration = profile unless profile_configuration.is_a?(Hash)
        rpm_limits = profile_configuration["rpm_limits"] if profile_configuration["rpm_limits"].is_a?(Hash)
        rpm_limits ||= {}
        rpm_window_seconds = profile_configuration["rpm_window_seconds"]
        rpm_window_seconds = 60 unless rpm_window_seconds.is_a?(Integer) && rpm_window_seconds.positive?
        operation_times = operations.values.to_h do |operation|
          [operation.fetch("operation_id"), Time.iso8601(operation.fetch("created_at"))]
        end
        final_time = operation_times.values.max || business_calendar&.fetch(:snapshot_time)
        snapshot_time = business_calendar&.fetch(:snapshot_time)
        final_day = calendar_day(final_time, business_calendar) if final_time
        snapshot_day = calendar_day(snapshot_time, business_calendar) if snapshot_time
        cutoff = final_time - rpm_window_seconds if final_time
        events = provider_ids.to_h { |provider_id| [provider_id, []] }

        decisions.each do |decision|
          next unless decision.is_a?(Hash)

          operation_time = operation_times[decision["operation_id"]]
          operation = operations[decision["operation_id"]]
          next unless operation && operation_time
          Array(decision["attempts"]).each do |attempt|
            next unless attempt.is_a?(Hash) && attempt["decision"] == "selected"
            provider_id = attempt["provider"]
            next unless events.key?(provider_id)

            events.fetch(provider_id) << {
              time: operation_time,
              amount: operation["amount"],
              status: attempt["simulated_result"]
            }
          end
        end

        provider_ids.each do |provider_id|
          provider = providers.fetch(provider_id)
          provider_events = events.fetch(provider_id)
          approved_events = provider_events.select { |event| event[:status] == "approved" }
          daily_approved_amount = if final_day && snapshot_day == final_day
            provider.fetch("daily_approved_amount") + approved_events.sum do |event|
              calendar_day(event.fetch(:time), business_calendar) == final_day ? event.fetch(:amount) : 0
            end
          else
            approved_events.sum do |event|
              calendar_day(event.fetch(:time), business_calendar) == final_day ? event.fetch(:amount) : 0
            end
          end
          expected = {
            "provider" => provider_id,
            "daily_approved_amount" => daily_approved_amount,
            "daily_amount_limit" => provider["daily_amount_limit"],
            "baseline_in_progress_count" => provider["in_progress_count"],
            "baseline_in_progress_amount" => provider["in_progress_amount"],
            "transient_in_progress_count" => 0,
            "transient_in_progress_amount" => 0,
            "available_requisites" => provider["available_requisites"],
            "rpm_count" => cutoff ? provider_events.count { |event| event.fetch(:time) > cutoff && event.fetch(:time) <= final_time } : 0,
            "rpm_limit" => rpm_limits[provider_id],
            "routed_count" => approved_events.length,
            "routed_volume" => approved_events.sum { |event| event.fetch(:amount) },
            "approved_count" => approved_events.length,
            "rejected_count" => provider_events.count { |event| event[:status] == "rejected" },
            "expired_count" => provider_events.count { |event| event[:status] == "expired" }
          }
          entry = actual[provider_id]
          unless entry.is_a?(Hash)
            add("provider_state.#{provider_id} must be an Object")
            next
          end
          expected.each do |field, value|
            add("provider_state.#{provider_id}.#{field} differs from raw inputs and decisions") unless entry[field] == value
          end
        end
      rescue KeyError, ArgumentError, TypeError
        add("report provider_state cannot be recomputed from raw inputs and decisions")
      end

      def validate_deviation_causes(provider_ids, profile, decisions, report)
        actual = report["deviation_causes"]
        unless actual.is_a?(Hash)
          add("report deviation_causes must be an Object")
          return
        end
        add("report deviation_causes provider set differs from raw providers") unless actual.keys.sort == provider_ids
        profile_configuration = profile["configuration"] if profile.is_a?(Hash)
        profile_configuration = profile unless profile_configuration.is_a?(Hash)
        terminal_provider_id = profile_configuration["terminal_provider_id"]
        hard_exclusions = provider_ids.to_h { |provider_id| [provider_id, Hash.new(0)] }
        fallback_assignments = provider_ids.to_h { |provider_id| [provider_id, 0] }
        terminal_fallback_assignments = provider_ids.to_h { |provider_id| [provider_id, 0] }
        hard_forced_assignments = derive_hard_forced_assignments(provider_ids, decisions)

        decisions.each do |decision|
          next unless decision.is_a?(Hash)
          attempts = decision["attempts"]
          next unless attempts.is_a?(Array)
          attempts.each do |attempt|
            next unless attempt.is_a?(Hash) && attempt["decision"] == "skipped"
            provider_id = attempt["provider"]
            hard_exclusions.fetch(provider_id)[attempt["reason"]] += 1 if hard_exclusions.key?(provider_id)
          end
          selected_indexes = attempts.each_index.select do |index|
            attempts[index].is_a?(Hash) && attempts[index]["decision"] == "selected"
          end
          primary = selected_indexes.first && attempts.fetch(selected_indexes.first)
          final_index = selected_indexes.last
          next unless primary && final_index
          fallback = attempts.first(final_index).any? do |attempt|
            attempt.is_a?(Hash) && attempt["decision"] == "selected" && attempt.key?("simulated_result")
          end
          final_provider = attempts.fetch(final_index)["provider"]
          fallback_assignments[final_provider] += 1 if fallback_assignments.key?(final_provider) && fallback
          terminal_fallback_assignments[final_provider] += 1 if final_provider == terminal_provider_id && terminal_fallback_assignments.key?(final_provider)
        end

        distribution = report["distribution"]
        provider_ids.each do |provider_id|
          entry = actual[provider_id]
          unless entry.is_a?(Hash)
            add("deviation_causes.#{provider_id} must be an Object")
            next
          end
          add("deviation_causes.#{provider_id}.hard_exclusions differs from skipped attempts") unless
            entry["hard_exclusions"] == hard_exclusions.fetch(provider_id)
          add("deviation_causes.#{provider_id}.fallback_assignments differs from decisions") unless
            entry["fallback_assignments"] == fallback_assignments.fetch(provider_id)
          add("deviation_causes.#{provider_id}.terminal_fallback_assignments differs from decisions") unless
            entry["terminal_fallback_assignments"] == terminal_fallback_assignments.fetch(provider_id)
          add("deviation_causes.#{provider_id}.hard_forced_assignments differs from decisions") unless
            entry["hard_forced_assignments"] == hard_forced_assignments.fetch(provider_id)
          next unless distribution.is_a?(Hash) && distribution[provider_id].is_a?(Hash)

          assignment = distribution[provider_id]
          count_target = exact_ratio(assignment["target_count_share"], "deviation count target")
          count_actual = exact_ratio(assignment["count_share"], "deviation count actual")
          volume_target = exact_ratio(assignment["target_volume_share"], "deviation volume target")
          volume_actual = exact_ratio(assignment["volume_share"], "deviation volume actual")
          compare_exact(entry["target_count_gap"], count_target - count_actual, "deviation_causes.#{provider_id}.target_count_gap") if count_target && count_actual
          compare_exact(entry["target_volume_gap"], volume_target - volume_actual, "deviation_causes.#{provider_id}.target_volume_gap") if volume_target && volume_actual
        end
      end

      def derive_hard_forced_assignments(provider_ids, decisions)
        expected = provider_ids.to_h { |provider_id| [provider_id, 0] }
        decisions.each do |decision|
          next unless decision.is_a?(Hash) && decision["attempts"].is_a?(Array)

          selected = decision["attempts"].find do |attempt|
            attempt.is_a?(Hash) && attempt["decision"] == "selected"
          end
          next unless selected && selected["reason"] == "only_eligible_provider"
          next unless decision["attempts"].any? { |attempt| attempt.is_a?(Hash) && attempt["decision"] == "skipped" }
          final = decision["attempts"].reverse.find do |attempt|
            attempt.is_a?(Hash) && attempt["decision"] == "selected"
          end
          next unless final && final["provider"] == selected["provider"]
          next unless expected.key?(final["provider"])

          expected[final["provider"]] += 1
        end
        expected
      end

      def validate_infeasibility(provider_ids, decisions, report)
        actual = report["infeasibility"]
        unless actual.is_a?(Array)
          add("report infeasibility must be an Array")
          return
        end
        distribution = report["distribution"]
        unless distribution.is_a?(Hash)
          add("report infeasibility cannot be recomputed without distribution")
          return
        end

        hard_forced = derive_hard_forced_assignments(provider_ids, decisions)
        expected = provider_ids.filter_map do |provider_id|
          entry = distribution[provider_id]
          next unless entry.is_a?(Hash)

          count_target = exact_ratio(entry["target_count_share"], "infeasibility count target")
          count_actual = exact_ratio(entry["count_share"], "infeasibility count actual")
          volume_target = exact_ratio(entry["target_volume_share"], "infeasibility volume target")
          volume_actual = exact_ratio(entry["volume_share"], "infeasibility volume actual")
          next unless count_target && count_actual && volume_target && volume_actual
          count_deviation = count_actual - count_target
          volume_deviation = volume_actual - volume_target
          next unless hard_forced.fetch(provider_id).positive? && (count_deviation.positive? || volume_deviation.positive?)

          {
            "provider" => provider_id,
            "reason" => "hard eligibility forced assignments exceed the configured target",
            "count" => {
              "target" => count_target,
              "actual" => count_actual,
              "deviation" => count_deviation
            },
            "volume" => {
              "target" => volume_target,
              "actual" => volume_actual,
              "deviation" => volume_deviation
            },
            "hard_forced_assignments" => hard_forced.fetch(provider_id)
          }
        end

        unless actual.length == expected.length
          add("report infeasibility coverage differs from decisions and distribution")
        end
        actual_by_provider = actual.each_with_object({}) do |entry, result|
          if entry.is_a?(Hash) && entry["provider"].is_a?(String) && !result.key?(entry["provider"])
            result[entry["provider"]] = entry
          else
            add("report infeasibility entries must have unique provider identities")
          end
        end
        expected_by_provider = expected.to_h { |entry| [entry.fetch("provider"), entry] }
        add("report infeasibility provider set differs from decisions and distribution") unless
          actual_by_provider.keys.sort == expected_by_provider.keys.sort
        expected_by_provider.each do |provider_id, expected_entry|
          actual_entry = actual_by_provider[provider_id]
          add("report infeasibility.#{provider_id} differs from decisions and distribution") unless
            actual_entry && actual_entry["provider"] == expected_entry["provider"] &&
            actual_entry["reason"] == expected_entry["reason"] &&
            actual_entry["hard_forced_assignments"] == expected_entry["hard_forced_assignments"]
          next unless actual_entry

          %w[count volume].each do |dimension|
            actual_dimension = actual_entry[dimension]
            expected_dimension = expected_entry.fetch(dimension)
            unless actual_dimension.is_a?(Hash)
              add("report infeasibility.#{provider_id}.#{dimension} must be an Object")
              next
            end
            %w[target actual deviation].each do |field|
              compare_exact(
                actual_dimension[field], expected_dimension.fetch(field),
                "report infeasibility.#{provider_id}.#{dimension}.#{field}"
              )
            end
          end
        end
      end

      def validate_explanations(providers, decisions, report)
        provider_ids = providers.keys.sort
        explanations = report["explanations"]
        unless explanations.is_a?(Hash)
          add("report explanations must be an Object")
          return
        end
        decision_ids = decisions.filter_map { |decision| decision["operation_id"] if decision.is_a?(Hash) }
        if explanations.keys.any? { |key| !key.is_a?(String) }
          add("report explanations keys must be Strings")
        elsif explanations.keys.sort != decision_ids.sort
          add("report explanations coverage differs from decisions")
        end

        terminal_provider_id = report.dig("configuration", "terminal_provider_id") if report["configuration"].is_a?(Hash)
        decisions.each do |decision|
          next unless decision.is_a?(Hash)

          operation_id = decision["operation_id"]
          explanation = explanations[operation_id]
          unless explanation.is_a?(Hash)
            add("explanations.#{operation_id} must be an Object")
            next
          end
          attempts = decision["attempts"]
          next unless attempts.is_a?(Array)

          selected = attempts.select { |attempt| attempt.is_a?(Hash) && attempt["decision"] == "selected" }
          primary = selected.first
          final = selected.last
          expected_hard_exclusions = attempts.filter_map do |attempt|
            next unless attempt.is_a?(Hash) && attempt["decision"] == "skipped"

            { "provider" => attempt["provider"], "reason" => attempt["reason"] }
          end
          expected_failed_attempts = selected.filter_map do |attempt|
            next if attempt["simulated_result"] == "approved"

            {
              "provider" => attempt["provider"],
              "result" => attempt["simulated_result"],
              "reason" => attempt["reason"]
            }
          end
          final_index = attempts.each_index.select do |index|
            attempts[index].is_a?(Hash) && attempts[index]["decision"] == "selected"
          end.last
          expected_fallback = final_index && attempts.first(final_index).any? do |attempt|
            attempt.is_a?(Hash) && attempt["decision"] == "selected" && attempt.key?("simulated_result")
          end
          expected_fallback = false unless expected_fallback

          compare_explanation_field(
            explanation, "selected_provider", decision["selected_provider"],
            "explanations.#{operation_id}.selected_provider differs from decision"
          )
          compare_explanation_field(
            explanation, "primary_assignment_provider", primary && primary["provider"],
            "explanations.#{operation_id}.primary_assignment_provider differs from decision"
          )
          validate_explanation_reason(explanation, "primary_assignment_reason", operation_id)
          validate_explanation_reason(explanation, "selected_reason", operation_id)
          if primary && primary["simulated_result"] == "approved"
            compare_explanation_field(
              explanation, "primary_assignment_reason", primary["reason"],
              "explanations.#{operation_id}.primary_assignment_reason differs from decision"
            )
          end
          if final && final["simulated_result"] == "approved"
            compare_explanation_field(
              explanation, "selected_reason", final["reason"],
              "explanations.#{operation_id}.selected_reason differs from decision"
            )
          end
          compare_explanation_field(
            explanation, "hard_exclusions", expected_hard_exclusions,
            "explanations.#{operation_id}.hard_exclusions differs from decision"
          )
          compare_explanation_field(
            explanation, "failed_attempts", expected_failed_attempts,
            "explanations.#{operation_id}.failed_attempts differs from decision"
          )
          compare_explanation_field(
            explanation, "fallback_continued", expected_fallback,
            "explanations.#{operation_id}.fallback_continued differs from decision"
          )
          compare_explanation_field(
            explanation, "terminal_fallback",
            final && final["provider"] == terminal_provider_id,
            "explanations.#{operation_id}.terminal_fallback differs from decision"
          )

          considered = explanation["considered"]
          unless considered.is_a?(Array)
            add("explanations.#{operation_id}.considered must be an Array")
            next
          end
          expected_considered_providers = selected.filter_map do |attempt|
            attempt["provider"] unless attempt["provider"] == terminal_provider_id
          end
          actual_considered_providers = considered.filter_map do |entry|
            unless entry.is_a?(Hash)
              add("explanations.#{operation_id}.considered entries must be Objects")
              next
            end
            provider = entry["provider"]
            add("explanations.#{operation_id}.considered provider is unknown") unless provider_ids.include?(provider)
            add("explanations.#{operation_id}.considered selected provider differs") unless entry["selected_by_resolver"] == provider
            scores = entry["scores"]
            unless scores.is_a?(Hash)
              add("explanations.#{operation_id}.considered scores must be an Object")
            else
              add("explanations.#{operation_id}.considered score provider is unknown") unless
                scores.keys.all? { |score_provider| provider_ids.include?(score_provider) }
              scores.each do |score_provider, score|
                exact_ratio(score, "explanations.#{operation_id}.considered score #{score_provider}")
              end
            end
            validate_explanation_factors(
              operation_id, entry, scores, report["configuration"], explanation["causal_chain"], providers
            )
            provider
          end
          add("explanations.#{operation_id}.considered coverage differs from selected attempts") unless actual_considered_providers == expected_considered_providers
          validate_explanation_causal_chain(operation_id, explanation, attempts, terminal_provider_id)
          compare_explanation_field(
            explanation, "decision_summary", decision_summary(explanation["causal_chain"]),
            "explanations.#{operation_id}.decision_summary differs from causal_chain"
          )
        end
      end

      def validate_explanation_causal_chain(operation_id, explanation, attempts, terminal_provider_id)
        chain = explanation["causal_chain"]
        unless chain.is_a?(Array) && chain.length == attempts.length
          add("explanations.#{operation_id}.causal_chain coverage differs from attempts")
          return
        end

        selected_seen = 0
        chain.each_with_index do |entry, index|
          label = "explanations.#{operation_id}.causal_chain[#{index}]"
          attempt = attempts[index]
          unless entry.is_a?(Hash)
            add("#{label} must be an Object")
            next
          end
          unless attempt.is_a?(Hash)
            add("#{label} has no corresponding attempt")
            next
          end

          skipped = attempt["decision"] == "skipped"
          terminal = !skipped && attempt["provider"] == terminal_provider_id
          expected_phase = if skipped
            "hard_gate"
          elsif terminal
            "terminal"
          else
            selected_seen += 1
            selected_seen == 1 ? "primary" : "fallback"
          end
          expected_authority = if skipped
            "hard_constraint"
          elsif terminal
            "terminal_policy"
          else
            "resolver"
          end
          expected_selected_by_resolver = skipped || terminal ? nil : attempt["provider"]
          expected_outcome = skipped ? nil : attempt["simulated_result"]
          expected_outcome_reason = if !skipped && attempt["simulated_result"] && attempt["simulated_result"] != "approved"
            attempt["reason"]
          end
          expected_settled = !skipped && attempt["simulated_result"] == "approved"

          add("#{label}.provider differs from attempt") unless entry["provider"] == attempt["provider"]
          add("#{label}.phase differs from attempt lifecycle") unless entry["phase"] == expected_phase
          add("#{label}.decision differs from attempt") unless entry["decision"] == attempt["decision"]
          add("#{label}.selection_authority differs from attempt lifecycle") unless entry["selection_authority"] == expected_authority
          add("#{label}.selected_by_resolver differs from attempt lifecycle") unless entry["selected_by_resolver"] == expected_selected_by_resolver
          add("#{label}.outcome differs from attempt") unless entry["outcome"] == expected_outcome
          add("#{label}.outcome_reason differs from attempt") unless entry["outcome_reason"] == expected_outcome_reason
          add("#{label}.settled differs from attempt") unless entry["settled"] == expected_settled

          selection_reason = entry["selection_reason"]
          add("#{label}.selection_reason must be a supported non-empty reason") unless
            selection_reason.is_a?(String) && !selection_reason.empty? && ATTEMPT_REASON_CODES.include?(selection_reason)
          if skipped || terminal
            add("#{label}.selection_reason differs from attempt") unless selection_reason == attempt["reason"]
          end
        end
        validate_explanation_selection_semantics(operation_id, explanation, chain)
      end

      def decision_summary(chain)
        return nil unless chain.is_a?(Array)

        labels = {
          "payflow" => "PayFlow", "quickpay" => "QuickPay",
          "spacepayments" => "SpacePayments", "vipay" => "VipPay"
        }
        reasons = {
          "bank_not_in_list" => "bank rule", "bank_excluded" => "bank exclusion",
          "amount_below_minimum" => "amount minimum", "amount_exceeds_limit" => "amount limit",
          "daily_amount_limit" => "daily limit", "in_progress_count_limit" => "in-progress count limit",
          "in_progress_amount_limit" => "in-progress amount limit", "inactive_provider" => "provider status",
          "zero_participation" => "zero participation", "no_available_requisite" => "requisites",
          "negative_margin_without_agreement" => "margin rule", "rpm_limit" => "RPM limit",
          "highest_composite_score" => "composite score",
          "fallback_highest_composite_score" => "fallback composite score",
          "only_eligible_provider" => "only eligible provider",
          "external_providers_exhausted" => "external providers exhausted"
        }
        chain.map do |entry|
          provider_id = entry.fetch("provider")
          provider = labels.fetch(provider_id) { provider_id.split(/[-_]/).map(&:capitalize).join }
          case entry.fetch("phase")
          when "hard_gate"
            reason = reasons.fetch(entry.fetch("selection_reason"), entry.fetch("selection_reason").tr("_", " "))
            "#{provider} excluded by #{reason}"
          when "terminal"
            outcome = entry["outcome"]
            outcome ? "#{provider} selected by terminal policy → #{provider} #{outcome}" :
              "#{provider} selected by terminal policy"
          else
            authority = entry.fetch("phase") == "fallback" ? "fallback composite score" : "composite score"
            outcome = entry["outcome"]
            outcome ? "#{provider} selected by #{authority} → #{provider} #{outcome}" :
              "#{provider} selected by #{authority}"
          end
        end.join(" → ")
      end

      def validate_explanation_selection_semantics(operation_id, explanation, chain)
        considered = explanation["considered"]
        return unless considered.is_a?(Array) && chain.is_a?(Array)

        selections = considered.each_with_object({}) do |entry, result|
          next unless entry.is_a?(Hash) && entry["provider"].is_a?(String)

          result[entry["provider"]] = entry
        end
        chain.each do |entry|
          next unless entry.is_a?(Hash) && entry["selection_authority"] == "resolver"

          label = "explanations.#{operation_id}.causal_chain"
          selection = selections[entry["provider"]]
          unless selection
            add("#{label} resolver entry has no considered score evidence")
            next
          end
          scores = selection["scores"]
          unless scores.is_a?(Hash) && !scores.empty?
            add("#{label}.scores must be a non-empty Object for resolver entries")
            next
          end

          ratios = scores.each_with_object({}) do |(provider, score), result|
            value = exact_ratio(score, "#{label}.#{entry["provider"]}.score #{provider}")
            result[provider] = value if value
          end
          next unless ratios.length == scores.length

          maximum = ratios.values.max
          winners = ratios.filter_map { |provider, score| provider if score == maximum }
          expected_provider = winners.min
          add("#{label}.selected_by_resolver differs from recomputed winner") unless
            entry["selected_by_resolver"] == expected_provider

          expected_reason = if ratios.length == 1
            "only_eligible_provider"
          elsif winners.length > 1
            entry["phase"] == "fallback" ? "fallback_deterministic_tie_break" : "deterministic_tie_break"
          else
            entry["phase"] == "fallback" ? "fallback_highest_composite_score" : "highest_composite_score"
          end
          add("#{label}.selection_reason differs from recomputed resolver semantics") unless
            entry["selection_reason"] == expected_reason
        end
      end

      def compare_explanation_field(explanation, field, expected, message)
        add(message) unless explanation.key?(field) && explanation[field] == expected
      end

      def validate_explanation_reason(explanation, field, operation_id)
        value = explanation[field]
        add("explanations.#{operation_id}.#{field} must be a supported non-empty reason") unless
          value.is_a?(String) && !value.empty? && ATTEMPT_REASON_CODES.include?(value)
      end

      def validate_explanation_factors(operation_id, entry, scores, configuration, causal_chain, providers)
        factors = entry["factors"]
        unless factors.is_a?(Hash)
          add("explanations.#{operation_id}.considered factors must be an Object")
          return
        end
        if scores.is_a?(Hash) && factors.keys.sort != scores.keys.sort
          add("explanations.#{operation_id}.considered factor providers differ from scores")
        end
        normalization_evidence = Hash.new { |result, factor| result[factor] = [] }
        expected_weights = explanation_factor_weights(
          operation_id, entry["provider"], configuration, causal_chain
        )
        factors.each do |provider, evidence|
          unless provider.is_a?(String)
            add("explanations.#{operation_id}.considered factor provider must be a String")
            next
          end
          unless evidence.is_a?(Array)
            add("explanations.#{operation_id}.considered factors.#{provider} must be an Array")
            next
          end
          if evidence.empty?
            add("#{label_prefix(operation_id, provider)} factor evidence must not be empty")
            next
          end
          if expected_weights
            actual_factors = evidence.filter_map { |trace| trace["factor"] if trace.is_a?(Hash) }.sort
            add("#{label_prefix(operation_id, provider)} factor keys differ from canonical configuration") unless
              actual_factors == expected_weights.keys.sort
          end
          seen = []
          contribution_total = Rational(0, 1)
          evidence.each_with_index do |trace, index|
            label = "explanations.#{operation_id}.considered factors.#{provider}[#{index}]"
            unless trace.is_a?(Hash)
              add("#{label} must be an Object")
              next
            end
            factor = trace["factor"]
            unless FACTOR_KEYS.include?(factor) && !seen.include?(factor)
              add("#{label}.factor must be a supported unique factor")
            end
            seen << factor if factor.is_a?(String)
            normalized = exact_ratio(trace["normalized"], "#{label}.normalized")
            weight = exact_ratio(trace["weight"], "#{label}.weight")
            contribution = exact_ratio(trace["contribution"], "#{label}.contribution")
            raw = exact_ratio(trace["raw"], "#{label}.raw")
            add("#{label}.reason must be a non-empty String") unless trace["reason"].is_a?(String) && !trace["reason"].empty?
            if FACTOR_KEYS.include?(factor) && raw && normalized
              normalization_evidence[factor] << {
                label: label, provider: provider, raw: raw, normalized: normalized, reason: trace["reason"]
              }
            end
            if expected_weights && expected_weights.key?(factor) && weight
              add("#{label}.weight differs from canonical configuration") unless
                weight == expected_weights.fetch(factor)
            end
            if normalized && weight && contribution
              expected = normalized * weight
              add("#{label}.contribution differs from normalized * weight") unless contribution == expected
              contribution_total += contribution
            end
          end
          if scores.is_a?(Hash) && scores.key?(provider)
            score = exact_ratio(scores[provider], "explanations.#{operation_id}.considered score #{provider}")
            add("#{label_prefix(operation_id, provider)} factor contributions differ from score") if score && contribution_total != score
          end
        end
        validate_explanation_factor_normalization(operation_id, normalization_evidence, providers, configuration)
        validate_explanation_factor_reasons(operation_id, normalization_evidence, providers, configuration)
      end

      def validate_explanation_factor_reasons(operation_id, normalization_evidence, providers, configuration)
        normalization_evidence.each do |factor, evidence|
          next if evidence.empty?

          available = evidence.select do |trace|
            factor_evidence_configured?(factor, trace.fetch(:provider), providers, configuration)
          end
          suffix = "; non-discriminating; no causal contribution" if available.map { |trace| trace.fetch(:raw) }.uniq.length <= 1
          evidence.each do |trace|
            expected = factor_reason(factor, trace.fetch(:raw), trace.fetch(:provider), providers, configuration)
            expected = "#{expected}#{suffix}" if expected && suffix
            next unless expected
            next if trace.fetch(:reason) == expected

            add("#{trace.fetch(:label)}.reason differs from canonical factor semantics")
          end
        end
      end

      def factor_evidence_configured?(factor, provider_id, providers, configuration)
        provider = providers[provider_id]
        return true unless provider.is_a?(Hash)

        case factor
        when "load"
          %w[daily_amount_limit in_progress_count_limit in_progress_amount_limit].any? do |field|
            provider.key?(field) && !provider[field].nil?
          end
        when "intensity"
          configuration.fetch("rpm_limits", {}).is_a?(Hash) && configuration.fetch("rpm_limits", {}).key?(provider_id)
        else
          true
        end
      end

      def factor_reason(factor, raw, provider_id, providers, configuration)
        provider = providers[provider_id]
        return unless provider.is_a?(Hash) && configuration.is_a?(Hash)

        case factor
        when "count"
          "post-decision count portfolio L1 loss=#{(-raw).to_s}"
        when "volume"
          "post-decision volume portfolio L1 loss=#{(-raw).to_s}"
        when "priority"
          "official priority lower-is-higher; preference=#{raw}"
        when "amount"
          ranges = configuration["preferred_amount_ranges"]
          return unless ranges.is_a?(Hash)

          if ranges.key?(provider_id)
            "preferred amount band preference=#{raw}; hard amount gate evaluated separately"
          else
            "preferred amount band absent; neutral/no preference; hard amount gate evaluated separately"
          end
        when "conversion_24h"
          "current conversion_24h=#{raw}"
        when "load"
          configured = %w[daily_amount_limit in_progress_count_limit in_progress_amount_limit].any? do |field|
            provider.key?(field) && !provider[field].nil?
          end
          if configured
            "current daily/concurrent headroom=#{raw}"
          else
            "capacity limits absent; neutral/no load preference"
          end
        when "intensity"
          rpm_limits = configuration["rpm_limits"]
          return unless rpm_limits.is_a?(Hash)

          if rpm_limits.key?(provider_id)
            "rolling RPM headroom=#{raw}"
          else
            "RPM limit absent; neutral/no intensity preference"
          end
        when "turnover_min"
          "minimum-turnover obligation urgency=#{raw}"
        end
      end

      def explanation_factor_weights(operation_id, selected_provider, configuration, causal_chain)
        return unless configuration.is_a?(Hash) && configuration["weights"].is_a?(Hash)
        return unless causal_chain.is_a?(Array)

        resolver_entry = causal_chain.find do |entry|
          entry.is_a?(Hash) && entry["provider"] == selected_provider && entry["selection_authority"] == "resolver"
        end
        return unless resolver_entry

        weights = configuration["weights"].each_with_object({}) do |(factor, value), result|
          parsed = exact_ratio(value, "explanations.#{operation_id}.#{selected_provider}.weight #{factor}")
          result[factor.to_s] = parsed if parsed
        end
        return unless weights.length == configuration["weights"].length

        weights
      end

      def validate_explanation_factor_normalization(operation_id, normalization_evidence, providers, configuration)
        normalization_evidence.each do |factor, evidence|
          next if evidence.empty?

          minimum, maximum = FACTOR_NORMALIZATION_BOUNDS.fetch(factor, [Rational(0, 1), Rational(1, 1)])
          raw_values = evidence.map { |trace| trace.fetch(:raw) }
          if raw_values.any? { |raw| raw < minimum || raw > maximum }
            add("explanations.#{operation_id}.considered factor #{factor} raw value is outside its fixed normalization domain")
            next
          end

          available_raw_values = evidence.select do |trace|
            factor_evidence_configured?(factor, trace.fetch(:provider), providers, configuration)
          end.map { |trace| trace.fetch(:raw) }
          discriminating = available_raw_values.uniq.length > 1
          evidence.each do |trace|
            expected = if discriminating && factor_evidence_configured?(factor, trace.fetch(:provider), providers, configuration)
              scaled = Rational(trace.fetch(:raw) - minimum, maximum - minimum)
              [[scaled, Rational(0, 1)].max, Rational(1, 1)].min
            else
              Rational(0, 1)
            end
            next if trace.fetch(:normalized) == expected

            add("#{trace.fetch(:label)}.normalized differs from fixed semantic scale")
          end
        end
      end

      def label_prefix(operation_id, provider)
        "explanations.#{operation_id}.considered factors.#{provider}"
      end

      def validate_recommendations(provider_ids, operations, decisions, report)
        recommendations = report["recommendations"]
        details = report["recommendation_details"]
        unless recommendations.is_a?(Array)
          add("report recommendations must be an Array")
          return
        end
        unless details.is_a?(Array)
          add("report recommendation_details must be an Array")
          return
        end
        add("report recommendations and recommendation_details must have equal length") unless recommendations.length == details.length

        recommendations.zip(details).each_with_index do |(text, detail), index|
          label = "report recommendation[#{index}]"
          add("#{label} must be a non-empty String") unless text.is_a?(String) && !text.empty?
          unless detail.is_a?(Hash)
            add("#{label} detail must be an Object")
            next
          end

          provider_id = detail["provider"]
          kind = detail["kind"]
          evidence = detail["evidence"]
          action = detail["action"]
          add("#{label} detail provider is unknown") unless provider_ids.include?(provider_id)
          add("#{label} detail kind is unsupported") unless RECOMMENDATION_KINDS.include?(kind)
          add("#{label} detail evidence must be an Object") unless evidence.is_a?(Hash)
          add("#{label} detail action must be a non-empty String") unless action.is_a?(String) && !action.empty?
          if provider_ids.include?(provider_id) && text.is_a?(String) && !text.start_with?("#{provider_id} ")
            add("#{label} text provider differs from detail provider")
          end
          expected_text = recommendation_text(detail, label)
          add("#{label} text differs from its typed detail") if expected_text && text != expected_text
          expected_action = recommendation_action(detail)
          add("#{label} action differs from its typed detail") if expected_action && action != expected_action
          next unless provider_ids.include?(provider_id) && evidence.is_a?(Hash)

          validate_recommendation_distribution_evidence(label, kind, evidence, report, provider_id, decisions)
          validate_recommendation_utilization_evidence(label, kind, evidence, report, provider_id)
          validate_recommendation_workload_evidence(label, kind, evidence, operations, report, provider_id)
          validate_structural_recommendation_evidence(label, kind, evidence, provider_id, operations, decisions, report)
        end
        validate_recommendation_completeness(provider_ids, operations, decisions, report, details)
      end

      def validate_recommendation_completeness(provider_ids, operations, decisions, report, details)
        return unless details.all? do |detail|
          detail.is_a?(Hash) && provider_ids.include?(detail["provider"]) && RECOMMENDATION_KINDS.include?(detail["kind"])
        end

        actual_keys = details.map { |detail| [detail["provider"], detail["kind"]] }
        add("report recommendation set contains duplicate provider/kind entries") unless actual_keys.uniq.length == actual_keys.length
        expected_keys = expected_recommendation_keys(provider_ids, operations, decisions, report)
        return unless expected_keys

        add("report recommendation set differs from independently recomputed conditions") unless
          actual_keys.sort == expected_keys.sort
      end

      def expected_recommendation_keys(provider_ids, operations, decisions, report)
        distribution = report["distribution"]
        causes = report["deviation_causes"]
        return unless distribution.is_a?(Hash) && causes.is_a?(Hash)

        total_count = operations.length
        total_volume = operations.values.sum { |operation| operation["amount"].is_a?(Integer) ? operation["amount"] : 0 }
        terminal_provider_id = report.dig("configuration", "terminal_provider_id")
        utilization = report["projected_daily_utilization"]
        expected = []

        provider_ids.each do |provider_id|
          entry = distribution[provider_id]
          provider_causes = causes[provider_id]
          next unless entry.is_a?(Hash) && provider_causes.is_a?(Hash)

          count_deviation = exact_ratio(entry["count_deviation"], "recommendation count deviation")
          volume_deviation = exact_ratio(entry["volume_deviation"], "recommendation volume deviation")
          target_count = exact_ratio(entry["target_count_share"], "recommendation target count")
          target_volume = exact_ratio(entry["target_volume_share"], "recommendation target volume")
          next unless count_deviation && volume_deviation && target_count && target_volume

          hard_exclusions = provider_causes["hard_exclusions"]
          hard_exclusion_count = if hard_exclusions.is_a?(Hash) && hard_exclusions.values.all? { |value| value.is_a?(Integer) }
            hard_exclusions.values.sum
          end
          hard_forced = provider_causes["hard_forced_assignments"]
          fallback_assignments = provider_causes["fallback_assignments"]
          terminal_fallback_assignments = provider_causes["terminal_fallback_assignments"]
          next unless hard_exclusion_count && hard_forced.is_a?(Integer) && fallback_assignments.is_a?(Integer) &&
            terminal_fallback_assignments.is_a?(Integer)

          capacity = recommendation_hard_capacity(provider_id, operations, decisions)
          count_structurally_unattainable = count_deviation.negative? &&
            target_count * total_count > capacity[:count]
          volume_structurally_unattainable = volume_deviation.negative? &&
            target_volume * total_volume > capacity[:volume]
          structural = hard_exclusion_count.positive? &&
            (count_structurally_unattainable || volume_structurally_unattainable)
          volume_subset = subset_sum_recommendation?(provider_id, entry, operations, total_volume, hard_exclusion_count, hard_forced, fallback_assignments, target_volume)
          volume_workload = volume_workload_recommendation?(entry, operations, total_volume, hard_exclusion_count, hard_forced, target_volume)
          count_workload = count_workload_recommendation?(entry, total_count, hard_exclusion_count, hard_forced, target_count)

          expected << [provider_id, "count_target_unmet"] if count_deviation.negative? && !count_structurally_unattainable
          expected << [provider_id, "volume_target_unmet"] if volume_deviation.negative? &&
            !volume_workload && !volume_subset && !volume_structurally_unattainable
          expected << [provider_id, "target_infeasible_hard_forced"] if hard_forced.positive? &&
            (count_deviation.positive? || volume_deviation.positive?)
          expected << [provider_id, "terminal_fallback_deviation"] if provider_id == terminal_provider_id &&
            terminal_fallback_assignments.positive? && (count_deviation.positive? || volume_deviation.positive?)
          expected << [provider_id, "structurally_constrained_under_target"] if structural
          expected << [provider_id, "workload_granularity"] if count_workload
          expected << [provider_id, "volume_subset_sum_granularity"] if volume_subset
          expected << [provider_id, "volume_workload_granularity"] if volume_workload

          daily = utilization[provider_id] if utilization.is_a?(Hash)
          if daily.is_a?(Hash) && daily["limit"].is_a?(Integer) && daily["limit"].positive? && daily["used"].is_a?(Integer) &&
            Rational(daily["used"], daily["limit"]) >= Rational(9, 10)
            expected << [provider_id, "daily_utilization_near_limit"]
          end
        end
        expected
      end

      def recommendation_hard_capacity(provider_id, operations, decisions)
        excluded = decisions.filter_map do |decision|
          next unless decision.is_a?(Hash)
          attempts = decision["attempts"]
          next unless attempts.is_a?(Array) && attempts.any? do |attempt|
            attempt.is_a?(Hash) && attempt["provider"] == provider_id && attempt["decision"] == "skipped"
          end

          operation = operations[decision["operation_id"]]
          operation if operation.is_a?(Hash) && operation["amount"].is_a?(Integer)
        end
        {
          count: operations.length - excluded.length,
          volume: operations.values.sum { |operation| operation["amount"].is_a?(Integer) ? operation["amount"] : 0 } -
            excluded.sum { |operation| operation["amount"] }
        }
      end

      def count_workload_recommendation?(entry, total_count, hard_exclusion_count, hard_forced, target_count)
        target = target_count * total_count
        return false unless total_count.positive? && target.denominator != 1

        [target.floor, target.ceil].include?(entry["count"]) &&
          hard_exclusion_count.zero? && hard_forced.zero?
      end

      def volume_workload_recommendation?(entry, operations, total_volume, hard_exclusion_count, hard_forced, target_volume)
        minimum_amount = operations.values.map { |operation| operation["amount"] }.select { |amount| amount.is_a?(Integer) }.min
        target = target_volume * total_volume
        gap = target - entry["volume"] if entry["volume"].is_a?(Integer)
        gap && minimum_amount && gap.positive? && gap < minimum_amount && hard_exclusion_count.zero? && hard_forced.zero?
      end

      def subset_sum_recommendation?(provider_id, entry, operations, total_volume, hard_exclusion_count, hard_forced, fallback_assignments, target_volume)
        nearest = subset_sum_nearest_amounts(operations, total_volume, target_volume)
        nearest[:reachable] == false && target_volume.denominator == 1 && target_volume.positive? &&
          entry["volume"].is_a?(Integer) && entry["volume"] < target_volume * total_volume &&
          operations.length >= 2 && operations.length <= SUBSET_SUM_MAX_OPERATIONS && total_volume <= SUBSET_SUM_MAX_VOLUME &&
          hard_exclusion_count.zero? && hard_forced.zero? && fallback_assignments.zero?
      end

      def recommendation_text(detail, label)
        provider = detail["provider"]
        evidence = detail["evidence"]
        kind = detail["kind"]
        return unless provider.is_a?(String) && evidence.is_a?(Hash)

        case kind
        when "count_target_unmet"
          gap = recommendation_percentage(evidence["gap"], "#{label}.evidence.gap")
          gap && "#{provider} is below its count target by #{gap} percentage points; review count target or hard eligibility/capacity."
        when "volume_target_unmet"
          gap = recommendation_percentage(evidence["gap"], "#{label}.evidence.gap")
          gap && "#{provider} is below its volume target by #{gap} percentage points; review volume target or hard eligibility/capacity."
        when "target_infeasible_hard_forced"
          forced = evidence["hard_forced_assignments"]
          "#{provider} is above target because #{forced} assignments were hard-forced; raise the target or improve alternatives." if forced.is_a?(Integer)
        when "structurally_constrained_under_target"
          excluded = evidence["hard_excluded_operations"]
          "#{provider} is below target by observed hard-rule exclusions on #{excluded} operations; review coverage before changing weights." if excluded.is_a?(Integer)
        when "workload_granularity"
          "#{provider} target is bounded by whole-operation granularity; use a larger workload before changing policy."
        when "volume_workload_granularity"
          "#{provider} volume target is bounded by whole-operation granularity; use a larger workload or adjust the target before changing policy."
        when "volume_subset_sum_granularity"
          below = evidence["nearest_attainable_volume_below"]
          above = evidence["nearest_attainable_volume_above"]
          nearest = [below, above].compact.map(&:to_s).join(" or ")
          "#{provider} volume target is not reachable by the bounded whole-operation workload; nearest attainable volume is #{nearest}; use a larger or differently sized workload before changing policy." unless nearest.empty?
        when "daily_utilization_near_limit"
          utilization = recommendation_percentage(evidence["utilization"], "#{label}.evidence.utilization")
          remaining = evidence["remaining"]
          utilization && remaining.is_a?(Integer) && "#{provider} is near its daily limit at #{utilization}%; preserve #{remaining} units of headroom or raise the daily limit."
        when "terminal_fallback_deviation"
          fallback_count = evidence["terminal_fallback_assignments"]
          "#{provider} exceeded its zero target because #{fallback_count} operation(s) used the configured terminal fallback after external hard exclusions; restore external coverage before changing targets." if fallback_count.is_a?(Integer)
        else
          "Review #{provider} routing evidence for #{kind}." if kind.is_a?(String)
        end
      end

      def recommendation_percentage(value, label)
        ratio = exact_ratio(value, label)
        ratio && format("%.2f", (ratio * 100).round(PERCENTAGE_DECIMAL_PLACES).to_f)
      end

      def recommendation_action(detail)
        provider = detail["provider"]
        evidence = detail["evidence"]
        return unless provider.is_a?(String) && evidence.is_a?(Hash)

        case detail["kind"]
        when "count_target_unmet"
          "review count target or hard eligibility/capacity for this provider"
        when "volume_target_unmet"
          "review volume target or hard eligibility/capacity for this provider"
        when "target_infeasible_hard_forced"
          "raise the configured target or improve alternatives' hard eligibility/capacity"
        when "terminal_fallback_deviation"
          "terminal fallback is the configured safety path; restore external coverage before changing traffic targets"
        when "structurally_constrained_under_target"
          "review target and alternative bank/amount/capacity coverage before changing weights"
        when "workload_granularity"
          "use a larger workload before changing policy; whole-operation granularity bounds this target gap"
        when "volume_workload_granularity"
          "use a larger workload or adjust the volume target before changing policy"
        when "volume_subset_sum_granularity"
          "use a larger or differently sized workload, or adjust the volume target before changing policy"
        when "daily_utilization_near_limit"
          remaining = evidence["remaining"]
          "preserve #{remaining} units of daily headroom or raise the daily limit before increasing this target" if remaining.is_a?(Integer)
        end
      end

      def validate_recommendation_distribution_evidence(label, kind, evidence, report, provider_id, decisions)
        distribution = report["distribution"]
        entry = distribution[provider_id] if distribution.is_a?(Hash)
        return unless entry.is_a?(Hash)

        if %w[count_target_unmet volume_target_unmet].include?(kind)
          causes = report["deviation_causes"]
          expected_causes = causes[provider_id] if causes.is_a?(Hash)
          add("#{label}.evidence.causes differs from deviation causes") if
            expected_causes.is_a?(Hash) && evidence["causes"] != expected_causes
        end

        fields = case kind
        when "count_target_unmet"
          { "target" => "target_count_share", "actual" => "count_share", "gap" => :negative_count_deviation }
        when "volume_target_unmet"
          { "target" => "target_volume_share", "actual" => "volume_share", "gap" => :negative_volume_deviation }
        when "target_infeasible_hard_forced", "terminal_fallback_deviation"
          {
            "target_count" => "target_count_share", "actual_count" => "count_share",
            "target_volume" => "target_volume_share", "actual_volume" => "volume_share"
          }
        when "structurally_constrained_under_target"
          {
            "target_count" => "target_count_share", "actual_count" => "count_share",
            "target_volume" => "target_volume_share", "actual_volume" => "volume_share",
            "count_gap" => :negative_count_deviation, "volume_gap" => :negative_volume_deviation
          }
        else
          {}
        end
        fields.each do |field, source|
          expected = if source == :negative_count_deviation
            negative_deviation(entry["count_deviation"])
          elsif source == :negative_volume_deviation
            negative_deviation(entry["volume_deviation"])
          else
            exact_ratio(entry[source], "#{label} distribution source #{source}")
          end
          compare_exact(evidence[field], expected, "#{label}.evidence.#{field}") if expected
        end
        if kind == "count_target_unmet"
          add("#{label} count_target_unmet condition is not met") unless
            negative_deviation(entry["count_deviation"])&.positive?
        elsif kind == "volume_target_unmet"
          add("#{label} volume_target_unmet condition is not met") unless
            negative_deviation(entry["volume_deviation"])&.positive?
        elsif kind == "target_infeasible_hard_forced"
          causes = report["deviation_causes"]
          expected_causes = causes[provider_id] if causes.is_a?(Hash)
          expected_forced = expected_causes["hard_forced_assignments"] if expected_causes.is_a?(Hash)
          add("#{label}.evidence.hard_forced_assignments differs from deviation causes") unless
            expected_forced.is_a?(Integer) && evidence["hard_forced_assignments"] == expected_forced
          add("#{label} target_infeasible_hard_forced condition is not met") unless
            expected_forced.is_a?(Integer) && expected_forced.positive? &&
            (exact_ratio(entry["count_deviation"], "#{label} count deviation")&.positive? ||
              exact_ratio(entry["volume_deviation"], "#{label} volume deviation")&.positive?)
        elsif kind == "terminal_fallback_deviation"
          causes = report["deviation_causes"]
          expected_causes = causes[provider_id] if causes.is_a?(Hash)
          expected_terminal = report.dig("configuration", "terminal_provider_id")
          expected_terminal_count = expected_causes["terminal_fallback_assignments"] if expected_causes.is_a?(Hash)
          expected_alternatives = terminal_exclusion_evidence(provider_id, expected_terminal, decisions)
          add("#{label}.evidence.terminal_fallback_assignments differs from deviation causes") unless
            expected_terminal_count.is_a?(Integer) && evidence["terminal_fallback_assignments"] == expected_terminal_count
          add("#{label}.evidence.hard_excluded_alternatives differs from decisions") unless
            evidence["hard_excluded_alternatives"] == expected_alternatives
          add("#{label} terminal_fallback_deviation condition is not met") unless
            provider_id == expected_terminal && expected_terminal_count.is_a?(Integer) && expected_terminal_count.positive? &&
            (exact_ratio(entry["count_deviation"], "#{label} count deviation")&.positive? ||
              exact_ratio(entry["volume_deviation"], "#{label} volume deviation")&.positive?)
        end
      end

      def terminal_exclusion_evidence(provider_id, terminal_provider_id, decisions)
        return {} unless provider_id == terminal_provider_id

        decisions.each_with_object(Hash.new(0)) do |decision, result|
          next unless decision.is_a?(Hash)
          attempts = decision["attempts"]
          next unless attempts.is_a?(Array)
          selected = attempts.select { |attempt| attempt.is_a?(Hash) && attempt["decision"] == "selected" }
          next if selected.empty? || selected.last["provider"] != terminal_provider_id

          attempts.each do |attempt|
            next unless attempt.is_a?(Hash) && attempt["decision"] == "skipped"
            result[attempt["reason"]] += 1
          end
        end
      end

      def validate_recommendation_utilization_evidence(label, kind, evidence, report, provider_id)
        return unless kind == "daily_utilization_near_limit"

        utilization = report["projected_daily_utilization"]
        entry = utilization[provider_id] if utilization.is_a?(Hash)
        return unless entry.is_a?(Hash)

        add("#{label}.evidence.used differs from projected utilization") unless evidence["used"] == entry["used"]
        add("#{label}.evidence.limit differs from projected utilization") unless evidence["limit"] == entry["limit"]
        expected_remaining = entry["limit"] - entry["used"] if entry["limit"].is_a?(Integer) && entry["used"].is_a?(Integer)
        add("#{label}.evidence.remaining differs from projected utilization") unless evidence["remaining"] == expected_remaining
        expected_utilization = if entry["limit"].is_a?(Integer) && entry["limit"].positive? && entry["used"].is_a?(Integer)
          Rational(entry["used"], entry["limit"])
        end
        compare_exact(evidence["utilization"], expected_utilization, "#{label}.evidence.utilization") if expected_utilization
        add("#{label} daily_utilization_near_limit condition is not met") unless
          expected_utilization && expected_utilization >= Rational(9, 10)
      end

      def validate_recommendation_workload_evidence(label, kind, evidence, operations, report, provider_id)
        distribution = report["distribution"]
        entry = distribution[provider_id] if distribution.is_a?(Hash)
        return unless entry.is_a?(Hash)

        if %w[workload_granularity volume_workload_granularity volume_subset_sum_granularity].include?(kind)
          add("#{label}.evidence.operation_count differs from queue") unless evidence["operation_count"] == operations.length
        end
        if %w[volume_workload_granularity volume_subset_sum_granularity].include?(kind)
          total_volume = operations.values.sum { |operation| operation["amount"].is_a?(Integer) ? operation["amount"] : 0 }
          add("#{label}.evidence.total_volume differs from queue") unless evidence["total_volume"] == total_volume
          target_volume = exact_ratio(entry["target_volume_share"], "#{label} target volume")
          compare_exact(
            evidence["target_volume"],
            target_volume * total_volume,
            "#{label}.evidence.target_volume"
          ) if target_volume
          add("#{label}.evidence.actual_volume differs from assignment distribution") unless evidence["actual_volume"] == entry["volume"]
          if kind == "volume_workload_granularity"
            expected_target_volume = target_volume * total_volume if target_volume
            expected_gap = expected_target_volume - entry["volume"] if expected_target_volume && entry["volume"].is_a?(Integer)
            minimum_amount = operations.values.map { |operation| operation["amount"] }.select { |amount| amount.is_a?(Integer) }.min
            compare_exact(evidence["gap"], expected_gap, "#{label}.evidence.gap") if expected_gap
            add("#{label}.evidence.minimum_operation_amount differs from queue") unless
              evidence["minimum_operation_amount"] == minimum_amount
            causes = report["deviation_causes"]
            provider_causes = causes[provider_id] if causes.is_a?(Hash)
            hard_exclusions = provider_causes["hard_exclusions"] if provider_causes.is_a?(Hash)
            hard_exclusion_count = if hard_exclusions.is_a?(Hash) && hard_exclusions.values.all? { |value| value.is_a?(Integer) }
              hard_exclusions.values.sum
            end
            hard_forced = provider_causes["hard_forced_assignments"] if provider_causes.is_a?(Hash)
            add("#{label} volume_workload_granularity condition is not met") unless
              expected_gap && minimum_amount && expected_gap.positive? && expected_gap < minimum_amount &&
              hard_exclusion_count == 0 && hard_forced == 0
          elsif kind == "volume_subset_sum_granularity"
            expected_target_volume = target_volume * total_volume if target_volume
            expected_search_bound = "#{SUBSET_SUM_MAX_OPERATIONS} operations / #{SUBSET_SUM_MAX_VOLUME} volume units"
            add("#{label}.evidence.search_bound differs from the bounded oracle") unless
              evidence["search_bound"] == expected_search_bound
            nearest = subset_sum_nearest_amounts(operations, total_volume, expected_target_volume)
            compare_exact(
              evidence["nearest_attainable_volume_below"], nearest[:below],
              "#{label}.evidence.nearest_attainable_volume_below"
            ) if nearest[:below]
            compare_exact(
              evidence["nearest_attainable_volume_above"], nearest[:above],
              "#{label}.evidence.nearest_attainable_volume_above"
            ) if nearest[:above]
            causes = report["deviation_causes"]
            provider_causes = causes[provider_id] if causes.is_a?(Hash)
            hard_exclusions = provider_causes["hard_exclusions"] if provider_causes.is_a?(Hash)
            hard_exclusion_count = if hard_exclusions.is_a?(Hash) && hard_exclusions.values.all? { |value| value.is_a?(Integer) }
              hard_exclusions.values.sum
            end
            hard_forced = provider_causes["hard_forced_assignments"] if provider_causes.is_a?(Hash)
            fallback_assignments = provider_causes["fallback_assignments"] if provider_causes.is_a?(Hash)
            add("#{label} volume_subset_sum_granularity condition is not met") unless
              nearest[:reachable] == false && expected_target_volume&.denominator == 1 &&
              expected_target_volume.positive? && entry["volume"].is_a?(Integer) &&
              entry["volume"] < expected_target_volume && operations.length >= 2 &&
              operations.length <= SUBSET_SUM_MAX_OPERATIONS && total_volume <= SUBSET_SUM_MAX_VOLUME &&
              hard_exclusion_count == 0 && hard_forced == 0 && fallback_assignments == 0
          end
        end
        if kind == "workload_granularity"
          target_count_share = exact_ratio(entry["target_count_share"], "#{label} target count")
          target_count = target_count_share * operations.length if target_count_share
          compare_exact(
            evidence["target_count"],
            target_count,
            "#{label}.evidence.target_count"
          ) if target_count
          add("#{label}.evidence.actual_count differs from assignment distribution") unless evidence["actual_count"] == entry["count"]
          expected_counts = [target_count.floor, target_count.ceil] if target_count
          add("#{label}.evidence.attainable_counts differs from the exact target") unless
            evidence["attainable_counts"] == expected_counts
          causes = report["deviation_causes"]
          provider_causes = causes[provider_id] if causes.is_a?(Hash)
          hard_exclusions = provider_causes["hard_exclusions"] if provider_causes.is_a?(Hash)
          hard_exclusion_count = if hard_exclusions.is_a?(Hash) && hard_exclusions.values.all? { |value| value.is_a?(Integer) }
            hard_exclusions.values.sum
          end
          hard_forced = provider_causes["hard_forced_assignments"] if provider_causes.is_a?(Hash)
          add("#{label} workload_granularity condition is not met") unless
            target_count && target_count.denominator != 1 &&
            expected_counts.include?(entry["count"]) && hard_exclusion_count == 0 && hard_forced == 0
        end
      end

      def subset_sum_nearest_amounts(operations, total_volume, target_volume)
        invalid = { reachable: nil, below: nil, above: nil }
        return invalid unless target_volume && target_volume.denominator == 1
        return invalid unless total_volume.is_a?(Integer) && total_volume >= 0
        return invalid if operations.length > SUBSET_SUM_MAX_OPERATIONS || total_volume > SUBSET_SUM_MAX_VOLUME

        amounts = operations.values.map { |operation| operation["amount"] }
        return invalid unless amounts.all? { |amount| amount.is_a?(Integer) && amount >= 0 }

        target = target_volume.to_i
        return invalid if target.negative? || target > total_volume

        mask = (1 << (total_volume + 1)) - 1
        reachable = 1
        amounts.each { |amount| reachable = (reachable | (reachable << amount)) & mask }
        nearest = {
          reachable: reachable[target] == 1,
          below: target.downto(0).find { |amount| reachable[amount] == 1 },
          above: target.upto(total_volume).find { |amount| reachable[amount] == 1 }
        }
        nearest
      end

      def validate_structural_recommendation_evidence(label, kind, evidence, provider_id, operations, decisions, report)
        return unless kind == "structurally_constrained_under_target"

        excluded_operations = decisions.filter_map do |decision|
          next unless decision.is_a?(Hash)
          attempts = decision["attempts"]
          next unless attempts.is_a?(Array) && attempts.any? do |attempt|
            attempt.is_a?(Hash) && attempt["provider"] == provider_id && attempt["decision"] == "skipped"
          end

          operation = operations[decision["operation_id"]]
          operation if operation.is_a?(Hash)
        end
        excluded_volume = excluded_operations.sum { |operation| operation.fetch("amount") }
        expected_count = operations.length - excluded_operations.length
        expected_volume = operations.values.sum { |operation| operation.fetch("amount") } - excluded_volume
        causes = report.fetch("deviation_causes").fetch(provider_id)
        add("#{label}.evidence.hard_excluded_operations differs from decisions") unless
          evidence["hard_excluded_operations"] == excluded_operations.length
        add("#{label}.evidence.hard_exclusion_reasons differs from deviation causes") unless
          evidence["hard_exclusion_reasons"] == causes.fetch("hard_exclusions")
        add("#{label}.evidence.hard_eligible_operations differs from decisions") unless
          evidence["hard_eligible_operations"] == expected_count
        add("#{label}.evidence.hard_eligible_volume differs from decisions") unless
          evidence["hard_eligible_volume"] == expected_volume

        distribution = report.fetch("distribution").fetch(provider_id)
        target_count = exact_ratio(distribution.fetch("target_count_share"), "#{label} target count")
        target_volume = exact_ratio(distribution.fetch("target_volume_share"), "#{label} target volume")
        count_deviation = exact_ratio(distribution.fetch("count_deviation"), "#{label} count deviation")
        volume_deviation = exact_ratio(distribution.fetch("volume_deviation"), "#{label} volume deviation")
        expected_measures = []
        expected_measures << "count" if target_count && count_deviation && count_deviation.negative? &&
          target_count * operations.length > expected_count
        expected_measures << "volume" if target_volume && volume_deviation && volume_deviation.negative? &&
          target_volume * operations.values.sum { |operation| operation.fetch("amount") } > expected_volume
        add("#{label}.evidence.structurally_unattainable_measures differs from decisions") unless
          evidence["structurally_unattainable_measures"] == expected_measures
      rescue KeyError, TypeError
        add("#{label} structural evidence cannot be recomputed from raw decisions")
      end

      def negative_deviation(value)
        deviation = exact_ratio(value, "recommendation deviation")
        deviation && (deviation.negative? ? -deviation : Rational(0, 1))
      end

      def business_calendar_for(providers_document)
        snapshot_value = providers_document.fetch("snapshot_at")
        snapshot_time = Time.iso8601(snapshot_value)
        calendar = BusinessCalendar.from(snapshot_value)
        { calendar: calendar, snapshot_time: snapshot_time }
      rescue KeyError, ArgumentError, TypeError, InputError => error
        add("providers snapshot_at is invalid: #{error.message}")
        nil
      end

      def calendar_day(value, business_calendar)
        return nil unless business_calendar

        business_calendar.fetch(:calendar).date_for(value)
      end

      def compare_percentage(actual, expected, label)
        unless actual.is_a?(Numeric) && actual.finite?
          add("#{label} must be a finite numeric percentage")
          return
        end
        add("#{label} #{actual} differs from recomputed #{expected}") unless actual.to_f == expected.to_f
      end

      def compare_exact(actual, expected, label)
        value = exact_ratio(actual, label)
        return unless value

        add("#{label} #{actual.inspect} differs from recomputed #{expected}") unless value == expected
      end

      def exact_ratio(value, label)
        return Rational(value, 1) if value.is_a?(Integer)
        if value.is_a?(String) && (match = /\A(-?\d+)\/([1-9]\d*)\z/.match(value))
          return Rational(match[1].to_i, match[2].to_i)
        end

        add("#{label} must be an exact Integer or numerator/denominator String")
        nil
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
