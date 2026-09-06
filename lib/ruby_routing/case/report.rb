# frozen_string_literal: true

module RubyRouting
  module Case
    class Report
      attr_reader :value

      def initialize(value)
        @value = Input.deep_freeze(value)
        freeze
      end

      def to_h
        value
      end
    end

    class HistoryAnalytics
      def initialize(entries, source: "operations_history.csv")
        @entries = entries
        @source = source
      end

      def call
        total_rows = @entries.length
        total_volume = @entries.sum(&:amount)
        providers = @entries.group_by(&:payment_system).each_with_object({}) do |(provider_id, rows), result|
          approved = rows.count { |row| row.status == "approved" }
          volume = rows.sum(&:amount)
          approved_volume = rows.select { |row| row.status == "approved" }.sum(&:amount)
          result[provider_id] = {
            rows: rows.length,
            volume: volume,
            count_share: total_rows.zero? ? Rational(0, 1) : Rational(rows.length, total_rows),
            volume_share: total_volume.zero? ? Rational(0, 1) : Rational(volume, total_volume),
            approved: approved,
            approved_volume: approved_volume,
            rejected: rows.count { |row| row.status == "rejected" },
            expired: rows.count { |row| row.status == "expired" },
            approval_rate: rows.empty? ? Rational(0, 1) : Rational(approved, rows.length),
            average_latency_sec: rows.empty? ? Rational(0, 1) : Rational(rows.sum(&:latency_sec), rows.length),
            p95_latency_sec: percentile(rows.map(&:latency_sec), 95)
          }
        end
        {
          source: @source,
          rows: @entries.length,
          volume: total_volume,
          by_provider: providers,
          role: "calibration/trends only; not current eligibility truth"
        }.freeze
      end

      private

      def percentile(values, percentile)
        return 0 if values.empty?
        sorted = values.sort
        index = ((sorted.length * percentile) + 99) / 100 - 1
        sorted.fetch([index, sorted.length - 1].min)
      end
    end

    class ReportBuilder
      def initialize(dataset, state, traffic, configuration, decisions, profile: nil,
                     attempt_ledger: nil, settlement_ledger: nil)
        @dataset = dataset
        @state = state
        @traffic = traffic
        @configuration = configuration
        @decisions = decisions
        @profile = profile
        @operations_by_id = @dataset.operations.to_h { |operation| [operation.operation_id, operation] }
        @attempt_ledger = attempt_ledger || build_attempt_ledger
        @settlement_ledger = settlement_ledger || build_settlement_ledger
      end

      def call
        attempt_outcomes = @attempt_ledger.by_outcome
        final_outcomes = Hash.new(0)
        fallback_count = 0
        skip_reasons = Hash.new(0)
        @decisions.each do |decision|
          final_outcomes[decision.simulated_result] += 1
          fallback_count += 1 if fallback?(decision)
          decision.attempts.each do |attempt|
            skip_reasons[attempt.reason] += 1 if attempt.decision == :skipped
          end
        end
        Report.new(
          version: "0.4.1",
          ratio_representation: "integer or numerator/denominator string; exact Rational values are never serialized as Float",
          period: period,
          total_operations: @dataset.operations.length,
          dataset: {
            snapshot_at: @dataset.snapshot_at.iso8601,
            gateway: @dataset.gateway,
            merchant: @dataset.merchant,
            history_rows: @dataset.history.length,
            operation_count: @dataset.operations.length,
            queue_volume: @dataset.operations.sum(&:amount)
          },
          configuration: @configuration.to_h,
          submission_profile: @profile&.to_h,
          outcomes: %w[approved rejected expired].each_with_object({}) do |status, result|
            result[status] = attempt_outcomes.fetch(status.to_sym, 0)
          end,
          final_outcomes: %w[approved rejected expired].each_with_object({}) { |status, result| result[status] = final_outcomes[status] },
          success_metrics: success_metrics(final_outcomes),
          assignment_distribution: @traffic.distribution,
          assignment_totals: { count: @traffic.total_count, volume: @traffic.total_volume },
          attempt_distribution: @attempt_ledger.distribution,
          attempt_totals: { count: @attempt_ledger.total_count, volume: @attempt_ledger.total_volume },
          settlement_distribution: @settlement_ledger.distribution,
          settlement_totals: { count: @settlement_ledger.total_count, volume: @settlement_ledger.total_volume },
          distribution: @traffic.distribution,
          traffic_totals: { count: @traffic.total_count, volume: @traffic.total_volume },
          fallbacks: { count: fallback_count },
          skip_reasons: skip_reasons,
          provider_state: provider_state,
          utilization: utilization(provider_state),
          deviation_causes: deviation_causes,
          infeasibility: infeasibility,
          explanations: explanations,
          history: HistoryAnalytics.new(@dataset.history, source: @dataset.history_source).call,
          recommendations: recommendations
        )
      end

      private

      def period
        timestamps = @dataset.operations.map(&:created_at)
        {
          from: timestamps.min&.iso8601,
          to: timestamps.max&.iso8601
        }.freeze
      end

      def success_metrics(final_outcomes)
        approved = final_outcomes["approved"]
        total = @dataset.operations.length
        {
          approved: approved,
          total: total,
          rate: total.zero? ? Rational(0, 1) : Rational(approved, total)
        }.freeze
      end

      def provider_state
        @provider_state ||= @state.snapshots(as_of: @dataset.operations.map(&:created_at).max || @dataset.snapshot_at)
      end

      def utilization(snapshots)
        @dataset.providers.each_with_object({}) do |provider, result|
          snapshot = snapshots.fetch(provider.payment_system)
          result[provider.payment_system] = {
            daily_approved: ratio(snapshot[:daily_approved_amount], snapshot[:daily_amount_limit]),
            in_progress_count: ratio(
              snapshot[:baseline_in_progress_count] + snapshot[:transient_in_progress_count],
              provider.in_progress_count_limit
            ),
            in_progress_amount: ratio(
              snapshot[:baseline_in_progress_amount] + snapshot[:transient_in_progress_amount],
              provider.in_progress_amount_limit
            ),
            rpm: ratio(snapshot[:rpm_count], snapshot[:rpm_limit])
          }.freeze
        end.freeze
      end

      def ratio(numerator, denominator)
        return nil if denominator.nil? || denominator.zero?

        Rational(numerator, denominator)
      end

      def terminal_provider_id
        @configuration.terminal_provider_id || @dataset.providers.find(&:self_provider?)&.payment_system
      end

      def deviation_causes
        @deviation_causes ||= begin
          decisions_by_primary = @decisions.group_by { |decision| primary_provider(decision) }
          exclusions_by_provider = @decisions.each_with_object(Hash.new { |hash, key| hash[key] = Hash.new(0) }) do |decision, result|
            decision.attempts.each do |attempt|
              result[attempt.provider][attempt.reason] += 1 if attempt.hard_skipped?
            end
          end
          @traffic.distribution.each_with_object({}) do |(provider_id, values), result|
            provider_decisions = decisions_by_primary.fetch(provider_id, [])
            result[provider_id] = {
              hard_forced_assignments: provider_decisions.count { |decision| hard_forced?(decision) },
              fallback_assignments: provider_decisions.count { |decision| fallback?(decision) },
              hard_exclusions: exclusions_by_provider.fetch(provider_id, {}).dup,
              target_count_gap: -values[:count_deviation],
              target_volume_gap: -values[:volume_deviation]
            }.freeze
          end.freeze
        end
      end

      def hard_forced?(decision)
        assigned = assignment_attempt(decision)
        assigned&.selection && assigned.selection.fetch(:factors).length == 1
      end

      def fallback?(decision)
        selected_indexes = decision.attempts.each_index.select { |index| decision.attempts[index].decision == :selected }
        final_index = selected_indexes.last
        final_index && decision.attempts.first(final_index).any? { |attempt| attempt.status }
      end

      def infeasibility
        @traffic.distribution.filter_map do |provider_id, values|
          causes = deviation_causes.fetch(provider_id)
          next unless causes[:hard_forced_assignments].positive?
          next unless values[:count_deviation].positive? || values[:volume_deviation].positive?

          {
            provider: provider_id,
            reason: "hard eligibility forced assignments exceed the configured target",
            count: {
              target: values[:target_count_share], actual: values[:count_share],
              deviation: values[:count_deviation]
            },
            volume: {
              target: values[:target_volume_share], actual: values[:volume_share],
              deviation: values[:volume_deviation]
            },
            hard_forced_assignments: causes[:hard_forced_assignments]
          }
        end
      end

      def explanations
        @decisions.to_h do |decision|
          selected_attempts = decision.attempts.select { |attempt| attempt.decision == :selected }
          primary = selected_attempts.first
          selected = selected_attempts.last
          hard_exclusions = decision.attempts.filter_map do |attempt|
            next unless attempt.decision == :skipped && attempt.status.nil?

            { provider: attempt.provider, reason: attempt.reason }
          end
          failed_attempts = decision.attempts.filter_map do |attempt|
            next unless attempt.attempted? && attempt.status != :approved

            { provider: attempt.provider, result: attempt.status.to_s, reason: attempt.reason }
          end
          considered = decision.attempts.filter_map do |attempt|
            next unless attempt.selection

            {
              provider: attempt.provider,
              scores: attempt.selection.fetch(:scores),
              selected_by_resolver: attempt.selection.fetch(:selected_provider)
            }
          end
          [
            decision.operation_id,
            {
              selected_provider: decision.selected_provider,
              selected_reason: selected&.reason,
              primary_assignment_provider: primary&.provider,
              primary_assignment_reason: primary&.reason,
              hard_exclusions: hard_exclusions,
              considered: considered,
              failed_attempts: failed_attempts,
              fallback_continued: fallback?(decision),
              terminal_fallback: selected&.provider == terminal_provider_id
            }
          ]
        end
      end

      def recommendations
        @traffic.distribution.each_with_object([]) do |(provider_id, values), result|
          if values[:count_deviation].negative?
            result << {
              kind: "count_target_unmet",
              provider: provider_id,
              evidence: {
                target: values[:target_count_share], actual: values[:count_share],
                gap: -values[:count_deviation],
                causes: deviation_causes.fetch(provider_id)
              },
              action: "review count target or hard eligibility/capacity for this provider"
            }
          end
          if values[:volume_deviation].negative?
            result << {
              kind: "volume_target_unmet",
              provider: provider_id,
              evidence: {
                target: values[:target_volume_share], actual: values[:volume_share],
                gap: -values[:volume_deviation],
                causes: deviation_causes.fetch(provider_id)
              },
              action: "review volume target or hard eligibility/capacity for this provider"
            }
          end
          causes = deviation_causes.fetch(provider_id)
          if causes[:hard_forced_assignments].positive? &&
             (values[:count_deviation].positive? || values[:volume_deviation].positive?)
            result << {
              kind: "target_infeasible_hard_forced",
              provider: provider_id,
              evidence: {
                target_count: values[:target_count_share], actual_count: values[:count_share],
                target_volume: values[:target_volume_share], actual_volume: values[:volume_share],
                hard_forced_assignments: causes[:hard_forced_assignments]
              },
              action: "raise the configured target or improve alternatives' hard eligibility/capacity"
            }
          end
        end
      end

      def assignment_attempt(decision)
        decision.attempts.find { |attempt| attempt.status }
      end

      def primary_provider(decision)
        assignment_attempt(decision)&.provider
      end

      def build_attempt_ledger
        ledger = AttemptLedger.new(@dataset.providers.map(&:payment_system))
        @decisions.each do |decision|
          decision.attempts.each do |attempt|
            next unless attempt.status

            ledger.record!(provider_id: attempt.provider, amount: operation_for(decision).amount, status: attempt.status)
          end
        end
        ledger
      end

      def build_settlement_ledger
        ledger = SettlementLedger.new(@dataset.providers.map(&:payment_system))
        @decisions.each do |decision|
          next unless decision.simulated_result == "approved"

          ledger.record!(provider_id: decision.selected_provider, amount: operation_for(decision).amount)
        end
        ledger
      end

      def operation_for(decision)
        @operations_by_id[decision.operation_id]
      end
    end

    module Serializer
      module_function

      def write_json(path, value)
        File.write(path, JSON.generate(json_value(value)) + "\n")
      rescue SystemCallError => error
        raise OutputError, "cannot write #{path}: #{error.message}"
      end

      def json_value(value)
        case value
        when Rational
          # Exact ratios stay exact at the JSON boundary: integral values use
          # JSON integers; fractional values use a stable, judge-readable
          # numerator/denominator string rather than an inexact Float.
          value.denominator == 1 ? value.numerator : "#{value.numerator}/#{value.denominator}"
        when Hash
          value.each_with_object({}) { |(key, nested), result| result[key.to_s] = json_value(nested) }
        when Array
          value.map { |nested| json_value(nested) }
        else
          value
        end
      end
    end
  end
end
