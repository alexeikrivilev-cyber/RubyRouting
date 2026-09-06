# frozen_string_literal: true

require_relative "../test_helper"

class DurableFailureInjectionTest < Minitest::Test
  class Journal
    attr_reader :facts

    def initialize
      @facts = []
      @fail_next = false
    end

    def fail_next!
      @fail_next = true
    end

    def append_many(facts)
      if @fail_next
        @fail_next = false
        raise IOError, "injected append failure before durable publish"
      end

      @facts.concat(facts)
    end
  end

  def test_atomic_coordinator_mutation_rolls_back_memory_when_durable_batch_is_rejected
    journal = Journal.new
    coordinator = RubyRouting::State::Coordinator.new(
      journal: journal,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capacity: RubyRouting::CapacityBudget.new(max_slots: 1)
        )
      ]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "durable-failure",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    payout = RubyRouting::PayoutIntent.new(
      id: "durable-failure-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )
    facts_before = coordinator.facts
    journal.fail_next!

    assert_raises(IOError) do
      coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    end

    assert_equal facts_before, coordinator.facts
    assert_equal 0, coordinator.active_unresolved_owners
    assert_equal 0, coordinator.capacity_snapshot("A").used_slots
    assert_raises(KeyError) { coordinator.payout_snapshot(payout.id) }

    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assert_equal :assign, committed.proposal.action
    assert_equal 1, coordinator.active_unresolved_owners
    assert_equal coordinator.facts, journal.facts
  end

  def test_durable_failure_after_prior_history_rebuilds_all_working_projections
    journal = Journal.new
    coordinator = RubyRouting::State::Coordinator.new(
      journal: journal,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(
          provider_id: "A",
          capacity: RubyRouting::CapacityBudget.new(max_slots: 2)
        )
      ]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "durable-rebuild",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    first = RubyRouting::PayoutIntent.new(
      id: "durable-rebuild-1",
      money: RubyRouting::Money.new(100, "RUB")
    )
    second = RubyRouting::PayoutIntent.new(
      id: "durable-rebuild-2",
      money: RubyRouting::Money.new(200, "RUB")
    )
    coordinator.prepare_and_commit_decision(intent: first, policy: policy)
    facts_before = coordinator.facts
    journal.fail_next!

    assert_raises(IOError) do
      coordinator.prepare_and_commit_decision(intent: second, policy: policy)
    end

    assert_equal facts_before, coordinator.facts
    assert_equal :pending, coordinator.payout_snapshot(first.id).status
    assert_raises(KeyError) { coordinator.payout_snapshot(second.id) }
    assert_equal 1, coordinator.capacity_snapshot("A").used_slots
    assert_equal coordinator.capacity_projection.to_h,
      RubyRouting::Projections::Replay.capacity(coordinator.facts).to_h
  end
end
