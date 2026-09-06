# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "json"
require "ruby_routing"

class FreshProviderFailureRecoveryProvider
  attr_reader :calls

  def initialize
    @calls = []
  end

  def initiate(_request)
    raise "fresh provider failure recovery must not initiate a second operation"
  end

  def resolve(request)
    @calls << [:resolve, request.operation_id, request.attempt_id]
    RubyRouting::ProviderObservation.new(
      observation_id: "ptz9-fresh-provider-failure:#{request.operation_id}",
      payout_id: request.payout_id,
      provider_id: request.provider_id,
      operation_id: request.operation_id,
      attempt_id: request.attempt_id,
      outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
    )
  end
end

path, payout_id = ARGV
abort "usage: fresh_process_provider_failure_resume.rb JOURNAL_PATH PAYOUT_ID" unless path && payout_id

coordinator = RubyRouting::State::Coordinator.new(
  journal: RubyRouting::State::FileJournal.new(path)
)
provider = FreshProviderFailureRecoveryProvider.new
service = RubyRouting::Application::Service.new(
  coordinator: coordinator,
  providers: { "A" => provider }
)
due = service.queries.due_work(as_of: coordinator.current_time, limit: 1)
pass = service.recovery_executor.run(limit: 1, as_of: coordinator.current_time)
snapshot = service.queries.payout(payout_id)

puts JSON.generate(
  due: due.map do |item|
    {
      action: item.action.to_s,
      provider_id: item.provider_id,
      operation_id: item.operation_id,
      attempt_id: item.attempt_id,
      reason_code: item.reason_code.to_s,
      due_at: item.due_at
    }
  end,
  pass: pass.to_h,
  calls: provider.calls,
  status: snapshot.status.to_s,
  operation_ids: snapshot.attempts.map(&:operation_id),
  attempt_ids: snapshot.attempts.map(&:attempt_id),
  fact_counts: coordinator.facts.group_by(&:type).transform_values(&:length).transform_keys(&:to_s)
)
