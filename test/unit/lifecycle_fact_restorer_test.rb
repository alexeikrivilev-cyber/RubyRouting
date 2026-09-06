# frozen_string_literal: true

require_relative "../test_helper"

class LifecycleFactRestorerTest < Minitest::Test
  Fact = Struct.new(:type, :payout_id, :payload, :sequence)
  Attempt = Struct.new(:operation_id, :attempt_id, :provider_id, :phase, :measure, :outcome)
  State = Struct.new(
    :operations,
    :ownership,
    :dispatch_pending,
    :settlement_operation_id,
    :settlement_provider_id,
    :last_outcome,
    :status
  )

  def setup
    @attempt = Attempt.new("operation", "attempt", "provider", :committed, 100, nil)
    @state = State.new(
      { "operation" => @attempt },
      RubyRouting::EconomicOwnership.new(
        payout_id: "payout",
        provider_id: "provider",
        operation_id: "operation",
        attempt_id: "attempt"
      ),
      { "operation" => true },
      nil,
      nil,
      nil,
      :pending
    )
    @restorer = RubyRouting::State::LifecycleFactRestorer.new(
      lifecycle_ledger: -> { RubyRouting::State::LifecycleLedger.new },
      payout_state: ->(_payout_id) { @state },
      operation_identity: ->(payload, key) { payload.fetch(key) },
      provider_identity: ->(payload, key) { payload.fetch(key) },
      enum_value: ->(payload, key, _allowed, _label) { payload.fetch(key) },
      validate_operation_release_order: ->(_state, _attempt, _operation_id, _label) {}
    )
  end

  def test_replays_a_phase_change_through_the_lifecycle_ledger
    fact = Fact.new(
      :operation_phase_changed,
      "payout",
      {
        operation_id: "operation",
        attempt_id: "attempt",
        provider_id: "provider",
        from: :committed,
        to: :dispatching
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_equal :dispatching, @attempt.phase
  end

  def test_replays_ownership_release_without_releasing_other_state
    @attempt.phase = :released
    @attempt.outcome = RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
    fact = Fact.new(
      :ownership_released,
      "payout",
      {
        operation_id: "operation",
        attempt_id: "attempt",
        provider_id: "provider",
        reason: :safe_route_failure
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_nil @state.ownership
    assert_empty @state.dispatch_pending
  end

  def test_replays_settlement_only_for_a_settled_successful_operation
    @attempt.phase = :settled
    @state.ownership = nil
    @state.last_outcome = RubyRouting::NormalizedOutcome.success(attribution: :provider)
    fact = Fact.new(
      :settlement_recorded,
      "payout",
      {
        operation_id: "operation",
        provider_id: "provider",
        outcome: :success,
        measure: 100
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_equal :success, @state.status
    assert_equal "operation", @state.settlement_operation_id
  end
end
