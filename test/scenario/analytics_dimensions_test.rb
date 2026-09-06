# frozen_string_literal: true

require_relative "../test_helper"
require "json"

class AnalyticsDimensionsTest < Minitest::Test
  def test_measure_and_currency_dimensions_prevent_ambiguous_provider_totals
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    cases = [
      [count_policy, RubyRouting::Money.new(1_000, "RUB"), :count, nil, 1],
      [volume_policy("rub-policy", "RUB"), RubyRouting::Money.new(10_000, "RUB"), :volume, "RUB", 10_000],
      [volume_policy("usd-policy", "USD"), RubyRouting::Money.new(500, "USD"), :volume, "USD", 500]
    ]

    cases.each_with_index do |(policy, money, _measure, _currency, _expected), index|
      intent = RubyRouting::PayoutIntent.new(id: "dimensioned-#{index}", money: money)
      commit = coordinator.prepare_and_commit_decision(intent: intent, policy: policy)
      coordinator.mark_attempt_started(commit)
      coordinator.apply_observation(
        RubyRouting::ProviderObservation.new(
          observation_id: "dimensioned-success-#{index}",
          payout_id: intent.id,
          provider_id: commit.proposal.provider_id,
          operation_id: commit.proposal.operation_id,
          attempt_id: commit.proposal.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        )
      )
    end

    analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
    replay = RubyRouting::Projections::Replay.analytics(coordinator.facts)

    assert_empty analytics.assignment_measure_by_provider,
      "provider-only measure rollup must not mix count, RUB and USD"
    assert_empty analytics.settlement_measure_by_provider,
      "provider-only settlement rollup must not mix count, RUB and USD"
    assert_equal analytics.to_h, replay.to_h

    assignment_rows = analytics.assignment_measure_by_dimension
    assert_equal 3, assignment_rows.length
    assert_equal [1, 500, 10_000], assignment_rows.values.sort
    assert_equal %i[count volume volume], assignment_rows.keys.map(&:measure).sort_by(&:to_s)
    assert_equal ["RUB", "USD"], assignment_rows.keys.map(&:currency).compact.sort
    assert assignment_rows.keys.all? { |dimension|
      dimension.to_h.keys.sort == %i[cohort currency measure policy_epoch policy_id policy_scope provider_id window].sort
    }

    assert_equal [1, 500, 10_000], analytics.primary_target_measure_by_dimension.values.sort
    assert_equal [0, 0, 0], analytics.primary_deviation_measure_by_dimension.values.sort
    assert_equal [1, 500, 10_000], analytics.settlement_measure_by_dimension.values.sort

    payload = JSON.parse(JSON.generate(analytics.to_h))
    assert_equal 3, payload.fetch("assignment_measure_by_dimension").length
    assert_equal ["RUB", "USD"], payload.fetch("assignment_measure_by_dimension")
      .map { |row| row.fetch("dimension").fetch("currency") }.compact.sort
  end

  def test_application_query_filters_and_groups_only_compatible_dimensioned_measures
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    append_success(coordinator, count_policy, RubyRouting::Money.new(1_000, "RUB"), "query-count")
    append_success(
      coordinator,
      volume_policy("rub-query-policy", "RUB"),
      RubyRouting::Money.new(10_000, "RUB"),
      "query-rub"
    )
    append_success(
      coordinator,
      volume_policy("usd-query-policy", "USD"),
      RubyRouting::Money.new(500, "USD"),
      "query-usd"
    )
    queries = RubyRouting::Application::Queries.new(
      coordinator: coordinator,
      policy_registry: RubyRouting::PolicyRegistry.new
    )

    rub = queries.analytics_query(
      metric: "settlement_measure",
      filters: {
        "policy_id" => "rub-query-policy",
        policy_epoch: "1",
        policy_scope: "default",
        window: "opportunity_cohort",
        cohort: ["A"],
        measure: "volume",
        currency: " rub "
      },
      group_by: ["provider_id"]
    )

    assert_equal :settlement_measure, rub.metric
    assert_equal(
      {
        policy_id: "rub-query-policy",
        policy_epoch: "1",
        policy_scope: "default",
        window: :opportunity_cohort,
        cohort: ["A"],
        measure: :volume,
        currency: "RUB"
      },
      rub.filters
    )
    assert_equal [:provider_id], rub.group_by
    assert_equal [{ group: { provider_id: "A" }, value: 10_000 }], rub.to_h.fetch(:rows)
    assert_predicate rub, :frozen?
    assert_predicate rub.rows, :frozen?

    assert_raises(ArgumentError) do
      queries.analytics_query(
        metric: :settlement_measure,
        filters: { provider_id: "A" },
        group_by: [:policy_id]
      )
    end
    assert_raises(ArgumentError) do
      queries.analytics_query(
        metric: :settlement_measure,
        filters: { measure: :count, currency: "RUB" }
      )
    end
    assert_raises(ArgumentError) do
      queries.analytics_query(metric: :settlement_measure, group_by: [:provider_id, :provider_id])
    end
  end

  private

  def append_success(coordinator, policy, money, payout_id)
    intent = RubyRouting::PayoutIntent.new(id: payout_id, money: money)
    commit = coordinator.prepare_and_commit_decision(intent: intent, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "#{payout_id}-success",
        payout_id: payout_id,
        provider_id: commit.proposal.provider_id,
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )
  end

  def count_policy
    RubyRouting::RoutingPolicy.new(
      id: "count-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
  end

  def volume_policy(id, currency)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :volume,
      targets: { "A" => 1 },
      currency: currency
    )
  end
end
