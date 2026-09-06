# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "json"
require "ruby_routing"

class FreshProcessReconciliationResumeClock
  def initialize
    @now = Time.utc(2026, 9, 1, 0, 0, 1).freeze
    @monotonic = Rational(1)
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

class FreshProcessReconciliationResumeProvider
  attr_reader :calls

  def initialize(provider_id)
    @provider_id = provider_id
    @calls = []
  end

  def initiate(request)
    @calls << [:initiate, request.operation_id]
    RubyRouting::ProviderObservation.new(
      observation_id: "ptz6-fresh-reconciliation-resume:#{@provider_id}:#{request.operation_id}",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
    )
  end

  def resolve(request)
    @calls << [:resolve, request.operation_id]
    RubyRouting::ProviderObservation.new(
      observation_id: "ptz6-fresh-reconciliation-resume:#{@provider_id}:resolve:#{request.operation_id}",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
    )
  end
end

path, payout_id = ARGV
abort "usage: fresh_process_reconciliation_resume.rb JOURNAL_PATH PAYOUT_ID" unless path && payout_id

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
  clock: FreshProcessReconciliationResumeClock.new
)
providers = {
  "A" => FreshProcessReconciliationResumeProvider.new("A"),
  "B" => FreshProcessReconciliationResumeProvider.new("B")
}
result = RubyRouting::Application::Orchestrator.new(
  coordinator: coordinator,
  providers: providers
).resume(payout_id: payout_id, policy: policy)

fact_counts = coordinator.facts.group_by(&:type).transform_values(&:length)
puts JSON.generate(
  status: result.status.to_s,
  action: result.action.to_s,
  calls: providers.values.flat_map(&:calls),
  ownership: result.payout.ownership && {
    provider_id: result.payout.ownership.provider_id,
    operation_id: result.payout.ownership.operation_id,
    attempt_id: result.payout.ownership.attempt_id
  },
  attempts: result.payout.attempts.map do |attempt|
    { provider_id: attempt.provider_id, operation_id: attempt.operation_id, phase: attempt.phase }
  end,
  fact_counts: fact_counts.transform_keys(&:to_s)
)
