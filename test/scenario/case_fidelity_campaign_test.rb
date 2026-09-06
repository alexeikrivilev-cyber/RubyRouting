# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "stringio"
require "tmpdir"

class CaseFidelityCampaignTest < Minitest::Test
  def test_case_campaign_preserves_count_volume_fallback_unknown_and_restart
    Dir.mktmpdir("ruby-routing-case-campaign") do |directory|
      campaign = run_campaign(File.join(directory, "facts.jsonl"))
      analytics = campaign.fetch(:service).queries.analytics
      restored_service = restored_service_for(campaign)

      count_assignment = measure_by_provider(analytics, campaign.fetch(:count_policy), :primary_assignment)
      volume_assignment = measure_by_provider(analytics, campaign.fetch(:volume_policy), :primary_assignment)
      count_target = measure_by_provider(analytics, campaign.fetch(:count_policy), :primary_target)
      volume_target = measure_by_provider(analytics, campaign.fetch(:volume_policy), :primary_target)
      assert_equal 8, count_assignment.values.sum
      assert_equal 2_000, volume_assignment.values.sum
      assert_equal({ "A" => Rational(4), "B" => Rational(4) }, count_target)
      assert_equal({ "A" => Rational(1_000), "B" => Rational(1_000) }, volume_target)
      assert_equal 8, campaign.fetch(:count_payouts).length
      assert_equal [100, 100, 100, 700, 1000], campaign.fetch(:volume_amounts).sort
      assert_operator volume_assignment.values.max, :>=, 1_000
      assert_operator volume_assignment.values.min, :<=, 1_000
      refute_equal(
        count_assignment.transform_values { |value| Rational(value, 8) },
        volume_assignment.transform_values { |value| Rational(value, 2_000) }
      )

      fallback = analytics.query(
        metric: :successful_fallback_recovery_count,
        filters: { policy_id: campaign.fetch(:recovery_policy).id, currency: "RUB" },
        group_by: %i[provider_id role]
      )
      assert_equal 1, fallback.rows.sum(&:value)
      provider_failures = analytics.query(
        metric: :provider_failure_count,
        filters: { policy_id: campaign.fetch(:recovery_policy).id, currency: "RUB" },
        group_by: %i[provider_id role]
      )
      assert_equal :provider_attributed_attempts, provider_failures.population
      assert_equal 1, provider_failures.rows.sum(&:value)
      eventual = analytics.query(
        metric: :eventual_settlement_count,
        filters: { policy_id: campaign.fetch(:count_policy).id, currency: "RUB" },
        group_by: %i[provider_id role]
      )
      assert_equal 8, eventual.rows.sum(&:value)
      recovery_eventual = analytics.query(
        metric: :eventual_settlement_count,
        filters: { policy_id: campaign.fetch(:recovery_policy).id, currency: "RUB" },
        group_by: %i[provider_id role]
      )
      assert_equal 2, recovery_eventual.rows.sum(&:value)
      unresolved = analytics.query(
        metric: :unresolved_count,
        filters: { policy_id: campaign.fetch(:recovery_policy).id, currency: "RUB" },
        group_by: %i[provider_id role]
      )
      assert_empty unresolved.rows

      assert_equal analytics.to_h, RubyRouting::Projections::Replay.analytics(
        campaign.fetch(:coordinator).facts
      ).to_h
      assert_equal analytics.to_h, restored_service.queries.analytics.to_h
      assert_equal(
        payout_signature(campaign.fetch(:service).queries.payout(campaign.fetch(:unknown_payout).id)),
        payout_signature(restored_service.queries.payout(campaign.fetch(:unknown_payout).id))
      )
    end
  end

  def test_public_surfaces_preserve_every_multi_attempt_history_entry_after_restart
    Dir.mktmpdir("ruby-routing-case-history") do |directory|
      campaign = run_campaign(File.join(directory, "facts.jsonl"))
      restored_service = restored_service_for(campaign)
      app = RubyRouting::Application::HttpApp.new(service: restored_service)
      payout_id = campaign.fetch(:safe_fallback_payout).id

      payout_response = call(app, "GET", "/v1/payouts/#{payout_id}")
      explanation_response = call(app, "GET", "/v1/payouts/#{payout_id}/explanation")
      audit_response = call(
        app,
        "GET",
        "/v1/audit/facts",
        "payout_id=#{URI.encode_www_form_component(payout_id)}"
      )

      assert_equal 200, payout_response.fetch(0)
      payout_payload = parse(payout_response).fetch("payout")
      assert_equal %w[primary recovery], payout_payload.fetch("attempts").map { |attempt| attempt.fetch("role") }
      assert_equal ["A", "B"].sort, payout_payload.fetch("attempts").map { |attempt| attempt.fetch("provider_id") }.sort
      all_attempts_have_valid_outcomes = payout_payload.fetch("attempts").all? do |attempt|
        attempt.fetch("attempt_id").is_a?(String) &&
          attempt.fetch("operation_id").is_a?(String) &&
          %w[success safe_route_failure].include?(attempt.fetch("outcome").fetch("status"))
      end
      assert all_attempts_have_valid_outcomes

      assert_equal 200, explanation_response.fetch(0)
      explanation = parse(explanation_response).fetch("explanation")
      assert_equal payout_id, explanation.fetch("payout_id")
      assert_equal 2, explanation.fetch("decisions").length
      assert_equal "success", explanation.fetch("result").fetch("status")

      assert_equal 200, audit_response.fetch(0)
      audit = parse(audit_response)
      assert_operator audit.fetch("total"), :>=, 10
      fact_types = audit.fetch("facts").map { |fact| fact.fetch("type") }
      assert_includes fact_types, "decision_committed"
      assert_includes fact_types, "provider_observed"
      audit.fetch("facts").each do |fact|
        refute_includes fact.fetch("payload").keys, "recipient"
        refute_includes fact.fetch("payload").keys, "raw"
      end
    end
  end

  private

  def run_campaign(journal_path)
    clock = TestSupport::ControlledClock.new
    count_policy = policy(
      "campaign-count",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(initial_delay_seconds: 5)
    )
    recovery_policy = policy(
      "campaign-recovery",
      measure: :count,
      targets: { "A" => 1, "B" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(initial_delay_seconds: 5)
    )
    volume_policy = policy("campaign-volume", measure: :volume, currency: "RUB", targets: { "A" => 1, "B" => 1 })
    opportunities = %w[A B].map do |provider_id|
      RubyRouting::ProviderOpportunity.new(
        provider_id: provider_id,
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )
    end
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      journal: RubyRouting::State::FileJournal.new(journal_path),
      opportunities: opportunities
    )
    providers = {
      "A" => CampaignProvider.new(provider_id: "A"),
      "B" => CampaignProvider.new(provider_id: "B")
    }
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: providers,
      policy_registry: RubyRouting::PolicyRegistry.new([count_policy, volume_policy, recovery_policy])
    )

    count_payouts = 8.times.map do |index|
      submit(service, "campaign-count-#{index}", 100, count_policy)
    end
    volume_amounts = [100, 100, 100, 700, 1000]
    volume_amounts.each_with_index.map do |amount, index|
      submit(service, "campaign-volume-#{index}", amount, volume_policy)
    end
    safe_fallback_payout = submit(service, "campaign-safe-fallback", 100, recovery_policy)
    unknown_initial = submit(
      service,
      "campaign-unknown",
      100,
      recovery_policy,
      expected_status: :unknown
    )
    assert_equal :unknown, unknown_initial.status, unknown_initial.payout.inspect
    assert_equal 1, unknown_initial.payout.attempts.length
    clock.advance(5)
    resolved_unknown = service.resume(payout_id: unknown_initial.payout.id, policy: recovery_policy)

    assert_equal :success, safe_fallback_payout.status
    assert_equal :success, resolved_unknown.status
    assert_equal 2, safe_fallback_payout.payout.attempts.length
    assert_equal 1, resolved_unknown.payout.attempts.length
    assert_equal 2, resolved_unknown.payout.provider_interaction_count
    assert_nil resolved_unknown.payout.ownership

    {
      service: service,
      coordinator: coordinator,
      count_policy: count_policy,
      volume_policy: volume_policy,
      recovery_policy: recovery_policy,
      count_payouts: count_payouts,
      volume_amounts: volume_amounts,
      safe_fallback_payout: safe_fallback_payout.payout,
      unknown_payout: resolved_unknown.payout,
      providers: providers,
      clock: clock,
      journal_path: journal_path
    }.freeze
  end

  def restored_service_for(campaign)
    restored = RubyRouting::State::Coordinator.new(
      clock: campaign.fetch(:clock),
      journal: RubyRouting::State::FileJournal.new(campaign.fetch(:journal_path))
    )
    RubyRouting::Application::Service.new(
      coordinator: restored,
      providers: {
        "A" => CampaignProvider.new(provider_id: "A"),
        "B" => CampaignProvider.new(provider_id: "B")
      },
      policy_registry: RubyRouting::PolicyRegistry.new([
        campaign.fetch(:count_policy),
        campaign.fetch(:volume_policy),
        campaign.fetch(:recovery_policy)
      ])
    )
  end

  def submit(service, id, amount, policy, expected_status: :success)
    service.submit(
      intent: RubyRouting::PayoutIntent.new(
        id: id,
        money: RubyRouting::Money.new(amount, "RUB")
      ),
      policy: policy
    ).tap do |result|
      assert_equal expected_status, result.status, "#{id} did not reach the expected status"
    end
  end

  def payout_signature(snapshot)
    {
      intent: [snapshot.intent.id, snapshot.intent.money.amount_minor, snapshot.intent.money.currency],
      status: snapshot.status,
      ownership: snapshot.ownership && [
        snapshot.ownership.payout_id,
        snapshot.ownership.provider_id,
        snapshot.ownership.operation_id,
        snapshot.ownership.attempt_id
      ],
      last_outcome: outcome_signature(snapshot.last_outcome),
      attempts: snapshot.attempts.map do |attempt|
        [
          attempt.attempt_id,
          attempt.operation_id,
          attempt.provider_id,
          attempt.role,
          outcome_signature(attempt.outcome),
          attempt.measure,
          attempt.phase,
          attempt.contract&.to_h,
          attempt.last_observation_sequence,
          attempt.committed_at
        ]
      end,
      primary_provider_id: snapshot.primary_provider_id,
      settlement_provider_id: snapshot.settlement_provider_id,
      policy_epoch: snapshot.policy_epoch,
      policy_scope_key: snapshot.policy_scope_key,
      policy_fingerprint: snapshot.policy_fingerprint,
      settlement_operation_id: snapshot.settlement_operation_id,
      provider_interaction_count: snapshot.provider_interaction_count,
      resolution_interaction_count: snapshot.resolution_interaction_count,
      revision: snapshot.revision,
      recovery_schedule: snapshot.recovery_schedule&.to_h
    }
  end

  def outcome_signature(outcome)
    return nil if outcome.nil?

    [
      outcome.status,
      outcome.attribution,
      outcome.provider_reference,
      outcome.message,
      outcome.safe_to_release?
    ]
  end

  def measure_by_provider(analytics, policy, metric)
    source = case metric
    when :primary_assignment
      analytics.primary_assignment_measure_by_dimension
    when :primary_target
      analytics.primary_target_measure_by_dimension
    else
      raise ArgumentError, "unsupported campaign metric"
    end
    source.each_with_object(Hash.new(0)) do |(dimension, value), measures|
      measures[dimension.provider_id] += value if dimension.policy_id == policy.id
    end
  end

  def policy(id, measure:, targets:, currency: nil, recovery: nil)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: measure,
      currency: currency,
      targets: targets,
      recovery: recovery || RubyRouting::RecoveryPolicy.new
    )
  end

  def call(app, method, path, query = "")
    app.call(
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "QUERY_STRING" => query,
      "rack.input" => StringIO.new("")
    )
  end

  def parse(response)
    JSON.parse(response.fetch(2).join)
  end

  class CampaignProvider
    attr_reader :provider_id, :calls

    def initialize(provider_id:)
      @provider_id = provider_id
      @calls = []
    end

    def initiate(request)
      @calls << [:initiate, request.payout_id, request.operation_id]
      outcome = case [request.payout_id, provider_id]
      when ["campaign-safe-fallback", "A"]
        RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
      when ["campaign-unknown", "A"], ["campaign-unknown", "B"]
        RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
      else
        RubyRouting::NormalizedOutcome.success(attribution: :provider)
      end
      observation(request, "initiate", outcome)
    end

    def resolve(request)
      @calls << [:resolve, request.payout_id, request.operation_id]
      observation(request, "resolve", RubyRouting::NormalizedOutcome.success(attribution: :provider))
    end

    private

    def observation(request, source, outcome)
      RubyRouting::ProviderObservation.new(
        observation_id: "campaign-#{source}-#{provider_id}-#{request.operation_id}-#{@calls.length}",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: outcome
      )
    end
  end
end
