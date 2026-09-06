# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class DueRecoveryWorkersTest < Minitest::Test
  def test_concurrent_due_workers_start_one_status_resolution_after_restart
    Dir.mktmpdir("ruby-routing-due-workers-resolve") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      providers = opportunities(status_lookup: true)
      payout = intent("due-workers-resolve")
      policy = two_provider_policy("due-workers-resolve-policy")
      initial = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: providers
      )
      committed = initial.prepare_and_commit_decision(intent: payout, policy: policy)
      assert_equal "A", committed.proposal.provider_id
      initial.mark_attempt_started(committed)

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      provider_a = BlockingRecoveryProvider.new(clock)
      provider_b = NeverCalledProvider.new
      app = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => provider_a, "B" => provider_b }
      )

      results = run_concurrent_workers(app, payout.id, policy, provider_a)

      assert results.any? { |result| result.status == :success }
      assert_equal [[:resolve, committed.proposal.operation_id]], provider_a.calls
      assert_empty provider_b.calls
      assert_recovered_once(recovered, payout.id, committed.proposal.operation_id)
    end
  end

  def test_concurrent_due_workers_start_one_idempotent_retry_after_restart
    Dir.mktmpdir("ruby-routing-due-workers-retry") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      providers = opportunities(idempotent_retry: true)
      payout = intent("due-workers-retry")
      policy = two_provider_policy("due-workers-retry-policy")
      initial = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: providers
      )
      committed = initial.prepare_and_commit_decision(intent: payout, policy: policy)
      assert_equal "A", committed.proposal.provider_id
      initial.mark_attempt_started(committed)

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      provider_a = BlockingRecoveryProvider.new(clock)
      provider_b = NeverCalledProvider.new
      app = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => provider_a, "B" => provider_b }
      )

      results = run_concurrent_workers(app, payout.id, policy, provider_a)

      assert results.any? { |result| result.status == :success }
      assert_equal [[:initiate, committed.proposal.operation_id]], provider_a.calls
      assert_empty provider_b.calls
      assert_recovered_once(recovered, payout.id, committed.proposal.operation_id)
    end
  end

  def test_concurrent_recovery_executors_start_one_restart_resolution
    Dir.mktmpdir("ruby-routing-due-executor-workers") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      payout = intent("due-executor-workers")
      policy = two_provider_policy("due-executor-workers-policy")
      initial = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: opportunities(status_lookup: true)
      )
      committed = initial.prepare_and_commit_decision(intent: payout, policy: policy)
      initial.mark_attempt_started(committed)

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      provider_a = BlockingRecoveryProvider.new(clock)
      provider_b = NeverCalledProvider.new
      service = RubyRouting::Application::Service.new(
        coordinator: recovered,
        providers: { "A" => provider_a, "B" => provider_b }
      )
      barrier = TestSupport::Synchronization::Barrier.new(4)
      completions = Queue.new
      workers = 4.times.map do
        Thread.new do
          barrier.wait
          pass = nil
          error = nil
          begin
            pass = service.recovery_executor.run(limit: 1, as_of: clock.now)
          rescue StandardError => exception
            error = exception
          ensure
            completions << [pass, error]
          end
        end
      end

      assert_equal :resolve, Timeout.timeout(3) { provider_a.entered.pop }
      completed = Timeout.timeout(3) { Array.new(3) { completions.pop } }
      assert completed.all? { |pass, error| error.nil? && pass.success? }, completed.inspect
      assert_equal [[:resolve, committed.proposal.operation_id]], provider_a.calls

      provider_a.release(1)
      final_pass, final_error = Timeout.timeout(3) { completions.pop }
      raise final_error if final_error
      assert final_pass.success?
      workers.each(&:value)
      assert_equal :success, service.queries.payout(payout.id).status
      assert_nil service.queries.payout(payout.id).ownership
      assert_empty provider_b.calls
      assert_equal 1, recovered.facts.count { |fact| fact.type == :allocation_committed }
      assert_equal 2, recovered.facts.count { |fact| fact.type == :attempt_started }
    ensure
      provider_a&.release(4)
      workers&.each { |worker| worker.join(3) }
    end
  end

  def test_unclassified_adapter_failure_releases_only_the_live_guard
    Dir.mktmpdir("ruby-routing-due-workers-failure") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      providers = opportunities(status_lookup: true)
      payout = intent("due-workers-failure")
      policy = two_provider_policy("due-workers-failure-policy")
      initial = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: providers
      )
      committed = initial.prepare_and_commit_decision(intent: payout, policy: policy)
      initial.mark_attempt_started(committed)

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      provider_a = FailingOnceRecoveryProvider.new(clock)
      app = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => provider_a, "B" => NeverCalledProvider.new }
      )

      assert_raises(RuntimeError) { app.resume(payout_id: payout.id, policy: policy) }
      result = app.resume(payout_id: payout.id, policy: policy)

      assert_equal :success, result.status
      assert_equal [[:resolve, committed.proposal.operation_id],
                    [:resolve, committed.proposal.operation_id]], provider_a.calls
      payout_snapshot = recovered.payout_snapshot(payout.id)
      assert_equal 3, payout_snapshot.provider_interaction_count
      assert_equal 2, payout_snapshot.resolution_interaction_count
      assert_equal 1, recovered.facts.count { |fact| fact.type == :allocation_committed }
      assert_equal 3, recovered.facts.count { |fact| fact.type == :attempt_started }
    end
  end

  def test_duplicate_observation_during_blocked_resolution_cannot_release_live_guard
    Dir.mktmpdir("ruby-routing-live-guard-duplicate") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      providers = opportunities(status_lookup: true)
      payout = intent("live-guard-duplicate")
      policy = two_provider_policy("live-guard-duplicate-policy")
      initial = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: providers
      )
      committed = initial.prepare_and_commit_decision(intent: payout, policy: policy)
      initial.mark_attempt_started(committed)
      unknown = observation(committed, "live-guard-unknown", :unknown)
      initial.apply_observation(unknown)

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      provider_a = BlockingRecoveryProvider.new(clock)
      provider_b = NeverCalledProvider.new
      app = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => provider_a, "B" => provider_b }
      )

      worker_a = Thread.new { app.resume(payout_id: payout.id, policy: policy) }
      assert_equal :resolve, Timeout.timeout(3) { provider_a.entered.pop }

      duplicate = app.reconcile(observation: unknown)
      assert duplicate.duplicate

      worker_b = Thread.new { app.resume(payout_id: payout.id, policy: policy) }
      result_b = Timeout.timeout(3) { worker_b.value }
      assert_equal :unknown, result_b.status
      assert_equal 1, provider_a.calls.length
      assert_empty provider_b.calls
      assert_equal 1, recovered.active_unresolved_owners
      assert_equal 2, recovered.facts.count { |fact| fact.type == :attempt_started }
      assert_equal 1, recovered.facts.count { |fact| fact.type == :allocation_committed }

      provider_a.release(1)
      result_a = Timeout.timeout(3) { worker_a.value }
      assert_equal :success, result_a.status
      assert_recovered_once(recovered, payout.id, committed.proposal.operation_id)
      completed = app.resume(payout_id: payout.id, policy: policy)
      assert_equal :success, completed.status
      assert_equal [[:resolve, committed.proposal.operation_id]], provider_a.calls
    ensure
      provider_a&.release(2)
      worker_a&.join(3)
      worker_b&.join(3)
    end
  end

  def test_duplicate_observation_during_blocked_idempotent_retry_cannot_release_live_guard
    Dir.mktmpdir("ruby-routing-live-guard-retry-duplicate") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      providers = opportunities(idempotent_retry: true)
      payout = intent("live-guard-retry-duplicate")
      policy = two_provider_policy("live-guard-retry-duplicate-policy")
      initial = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: providers
      )
      committed = initial.prepare_and_commit_decision(intent: payout, policy: policy)
      initial.mark_attempt_started(committed)
      unknown = observation(committed, "live-guard-retry-unknown", :unknown)
      initial.apply_observation(unknown)

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      provider_a = BlockingRecoveryProvider.new(clock)
      provider_b = NeverCalledProvider.new
      app = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => provider_a, "B" => provider_b }
      )

      worker_a = Thread.new { app.resume(payout_id: payout.id, policy: policy) }
      assert_equal :initiate, Timeout.timeout(3) { provider_a.entered.pop }

      duplicate = app.reconcile(observation: unknown)
      assert duplicate.duplicate

      worker_b = Thread.new { app.resume(payout_id: payout.id, policy: policy) }
      result_b = Timeout.timeout(3) { worker_b.value }
      assert_equal :unknown, result_b.status
      assert_equal [[:initiate, committed.proposal.operation_id]], provider_a.calls
      assert_empty provider_b.calls
      assert_equal 1, recovered.active_unresolved_owners

      provider_a.release(1)
      result_a = Timeout.timeout(3) { worker_a.value }
      assert_equal :success, result_a.status
      assert_recovered_once(recovered, payout.id, committed.proposal.operation_id)
      completed = app.resume(payout_id: payout.id, policy: policy)
      assert_equal :success, completed.status
      assert_equal [[:initiate, committed.proposal.operation_id]], provider_a.calls
    ensure
      provider_a&.release(2)
      worker_a&.join(3)
      worker_b&.join(3)
    end
  end

  def test_non_applying_observation_during_blocked_resolution_cannot_release_live_guard
    Dir.mktmpdir("ruby-routing-live-guard-stale") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      providers = opportunities(status_lookup: true)
      payout = intent("live-guard-stale-observation")
      policy = two_provider_policy("live-guard-stale-observation-policy")
      initial = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: providers
      )
      committed = initial.prepare_and_commit_decision(intent: payout, policy: policy)
      initial.mark_attempt_started(committed)
      unknown = observation(committed, "live-guard-stale-unknown", :unknown)
      initial.apply_observation(unknown)

      recovered = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      provider_a = BlockingRecoveryProvider.new(clock)
      provider_b = NeverCalledProvider.new
      app = RubyRouting::Application::Orchestrator.new(
        coordinator: recovered,
        providers: { "A" => provider_a, "B" => provider_b }
      )

      worker_a = Thread.new { app.resume(payout_id: payout.id, policy: policy) }
      assert_equal :resolve, Timeout.timeout(3) { provider_a.entered.pop }

      stale = observation(committed, "live-guard-stale-pending", :pending)
      stale_application = app.reconcile(observation: stale)
      refute stale_application.duplicate
      assert_equal :wait, stale_application.next_action

      worker_b = Thread.new { app.resume(payout_id: payout.id, policy: policy) }
      result_b = Timeout.timeout(3) { worker_b.value }
      assert_equal :unknown, result_b.status
      assert_equal [[:resolve, committed.proposal.operation_id]], provider_a.calls
      assert_empty provider_b.calls
      assert_equal 1, recovered.active_unresolved_owners

      provider_a.release(1)
      result_a = Timeout.timeout(3) { worker_a.value }
      assert_equal :success, result_a.status
      assert_recovered_once(recovered, payout.id, committed.proposal.operation_id)
    ensure
      provider_a&.release(2)
      worker_a&.join(3)
      worker_b&.join(3)
    end
  end

  def test_stale_interaction_token_cannot_release_a_newer_invocation
    clock = TestSupport::ControlledClock.new
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    )
    payout = intent("live-guard-aba")
    policy = RubyRouting::RoutingPolicy.new(
      id: "live-guard-aba-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(
        max_resolution_interactions: 3,
        initial_delay_seconds: 0,
        backoff_seconds: 0
      )
    )
    coordinator = RubyRouting::State::Coordinator.new(clock: clock, opportunities: [provider])
    initial = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    initial_token = coordinator.mark_attempt_started(initial)
    coordinator.apply_observation(
      observation(initial, "live-guard-aba-unknown", :unknown),
      interaction_token: initial_token
    )

    first_resolution = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    first_token = coordinator.mark_resolution_started(first_resolution)
    coordinator.provider_interaction_failed(interaction_token: first_token)

    second_resolution = coordinator.resume_operation(payout.id)
    refute_nil second_resolution
    assert_equal :resolve, second_resolution.proposal.action
    second_token = coordinator.mark_resolution_started(second_resolution)
    refute_nil second_token
    coordinator.provider_interaction_failed(interaction_token: first_token)

    assert_nil coordinator.resume_operation(payout.id)
    coordinator.provider_interaction_failed(interaction_token: second_token)
    refute_nil coordinator.resume_operation(payout.id)
  end

  private

  def run_concurrent_workers(app, payout_id, policy, provider, worker_count: 4)
    barrier = TestSupport::Synchronization::Barrier.new(worker_count)
    completions = Queue.new
    threads = worker_count.times.map do
      Thread.new do
        barrier.wait
        result = nil
        error = nil
        begin
          result = app.resume(payout_id: payout_id, policy: policy)
        rescue StandardError => exception
          error = exception
        ensure
          completions << [result, error]
        end
      end
    end

    provider.entered.pop
    completed = Timeout.timeout(3) { Array.new(worker_count - 1) { completions.pop } }
    assert completed.all? { |(_result, error)| error.nil? }, completed.inspect
    assert_equal 1, provider.calls.length

    provider.release(worker_count + 1)
    threads.map(&:value).map do |result, error|
      raise error if error

      result
    end
  ensure
    provider.release(worker_count + 1)
    threads&.each { |thread| thread.join(3) }
  end

  def assert_recovered_once(coordinator, payout_id, operation_id)
    payout = coordinator.payout_snapshot(payout_id)
    assert_equal :success, payout.status
    assert_nil payout.ownership
    assert_equal [operation_id], payout.attempts.map(&:operation_id)
    assert_equal 2, payout.provider_interaction_count
    assert_equal 1, payout.resolution_interaction_count
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :allocation_committed }
    assert_equal 2, coordinator.facts.count { |fact| fact.type == :attempt_started }
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :settlement_recorded }
  end

  def opportunities(status_lookup: false, idempotent_retry: false)
    [
      RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(
          status_lookup: status_lookup,
          idempotent_retry: idempotent_retry
        )
      ),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def two_provider_policy(id)
    RubyRouting::RoutingPolicy.new(id: id, epoch: "1", measure: :count, targets: { "A" => 1, "B" => 1 })
  end

  def observation(commit, id, status)
    RubyRouting::ProviderObservation.new(
      observation_id: id,
      payout_id: commit.request.payout_id,
      provider_id: commit.request.provider_id,
      operation_id: commit.request.operation_id,
      attempt_id: commit.request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(
        status: status,
        attribution: :provider,
        safe_to_release: false
      ),
      observed_at: nil
    )
  end

  class BlockingRecoveryProvider
    attr_reader :calls, :entered

    def initialize(clock)
      @clock = clock
      @calls = []
      @entered = Queue.new
      @release = Queue.new
      @mutex = Thread::Mutex.new
      @sequence = 0
    end

    def initiate(request)
      invoke(request, :initiate)
    end

    def resolve(request)
      invoke(request, :resolve)
    end

    def release(count)
      count.times { @release << true }
    end

    private

    def invoke(request, action)
      sequence = @mutex.synchronize do
        @calls << [action, request.operation_id].freeze
        @sequence += 1
      end
      @entered << action
      @release.pop
      RubyRouting::ProviderObservation.new(
        observation_id: "due-worker-observation-#{sequence}",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider),
        provider_reference: "due-worker-reference",
        observed_at: @clock.now
      )
    end
  end

  class NeverCalledProvider
    attr_reader :calls

    def initialize
      @calls = []
    end

    def initiate(request)
      @calls << [:initiate, request.operation_id]
      raise "unexpected provider B interaction"
    end

    def resolve(request)
      @calls << [:resolve, request.operation_id]
      raise "unexpected provider B interaction"
    end
  end

  class FailingOnceRecoveryProvider
    attr_reader :calls

    def initialize(clock)
      @clock = clock
      @calls = []
      @failed = false
    end

    def initiate(_request)
      raise "unexpected initiate"
    end

    def resolve(request)
      @calls << [:resolve, request.operation_id].freeze
      unless @failed
        @failed = true
        raise "adapter failed before returning an observation"
      end

      RubyRouting::ProviderObservation.new(
        observation_id: "recovery-after-adapter-failure",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider),
        provider_reference: "recovery-after-failure",
        observed_at: @clock.now
      )
    end
  end
end
