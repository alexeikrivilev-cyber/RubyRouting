# frozen_string_literal: true

require_relative "../test_helper"

class AdmissionLedgerTest < Minitest::Test
  def test_admission_ledger_uses_one_canonical_provider_bucket
    clock = TestSupport::ControlledClock.new
    ledger = RubyRouting::State::AdmissionLedger.new(clock: clock)
    money = RubyRouting::Money.new(100, "RUB")
    capacity = RubyRouting::CapacityBudget.new(max_slots: 1, max_amount_minor: 100, currency: "RUB")
    throughput = RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)

    ledger.ensure_provider(" A ")
    ledger.restore_capacity_reservation!(" A ", money)
    ledger.restore_throughput!(" A ", clock.now)

    capacity_snapshot = ledger.capacity_snapshot("A", budget: capacity)
    throughput_snapshot = ledger.throughput_snapshot(" A ", budget: throughput)

    assert_equal "A", capacity_snapshot.provider_id
    assert_equal 1, capacity_snapshot.used_slots
    assert_equal 1, capacity_snapshot.used_count
    assert_equal 100, capacity_snapshot.used_amount_minor
    assert_equal "A", throughput_snapshot.provider_id
    assert_equal 1, throughput_snapshot.consumed_count
    refute throughput_snapshot.available?

    ledger.release_capacity!(" A ", money)
    assert_equal 0, ledger.capacity_snapshot("A", budget: capacity).used_slots
  end

  def test_capacity_budget_uses_one_concurrent_limit_and_keeps_count_as_legacy_cap
    budget = RubyRouting::CapacityBudget.new(max_slots: 2, max_count: 3)
    money = RubyRouting::Money.new(100, "RUB")

    assert_equal 2, budget.concurrent_limit
    assert budget.allows?(money, used_slots: 1, used_count: 1, used_amount_minor: 100)
    refute budget.allows?(money, used_slots: 2, used_count: 2, used_amount_minor: 100)
    refute budget.allows?(money, used_slots: 1, used_count: 2, used_amount_minor: 100)
    assert_equal({ max_slots: 2, max_count: 3, max_amount_minor: nil, currency: nil }, budget.to_h)

    count_only = RubyRouting::CapacityBudget.new(max_count: 2)
    assert_equal 2, count_only.concurrent_limit
  end

  def test_admission_snapshots_reject_malformed_values_and_accept_each_only_times
    budget = RubyRouting::CapacityBudget.new(max_slots: 1)

    assert_raises(ArgumentError) do
      RubyRouting::State::CapacitySnapshot.new(
        provider_id: " ", budget: budget, used_slots: 0, used_count: 0, used_amount_minor: 0
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::State::CapacitySnapshot.new(
        provider_id: "A", budget: budget, used_slots: -1, used_count: 0, used_amount_minor: 0
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::State::CapacitySnapshot.new(
        provider_id: "A", budget: budget, used_slots: 1, used_count: 2, used_amount_minor: 0
      )
    end
    assert_raises(ArgumentError) do
      RubyRouting::State::CapacitySnapshot.new(
        provider_id: "A", budget: Object.new, used_slots: 0, used_count: 0, used_amount_minor: 0
      )
    end
    assert_raises(ArgumentError) do
      ledger = RubyRouting::State::AdmissionLedger.new(clock: TestSupport::ControlledClock.new)
      ledger.capacity_snapshot("A", budget: Object.new)
    end
    assert_raises(ArgumentError) do
      RubyRouting::State::ThroughputSnapshot.new(provider_id: " ", budget: nil, consumed_at: [])
    end
    assert_raises(ArgumentError) do
      RubyRouting::State::ThroughputSnapshot.new(provider_id: "A", budget: nil, consumed_at: ["not-time"])
    end

    snapshot = RubyRouting::State::ThroughputSnapshot.new(
      provider_id: " A ",
      budget: nil,
      consumed_at: TestSupport::EachOnlyCollection.new([Time.at(1)])
    )
    assert_equal "A", snapshot.provider_id
    assert_equal 1, snapshot.consumed_count
  end

  def test_admission_mutations_reject_malformed_money_and_time_before_recording
    ledger = RubyRouting::State::AdmissionLedger.new(clock: TestSupport::ControlledClock.new)

    assert_raises(ArgumentError) { ledger.restore_capacity_reservation!("A", Object.new) }
    assert_raises(ArgumentError) { ledger.release_capacity!("A", Object.new) }
    assert_raises(ArgumentError) { ledger.restore_throughput!("A", "not-time") }
    assert_raises(ArgumentError) do
      ledger.restore_throughput!("A", Time.at(1), consumed_monotonic_at: 0.5)
    end
  end

  def test_capacity_release_underflow_does_not_mutate_usage
    ledger = RubyRouting::State::AdmissionLedger.new(clock: TestSupport::ControlledClock.new)
    reserved = RubyRouting::Money.new(100, "RUB")
    capacity = RubyRouting::CapacityBudget.new(max_slots: 2, max_amount_minor: 200, currency: "RUB")

    ledger.restore_capacity_reservation!("A", reserved)

    assert_raises(ArgumentError) do
      ledger.release_capacity!("A", RubyRouting::Money.new(1, "USD"))
    end
    assert_equal 1, ledger.capacity_snapshot("A", budget: capacity).used_slots
    assert_equal 100, ledger.capacity_snapshot("A", budget: capacity).used_amount_minor

    assert_raises(ArgumentError) do
      ledger.release_capacity!("A", RubyRouting::Money.new(101, "RUB"))
    end
    assert_equal 1, ledger.capacity_snapshot("A", budget: capacity).used_slots
    assert_equal 100, ledger.capacity_snapshot("A", budget: capacity).used_amount_minor

    ledger.release_capacity!("A", reserved)
    snapshot = ledger.capacity_snapshot("A", budget: capacity)
    assert_equal 0, snapshot.used_slots
    assert_equal 0, snapshot.used_amount_minor

    assert_raises(ArgumentError) { ledger.release_capacity!("A", reserved) }
    assert_equal 0, ledger.capacity_snapshot("A", budget: capacity).used_slots
    assert_equal 0, ledger.capacity_snapshot("A", budget: capacity).used_amount_minor
  end

  def test_capacity_trace_rejects_inexact_supplied_monotonic_time
    clock = TestSupport::ControlledClock.new
    ledger = RubyRouting::State::AdmissionLedger.new(clock: clock)
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)
    )

    assert_raises(ArgumentError) do
      ledger.capacity_trace(opportunity, as_of: clock.now, as_of_monotonic: 0.5)
    end
  end

  def test_admission_clock_must_return_time_values
    clock = Object.new
    clock.define_singleton_method(:now) { "not-time" }
    ledger = RubyRouting::State::AdmissionLedger.new(clock: clock)
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)
    )

    assert_raises(ArgumentError) { ledger.reserve_throughput!(opportunity) }
  end

  def test_admission_clock_must_provide_monotonic_elapsed_measurement
    clock = Object.new
    clock.define_singleton_method(:now) { Time.utc(2026, 1, 1) }
    ledger = RubyRouting::State::AdmissionLedger.new(clock: clock)
    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)
    )

    assert_raises(ArgumentError) { ledger.reserve_throughput!(opportunity) }
  end
end
