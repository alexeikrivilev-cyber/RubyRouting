# frozen_string_literal: true

module RubyRouting
  module Projections
    class Analytics
      FAILURE_STATUSES = %i[
        safe_route_failure
        temporary_provider_failure
        terminal_payout_failure
      ].freeze

      attr_reader :opportunity_count_by_provider, :functional_provider_count_by_provider,
                  :assignment_measure_by_provider, :primary_assignment_measure_by_provider,
                  :primary_target_measure_by_provider, :primary_deviation_measure_by_provider,
                  :attempt_count_by_provider, :money_moving_operation_count_by_provider,
                  :settlement_measure_by_provider, :first_attempt_success_count,
                  :eventual_success_count, :fallback_recovery_count,
                  :successful_fallback_recovery_count, :recovery_attempt_count,
                  :terminal_failure_count, :no_safe_route_count, :provider_failure_count,
                  :economic_conflict_count, :reversal_count, :reversal_measure_by_currency,
                  :failure_count_by_attribution, :exclusion_count_by_code,
                  :capacity_exclusion_count_by_provider, :health_exclusion_count_by_provider,
                  :transport_count_by_kind, :unresolved_count_by_status,
                  :unresolved_age_seconds_by_payout, :attempt_count_by_payout,
                  :provider_interaction_count_by_payout, :provider_switch_count_by_payout,
                  :deviation_by_cause

      def self.from_facts(facts, as_of: nil)
        new(facts, as_of: as_of)
      end

      def initialize(facts, as_of: nil)
        @facts = facts.to_a.sort_by(&:sequence).freeze
        @as_of = as_of
        @opportunity_count_by_provider = Hash.new(0)
        @functional_provider_count_by_provider = Hash.new(0)
        @assignment_measure_by_provider = Hash.new(0)
        @primary_assignment_measure_by_provider = Hash.new(0)
        @primary_target_measure_by_provider = Hash.new(0)
        @primary_deviation_measure_by_provider = Hash.new(0)
        @attempt_count_by_provider = Hash.new(0)
        @money_moving_operation_count_by_provider = Hash.new(0)
        @settlement_measure_by_provider = Hash.new(0)
        @provider_failure_count = Hash.new(0)
        @first_attempt_success_count = 0
        @eventual_success_count = 0
        @fallback_recovery_count = 0
        @successful_fallback_recovery_count = 0
        @recovery_attempt_count = 0
        @terminal_failure_count = 0
        @no_safe_route_count = 0
        @economic_conflict_count = 0
        @reversal_count = 0
        @reversal_measure_by_currency = Hash.new(0)
        @failure_count_by_attribution = Hash.new(0)
        @exclusion_count_by_code = Hash.new(0)
        @capacity_exclusion_count_by_provider = Hash.new(0)
        @health_exclusion_count_by_provider = Hash.new(0)
        @transport_count_by_kind = Hash.new(0)
        @unresolved_count_by_status = Hash.new(0)
        @unresolved_age_seconds_by_payout = {}
        @attempt_count_by_payout = Hash.new(0)
        @provider_interaction_count_by_payout = Hash.new(0)
        @provider_switch_count_by_payout = Hash.new(0)
        @deviation_by_cause = Hash.new { |hash, cause| hash[cause] = { count: 0, measure: 0 } }
        project
        freeze_collections
        freeze
      end

      def to_h
        {
          opportunity_count_by_provider: opportunity_count_by_provider,
          functional_provider_count_by_provider: functional_provider_count_by_provider,
          assignment_measure_by_provider: assignment_measure_by_provider,
          primary_assignment_measure_by_provider: primary_assignment_measure_by_provider,
          primary_target_measure_by_provider: primary_target_measure_by_provider,
          primary_deviation_measure_by_provider: primary_deviation_measure_by_provider,
          attempt_count_by_provider: attempt_count_by_provider,
          money_moving_operation_count_by_provider: money_moving_operation_count_by_provider,
          settlement_measure_by_provider: settlement_measure_by_provider,
          first_attempt_success_count: first_attempt_success_count,
          eventual_success_count: eventual_success_count,
          fallback_recovery_count: fallback_recovery_count,
          successful_fallback_recovery_count: successful_fallback_recovery_count,
          recovery_attempt_count: recovery_attempt_count,
          terminal_failure_count: terminal_failure_count,
          no_safe_route_count: no_safe_route_count,
          provider_failure_count: provider_failure_count,
          economic_conflict_count: economic_conflict_count,
          reversal_count: reversal_count,
          reversal_measure_by_currency: reversal_measure_by_currency,
          failure_count_by_attribution: failure_count_by_attribution,
          exclusion_count_by_code: exclusion_count_by_code,
          capacity_exclusion_count_by_provider: capacity_exclusion_count_by_provider,
          health_exclusion_count_by_provider: health_exclusion_count_by_provider,
          transport_count_by_kind: transport_count_by_kind,
          unresolved_count_by_status: unresolved_count_by_status,
          unresolved_age_seconds_by_payout: unresolved_age_seconds_by_payout,
          attempt_count_by_payout: attempt_count_by_payout,
          provider_interaction_count_by_payout: provider_interaction_count_by_payout,
          provider_switch_count_by_payout: provider_switch_count_by_payout,
          deviation_by_cause: deviation_by_cause
        }
      end

      private

      def project
        roles_by_operation = {}
        first_operation_by_payout = {}
        successful_payouts = {}
        terminal_payouts = {}
        successful_fallback_payouts = {}
        policies_by_scope = {}
        primary_allocations = []
        status_by_payout = Hash.new(:new)
        attempt_providers_by_payout = Hash.new { |hash, payout_id| hash[payout_id] = [] }
        unresolved_since_by_payout = {}
        blocked_age_by_payout = {}

        @facts.each do |fact|
          payload = fact.payload
          status_by_payout[fact.payout_id] = :new unless status_by_payout.key?(fact.payout_id)
          case fact.type
          when :policy_registered
            policies_by_scope[policy_scope_key(payload)] = payload[:definition]
          when :opportunity_evaluated
            Array(payload[:opportunities]).each { |provider_id| opportunity_count_by_provider[provider_id] += 1 }
            Array(payload[:functional_provider_ids]).each do |provider_id|
              functional_provider_count_by_provider[provider_id] += 1
            end
            record_exclusions(payload[:exclusion_codes])
            record_exclusions(payload[:allocation_exclusions])
          when :decision_committed
            operation_id = payload[:operation_id]
            roles_by_operation[operation_id] = payload[:role] if operation_id
            if payload[:action] == :defer && Array(payload[:reason_codes]).include?(:no_safe_route)
              @no_safe_route_count += 1
            end
            record_deviation(payload) if payload[:action] == :assign && payload[:role] == :primary
          when :allocation_committed
            provider_id = payload.fetch(:provider_id)
            measure = payload.fetch(:measure)
            assignment_measure_by_provider[provider_id] += measure
            money_moving_operation_count_by_provider[provider_id] += 1
            attempt_providers_by_payout[fact.payout_id] << provider_id
            if payload[:role] == :primary
              primary_assignment_measure_by_provider[provider_id] += measure
              primary_allocations << [policy_scope_key(payload), provider_id, measure]
            else
              @recovery_attempt_count += 1 if payload[:role] == :recovery
            end
          when :attempt_started
            provider_id = payload.fetch(:provider_id)
            attempt_count_by_provider[provider_id] += 1
            provider_interaction_count_by_payout[fact.payout_id] += 1
            first_operation_by_payout[fact.payout_id] ||= payload.fetch(:operation_id)
            unresolved_since_by_payout[fact.payout_id] ||= payload[:started_at]
          when :ownership_acquired
            status_by_payout[fact.payout_id] = :pending
            unresolved_since_by_payout[fact.payout_id] ||= payload[:acquired_at]
          when :provider_observed
            next unless payload[:applied]

            provider_id = payload.fetch(:provider_id)
            status = payload.fetch(:status)
            attribution = payload.fetch(:attribution).to_sym
            status_by_payout[fact.payout_id] = reduced_status(status, payload[:safe_to_release])
            if %i[pending unknown].include?(status_by_payout[fact.payout_id])
              unresolved_since_by_payout[fact.payout_id] ||= payload[:observed_at]
            else
              unresolved_since_by_payout.delete(fact.payout_id)
              blocked_age_by_payout.delete(fact.payout_id)
            end
            if FAILURE_STATUSES.include?(status)
              @failure_count_by_attribution[attribution] += 1
              @provider_failure_count[provider_id] += 1 if attribution == :provider &&
                %i[safe_route_failure temporary_provider_failure].include?(status)
            end
            if status == :success
              successful_payouts[fact.payout_id] = true
              if roles_by_operation[payload[:operation_id]] == :recovery
                successful_fallback_payouts[fact.payout_id] = true
              end
              @first_attempt_success_count += 1 if roles_by_operation[payload[:operation_id]] == :primary &&
                first_operation_by_payout[fact.payout_id] == payload[:operation_id]
            elsif status == :terminal_payout_failure
              terminal_payouts[fact.payout_id] = true
            end
          when :transport_classified
            @transport_count_by_kind[payload.fetch(:kind).to_sym] += 1
          when :settlement_recorded
            provider_id = payload.fetch(:provider_id)
            settlement_measure_by_provider[provider_id] += payload.fetch(:measure)
            status_by_payout[fact.payout_id] = :success
          when :reversal_recorded
            @reversal_count += 1
            amount = payload.fetch(:amount)
            @reversal_measure_by_currency[amount.currency] += amount.amount_minor
          when :economic_conflict
            @economic_conflict_count += 1
          when :reconciliation_blocked
            status_by_payout[fact.payout_id] = :reconciliation_blocked
            blocked_age_by_payout[fact.payout_id] = payload[:elapsed] if payload[:elapsed]
          end
        end

        project_primary_targets(primary_allocations, policies_by_scope)
        project_lifecycle_metrics(
          status_by_payout,
          attempt_providers_by_payout,
          unresolved_since_by_payout,
          blocked_age_by_payout
        )
        @eventual_success_count = successful_payouts.length
        @successful_fallback_recovery_count = successful_fallback_payouts.length
        @fallback_recovery_count = @successful_fallback_recovery_count
        @terminal_failure_count = terminal_payouts.length
      end

      def record_exclusions(exclusion_codes)
        exclusion_codes.to_h.each do |provider_id, code|
          normalized_code = code.to_sym
          @exclusion_count_by_code[normalized_code] += 1
          if normalized_code == :capacity_exhausted
            @capacity_exclusion_count_by_provider[provider_id] += 1
          elsif normalized_code == :quarantined
            @health_exclusion_count_by_provider[provider_id] += 1
          end
        end
      end

      def record_deviation(payload)
        discrepancy = payload[:allocation_discrepancy]
        tolerance = payload[:allocation_tolerance]
        return if discrepancy.nil?
        return unless discrepancy.positive?
        return unless tolerance.nil? || discrepancy > tolerance

        cause = (payload[:allocation_deviation_cause] || :unknown).to_sym
        entry = @deviation_by_cause[cause]
        entry[:count] += 1
        entry[:measure] += payload[:measure].to_i
      end

      def project_primary_targets(primary_allocations, policies_by_scope)
        grouped = primary_allocations.group_by(&:first)
        grouped.each do |scope_key, rows|
          definition = policies_by_scope[scope_key]
          next unless definition.is_a?(Hash)

          targets = definition[:targets] || definition["targets"]
          next unless targets.is_a?(Hash) && !targets.empty?

          weights = targets.transform_keys(&:to_s)
          total_weight = weights.values.sum
          total_measure = rows.sum { |(_, _provider_id, measure)| measure }
          actual = rows.each_with_object(Hash.new(0)) do |row, copy|
            provider_id = row.fetch(1)
            copy[provider_id] += row.fetch(2)
          end
          weights.each do |provider_id, weight|
            target = Rational(total_measure * weight, total_weight)
            primary_target_measure_by_provider[provider_id] += target
            primary_deviation_measure_by_provider[provider_id] +=
              (actual.fetch(provider_id, 0) - target).abs
          end
        end
      end

      def project_lifecycle_metrics(
        status_by_payout,
        attempt_providers_by_payout,
        unresolved_since_by_payout,
        blocked_age_by_payout
      )
        attempt_providers_by_payout.each do |payout_id, providers|
          attempt_count_by_payout[payout_id] = providers.length
          provider_switch_count_by_payout[payout_id] = providers
            .each_cons(2).count { |left, right| left != right }
        end
        status_by_payout.each do |payout_id, status|
          unresolved_count_by_status[status] += 1 if %i[pending unknown reconciliation_blocked].include?(status)
          next unless %i[pending unknown reconciliation_blocked].include?(status)

          age = unresolved_age(
            payout_id,
            unresolved_since_by_payout[payout_id],
            blocked_age_by_payout[payout_id]
          )
          @unresolved_age_seconds_by_payout[payout_id] = age unless age.nil?
        end
      end

      def unresolved_age(payout_id, started_at, blocked_age)
        return blocked_age if @as_of.nil?
        return blocked_age if started_at.nil?

        elapsed = @as_of - started_at
        raise ArgumentError, "analytics as_of cannot precede unresolved start for #{payout_id}" if elapsed.negative?

        elapsed
      rescue NoMethodError, TypeError
        raise ArgumentError, "analytics as_of and unresolved timestamps must be subtractable"
      end

      def reduced_status(status, safe_to_release)
        case status.to_sym
        when :safe_route_failure, :temporary_provider_failure
          safe_to_release ? status.to_sym : :unknown
        else
          status.to_sym
        end
      end

      def policy_scope_key(payload)
        raw = if payload[:policy_scope].is_a?(Array)
          payload[:policy_scope]
        else
          [payload[:policy_id], payload[:policy_epoch], payload[:policy_scope]]
        end
        Array(raw).map(&:to_s).freeze
      end

      def freeze_collections
        hash_names = [
          :@opportunity_count_by_provider,
          :@functional_provider_count_by_provider,
          :@assignment_measure_by_provider,
          :@primary_assignment_measure_by_provider,
          :@primary_target_measure_by_provider,
          :@primary_deviation_measure_by_provider,
          :@attempt_count_by_provider,
          :@money_moving_operation_count_by_provider,
          :@settlement_measure_by_provider,
          :@provider_failure_count,
          :@reversal_measure_by_currency,
          :@failure_count_by_attribution,
          :@exclusion_count_by_code,
          :@capacity_exclusion_count_by_provider,
          :@health_exclusion_count_by_provider,
          :@transport_count_by_kind,
          :@unresolved_count_by_status,
          :@unresolved_age_seconds_by_payout,
          :@attempt_count_by_payout,
          :@provider_interaction_count_by_payout,
          :@provider_switch_count_by_payout
        ]
        hash_names.each do |name|
          instance_variable_set(name, instance_variable_get(name).dup.freeze)
        end
        @deviation_by_cause = @deviation_by_cause.each_with_object({}) do |(cause, value), copy|
          copy[cause] = value.dup.freeze
        end.freeze
      end
    end
  end
end
