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
      REPORT_VERSION = VERSION
      PERCENTAGE_DECIMAL_PLACES = 2
      SUBSET_SUM_MAX_OPERATIONS = 64
      SUBSET_SUM_MAX_VOLUME = 250_000

      def initialize(dataset, state, traffic, configuration, decisions, profile: nil,
                     primary_assignment_ledger: nil, attempt_ledger: nil, settlement_ledger: nil)
        @dataset = dataset
        @state = state
        @traffic = traffic
        @configuration = configuration
        @decisions = decisions
        @profile = profile
        @operations_by_id = @dataset.operations.to_h { |operation| [operation.operation_id, operation] }
        @primary_assignment_ledger = primary_assignment_ledger || build_primary_assignment_ledger
        @attempt_ledger = attempt_ledger || build_attempt_ledger
        @final_selection_ledger = build_final_selection_ledger
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
        details = recommendation_details
        # The organizer-facing base distribution describes where each payout
        # finally landed. Primary assignments remain available as the
        # explicitly named assignment_distribution population below.
        report_distribution = organizer_distribution(final_distribution)
        snapshots = provider_state
        Report.new(
          version: REPORT_VERSION,
          ratio_representation: "integer or numerator/denominator string; exact Rational values are never serialized as Float",
          period: period,
          period_window: period_window,
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
          assignment_distribution: @primary_assignment_ledger.distribution,
          assignment_totals: {
            count: @primary_assignment_ledger.total_count,
            volume: @primary_assignment_ledger.total_volume
          },
          attempt_distribution: @attempt_ledger.distribution,
          attempt_totals: { count: @attempt_ledger.total_count, volume: @attempt_ledger.total_volume },
          final_selection_distribution: @final_selection_ledger.distribution,
          final_selection_totals: {
            count: @final_selection_ledger.total_count,
            volume: @final_selection_ledger.total_volume
          },
          settlement_distribution: @settlement_ledger.distribution,
          settlement_totals: { count: @settlement_ledger.total_count, volume: @settlement_ledger.total_volume },
          distribution: report_distribution,
          traffic_totals: { count: @traffic.total_count, volume: @traffic.total_volume },
          fallbacks: { count: fallback_count },
          skip_reasons: skip_reasons,
          provider_state: snapshots,
          projected_daily_utilization: projected_daily_utilization(snapshots),
          utilization: utilization(snapshots),
          deviation_causes: deviation_causes,
          infeasibility: infeasibility,
          explanations: explanations,
          history: HistoryAnalytics.new(@dataset.history, source: @dataset.history_source).call,
          recommendations: details.map { |detail| recommendation_text(detail) },
          recommendation_details: details
        )
      end

      private

      def period
        @dataset.business_calendar.date_for(
          @dataset.operations.map(&:created_at).min || @dataset.snapshot_at
        )
      end

      def period_window
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

      def percentage(value)
        return nil if value.nil?

        (value * 100).round(PERCENTAGE_DECIMAL_PLACES)
      end

      def percentage_text(value)
        formatted = percentage(value)
        return "n/a" if formatted.nil?

        format("%.2f", formatted.to_f)
      end

      def organizer_distribution(distribution)
        distribution.each_with_object({}) do |(provider_id, values), result|
          result[provider_id] = values.merge(
            share_pct: percentage(values.fetch(:count_share)),
            target_pct: percentage(@configuration.targets.count_share.fetch(provider_id))
          ).freeze
        end.freeze
      end

      def final_distribution
        @final_distribution ||= begin
          count_targets = @configuration.targets.count_share
          volume_targets = @configuration.targets.volume_share
          @final_selection_ledger.distribution.each_with_object({}) do |(provider_id, values), result|
            result[provider_id] = values.merge(
              target_count_share: count_targets.fetch(provider_id),
              target_volume_share: volume_targets.fetch(provider_id),
              count_deviation: values.fetch(:count_share) - count_targets.fetch(provider_id),
              volume_deviation: values.fetch(:volume_share) - volume_targets.fetch(provider_id)
            ).freeze
          end.freeze
        end
      end

      def projected_daily_utilization(snapshots)
        @dataset.providers.each_with_object({}) do |provider, result|
          snapshot = snapshots.fetch(provider.payment_system)
          limit = snapshot.fetch(:daily_amount_limit)
          result[provider.payment_system] = {
            used: snapshot.fetch(:daily_approved_amount),
            limit: limit,
            utilization_pct: percentage(ratio(snapshot.fetch(:daily_approved_amount), limit))
          }.freeze
        end.freeze
      end

      def terminal_provider_id
        @configuration.terminal_provider_id
      end

      def deviation_causes
        @deviation_causes ||= begin
          decisions_by_final = @decisions.group_by(&:selected_provider)
          exclusions_by_provider = @decisions.each_with_object(Hash.new { |hash, key| hash[key] = Hash.new(0) }) do |decision, result|
            decision.attempts.each do |attempt|
              result[attempt.provider][attempt.reason] += 1 if attempt.hard_skipped?
            end
          end
          final_distribution.each_with_object({}) do |(provider_id, values), result|
            provider_decisions = decisions_by_final.fetch(provider_id, [])
            result[provider_id] = {
              hard_forced_assignments: provider_decisions.count { |decision| hard_forced?(decision) },
              fallback_assignments: provider_decisions.count { |decision| fallback?(decision) },
              terminal_fallback_assignments: provider_id == terminal_provider_id ?
                @decisions.count { |decision| terminal_fallback?(decision) } : 0,
              hard_exclusions: exclusions_by_provider.fetch(provider_id, {}).dup,
              target_count_gap: -values[:count_deviation],
              target_volume_gap: -values[:volume_deviation]
            }.freeze
          end.freeze
        end
      end

      def hard_forced?(decision)
        assigned = assignment_attempt(decision)
        return false unless assigned&.selection
        # Hard-forced attribution belongs to the provider that kept the
        # assignment.  A rejected/expired primary may have been the only
        # eligible provider at selection time, but a later fallback (most
        # notably the terminal provider) must not inherit that cause in the
        # final-provider report coordinate.
        return false unless decision.selected_provider == assigned.provider
        return false unless assigned.selection_reason == "only_eligible_provider"

        decision.attempts.any?(&:hard_skipped?)
      end

      def fallback?(decision)
        selected_indexes = decision.attempts.each_index.select { |index| decision.attempts[index].decision == :selected }
        final_index = selected_indexes.last
        final_index && decision.attempts.first(final_index).any? { |attempt| attempt.status }
      end

      def infeasibility
        final_distribution.filter_map do |provider_id, values|
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
              factors: attempt.selection.fetch(:factors),
              selected_by_resolver: attempt.selection.fetch(:selected_provider)
            }
          end
          causal_chain = decision.attempts.map do |attempt|
            if attempt.selection
              {
                provider: attempt.provider,
                phase: attempt.selection.fetch(:phase),
                decision: attempt.decision.to_s,
                selection_authority: "resolver",
                selection_reason: attempt.selection_reason || attempt.reason,
                selected_by_resolver: attempt.selection.fetch(:selected_provider),
                outcome: attempt.status&.to_s,
                outcome_reason: attempt.status && attempt.status != :approved ? attempt.reason : nil,
                settled: attempt.status == :approved
              }
            elsif attempt.decision == :skipped
              {
                provider: attempt.provider,
                phase: "hard_gate",
                decision: attempt.decision.to_s,
                selection_authority: "hard_constraint",
                selection_reason: attempt.reason,
                selected_by_resolver: nil,
                outcome: nil,
                outcome_reason: nil,
                settled: false
              }
            else
              {
                provider: attempt.provider,
                phase: "terminal",
                decision: attempt.decision.to_s,
                selection_authority: "terminal_policy",
                selection_reason: attempt.selection_reason || attempt.reason,
                selected_by_resolver: nil,
                outcome: attempt.status&.to_s,
                outcome_reason: attempt.status && attempt.status != :approved ? attempt.reason : nil,
                settled: attempt.status == :approved
              }
            end
          end
          summary = decision_summary(causal_chain)
          [
            decision.operation_id,
            {
              selected_provider: decision.selected_provider,
              selected_reason: selected && (selected.selection_reason || selected.reason),
              primary_assignment_provider: primary&.provider,
              primary_assignment_reason: primary && (primary.selection_reason || primary.reason),
              hard_exclusions: hard_exclusions,
              considered: considered,
              causal_chain: causal_chain,
              decision_summary: summary,
              failed_attempts: failed_attempts,
              fallback_continued: fallback?(decision),
              terminal_fallback: selected&.provider == terminal_provider_id
            }
          ]
        end
      end

      PROVIDER_LABELS = {
        "payflow" => "PayFlow",
        "quickpay" => "QuickPay",
        "spacepayments" => "SpacePayments",
        "vipay" => "VipPay"
      }.freeze

      def decision_summary(causal_chain)
        causal_chain.map do |entry|
          provider = provider_label(entry.fetch(:provider))
          case entry.fetch(:phase)
          when "hard_gate"
            "#{provider} excluded by #{summary_reason(entry.fetch(:selection_reason))}"
          when "terminal"
            outcome = entry[:outcome]
            outcome ? "#{provider} selected by terminal policy → #{provider} #{outcome}" :
              "#{provider} selected by terminal policy"
          else
            authority = entry.fetch(:phase) == "fallback" ? "fallback composite score" : "composite score"
            outcome = entry[:outcome]
            outcome ? "#{provider} selected by #{authority} → #{provider} #{outcome}" :
              "#{provider} selected by #{authority}"
          end
        end.join(" → ")
      end

      def provider_label(provider_id)
        PROVIDER_LABELS.fetch(provider_id) { provider_id.split(/[-_]/).map(&:capitalize).join }
      end

      def summary_reason(reason)
        {
          "bank_not_in_list" => "bank rule",
          "bank_excluded" => "bank exclusion",
          "amount_below_minimum" => "amount minimum",
          "amount_exceeds_limit" => "amount limit",
          "daily_amount_limit" => "daily limit",
          "in_progress_count_limit" => "in-progress count limit",
          "in_progress_amount_limit" => "in-progress amount limit",
          "inactive_provider" => "provider status",
          "zero_participation" => "zero participation",
          "no_available_requisite" => "requisites",
          "negative_margin_without_agreement" => "margin rule",
          "rpm_limit" => "RPM limit",
          "highest_composite_score" => "composite score",
          "fallback_highest_composite_score" => "fallback composite score",
          "only_eligible_provider" => "only eligible provider",
          "external_providers_exhausted" => "external providers exhausted"
        }.fetch(reason, reason.tr("_", " "))
      end

      def recommendation_details
        details = final_distribution.each_with_object([]) do |(provider_id, values), result|
          causes = deviation_causes.fetch(provider_id)
          subset_granularity = volume_subset_sum_granularity(provider_id, values, causes: causes)
          volume_granularity = if subset_granularity
            nil
          else
            volume_workload_granularity(provider_id, values, causes: causes)
          end
          hard_capacity = hard_eligibility_capacity(provider_id)
          count_structurally_unattainable = values[:count_deviation].negative? &&
            values[:target_count_share] * @final_selection_ledger.total_count > hard_capacity.fetch(:count)
          volume_structurally_unattainable = values[:volume_deviation].negative? &&
            values[:target_volume_share] * @final_selection_ledger.total_volume > hard_capacity.fetch(:volume)
          structural_constraint_known = causes[:hard_exclusions].values.sum.positive? &&
            (count_structurally_unattainable || volume_structurally_unattainable)
          if values[:count_deviation].negative? && !count_structurally_unattainable
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
          if values[:volume_deviation].negative? && volume_granularity.nil? && subset_granularity.nil? && !volume_structurally_unattainable
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

          if provider_id == terminal_provider_id &&
             causes[:terminal_fallback_assignments].positive? &&
             (values[:count_deviation].positive? || values[:volume_deviation].positive?)
            result << {
              kind: "terminal_fallback_deviation",
              provider: provider_id,
              evidence: {
                terminal_fallback_assignments: causes[:terminal_fallback_assignments],
                target_count: values[:target_count_share], actual_count: values[:count_share],
                target_volume: values[:target_volume_share], actual_volume: values[:volume_share],
                hard_excluded_alternatives: terminal_hard_exclusion_causes
              },
              action: "terminal fallback is the configured safety path; restore external coverage before changing traffic targets"
            }
          end

          if structural_constraint_known
            result << {
              kind: "structurally_constrained_under_target",
              provider: provider_id,
              evidence: {
                target_count: values[:target_count_share], actual_count: values[:count_share],
                target_volume: values[:target_volume_share], actual_volume: values[:volume_share],
                count_gap: values[:count_deviation].negative? ? -values[:count_deviation] : Rational(0, 1),
                volume_gap: values[:volume_deviation].negative? ? -values[:volume_deviation] : Rational(0, 1),
                hard_excluded_operations: causes[:hard_exclusions].values.sum,
                hard_exclusion_reasons: causes[:hard_exclusions],
                hard_eligible_operations: hard_capacity.fetch(:count),
                hard_eligible_volume: hard_capacity.fetch(:volume),
                structurally_unattainable_measures: [
                  ("count" if count_structurally_unattainable),
                  ("volume" if volume_structurally_unattainable)
                ].compact
              },
              action: "review target and alternative bank/amount/capacity coverage before changing weights"
            }
          end

          granularity = workload_granularity(provider_id, values, causes: causes)
          result << granularity if granularity

          result << subset_granularity if subset_granularity
          result << volume_granularity if volume_granularity
        end
        details.concat(daily_limit_recommendations)
        details.freeze
      end

      def workload_granularity(provider_id, values, causes:)
        total = @final_selection_ledger.total_count
        target_count = values[:target_count_share] * total
        return if total.zero? || target_count.denominator == 1
        return if causes.fetch(:hard_exclusions).values.sum.positive?
        return if causes.fetch(:hard_forced_assignments).positive?
        return unless [target_count.floor, target_count.ceil].include?(values[:count])

        {
          kind: "workload_granularity",
          provider: provider_id,
          evidence: {
            operation_count: total,
            target_count: target_count,
            actual_count: values[:count],
            attainable_counts: [target_count.floor, target_count.ceil]
          },
          action: "use a larger workload before changing policy; whole-operation granularity bounds this target gap"
        }
      end

      def hard_eligibility_capacity(provider_id)
        excluded = @decisions.filter_map do |decision|
          operation = operation_for(decision)
          next unless operation
          next unless decision.attempts.any? do |attempt|
            attempt.provider == provider_id && attempt.hard_skipped?
          end

          operation
        end
        {
          count: @dataset.operations.length - excluded.length,
          volume: @dataset.operations.sum(&:amount) - excluded.sum(&:amount)
        }.freeze
      end

      def volume_workload_granularity(provider_id, values, causes:)
        total = @final_selection_ledger.total_volume
        target_volume = values[:target_volume_share] * total
        gap = target_volume - values[:volume]
        minimum_amount = @dataset.operations.map(&:amount).min
        return if total.zero? || !gap.positive?
        return if causes.fetch(:hard_exclusions).values.sum.positive?
        return if causes.fetch(:hard_forced_assignments).positive?
        return if minimum_amount.nil? || gap >= minimum_amount

        {
          kind: "volume_workload_granularity",
          provider: provider_id,
          evidence: {
            operation_count: @dataset.operations.length,
            total_volume: total,
            target_volume: target_volume,
            actual_volume: values[:volume],
            gap: gap,
            minimum_operation_amount: minimum_amount
          },
          action: "use a larger workload or adjust the volume target before changing policy"
        }
      end

      def volume_subset_sum_granularity(provider_id, values, causes:)
        total = @final_selection_ledger.total_volume
        target = values[:target_volume_share] * total
        return if total.zero? || @dataset.operations.length < 2
        return unless target.respond_to?(:denominator) && target.denominator == 1
        return unless target.positive? && values[:volume] < target
        return if causes.fetch(:hard_exclusions).values.sum.positive?
        return if causes.fetch(:hard_forced_assignments).positive?
        return if causes.fetch(:fallback_assignments).positive?
        return if @dataset.operations.length > SUBSET_SUM_MAX_OPERATIONS || total > SUBSET_SUM_MAX_VOLUME

        target = target.to_i
        mask = (1 << (total + 1)) - 1
        reachable = 1
        @dataset.operations.each do |operation|
          reachable = (reachable | (reachable << operation.amount)) & mask
        end
        return if reachable[target] == 1

        nearest_below = target.downto(0).find { |amount| reachable[amount] == 1 }
        nearest_above = target.upto(total).find { |amount| reachable[amount] == 1 }
        {
          kind: "volume_subset_sum_granularity",
          provider: provider_id,
          evidence: {
            operation_count: @dataset.operations.length,
            total_volume: total,
            target_volume: target,
            actual_volume: values[:volume],
            nearest_attainable_volume_below: nearest_below,
            nearest_attainable_volume_above: nearest_above,
            search_bound: "#{SUBSET_SUM_MAX_OPERATIONS} operations / #{SUBSET_SUM_MAX_VOLUME} volume units"
          },
          action: "use a larger or differently sized workload, or adjust the volume target before changing policy"
        }
      end

      def daily_limit_recommendations
        provider_state.filter_map do |provider_id, snapshot|
          limit = snapshot[:daily_amount_limit]
          next if limit.nil? || limit.zero?

          used = snapshot.fetch(:daily_approved_amount)
          utilization = Rational(used, limit)
          next unless utilization >= Rational(9, 10)

          {
            kind: "daily_utilization_near_limit",
            provider: provider_id,
            evidence: {
              used: used,
              limit: limit,
              remaining: limit - used,
              utilization: utilization
            },
            action: "preserve #{limit - used} units of daily headroom or raise the daily limit before increasing this target"
          }
        end
      end

      def recommendation_text(detail)
        provider = detail.fetch(:provider)
        evidence = detail.fetch(:evidence)
        case detail.fetch(:kind)
        when "count_target_unmet"
          "#{provider} is below its count target by #{percentage_text(evidence.fetch(:gap))} percentage points; review count target or hard eligibility/capacity."
        when "volume_target_unmet"
          "#{provider} is below its volume target by #{percentage_text(evidence.fetch(:gap))} percentage points; review volume target or hard eligibility/capacity."
        when "target_infeasible_hard_forced"
          "#{provider} is above target because #{evidence.fetch(:hard_forced_assignments)} assignments were hard-forced; raise the target or improve alternatives."
        when "structurally_constrained_under_target"
          "#{provider} is below target by observed hard-rule exclusions on #{evidence.fetch(:hard_excluded_operations)} operations; review coverage before changing weights."
        when "workload_granularity"
          "#{provider} target is bounded by whole-operation granularity; use a larger workload before changing policy."
        when "volume_workload_granularity"
          "#{provider} volume target is bounded by whole-operation granularity; use a larger workload or adjust the target before changing policy."
        when "volume_subset_sum_granularity"
          below = evidence.fetch(:nearest_attainable_volume_below)
          above = evidence.fetch(:nearest_attainable_volume_above)
          nearest = [below, above].compact.map(&:to_s).join(" or ")
          "#{provider} volume target is not reachable by the bounded whole-operation workload; nearest attainable volume is #{nearest}; use a larger or differently sized workload before changing policy."
        when "daily_utilization_near_limit"
          "#{provider} is near its daily limit at #{percentage_text(evidence.fetch(:utilization))}%; preserve #{evidence.fetch(:remaining)} units of headroom or raise the daily limit."
        when "terminal_fallback_deviation"
          "#{provider} exceeded its zero target because #{evidence.fetch(:terminal_fallback_assignments)} operation(s) used the configured terminal fallback after external hard exclusions; restore external coverage before changing targets."
        else
          "Review #{provider} routing evidence for #{detail.fetch(:kind)}."
        end
      end

      def assignment_attempt(decision)
        decision.attempts.find { |attempt| attempt.status }
      end

      def terminal_fallback?(decision)
        decision.selected_provider == terminal_provider_id &&
          decision.attempts.last&.provider == terminal_provider_id
      end

      def terminal_hard_exclusion_causes
        @terminal_hard_exclusion_causes ||= @decisions.each_with_object(Hash.new(0)) do |decision, result|
          next unless terminal_fallback?(decision)

          decision.attempts.each do |attempt|
            result[attempt.reason] += 1 if attempt.hard_skipped?
          end
        end
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

      def build_primary_assignment_ledger
        ledger = TrafficLedger.new(
          @dataset.providers.map(&:payment_system), targets: @configuration.targets
        )
        @decisions.each do |decision|
          primary = decision.attempts.find { |attempt| attempt.status }
          next unless primary

          ledger.record_assignment!(provider_id: primary.provider, amount: operation_for(decision).amount)
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

      def build_final_selection_ledger
        ledger = ProviderAmountLedger.new(@dataset.providers.map(&:payment_system))
        @decisions.each do |decision|
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
        bytes = (JSON.generate(json_value(value)) + "\n").encode(Encoding::UTF_8)
        File.binwrite(path, bytes)
      rescue SystemCallError => error
        raise OutputError, "cannot write #{path}: #{error.message}"
      end

      def json_value(value, key: nil)
        case value
        when Rational
          return percentage_number(value) if key.to_s.end_with?("_pct")

          # Exact ratios stay exact at the JSON boundary: integral values use
          # JSON integers; fractional values use a stable, judge-readable
          # numerator/denominator string rather than an inexact Float.
          value.denominator == 1 ? value.numerator : "#{value.numerator}/#{value.denominator}"
        when Hash
          value.each_with_object({}) do |(nested_key, nested), result|
            result[nested_key.to_s] = json_value(nested, key: nested_key)
          end
        when Array
          value.map { |nested| json_value(nested, key: key) }
        else
          value
        end
      end

      def percentage_number(value)
        value.round(ReportBuilder::PERCENTAGE_DECIMAL_PLACES).to_f
      end
    end
  end
end
