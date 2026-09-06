# frozen_string_literal: true

require_relative "../test_helper"

class ReadPathHardeningTest < Minitest::Test
  def test_revision_cache_reprojects_only_age_and_invalidates_after_new_facts
    clock = TestSupport::ControlledClock.new
    policy = RubyRouting::RoutingPolicy.new(
      id: "read-cache-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 },
      recovery: RubyRouting::RecoveryPolicy.new(initial_delay_seconds: 5)
    )
    coordinator = RubyRouting::State::Coordinator.new(
      clock: clock,
      opportunities: [RubyRouting::ProviderOpportunity.new(
        provider_id: "A",
        capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
      )]
    )
    service = RubyRouting::Application::Service.new(
      coordinator: coordinator,
      providers: { "A" => UnknownThenSuccessProvider.new },
      policy_registry: RubyRouting::PolicyRegistry.new([policy])
    )
    payout = RubyRouting::PayoutIntent.new(
      id: "read-cache-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )

    first = service.submit(intent: payout, policy: policy)
    assert_equal :unknown, first.status
    base = service.queries.analytics(as_of: nil)
    assert_same base, service.queries.analytics(as_of: nil)
    assert_equal({ payout.id => 0 }, service.queries.analytics(as_of: clock.now).unresolved_age_seconds_by_payout)

    later = clock.now + 7
    aged = service.queries.analytics(as_of: later)
    assert_equal({ payout.id => 7 }, aged.unresolved_age_seconds_by_payout)
    assert_equal(
      RubyRouting::Projections::Replay.analytics(coordinator.facts, as_of: later).to_h,
      aged.to_h
    )

    restored = RubyRouting::State::Coordinator.from_facts(
      clock: clock,
      facts: coordinator.facts
    )
    restored_service = RubyRouting::Application::Service.new(
      coordinator: restored,
      providers: { "A" => UnknownThenSuccessProvider.new },
      policy_registry: RubyRouting::PolicyRegistry.new([policy])
    )
    assert_equal(
      RubyRouting::Projections::Replay.analytics(restored.facts, as_of: later).to_h,
      restored_service.queries.analytics(as_of: later).to_h
    )

    clock.advance(5)
    resolved = service.resume(payout_id: payout.id, policy: policy)
    assert_equal :success, resolved.status
    refreshed = service.queries.analytics(as_of: clock.now)
    refute_same base, refreshed
    assert_equal(
      RubyRouting::Projections::Replay.analytics(coordinator.facts, as_of: clock.now).to_h,
      refreshed.to_h
    )
  end

  def test_explanation_uses_indexed_payout_facts_without_changing_the_projection
    coordinator = IndexedExplanationCoordinator.new(
      opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "indexed-explanation-policy",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    payout = RubyRouting::PayoutIntent.new(
      id: "indexed-explanation-payout",
      money: RubyRouting::Money.new(100, "RUB")
    )
    commit = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
    coordinator.mark_attempt_started(commit)
    coordinator.apply_observation(
      RubyRouting::ProviderObservation.new(
        observation_id: "indexed-explanation-observation",
        payout_id: payout.id,
        provider_id: "A",
        operation_id: commit.proposal.operation_id,
        attempt_id: commit.proposal.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    )

    queries = RubyRouting::Application::Queries.new(
      coordinator: coordinator,
      policy_registry: RubyRouting::PolicyRegistry.new([policy])
    )
    explanation = queries.explanation(payout.id)

    assert_equal payout.id, explanation.payout_id
    assert_equal 1, explanation.decisions.length
    assert_equal :success, explanation.result.status
    assert_operator coordinator.indexed_audit_calls, :>, 0
  end

  class UnknownThenSuccessProvider
    def initiate(request)
      observation(request, "initiate", RubyRouting::NormalizedOutcome.unknown(attribution: :provider))
    end

    def resolve(request)
      observation(request, "resolve", RubyRouting::NormalizedOutcome.success(attribution: :provider))
    end

    private

    def observation(request, source, outcome)
      RubyRouting::ProviderObservation.new(
        observation_id: "read-cache-#{source}-#{request.operation_id}",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: outcome
      )
    end
  end

  class IndexedExplanationCoordinator < RubyRouting::State::Coordinator
    attr_reader :indexed_audit_calls

    def initialize(**arguments)
      @indexed_audit_calls = 0
      super
    end

    def facts
      raise "explanation must not request the complete fact history"
    end

    def audit_facts(**arguments)
      @indexed_audit_calls += 1
      super
    end
  end
end
