# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseScaleCampaignTest < Minitest::Test
  SCALE = 1_000

  def build_run
    base = RubyRouting::Case::Runner.new.call.dataset
    operations = SCALE.times.map do |index|
      RubyRouting::Case::Operation.new(
        operation_id: "scale-#{index}", created_at: Time.utc(2026, 7, 30, 9) + index,
        amount: 1_000, bank: "sberbank", card_brand: nil,
        payout_requisite: { "sbp" => { "phone" => "7900#{index.to_s.rjust(7, "0")}" } }
      )
    end
    traffic_by_provider = { "vipay" => 35, "payflow" => 30, "quickpay" => 25 }
    providers = base.providers.map do |provider|
      next provider unless traffic_by_provider.key?(provider.payment_system)

      RubyRouting::Case::Provider.new(**provider.to_h.merge(
        traffic_percentage: traffic_by_provider.fetch(provider.payment_system)
      ))
    end
    providers.insert(
      -2,
      RubyRouting::Case::Provider.new(**base.providers.first.to_h.merge(
        payment_system: "scale-provider", traffic_percentage: 10, priority: 4,
        note: "synthetic hidden-like scale provider"
      ))
    )
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: base.snapshot_at, gateway: base.gateway, merchant: base.merchant,
      providers: providers, history: [], operations: operations
    )
    profile = RubyRouting::Case::SubmissionProfile.load(
      path: RubyRouting::Case::Runner::DEFAULT_PROFILE, dataset: dataset
    )
    router = RubyRouting::Case::Router.new(dataset, profile: profile)
    decisions = router.run
    report = RubyRouting::Case::ReportBuilder.new(
      dataset, router.state, router.traffic, router.configuration, decisions,
      profile: profile, attempt_ledger: router.attempt_ledger,
      settlement_ledger: router.settlement_ledger
    ).call
    RubyRouting::Case::Run.new(
      dataset: dataset, state: router.state, traffic: router.traffic,
      configuration: router.configuration, profile: profile,
      attempt_ledger: router.attempt_ledger, settlement_ledger: router.settlement_ledger,
      simulator: router.simulator, resolver: router.resolver,
      decisions: decisions, report: report
    )
  end

  def test_hundreds_of_operations_are_strictly_valid_and_byte_deterministic
    first = build_run
    second = build_run

    first_validation = RubyRouting::Case::StrictValidator.new(first).call
    assert first_validation.valid?, first_validation.errors.first(5).inspect
    assert_equal SCALE, first.decisions.length
    assert_equal 5, first.traffic.provider_ids.length
    assert_equal SCALE, first.traffic.total_count
    assert_equal SCALE * 1_000, first.traffic.total_volume
    assert_equal first.traffic.total_count, first.report.to_h.fetch(:assignment_totals).fetch(:count)
    assert_equal(
      JSON.generate(RubyRouting::Case::Serializer.json_value(first.decisions.map(&:to_h))),
      JSON.generate(RubyRouting::Case::Serializer.json_value(second.decisions.map(&:to_h)))
    )
    assert_equal first.report.to_h, second.report.to_h
  end

  def test_scale_artifacts_pass_independent_and_strict_serialized_validation
    run = build_run
    Tempfile.create(["scale-decisions", ".json"]) do |decisions|
      Tempfile.create(["scale-report", ".json"]) do |report|
        RubyRouting::Case::Serializer.write_json(decisions.path, run.decisions.map(&:to_h))
        RubyRouting::Case::Serializer.write_json(report.path, run.report.to_h)

        artifact_result = RubyRouting::Case::SerializedArtifactValidator.new(
          run, decisions_path: decisions.path, report_path: report.path
        ).call
        report_result = RubyRouting::Case::OrganizerReportContractValidator.new(report.path).call

        assert artifact_result.valid?, artifact_result.errors.first(5).inspect
        assert report_result.valid?, report_result.errors.first(5).inspect
        assert_equal SCALE, JSON.parse(File.read(report.path)).fetch("total_operations")
      end
    end
  end
end
