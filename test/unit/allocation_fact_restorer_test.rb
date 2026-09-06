# frozen_string_literal: true

require_relative "../test_helper"

class AllocationFactRestorerTest < Minitest::Test
  Fact = Struct.new(:type, :payout_id, :payload, :sequence)
  Intent = Struct.new(:money)
  Attempt = Struct.new(:provider_id, :attempt_id, :role, :measure, :phase)
  State = Struct.new(
    :intent,
    :policy_scope_key,
    :operations,
    :allocation_fact_operations,
    :ownership,
    :dispatch_pending,
    :latest_opportunity_evaluation,
    :capacity_reservations
  )

  FakePolicy = Class.new do
    attr_reader :id, :scope, :fingerprint, :epoch

    def initialize
      @id = "policy"
      @scope = "scope"
      @fingerprint = "fingerprint"
      @epoch = "epoch"
    end

    def weight_for(_provider_id)
      1
    end

    def measure_for(_money)
      100
    end
  end

  def setup
    @allocation = RubyRouting::State::AllocationLedger.new
    @policy = FakePolicy.new
    key = ["policy", "epoch", "scope", ["provider"]]
    @state = State.new(
      Intent.new(RubyRouting::Money.new(100, "RUB")),
      ["policy", "epoch", "scope"],
      { "operation" => Attempt.new("provider", "attempt", :primary, 100, :committed) },
      {},
      nil,
      { "operation" => true },
      { allocation_key: key },
      {}
    )
    @restorer = RubyRouting::State::AllocationFactRestorer.new(
      allocation_ledger: -> { @allocation },
      payout_state: ->(_payout_id) { @state },
      policy_for_scope: ->(_scope_key) { @policy },
      policy_identity: ->(payload, key_name) { payload.fetch(key_name) },
      operation_identity: ->(payload, key_name) { payload.fetch(key_name) },
      provider_identity: ->(payload, key_name) { payload.fetch(key_name) },
      enum_value: ->(payload, key_name, _allowed, _label) { payload.fetch(key_name) },
      collection_to_array: ->(value, _label) { value },
      validate_provider_registered_before_fact: ->(_fact, _provider_id) {}
    )
    @fact = Fact.new(
      :allocation_committed,
      "payout",
      {
        policy_id: "policy",
        policy_scope: "scope",
        policy_fingerprint: "fingerprint",
        policy_epoch: "epoch",
        operation_id: "operation",
        attempt_id: "attempt",
        provider_id: "provider",
        role: :primary,
        measure: 100,
        allocation_key: key,
        capacity_reserved: false
      },
      1
    )
  end

  def test_restores_a_primary_allocation_only_after_all_linkage_checks
    assert_equal true, @restorer.apply(@fact)
    assert_equal({ "operation" => true }, @state.allocation_fact_operations)
  end

  def test_returns_false_for_non_allocation_facts_without_mutation
    fact = Fact.new(:capacity_reserved, "payout", {}, 1)

    assert_equal false, @restorer.apply(fact)
    assert_empty @state.allocation_fact_operations
  end
end
