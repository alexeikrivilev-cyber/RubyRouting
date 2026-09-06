# frozen_string_literal: true

require_relative "../test_helper"

class ReplayTest < Minitest::Test
  def test_admission_replay_merges_padded_and_canonical_provider_facts
    facts = [
      fact(1, :provider_opportunity_registered, payload: {
        provider_id: " A ",
        capacity: { max_slots: 2 },
        throughput: { max_operations: 2, window_seconds: 60 }
      }),
      fact(2, :capacity_reserved, payload: {
        provider_id: "A", amount: RubyRouting::Money.new(1, "RUB")
      }),
      fact(3, :throughput_consumed, payload: {
        provider_id: " A ", consumed_at: Time.at(1)
      })
    ]

    capacity = RubyRouting::Projections::Replay.capacity(facts).snapshot(" A ")
    throughput = RubyRouting::Projections::Replay.throughput(facts).snapshot("A")

    assert_equal "A", capacity.provider_id
    assert_equal 1, capacity.used_slots
    assert_equal 1, throughput.consumed_count
    assert_equal "A", throughput.provider_id
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.capacity(facts).snapshot(1) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.throughput(facts).snapshot(1) }
  end

  def test_allocation_replay_merges_padded_and_canonical_provider_facts
    key = ["policy", "1", "default", ["A"]]
    facts = [
      fact(1, :allocation_committed, payload: {
        provider_id: " A ", role: :primary, allocation_key: key,
        measure: 1
      }),
      fact(2, :allocation_committed, payload: {
        provider_id: "A", role: :primary, allocation_key: key,
        measure: 1
      })
    ]

    snapshot = RubyRouting::Projections::Replay.allocation(facts).snapshot(
      [" policy ", " 1 ", " default ", [" A "]]
    )

    assert_equal({ "A" => 2 }, snapshot.measures)
    assert_equal 2, snapshot.revision
  end

  def test_legacy_allocation_policy_scope_accepts_each_only_collection
    facts = [
      fact(1, :allocation_committed, payload: {
        provider_id: " A ", role: :primary,
        policy_scope: TestSupport::EachOnlyCollection.new([" policy ", " 1 ", " default "]),
        measure: 1
      })
    ]

    snapshot = RubyRouting::Projections::Replay.allocation(facts).snapshot(
      ["policy", "1", "default"]
    )

    assert_equal({ "A" => 1 }, snapshot.measures)
    assert_equal 1, snapshot.revision
  end

  def test_legacy_allocation_policy_scope_rejects_scalar_collection
    facts = [
      fact(1, :allocation_committed, payload: {
        provider_id: "A", role: :primary, policy_scope: "default", measure: 1
      })
    ]

    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.allocation(facts) }
  end

  def test_replay_rejects_non_symbol_like_identity_payloads
    capacity_facts = [
      fact(1, :provider_opportunity_registered, payload: { provider_id: 1 })
    ]
    allocation_facts = [
      fact(1, :allocation_committed, payload: {
        provider_id: "A", role: :primary, allocation_key: [1], measure: 1
      })
    ]

    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.capacity(capacity_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.allocation(allocation_facts) }
    malformed_policy = Struct.new(:allocation_key).new([1])
    assert_raises(ArgumentError) do
      RubyRouting::Projections::Replay.allocation(allocation_facts).snapshot(malformed_policy)
    end
  end

  def test_health_and_quality_replay_reject_non_symbol_like_fact_identities
    health_facts = [
      fact(1, :health_signal, payload: {
        provider_id: 1, signal: :operational_failure, attribution: :provider
      })
    ]
    quality_provider_facts = [
      fact(1, :quality_signal, payload: {
        provider_id: 1, context_key: [], status: :success,
        attribution: :provider, safe_to_release: true
      })
    ]
    quality_context_facts = [
      fact(1, :quality_signal, payload: {
        provider_id: "A", context_key: [1], status: :success,
        attribution: :provider, safe_to_release: true
      })
    ]
    exposure_facts = [
      fact(1, :health_exposure_reserved, payload: {
        provider_id: "A", operation_id: 1
      })
    ]
    orphan_release_facts = [
      fact(1, :health_exposure_released, payload: {
        provider_id: "A", operation_id: 1
      })
    ]

    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.health(health_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.quality(quality_provider_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.quality(quality_context_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.health(exposure_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.health(orphan_release_facts) }
  end

  def test_lifecycle_replay_rejects_non_symbol_like_fact_identities
    ownership_facts = [
      fact(1, :ownership_acquired, payload: {
        provider_id: 1, operation_id: "op", attempt_id: "att"
      })
    ]
    conflict_facts = [
      fact(1, :economic_conflict, payload: {
        provider_id: 1, operation_id: "op", attempt_id: "att", reason: :late_success
      })
    ]
    reversal_facts = [
      fact(1, :reversal_recorded, payload: {
        reversal_id: 1, provider_id: "A", operation_id: "op",
        amount: RubyRouting::Money.new(1, "RUB"), reason: :returned
      })
    ]
    contract_facts = [
      fact(1, :decision_committed, payload: {
        action: :assign, provider_id: "A", operation_id: "op", attempt_id: "att",
        role: :primary,
        contract: {
          provider_id: 1, idempotent_retry: true, status_lookup: false,
          idempotency_key: "p:op", version: "1"
        }
      })
    ]
    observation_facts = [
      fact(1, :provider_observed, payload: {
        observation_id: 1, provider_id: "A", operation_id: "op", attempt_id: "att",
        applied: false
      })
    ]
    attempt_started_facts = [
      fact(1, :attempt_started, payload: {
        provider_id: 1, operation_id: "op", attempt_id: "att", action: :assign
      })
    ]
    resolution_facts = [
      fact(1, :decision_committed, payload: {
        action: :resolve, provider_id: 1, operation_id: "op", attempt_id: "att",
        role: :resolution
      })
    ]
    release_facts = [
      fact(1, :ownership_released, payload: {
        provider_id: 1, operation_id: "op", attempt_id: "att"
      })
    ]

    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.lifecycle(ownership_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.lifecycle(conflict_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.lifecycle(reversal_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.lifecycle(contract_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.lifecycle(observation_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.lifecycle(attempt_started_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.lifecycle(resolution_facts) }
    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.lifecycle(release_facts) }
  end

  def test_lifecycle_replay_rejects_a_schedule_on_an_unapplied_observation
    facts = [
      fact(1, :provider_observed, payload: {
        observation_id: "obs", provider_id: "A", operation_id: "op", attempt_id: "att",
        applied: false, recovery_schedule: recovery_schedule_payload
      })
    ]

    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.lifecycle(facts) }
  end

  def test_lifecycle_replay_rejects_a_schedule_that_is_not_linked_to_current_ownership
    facts = [
      fact(1, :intent_registered, payload: {
        money: RubyRouting::Money.new(1, "RUB"), recipient: {}, context: {}, created_at: Time.at(1)
      }),
      fact(2, :decision_committed, payload: {
        action: :assign, provider_id: "A", operation_id: "op", attempt_id: "att", role: :primary,
        contract: {
          provider_id: "A", idempotent_retry: false, status_lookup: true,
          idempotency_key: "p:op", version: "1"
        }
      }),
      fact(3, :ownership_acquired, payload: {
        provider_id: "A", operation_id: "op", attempt_id: "att"
      }),
      fact(4, :provider_observed, payload: {
        observation_id: "obs", provider_id: "A", operation_id: "op", attempt_id: "att",
        applied: true, status: :unknown, attribution: :provider, safe_to_release: false,
        recovery_schedule: recovery_schedule_payload(provider_id: "B")
      })
    ]

    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.lifecycle(facts) }
  end

  def test_analytics_rejects_non_symbol_like_provider_identity_payloads
    facts = [
      fact(1, :opportunity_evaluated, payload: {
        opportunities: [1],
        functional_provider_ids: [],
        exclusion_codes: {},
        allocation_exclusions: {}
      })
    ]

    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.analytics(facts) }
  end

  def test_lifecycle_replay_uses_one_canonical_operation_and_provider_identity
    facts = [
      fact(1, :intent_registered, payload: {
        money: RubyRouting::Money.new(1, "RUB"), recipient: {}, context: {}, created_at: Time.at(1)
      }),
      fact(2, :policy_registered, payload: {
        policy_id: "policy", policy_epoch: "1", policy_scope: "default", policy_fingerprint: "fp"
      }),
      fact(3, :decision_committed, payload: {
        action: :assign, provider_id: " A ", operation_id: " op ", attempt_id: " att ", role: :primary,
        policy_epoch: "1"
      }),
      fact(4, :allocation_committed, payload: {
        provider_id: "A", operation_id: "op", attempt_id: "att", role: :primary, measure: 1
      }),
      fact(5, :ownership_acquired, payload: {
        provider_id: " A ", operation_id: "op", attempt_id: "att"
      })
    ]

    payout = RubyRouting::Projections::Replay.lifecycle(facts).payout(" p ")

    assert_equal :pending, payout.status
    assert_equal ["A", "op", "att"], [
      payout.ownership.provider_id,
      payout.ownership.operation_id,
      payout.ownership.attempt_id
    ]
    attempt_ids = payout.attempts.map do |attempt|
      [attempt.provider_id, attempt.operation_id, attempt.attempt_id]
    end
    assert_equal [["A", "op", "att"]], attempt_ids
    assert_equal "A", payout.primary_provider_id
  end

  def test_analytics_merges_padded_provider_and_operation_id_metrics
    facts = [
      fact(1, :opportunity_evaluated, payload: {
        opportunities: [" A ", "A"],
        functional_provider_ids: [" A "],
        exclusion_codes: { " A " => :capacity_exhausted },
        allocation_exclusions: {}
      }),
      fact(2, :decision_committed, payload: {
        action: :assign, operation_id: " op ", role: :primary
      }),
      fact(3, :allocation_committed, payload: {
        provider_id: " A ", operation_id: "op", role: :primary, measure: 1,
        measure_kind: :count, currency: nil,
        allocation_key: ["policy", "1", "default", ["A"]]
      }),
      fact(4, :attempt_started, payload: {
        provider_id: "A", operation_id: " op ", started_at: Time.at(1)
      }),
      fact(5, :provider_observed, payload: {
        observation_id: "obs", provider_id: " A ", operation_id: "op", applied: true,
        status: :success, attribution: :provider, safe_to_release: true
      }),
      fact(6, :settlement_recorded, payload: {
        provider_id: " A ", operation_id: " op ", measure: 1,
        measure_kind: :count, currency: nil,
        allocation_key: ["policy", "1", "default", ["A"]]
      })
    ]

    analytics = RubyRouting::Projections::Replay.analytics(facts)

    assert_equal({ "A" => 2 }, analytics.opportunity_count_by_provider)
    assert_equal({ "A" => 1 }, analytics.functional_provider_count_by_provider)
    assert_equal({ "A" => 1 }, analytics.assignment_measure_by_provider)
    assert_equal({ "A" => 1 }, analytics.attempt_count_by_provider)
    assert_equal({ "A" => 1 }, analytics.settlement_measure_by_provider)
    assert_equal({ "A" => 1 }, analytics.capacity_exclusion_count_by_provider)
    assert_equal 1, analytics.first_attempt_success_count
    assert_equal 1, analytics.eventual_success_count
  end

  def test_analytics_consumes_each_only_fact_collections
    fact_view = Struct.new(:sequence, :type, :payout_id, :payload)
    facts = [
      fact_view.new(1, :opportunity_evaluated, "each-only-analytics", {
        opportunities: TestSupport::EachOnlyCollection.new([" A ", "B"]),
        functional_provider_ids: TestSupport::EachOnlyCollection.new([" A "]),
        exclusion_codes: {},
        allocation_exclusions: {}
      }),
      fact_view.new(2, :decision_committed, "each-only-analytics", {
        action: :defer,
        reason_codes: TestSupport::EachOnlyCollection.new([:no_safe_route])
      })
    ]

    analytics = RubyRouting::Projections::Replay.analytics(facts)

    assert_equal({ "A" => 1, "B" => 1 }, analytics.opportunity_count_by_provider)
    assert_equal({ "A" => 1 }, analytics.functional_provider_count_by_provider)
    assert_equal 1, analytics.no_safe_route_count
  end

  def test_analytics_rejects_non_enumerable_fact_collections
    facts = [
      fact(1, :opportunity_evaluated, payload: {
        opportunities: "A",
        functional_provider_ids: [],
        exclusion_codes: {},
        allocation_exclusions: {}
      })
    ]

    assert_raises(ArgumentError) { RubyRouting::Projections::Replay.analytics(facts) }
  end

  private

  def fact(sequence, type, payout_id: "p", payload:)
    RubyRouting::Fact.new(
      sequence: sequence,
      type: type,
      fact_id: "fact-#{sequence}",
      payout_id: payout_id,
      payload: payload
    )
  end

  def recovery_schedule_payload(provider_id: "A")
    {
      action: :resolve,
      provider_id: provider_id,
      operation_id: "op",
      attempt_id: "att",
      scheduled_at: Time.at(10),
      scheduled_monotonic_at: 10,
      next_action_at: Time.at(10),
      next_action_monotonic_at: 10,
      delay_seconds: 0,
      interaction_index: 0,
      reason_code: :unresolved_provider_outcome
    }
  end
end
