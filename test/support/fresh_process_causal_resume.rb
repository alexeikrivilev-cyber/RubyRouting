# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "json"
require "ruby_routing"

class CausalResumeProvider
  attr_reader :calls

  def initialize(provider_id, outcome)
    @provider_id = provider_id
    @outcome = outcome
    @calls = []
  end

  def initiate(request)
    @calls << [:initiate, request.operation_id]
    if @provider_id == "A"
      raise "fresh causal resume must not initiate provider A"
    end

    RubyRouting::ProviderObservation.new(
      observation_id: "ptz6-fresh-resume:#{@provider_id}:#{request.operation_id}",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: @outcome
    )
  end

  def resolve(request)
    @calls << [:resolve, request.operation_id]
    RubyRouting::ProviderObservation.new(
      observation_id: "ptz6-fresh-resume:#{@provider_id}:resolve:#{request.operation_id}",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
    )
  end
end

path, payout_id = ARGV
abort "usage: fresh_process_causal_resume.rb JOURNAL_PATH PAYOUT_ID" unless path && payout_id

intent = RubyRouting::PayoutIntent.new(
  id: payout_id,
  money: RubyRouting::Money.new(100, "RUB")
)
policy = RubyRouting::RoutingPolicy.new(
  id: "ptz6-fresh-process-policy",
  epoch: "1",
  measure: :count,
  targets: { "A" => 1, "B" => 1 },
  max_attempts: 2
)
coordinator = RubyRouting::State::Coordinator.new(
  journal: RubyRouting::State::FileJournal.new(path)
)
providers = {
  "A" => CausalResumeProvider.new("A", RubyRouting::NormalizedOutcome.success(attribution: :provider)),
  "B" => CausalResumeProvider.new("B", RubyRouting::NormalizedOutcome.success(attribution: :provider))
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
  attempts: result.payout.attempts.map do |attempt|
    { provider_id: attempt.provider_id, operation_id: attempt.operation_id, phase: attempt.phase }
  end,
  fact_counts: fact_counts.transform_keys(&:to_s)
)
