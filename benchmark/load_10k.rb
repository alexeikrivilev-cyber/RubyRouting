# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruby_routing"

class LoadBenchmarkProvider
  def initiate(request)
    RubyRouting::ProviderObservation.new(
      observation_id: "load:#{request.operation_id}",
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

iterations = 10_000
policy = RubyRouting::RoutingPolicy.new(
  id: "load-policy",
  epoch: "1",
  measure: :count,
  targets: { "A" => 1, "B" => 1 }
)
coordinator = RubyRouting::State::Coordinator.new(
  opportunities: %w[A B].map { |id| RubyRouting::ProviderOpportunity.new(provider_id: id) }
)
provider = LoadBenchmarkProvider.new
app = RubyRouting::Application::Orchestrator.new(
  coordinator: coordinator,
  providers: { "A" => provider, "B" => provider }
)

started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
iterations.times do |index|
  intent = RubyRouting::PayoutIntent.new(
    id: "load-#{index}",
    money: RubyRouting::Money.new(100, "RUB")
  )
  result = app.submit(intent: intent, policy: policy)
  raise "unexpected load result #{result.status}" unless result.status == :success
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

puts "Ruby: #{RUBY_DESCRIPTION}"
puts format("10k coordinator lifecycle %0.4f s %0.1f ops/s", elapsed, iterations / elapsed)
puts "Facts: #{coordinator.facts.length}"
