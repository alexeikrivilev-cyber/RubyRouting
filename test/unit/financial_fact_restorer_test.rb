# frozen_string_literal: true

require_relative "../test_helper"

class FinancialFactRestorerTest < Minitest::Test
  Fact = Struct.new(:type, :payout_id, :payload, :sequence)
  Intent = Struct.new(:money)
  Attempt = Struct.new(:operation_id, :attempt_id, :provider_id, :phase)
  State = Struct.new(
    :intent,
    :operations,
    :seen_observations,
    :conflict_observation_ids,
    :conflicts,
    :status,
    :reversals,
    :settlement_provider_id,
    :settlement_operation_id
  )

  def setup
    @money = RubyRouting::Money.new(100, "RUB")
    @attempt = Attempt.new("operation", "attempt", "provider", :released)
    @state = State.new(
      Intent.new(@money),
      { "operation" => @attempt },
      { "observation" => true },
      [],
      [],
      :safe_route_failure,
      [],
      nil,
      nil
    )
    @pending_conflicts = { ["payout", "observation"] => true }
    @restorer = RubyRouting::State::FinancialFactRestorer.new(
      payout_state: ->(_payout_id) { @state },
      pending_economic_conflicts: -> { @pending_conflicts },
      operation_identity: ->(payload, key) { payload.fetch(key) },
      provider_identity: ->(payload, key) { payload.fetch(key) },
      enum_value: ->(payload, key, _allowed, _label) { payload.fetch(key) },
      optional_operation_identity: lambda do |payload, key, default:|
        payload.fetch(key, default)
      end
    )
  end

  def test_restores_a_late_success_conflict_after_the_source_observation
    fact = Fact.new(
      :economic_conflict,
      "payout",
      {
        observation_id: "observation",
        provider_id: "provider",
        operation_id: "operation",
        attempt_id: "attempt",
        reason: :late_old_operation_success
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_equal 1, @state.conflicts.size
    assert_equal :late_old_operation_success, @state.conflicts.first.reason
    assert_empty @pending_conflicts
  end

  def test_restores_a_linked_settlement_reversal
    @attempt.phase = :settled
    @state.status = :success
    @state.settlement_provider_id = "provider"
    @state.settlement_operation_id = "operation"
    fact = Fact.new(
      :reversal_recorded,
      "payout",
      {
        reversal_id: "reversal",
        provider_id: "provider",
        operation_id: "operation",
        attempt_id: "attempt",
        amount: RubyRouting::Money.new(40, "RUB"),
        reason: :returned
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_equal :reversed, @state.status
    assert_equal 40, @state.reversals.first.amount.amount_minor
  end

  def test_returns_false_for_non_financial_fact
    fact = Fact.new(:health_signal, "system:provider:provider", {}, 1)

    assert_equal false, @restorer.apply(fact)
    assert_empty @state.conflicts
  end
end
