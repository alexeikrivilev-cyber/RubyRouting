# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseAccountingSemanticsTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_primary_final_and_settlement_populations_remain_distinct_for_rejected_primary
    run = fallback_run(:rejected)
    decision = run.decisions.fetch(0)
    provider_ids = run.dataset.providers.map(&:payment_system)

    primary_provider = decision.attempts.find { |attempt| attempt.decision == :selected }.provider
    final_provider = decision.selected_provider
    settlement_provider = decision.simulated_result == "approved" ? final_provider : nil

    primary = provider_ids.to_h { |provider_id| [provider_id, provider_id == primary_provider ? 1 : 0] }
    final = provider_ids.to_h { |provider_id| [provider_id, provider_id == final_provider ? 1 : 0] }
    settlement = provider_ids.to_h { |provider_id| [provider_id, provider_id == settlement_provider ? 1 : 0] }
    report_distribution = run.report.to_h.fetch(:distribution).to_h do |provider_id, values|
      [provider_id, values.fetch(:count)]
    end

    assert_equal "vipay", primary_provider
    assert_equal "payflow", final_provider
    assert_equal "payflow", settlement_provider
    refute_equal primary, final
    assert_equal final, settlement
    assert_equal primary, report_distribution
    assert_equal primary, run.traffic.count_by_provider
    assert_equal settlement, run.settlement_ledger.count_by_provider
    assert_equal 1, primary.values.sum
    assert_equal 1, final.values.sum
    assert_equal 1, settlement.values.sum
  end

  def test_expired_primary_has_the_same_three_explicit_populations
    run = fallback_run(:expired)
    decision = run.decisions.fetch(0)

    assert_equal "vipay", decision.attempts.find { |attempt| attempt.decision == :selected }.provider
    assert_equal "payflow", decision.selected_provider
    assert_equal 1, run.traffic.count_by_provider.fetch("vipay")
    assert_equal 1, run.settlement_ledger.count_by_provider.fetch("payflow")
    assert_equal 1, run.attempt_ledger.by_outcome.fetch(:expired)
    assert_equal 1, run.attempt_ledger.by_outcome.fetch(:approved)
  end

  def test_base_distribution_is_explicitly_primary_while_rich_ledgers_keep_final_and_settlement
    run = fallback_run(:rejected)
    report = run.report.to_h

    assert_equal run.traffic.distribution, report.fetch(:assignment_distribution)
    assert_equal run.settlement_ledger.distribution, report.fetch(:settlement_distribution)
    assert_equal run.attempt_ledger.distribution, report.fetch(:attempt_distribution)
    assert_equal 1, report.fetch(:distribution).fetch("vipay").fetch(:count)
    assert_equal 0, report.fetch(:distribution).fetch("payflow").fetch(:count)
    assert_equal 1, report.fetch(:settlement_distribution).fetch("payflow").fetch(:count)
    assert_equal 1, report.fetch(:attempt_distribution).fetch("vipay").fetch(:outcomes).fetch(:rejected)
  end

  private

  def fallback_run(primary_status)
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    operation = dataset.operations.fetch(0)
    one_operation = RubyRouting::Case::Dataset.new(
      snapshot_at: dataset.snapshot_at, gateway: dataset.gateway, merchant: dataset.merchant,
      providers: dataset.providers, history: dataset.history, operations: [operation]
    )
    profile = RubyRouting::Case::SubmissionProfile.load(
      path: File.join(ROOT, "data/submission_profile.json"), dataset: one_operation
    )
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: {
        [operation.operation_id, "vipay"] => primary_status,
        [operation.operation_id, "payflow"] => :approved
      }
    )
    router = RubyRouting::Case::Router.new(one_operation, profile: profile, simulator: simulator)
    decisions = router.run
    report = RubyRouting::Case::ReportBuilder.new(
      one_operation, router.state, router.traffic, router.configuration, decisions,
      profile: profile, attempt_ledger: router.attempt_ledger,
      settlement_ledger: router.settlement_ledger
    ).call

    RubyRouting::Case::Run.new(
      dataset: one_operation, state: router.state, traffic: router.traffic,
      configuration: router.configuration, simulator: router.simulator,
      resolver: router.resolver, decisions: decisions, report: report,
      profile: profile, attempt_ledger: router.attempt_ledger,
      settlement_ledger: router.settlement_ledger
    )
  end
end
