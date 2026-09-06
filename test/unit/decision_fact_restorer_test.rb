# frozen_string_literal: true

require_relative "../test_helper"

class DecisionFactRestorerTest < Minitest::Test
  Fact = Struct.new(:type, :payout_id, :payload, :sequence)
  Attempt = Struct.new(
    :attempt_id,
    :operation_id,
    :provider_id,
    :role,
    :measure,
    :phase,
    :contract,
    :committed_at,
    :committed_monotonic_at
  )
  State = Struct.new(
    :operations,
    :attempts,
    :dispatch_pending,
    :operation_actions,
    :primary_provider_id,
    :operation_action_fact_sequences
  )

  class TraceValidator
    def validate_policy_binding(_state, _payload); end
    def validate_non_operation_decision(state:, action:, payload:); end
    def validate_assignment_trace(state:, payload:, provider_id:); end
    def validate_assignment(fact:, state:, provider_id:, operation_id:, attempt_id:, role:, measure:, contract:); end
    def validate_resolution_trace(state:, attempt:, action:, payload:); end
    def validate_resolution(state:, attempt:, action:, payload:, provider_id:, attempt_id:, role:, operation_id:); end
  end

  def setup
    @state = State.new({}, [], {}, {}, nil, {})
    @contract = Object.new
    @trace_validator = TraceValidator.new
    @restorer = RubyRouting::State::DecisionFactRestorer.new(
      payout_state: ->(_payout_id) { @state },
      enum_value: ->(payload, key, _allowed, _label) { payload.fetch(key) },
      decision_identifier: ->(value, _label) { value },
      provider_identity: ->(payload, key) { payload.fetch(key) },
      decision_role: ->(value, action:) { value },
      decision_trace_validator: @trace_validator,
      validate_provider_registered: ->(_fact, _provider_id) {},
      contract_from_payload: ->(_payload) { @contract },
      attempt_state_factory: ->(**attributes) { Attempt.new(**attributes) },
      monotonic_value: ->(payload, key) { payload.fetch(key) },
      monotonic_reference: ->(_value) { Rational(1, 1) }
    )
  end

  def test_restores_assignment_and_dispatch_pending_state
    fact = Fact.new(
      :decision_committed,
      "payout",
      {
        action: :assign,
        provider_id: "provider",
        operation_id: "operation",
        attempt_id: "attempt",
        role: :primary,
        measure: :count,
        contract: {},
        committed_at: nil
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_equal "provider", @state.primary_provider_id
    assert_equal true, @state.dispatch_pending["operation"]
    assert_equal :assign, @state.operation_actions["operation"]
    assert_equal @contract, @state.operations["operation"].contract
  end

  def test_restores_resolution_decision_without_creating_an_attempt
    attempt = Attempt.new("attempt", "operation", "provider", :primary, :count, :unknown, @contract, nil, nil)
    @state.operations["operation"] = attempt
    @state.attempts << attempt
    @state.dispatch_pending["operation"] = nil
    fact = Fact.new(
      :decision_committed,
      "payout",
      {
        action: :resolve,
        provider_id: "provider",
        operation_id: "operation",
        attempt_id: "attempt",
        role: :resolution
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_equal :resolution, @state.dispatch_pending["operation"]
    assert_equal :resolve, @state.operation_actions["operation"]
    assert_equal 1, @state.attempts.size
  end

  def test_returns_false_for_non_decision_fact
    fact = Fact.new(:opportunity_evaluated, "payout", {}, 1)

    assert_equal false, @restorer.apply(fact)
    assert_empty @state.operations
  end
end
