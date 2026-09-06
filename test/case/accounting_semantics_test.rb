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
    assert_equal final, report_distribution
    # The routing-target ledger must reflect the provider that finally won the
    # cascade. Primary assignment remains a separate population below.
    assert_equal final, run.traffic.count_by_provider
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
    assert_equal 1, run.traffic.count_by_provider.fetch("payflow")
    assert_equal 0, run.traffic.count_by_provider.fetch("vipay")
    assert_equal 1, run.settlement_ledger.count_by_provider.fetch("payflow")
    assert_equal 1, run.attempt_ledger.by_outcome.fetch(:expired)
    assert_equal 1, run.attempt_ledger.by_outcome.fetch(:approved)
  end

  def test_base_distribution_is_final_selected_while_assignment_and_settlement_stay_explicit
    run = fallback_run(:rejected)
    report = run.report.to_h

    assert_equal run.primary_assignment_ledger.distribution, report.fetch(:assignment_distribution)
    assert_equal run.decisions.length, report.fetch(:final_selection_totals).fetch(:count)
    assert_equal run.dataset.operations.sum(&:amount), report.fetch(:final_selection_totals).fetch(:volume)
    assert_equal run.settlement_ledger.distribution, report.fetch(:settlement_distribution)
    assert_equal run.attempt_ledger.distribution, report.fetch(:attempt_distribution)
    assert_equal 0, report.fetch(:distribution).fetch("vipay").fetch(:count)
    assert_equal 1, report.fetch(:distribution).fetch("payflow").fetch(:count)
    assert_equal 0, report.fetch(:distribution).fetch("quickpay").fetch(:count)
    assert_equal 1, report.fetch(:settlement_distribution).fetch("payflow").fetch(:count)
    assert_equal 1, report.fetch(:final_selection_distribution).fetch("payflow").fetch(:count)
    assert_equal 1, report.fetch(:attempt_distribution).fetch("vipay").fetch(:outcomes).fetch(:rejected)
  end

  def test_target_causes_and_recommendations_use_the_final_population
    run = fallback_run(:rejected)
    report = run.report.to_h
    total = run.decisions.length
    final_counts = report.fetch(:final_selection_distribution).transform_values { |values| values.fetch(:count) }
    targets = run.configuration.targets.count_share

    final_counts.each do |provider_id, count|
      final_deviation = Rational(count, total) - targets.fetch(provider_id)
      assert_equal(-final_deviation, report.fetch(:deviation_causes).fetch(provider_id).fetch(:target_count_gap))
    end

    recommendations = report.fetch(:recommendation_details)
    assert recommendations.any? { |detail| detail[:provider] == "vipay" && detail[:kind] == "count_target_unmet" }
    assert recommendations.any? { |detail| detail[:provider] == "quickpay" && detail[:kind] == "count_target_unmet" }
  end

  def test_next_primary_resolution_observes_final_target_ledger_after_fallback
    base = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: base.snapshot_at, gateway: base.gateway, merchant: base.merchant,
      providers: base.providers, history: base.history, operations: base.operations.first(2)
    )
    profile = RubyRouting::Case::SubmissionProfile.load(
      path: File.join(ROOT, "data/submission_profile.json"), dataset: dataset
    )
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: { ["op_101", "vipay"] => :rejected }
    )
    router = RubyRouting::Case::Router.new(dataset, profile: profile, simulator: simulator)
    decisions = router.run
    first, second = decisions

    assert_equal "vipay", first.attempts.find { |attempt| attempt.status }.provider
    assert_equal "payflow", first.selected_provider
    selection = second.attempts.find(&:selection).selection
    count_evidence = selection.fetch(:factors).fetch("payflow").find { |factor| factor[:factor] == "count" }

    final_traffic = RubyRouting::Case::TrafficLedger.new(
      dataset.providers.map(&:payment_system), targets: profile.configuration.targets
    )
    final_traffic.record_assignment!(provider_id: first.selected_provider, amount: dataset.operations.first.amount)
    primary_traffic = RubyRouting::Case::TrafficLedger.new(
      dataset.providers.map(&:payment_system), targets: profile.configuration.targets
    )
    primary_traffic.record_assignment!(
      provider_id: first.attempts.find { |attempt| attempt.status }.provider,
      amount: dataset.operations.first.amount
    )
    count_factor = RubyRouting::Case::FactorRegistry.fetch(:count)
    expected_final_raw = count_factor.raw(
      provider_state: router.state.fetch("payflow"), operation: dataset.operations.last,
      traffic: final_traffic, as_of: dataset.operations.last.created_at
    )
    primary_raw = count_factor.raw(
      provider_state: router.state.fetch("payflow"), operation: dataset.operations.last,
      traffic: primary_traffic, as_of: dataset.operations.last.created_at
    )

    assert_equal expected_final_raw, count_evidence.fetch(:raw)
    refute_equal primary_raw, count_evidence.fetch(:raw)
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
      profile: profile, primary_assignment_ledger: router.primary_assignment_ledger,
      attempt_ledger: router.attempt_ledger,
      settlement_ledger: router.settlement_ledger
    ).call

    RubyRouting::Case::Run.new(
      dataset: one_operation, state: router.state, traffic: router.traffic,
      primary_assignment_ledger: router.primary_assignment_ledger,
      configuration: router.configuration, simulator: router.simulator,
      resolver: router.resolver, decisions: decisions, report: report,
      profile: profile, attempt_ledger: router.attempt_ledger,
      settlement_ledger: router.settlement_ledger
    )
  end
end
