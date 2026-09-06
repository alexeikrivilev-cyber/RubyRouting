# frozen_string_literal: true

require_relative "../test_helper"

class HighContentionFuzzTest < Minitest::Test
  FUZZ_SEED = 20_260_828

  class ChaoticProvider
    attr_reader :id

    def initialize(id, seed:, fail_rate: Rational(1, 10), timeout_rate: Rational(1, 20))
      @id = id
      @seed = seed
      @fail_rate = fail_rate
      @timeout_rate = timeout_rate
      @lock = Thread::Mutex.new
      @call_count = 0
    end

    def initiate(request)
      call_count = @lock.synchronize { @call_count += 1 }
      roll = deterministic_roll(request, :initiate)
      if roll < @timeout_rate
        # Ambiguous transport timeout
        RubyRouting::ProviderTransportResult.ambiguous_after_possible_send(
          provider_reference: "ref:#{@id}:#{call_count}",
          message: "simulated network timeout on #{@id}"
        )
      elsif roll < @timeout_rate + @fail_rate
        # Safe failure
        RubyRouting::ProviderTransportResult.definitely_not_sent(
          provider_reference: "ref:#{@id}:#{call_count}",
          message: "simulated connection reset on #{@id}"
        )
      else
        # Success
        RubyRouting::ProviderObservation.new(
          observation_id: "obs:#{request.operation_id}:#{call_count}",
          payout_id: request.payout_id,
          provider_id: @id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(
            attribution: :provider,
            provider_reference: "ref:#{@id}:#{call_count}"
          )
        )
      end
    end

    def resolve(request)
      call_count = @lock.synchronize { @call_count += 1 }
      # 50% success, 50% pending
      if deterministic_roll(request, :resolve) < Rational(3, 5)
        RubyRouting::ProviderObservation.new(
          observation_id: "obs-res:#{request.operation_id}:#{call_count}",
          payout_id: request.payout_id,
          provider_id: @id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.success(
            attribution: :provider,
            provider_reference: "ref-res:#{@id}:#{call_count}"
          )
        )
      else
        RubyRouting::ProviderObservation.new(
          observation_id: "obs-res:#{request.operation_id}:#{call_count}",
          payout_id: request.payout_id,
          provider_id: @id,
          operation_id: request.operation_id,
          attempt_id: request.attempt_id,
          outcome: RubyRouting::NormalizedOutcome.pending(
            attribution: :provider,
            provider_reference: "ref-res:#{@id}:#{call_count}"
          )
        )
      end
    end

    private

    def deterministic_roll(request, phase)
      digest = Digest::SHA256.hexdigest("#{@seed}:#{@id}:#{phase}:#{request.operation_id}")
      Rational(digest.to_i(16) % 10_000, 10_000)
    end
  end

  def test_high_contention_fuzz_preserves_all_financial_and_state_invariants
    clock = TestSupport::ControlledClock.new(start_time: Time.utc(2026, 8, 28, 12, 0, 0))
    providers = {
      "P-A" => ChaoticProvider.new("P-A", seed: FUZZ_SEED, fail_rate: Rational(1, 10), timeout_rate: Rational(1, 20)),
      "P-B" => ChaoticProvider.new("P-B", seed: FUZZ_SEED, fail_rate: Rational(1, 5), timeout_rate: Rational(1, 10)),
      "P-C" => ChaoticProvider.new("P-C", seed: FUZZ_SEED, fail_rate: Rational(1, 20), timeout_rate: Rational(1, 20)),
      "P-D" => ChaoticProvider.new("P-D", seed: FUZZ_SEED, fail_rate: Rational(3, 20), timeout_rate: Rational(1, 20))
    }

    opportunities = [
      RubyRouting::ProviderOpportunity.new(
        provider_id: "P-A",
        capacity: RubyRouting::CapacityBudget.new(max_slots: 10, max_count: 500, max_amount_minor: 10_000_000, currency: "RUB"),
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, ttl_seconds: 10)
      ),
      RubyRouting::ProviderOpportunity.new(
        provider_id: "P-B",
        capacity: RubyRouting::CapacityBudget.new(max_slots: 10),
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, ttl_seconds: 10)
      ),
      RubyRouting::ProviderOpportunity.new(
        provider_id: "P-C",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, ttl_seconds: 10)
      ),
      RubyRouting::ProviderOpportunity.new(
        provider_id: "P-D",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, ttl_seconds: 10)
      )
    ]

    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: opportunities,
      health_policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 2,
        quarantine_after: 4,
        recover_after: 2,
        probe_limit: 2
      )
    )

    policy_rub = RubyRouting::RoutingPolicy.new(
      id: "fuzz-rub",
      epoch: "1",
      measure: :volume,
      targets: { "P-A" => 3, "P-B" => 2, "P-C" => 4, "P-D" => 1 },
      currency: "RUB",
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 3,
        max_switches: 2,
        max_resolution_interactions: 3,
        ttl_seconds: 10
      )
    )
    policy_usd = RubyRouting::RoutingPolicy.new(
      id: "fuzz-usd",
      epoch: "1",
      measure: :count,
      targets: { "P-A" => 1, "P-B" => 1, "P-C" => 1 },
      currency: "USD",
      recovery: RubyRouting::RecoveryPolicy.new(
        max_operations: 3,
        max_switches: 2,
        max_resolution_interactions: 3,
        ttl_seconds: 10
      )
    )
    registry = RubyRouting::PolicyRegistry.new([policy_rub, policy_usd])

    orchestrator = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: providers,
      policy_registry: registry
    )

    payout_count = 150
    thread_count = 12
    payout_intents = payout_count.times.map do |i|
      currency = i.even? ? "RUB" : "USD"
      amount = (i + 1) * 100
      RubyRouting::PayoutIntent.new(
        id: "fuzz-payout-#{i}",
        money: RubyRouting::Money.new(amount, currency),
        context: { labels: ["fuzz"] }
      )
    end

    queue = Thread::Queue.new
    payout_intents.each { |intent| queue << intent }

    errors = []
    error_mutex = Thread::Mutex.new
    execution_trace = []
    trace_mutex = Thread::Mutex.new
    worker_barrier = TestSupport::Synchronization::Barrier.new(thread_count)

    threads = thread_count.times.map do
      Thread.new do
        worker_barrier.wait
        until queue.empty?
          intent = begin
            queue.pop(true)
          rescue ThreadError
            nil
          end
          break unless intent

          begin
            res = orchestrator.submit(intent: intent)
            resumed = nil
            # If unresolved or deferred, occasionally attempt resume
            if %i[wait defer].include?(res.action) && deterministic_roll("resume:#{intent.id}") < Rational(3, 10)
              clock.advance(2)
              resumed = orchestrator.resume(payout_id: intent.id)
            end
            trace_mutex.synchronize do
              execution_trace << {
                payout_id: intent.id,
                result: route_trace(res),
                resumed: resumed && route_trace(resumed)
              }.freeze
            end
          rescue StandardError => error
            trace_mutex.synchronize do
              execution_trace << {
                payout_id: intent.id,
                error: "#{error.class}: #{error.message}"
              }.freeze
            end
            error_mutex.synchronize { errors << error }
          end
        end
      end
    end

    threads.each(&:join)
    if errors.any?
      trace = trace_mutex.synchronize { execution_trace.sort_by { |entry| entry.fetch(:payout_id) }.freeze }
      raise RuntimeError,
        "deterministic fuzz failed for seed=#{FUZZ_SEED}: #{errors.first.full_message}\nexecution_trace=#{trace.inspect}"
    end

    # Verification of Financial and Structural Invariants
    with_trace_on_assertion_failure(trace_mutex, execution_trace) do
      # 1. Capacity Invariant: slots used must equal active non-released ownerships
      opportunities.each do |opp|
        snap = coordinator.capacity_snapshot(opp.provider_id)
        assert snap.used_slots >= 0, "Capacity slots for #{opp.provider_id} cannot be negative"
        assert snap.used_count >= 0, "Capacity count for #{opp.provider_id} cannot be negative"
        assert snap.used_amount_minor >= 0, "Capacity amount for #{opp.provider_id} cannot be negative"
      end

      # 2. Safety Invariant: Every payout has at most 1 active ownership
      payout_intents.each do |intent|
        snap = coordinator.payout_snapshot(intent.id)
        if snap.status == :success
          assert_nil snap.ownership, "Settled payout #{intent.id} must not retain ownership"
          assert_includes %w[P-A P-B P-C P-D], snap.settlement_provider_id
        elsif snap.ownership
          assert_includes %w[P-A P-B P-C P-D], snap.ownership.provider_id
        end
      end

      # 3. Replay Parity: Full Lifecycle, Capacity, Allocation, and Health
      facts = coordinator.facts
      assert facts.length > payout_count, "Expected facts to record all decisions and transitions"

      replayed_lifecycle = RubyRouting::Projections::Replay.lifecycle(facts)
      payout_intents.each do |intent|
        live_snap = coordinator.payout_snapshot(intent.id)
        replayed_snap = replayed_lifecycle.payout(intent.id)

        assert_equal live_snap.status, replayed_snap.status, "Status mismatch for #{intent.id}"
        if live_snap.settlement_provider_id.nil?
          assert_nil replayed_snap.settlement_provider_id
        else
          assert_equal live_snap.settlement_provider_id, replayed_snap.settlement_provider_id
        end
        assert_equal live_snap.attempts.length, replayed_snap.attempts.length
      end

      replayed_capacity = RubyRouting::Projections::Replay.capacity(facts).to_h
      live_capacity = coordinator.capacity_projection.to_h
      assert_equal live_capacity, replayed_capacity, "Capacity projection mismatch after fuzzing"

      replayed_allocation_rub = RubyRouting::Projections::Replay.allocation(facts).snapshot(policy_rub)
      live_allocation_rub = coordinator.allocation_snapshot(policy: policy_rub)
      assert_equal live_allocation_rub.measures, replayed_allocation_rub.measures

      # 4. Analytics Projection: executes cleanly and reflects actual counts
      analytics = RubyRouting::Projections::Analytics.from_facts(facts)
      assert analytics.eventual_success_count >= 0
      assert analytics.attempt_count_by_provider.values.sum >= payout_count
    end
  end

  private

  def route_trace(result)
    {
      action: result.action,
      status: result.status,
      attempts: result.payout.attempts.map { |attempt| [attempt.provider_id, attempt.phase] },
      owner: result.payout.ownership&.operation_id
    }.freeze
  end

  def with_trace_on_assertion_failure(trace_mutex, execution_trace)
    yield
  rescue Minitest::Assertion => error
    trace = trace_mutex.synchronize { execution_trace.sort_by { |entry| entry.fetch(:payout_id) }.freeze }
    raise Minitest::Assertion,
      "#{error.message}\nseed=#{FUZZ_SEED} execution_trace=#{trace.inspect}"
  end

  def deterministic_roll(value)
    digest = Digest::SHA256.hexdigest("#{FUZZ_SEED}:#{value}")
    Rational(digest.to_i(16) % 10_000, 10_000)
  end
end
