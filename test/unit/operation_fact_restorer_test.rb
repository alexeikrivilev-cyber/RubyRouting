# frozen_string_literal: true

require_relative "../test_helper"

class OperationFactRestorerTest < Minitest::Test
  Fact = Struct.new(:type, :payout_id, :payload, :sequence)
  Attempt = Struct.new(
    :operation_id,
    :attempt_id,
    :provider_id,
    :phase,
    :committed_monotonic_at,
    :contract
  )
  State = Struct.new(
    :operations,
    :operation_actions,
    :dispatch_pending,
    :provider_interaction_count,
    :resolution_interaction_count,
    :ownership,
    :allocation_fact_operations,
    :status,
    :latest_opportunity_evaluation,
    :throughput_reservations,
    :health_exposure_reservations
  )
  HealthSnapshot = Struct.new(:state)

  class FakeHealthController
    attr_reader :reserved, :released

    def initialize
      @reserved = []
      @released = []
    end

    def snapshot(_provider_id)
      HealthSnapshot.new(:probing)
    end

    def reserve_exposure(provider_id, owner:)
      @reserved << [provider_id, owner]
      true
    end

    def release_exposure(provider_id, owner:)
      @released << [provider_id, owner]
      true
    end
  end

  def setup
    @health = FakeHealthController.new
    @attempt = Attempt.new("operation", "attempt", "provider", :dispatching, nil, nil)
    @state = State.new(
      { "operation" => @attempt },
      { "operation" => :assign },
      { "operation" => true },
      0,
      0,
      nil,
      { "operation" => true },
      :pending,
      {
        throughput: { "provider" => nil },
        health: { "provider" => { state: :healthy } }
      },
      {},
      {}
    )
    @restorer = RubyRouting::State::OperationFactRestorer.new(
      payout_state: ->(_payout_id) { @state },
      health_controller: -> { @health },
      provider_identity: ->(payload, key) { payload.fetch(key) },
      operation_identity: ->(payload, key) { payload.fetch(key) },
      enum_value: ->(payload, key, _allowed, _label) { payload.fetch(key) },
      durable_monotonic: ->(payload, key) { payload.fetch(key) },
      monotonic_reference: ->(_value) { Rational(0, 1) },
      elapsed_seconds: ->(later, earlier) { later - earlier },
      reconciliation_expired_at: ->(_state, _attempt, _blocked_at) { true },
      validate_operation_release_order: ->(_state, _attempt, _operation_id, _label) {}
    )
  end

  def test_restores_attempt_start_and_consumes_dispatch_pending
    fact = Fact.new(
      :attempt_started,
      "payout",
      {
        operation_id: "operation",
        attempt_id: "attempt",
        provider_id: "provider",
        action: :assign
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_empty @state.dispatch_pending
    assert_equal 1, @state.provider_interaction_count
    assert_equal 0, @state.resolution_interaction_count
  end

  def test_restores_ownership_after_allocation_and_admission_facts
    @attempt.phase = :committed
    fact = Fact.new(
      :ownership_acquired,
      "payout",
      {
        provider_id: "provider",
        operation_id: "operation",
        attempt_id: "attempt"
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_equal "provider", @state.ownership.provider_id
    assert_equal "operation", @state.ownership.operation_id
    assert_equal :pending, @state.status
  end

  def test_restores_and_releases_health_exposure
    @attempt.phase = :committed
    reserved = Fact.new(
      :health_exposure_reserved,
      "payout",
      { provider_id: "provider", operation_id: "operation", attempt_id: "attempt" },
      1
    )
    released = Fact.new(
      :health_exposure_released,
      "payout",
      { provider_id: "provider", operation_id: "operation", attempt_id: "attempt" },
      2
    )

    assert_equal true, @restorer.apply(reserved)
    assert_equal ["provider", "operation"], @health.reserved.first
    assert_equal true, @restorer.apply(released)
    assert_empty @state.health_exposure_reservations
    assert_equal [["provider", "operation"]], @health.released
  end

  def test_returns_false_for_non_operation_fact
    fact = Fact.new(:decision_committed, "payout", {}, 1)

    assert_equal false, @restorer.apply(fact)
    assert_equal 0, @state.provider_interaction_count
  end
end
