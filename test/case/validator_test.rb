# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseValidatorTest < Minitest::Test
  def test_valid_run_passes_strict_validation
    run = RubyRouting::Case::Runner.new.call
    result = RubyRouting::Case::StrictValidator.new(run).call

    assert result.valid?, result.errors.inspect
    assert_empty result.warnings
  end

  def test_report_tampering_is_rejected_even_when_public_decision_shape_is_valid
    run = RubyRouting::Case::Runner.new.call
    forged_report = RubyRouting::Case::Report.new(run.report.to_h.merge(
      distribution: run.report.to_h.fetch(:distribution).merge(
        "vipay" => run.report.to_h.fetch(:distribution).fetch("vipay").merge(count: 999)
      )
    ))
    forged_run = RubyRouting::Case::Run.new(
      dataset: run.dataset, state: run.state, traffic: run.traffic,
      configuration: run.configuration, simulator: run.simulator, resolver: run.resolver,
      decisions: run.decisions, report: forged_report
    )

    result = RubyRouting::Case::StrictValidator.new(forged_run).call
    refute result.valid?
    assert result.errors.any? { |error| error.include?("report is not recomputable") }
  end

  def test_selection_trace_tampering_is_rejected_by_stateful_replay
    run = RubyRouting::Case::Runner.new.call
    original = run.decisions.first
    selected = original.attempts.last
    forged_selection = original.selection.merge(
      scores: original.selection.fetch(:scores).merge(selected.provider => Rational(999, 1))
    )
    forged_attempt = RubyRouting::Case::Attempt.new(
      provider: selected.provider, decision: selected.decision, reason: selected.reason,
      status: selected.status, latency_sec: selected.latency_sec,
      selection: forged_selection
    )
    forged_decision = RubyRouting::Case::Decision.new(
      operation_id: original.operation_id, selected_provider: original.selected_provider,
      attempts: original.attempts[0...-1] + [forged_attempt],
      simulated_result: original.simulated_result, latency_sec: original.latency_sec,
      selection: forged_selection
    )
    decisions = [forged_decision] + run.decisions.drop(1)
    forged_report = RubyRouting::Case::ReportBuilder.new(
      run.dataset, run.state, run.traffic, run.configuration, decisions
    ).call
    forged_run = RubyRouting::Case::Run.new(
      dataset: run.dataset, state: run.state, traffic: run.traffic,
      configuration: run.configuration, simulator: run.simulator, resolver: run.resolver,
      decisions: decisions, report: forged_report
    )

    result = RubyRouting::Case::StrictValidator.new(forged_run).call
    refute result.valid?
    assert result.errors.any? { |error| error.include?("resolver trace differs") }
  end

  def test_unknown_operation_is_reported_without_validator_crash
    run = RubyRouting::Case::Runner.new.call
    original = run.decisions.first
    forged_decision = RubyRouting::Case::Decision.new(
      operation_id: "unknown-operation", selected_provider: original.selected_provider,
      attempts: original.attempts, simulated_result: original.simulated_result,
      latency_sec: original.latency_sec, selection: original.selection
    )
    forged_run = RubyRouting::Case::Run.new(
      dataset: run.dataset, state: run.state, traffic: run.traffic,
      configuration: run.configuration, simulator: run.simulator, resolver: run.resolver,
      decisions: [forged_decision] + run.decisions.drop(1), report: run.report
    )

    result = RubyRouting::Case::StrictValidator.new(forged_run).call
    refute result.valid?
    assert result.errors.any? { |error| error.include?("unknown operation") }
  end

  def test_hard_skip_cannot_claim_interaction_metadata
    run = RubyRouting::Case::Runner.new.call
    original = run.decisions.find { |decision| decision.operation_id == "op_103" }
    hard_skip = original.attempts.find { |attempt| attempt.status.nil? }
    forged_attempt = RubyRouting::Case::Attempt.new(
      provider: hard_skip.provider, decision: :skipped, reason: hard_skip.reason,
      latency_sec: 1, selection: {}
    )
    attempts = original.attempts.map { |attempt| attempt.equal?(hard_skip) ? forged_attempt : attempt }
    forged_decision = RubyRouting::Case::Decision.new(
      operation_id: original.operation_id, selected_provider: original.selected_provider,
      attempts: attempts, simulated_result: original.simulated_result,
      latency_sec: original.latency_sec, selection: original.selection
    )
    decisions = run.decisions.map { |decision| decision.equal?(original) ? forged_decision : decision }
    forged_run = RubyRouting::Case::Run.new(
      dataset: run.dataset, state: run.state, traffic: run.traffic,
      configuration: run.configuration, simulator: run.simulator, resolver: run.resolver,
      decisions: decisions, report: run.report
    )

    result = RubyRouting::Case::StrictValidator.new(forged_run).call
    refute result.valid?
    assert result.errors.any? { |error| error.include?("hard-skipped attempt") }
  end
end
