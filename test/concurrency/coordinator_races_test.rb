# frozen_string_literal: true

require_relative "../test_helper"

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
