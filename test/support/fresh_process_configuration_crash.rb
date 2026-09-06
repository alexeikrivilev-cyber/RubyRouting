# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ruby_routing"

class CrashAfterProviderReplacementCoordinator < RubyRouting::State::Coordinator
  def replace_provider_opportunities(opportunities)
    super
    # `exit!` is the portable fresh-process equivalent of an abrupt
    # termination in this Windows CI environment: it skips compensation and
    # all Ruby ensure handlers after the durable provider publication.
    Process.exit!(137)
  end
end

class CrashAfterPolicyReplacementRegistry < RubyRouting::PolicyRegistry
  def replace!(policies)
    result = super
    # The registry is process-local and the ConfigurationStore snapshot has
    # not been published yet. This models the second publication boundary.
    Process.exit!(138)
    result
  end
end

class ConfigurationCrashProbeProvider
  def initiate(_request)
    raise "configuration crash probe must not call a provider"
  end

  def resolve(_request)
    raise "configuration crash probe must not call a provider"
  end
end

path = ARGV.fetch(0)
phase = ARGV.fetch(1, "provider")

old_provider = RubyRouting::ProviderOpportunity.new(
  provider_id: "A",
  capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, version: "generation-a")
)
new_provider = RubyRouting::ProviderOpportunity.new(
  provider_id: "B",
  capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true, version: "generation-b")
)
old_policy = RubyRouting::RoutingPolicy.new(
  id: "crash-generation-a",
  epoch: "1",
  measure: :count,
  targets: { "A" => 1 }
)
new_policy = RubyRouting::RoutingPolicy.new(
  id: "crash-generation-b",
  epoch: "1",
  measure: :count,
  targets: { "B" => 1 }
)
old_configuration = RubyRouting::Application::RoutingConfiguration.new(
  policies: [old_policy],
  provider_opportunities: [old_provider]
)
new_configuration = RubyRouting::Application::RoutingConfiguration.new(
  policies: [new_policy],
  provider_opportunities: [new_provider]
)

coordinator_class = if phase == "provider"
  CrashAfterProviderReplacementCoordinator
else
  RubyRouting::State::Coordinator
end
registry = if phase == "policy"
  CrashAfterPolicyReplacementRegistry.new([old_policy])
else
  RubyRouting::PolicyRegistry.new([old_policy])
end
coordinator = coordinator_class.new(journal: RubyRouting::State::FileJournal.new(path))
store = RubyRouting::Application::ConfigurationStore.new(configuration: old_configuration)
RubyRouting::Application::Service.new(
  coordinator: coordinator,
  providers: { "A" => ConfigurationCrashProbeProvider.new },
  policy_registry: registry,
  configuration_store: store
).apply_configuration(new_configuration)
