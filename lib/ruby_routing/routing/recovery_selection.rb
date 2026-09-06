# frozen_string_literal: true

module RubyRouting
  module Routing
    # Selects a provider for a fresh recovery attempt after the higher-level
    # recovery classifier has admitted cross-provider fallback. Recovery keeps
    # the same exact allocation authority as primary routing, but makes the
    # recovery-only legality boundary explicit: a provider that already hosted
    # a money-moving attempt is never a candidate again.
    #
    # The accounting universe intentionally remains the full functional set.
    # Excluded providers therefore continue to contribute to the policy target
    # without receiving another operation, while the primary allocation ledger
    # remains untouched by the recovery commit.
    module RecoverySelection
      module_function

      def choose(policy:, candidates:, attempted_provider_ids:, snapshot:, incoming_measure:,
                 accounting_provider_ids:)
        normalized_candidates = normalize_provider_ids(candidates, "recovery candidates")
        attempted_ids = normalize_provider_ids(attempted_provider_ids, "attempted_provider_ids")
        eligible_candidates = normalized_candidates - attempted_ids

        case policy.recovery_objective.mode
        when :allocation_constrained
          RubyRouting::Routing::Allocation.choose(
            policy: policy,
            candidates: eligible_candidates,
            snapshot: snapshot,
            incoming_measure: incoming_measure,
            accounting_provider_ids: accounting_provider_ids
          )
        else
          raise ArgumentError, "unsupported recovery objective #{policy.recovery_objective.mode.inspect}"
        end
      end

      def normalize_provider_ids(provider_ids, label)
        RubyRouting::Collection.to_array(provider_ids, label).map do |provider_id|
          RubyRouting::Identity.normalize(provider_id, "provider id")
        end.uniq.sort
      end
      private_class_method :normalize_provider_ids
    end
  end
end
