# frozen_string_literal: true

require "json"
require_relative "../../lib/ruby_routing"

class FreshProcessSuccessProvider
  def initiate(request)
    observation(request, "initiate")
  end

  def resolve(request)
    observation(request, "resolve")
  end

  private

  def observation(request, phase)
    RubyRouting::ProviderObservation.new(
      observation_id: "fresh-process:#{request.operation_id}:#{phase}",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
    )
  end
end

path, payout_id = ARGV
abort "usage: fresh_process_resume.rb JOURNAL_PATH PAYOUT_ID" unless path && payout_id

coordinator = RubyRouting::State::Coordinator.new(
  journal: RubyRouting::State::FileJournal.new(path)
)
service = RubyRouting::Application::Service.new(
  coordinator: coordinator,
  providers: { "A" => FreshProcessSuccessProvider.new }
)
result = service.resume(payout_id: payout_id)

puts JSON.generate(
  status: result.status,
  action: result.action,
  attempt_count: result.payout.attempt_count,
  operation_id: result.payout.attempts.first&.operation_id,
  ownership: result.payout.ownership&.operation_id
)
