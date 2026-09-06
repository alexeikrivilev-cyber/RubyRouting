# frozen_string_literal: true

require_relative "../test_helper"

class ObservationFactRestorerTest < Minitest::Test
  Fact = Struct.new(:type, :payout_id, :payload, :sequence)
  Attempt = Struct.new(
    :operation_id,
    :attempt_id,
    :provider_id,
    :phase,
    :contract,
    :outcome,
    :last_observation_sequence
  )
  State = Struct.new(
    :operations,
    :ownership,
    :seen_observations,
    :last_outcome,
    :status,
    :dispatch_pending,
    :applied_observation_fact_sequences
  )

  def setup
    @attempt = Attempt.new("operation", "attempt", "provider", :dispatching, nil, nil, nil)
    @state = State.new(
      { "operation" => @attempt },
      RubyRouting::EconomicOwnership.new(
        payout_id: "payout",
        provider_id: "provider",
        operation_id: "operation",
        attempt_id: "attempt"
      ),
      {},
      nil,
      :pending,
      { "operation" => true },
      {}
    )
    @restored_observations = {}
    @pending_conflicts = {}
    @restorer = RubyRouting::State::ObservationFactRestorer.new(
      observation_ledger: -> { RubyRouting::State::ObservationLedger.new },
      lifecycle_ledger: -> { RubyRouting::State::LifecycleLedger.new },
      payout_state: ->(_payout_id) { @state },
      restored_observations: -> { @restored_observations },
      pending_economic_conflicts: -> { @pending_conflicts },
      operation_identity: ->(payload, key) { payload.fetch(key) },
      provider_identity: ->(payload, key) { payload.fetch(key) }
    )
    @fact = Fact.new(
      :provider_observed,
      "payout",
      {
        observation_id: "observation",
        provider_id: "provider",
        operation_id: "operation",
        attempt_id: "attempt",
        provider_reference: "provider-reference",
        status: :success,
        attribution: :provider,
        outcome_provider_reference: "provider-reference",
        message: "accepted",
        safe_to_release: false,
        applied: true,
        conflict: false,
        sequence: nil,
        observed_at: nil,
        transport_kind: nil
      },
      1
    )
  end

  def test_replays_a_normalized_observation_and_reduces_lifecycle_status
    assert_equal true, @restorer.apply(@fact)
    assert_equal :success, @state.status
    assert_equal :success, @state.last_outcome.status
    assert_empty @state.dispatch_pending
    assert_equal ["payout", "observation"], @restored_observations.keys.first
  end

  def test_duplicate_observation_is_idempotent
    assert_equal true, @restorer.apply(@fact)
    assert_equal true, @restorer.apply(@fact)

    assert_equal 1, @state.seen_observations.size
    assert_equal :success, @state.status
    assert_empty @pending_conflicts
  end

  def test_returns_false_for_non_observation_facts
    fact = Fact.new(:settlement_recorded, "payout", {}, 1)

    assert_equal false, @restorer.apply(fact)
    assert_empty @state.seen_observations
  end
end
