# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "json"
require "ruby_routing"

path, payout_id = ARGV
abort "usage: fresh_process_causal_due_work.rb JOURNAL_PATH PAYOUT_ID" unless path && payout_id

coordinator = RubyRouting::State::Coordinator.new(
  journal: RubyRouting::State::FileJournal.new(path)
)
work = coordinator.due_work(as_of: coordinator.current_time, limit: 1)
snapshot = coordinator.payout_snapshot(payout_id)

puts JSON.generate(
  due: work.map do |item|
    {
      action: item.action.to_s,
      provider_id: item.provider_id,
      operation_id: item.operation_id,
      attempt_id: item.attempt_id,
      reason_code: item.reason_code.to_s,
      status: item.status.to_s
    }
  end,
  status: snapshot.status.to_s,
  phase: snapshot.attempts.fetch(0).phase.to_s,
  operation_id: snapshot.attempts.fetch(0).operation_id,
  ownership: snapshot.ownership && {
    provider_id: snapshot.ownership.provider_id,
    operation_id: snapshot.ownership.operation_id,
    attempt_id: snapshot.ownership.attempt_id
  }
)
