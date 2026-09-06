# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "tmpdir"

class OperatorCompositionCampaignTest < Minitest::Test
  def test_decoded_configuration_drives_count_volume_fallback_executor_and_restart
    Dir.mktmpdir("ruby-routing-operator-composition") do |directory|
      path = File.join(directory, "facts.jsonl")
      clock = TestSupport::ControlledClock.new
      source = configuration
      decoded = RubyRouting::Application::RoutingConfiguration.decode(
        JSON.parse(JSON.generate(source.to_h))
      )
      assert_equal source.to_h, decoded.to_h

      providers = {
        "A" => TestSupport::Simulator::ScriptedProvider.new(
          provider_id: "A",
          clock: clock,
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
          steps: [
            TestSupport::Simulator::Step.unknown(attribution: :provider),
            TestSupport::Simulator::Step.safe_failure,
            TestSupport::Simulator::Step.success
          ]
        ),
        "B" => TestSupport::Simulator::ScriptedProvider.new(
          provider_id: "B",
          clock: clock,
          steps: [
            TestSupport::Simulator::Step.success,
            TestSupport::Simulator::Step.success
          ]
        )
      }
      coordinator = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path),
        opportunities: decoded.provider_opportunities
      )
      service = RubyRouting::Application::Service.new(
        coordinator: coordinator,
        providers: providers
      )
      service.apply_configuration(decoded)
      unknown_policy = decoded.policies.find { |policy| policy.id == "operator-unknown" }
      volume_policy = decoded.policies.find { |policy| policy.id == "operator-volume" }

      unknown = service.submit(intent: intent("operator-unknown", 100), policy: unknown_policy)
      assert_equal :unknown, unknown.status
      assert_equal 1, unknown.payout.attempts.length

      due = service.queries.due_work(as_of: clock.now, limit: 10)
      assert_equal [unknown.payout.id], due.map(&:payout_id)
      execution = service.recovery_executor.run(limit: 10, as_of: clock.now)
      assert_equal [unknown.payout.id], execution.items.map { |item| item.work_item.payout_id }
      assert_equal [:success], execution.items.map(&:status)
      assert_equal :success, service.queries.payout(unknown.payout.id).status
      assert_equal 2, service.queries.payout(unknown.payout.id).attempts.length

      volume = service.submit(intent: intent("operator-volume", 300), policy: volume_policy)
      assert_equal :success, volume.status
      analytics = service.queries.analytics
      assert_equal 1, measure_total(analytics, unknown_policy.id, :primary_assignment)
      assert_equal 300, measure_total(analytics, volume_policy.id, :primary_assignment)
      assert_equal 1, measure_total(analytics, unknown_policy.id, :eventual_settlement_count)
      assert_equal 1, analytics.query(
        metric: :successful_fallback_recovery_count,
        filters: { policy_id: unknown_policy.id, currency: "RUB" },
        group_by: %i[provider_id role]
      ).rows.sum(&:value)
      restored_coordinator = RubyRouting::State::Coordinator.new(
        clock: clock,
        journal: RubyRouting::State::FileJournal.new(path)
      )
      restored_service = RubyRouting::Application::Service.new(
        coordinator: restored_coordinator,
        providers: {
          "A" => TestSupport::Simulator::ScriptedProvider.new(provider_id: "A", steps: []),
          "B" => TestSupport::Simulator::ScriptedProvider.new(provider_id: "B", steps: [])
        },
        policy_registry: RubyRouting::PolicyRegistry.new(decoded.policies)
      )

      assert_equal analytics.to_h, restored_service.queries.analytics.to_h
      [unknown.payout.id, volume.payout.id].each do |payout_id|
        assert_equal payout_signature(service.queries.payout(payout_id)),
          payout_signature(restored_service.queries.payout(payout_id))
      end
      assert_empty restored_service.queries.due_work(as_of: clock.now)
    end
  end

  private

  def configuration
    RubyRouting::Application::RoutingConfiguration.new(
      policies: [
        RubyRouting::RoutingPolicy.new(
          id: "operator-count",
          epoch: "1",
          measure: :count,
          targets: { "A" => 1, "B" => 1 },
          scope: "count",
          recovery: RubyRouting::RecoveryPolicy.new(initial_delay_seconds: 0)
        ),
        RubyRouting::RoutingPolicy.new(
          id: "operator-unknown",
          epoch: "1",
          measure: :count,
          targets: { "A" => 1, "B" => 1 },
          scope: "unknown",
          recovery: RubyRouting::RecoveryPolicy.new(initial_delay_seconds: 0)
        ),
        RubyRouting::RoutingPolicy.new(
          id: "operator-volume",
          epoch: "1",
          measure: :volume,
          currency: "RUB",
          targets: { "A" => 1, "B" => 1 },
          scope: "volume"
        )
      ],
      provider_opportunities: %w[A B].map do |provider_id|
        RubyRouting::ProviderOpportunity.new(
          provider_id: provider_id,
          capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
        )
      end
    )
  end

  def intent(id, amount)
    RubyRouting::PayoutIntent.new(
      id: id,
      money: RubyRouting::Money.new(amount, "RUB")
    )
  end

  def measure_total(analytics, policy_id, metric)
    if metric == :primary_assignment
      return analytics.primary_assignment_measure_by_dimension.sum do |dimension, value|
        dimension.policy_id == policy_id ? value : 0
      end
    end

    analytics.query(
      metric: metric,
      filters: { policy_id: policy_id, currency: "RUB" },
      group_by: %i[provider_id role]
    ).rows.sum(&:value)
  end

  def payout_signature(snapshot)
    {
      id: snapshot.id,
      status: snapshot.status,
      attempts: snapshot.attempts.map do |attempt|
        [attempt.provider_id, attempt.role, attempt.operation_id, attempt.phase, attempt.outcome&.status]
      end,
      primary_provider_id: snapshot.primary_provider_id,
      settlement_provider_id: snapshot.settlement_provider_id,
      provider_interaction_count: snapshot.provider_interaction_count,
      recovery_schedule: snapshot.recovery_schedule&.to_h
    }
  end
end
