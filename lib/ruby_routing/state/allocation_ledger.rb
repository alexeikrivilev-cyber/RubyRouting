# frozen_string_literal: true

module RubyRouting
  module State
    # Owns the committed allocation snapshots. The coordinator still decides
    # when a snapshot update is part of an atomic mutation; this ledger owns
    # only the keyed allocation state and its exact revision progression.
    class AllocationLedger
      def initialize
        @snapshots = {}
      end

      def snapshot(policy:, opportunity_provider_ids: nil)
        key = policy.allocation_key(opportunity_provider_ids: opportunity_provider_ids)
        snapshot_for_key(key)
      end

      def commit(key:, provider_id:, measure:)
        current = snapshot_for_key(key)
        @snapshots[key] = current.with_commit(provider_id, measure)
      end

      def restore(key:, provider_id:, measure:)
        commit(key: key, provider_id: provider_id, measure: measure)
      end

      private

      def snapshot_for_key(key)
        @snapshots[key] ||= RubyRouting::Routing::AllocationSnapshot.empty
      end
    end
  end
end
