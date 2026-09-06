# frozen_string_literal: true

require_relative "../test_helper"

class DemoScenarioTest < Minitest::Test
  def test_demo_is_explicitly_simulated_and_exercises_safe_fallback
    demo = RubyRouting::Demo::Scenario.run
    result = demo.fetch(:result)
    payout = result.payout

    assert_equal :success, result.status
    assert_equal "simulated-recovery", payout.settlement_provider_id
    assert_equal %w[simulated-primary simulated-recovery], payout.attempts.map(&:provider_id)
    assert_equal [:primary, :recovery], payout.attempts.map(&:role)
    assert_equal 1, demo.fetch(:service).queries.analytics.fallback_recovery_count
    assert_equal [
      [:initiate, "demo-payout-1:demo-payout-1:operation:1"]
    ], demo.fetch(:providers).fetch(:primary).calls
  end
end
