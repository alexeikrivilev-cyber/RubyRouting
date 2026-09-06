# frozen_string_literal: true

require "json"
require_relative "../test_helper"

class AuthoritativeSerializedArtifactTest < Minitest::Test
  def test_written_decisions_and_report_are_reparsed_and_strictly_validated
    run = RubyRouting::Case::Runner.new.call
    Tempfile.create(["routing-decisions", ".json"]) do |decisions|
      Tempfile.create(["routing-report", ".json"]) do |report|
        RubyRouting::Case::Serializer.write_json(decisions.path, run.decisions.map(&:to_h))
        RubyRouting::Case::Serializer.write_json(report.path, run.report.to_h)

        result = RubyRouting::Case::SerializedArtifactValidator.new(
          run, decisions_path: decisions.path, report_path: report.path
        ).call

        assert result.valid?, result.errors.inspect
        parsed_decisions = JSON.parse(File.read(decisions.path))
        refute parsed_decisions.first.key?("selection")
        refute parsed_decisions.first.fetch("attempts").first.key?("selection")
        parsed_report = JSON.parse(File.read(report.path))
        assert_equal "official-smart-v0.4.1", parsed_report.fetch("submission_profile").fetch("profile_id")
        assert_equal "integer or numerator/denominator string; exact Rational values are never serialized as Float",
                     parsed_report.fetch("ratio_representation")
      end
    end
  end

  def test_post_write_extra_selection_trace_is_rejected
    run = RubyRouting::Case::Runner.new.call
    Tempfile.create(["routing-decisions", ".json"]) do |decisions|
      Tempfile.create(["routing-report", ".json"]) do |report|
        RubyRouting::Case::Serializer.write_json(decisions.path, run.decisions.map(&:to_h))
        RubyRouting::Case::Serializer.write_json(report.path, run.report.to_h)
        forged = JSON.parse(File.read(decisions.path))
        forged.first["selection"] = { "scores" => {} }
        File.write(decisions.path, JSON.generate(forged))

        result = RubyRouting::Case::SerializedArtifactValidator.new(
          run, decisions_path: decisions.path, report_path: report.path
        ).call

        refute result.valid?
        assert result.errors.any? { |error| error.include?("unsupported fields") || error.include?("differs") }
      end
    end
  end

  def test_post_write_report_tampering_is_rejected_even_when_json_is_well_formed
    run = RubyRouting::Case::Runner.new.call
    Tempfile.create(["routing-decisions", ".json"]) do |decisions|
      Tempfile.create(["routing-report", ".json"]) do |report|
        RubyRouting::Case::Serializer.write_json(decisions.path, run.decisions.map(&:to_h))
        RubyRouting::Case::Serializer.write_json(report.path, run.report.to_h)
        forged = JSON.parse(File.read(report.path))
        forged.fetch("assignment_totals")["count"] = 999
        File.write(report.path, JSON.generate(forged))

        result = RubyRouting::Case::SerializedArtifactValidator.new(
          run, decisions_path: decisions.path, report_path: report.path
        ).call

        refute result.valid?
        assert result.errors.any? { |error| error.include?("differs") }
      end
    end
  end

  def test_malformed_operation_id_types_are_reported_without_validator_crash
    run = RubyRouting::Case::Runner.new.call
    decisions = JSON.parse(JSON.generate(RubyRouting::Case::Serializer.json_value(run.decisions.map(&:to_h))))
    decisions.first["operation_id"] = 1

    Tempfile.create(["routing-decisions-malformed-id", ".json"]) do |decisions_file|
      Tempfile.create(["routing-report-valid", ".json"]) do |report_file|
        File.write(decisions_file.path, JSON.generate(decisions))
        RubyRouting::Case::Serializer.write_json(report_file.path, run.report.to_h)

        result = RubyRouting::Case::SerializedArtifactValidator.new(
          run, decisions_path: decisions_file.path, report_path: report_file.path
        ).call

        refute result.valid?
        assert_includes result.errors.join("; "), "operation ids must be Strings"
      end
    end
  end

  def test_null_artifact_roots_are_invalid
    run = RubyRouting::Case::Runner.new.call

    Tempfile.create(["routing-decisions-null", ".json"]) do |decisions_file|
      Tempfile.create(["routing-report-null", ".json"]) do |report_file|
        File.write(decisions_file.path, "null")
        File.write(report_file.path, "null")

        result = RubyRouting::Case::SerializedArtifactValidator.new(
          run, decisions_path: decisions_file.path, report_path: report_file.path
        ).call

        refute result.valid?
        assert_includes result.errors.join("; "), "decisions artifact must be an Array"
        assert_includes result.errors.join("; "), "report artifact must be an Object"
      end
    end
  end
end
