# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "stringio"

class OutcomeAnalyticsTest < Minitest::Test
  def test_mixed_case_exposes_typed_provider_and_fallback_outcome_counts
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities("A", "B"))
    count_policy = policy("count-outcome", measure: :count, targets: { "A" => 1, "B" => 1 })
    usd_policy = policy("usd-outcome", measure: :volume, currency: "USD", targets: { "A" => 1, "B" => 1 })

    primary = commit(coordinator, "fallback-outcome", 100, "RUB", count_policy)
    coordinator.mark_attempt_started(primary)
    coordinator.apply_observation(
      observation(primary, "fallback-safe-failure", :safe_route_failure, :provider)
    )
    fallback = coordinator.prepare_and_commit_decision(
      intent: intent("fallback-outcome", 100, "RUB"),
      policy: count_policy
    )
    coordinator.mark_attempt_started(fallback)
    coordinator.apply_observation(observation(fallback, "fallback-success", :success, :provider))
    coordinator.apply_observation(
      observation(primary, "late-primary-success", :success, :provider)
    )

    settled = commit(coordinator, "usd-first-success", 10_000, "USD", usd_policy)
    coordinator.mark_attempt_started(settled)
    coordinator.apply_observation(observation(settled, "usd-success", :success, :provider))
    coordinator.record_reversal(
      payout_id: "usd-first-success",
      reversal_id: "usd-reversal",
      provider_id: settled.proposal.provider_id,
      operation_id: settled.proposal.operation_id,
      amount: RubyRouting::Money.new(10_000, "USD")
    )

    unknown_policy = policy("unknown-outcome", measure: :count, targets: { "A" => 1 })
    unknown = commit(coordinator, "unknown-outcome", 1, "RUB", unknown_policy)
    coordinator.mark_attempt_started(unknown)
    coordinator.apply_observation(observation(unknown, "unknown-outcome", :unknown, :provider))

    terminal_policy = policy("terminal-outcome", measure: :count, targets: { "A" => 1 })
    terminal = commit(coordinator, "terminal-outcome", 1, "RUB", terminal_policy)
    coordinator.mark_attempt_started(terminal)
    coordinator.apply_observation(observation(terminal, "recipient-terminal", :terminal_payout_failure, :recipient))

    analytics = RubyRouting::Projections::Replay.analytics(coordinator.facts)
    replay = RubyRouting::Projections::Replay.analytics(coordinator.facts)

    failure = analytics.query(
      metric: :provider_failure_count,
      filters: { policy_id: "count-outcome", currency: "rub", role: :primary, attribution: :provider },
      group_by: [:provider_id]
    )
    assert_equal :provider_attributed_attempts, failure.population
    assert_equal [{ group: { provider_id: "A" }, value: 1 }], failure.to_h.fetch(:rows)

    fallback_success = analytics.query(
      metric: :successful_fallback_recovery_count,
      filters: { policy_id: "count-outcome", currency: "RUB", role: :recovery },
      group_by: [:provider_id]
    )
    assert_equal :payouts, fallback_success.population
    assert_equal [{ group: { provider_id: "B" }, value: 1 }], fallback_success.to_h.fetch(:rows)

    eventual = analytics.query(
      metric: :eventual_settlement_count,
      filters: { policy_id: "count-outcome", currency: "RUB" },
      group_by: [:provider_id]
    )
    assert_equal [{ group: { provider_id: "B" }, value: 1 }], eventual.to_h.fetch(:rows)

    first_success = analytics.query(
      metric: :first_attempt_success_count,
      filters: { policy_id: "usd-outcome", currency: "USD", role: :primary },
      group_by: [:provider_id]
    )
    assert_equal [{ group: { provider_id: "A" }, value: 1 }], first_success.to_h.fetch(:rows)

    unresolved = analytics.query(
      metric: :unresolved_count,
      filters: { policy_id: "unknown-outcome", currency: "RUB" },
      group_by: [:provider_id]
    )
    assert_equal [{ group: { provider_id: "A" }, value: 1 }], unresolved.to_h.fetch(:rows)

    terminal_failure = analytics.query(
      metric: :terminal_failure_count,
      filters: { policy_id: "terminal-outcome", currency: "RUB", attribution: :recipient },
      group_by: [:provider_id]
    )
    assert_equal [{ group: { provider_id: "A" }, value: 1 }], terminal_failure.to_h.fetch(:rows)

    assert_equal 2, analytics.eventual_success_count
    assert_equal 1, analytics.successful_fallback_recovery_count
    assert_equal 1, analytics.reversal_count
    assert_equal analytics.to_h, replay.to_h
    assert_equal 7, analytics.outcome_count_by_dimension.values.sum

    assert_raises(ArgumentError) do
      analytics.query(metric: :eventual_settlement_count, group_by: [:provider_id])
    end
  end

  def test_exact_duplicate_observation_does_not_duplicate_typed_outcome_counts
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    payout = intent("outcome-duplicate", 50, "RUB")
    policy = policy("outcome-duplicate-policy", measure: :count, targets: { "A" => 1 })
    committed = commit(coordinator, payout.id, payout.money.amount_minor, payout.money.currency, policy)
    coordinator.mark_attempt_started(committed)
    coordinator.apply_observation(observation(committed, "outcome-duplicate-success", :success, :provider))

    original = coordinator.facts.find { |fact| fact.type == :provider_observed }
    duplicate = RubyRouting::Fact.new(
      sequence: coordinator.facts.length + 1,
      type: original.type,
      fact_id: "fact:#{coordinator.facts.length + 1}",
      payout_id: original.payout_id,
      payload: original.payload
    )
    analytics = RubyRouting::Projections::Replay.analytics(coordinator.facts)
    duplicated = RubyRouting::Projections::Replay.analytics(coordinator.facts + [duplicate])

    assert_equal analytics.to_h, duplicated.to_h
    assert_equal 1, duplicated.query(
      metric: :first_attempt_success_count,
      filters: { policy_id: policy.id, currency: "RUB" },
      group_by: [:provider_id]
    ).rows.first.value
  end

  def test_http_outcome_query_uses_the_same_canonical_projection
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = policy("http-outcome", measure: :count, targets: { "A" => 1 })
    committed = commit(coordinator, "http-outcome-payout", 10, "RUB", policy)
    coordinator.mark_attempt_started(committed)
    coordinator.apply_observation(observation(committed, "http-outcome-success", :success, :provider))
    provider = Class.new do
      include RubyRouting::Ports::Provider

      def initiate(_request); RubyRouting::ProviderTransportResult.success; end
      def resolve(_request); RubyRouting::ProviderTransportResult.success; end
    end.new
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider }
    )
    response = RubyRouting::Application::HttpApp.new(service: service).call(
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/v1/analytics",
      "QUERY_STRING" => "metric=first_attempt_success_count&policy_id=http-outcome&currency=RUB&group_by=provider_id",
      "rack.input" => StringIO.new("")
    )

    assert_equal 200, response.fetch(0)
    body = JSON.parse(response.fetch(2).join)
    assert_equal "first_attempt_success_count", body.fetch("metric")
    assert_equal "payouts", body.fetch("population")
    assert_equal [{ "group" => { "provider_id" => "A" }, "value" => 1 }], body.fetch("rows")
  end

  private

  def opportunities(*ids)
    ids.map { |id| RubyRouting::ProviderOpportunity.new(provider_id: id) }
  end

  def intent(id, amount, currency)
    RubyRouting::PayoutIntent.new(
      id: id,
      money: RubyRouting::Money.new(amount, currency)
    )
  end

  def policy(id, measure:, targets:, currency: nil)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: measure,
      currency: currency,
      targets: targets
    )
  end

  def commit(coordinator, id, amount, currency, policy)
    coordinator.prepare_and_commit_decision(
      intent: intent(id, amount, currency),
      policy: policy
    )
  end

  def observation(commit, id, status, attribution)
    RubyRouting::ProviderObservation.new(
      observation_id: id,
      payout_id: commit.payout.id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(
        status: status,
        attribution: attribution
      )
    )
  end
end
