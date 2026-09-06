# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

class ConfigurationCrashConsistencyTest < Minitest::Test
  def test_fresh_process_crash_after_provider_publication_restarts_only_with_a_coherent_generation
    Dir.mktmpdir("ruby-routing-configuration-crash") do |directory|
      clock = TestSupport::ControlledClock.new
      old_configuration = configuration("A", "crash-generation-a", "generation-a")
      new_configuration = configuration("B", "crash-generation-b", "generation-b")
      %w[provider policy].each do |phase|
        run_crash_case(directory, phase, old_configuration, new_configuration, clock)
      end
    end
  end

  private

  def run_crash_case(directory, phase, old_configuration, new_configuration, clock)
    crashed_path = File.join(directory, "#{phase}-crashed.jsonl")
    old_restart_path = File.join(directory, "#{phase}-old-restart.jsonl")
    new_restart_path = File.join(directory, "#{phase}-new-restart.jsonl")
    payout = RubyRouting::PayoutIntent.new(
      id: "configuration-crash-payout-#{phase}",
      money: RubyRouting::Money.new(100, "RUB")
    )
    initial = RubyRouting::State::Coordinator.new(
      clock: clock,
      journal: RubyRouting::State::FileJournal.new(crashed_path),
      opportunities: old_configuration.provider_opportunities
    )
    initial.prepare_and_commit_decision(intent: payout, policy: old_configuration.policies.first)

    run_crash_probe(crashed_path, phase)

    crashed = RubyRouting::State::Coordinator.new(
      clock: clock,
      journal: RubyRouting::State::FileJournal.new(crashed_path)
    )
    assert_equal ["B"], crashed.provider_opportunities.map(&:provider_id)
    assert_equal :pending, crashed.payout_snapshot(payout.id).status
    assert_equal "A", crashed.payout_snapshot(payout.id).ownership.provider_id

    FileUtils.cp(crashed_path, old_restart_path)
    FileUtils.cp(crashed_path, new_restart_path)

    old_recovered = RubyRouting::State::Coordinator.new(
      clock: clock,
      journal: RubyRouting::State::FileJournal.new(old_restart_path)
    )
    old_store = RubyRouting::Application::ConfigurationStore.new(configuration: old_configuration)
    old_service = RubyRouting::Application::Service.new(
      coordinator: old_recovered,
      providers: { "A" => SuccessProvider.new },
      configuration_store: old_store
    )

    assert_equal ["A"], old_service.queries.providers.map(&:provider_id)
    assert_equal :valid, old_service.queries.configuration_status
    assert_equal :pending, old_service.queries.get_payout(payout.id).status
    assert_equal "A", old_service.queries.get_payout(payout.id).ownership.provider_id
    old_result = old_service.resume(payout_id: payout.id, policy: old_configuration.policies.first)
    assert_equal :success, old_result.status
    assert_equal "A", old_result.payout.settlement_provider_id

    new_recovered = RubyRouting::State::Coordinator.new(
      clock: clock,
      journal: RubyRouting::State::FileJournal.new(new_restart_path)
    )
    new_store = RubyRouting::Application::ConfigurationStore.new(configuration: new_configuration)
    new_service = RubyRouting::Application::Service.new(
      coordinator: new_recovered,
      providers: { "B" => SuccessProvider.new },
      configuration_store: new_store
    )

    assert_equal ["B"], new_service.queries.providers.map(&:provider_id)
    assert_equal :valid, new_service.queries.configuration_status
    new_payout = RubyRouting::PayoutIntent.new(
      id: "configuration-crash-new-payout-#{phase}",
      money: RubyRouting::Money.new(100, "RUB")
    )
    new_result = new_service.submit(intent: new_payout, policy: new_configuration.policies.first)
    assert_equal :success, new_result.status
    assert_equal "B", new_result.payout.settlement_provider_id
  end

  def run_crash_probe(path, phase)
    script = File.expand_path("../support/fresh_process_configuration_crash.rb", __dir__)
    _stdout, _stderr, status = Open3.capture3(RbConfig.ruby, script, path, phase)
    refute status.success?, "the crash probe unexpectedly completed normally"
  end

  def configuration(provider_id, policy_id, version)
    provider = RubyRouting::ProviderOpportunity.new(
      provider_id: provider_id,
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, version: version)
    )
    policy = RubyRouting::RoutingPolicy.new(
      id: policy_id,
      epoch: "1",
      measure: :count,
      targets: { provider_id => 1 }
    )
    RubyRouting::Application::RoutingConfiguration.new(
      policies: [policy],
      provider_opportunities: [provider]
    )
  end

  class SuccessProvider
    def initiate(request)
      observation(request, "initiate")
    end

    def resolve(request)
      observation(request, "resolve")
    end

    private

    def observation(request, source)
      RubyRouting::ProviderObservation.new(
        observation_id: "configuration-crash-#{source}-#{request.operation_id}",
        payout_id: request.payout_id,
        provider_id: request.provider_id,
        operation_id: request.operation_id,
        attempt_id: request.attempt_id,
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
      )
    end
  end
end
