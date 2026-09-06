# frozen_string_literal: true

module RubyRouting
  module Case
    class HardConstraintResult
      attr_reader :provider_id, :eligible, :reason

      def initialize(provider_id:, eligible:, reason: nil)
        @provider_id = provider_id.to_s.freeze
        @eligible = eligible == true
        @reason = reason
        freeze
      end

      def eligible?
        eligible
      end
    end

    class HardConstraintEvaluator
      def call(provider_state, operation, as_of:, terminal: false)
        provider = provider_state.provider
        reason = if !provider.active?
          :inactive_provider
        elsif provider.traffic_percentage.zero? && !terminal
          :zero_participation
        elsif provider.limit_amount_min && operation.amount < provider.limit_amount_min
          :amount_below_minimum
        elsif provider.limit_amount_max && operation.amount > provider.limit_amount_max
          :amount_exceeds_limit
        elsif provider.daily_amount_limit && provider_state.daily_approved_amount + operation.amount > provider.daily_amount_limit
          :daily_amount_limit
        elsif provider.in_progress_count_limit && provider_state.in_progress_count + 1 > provider.in_progress_count_limit
          :in_progress_count_limit
        elsif provider.in_progress_amount_limit && provider_state.in_progress_amount + operation.amount > provider.in_progress_amount_limit
          :in_progress_amount_limit
        elsif provider.banks.any? && provider.exclude_banks && provider.banks.include?(operation.bank)
          :bank_excluded
        elsif provider.banks.any? && !provider.exclude_banks && !provider.banks.include?(operation.bank)
          :bank_not_in_list
        elsif provider.provider_margin_pct > provider.merchant_margin_pct && !provider.allow_negative_agreement
          :negative_margin_without_agreement
        elsif provider_state.available_requisites.zero?
          :no_available_requisite
        elsif provider_state.rpm_limit && provider_state.rpm_count(as_of) >= provider_state.rpm_limit
          :rpm_limit
        end
        HardConstraintResult.new(provider_id: provider.payment_system, eligible: reason.nil?, reason: reason)
      end
    end

    class ProviderCaseState
      attr_reader :provider, :daily_approved_amount, :transient_count,
                  :transient_amount, :available_requisites,
                  :routed_count, :routed_volume, :approved_count,
                  :rejected_count, :expired_count

      def initialize(provider, rpm_limit: nil, rpm_window_seconds: 60)
        @provider = provider
        @daily_approved_amount = provider.daily_approved_amount
        @transient_count = 0
        @transient_amount = 0
        @reservations = {}
        @available_requisites = provider.available_requisites
        @rpm_events = []
        unless rpm_limit.nil? || (rpm_limit.is_a?(Integer) && rpm_limit >= 0)
          raise InputError, "rpm_limit must be a non-negative Integer or nil"
        end
        unless rpm_window_seconds.is_a?(Integer) && rpm_window_seconds.positive?
          raise InputError, "rpm_window_seconds must be a positive Integer"
        end
        @rpm_limit = rpm_limit
        @rpm_window_seconds = rpm_window_seconds
        @routed_count = 0
        @routed_volume = 0
        @approved_count = 0
        @rejected_count = 0
        @expired_count = 0
      end

      def in_progress_count
        provider.in_progress_count + transient_count
      end

      def in_progress_amount
        provider.in_progress_amount + transient_amount
      end

      def rpm_count(as_of)
        validate_time!(as_of)
        cutoff = as_of - @rpm_window_seconds
        @rpm_events.count { |time| time > cutoff && time <= as_of }
      end

      def rpm_events
        @rpm_events.dup.freeze
      end

      def rpm_limit
        @rpm_limit
      end

      def reserve!(operation, as_of:)
        validate_time!(as_of)
        if @reservations.key?(operation.operation_id)
          raise RubyRouting::Case::OutputError, "operation is already reserved"
        end
        @reservations[operation.operation_id] = operation.amount
        @transient_count += 1
        @transient_amount += operation.amount
        @rpm_events << as_of
      end

      def release!(operation)
        unless @reservations.fetch(operation.operation_id, nil) == operation.amount
          raise RubyRouting::Case::OutputError, "transient release exceeds reserved state"
        end
        @reservations.delete(operation.operation_id)
        @transient_count -= 1
        @transient_amount -= operation.amount
      end

      def record_outcome!(operation, status)
        case status
        when :approved
          @approved_count += 1
          @daily_approved_amount += operation.amount
        when :rejected
          @rejected_count += 1
        when :expired
          @expired_count += 1
        else
          raise RubyRouting::Case::OutputError, "unsupported simulated status #{status.inspect}"
        end
      end

      def record_route!(operation)
        @routed_count += 1
        @routed_volume += operation.amount
      end

      def snapshot(as_of:)
        {
          provider: provider.payment_system,
          daily_approved_amount: daily_approved_amount,
          daily_amount_limit: provider.daily_amount_limit,
          baseline_in_progress_count: provider.in_progress_count,
          baseline_in_progress_amount: provider.in_progress_amount,
          transient_in_progress_count: transient_count,
          transient_in_progress_amount: transient_amount,
          available_requisites: available_requisites,
          rpm_count: rpm_count(as_of),
          rpm_limit: rpm_limit,
          routed_count: routed_count,
          routed_volume: routed_volume,
          approved_count: approved_count,
          rejected_count: rejected_count,
          expired_count: expired_count
        }.freeze
      end

      private

      def validate_time!(value)
        raise InputError, "case state time must be a Time" unless value.is_a?(Time)
      end
    end

    ProviderState = ProviderCaseState

    class CaseState
      def initialize(dataset, rpm_limits: {}, rpm_window_seconds: 60)
        @providers = dataset.providers.each_with_object({}) do |provider, states|
          states[provider.payment_system] = ProviderCaseState.new(
            provider,
            rpm_limit: rpm_limits[provider.payment_system],
            rpm_window_seconds: rpm_window_seconds
          )
        end
      end

      def providers
        @providers.dup.freeze
      end

      def fetch(provider_id)
        provider_id = Input.assert_id(provider_id, "case state provider id")
        providers.fetch(provider_id) { raise InputError, "unknown provider #{provider_id}" }
      end

      def snapshots(as_of:)
        providers.transform_values do |state|
          {
            provider: state.provider.payment_system,
            daily_approved_amount: state.daily_approved_amount,
            daily_amount_limit: state.provider.daily_amount_limit,
            baseline_in_progress_count: state.provider.in_progress_count,
            baseline_in_progress_amount: state.provider.in_progress_amount,
            transient_in_progress_count: state.transient_count,
            transient_in_progress_amount: state.transient_amount,
            available_requisites: state.available_requisites,
            rpm_count: state.rpm_count(as_of),
            rpm_limit: state.rpm_limit,
            routed_count: state.routed_count,
            routed_volume: state.routed_volume,
            approved_count: state.approved_count,
            rejected_count: state.rejected_count,
            expired_count: state.expired_count
          }.freeze
        end.freeze
      end
    end
  end
end
