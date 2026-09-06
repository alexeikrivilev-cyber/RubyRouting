# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseRunnerTest < Minitest::Test
  ROOT = File.expand_path("../../", __dir__)

  def runner(simulator: RubyRouting::Case::DeterministicSimulator.new)
    RubyRouting::Case::Runner.new(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json"),
      simulator: simulator
    )
  end

  def test_routes_public_queue_and_hits_authoritative_goldens
    run = runner.call
    selected = run.decisions.to_h { |decision| [decision.operation_id, decision.selected_provider] }
    reference = JSON.parse(File.read(File.join(ROOT, "data/reference_decisions.json")))

    assert_equal 10, selected.length
    reference.fetch("deterministic_cases").each do |golden|
      assert_equal golden.fetch("required_provider"), selected.fetch(golden.fetch("operation_id"))
    end
    assert_equal 385_800, run.report.to_h.fetch(:dataset).fetch(:queue_volume)
    assert_equal 10, run.report.to_h.fetch(:total_operations)
    assert_equal(
      { from: "2026-07-30T06:05:00Z", to: "2026-07-30T06:09:30Z" },
      run.report.to_h.fetch(:period)
    )
    assert_equal Rational(1, 1), run.report.to_h.fetch(:success_metrics).fetch(:rate)
    assert_equal 0, run.report.to_h.fetch(:fallbacks).fetch(:count)
    assert_equal 100, run.report.to_h.fetch(:history).fetch(:rows)
    assert_equal run.dataset.history.sum(&:amount), run.report.to_h.fetch(:history).fetch(:volume)
    assert_equal Rational(1, 1), run.report.to_h.fetch(:history).fetch(:by_provider).values.sum { |item| item.fetch(:volume_share) }
    assert_equal "calibration/trends only; not current eligibility truth", run.report.to_h.fetch(:history).fetch(:role)
  end

  def test_report_explains_hard_exclusions_and_fallbacks_without_private_input
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: { ["op_101", "vipay"] => :rejected }
    )
    run = runner(simulator: simulator).call
    report = run.report.to_h
    explanation = report.fetch(:explanations).fetch("op_101")

    assert_equal "payflow", explanation.fetch(:selected_provider)
    assert_equal "selected", explanation.fetch(:selected_reason)
    assert_equal "vipay", explanation.fetch(:primary_assignment_provider)
    assert_equal "provider_rejected", explanation.fetch(:primary_assignment_reason)
    assert explanation.fetch(:fallback_continued)
    assert_equal "vipay", explanation.fetch(:failed_attempts).first.fetch(:provider)
    assert report.fetch(:utilization).fetch("payflow").key?(:daily_approved)
    assert report.fetch(:deviation_causes).fetch("quickpay").key?(:hard_forced_assignments)
    assert report.fetch(:attempt_distribution).fetch("vipay").fetch(:outcomes).key?(:rejected)
    assert report.fetch(:deviation_causes).fetch("vipay").key?(:hard_exclusions)
    refute JSON.generate(report).include?("7900")
    payflow_gap = report.fetch(:recommendations).find do |recommendation|
      recommendation[:kind] == "count_target_unmet" && recommendation[:provider] == "payflow"
    end
    refute_nil payflow_gap
    refute_empty payflow_gap.fetch(:evidence).fetch(:causes).fetch(:hard_exclusions)
    assert_includes payflow_gap.fetch(:action), "hard eligibility"
  end

  def test_report_identifies_hard_forced_target_infeasibility
    dataset = runner.call.dataset
    provider_ids = dataset.providers.map(&:payment_system)
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: provider_ids,
      count_share: { "quickpay" => Rational(1, 10) },
      volume_share: { "quickpay" => Rational(1, 10) }
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: provider_ids, targets: targets,
      weights: { count: 1, volume: 1 }, terminal_provider_id: "spacepayments",
      source: "test/infeasible-target"
    )
    run = RubyRouting::Case::Runner.new(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json"),
      configuration: configuration
    ).call
    entry = run.report.to_h.fetch(:infeasibility).find { |item| item[:provider] == "quickpay" }

    refute_nil entry
    assert_operator entry.fetch(:hard_forced_assignments), :>, 0
    assert_includes entry.fetch(:reason), "hard eligibility"
    recommendation_present = run.report.to_h.fetch(:recommendations).any? do |recommendation|
      recommendation[:kind] == "target_infeasible_hard_forced" && recommendation[:provider] == "quickpay"
    end
    assert recommendation_present
    recommendation = run.report.to_h.fetch(:recommendations).find do |item|
      item[:kind] == "target_infeasible_hard_forced" && item[:provider] == "quickpay"
    end
    assert_includes recommendation.fetch(:action), "alternatives"
    refute_includes recommendation.fetch(:action), "expand hard eligibility/capacity for this provider"
  end

  def test_same_inputs_are_byte_equivalent
    first = runner.call
    second = runner.call
    assert_equal(
      JSON.generate(first.decisions.map(&:to_h)),
      JSON.generate(second.decisions.map(&:to_h))
    )
    assert_equal first.report.to_h, second.report.to_h
  end

  def test_simulator_rejects_malformed_seed_outcomes_and_structured_keys
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::DeterministicSimulator.new(seed: false)
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::DeterministicSimulator.new(outcomes: false)
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::DeterministicSimulator.new(outcomes: { "op_101" => :approved })
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::DeterministicSimulator.new(outcomes: { [{}, "vipay"] => :approved })
    end
  end

  def test_rejected_provider_is_skipped_and_next_provider_is_selected
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: { ["op_101", "vipay"] => :rejected }
    )
    decision = runner(simulator: simulator).call.decisions.find { |item| item.operation_id == "op_101" }

    assert_equal "payflow", decision.selected_provider
    assert_equal ["vipay", "payflow"], decision.attempts.map(&:provider).first(2)
    assert_equal "provider_rejected", decision.attempts.first.reason
    assert_equal :selected, decision.attempts.first.decision
    assert_equal :attempted_rejected, decision.attempts.first.classification
    assert decision.attempts.first.attempted?
    assert_equal 1, runner(simulator: simulator).call.report.to_h.fetch(:outcomes).fetch("rejected")
  end

  def test_external_decisions_are_minimal_while_internal_attempts_retain_classification_and_trace
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: { ["op_101", "vipay"] => :expired }
    )
    run = runner(simulator: simulator).call
    decision = run.decisions.find { |item| item.operation_id == "op_101" }

    assert_equal :attempted_expired, decision.attempts.first.classification
    assert_equal :selected, decision.attempts.first.decision
    assert decision.attempts.first.selection
    refute decision.to_h.key?(:selection)
    refute decision.to_h.fetch(:attempts).first.key?(:selection)
    assert_equal "selected", decision.to_h.fetch(:attempts).first.fetch(:decision)
  end

  def test_assignment_attempt_and_settlement_ledgers_remain_distinct_on_fallback
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: { ["op_101", "vipay"] => :rejected }
    )
    run = runner(simulator: simulator).call

    assert_equal "payflow", run.decisions.find { |item| item.operation_id == "op_101" }.selected_provider
    assert_equal 10, run.traffic.total_count
    assert_equal 4, run.traffic.count_by_provider.fetch("vipay")
    assert_equal 4, run.attempt_ledger.count_by_provider.fetch("vipay")
    assert_equal 3, run.settlement_ledger.count_by_provider.fetch("payflow")
    assert_equal 3, run.settlement_ledger.count_by_provider.fetch("vipay")
    assert_equal 10, run.attempt_ledger.by_outcome.fetch(:approved)
    assert_equal 1, run.attempt_ledger.by_outcome.fetch(:rejected)
    report = run.report.to_h
    assert_equal run.traffic.distribution, report.fetch(:assignment_distribution)
    assert_equal run.settlement_ledger.distribution, report.fetch(:settlement_distribution)
    assert_equal run.attempt_ledger.distribution, report.fetch(:attempt_distribution)
    assert RubyRouting::Case::StrictValidator.new(run).call.valid?
  end

  def test_expiry_is_simulation_only_and_falls_back
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: { ["op_101", "vipay"] => :expired }
    )
    decision = runner(simulator: simulator).call.decisions.find { |item| item.operation_id == "op_101" }

    assert_equal "payflow", decision.selected_provider
    assert_equal :expired, decision.attempts.first.status
    assert_equal "provider_expired", decision.attempts.first.reason
    assert_equal 1, runner(simulator: simulator).call.report.to_h.fetch(:outcomes).fetch("expired")
  end

  def test_external_exhaustion_uses_configured_terminal_provider
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: {
        ["op_101", "vipay"] => :rejected,
        ["op_101", "payflow"] => :rejected,
        ["op_101", "quickpay"] => :rejected
      }
    )
    run = runner(simulator: simulator).call
    decision = run.decisions.find { |item| item.operation_id == "op_101" }

    assert_equal "spacepayments", decision.selected_provider
    assert_equal :selected, decision.attempts.last.decision
    assert_equal "external_providers_exhausted", decision.attempts.last.reason
    assert_equal :approved, decision.attempts.last.status
    assert run.report.to_h.fetch(:explanations).fetch("op_101").fetch(:terminal_fallback)
  end

  def test_terminal_non_approval_is_a_final_decision_without_successful_route_accounting
    %i[rejected expired].each do |terminal_status|
      simulator = RubyRouting::Case::DeterministicSimulator.new(
        outcomes: {
          ["op_101", "vipay"] => :rejected,
          ["op_101", "payflow"] => :rejected,
          ["op_101", "quickpay"] => :rejected,
          ["op_101", "spacepayments"] => terminal_status
        }
      )
      run = runner(simulator: simulator).call
      decision = run.decisions.find { |item| item.operation_id == "op_101" }

      assert_equal "spacepayments", decision.selected_provider
      assert_equal terminal_status.to_s, decision.simulated_result
      assert_equal :selected, decision.attempts.last.decision
      assert_equal terminal_status, decision.attempts.last.status
      assert_equal 1, run.report.to_h.fetch(:final_outcomes).fetch(terminal_status.to_s)
      assert_equal run.decisions.length, run.traffic.total_count
      assert_equal run.dataset.operations.sum(&:amount), run.traffic.total_volume
      assert_equal 0, run.state.fetch("spacepayments").daily_approved_amount
      assert_equal 0, run.settlement_ledger.count_by_provider.fetch("spacepayments")
      expected_terminal_outcomes = terminal_status == :rejected ? 4 : 1
      assert_equal expected_terminal_outcomes, run.attempt_ledger.by_outcome.fetch(terminal_status)
      assert RubyRouting::Case::StrictValidator.new(run).call.valid?
    end
  end

  def test_terminal_fallback_rechecks_hard_constraints
    base = runner.call.dataset
    constrained_terminal = RubyRouting::Case::Provider.new(
      payment_system: "spacepayments", status: "active", traffic_percentage: 0,
      priority: 99, limit_amount_min: nil, limit_amount_max: 1,
      daily_amount_limit: nil, daily_approved_amount: 0,
      in_progress_count_limit: nil, in_progress_count: 0,
      in_progress_amount_limit: nil, in_progress_amount: 0,
      available_requisites: 8, conversion_24h: Rational(95, 100),
      avg_latency_sec: 15, banks: [], exclude_banks: false,
      provider_margin_pct: Rational(1, 2), merchant_margin_pct: Rational(3, 2),
      allow_negative_agreement: false
    )
    operation = RubyRouting::Case::Operation.new(
      operation_id: "terminal-hard-limit", created_at: Time.utc(2026, 7, 30, 6),
      amount: 10_000_000, bank: "unknown", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: base.snapshot_at, gateway: base.gateway, merchant: base.merchant,
      providers: base.providers.map { |provider| provider.payment_system == "spacepayments" ? constrained_terminal : provider },
      history: [], operations: [operation]
    )

    error = assert_raises(RubyRouting::Case::OutputError) do
      RubyRouting::Case::Router.new(dataset).run
    end

    assert_includes error.message, "terminal self-provider spacepayments is ineligible"
    assert_includes error.message, "amount_exceeds_limit"
  end

  def test_terminal_only_non_approval_is_not_reported_as_a_fallback_transition
    operation = RubyRouting::Case::Operation.new(
      operation_id: "terminal-only", created_at: Time.utc(2026, 7, 30, 6),
      amount: 300_000, bank: "sberbank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      mode: :approved, outcomes: { ["terminal-only", "spacepayments"] => :rejected }
    )
    queue_dir = Dir.mktmpdir("ruby-routing-terminal-only")
    queue_path = File.join(queue_dir, "queue.json")
    File.write(queue_path, JSON.generate([operation.to_h]))
    run = RubyRouting::Case::Runner.new(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: queue_path, simulator: simulator
    ).call

    assert_equal "spacepayments", run.decisions.first.selected_provider
    assert_equal 1, run.report.to_h.fetch(:attempt_totals).fetch(:count)
    assert_equal 1, run.report.to_h.fetch(:assignment_totals).fetch(:count)
    assert_equal 0, run.report.to_h.fetch(:settlement_totals).fetch(:count)
    assert_equal 0, run.report.to_h.fetch(:fallbacks).fetch(:count)
    refute run.report.to_h.fetch(:explanations).fetch("terminal-only").fetch(:fallback_continued)
    assert_equal 1, run.report.to_h.fetch(:final_outcomes).fetch("rejected")
  ensure
    FileUtils.remove_entry(queue_dir) if queue_dir && File.exist?(queue_dir)
  end

  def test_fallback_does_not_duplicate_hard_exclusions
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: { ["op_102", "payflow"] => :rejected }
    )
    run = runner(simulator: simulator).call
    decision = run.decisions.find { |item| item.operation_id == "op_102" }

    assert_equal "quickpay", decision.selected_provider
    assert_equal decision.attempts.map(&:provider).uniq, decision.attempts.map(&:provider)
    assert RubyRouting::Case::StrictValidator.new(run).call.valid?
  end

  def test_decision_output_provider_identity_does_not_use_structured_to_s_coercion
    structured = Object.new
    def structured.to_s
      "vipay"
    end

    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Attempt.new(
        provider: structured, decision: :selected, reason: "selected", status: :approved,
        latency_sec: 1
      )
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Decision.new(
        operation_id: structured, selected_provider: "vipay", attempts: [],
        simulated_result: "approved", latency_sec: 1
      )
    end
  end
end
