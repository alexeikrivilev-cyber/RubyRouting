# frozen_string_literal: true

module RubyRouting
  module Projections
    class Analytics
      attr_reader :opportunity_count_by_provider, :assignment_measure_by_provider,
                  :primary_assignment_measure_by_provider, :attempt_count_by_provider,
                  :settlement_measure_by_provider, :first_attempt_success_count,
                  :eventual_success_count, :fallback_recovery_count,
                  :terminal_failure_count, :no_safe_route_count, :provider_failure_count

      def self.from_facts(facts)
        new(facts)
      end

      def initialize(facts)
        @facts = facts.to_a.sort_by(&:sequence).freeze
        @opportunity_count_by_provider = Hash.new(0)
        @assignment_measure_by_provider = Hash.new(0)
        @primary_assignment_measure_by_provider = Hash.new(0)
        @attempt_count_by_provider = Hash.new(0)
        @settlement_measure_by_provider = Hash.new(0)
        @provider_failure_count = Hash.new(0)
        @first_attempt_success_count = 0
        @eventual_success_count = 0
        @fallback_recovery_count = 0
        @terminal_failure_count = 0
        @no_safe_route_count = 0
        project
        freeze_collections
        freeze
      end

      def to_h
        {
          opportunity_count_by_provider: opportunity_count_by_provider,
          assignment_measure_by_provider: assignment_measure_by_provider,
          primary_assignment_measure_by_provider: primary_assignment_measure_by_provider,
          attempt_count_by_provider: attempt_count_by_provider,
          settlement_measure_by_provider: settlement_measure_by_provider,
          first_attempt_success_count: first_attempt_success_count,
          eventual_success_count: eventual_success_count,
          fallback_recovery_count: fallback_recovery_count,
          terminal_failure_count: terminal_failure_count,
          no_safe_route_count: no_safe_route_count,
          provider_failure_count: provider_failure_count
        }
      end

      private

      def project
        roles_by_operation = {}
        first_attempt_by_payout = {}
        successful_payouts = {}
        terminal_payouts = {}

        @facts.each do |fact|
          payload = fact.payload
          case fact.type
          when :opportunity_evaluated
            Array(payload[:opportunities]).each { |provider_id| opportunity_count_by_provider[provider_id] += 1 }
          when :decision_committed
            operation_id = payload[:operation_id]
            roles_by_operation[operation_id] = payload[:role] if operation_id
            if payload[:action] == :defer && Array(payload[:reasons]).any? { |reason| reason.to_s.include?("no safe") }
              @no_safe_route_count += 1
            end
          when :allocation_committed
            provider_id = payload.fetch(:provider_id)
            measure = payload.fetch(:measure)
            assignment_measure_by_provider[provider_id] += measure
            if payload[:role] == :primary
              primary_assignment_measure_by_provider[provider_id] += measure
            else
              @fallback_recovery_count += 1 if payload[:role] == :recovery
            end
          when :attempt_started
            attempt_count_by_provider[payload.fetch(:provider_id)] += 1
            first_attempt_by_payout[fact.payout_id] ||= payload.fetch(:operation_id)
          when :provider_observed
            next unless payload[:applied]
            provider_id = payload.fetch(:provider_id)
            status = payload.fetch(:status)
            @provider_failure_count[provider_id] += 1 if payload[:attribution] == :provider &&
              %i[safe_route_failure temporary_provider_failure].include?(status)
            if status == :success
              successful_payouts[fact.payout_id] = true
              @first_attempt_success_count += 1 if roles_by_operation[payload[:operation_id]] == :primary &&
                first_attempt_by_payout[fact.payout_id] == payload[:operation_id]
            elsif status == :terminal_payout_failure
              terminal_payouts[fact.payout_id] = true
            end
          when :settlement_recorded
            provider_id = payload.fetch(:provider_id)
            settlement_measure_by_provider[provider_id] += payload.fetch(:measure)
          end
        end

        @eventual_success_count = successful_payouts.length
        @terminal_failure_count = terminal_payouts.length
      end

      def freeze_collections
        [
          :@opportunity_count_by_provider,
          :@assignment_measure_by_provider,
          :@primary_assignment_measure_by_provider,
          :@attempt_count_by_provider,
          :@settlement_measure_by_provider,
          :@provider_failure_count
        ].each do |name|
          instance_variable_set(name, instance_variable_get(name).dup.freeze)
        end
      end
    end
  end
end
