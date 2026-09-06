# frozen_string_literal: true

require "benchmark"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruby_routing"

class BenchmarkProvider
  def initiate(request)
    RubyRouting::ProviderObservation.new(
      observation_id: "benchmark:#{request.operation_id}",
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

def measure(label, iterations)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  iterations.times { |index| yield index }
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  rate = iterations / elapsed
  puts format("%-30s %8d ops %10.4f s %12.1f ops/s", label, iterations, elapsed, rate)
end

puts "Ruby: #{RUBY_DESCRIPTION}"
yjit_enabled = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
puts "YJIT: #{!!yjit_enabled}"

policy = RubyRouting::RoutingPolicy.new(
  id: "benchmark-policy",
  epoch: "1",
  measure: :volume,
  targets: { "A" => 3, "B" => 2, "C" => 1 },
  currency: "RUB"
)
allocation_snapshot = RubyRouting::Routing::AllocationSnapshot.new(
  measures: { "A" => 30_000, "B" => 20_000, "C" => 10_000 }
)
measure("pure volume allocation", 20_000) do
  RubyRouting::Routing::Allocation.choose(
    policy: policy,
    candidates: %w[A B C],
    snapshot: allocation_snapshot,
    incoming_measure: 125
  )
end

coordinator = RubyRouting::State::Coordinator.new(
  opportunities: %w[A B C].map { |id| RubyRouting::ProviderOpportunity.new(provider_id: id) }
)
app = RubyRouting::Application::Orchestrator.new(
  coordinator: coordinator,
  providers: { "A" => BenchmarkProvider.new, "B" => BenchmarkProvider.new, "C" => BenchmarkProvider.new }
)
measure("coordinator lifecycle", 2_000) do |index|
  intent = RubyRouting::PayoutIntent.new(
    id: "benchmark-#{index}",
    money: RubyRouting::Money.new(125, "RUB")
  )
  app.submit(intent: intent, policy: policy)
end

facts = coordinator.facts
measure("fact analytics replay", 250) do
  RubyRouting::Projections::Replay.analytics(facts)
end
puts "Facts replayed: #{facts.length}"
