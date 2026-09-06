# frozen_string_literal: true

require_relative "../test_helper"

class PausingConfigurationCoordinator < RubyRouting::State::Coordinator
  attr_reader :provider_replacement_started, :provider_replacement_release

  def initialize(**attributes)
    @pause_after_provider_replacement = false
    @provider_replacement_started = Queue.new
    @provider_replacement_release = Queue.new
    super
  end

  def pause_after_provider_replacement!
    @pause_after_provider_replacement = true
  end

  def replace_provider_opportunities(opportunities)
    super
    return unless @pause_after_provider_replacement

    @pause_after_provider_replacement = false
    @provider_replacement_started << true
    @provider_replacement_release.pop
  end
end

class ObservingConfigurationStore < RubyRouting::Application::ConfigurationStore
  attr_reader :snapshot_attempted, :snapshot_entered

  def initialize(**attributes)
    @snapshot_attempted = Queue.new
    @snapshot_entered = Queue.new
    super
  end

  def with_snapshot
    @snapshot_attempted << true
    super do |snapshot|
      @snapshot_entered << snapshot.revision
      yield snapshot
    end
  end
end

class CoordinatorRacesTest < Minitest::Test
  def test_concurrent_same_intent_commits_at_most_one_owner
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
    intent = intent("owner-race")
    barrier = TestSupport::Synchronization::Barrier.new(2)
    results = Array.new(2)
    errors = []
    error_mutex = Thread::Mutex.new

    threads = 2.times.map do |index|
      Thread.new do
        barrier.wait
        results[index] = coordinator.prepare_and_commit_decision(intent: intent, policy: policy)
      rescue StandardError => error
        error_mutex.synchronize { errors << error }
      end
    end
    threads.each(&:join)
    raise errors.first if errors.any?

    assert_equal 1, results.count { |result| result.proposal.assignment? }
    assert_equal 1, results.count { |result| result.proposal.action == :defer }
    assert_equal 1, coordinator.active_unresolved_owners
    assert_equal 1, coordinator.payout_snapshot(intent.id).attempt_count
  end

  def test_concurrent_assignments_see_committed_allocation_reservation
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
    intents = [intent("allocation-race-a"), intent("allocation-race-b")]
    barrier = TestSupport::Synchronization::Barrier.new(2)
    results = Array.new(2)
    errors = []
    error_mutex = Thread::Mutex.new

    threads = intents.each_with_index.map do |payout, index|
      Thread.new do
        barrier.wait
        results[index] = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      rescue StandardError => error
        error_mutex.synchronize { errors << error }
      end
    end
    threads.each(&:join)
    raise errors.first if errors.any?

    assert_equal %w[A B], results.map { |result| result.proposal.provider_id }.sort
    assert_equal({ "A" => 1, "B" => 1 }, coordinator.allocation_snapshot(policy: policy).measures)
    assert_equal 2, coordinator.active_unresolved_owners
  end

  def test_provider_io_can_block_without_blocking_another_atomic_commit
    blocking_provider = BlockingProvider.new
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => blocking_provider, "B" => blocking_provider }
    )
    first_intent = intent("io-race-a")
    second_intent = intent("io-race-b")
    first_error = nil
    first_thread = Thread.new do
      app.submit(intent: first_intent, policy: policy)
    rescue StandardError => error
      first_error = error
    end
    blocking_provider.started.pop

    second_result = Queue.new
    second_thread = Thread.new do
      second_result << coordinator.prepare_and_commit_decision(intent: second_intent, policy: policy)
    end
    begin
      committed = Timeout.timeout(2) { second_result.pop }
      assert committed.proposal.assignment?
    ensure
      blocking_provider.release << true
      second_thread.join
      first_thread.join
    end

    raise first_error if first_error
  end

  def test_active_configuration_race_publishes_a_whole_generation
    coordinator = PausingConfigurationCoordinator.new
    configuration_store = ObservingConfigurationStore.new(
      configuration: RubyRouting::Application::RoutingConfiguration.new
    )
    provider_a = TestSupport::Simulator::ScriptedProvider.new(provider_id: "A", steps: [TestSupport::Simulator::Step.success])
    provider_b = TestSupport::Simulator::ScriptedProvider.new(provider_id: "B", steps: [TestSupport::Simulator::Step.success])
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => provider_a, "B" => provider_b },
      configuration_store: configuration_store
    )
    policy_a = RubyRouting::RoutingPolicy.new(id: "generation-a", epoch: "1", measure: :count, targets: { "A" => 1 })
    policy_b = RubyRouting::RoutingPolicy.new(id: "generation-b", epoch: "1", measure: :count, targets: { "B" => 1 })
    configuration_a = RubyRouting::Application::RoutingConfiguration.new(
      policies: [policy_a], provider_opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    configuration_b = RubyRouting::Application::RoutingConfiguration.new(
      policies: [policy_b], provider_opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "B")]
    )
    service.apply_configuration(configuration_a)
    coordinator.pause_after_provider_replacement!

    apply_errors = Queue.new
    apply_thread = Thread.new do
      service.apply_configuration(configuration_b)
    rescue StandardError => error
      apply_errors << error
    end
    coordinator.provider_replacement_started.pop

    payout = intent("configuration-generation-race")
    submit_result = Queue.new
    submit_thread = Thread.new do
      submit_result << service.submit(intent: payout)
    rescue StandardError => error
      submit_result << error
    end
    configuration_store.snapshot_attempted.pop

    assert_empty coordinator.facts.select { |fact| fact.type == :opportunity_evaluated && fact.payout_id == payout.id }
    assert_raises(ThreadError) { configuration_store.snapshot_entered.pop(true) }

    coordinator.provider_replacement_release << true
    apply_thread.join
    result = Timeout.timeout(2) { submit_result.pop }
    submit_thread.join
    raise apply_errors.pop unless apply_errors.empty?
    raise result if result.is_a?(StandardError)

    assert_equal :success, result.status
    assert_equal 2, service.queries.configuration_revision
    evaluation = coordinator.facts.find do |fact|
      fact.type == :opportunity_evaluated && fact.payout_id == payout.id
    end
    assert_equal "generation-b", evaluation.payload.fetch(:policy_id)
    assert_equal ["B"], evaluation.payload.fetch(:opportunities)
    assert_empty provider_a.calls
    assert_equal [[:initiate, "configuration-generation-race:configuration-generation-race:operation:1"]], provider_b.calls
  end

  def test_configuration_lock_is_released_before_provider_io
    blocking_provider = BlockingProvider.new
    coordinator = RubyRouting::State::Coordinator.new
    configuration_store = ObservingConfigurationStore.new(
      configuration: RubyRouting::Application::RoutingConfiguration.new
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: {
        "A" => blocking_provider,
        "B" => TestSupport::Simulator::ScriptedProvider.new(provider_id: "B", steps: [])
      },
      configuration_store: configuration_store
    )
    policy_a = RubyRouting::RoutingPolicy.new(id: "io-generation-a", epoch: "1", measure: :count, targets: { "A" => 1 })
    policy_b = RubyRouting::RoutingPolicy.new(id: "io-generation-b", epoch: "1", measure: :count, targets: { "B" => 1 })
    service.apply_configuration(
      RubyRouting::Application::RoutingConfiguration.new(
        policies: [policy_a], provider_opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
      )
    )

    submit_result = Queue.new
    submit_thread = Thread.new do
      submit_result << service.submit(intent: intent("configuration-io-race"))
    end
    blocking_provider.started.pop

    apply_result = Queue.new
    apply_thread = Thread.new do
      service.apply_configuration(
        RubyRouting::Application::RoutingConfiguration.new(
          policies: [policy_b], provider_opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "B")]
        )
      )
      apply_result << :applied
    rescue StandardError => error
      apply_result << error
    end

    assert_equal :applied, Timeout.timeout(2) { apply_result.pop }
    apply_thread.join
    blocking_provider.release << true
    result = Timeout.timeout(2) { submit_result.pop }
    submit_thread.join
    raise result if result.is_a?(StandardError)
    assert_equal :success, result.status
  end

  def test_duplicate_submit_during_dispatch_does_not_start_resolution_or_retry
    blocking_provider = BlockingProvider.new
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
    app = RubyRouting::Application::Orchestrator.new(
      coordinator: coordinator,
      providers: { "A" => blocking_provider, "B" => blocking_provider }
    )
    payout = intent("dispatch-duplicate")
    first_error = nil
    first_thread = Thread.new do
      app.submit(intent: payout, policy: policy)
    rescue StandardError => error
      first_error = error
    end
    blocking_provider.started.pop

    duplicate = coordinator.prepare_and_commit_decision(
      intent: payout,
      policy: policy,
      available_provider_ids: %w[A B]
    )

    assert_equal :defer, duplicate.proposal.action
    assert_equal "provider operation dispatch is in progress", duplicate.proposal.reasons.first
    assert_equal 1, duplicate.payout.attempt_count
    assert_equal :dispatching, duplicate.payout.current_operation_phase

    blocking_provider.release << true
    first_thread.join
    raise first_error if first_error
  end

  def test_concurrent_capacity_reservations_allow_only_configured_slots
    coordinator = RubyRouting::State::Coordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capacity: RubyRouting::CapacityBudget.new(max_slots: 1)
      )]
    )
    policy = RubyRouting::RoutingPolicy.new(id: "capacity-race", epoch: "1", measure: :count, targets: { "A" => 1 })
    payouts = [intent("capacity-race-a"), intent("capacity-race-b")]
    barrier = TestSupport::Synchronization::Barrier.new(2)
    results = Array.new(2)
    threads = payouts.each_with_index.map do |payout, index|
      Thread.new do
        barrier.wait
        results[index] = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      end
    end
    threads.each(&:join)

    assert_equal 1, results.count { |result| result.proposal.assignment? }
    assert_equal 1, results.count { |result| result.proposal.action == :defer }
    assert_equal 1, coordinator.capacity_snapshot("A").used_slots
  end

  def test_concurrent_throughput_reservations_consume_only_configured_rate
    clock = TestSupport::ControlledClock.new
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        throughput: RubyRouting::ThroughputBudget.new(max_operations: 1, window_seconds: 60)
      )]
    )
    throughput_policy = RubyRouting::RoutingPolicy.new(
      id: "throughput-race",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    payouts = [intent("throughput-race-a"), intent("throughput-race-b")]
    barrier = TestSupport::Synchronization::Barrier.new(2)
    results = Array.new(2)
    threads = payouts.each_with_index.map do |payout, index|
      Thread.new do
        barrier.wait
        results[index] = coordinator.prepare_and_commit_decision(
          intent: payout,
          policy: throughput_policy
        )
      end
    end
    threads.each(&:join)

    assert_equal 1, results.count { |result| result.proposal.assignment? }
    assert_equal 1, results.count { |result| result.proposal.action == :defer }
    assert_equal 1, coordinator.throughput_snapshot("A").consumed_count
    assert_equal 1, coordinator.facts.count { |fact| fact.type == :throughput_consumed }
  end

  def test_missing_adapter_is_rejected_before_assignment_commit
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
    app = RubyRouting::Application::Orchestrator.new(coordinator: coordinator, providers: {})

    result = app.submit(intent: intent("missing-adapter"), policy: policy)

    assert_equal :defer, result.action
    assert_empty result.payout.attempts
    assert_nil result.payout.ownership
    assert_empty coordinator.allocation_snapshot(policy: policy).measures
    refute coordinator.facts.any? { |fact| fact.type == :allocation_committed }
  end

  def test_non_executable_adapter_is_rejected_before_any_payout_can_commit
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)

    assert_raises(ArgumentError) do
      RubyRouting::Application::Orchestrator.new(
        coordinator: coordinator,
        providers: { "A" => Object.new }
      )
    end

    assert_empty coordinator.facts.select { |fact| fact.type == :allocation_committed }
  end

  def test_provider_port_abstract_methods_are_rejected_before_any_payout_can_commit
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
    adapter = Class.new do
      include RubyRouting::Ports::Provider
    end.new

    assert_raises(ArgumentError) do
      RubyRouting::Application::Orchestrator.new(
        coordinator: coordinator,
        providers: { "A" => adapter }
      )
    end

    assert_empty coordinator.facts.select { |fact| fact.type == :allocation_committed }
    assert_empty coordinator.facts.select { |fact| fact.type == :intent_registered }
  end

  def test_safe_release_racing_with_fallback_never_creates_two_owners
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
    payout = intent("release-fallback-race")
    first = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    interaction_token = coordinator.mark_attempt_started(first)
    safe_failure = observation(first)
    barrier = TestSupport::Synchronization::Barrier.new(2)
    fallback_result = nil
    errors = []
    error_mutex = Thread::Mutex.new

    release_thread = Thread.new do
      barrier.wait
      coordinator.apply_observation(safe_failure)
    rescue StandardError => error
      error_mutex.synchronize { errors << error }
    end
    fallback_thread = Thread.new do
      barrier.wait
      fallback_result = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    rescue StandardError => error
      error_mutex.synchronize { errors << error }
    end
    [release_thread, fallback_thread].each(&:join)

    raise errors.first if errors.any?

    assert_operator coordinator.active_unresolved_owners, :<=, 1
    assert_operator coordinator.facts.count { |fact| fact.type == :ownership_acquired }, :<=, 2
    assert_equal({ "A" => 1 }, coordinator.allocation_snapshot(policy: policy).measures)
    assert_operator coordinator.capacity_snapshot("A").used_slots, :<=, 1

    assert_equal :defer, fallback_result.proposal.action
    assert_equal :wait, coordinator.apply_observation(safe_failure).next_action
    assert_equal first.proposal.operation_id,
      coordinator.payout_snapshot(payout.id).ownership.operation_id
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "race:owning-success:#{first.proposal.operation_id}",
        payout_id: payout.id,
        provider_id: first.proposal.provider_id,
        operation_id: first.proposal.operation_id,
        attempt_id: first.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      ),
      interaction_token: interaction_token
    )

    assert_equal 0, coordinator.active_unresolved_owners
    assert_equal 0, coordinator.capacity_snapshot("A").used_slots
    assert_equal 0, coordinator.capacity_snapshot("B").used_slots
  end

  def test_live_provider_update_is_serialized_with_decision_commit
    coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
    payout = intent("live-state-race")
    barrier = TestSupport::Synchronization::Barrier.new(2)
    result = nil
    errors = []
    error_mutex = Thread::Mutex.new

    decision_thread = Thread.new do
      barrier.wait
      result = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    rescue StandardError => error
      error_mutex.synchronize { errors << error }
    end
    update_thread = Thread.new do
      barrier.wait
      coordinator.set_provider_availability("A", available: false)
    rescue StandardError => error
      error_mutex.synchronize { errors << error }
    end
    [decision_thread, update_thread].each(&:join)

    raise errors.first if errors.any?

    evaluated = coordinator.facts.reverse.find do |fact|
      fact.type == :opportunity_evaluated && fact.payout_id == payout.id
    end
    if evaluated.payload.fetch(:exclusion_codes).fetch("A", nil) == :unavailable
      refute_equal "A", result.proposal.provider_id
    elsif result.proposal.assignment?
      assert_equal "A", result.proposal.provider_id
    end
    assert_operator coordinator.active_unresolved_owners, :<=, 1
  end

  private

  def opportunities
    [
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
  end

  def policy
    RubyRouting::RoutingPolicy.new(id: "policy", epoch: "1", measure: :count, targets: { "A" => 1, "B" => 1 })
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def observation(commit)
    RubyRouting::ProviderObservation.new(
      observation_id: "race:safe-failure:#{commit.proposal.operation_id}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
    )
  end

  class BlockingProvider
    attr_reader :started, :release

    def initialize
      @started = Queue.new
      @release = Queue.new
    end

    def initiate(request)
      @started << request
      @release.pop
      RubyRouting::ProviderObservation.new(
        observation_id: "blocking:#{request.operation_id}",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    end

    def resolve(_request)
      raise NotImplementedError
    end
  end
end
