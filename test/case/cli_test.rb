# frozen_string_literal: true

require "open3"
require_relative "../test_helper"

class AuthoritativeCaseCliTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_missing_input_is_a_single_actionable_cli_error
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", File.join(ROOT, "bin/ruby_routing_case"),
      "--providers", File.join(ROOT, "does-not-exist.json"), chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "case run failed: providers file not found"
    refute_includes stderr, "in `RubyRouting::Case::Input.load_json'"
  end

  def test_cli_generates_strictly_valid_decisions_and_report_once
    decisions = Tempfile.new(["routing-decisions", ".json"])
    report = Tempfile.new(["routing-report", ".json"])
    decisions.close
    report.close
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", File.join(ROOT, "bin/ruby_routing_case"),
      "--decisions", decisions.path, "--report", report.path, chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "for 10 operations"
    assert_equal 10, JSON.parse(File.read(decisions.path)).length
    report_value = JSON.parse(File.read(report.path))
    assert report_value.key?("distribution")
    assert_equal "official-smart-v0.4.2", report_value.fetch("submission_profile").fetch("profile_id")
    assert_equal "conversion", report_value.fetch("submission_profile").fetch("configuration").fetch("simulation_mode")
  ensure
    decisions&.unlink
    report&.unlink
  end
end
