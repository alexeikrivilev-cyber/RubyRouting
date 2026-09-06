# frozen_string_literal: true

require_relative "../test_helper"

class SnapshotTest < Minitest::Test
  def test_attempt_snapshot_canonicalizes_and_types_operation_state
    contract = RubyRouting::ProviderOperationContract.new(
      provider_id: "A",
      idempotency_key: "p:o"
    )
    snapshot = RubyRouting::State::AttemptSnapshot.new(
      attempt_id: " a ",
      operation_id: " o ",
      provider_id: " A ",
      role: :primary,
      outcome: RubyRouting::NormalizedOutcome.pending,
      measure: 1,
      contract: contract,
      last_observation_sequence: 2,
      committed_at: Time.at(1)
    )

    assert_equal ["a", "o", "A", :primary, 1, 2], [
      snapshot.attempt_id,
      snapshot.operation_id,
      snapshot.provider_id,
      snapshot.role,
      snapshot.measure,
      snapshot.last_observation_sequence
    ]
    assert_instance_of RubyRouting::NormalizedOutcome, snapshot.outcome
    assert_instance_of Time, snapshot.committed_at
  end

  def test_attempt_snapshot_rejects_malformed_identity_state_and_contract_linkage
    assert_raises(ArgumentError) do
      RubyRouting::State::AttemptSnapshot.new(
        attempt_id: " ", operation_id: "o", provider_id: "A", role: :primary
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::State::AttemptSnapshot.new(
        attempt_id: "a", operation_id: "o", provider_id: "A", role: :resolution
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::State::AttemptSnapshot.new(
        attempt_id: "a", operation_id: "o", provider_id: "A", role: :primary, measure: -1
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::State::AttemptSnapshot.new(
        attempt_id: "a", operation_id: "o", provider_id: "A", role: :primary, outcome: :success
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::State::AttemptSnapshot.new(
        attempt_id: "a", operation_id: "o", provider_id: "A", role: :primary, committed_at: "now"
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::State::AttemptSnapshot.new(
        attempt_id: "a",
        operation_id: "o",
        provider_id: "A",
        role: :primary,
        contract: RubyRouting::ProviderOperationContract.new(
          provider_id: "B", idempotency_key: "p:o"
        )
      )
    end
  end

  def test_payout_snapshot_materializes_typed_history_and_links_ownership
    attempt = RubyRouting::State::AttemptSnapshot.new(
      attempt_id: "a",
      operation_id: "o",
      provider_id: "A",
      role: :primary
    )
    ownership = RubyRouting::EconomicOwnership.new(
      payout_id: "p",
      provider_id: "A",
      operation_id: "o",
      attempt_id: "a"
    )
    conflict = RubyRouting::EconomicConflict.new(
      payout_id: "p", provider_id: "A", operation_id: "o", attempt_id: "a", reason: :late_old_operation_success
    )
    reversal = RubyRouting::SettlementReversal.new(
      reversal_id: "r", payout_id: "p", provider_id: "A", operation_id: "o",
      amount: RubyRouting::Money.new(1, "RUB"), reason: :returned
    )
    snapshot = RubyRouting::State::PayoutSnapshot.new(
      intent: RubyRouting::PayoutIntent.new(id: "p", money: RubyRouting::Money.new(1, "RUB")),
      status: :pending,
      ownership: ownership,
      last_outcome: RubyRouting::NormalizedOutcome.pending,
      attempts: TestSupport::EachOnlyCollection.new([attempt]),
      primary_provider_id: " A ",
      settlement_provider_id: nil,
      settlement_operation_id: nil,
      policy_epoch: " 1 ",
      policy_scope_key: [" policy ", " 1 ", " default "],
      policy_fingerprint: " fingerprint ",
      provider_interaction_count: 1,
      resolution_interaction_count: 0,
      revision: 4,
      conflicts: TestSupport::EachOnlyCollection.new([conflict]),
      reversals: [reversal],
      created_at: Time.at(1)
    )

    assert_equal "A", snapshot.primary_provider_id
    assert_equal "1", snapshot.policy_epoch
    assert_equal ["policy", "1", "default"], snapshot.policy_scope_key
    assert_equal "fingerprint", snapshot.policy_fingerprint
    assert_equal [attempt], snapshot.attempts
    assert_equal [conflict], snapshot.conflicts
    assert_equal [reversal], snapshot.reversals
    assert_equal attempt, snapshot.current_operation
  end

  def test_payout_snapshot_rejects_untyped_or_unlinked_history
    intent = RubyRouting::PayoutIntent.new(id: "p", money: RubyRouting::Money.new(1, "RUB"))
    attempt = RubyRouting::State::AttemptSnapshot.new(
      attempt_id: "a", operation_id: "o", provider_id: "A", role: :primary
    )
    base = {
      intent: intent, status: :new, ownership: nil, last_outcome: nil, attempts: [attempt],
      primary_provider_id: nil, settlement_provider_id: nil, settlement_operation_id: nil,
      policy_epoch: nil, revision: 0
    }

    assert_raises(ArgumentError) { RubyRouting::State::PayoutSnapshot.new(**base.merge(attempts: [:bad])) }
    assert_raises(ArgumentError) { RubyRouting::State::PayoutSnapshot.new(**base.merge(provider_interaction_count: -1)) }
    assert_raises(ArgumentError) { RubyRouting::State::PayoutSnapshot.new(**base.merge(revision: 1.5)) }
    assert_raises(ArgumentError) { RubyRouting::State::PayoutSnapshot.new(**base.merge(created_at: "now")) }
    assert_raises(ArgumentError) { RubyRouting::State::PayoutSnapshot.new(**base.merge(policy_scope_key: ["p", "1"])) }
    assert_raises(ArgumentError) do
      RubyRouting::State::PayoutSnapshot.new(**base.merge(
        ownership: RubyRouting::EconomicOwnership.new(
          payout_id: "other", provider_id: "A", operation_id: "o", attempt_id: "a"
        )
      ))
    end
  end

  def test_decision_proposal_canonicalizes_inputs_and_enforces_action_shape
    proposal = RubyRouting::DecisionProposal.new(
      action: :assign,
      provider_id: " A ",
      role: :primary,
      policy_epoch: " 1 ",
      reasons: TestSupport::EachOnlyCollection.new([" selected "]),
      reason_codes: TestSupport::EachOnlyCollection.new([:allocation_choice])
    )

    assert_equal "A", proposal.provider_id
    assert_equal "1", proposal.policy_epoch
    assert_equal [" selected "], proposal.reasons
    assert_equal [:allocation_choice], proposal.reason_codes

    assert_raises(ArgumentError) do
      RubyRouting::DecisionProposal.new(action: :assign, provider_id: " ", role: :primary, policy_epoch: "1")
    end
    assert_raises(ArgumentError) do
      RubyRouting::DecisionProposal.new(action: :assign, provider_id: "A", role: :resolution, policy_epoch: "1")
    end
    assert_raises(ArgumentError) do
      RubyRouting::DecisionProposal.new(action: :resolve, provider_id: "A", role: :resolution, policy_epoch: "1")
    end
    assert_raises(ArgumentError) do
      RubyRouting::DecisionProposal.new(action: :defer, role: :primary, policy_epoch: "1")
    end
    assert_raises(ArgumentError) do
      RubyRouting::DecisionProposal.new(action: :terminate, role: :recovery, policy_epoch: "1")
    end
    assert_raises(ArgumentError) do
      RubyRouting::DecisionProposal.new(
        action: :defer,
        provider_id: "A",
        role: :recovery,
        policy_epoch: "1"
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::DecisionProposal.new(action: :defer, role: :resolution, policy_epoch: " ")
    end
    assert_raises(ArgumentError) do
      RubyRouting::DecisionProposal.new(action: :assign, provider_id: "A", role: :primary, policy_epoch: "1", allocation_decision: :bad)
    end
  end
end
