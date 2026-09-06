# frozen_string_literal: true

require_relative "../test_helper"

class LifecycleLedgerTest < Minitest::Test
  LifecycleState = Struct.new(:operations, :ownership, :dispatch_pending, :last_outcome, :status)
  LifecycleAttempt = Struct.new(:operation_id, :attempt_id, :provider_id, :phase)
  LifecycleOwner = Struct.new(:operation_id)

  def test_outcome_reducer_owns_phase_status_and_release_classification
    ledger = RubyRouting::State::LifecycleLedger.new
    attempt = LifecycleAttempt.new("operation-1", "attempt-1", "A", :dispatching)
    state = LifecycleState.new(
      { "operation-1" => attempt },
      LifecycleOwner.new("operation-1"),
      { "operation-1" => true },
      nil,
      :pending
    )

    transition = ledger.apply_outcome(
      state,
      attempt,
      RubyRouting::NormalizedOutcome.success(attribution: :provider)
    )

    assert_equal :settled, attempt.phase
    assert_equal :success, state.status
    assert transition.settled?
    assert transition.release_ownership?
    assert_equal :settled, transition.phase_change.to
    assert_empty state.dispatch_pending
  end

  def test_phase_change_rejects_history_that_does_not_follow_current_phase
    ledger = RubyRouting::State::LifecycleLedger.new
    attempt = LifecycleAttempt.new("operation-1", "attempt-1", "A", :unknown)
    state = LifecycleState.new({ "operation-1" => attempt }, nil, {}, nil, :unknown)

    assert_raises(ArgumentError) do
      ledger.apply_phase_change(state, "operation-1", from: :dispatching, to: :settled)
    end
  end

  def test_phase_changes_use_canonical_operation_and_attempt_identity
    ledger = RubyRouting::State::LifecycleLedger.new
    attempt = LifecycleAttempt.new("operation-1", "attempt-1", "provider-1", :unknown)
    state = LifecycleState.new({ "operation-1" => attempt }, nil, {}, nil, :unknown)

    phase_change = ledger.apply_phase_change(state, " operation-1 ", from: :unknown, to: :resolving)

    assert_equal "operation-1", phase_change.operation_id
    assert_equal "attempt-1", phase_change.attempt_id
    assert_equal "provider-1", phase_change.provider_id
    assert_equal :resolving, attempt.phase
  end

  def test_phase_change_rejects_blank_identity
    assert_raises(ArgumentError) do
      RubyRouting::State::LifecycleLedger::PhaseChange.new(
        operation_id: " ",
        attempt_id: "attempt-1",
        provider_id: "provider-1",
        from: :unknown,
        to: :resolving
      )
    end
  end

  def test_status_for_reuses_the_same_outcome_reduction_as_live_application
    ledger = RubyRouting::State::LifecycleLedger.new

    assert_equal :success, ledger.status_for(RubyRouting::NormalizedOutcome.success)
    assert_equal :pending, ledger.status_for(RubyRouting::NormalizedOutcome.pending)
    assert_equal :unknown, ledger.status_for(RubyRouting::NormalizedOutcome.unknown)
    assert_equal :safe_route_failure,
      ledger.status_for(RubyRouting::NormalizedOutcome.safe_route_failure)
  end

  def test_phase_transition_table_is_deeply_immutable
    transitions = RubyRouting::State::LifecycleLedger::PHASE_TRANSITIONS

    assert_predicate transitions, :frozen?
    assert_predicate transitions.fetch(:committed), :frozen?
    assert_raises(FrozenError) { transitions.fetch(:committed) << :made_up_phase }
  end
end
