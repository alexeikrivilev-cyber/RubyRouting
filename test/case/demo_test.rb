# frozen_string_literal: true

require "open3"
require "rbconfig"
require_relative "../test_helper"

class AuthoritativeCaseDemoTest < Minitest::Test
  ROOT = File.expand_path("../../", __dir__)

  def test_demo_is_generated_from_two_fresh_strategies_and_shows_simulation_fallback
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, File.join(ROOT, "bin/ruby_routing_case_demo"), chdir: ROOT
    )

    assert status.success?, stderr
    payload = JSON.parse(stdout)
    assert_equal "0.4.2", payload.fetch("version")
    count = payload.fetch("same_input_fresh_runtime_strategies").fetch("count")
    volume = payload.fetch("same_input_fresh_runtime_strategies").fetch("volume")
    refute_equal count.fetch("selected_providers"), volume.fetch("selected_providers")
    refute_equal count.fetch("distribution"), volume.fetch("distribution")
    simulation = payload.fetch("deterministic_conversion_simulation")
    assert_equal "official-smart-v0.4.2", simulation.fetch("report").fetch("submission_profile").fetch("profile_id")
    assert_equal "provider.traffic_percentage", simulation.fetch("report").fetch("submission_profile").fetch("volume_target_source")
    refute_empty simulation.fetch("configuration").fetch("count_share")
    assert_equal %w[count volume priority amount conversion_24h load],
                 simulation.fetch("report").fetch("submission_profile").fetch("configuration").fetch("weights").keys
    assert_operator simulation.fetch("report").fetch("outcomes").fetch("expired"), :>, 0
    assert_operator simulation.fetch("report").fetch("fallbacks").fetch("count"), :>, 0
  end
end
