# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/reference/ownership_model"

class OwnershipStateMachineTest < Minitest::Test
  DEFAULT_SEED = 7_311

  def test_generated_histories_match_independent_ownership_model
    seed = Integer(ENV.fetch("RUBY_ROUTING_SEED", DEFAULT_SEED.to_s))
    random = Random.new(seed)

    100.times do |history_index|
      coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
      intent = RubyRouting::PayoutIntent.new(
        id: "model-#{history_index}",
        money: RubyRouting::Money.new(100, "RUB")
      )
      policy = RubyRouting::RoutingPolicy.new(
        id: "policy",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1, "B" => 1 }
      )
      model = Reference::OwnershipModel.new
      current_commit = nil

      6.times do |step_index|
        if model.owner.nil? && !%i[success terminal_payout_failure].include?(model.status)
          current_commit = coordinator.prepare_and_commit_decision(intent: intent, policy: policy)
          if current_commit.proposal.action == :defer
            break
          end
          assert_equal :assign, current_commit.proposal.action
          coordinator.mark_attempt_started(current_commit)
          model.assign(current_commit.proposal.provider_id)
        elsif model.owner
          status = %i[pending unknown safe_route_failure success terminal_payout_failure][random.rand(5)]
          outcome = RubyRouting::NormalizedOutcome.new(
            status: status,
            attribution: status == :terminal_payout_failure ? :recipient : :provider
          )
          coordinator.apply_observation(observation(current_commit, outcome, step_index))
          model.observe(status)
        end

        snapshot = coordinator.payout_snapshot(intent.id)
        assert_equal model.owner.nil?, snapshot.ownership.nil?, trace(seed, history_index, step_index, model, snapshot)
        assert_equal model.status, snapshot.status, trace(seed, history_index, step_index, model, snapshot)
        assert_equal model.attempt_count, snapshot.attempt_count, trace(seed, history_index, step_index, model, snapshot)
      end
    end
  end

  private

  def opportunities
    [
      RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      RubyRouting::ProviderOpportunity.new(provider_id: "B")
    ]
  end

  def observation(commit, outcome, step_index)
    RubyRouting::ProviderObservation.new(
      observation_id: "model-observation-#{commit.proposal.operation_id}-#{step_index}",
      payout_id: commit.request.payout_id,
      provider_id: commit.proposal.provider_id,
      operation_id: commit.proposal.operation_id,
      attempt_id: commit.proposal.attempt_id,
      outcome: outcome
    )
  end

  def trace(seed, history_index, step_index, model, snapshot)
    "seed=#{seed} history=#{history_index} step=#{step_index} model=#{model.status}/#{model.owner.inspect}/#{model.attempt_count} " \
      "sut=#{snapshot.status}/#{snapshot.ownership&.provider_id.inspect}/#{snapshot.attempt_count}"
  end
end
