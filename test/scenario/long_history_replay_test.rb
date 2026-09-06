# frozen_string_literal: true

require_relative "../test_helper"

class LongHistoryReplayTest < Minitest::Test
  HISTORY_SEED = 20_260_829
  PAYOUT_COUNT = 1_000

  class PeriodicProvider
    attr_reader :provider_id, :calls

    def initialize(provider_id:, safe_failure_every: nil)
      @provider_id = provider_id.freeze
      @safe_failure_every = safe_failure_every
      @calls = []
      @initiation_count = 0
      @sequence = 0
      @operations = {}
    end

    def initiate(request)
      validate_request!(request)
      @calls << [:initiate, request.operation_id].freeze
      operation = @operations[request.idempotency_key]
      unless operation
        @operations[request.idempotency_key] = operation = {
          outcome: next_outcome
        }
      end
      observation_for(request, operation.fetch(:outcome))
    end

    def resolve(request)
      validate_request!(request)
      @calls << [:resolve, request.operation_id].freeze
      operation = @operations.fetch(request.idempotency_key) do
        raise ArgumentError, "cannot resolve unknown operation"
      end
      operation[:outcome] = RubyRouting::NormalizedOutcome.success(attribution: :provider)
      observation_for(request, operation.fetch(:outcome))
    end

    private

    def next_outcome
      @initiation_count += 1
      @safe_failure_every && (@initiation_count % @safe_failure_every).zero? ?
        RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider) :
        RubyRouting::NormalizedOutcome.success(attribution: :provider)
    end

    def observation_for(request, outcome)
      @sequence += 1
      RubyRouting::ProviderObservation.new(
        observation_id: "long-history:#{provider_id}:#{@sequence}",
        payout_id: request.payout_id,
        provider_id: provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: outcome,
        sequence: @sequence
      )
    end

    def validate_request!(request)
      unless request.is_a?(RubyRouting::ProviderOperationRequest) && request.provider_id == provider_id
        raise ArgumentError, "provider operation request does not match #{provider_id}"
      end
    end
  end

  def test_long_seeded_history_preserves_live_replay_and_restart_conservation
    providers = {
      "A" => PeriodicProvider.new(provider_id: "A", safe_failure_every: 5),
      "B" => PeriodicProvider.new(provider_id: "B", safe_failure_every: 7),
      "C" => PeriodicProvider.new(provider_id: "C")
    }
    opportunities = providers.keys.map { |provider_id| RubyRouting::ProviderOpportunity.new(provider_id: provider_id) }
    policy = RubyRouting::RoutingPolicy.new(
      id: "long-history-policy",
      epoch: "#{HISTORY_SEED}",
      measure: :count,
      targets: { "A" => 1, "B" => 1, "C" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 3, max_switches: 2)
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
    app = RubyRouting::Application::Orchestrator.new(coordinator: coordinator, providers: providers)

    PAYOUT_COUNT.times do |index|
      payout = RubyRouting::PayoutIntent.new(
        id: "long-history-#{index}",
        money: RubyRouting::Money.new(100 + index, "RUB")
      )
      result = app.submit(intent: payout, policy: policy)
      assert_equal :success, result.status,
        "seed=#{HISTORY_SEED} payout=#{index} status=#{result.status} attempts=#{result.payout.attempts.map(&:provider_id)}"
      assert_nil result.payout.ownership,
        "seed=#{HISTORY_SEED} payout=#{index} retained owner=#{result.payout.ownership.inspect}"
    end

    facts = coordinator.facts
    live_analytics = RubyRouting::Projections::Analytics.from_facts(facts)
    replay_analytics = RubyRouting::Projections::Replay.analytics(facts)
    replay_lifecycle = RubyRouting::Projections::Replay.lifecycle(facts)
    recovered = RubyRouting::State::Coordinator.from_facts(facts: facts, opportunities: opportunities)

    assert_equal PAYOUT_COUNT, live_analytics.eventual_success_count
    assert_equal PAYOUT_COUNT, live_analytics.primary_assignment_measure_by_provider.values.sum
    assert_equal PAYOUT_COUNT, live_analytics.settlement_measure_by_provider.values.sum
    assert_equal live_analytics.assignment_measure_by_provider.values.sum,
      live_analytics.attempt_count_by_payout.values.sum
    assert_equal live_analytics.to_h, replay_analytics.to_h
    assert_equal coordinator.lifecycle_projection.to_h, replay_lifecycle.to_h
    assert_equal coordinator.lifecycle_projection.to_h, recovered.lifecycle_projection.to_h
    assert_equal live_analytics.to_h,
      RubyRouting::Projections::Analytics.from_facts(recovered.facts).to_h
    assert_operator live_analytics.fallback_recovery_count, :>, 0
    assert_equal 0, recovered.active_unresolved_owners
  end
end
