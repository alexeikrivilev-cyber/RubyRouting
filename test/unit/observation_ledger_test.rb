# frozen_string_literal: true

require_relative "../test_helper"

class ObservationLedgerTest < Minitest::Test
  ObservationAttempt = Struct.new(:phase, :contract, :last_observation_sequence, :outcome)

  def test_exact_duplicate_is_idempotent_but_payload_reuse_is_rejected
    ledger = RubyRouting::State::ObservationLedger.new
    seen = {}
    attempt = attempt(phase: :dispatching)
    observation = observation(id: "observation-1", outcome: RubyRouting::NormalizedOutcome.pending)

    first = ledger.observe(
      seen_observations: seen,
      current_operation_id: "operation-1",
      attempt: attempt,
      observation: observation
    )
    duplicate = ledger.observe(
      seen_observations: seen,
      current_operation_id: "operation-1",
      attempt: attempt,
      observation: observation
    )

    refute first.duplicate?
    assert first.applies?
    assert duplicate.duplicate?
    refute duplicate.applies?
    assert_equal 1, seen.length

    conflicting = observation(id: "observation-1", outcome: RubyRouting::NormalizedOutcome.success)
    assert_raises(ArgumentError) do
      ledger.observe(
        seen_observations: seen,
        current_operation_id: "operation-1",
        attempt: attempt,
        observation: conflicting
      )
    end
  end

  def test_authoritative_provider_sequence_and_transport_classification_are_distinct
    ledger = RubyRouting::State::ObservationLedger.new
    seen = {}
    attempt = attempt(
      phase: :dispatching,
      contract: RubyRouting::ProviderOperationContract.new(
        provider_id: "A",
        idempotency_key: "payout:operation-1",
        authoritative_sequence: true
      )
    )

    first = ledger.observe(
      seen_observations: seen,
      current_operation_id: "operation-1",
      attempt: attempt,
      observation: observation(id: "observation-1", sequence: 2)
    )
    attempt.last_observation_sequence = 2
    stale = ledger.observe(
      seen_observations: seen,
      current_operation_id: "operation-1",
      attempt: attempt,
      observation: observation(id: "observation-2", sequence: 1)
    )
    unsequenced_event = ledger.observe(
      seen_observations: seen,
      current_operation_id: "operation-1",
      attempt: attempt,
      observation: observation(id: "observation-3", sequence: nil)
    )
    transport = ledger.observe(
      seen_observations: seen,
      current_operation_id: "operation-1",
      attempt: attempt,
      observation: observation(
        id: "observation-4",
        sequence: nil,
        transport_kind: :ambiguous_after_possible_send
      )
    )

    assert first.applies?
    assert first.health_evidence?
    refute stale.applies?
    refute stale.health_evidence?
    refute unsequenced_event.applies?
    refute unsequenced_event.health_evidence?
    assert transport.applies?
    assert transport.health_evidence?
  end

  def test_late_new_authoritative_sequence_can_still_supply_health_evidence
    ledger = RubyRouting::State::ObservationLedger.new
    seen = {}
    attempt = attempt(
      phase: :released,
      contract: RubyRouting::ProviderOperationContract.new(
        provider_id: "A",
        idempotency_key: "payout:operation-1",
        authoritative_sequence: true
      )
    )

    decision = ledger.observe(
      seen_observations: seen,
      current_operation_id: "operation-2",
      attempt: attempt,
      observation: observation(
        id: "observation-late-success",
        outcome: RubyRouting::NormalizedOutcome.success,
        sequence: 1
      )
    )

    refute decision.applies?
    assert decision.conflict?
    assert decision.health_evidence?
    assert_equal 1, attempt.last_observation_sequence
  end

  def test_restore_rejects_health_evidence_that_violates_authoritative_order
    ledger = RubyRouting::State::ObservationLedger.new
    payload = {
      observation_id: "observation-stale",
      provider_id: "A",
      operation_id: "operation-1",
      attempt_id: "attempt-1",
      status: :safe_route_failure,
      attribution: :provider,
      safe_to_release: true,
      applied: false,
      conflict: false,
      sequence: 1,
      observed_at: Time.utc(2026, 8, 29, 12, 0, 0),
      health_evidence: true
    }
    attempt = attempt(
      phase: :dispatching,
      contract: RubyRouting::ProviderOperationContract.new(
        provider_id: "A",
        idempotency_key: "payout:operation-1",
        authoritative_sequence: true
      )
    )
    attempt.last_observation_sequence = 2

    assert_raises(ArgumentError) do
      ledger.restore(
        seen_observations: {},
        payout_id: "payout-1",
        payload: payload,
        current_operation_id: "operation-1",
        attempt: attempt
      )
    end
  end

  def test_late_success_from_released_old_operation_is_a_conflict
    ledger = RubyRouting::State::ObservationLedger.new
    decision = ledger.observe(
      seen_observations: {},
      current_operation_id: "operation-2",
      attempt: attempt(phase: :released),
      observation: observation(id: "observation-1", outcome: RubyRouting::NormalizedOutcome.success)
    )

    refute decision.applies?
    assert decision.conflict?
  end

  def test_causal_hold_blocks_safe_release_until_owning_completion
    ledger = RubyRouting::State::ObservationLedger.new
    seen = {}
    attempt = attempt(phase: :unknown)
    release = observation(
      id: "independent-release",
      outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
    )

    held = ledger.observe(
      seen_observations: seen,
      current_operation_id: "operation-1",
      attempt: attempt,
      observation: release,
      causal_hold: true
    )
    success = ledger.observe(
      seen_observations: seen,
      current_operation_id: "operation-1",
      attempt: attempt,
      observation: observation(id: "owning-success", outcome: RubyRouting::NormalizedOutcome.success)
    )

    assert held.causal_hold?
    refute held.applies?
    refute held.conflict?
    assert success.applies?
    assert success.conflict?
    assert success.causal_contradiction?
  end

  def test_restore_rejects_causal_hold_without_unresolved_lifecycle
    ledger = RubyRouting::State::ObservationLedger.new
    payload = {
      observation_id: "independent-release",
      provider_id: "A",
      operation_id: "operation-1",
      attempt_id: "attempt-1",
      status: :safe_route_failure,
      attribution: :provider,
      safe_to_release: true,
      applied: false,
      conflict: false,
      causal_hold: true,
      sequence: nil,
      observed_at: Time.utc(2026, 8, 29, 12, 0, 0)
    }

    assert_raises(ArgumentError) do
      ledger.restore(
        seen_observations: {},
        payout_id: "payout-1",
        payload: payload,
        current_operation_id: "operation-2",
        attempt: attempt(phase: :released)
      )
    end
  end

  def test_restore_rejects_causal_hold_for_a_non_current_operation
    ledger = RubyRouting::State::ObservationLedger.new
    payload = {
      observation_id: "independent-release-old-operation",
      provider_id: "A",
      operation_id: "operation-1",
      attempt_id: "attempt-1",
      status: :safe_route_failure,
      attribution: :provider,
      safe_to_release: true,
      applied: false,
      conflict: false,
      causal_hold: true,
      sequence: nil,
      observed_at: Time.utc(2026, 8, 29, 12, 0, 0)
    }

    assert_raises(ArgumentError) do
      ledger.restore(
        seen_observations: {},
        payout_id: "payout-1",
        payload: payload,
        current_operation_id: "operation-2",
        attempt: attempt(phase: :unknown)
      )
    end
  end

  def test_restore_uses_the_same_identity_rule_as_live_observation
    ledger = RubyRouting::State::ObservationLedger.new
    seen = {}
    payload = {
      observation_id: "observation-1",
      provider_id: "A",
      operation_id: "operation-1",
      attempt_id: "attempt-1",
      provider_reference: "transport-ref",
      status: :pending,
      attribution: :provider,
      outcome_provider_reference: "provider-ref",
      message: "waiting",
      safe_to_release: false,
      sequence: 4,
      observed_at: Time.utc(2026, 8, 29, 12, 0, 0),
      transport_kind: nil,
      applied: true,
      conflict: false
    }

    restore_attempt = attempt(phase: :dispatching)
    first = ledger.restore(
      seen_observations: seen,
      payout_id: "payout-1",
      payload: payload,
      current_operation_id: "operation-1",
      attempt: restore_attempt
    )
    duplicate = ledger.restore(
      seen_observations: seen,
      payout_id: "payout-1",
      payload: payload.dup,
      current_operation_id: "operation-1",
      attempt: restore_attempt
    )

    refute first.duplicate?
    assert first.applies?
    assert duplicate.duplicate?

    conflicting = payload.merge(status: :unknown)
    assert_raises(ArgumentError) do
      ledger.restore(
        seen_observations: seen,
        payout_id: "payout-1",
        payload: conflicting,
        current_operation_id: "operation-1",
        attempt: restore_attempt
      )
    end
  end

  def test_restore_keeps_an_exact_duplicate_idempotent_after_a_newer_authoritative_event
    ledger = RubyRouting::State::ObservationLedger.new
    seen = {}
    attempt = attempt(
      phase: :dispatching,
      contract: RubyRouting::ProviderOperationContract.new(
        provider_id: "A",
        idempotency_key: "payout:operation-1",
        authoritative_sequence: true
      )
    )
    original = {
      observation_id: "observation-2",
      provider_id: "A",
      operation_id: "operation-1",
      attempt_id: "attempt-1",
      status: :pending,
      attribution: :provider,
      safe_to_release: false,
      applied: true,
      conflict: false,
      sequence: 2,
      observed_at: Time.utc(2026, 8, 29, 12, 0, 0),
      health_evidence: true
    }
    newer = original.merge(
      observation_id: "observation-4",
      sequence: 4,
      applied: false,
      health_evidence: true
    )

    first = ledger.restore(
      seen_observations: seen,
      payout_id: "payout-1",
      payload: original,
      current_operation_id: "operation-1",
      attempt: attempt
    )
    ledger.restore(
      seen_observations: seen,
      payout_id: "payout-1",
      payload: newer,
      current_operation_id: "operation-2",
      attempt: attempt
    )
    duplicate = ledger.restore(
      seen_observations: seen,
      payout_id: "payout-1",
      payload: original,
      current_operation_id: "operation-1",
      attempt: attempt
    )

    assert first.applies?
    assert duplicate.duplicate?
    assert_equal 4, attempt.last_observation_sequence

    assert_raises(ArgumentError) do
      ledger.restore(
        seen_observations: seen,
        payout_id: "payout-1",
        payload: original.merge(applied: false),
        current_operation_id: "operation-1",
        attempt: attempt
      )
    end
  end

  def test_restore_rejects_noncanonical_observation_fields
    ledger = RubyRouting::State::ObservationLedger.new
    base = {
      observation_id: "observation-1",
      provider_id: "A",
      operation_id: "operation-1",
      attempt_id: "attempt-1",
      status: :pending,
      attribution: :provider,
      safe_to_release: false,
      applied: true,
      conflict: false,
      sequence: 1,
      observed_at: Time.utc(2026, 8, 29, 12, 0, 0)
    }

    {
      observation_id: :symbol_id,
      provider_id: :symbol_provider_id,
      operation_id: " operation-1",
      attempt_id: :symbol_attempt_id,
      applied: "true",
      conflict: nil,
      safe_to_release: 0,
      sequence: -1,
      observed_at: "not-a-time",
      status: :not_an_outcome,
      attribution: :not_an_attribution,
      transport_kind: :not_a_transport_kind
    }.each do |field, value|
      assert_raises(ArgumentError, "field=#{field}") do
        ledger.restore(
          seen_observations: {},
          payout_id: "payout-1",
          payload: base.merge(field => value),
          current_operation_id: "operation-1",
          attempt: attempt(phase: :dispatching)
        )
      end
    end
  end

  private

  def attempt(phase:, contract: nil)
    ObservationAttempt.new(phase, contract, nil, nil)
  end

  def observation(id:, outcome: RubyRouting::NormalizedOutcome.pending,
                  sequence: nil, transport_kind: nil)
    RubyRouting::ProviderObservation.new(
      observation_id: id,
      payout_id: "payout-1",
      provider_id: "A",
      operation_id: "operation-1",
      attempt_id: "attempt-1",
      outcome: outcome,
      provider_reference: "transport-ref",
      sequence: sequence,
      observed_at: Time.utc(2026, 8, 29, 12, 0, 0),
      transport_kind: transport_kind
    )
  end
end
