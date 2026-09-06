# frozen_string_literal: true

require_relative "../test_helper"

class AllocationLedgerTest < Minitest::Test
  def test_keyed_snapshot_commit_and_restore_share_exact_revision_progression
    ledger = RubyRouting::State::AllocationLedger.new
    policy = RubyRouting::RoutingPolicy.new(
      id: "allocation-ledger",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )

    first = ledger.snapshot(policy: policy, opportunity_provider_ids: ["A"])
    second = ledger.snapshot(policy: policy, opportunity_provider_ids: ["A", "B"])
    assert_equal 0, first.revision
    assert_equal 0, second.revision

    ledger.commit(
      key: policy.allocation_key(opportunity_provider_ids: ["A"]),
      provider_id: "A",
      measure: 1
    )
    ledger.restore(
      key: policy.allocation_key(opportunity_provider_ids: ["A", "B"]),
      provider_id: "B",
      measure: 2
    )

    assert_equal({ "A" => 1 }, ledger.snapshot(policy: policy, opportunity_provider_ids: ["A"]).measures)
    assert_equal({ "B" => 2 }, ledger.snapshot(policy: policy, opportunity_provider_ids: ["A", "B"]).measures)
    assert_equal 1, ledger.snapshot(policy: policy, opportunity_provider_ids: ["A"]).revision
    assert_equal 1, ledger.snapshot(policy: policy, opportunity_provider_ids: ["A", "B"]).revision
  end
end
