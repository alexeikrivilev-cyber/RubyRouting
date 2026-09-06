# frozen_string_literal: true

require_relative "../test_helper"
require "digest"

class SeededFaultTraceTest < Minitest::Test
  FAULT_SEED = 20_260_829
  PAYOUT_COUNT = 96

  class SeededProvider
    attr_reader :provider_id, :observed_statuses, :transport_kinds

    def initialize(provider_id:, seed:)
      @provider_id = provider_id.freeze
      @offset = Digest::SHA256.hexdigest("#{seed}:#{provider_id}").to_i(16) % 9
      @observed_statuses = []
      @transport_kinds = []
      @initiation_count = 0
      @sequence = 0
      @operations = {}
    end

    def initiate(request)
      operation = @operations[request.idempotency_key]
      unless operation
        @initiation_count += 1
        operation = @operations[request.idempotency_key] = response_for
      end

      response = operation.fetch(:initial)
      if response.is_a?(RubyRouting::ProviderTransportResult)
        @transport_kinds << response.kind
        response
      else
        observation(request, response)
      end
    end

    def resolve(request)
      operation = @operations.fetch(request.idempotency_key) do
        raise ArgumentError, "seeded provider cannot resolve unknown operation"
      end
      observation(request, operation.fetch(:resolution))
    end

    private

    def response_for
      case (@initiation_count + @offset) % 9
      when 0
        {
          initial: RubyRouting::ProviderTransportResult.definitely_not_sent(message: "seeded not sent"),
          resolution: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        }
      when 1
        {
          initial: RubyRouting::ProviderTransportResult.ambiguous_after_possible_send(message: "seeded timeout"),
          resolution: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        }
      when 2
        {
          initial: RubyRouting::NormalizedOutcome.pending(attribution: :provider),
          resolution: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        }
      when 3
        {
          initial: RubyRouting::NormalizedOutcome.unknown(attribution: :unknown),
          resolution: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        }
      when 4
        {
          initial: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider),
          resolution: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
        }
      when 5
        {
          initial: RubyRouting::NormalizedOutcome.temporary_provider_failure(
            attribution: :provider,
            safe_to_release: true
          ),
          resolution: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
        }
      when 6
        {
          initial: RubyRouting::NormalizedOutcome.terminal_payout_failure(attribution: :recipient),
          resolution: RubyRouting::NormalizedOutcome.terminal_payout_failure(attribution: :recipient)
        }
      else
        {
          initial: RubyRouting::NormalizedOutcome.success(attribution: :provider),
          resolution: RubyRouting::NormalizedOutcome.success(attribution: :provider)
        }
      end
    end

    def observation(request, outcome)
      @sequence += 1
      @observed_statuses << outcome.status
      RubyRouting::ProviderObservation.new(
        observation_id: "seeded-fault:#{provider_id}:#{@sequence}",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: outcome,
        sequence: @sequence
      )
    end
  end

  def test_seeded_fault_histories_preserve_terminal_safety_and_replay
    providers = {
      "A" => SeededProvider.new(provider_id: "A", seed: FAULT_SEED),
      "B" => SeededProvider.new(provider_id: "B", seed: FAULT_SEED),
      "C" => SeededProvider.new(provider_id: "C", seed: FAULT_SEED)
    }
    opportunities = providers.keys.map do |provider_id|
      RubyRouting::ProviderOpportunity.new(
        provider_id: provider_id,
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )
    end
    policy = RubyRouting::RoutingPolicy.new(
      id: "seeded-fault-policy",
      epoch: FAULT_SEED.to_s,
      measure: :count,
      targets: { "A" => 1, "B" => 1, "C" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 3, max_switches: 2)
    )
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
    app = RubyRouting::Application::Orchestrator.new(coordinator: coordinator, providers: providers)

    PAYOUT_COUNT.times do |index|
      payout = RubyRouting::PayoutIntent.new(
        id: "seeded-fault-#{index}",
        money: RubyRouting::Money.new(100, "RUB")
      )
      result = app.submit(intent: payout, policy: policy)
      3.times do
        break unless result.action == :wait

        result = app.resume(payout_id: payout.id, policy: policy)
      end

      assert_includes %i[success terminal_payout_failure safe_route_failure temporary_provider_failure deferred], result.status,
        trace(index, result)
      assert_nil result.payout.ownership, trace(index, result)
    end

    facts = coordinator.facts
    analytics = RubyRouting::Projections::Analytics.from_facts(facts)
    replay = RubyRouting::Projections::Replay.analytics(facts)
    recovered = RubyRouting::State::Coordinator.from_facts(facts: facts, opportunities: opportunities)

    status_counts = recovered.lifecycle_projection.payouts.values.map(&:status).tally
    assert_equal PAYOUT_COUNT, status_counts.values.sum
    assert_equal status_counts.fetch(:success, 0), analytics.eventual_success_count
    assert_equal status_counts.fetch(:terminal_payout_failure, 0), analytics.terminal_failure_count
    assert_equal analytics.to_h, replay.to_h
    assert_equal coordinator.lifecycle_projection.to_h, recovered.lifecycle_projection.to_h
    assert_operator analytics.transport_count_by_kind.fetch(:definitely_not_sent, 0), :>, 0
    assert_operator analytics.transport_count_by_kind.fetch(:ambiguous_after_possible_send, 0), :>, 0
    assert_equal 0, analytics.unresolved_count_by_status.values.sum
    assert_equal 0, recovered.active_unresolved_owners
    assert_includes providers.values.flat_map(&:observed_statuses), :pending
    assert_includes providers.values.flat_map(&:observed_statuses), :unknown
    assert_includes providers.values.flat_map(&:observed_statuses), :safe_route_failure
    assert_includes providers.values.flat_map(&:observed_statuses), :terminal_payout_failure
  end

  private

  def trace(index, result)
    "seed=#{FAULT_SEED} payout=#{index} status=#{result.status} action=#{result.action} " \
      "attempts=#{result.payout.attempts.map { |attempt| [attempt.provider_id, attempt.phase] }.inspect}"
  end
end
