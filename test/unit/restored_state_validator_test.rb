# frozen_string_literal: true

require_relative "../test_helper"

class RestoredStateValidatorTest < Minitest::Test
  Owner = Struct.new(:operation_id)

  def setup
    @payouts = {}
    @pending_health_transitions = {}
    @pending_economic_conflicts = {}
    @validator = RubyRouting::State::RestoredStateValidator.new(
      payouts: -> { @payouts },
      pending_health_transitions: -> { @pending_health_transitions },
      pending_economic_conflicts: -> { @pending_economic_conflicts }
    )
    @state = RubyRouting::State::Coordinator::PayoutState.new(
      RubyRouting::PayoutIntent.new(
        id: "payout",
        money: RubyRouting::Money.new(100, "RUB")
      )
    )
    @payouts["payout"] = @state
  end

  def test_accepts_a_valid_unresolved_payout_after_replay
    @state.status = :pending
    @state.ownership = Owner.new("operation")

    assert_nil @validator.validate!
  end

  def test_rejects_unpaired_cross_fact_state
    @pending_health_transitions[["provider", 3]] = :degraded

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      @validator.validate!
    end

    assert_match(/health state transition is missing/, error.message)
  end

  def test_rejects_committed_dispatch_without_ownership
    attempt = RubyRouting::State::Coordinator::AttemptState.new(
      attempt_id: "attempt",
      operation_id: "operation",
      provider_id: "provider",
      role: :primary,
      measure: 1,
      phase: :committed,
      contract: nil
    )
    @state.operations["operation"] = attempt
    @state.dispatch_pending["operation"] = true

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      @validator.validate!
    end

    assert_match(/committed assignment is missing ownership/, error.message)
  end

  def test_release_order_requires_terminal_operation_phase
    attempt = RubyRouting::State::Coordinator::AttemptState.new(
      attempt_id: "attempt",
      operation_id: "operation",
      provider_id: "provider",
      role: :primary,
      measure: 1,
      phase: :pending,
      contract: nil
    )
    @state.ownership = Owner.new("operation")

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      @validator.validate_operation_release_order(@state, attempt, "operation", "capacity release")
    end

    assert_match(/capacity release is not ordered/, error.message)
  end
end
