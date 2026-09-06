# frozen_string_literal: true

require "objspace"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruby_routing"

class DegradationMetricsProvider
  attr_reader :provider_id

  def initialize(provider_id:, safe_failure_every: nil)
    @provider_id = provider_id.freeze
    @safe_failure_every = safe_failure_every
    @initiation_count = 0
    @sequence = 0
    @operations = {}
  end

  def initiate(request)
    operation = @operations[request.idempotency_key]
    unless operation
      @initiation_count += 1
      operation = @operations[request.idempotency_key] = {
        outcome: next_outcome
      }
    end
    observation(request, operation.fetch(:outcome))
  end

  def resolve(request)
    operation = @operations.fetch(request.idempotency_key)
    operation[:outcome] = RubyRouting::NormalizedOutcome.success(attribution: :provider)
    observation(request, operation.fetch(:outcome))
  end

  private

  def next_outcome
    if @safe_failure_every && (@initiation_count % @safe_failure_every).zero?
      RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider)
    else
      RubyRouting::NormalizedOutcome.success(attribution: :provider)
    end
  end

  def observation(request, outcome)
    @sequence += 1
    RubyRouting::ProviderObservation.new(
      observation_id: "degradation-metrics:#{provider_id}:#{@sequence}",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: outcome,
      sequence: @sequence
    )
  end
end

PAYOUT_COUNT = 2_000
SEED = 20_260_829
policy = RubyRouting::RoutingPolicy.new(
  id: "degradation-metrics-policy",
  epoch: SEED.to_s,
  measure: :count,
  targets: { "A" => 1, "B" => 1, "C" => 1 },
  recovery: RubyRouting::RecoveryPolicy.new(max_operations: 3, max_switches: 2)
)
opportunities = %w[A B C].map { |provider_id| RubyRouting::ProviderOpportunity.new(provider_id: provider_id) }
providers = {
  "A" => DegradationMetricsProvider.new(provider_id: "A", safe_failure_every: 5),
  "B" => DegradationMetricsProvider.new(provider_id: "B", safe_failure_every: 7),
  "C" => DegradationMetricsProvider.new(provider_id: "C")
}
coordinator = RubyRouting::State::Coordinator.new(opportunities: opportunities)
app = RubyRouting::Application::Orchestrator.new(coordinator: coordinator, providers: providers)

GC.start
before_bytes = ObjectSpace.memsize_of_all
before_slots = GC.stat.fetch(:heap_live_slots)
started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
PAYOUT_COUNT.times do |index|
  result = app.submit(
    intent: RubyRouting::PayoutIntent.new(
      id: "degradation-metrics-#{index}",
      money: RubyRouting::Money.new(100, "RUB")
    ),
    policy: policy
  )
  raise "seed=#{SEED} payout=#{index} did not settle: #{result.status}" unless result.status == :success
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
GC.start
after_bytes = ObjectSpace.memsize_of_all
after_slots = GC.stat.fetch(:heap_live_slots)

analytics = RubyRouting::Projections::Analytics.from_facts(coordinator.facts)
attempts = analytics.attempt_count_by_payout.values.sum
amplification = Rational(attempts, PAYOUT_COUNT)

puts "Ruby: #{RUBY_DESCRIPTION}"
puts "Seed: #{SEED}"
puts "Payouts: #{PAYOUT_COUNT}"
puts format("Lifecycle: %.4f s", elapsed)
puts "Attempts: #{attempts}"
puts "Attempt amplification: #{amplification} attempts/payout"
puts "Fallback payouts: #{analytics.fallback_recovery_count}"
puts "Successful fallback recoveries: #{analytics.successful_fallback_recovery_count}"
puts "Max attempts/payout: #{analytics.attempt_count_by_payout.values.max}"
puts "ObjectSpace memsize delta: #{after_bytes - before_bytes} bytes"
puts "GC heap live-slot delta: #{after_slots - before_slots} slots"
