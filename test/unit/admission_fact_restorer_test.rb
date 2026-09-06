# frozen_string_literal: true

require_relative "../test_helper"

class AdmissionFactRestorerTest < Minitest::Test
  Fact = Struct.new(:type, :payout_id, :payload, :sequence)
  Intent = Struct.new(:money)
  Attempt = Struct.new(:provider_id, :phase)
  State = Struct.new(
    :intent,
    :capacity_reservations,
    :ownership,
    :operations,
    :dispatch_pending,
    :status,
    :throughput_reservations,
    :allocation_fact_operations
  )

  def setup
    @clock = TestSupport::ControlledClock.new
    @admission = RubyRouting::State::AdmissionLedger.new(clock: @clock)
    @provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "provider",
      capacity: RubyRouting::CapacityBudget.new(max_slots: 1),
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)
    )
    @catalog = RubyRouting::State::ProviderCatalogLedger.new(opportunities: [@provider])
    @money = RubyRouting::Money.new(100, "RUB")
    @attempt = Attempt.new("provider", :committed)
    @state = State.new(
      Intent.new(@money),
      {},
      nil,
      { "operation" => @attempt },
      { "operation" => true },
      :pending,
      {},
      { "operation" => true }
    )
    @restorer = RubyRouting::State::AdmissionFactRestorer.new(
      admission_ledger: -> { @admission },
      provider_catalog: -> { @catalog },
      payout_state: ->(_payout_id) { @state },
      provider_identity: ->(payload, key) { payload.fetch(key) },
      operation_identity: ->(payload, key) { payload.fetch(key) },
      validate_provider_registered_before_fact: ->(_fact, _provider_id) {},
      validate_operation_release_order: ->(_state, _attempt, _operation_id, _label) {},
      durable_monotonic: ->(payload, key) { payload.fetch(key) },
      monotonic_reference: ->(_time) { Rational(0, 1) }
    )
  end

  def test_restores_and_releases_capacity_through_the_admission_ledger
    reserved = Fact.new(
      :capacity_reserved,
      "payout",
      { provider_id: "provider", operation_id: "operation", amount: @money },
      1
    )
    released = Fact.new(
      :capacity_released,
      "payout",
      { provider_id: "provider", operation_id: "operation", amount: @money },
      2
    )

    assert_equal true, @restorer.apply(reserved)
    assert_equal 1, @admission.capacity_snapshot("provider", budget: @provider.capacity).used_slots
    assert_equal true, @restorer.apply(released)
    assert_equal 0, @admission.capacity_snapshot("provider", budget: @provider.capacity).used_slots
    assert_empty @state.capacity_reservations
  end

  def test_restores_throughput_with_the_exact_monotonic_anchor
    consumed_at = @clock.current_time
    fact = Fact.new(
      :throughput_consumed,
      "payout",
      {
        provider_id: "provider",
        operation_id: "operation",
        budget: @provider.throughput.to_h,
        consumed_at: consumed_at,
        consumed_monotonic_at: Rational(5, 2)
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    @clock.advance(Rational(5, 2))
    assert_equal [consumed_at], @admission.throughput_snapshot(
      "provider",
      budget: @provider.throughput
    ).consumed_at
    assert_equal ["provider", consumed_at, Rational(5, 2)], @state.throughput_reservations["operation"]
  end

  def test_returns_false_for_non_admission_facts
    fact = Fact.new(:decision_committed, "payout", {}, 1)

    assert_equal false, @restorer.apply(fact)
    assert_empty @state.capacity_reservations
    assert_empty @state.throughput_reservations
  end
end
