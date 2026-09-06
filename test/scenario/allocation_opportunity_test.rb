# frozen_string_literal: true

require_relative "../test_helper"

class AllocationOpportunityTest < Minitest::Test
  def test_provider_absent_from_opportunity_cohort_does_not_create_catch_up_debt
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("B")])
    policy = RubyRouting::RoutingPolicy.new(
      id: "skewed-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 9 }
    )

    2.times do |index|
      payout = intent("ineligible-#{index}")
      commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      assert_equal "B", commit.proposal.provider_id
      coordinator.mark_attempt_started(commit)
      coordinator.apply_observation(observation(commit, index))
    end

    coordinator.replace_provider_opportunities([opportunity("A"), opportunity("B")])
    next_commit = coordinator.prepare_and_commit_decision(intent: intent("eligible-again"), policy: policy)

    assert_equal "B", next_commit.proposal.provider_id
    assert_equal ["A", "B"], coordinator.provider_opportunities.map(&:provider_id)
  end

  def test_recovered_provider_does_not_receive_unlimited_historical_catch_up_traffic
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("B")])
    policy = RubyRouting::RoutingPolicy.new(
      id: "recovery-pressure-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 9 }
    )

    2.times do |index|
      payout = intent("historical-#{index}")
      commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      coordinator.mark_attempt_started(commit)
      coordinator.apply_observation(observation(commit, index))
    end

    coordinator.replace_provider_opportunities([opportunity("A"), opportunity("B")])
    3.times do |index|
      payout = intent("recovered-#{index}")
      commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

      assert_equal "B", commit.proposal.provider_id
      coordinator.mark_attempt_started(commit)
      coordinator.apply_observation(observation(commit, index + 2))
    end

    assert_equal({ "B" => 3 }, coordinator.allocation_snapshot(policy: policy).measures)
  end

  def test_no_safe_route_is_visible_when_all_opportunities_are_unavailable
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A", available: false),
        RubyRouting::ProviderOpportunity.new(provider_id: "B", capacity_available: false)
      ]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "outage-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )

    commit = coordinator.prepare_and_commit_decision(intent: intent("runtime-infeasible"), policy: policy)

    assert_equal :defer, commit.proposal.action
    assert_includes commit.proposal.reasons, "no safe feasible provider"
    assert_includes commit.proposal.reason_codes, :runtime_policy_infeasible
    assert_equal [:operational_infeasibility],
      commit.proposal.runtime_feasibility.reason_codes
    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    assert_equal :infeasible, evaluation.payload.fetch(:runtime_feasibility).fetch(:status)
    assert_equal :deferred, commit.payout.status
    assert_empty coordinator.payout_snapshot("runtime-infeasible").attempts
    restored = RubyRouting::State::Coordinator.from_facts(
      facts: coordinator.facts,
      opportunities: [
        RubyRouting::ProviderOpportunity.new(provider_id: "A", available: false),
        RubyRouting::ProviderOpportunity.new(provider_id: "B", capacity_available: false)
      ]
    )
    assert_equal :deferred, restored.payout_snapshot("runtime-infeasible").status
    assert_equal({ count: 1, measure: 1 }, analytics.deviation_by_cause.fetch(:availability))
    assert_equal({ count: 1, measure: 1 }, analytics.deviation_by_recoverability.fetch(:recoverable))
    assert_equal 1, analytics.deferred_count
    assert_equal analytics.to_h, RubyRouting::Projections::Replay.analytics(coordinator.facts).to_h
  end

  def test_deferred_no_route_can_be_reconsidered_after_provider_recovery
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A", available: false)]
    )
    payout = intent("deferred-retry")
    policy = policy(epoch: "deferred-retry")

    deferred = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assert_equal :defer, deferred.proposal.action
    assert_equal :deferred, deferred.payout.status

    coordinator.replace_provider_opportunities([opportunity("A")])
    reassigned = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

    assert_equal :assign, reassigned.proposal.action
    assert_equal :pending, reassigned.payout.status
    assert_equal :pending, coordinator.lifecycle_projection.payout(payout.id).status
  end

  def test_available_provider_filter_accepts_each_only_collection
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A")])
    commit = coordinator.prepare_and_commit_decision(
      intent: intent("each-only-provider-filter"),
      policy: policy(epoch: "1"),
      available_provider_ids: TestSupport::EachOnlyCollection.new(["A"])
    )

    assert commit.proposal.assignment?
    assert_equal "A", commit.proposal.provider_id
  end

  def test_missing_adapter_is_operational_exclusion_not_functional_cohort_loss
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [opportunity("A"), opportunity("B")]
    )
    policy = policy(epoch: "adapter-cohort")

    commit = coordinator.prepare_and_commit_decision(
      intent: intent("missing-adapter-cohort"),
      policy: policy,
      available_provider_ids: ["A"]
    )
    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }

    assert_equal :assign, commit.proposal.action
    assert_equal ["A", "B"], evaluation.payload.fetch(:opportunities)
    assert_equal ["A", "B"], evaluation.payload.fetch(:functional_provider_ids)
    assert_equal ["A"], evaluation.payload.fetch(:feasible_provider_ids)
    assert_equal ["A", "B"], evaluation.payload.fetch(:allocation_key).fetch(3)
    assert_equal :unavailable, evaluation.payload.fetch(:exclusion_codes).fetch("B")
  end

  def test_policy_measure_limit_is_a_typed_allocation_exclusion
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A")])
    policy = RubyRouting::RoutingPolicy.new(
      id: "measure-limit-policy",
      epoch: "1",
      measure: :volume,
      targets: { "A" => 1 },
      currency: "RUB",
      minimum_measures: { "A" => 200 }
    )
    payout = RubyRouting::PayoutIntent.new(
      id: "measure-limit-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )

    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    evaluation = coordinator.facts.find { |fact| fact.type == :opportunity_evaluated }
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)

    assert_equal :defer, commit.proposal.action
    assert_includes commit.proposal.reason_codes, :policy_measure_constraint
    assert_includes commit.proposal.reason_codes, :runtime_policy_infeasible
    assert_equal [:policy_measure_infeasibility],
      commit.proposal.runtime_feasibility.reason_codes
    assert_equal({ "A" => :policy_measure_constraint }, evaluation.payload.fetch(:allocation_exclusions))
    assert_equal 1, analytics.exclusion_count_by_code.fetch(:policy_measure_constraint)
  end

  def test_share_corridor_deviation_is_typed_in_decision_fact_and_analytics
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [opportunity("A"), opportunity("B")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "share-corridor",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      maximum_shares: { "A" => "1/2", "B" => "1/2" }
    )

    commit = coordinator.prepare_and_commit_decision(intent: intent("share-corridor"), policy: policy)
    decision_fact = coordinator.facts.find do |fact|
      fact.type == :decision_committed && fact.payload[:operation_id] == commit.proposal.operation_id
    end
    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)

    assert_equal :assign, commit.proposal.action
    assert_includes commit.proposal.reason_codes, :allocation_share_corridor_exceeded
    assert_equal :allocation_share_constraint, commit.proposal.allocation_decision.deviation_cause
    assert_equal :recoverable, commit.proposal.allocation_decision.deviation_recoverability
    assert_equal({ "A" => { maximum: Rational(1, 2) } },
      decision_fact.payload.fetch(:allocation_share_violations))
    assert_equal :recoverable, decision_fact.payload.fetch(:allocation_deviation_recoverability)
    trace = decision_fact.payload.fetch(:optimization_trace)
    assert_equal true, trace.fetch(commit.proposal.provider_id).fetch(:selected)
    assert_equal true, trace.fetch(commit.proposal.provider_id).fetch(:allocation_admissible)
    assert_equal 1, analytics.deviation_by_cause.fetch(:allocation_share_constraint).fetch(:count)
    assert_equal 1, analytics.deviation_by_recoverability.fetch(:recoverable).fetch(:count)
  end

  def test_policy_epoch_has_an_independent_allocation_projection
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A"), opportunity("B")])
    first_policy = policy(epoch: "1")
    second_policy = policy(epoch: "2")

    first = coordinator.prepare_and_commit_decision(intent: intent("epoch-1"), policy: first_policy)
    second = coordinator.prepare_and_commit_decision(intent: intent("epoch-2"), policy: second_policy)

    assert_equal "A", first.proposal.provider_id
    assert_equal "A", second.proposal.provider_id
    assert_equal({ "A" => 1 }, coordinator.allocation_snapshot(policy: first_policy).measures)
    assert_equal({ "A" => 1 }, coordinator.allocation_snapshot(policy: second_policy).measures)
    epochs = coordinator.facts.select { |fact| fact.type == :allocation_committed }.map { |fact| fact.payload[:policy_epoch] }
    assert_equal %w[1 2], epochs
  end

  def test_opportunity_cohort_window_keeps_distinct_functional_cohorts
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [
        opportunity("A"),
        RubyRouting::ProviderOpportunity.new(
          provider_id: "B",
          required_context_labels: ["wholesale"]
        )
      ]
    )
    policy = policy(epoch: "cohort")

    first = coordinator.prepare_and_commit_decision(
      intent: intent("cohort-only-a", context: { labels: ["retail"] }),
      policy: policy
    )
    second = coordinator.prepare_and_commit_decision(
      intent: intent("cohort-a-b-1", context: { labels: ["wholesale"] }),
      policy: policy
    )
    third = coordinator.prepare_and_commit_decision(
      intent: intent("cohort-a-b-2", context: { labels: ["wholesale"] }),
      policy: policy
    )

    assert_equal "A", first.proposal.provider_id
    assert_equal "A", second.proposal.provider_id
    assert_equal "B", third.proposal.provider_id
    allocation_facts = coordinator.facts.select { |fact| fact.type == :allocation_committed }
    keys = allocation_facts.map { |fact| fact.payload.fetch(:allocation_key) }
    assert_equal [
      ["epoch-policy", "cohort", "default", ["A"]],
      ["epoch-policy", "cohort", "default", ["A", "B"]],
      ["epoch-policy", "cohort", "default", ["A", "B"]]
    ], keys

    assert_equal({ "A" => 1, "B" => 1 }, coordinator.allocation_snapshot(policy: policy).measures)
    assert_equal coordinator.allocation_snapshot(policy: policy).measures,
      coordinator.allocation_projection.snapshot(policy).measures

    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    # Provider-only convenience totals intentionally omit A because its two
    # values belong to distinct opportunity cohorts. The dimensioned view is
    # the canonical metric surface.
    assert_equal({ "B" => Rational(1, 1) },
      analytics.primary_target_measure_by_provider)
    assert_equal({ "B" => Rational(0, 1) },
      analytics.primary_deviation_measure_by_provider)
    assert_equal 3, analytics.primary_target_measure_by_dimension.length
    assert_equal 3, analytics.primary_deviation_measure_by_dimension.length
  end

  def test_same_policy_identity_cannot_be_reused_with_changed_definition
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A")])
    first_policy = RubyRouting::RoutingPolicy.new(
      id: "immutable-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    changed_policy = RubyRouting::RoutingPolicy.new(
      id: "immutable-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 2 }
    )

    coordinator.prepare_and_commit_decision(intent: intent("policy-one"), policy: first_policy)

    assert_raises(ArgumentError) do
      coordinator.prepare_and_commit_decision(intent: intent("policy-two"), policy: changed_policy)
    end
  end

  def test_unresolved_payout_cannot_silently_switch_policy_identity
    coordinator = RubyRouting::State::Coordinator.new(opportunities: [opportunity("A")])
    first_policy = policy(epoch: "1")
    changed_epoch = policy(epoch: "2")
    payout = intent("pinned-policy")

    coordinator.prepare_and_commit_decision(intent: payout, policy: first_policy)

    assert_raises(ArgumentError) do
      coordinator.prepare_and_commit_decision(intent: payout, policy: changed_epoch)
    end
  end

  def test_fallback_recomputes_against_current_provider_availability
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [opportunity("A"), opportunity("B"), opportunity("C")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "fallback-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1, "B" => 1, "C" => 1 }
    )
    payout = intent("fresh-fallback")
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    first_token = coordinator.mark_attempt_started(first)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "fallback-safe-failure",
        payout_id: payout.id,
        provider_id: first.proposal.provider_id,
        operation_id: first.proposal.operation_id,
        attempt_id: first.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      ),
      interaction_token: first_token
    )
    coordinator.set_provider_availability("A", available: false)
    coordinator.set_provider_availability("B", available: false)

    second = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

    assert_equal "C", second.proposal.provider_id
  end

  def test_skewed_fallback_excludes_provider_used_by_previous_money_moving_operation
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [opportunity("A"), opportunity("B")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "skewed-fallback-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 9, "B" => 1 }
    )
    payout = intent("exclude-used-provider")
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    assert_equal "A", first.proposal.provider_id
    first_token = coordinator.mark_attempt_started(first)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "exclude-used-provider-failure",
        payout_id: payout.id,
        provider_id: first.proposal.provider_id,
        operation_id: first.proposal.operation_id,
        attempt_id: first.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      ),
      interaction_token: first_token
    )

    second = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)

    assert_equal "B", second.proposal.provider_id
    assert_equal :recovery, second.proposal.role
  end

  private

  def opportunity(id)
    RubyRouting::ProviderOpportunity.new(provider_id: id)
  end

  def policy(epoch:)
    RubyRouting::RoutingPolicy.new(
      id: "epoch-policy",
      epoch: epoch,
      measure: :count,
      targets: { "A" => 1, "B" => 1 }
    )
  end

  def intent(id, context: {})
    RubyRouting::PayoutIntent.new(
      id: id,
      money: RubyRouting::Money.new(100, "RUB"),
      context: context
    )
  end

  def observation(commit, index)
    RubyRouting::ProviderObservation.new(
      observation_id: "opportunity-observation-#{index}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
    )
  end
end
