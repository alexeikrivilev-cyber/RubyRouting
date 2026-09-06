# frozen_string_literal: true

require "json"
require_relative "../test_helper"

class AuthoritativeCaseVersionMetadataTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  CURRENT_CASE_VERSION = "0.4.4".freeze

  def test_report_and_judge_surfaces_use_one_current_case_version
    run = RubyRouting::Case::Runner.new.call
    evidence = JSON.parse(`bundle exec ruby "#{File.join(ROOT, "bin/ruby_routing_case_evidence")}"`)
    demo = JSON.parse(`bundle exec ruby "#{File.join(ROOT, "bin/ruby_routing_case_demo")}"`)

    versions = [
      RubyRouting::Case::VERSION,
      run.report.to_h.fetch(:version),
      evidence.fetch("version"),
      demo.fetch("version")
    ]
    assert_equal [CURRENT_CASE_VERSION] * versions.length, versions
  end
end
