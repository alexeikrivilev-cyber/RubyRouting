# frozen_string_literal: true

require_relative "../test_helper"

class PayoutFactRestorerTest < Minitest::Test
  Fact = Struct.new(:type, :payout_id, :payload, :sequence)
  State = Struct.new(
    :intent,
    :created_at,
    :created_monotonic_at,
    :policy_scope_key,
    :policy_epoch,
    :policy_fingerprint
  )
  Policy = Struct.new(:scope_key, :fingerprint, :static_feasibility, :to_h, keyword_init: true)

  def setup
    @payouts = {}
    @policies = {}
    @policy = Policy.new(
      scope_key: ["policy", "epoch", "scope"].freeze,
      fingerprint: "fingerprint",
      static_feasibility: { status: :feasible },
      to_h: { id: "policy", epoch: "epoch", scope: "scope" }
    )
    @restorer = RubyRouting::State::PayoutFactRestorer.new(
      payouts: -> { @payouts },
      policies: -> { @policies },
      payout_state_factory: ->(intent) { State.new(intent) },
      payout_state: ->(payout_id) { @payouts.fetch(payout_id) },
      same_intent: ->(left, right) { left.to_h == right.to_h },
      policy_from_definition: ->(_definition) { @policy },
      policy_identity: ->(payload, key) { payload.fetch(key) },
      monotonic_value: ->(payload, key) { payload.fetch(key) },
      monotonic_reference: ->(_time) { Rational(3, 2) }
    )
  end

  def test_restores_intent_with_exact_creation_anchor
    fact = Fact.new(
      :intent_registered,
      "payout",
      {
        money: RubyRouting::Money.new(100, "RUB"),
        recipient: { "bank" => "demo" },
        context: { "segment" => "standard" },
        created_at: Time.utc(2026, 1, 1),
        created_monotonic_at: Rational(7, 2)
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_equal Rational(7, 2), @payouts.fetch("payout").created_monotonic_at
    assert_equal 100, @payouts.fetch("payout").intent.money.amount_minor
  end

  def test_restores_policy_binding_and_definition
    @payouts["payout"] = State.new(
      RubyRouting::PayoutIntent.new(
        id: "payout",
        money: RubyRouting::Money.new(100, "RUB")
      )
    )
    fact = Fact.new(
      :policy_registered,
      "payout",
      {
        policy_id: "policy",
        policy_epoch: "epoch",
        policy_scope: "scope",
        policy_fingerprint: "fingerprint",
        definition: {},
        static_feasibility: { status: :feasible }
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_equal ["policy", "epoch", "scope"], @payouts.fetch("payout").policy_scope_key
    assert_equal @policy, @policies.fetch(["policy", "epoch", "scope"])
  end

  def test_returns_false_for_non_payout_fact
    fact = Fact.new(:decision_committed, "payout", {}, 1)

    assert_equal false, @restorer.apply(fact)
    assert_empty @payouts
  end
end
