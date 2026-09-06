# frozen_string_literal: true

require_relative "../test_helper"

class RecoveryTest < Minitest::Test
  def test_unknown_without_resolution_capability_defers
    decision = RubyRouting::Routing::Recovery.choose(
      status: :unknown,
      ownership: Object.new,
      capabilities: RubyRouting::ProviderCapabilities.new,
      attempts: 1,
      max_attempts: 3
    )

    assert_equal :defer, decision.action
  end

  def test_unknown_with_status_lookup_resolves
    decision = RubyRouting::Routing::Recovery.choose(
      status: :unknown,
      ownership: Object.new,
      capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
      attempts: 1,
      max_attempts: 3
    )

    assert_equal :resolve, decision.action
  end

  def test_safe_failure_falls_back_only_after_owner_is_released
    decision = RubyRouting::Routing::Recovery.choose(
      status: :safe_route_failure,
      ownership: nil,
      capabilities: nil,
      attempts: 1,
      max_attempts: 3
    )

    assert_equal :fallback, decision.action
  end

  def test_terminal_failure_stops_and_budget_exhaustion_defers
    terminal = RubyRouting::Routing::Recovery.choose(
      status: :terminal_payout_failure,
      ownership: nil,
      capabilities: nil,
      attempts: 1,
      max_attempts: 3
    )
    exhausted = RubyRouting::Routing::Recovery.choose(
      status: :safe_route_failure,
      ownership: nil,
      capabilities: nil,
      attempts: 3,
      max_attempts: 3
    )

    assert_equal :terminate, terminal.action
    assert_equal :defer, exhausted.action
  end
end
