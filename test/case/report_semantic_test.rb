# frozen_string_literal: true

require "json"
require "tempfile"
require_relative "../test_helper"

class OrganizerReportSemanticValidatorTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_canonical_serialized_report_passes_independent_raw_input_recomputation
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      result = semantic_validator(decisions_path, report_path).call

      assert result.valid?, result.errors.inspect
    end
  end

  def test_fallback_artifact_passes_primary_assignment_accounting_semantics
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    operation = dataset.operations.fetch(0)
    queue = Tempfile.new(["semantic-queue", ".json"])
    queue.write(JSON.generate([operation.to_h]))
    queue.close
    profile = RubyRouting::Case::SubmissionProfile.load(
      path: File.join(ROOT, "data/submission_profile.json"), dataset: dataset
    )
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: {
        [operation.operation_id, "vipay"] => :rejected,
        [operation.operation_id, "payflow"] => :approved
      }
    )
    one_operation = RubyRouting::Case::Dataset.new(
      snapshot_at: dataset.snapshot_at, gateway: dataset.gateway, merchant: dataset.merchant,
      providers: dataset.providers, history: dataset.history, operations: [operation]
    )
    router = RubyRouting::Case::Router.new(one_operation, profile: profile, simulator: simulator)
    decisions = router.run
    report = RubyRouting::Case::ReportBuilder.new(
      one_operation, router.state, router.traffic, router.configuration, decisions,
      profile: profile, attempt_ledger: router.attempt_ledger,
      settlement_ledger: router.settlement_ledger
    ).call

    Tempfile.create(["semantic-decisions", ".json"]) do |decisions_file|
      Tempfile.create(["semantic-report", ".json"]) do |report_file|
        RubyRouting::Case::Serializer.write_json(decisions_file.path, decisions.map(&:to_h))
        RubyRouting::Case::Serializer.write_json(report_file.path, report.to_h)

        result = RubyRouting::Case::OrganizerReportSemanticValidator.new(
          providers_path: File.join(ROOT, "data/providers.json"),
          queue_path: queue.path,
          profile_path: File.join(ROOT, "data/submission_profile.json"),
          decisions_path: decisions_file.path,
          report_path: report_file.path
        ).call

        assert result.valid?, result.errors.inspect
      end
    end
  ensure
    queue&.unlink
  end

  def test_shape_valid_business_tampering_is_rejected_without_report_builder_oracle
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      baseline = JSON.parse(File.read(report_path))
      mutations = {
        "total_operations" => ->(report) { report["total_operations"] += 1 },
        "distribution count" => ->(report) { report.fetch("distribution").fetch("vipay")["count"] += 1 },
        "distribution share" => ->(report) { report.fetch("distribution").fetch("vipay")["share_pct"] = 99.0 },
        "distribution target" => ->(report) { report.fetch("distribution").fetch("vipay")["target_pct"] = 99.0 },
        "utilization used" => ->(report) { report.fetch("projected_daily_utilization").fetch("payflow")["used"] += 1 },
        "utilization percentage" => ->(report) { report.fetch("projected_daily_utilization").fetch("payflow")["utilization_pct"] = 1.0 },
        "period" => ->(report) { report["period"] = "2099-01-01" }
      }

      mutations.each do |label, mutation|
        forged = Marshal.load(Marshal.dump(baseline))
        mutation.call(forged)
        File.write(report_path, JSON.generate(forged))

        result = semantic_validator(decisions_path, report_path).call

        refute result.valid?, "expected semantic rejection for #{label}"
      end
    end
  end

  def test_malformed_raw_inputs_return_validation_errors_instead_of_raising
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      Tempfile.create(["semantic-providers", ".json"]) do |providers_file|
        providers = JSON.parse(File.read(File.join(ROOT, "data/providers.json")))
        providers.fetch("providers").first["traffic_percentage"] = "not-exact"
        providers_file.write(JSON.generate(providers))
        providers_file.close

        result = semantic_validator(
          decisions_path, report_path, providers_path: providers_file.path
        ).call

        refute result.valid?
        assert_includes result.errors.join("; "), "traffic_percentage must be exact"
      end
    end
  end

  def test_malformed_raw_queue_returns_validation_errors_instead_of_raising
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      Tempfile.create(["semantic-queue", ".json"]) do |queue_file|
        queue_file.write(JSON.generate([nil]))
        queue_file.close

        result = semantic_validator(
          decisions_path, report_path, queue_path: queue_file.path
        ).call

        refute result.valid?
        assert_includes result.errors.join("; "), "queue input contains an invalid operation"
      end
    end
  end

  def test_empty_queue_has_zero_distribution_shares
    Tempfile.create(["semantic-empty-queue", ".json"]) do |queue_file|
      queue_file.write("[]")
      queue_file.close
      run = RubyRouting::Case::Runner.new(queue_path: queue_file.path).call

      with_artifacts(run) do |decisions_path, report_path|
        result = semantic_validator(
          decisions_path, report_path, queue_path: queue_file.path
        ).call

        assert result.valid?, result.errors.inspect
        assert_equal 0, JSON.parse(File.read(report_path)).fetch("total_operations")
      end
    end
  end

  private

  def with_artifacts(run)
    Tempfile.create(["semantic-decisions", ".json"]) do |decisions|
      Tempfile.create(["semantic-report", ".json"]) do |report|
        RubyRouting::Case::Serializer.write_json(decisions.path, run.decisions.map(&:to_h))
        RubyRouting::Case::Serializer.write_json(report.path, run.report.to_h)
        yield decisions.path, report.path
      end
    end
  end

  def semantic_validator(decisions_path, report_path, providers_path: File.join(ROOT, "data/providers.json"),
                         queue_path: File.join(ROOT, "data/operations_queue_10.json"))
    RubyRouting::Case::OrganizerReportSemanticValidator.new(
      providers_path: providers_path,
      queue_path: queue_path,
      profile_path: File.join(ROOT, "data/submission_profile.json"),
      decisions_path: decisions_path,
      report_path: report_path
    )
  end
end
