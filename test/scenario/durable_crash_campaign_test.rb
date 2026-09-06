# frozen_string_literal: true

require_relative "../test_helper"

class DurableCrashCampaignTest < Minitest::Test
  CRASH_SEED = 20_260_829

  class CrashJournal
    attr_reader :facts

    def initialize
      @facts = []
      @append_count = 0
      @crash_at = nil
    end

    def crash_on_next_append!
      @crash_at = @append_count + 1
    end

    def append_many(facts)
      @facts.concat(facts)
      @append_count += 1
      return unless @append_count == @crash_at

      @crash_at = nil
      raise SystemExit, "simulated crash seed=#{CRASH_SEED} append=#{@append_count}"
    end
  end

  class AlwaysSuccessProvider
    def initiate(request)
      observation(request, "initiate")
    end

    def resolve(request)
      observation(request, "resolve")
    end

    private

    def observation(request, phase)
      RubyRouting::ProviderObservation.new(
        observation_id: "crash-campaign:#{request.operation_id}:#{phase}",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    end
  end

  def test_crash_after_assignment_batch_restores_owner_and_dispatches_same_operation
    journal = CrashJournal.new
    coordinator = build_coordinator(journal: journal, opportunities: [opportunity("A", status_lookup: true)])
    payout = intent("crash-after-assignment")
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.prepare_and_commit_decision(intent: payout, policy: policy("crash-assignment"))
    end

    recovered = recover(journal: journal)
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: recovered,
      providers: { "A" => AlwaysSuccessProvider.new }
    ).resume(payout_id: payout.id)

    assert_equal :success, result.status, campaign_trace(recovered, "assignment")
    assert_nil result.payout.ownership
    assert_equal 1, result.payout.attempt_count
  end

  def test_crash_after_possible_provider_acceptance_preserves_settlement
    journal = CrashJournal.new
    coordinator = build_coordinator(journal: journal, opportunities: [opportunity("A")])
    payout = intent("crash-after-accepted")
    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy("crash-accepted"))
    coordinator.mark_attempt_started(committed)
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.apply_observation(observation(committed, :success, :provider))
    end

    recovered = recover(journal: journal)
    snapshot = recovered.payout_snapshot(payout.id)
    assert_equal :success, snapshot.status, campaign_trace(recovered, "accepted")
    assert_nil snapshot.ownership
    assert_equal recovered.lifecycle_projection.to_h,
      RubyRouting::Projections::Replay.lifecycle(recovered.facts).to_h
  end

  def test_crash_after_unknown_observation_keeps_owner_and_only_resolves_same_operation
    journal = CrashJournal.new
    coordinator = build_coordinator(journal: journal, opportunities: [opportunity("A", status_lookup: true)])
    payout = intent("crash-after-unknown")
    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy("crash-unknown"))
    coordinator.mark_attempt_started(committed)
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.apply_observation(observation(committed, :unknown, :provider))
    end

    recovered = recover(journal: journal)
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: recovered,
      providers: { "A" => AlwaysSuccessProvider.new }
    ).resume(payout_id: payout.id)

    assert_equal :success, result.status, campaign_trace(recovered, "unknown")
    assert_equal [committed.proposal.operation_id],
      result.payout.attempts.map(&:operation_id)
  end

  def test_crash_after_safe_release_restarts_with_fresh_fallback
    journal = CrashJournal.new
    coordinator = build_coordinator(
      journal: journal,
      opportunities: [opportunity("A"), opportunity("B")]
    )
    payout = intent("crash-after-release")
    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy("crash-release", targets: { "A" => 1, "B" => 1 }))
    coordinator.mark_attempt_started(committed)
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.apply_observation(observation(committed, :safe_route_failure, :provider))
    end

    recovered = recover(journal: journal)
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: recovered,
      providers: { "A" => AlwaysSuccessProvider.new, "B" => AlwaysSuccessProvider.new }
    ).resume(payout_id: payout.id, policy: policy("crash-release", targets: { "A" => 1, "B" => 1 }))

    assert_equal :success, result.status, campaign_trace(recovered, "safe-release")
    assert_equal ["A", "B"], result.payout.attempts.map(&:provider_id)
  end

  def test_crash_after_settlement_restores_final_state_without_dispatch
    journal = CrashJournal.new
    coordinator = build_coordinator(journal: journal, opportunities: [opportunity("A")])
    payout = intent("crash-after-settlement")
    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy("crash-settlement"))
    coordinator.mark_attempt_started(committed)
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.apply_observation(observation(committed, :success, :provider))
    end

    recovered = recover(journal: journal)
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: recovered,
      providers: {}
    ).resume(payout_id: payout.id)

    assert_equal :already_final, result.action, campaign_trace(recovered, "settlement")
    assert_equal :success, result.status
    assert_equal 1, result.payout.attempt_count
  end

  def test_crash_while_reconciliation_blocked_keeps_owner_until_explicit_observation
    journal = CrashJournal.new
    clock = TestSupport::ControlledClock.new
    coordinator = build_coordinator(
      journal: journal,
      clock: clock,
      opportunities: [opportunity("A", status_lookup: true)]
    )
    payout = intent("crash-reconciliation")
    policy = policy("crash-reconciliation", ttl_seconds: 1)
    committed = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    clock.advance(1)
    journal.crash_on_next_append!

    assert_raises(SystemExit) do
      coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    end

    recovered = recover(journal: journal, clock: clock)
    result = RubyRouting::Application::Orchestrator.new(
      coordinator: recovered,
      providers: {}
    ).resume(payout_id: payout.id)

    assert_equal :defer, result.action, campaign_trace(recovered, "reconciliation")
    assert_equal :reconciliation_blocked, result.status
    assert_equal committed.proposal.operation_id, result.payout.ownership.operation_id

    settled = recovered.apply_observation(observation(committed, :success, :provider))
    assert_equal :success, settled.payout.status
    assert_nil settled.payout.ownership
  end

  private

  def build_coordinator(journal:, opportunities:, clock: nil)
    RubyRouting::State::Coordinator.new(
      journal: journal,
      opportunities: opportunities,
      clock: clock
    )
  end

  def recover(journal:, clock: nil)
    RubyRouting::State::Coordinator.new(journal: journal, clock: clock)
  end

  def opportunity(provider_id, status_lookup: false)
    RubyRouting::ProviderOpportunity.new(
      provider_id: provider_id,
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: status_lookup)
    )
  end

  def policy(id, targets: { "A" => 1 }, ttl_seconds: nil)
    RubyRouting::RoutingPolicy.new(
      id: id,
      epoch: "1",
      measure: :count,
      targets: targets,
      recovery: RubyRouting::RecoveryPolicy.new(max_operations: 2, ttl_seconds: ttl_seconds)
    )
  end

  def intent(id)
    RubyRouting::PayoutIntent.new(id: id, money: RubyRouting::Money.new(100, "RUB"))
  end

  def observation(commit, status, attribution)
    RubyRouting::ProviderObservation.new(
      observation_id: "crash-campaign:#{commit.proposal.operation_id}:#{status}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.new(
        status: status,
        attribution: attribution,
        safe_to_release: status == :safe_route_failure
      )
    )
  end

  def campaign_trace(coordinator, boundary)
    payout = coordinator.payout_snapshot(coordinator.facts.last.payout_id)
    "seed=#{CRASH_SEED} boundary=#{boundary} status=#{payout.status} " \
      "owner=#{payout.ownership&.operation_id.inspect} attempts=#{payout.attempts.map(&:operation_id).inspect}"
  end
end
