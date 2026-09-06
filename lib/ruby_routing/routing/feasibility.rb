# frozen_string_literal: true

module RubyRouting
  module Routing
    class RuntimeFeasibility
      STATUSES = %i[feasible infeasible].freeze

      attr_reader :status, :reason_codes, :functional_target_provider_ids,
                  :feasible_target_provider_ids, :unattempted_provider_ids,
                  :measure_admissible_provider_ids

      def self.assess(policy:, eligibility:, attempted_provider_ids:, measure_exclusions:)
        target_ids = normalize_provider_ids(policy.targets.keys, "policy target provider ids")
        functional_ids = (
          normalize_provider_ids(eligibility.functional_provider_ids, "functional provider ids") & target_ids
        ).sort.freeze
        feasible_ids = (
          normalize_provider_ids(eligibility.feasible_provider_ids, "feasible provider ids") & target_ids
        ).sort.freeze
        attempted_ids = normalize_provider_ids(attempted_provider_ids, "attempted_provider_ids")
        measure_exclusion_ids = normalize_provider_ids(measure_exclusions.keys, "measure exclusion provider ids")
        unattempted_ids = (feasible_ids - attempted_ids).sort.freeze
        measure_admissible_ids = unattempted_ids.reject do |provider_id|
          measure_exclusion_ids.include?(provider_id)
        end.freeze

        reason_codes = if measure_admissible_ids.any?
          []
        elsif unattempted_ids.empty? && feasible_ids.any?
          [:recovery_provider_exhausted]
        elsif feasible_ids.empty? && functional_ids.any?
          [:operational_infeasibility]
        elsif functional_ids.empty?
          [:no_functional_target_opportunity]
        else
          [:policy_measure_infeasibility]
        end

        new(
          status: reason_codes.empty? ? :feasible : :infeasible,
          reason_codes: reason_codes,
          functional_target_provider_ids: functional_ids,
          feasible_target_provider_ids: feasible_ids,
          unattempted_provider_ids: unattempted_ids,
          measure_admissible_provider_ids: measure_admissible_ids
        )
      end

      def initialize(status:, reason_codes:, functional_target_provider_ids: [],
                     feasible_target_provider_ids: [], unattempted_provider_ids: [],
                     measure_admissible_provider_ids: [])
        @status = RubyRouting::Enum.normalize(status, STATUSES, "runtime feasibility status")

        @reason_codes = RubyRouting::Collection.to_array(
          reason_codes,
          "runtime feasibility reason codes"
        ).map { |reason_code| reason_code.is_a?(Symbol) ? reason_code : reason_code.to_s.freeze }.uniq.freeze
        @functional_target_provider_ids = self.class.send(
          :normalize_provider_ids,
          functional_target_provider_ids,
          "functional target provider ids"
        )
        @feasible_target_provider_ids = self.class.send(
          :normalize_provider_ids,
          feasible_target_provider_ids,
          "feasible target provider ids"
        )
        @unattempted_provider_ids = self.class.send(
          :normalize_provider_ids,
          unattempted_provider_ids,
          "unattempted provider ids"
        )
        @measure_admissible_provider_ids = self.class.send(
          :normalize_provider_ids,
          measure_admissible_provider_ids,
          "measure-admissible provider ids"
        )
        freeze
      end

      def feasible?
        status == :feasible
      end

      def infeasible?
        !feasible?
      end

      def policy_infeasible?
        infeasible? && !reason_codes.include?(:recovery_provider_exhausted)
      end

      def to_h
        {
          status: status,
          reason_codes: reason_codes,
          functional_target_provider_ids: functional_target_provider_ids,
          feasible_target_provider_ids: feasible_target_provider_ids,
          unattempted_provider_ids: unattempted_provider_ids,
          measure_admissible_provider_ids: measure_admissible_provider_ids
        }.freeze
      end

      class << self
        private

        def normalize_provider_ids(provider_ids, label)
          RubyRouting::Collection.to_array(provider_ids, label)
            .map { |provider_id| normalize_provider_id(provider_id) }
            .uniq.sort.freeze
        end

        def normalize_provider_id(provider_id)
          normalized = provider_id.to_s.strip
          raise ArgumentError, "provider id must be non-empty" if normalized.empty?

          normalized
        end
      end
    end
  end
end
