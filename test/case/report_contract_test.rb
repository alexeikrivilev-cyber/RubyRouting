# frozen_string_literal: true

require "json"
require_relative "../test_helper"

class OrganizerReportContractTest < Minitest::Test
  def test_finalization_report_has_authoritative_base_projection
    run = RubyRouting::Case::Runner.new.call

    Tempfile.create(["routing-report-contract", ".json"]) do |report_file|
      RubyRouting::Case::Serializer.write_json(report_file.path, run.report.to_h)

      result = RubyRouting::Case::OrganizerReportContractValidator.new(report_file.path).call

      assert result.valid?, result.errors.inspect
      report = JSON.parse(File.read(report_file.path))
      assert_kind_of String, report.fetch("period")
      assert_kind_of Integer, report.fetch("total_operations")
      assert_equal %w[count share_pct target_pct], report.fetch("distribution").fetch("vipay").keys.grep(
        /\A(?:count|share_pct|target_pct)\z/
      ).sort
      assert_kind_of Hash, report.fetch("skip_reasons")
      assert_kind_of Hash, report.fetch("projected_daily_utilization").fetch("vipay")
      assert_kind_of Array, report.fetch("recommendations")
      assert report.fetch("recommendations").all? { |recommendation| recommendation.is_a?(String) }
      assert_kind_of Array, report.fetch("recommendation_details")
      assert_kind_of Hash, report.fetch("assignment_distribution")
      assert_kind_of Hash, report.fetch("settlement_distribution")
    end
  end

  def test_validator_rejects_missing_base_projection_without_report_builder
    report = {
      "period" => "2026-07-30",
      "total_operations" => 1,
      "distribution" => {
        "vipay" => { "count" => 1, "share_pct" => 100.0 }
      },
      "skip_reasons" => {},
      "projected_daily_utilization" => {
        "vipay" => { "used" => 100, "limit" => 1_000, "utilization_pct" => 10.0 }
      },
      "recommendations" => ["review routing capacity"]
    }

    Tempfile.create(["routing-invalid-report", ".json"]) do |report_file|
      File.write(report_file.path, JSON.generate(report))

      result = RubyRouting::Case::OrganizerReportContractValidator.new(report_file.path).call

      refute result.valid?
      assert_includes result.errors.join("; "), "target_pct"
    end
  end

  def test_validator_rejects_non_scalar_period_and_structured_recommendations
    report = {
      "period" => { "from" => "2026-07-30", "to" => "2026-07-30" },
      "total_operations" => 0,
      "distribution" => {},
      "skip_reasons" => {},
      "projected_daily_utilization" => {},
      "recommendations" => [{ "kind" => "review" }]
    }

    Tempfile.create(["routing-invalid-shape", ".json"]) do |report_file|
      File.write(report_file.path, JSON.generate(report))

      result = RubyRouting::Case::OrganizerReportContractValidator.new(report_file.path).call

      refute result.valid?
      errors = result.errors.join("; ")
      assert_includes errors, "period must be a non-empty String"
      assert_includes errors, "recommendations[0] must be a non-empty String"
      assert_includes errors, "distribution must include at least one provider"
      assert_includes errors, "projected_daily_utilization must include at least one provider"
    end
  end

  def test_validator_rejects_out_of_range_utilization_percentage
    report = {
      "period" => "2026-07-30",
      "total_operations" => 1,
      "distribution" => {
        "vipay" => { "count" => 1, "share_pct" => 100.0, "target_pct" => 100.0 }
      },
      "skip_reasons" => {},
      "projected_daily_utilization" => {
        "vipay" => { "used" => 101, "limit" => 100, "utilization_pct" => 101.0 }
      },
      "recommendations" => []
    }

    Tempfile.create(["routing-invalid-utilization", ".json"]) do |report_file|
      File.write(report_file.path, JSON.generate(report))

      result = RubyRouting::Case::OrganizerReportContractValidator.new(report_file.path).call

      refute result.valid?
      assert_includes result.errors.join("; "), "utilization_pct must be nil or a number from 0 to 100"
    end
  end

  def test_serializer_rounds_only_compatibility_percentage_fields
    value = { share_pct: Rational(1, 3), exact_ratio: Rational(1, 3) }

    Tempfile.create(["routing-percentage-boundary", ".json"]) do |file|
      RubyRouting::Case::Serializer.write_json(file.path, value)
      serialized = JSON.parse(File.read(file.path))

      assert_equal 0.33, serialized.fetch("share_pct")
      assert_instance_of Float, serialized.fetch("share_pct")
      assert_equal "1/3", serialized.fetch("exact_ratio")
      assert_instance_of String, serialized.fetch("exact_ratio")
    end
  end
end
