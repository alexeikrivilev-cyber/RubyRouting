# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "json"
require "ruby_routing"

class FatalApplyCoordinator < RubyRouting::State::Coordinator
  def apply_observation(*_arguments, **_keywords)
    raise NotImplementedError, "fatal apply-path process-death probe"
  end
end

class FatalApplyProvider
  def initiate(request)
    puts JSON.generate(
      event: "provider_returned",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id
    )
    STDOUT.flush
    RubyRouting::ProviderObservation.new(
      observation_id: "fatal-apply-provider-return",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
    )
  end

  def resolve(_request)
    raise "fatal apply probe must not resolve before restart"
  end
end

path, payout_id = ARGV
abort "usage: fresh_process_fatal_apply.rb JOURNAL_PATH PAYOUT_ID" unless path && payout_id

intent = RubyRouting::PayoutIntent.new(
  id: payout_id,
  money: RubyRouting::Money.new(100, "RUB")
)
policy = RubyRouting::RoutingPolicy.new(
  id: "ptz10-fatal-apply-policy",
  epoch: "1",
  measure: :count,
  targets: { "A" => 1, "B" => 1 },
  max_attempts: 2
)
coordinator = FatalApplyCoordinator.new(
  journal: RubyRouting::State::FileJournal.new(path),
  opportunities: [
    RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
    ),
    RubyRouting::ProviderOpportunity.new(provider_id: "B")
  ]
)
RubyRouting::Application::Orchestrator.new(
  coordinator: coordinator,
  providers: { "A" => FatalApplyProvider.new }
).submit(intent: intent, policy: policy)
