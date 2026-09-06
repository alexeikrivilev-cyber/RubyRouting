# frozen_string_literal: true

require_relative "../test_helper"

class AdmissionOracleTest < Minitest::Test
  DEFAULT_SEED = 20_260_829
  STEPS = 120

  def test_generated_capacity_and_throughput_admission_matches_independent_model
    seed = Integer(ENV.fetch("RUBY_ROUTING_SEED", DEFAULT_SEED.to_s))
    random = Random.new(seed)
    clock = TestSupport::ControlledClock.new
    capacity = RubyRouting::CapacityBudget.new(
      max_slots: 3,
      max_count: 4,
      max_amount_minor: 320,
      currency: "RUB"
    )
    throughput = RubyRouting::ThroughputBudget.new(max_operations: 3, window_seconds: 5)
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capacity: capacity,
      throughput: throughput
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: "admission-oracle",
      epoch: "1",
      measure: :count,
      targets: { "A" => 1 }
    )
    coordinator = RubyRouting::State::Coordinator.new(clock: clock, opportunities: [provider])
    active = {}
    consumed_at = []
    used_amount_minor = 0

    STEPS.times do |step|
      clock.advance(random.rand(0..2))
      if active.any? && random.rand(3).zero?
        payout_id, commit = active.keys.sample(random: random)
        coordinator.mark_attempt_started(commit)
        coordinator.apply_observation(
          RubyRouting::ProviderObservation.new(
            observation_id: "admission-oracle-release-#{step}",
            payout_id: payout_id,
            provider_id: "A",
            operation_id: commit.proposal.operation_id,
            attempt_id: commit.proposal.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :unknown)
          )
        )
        used_amount_minor -= active.fetch([payout_id, commit]).fetch(:amount)
        active.delete([payout_id, commit])
      end

      consumed_at.reject! { |timestamp| timestamp <= clock.now - throughput.window_seconds }
      amount = random.rand(40..140)
      payout = RubyRouting::PayoutIntent.new(
        id: "admission-oracle-#{step}",
        money: RubyRouting::Money.new(amount, "RUB")
      )
      expected = active.length < capacity.max_slots &&
        active.length < capacity.max_count &&
        used_amount_minor + amount <= capacity.max_amount_minor &&
        consumed_at.length < throughput.max_operations

      result = coordinator.prepare_and_commit_decision(intent: payout, policy: policy)
      assert_equal expected, result.proposal.assignment?,
        "seed=#{seed} step=#{step} active=#{active.length} used_amount=#{used_amount_minor} " \
        "amount=#{amount} consumed=#{consumed_at.length} reasons=#{result.proposal.reason_codes.inspect}"

      if expected
        active[[payout.id, result]] = { amount: amount }.freeze
        consumed_at << clock.now
        used_amount_minor += amount
      end
      assert_equal active.length, coordinator.capacity_snapshot("A").used_count,
        "seed=#{seed} step=#{step} capacity"
      assert_equal consumed_at.length, coordinator.throughput_snapshot("A").consumed_count,
        "seed=#{seed} step=#{step} throughput"
    end
  end
end
