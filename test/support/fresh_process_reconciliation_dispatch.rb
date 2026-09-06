# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "json"
require "ruby_routing"

class FreshProcessReconciliationClock
  def initialize
    @now = Time.utc(2026, 9, 1, 0, 0, 0).freeze
    @monotonic = 0
  end

  def now
    @now
  end

  def monotonic
    @monotonic
  end

  def monotonic_reference_for(wall_time)
    @monotonic + Rational(wall_time.utc.to_r - @now.to_r)
  end
end

class FreshProcessReconciliationBlockingProvider
  def initialize(gate)
    @gate = gate
  end

  def initiate(request)
    puts JSON.generate(
      event: "initiate_started",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id
    )
    STDOUT.flush
    @gate.pop
    raise "reconciliation crash probe must terminate before provider completion"
  end

  def resolve(_request)
    raise "reconciliation crash probe must not resolve before process death"
  end
end

path, payout_id = ARGV
abort "usage: fresh_process_reconciliation_dispatch.rb JOURNAL_PATH PAYOUT_ID" unless path && payout_id

intent = RubyRouting::PayoutIntent.new(
  id: payout_id,
  money: RubyRouting::Money.new(100, "RUB")
)
policy = RubyRouting::RoutingPolicy.new(
  id: "ptz6-fresh-reconciliation-policy",
  epoch: "1",
  measure: :count,
  targets: { "A" => 1, "B" => 1 },
  recovery: RubyRouting::RecoveryPolicy.new(max_operations: 2, ttl_seconds: 1)
)
coordinator = RubyRouting::State::Coordinator.new(
  journal: RubyRouting::State::FileJournal.new(path),
  clock: FreshProcessReconciliationClock.new,
  opportunities: [
    RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    ),
    RubyRouting::ProviderOpportunity.new(provider_id: "B")
  ]
)
gate = Queue.new
app = RubyRouting::Application::Orchestrator.new(
  coordinator: coordinator,
  providers: { "A" => FreshProcessReconciliationBlockingProvider.new(gate) }
)

Thread.new do
  begin
    app.submit(intent: intent, policy: policy)
  rescue StandardError => error
    warn "reconciliation crash probe invocation error: #{error.class}: #{error.message}"
  end
end

while (command = STDIN.gets)
  Process.exit!(137) if command.strip == "crash"
end
