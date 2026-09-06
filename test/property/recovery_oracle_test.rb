# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/reference/recovery_oracle"

class RecoveryOracleTest < Minitest::Test
  DEFAULT_SEED = 18_207

  def test_generated_recovery_contexts_match_independent_oracle
    seed = Integer(ENV.fetch("RUBY_ROUTING_SEED", DEFAULT_SEED.to_s))
    random = Random.new(seed)
    statuses = %i[new success pending unknown safe_route_failure temporary_provider_failure terminal_payout_failure]

    300.times do |iteration|
      status = statuses.fetch(random.rand(statuses.length))
      owner_present = random.rand(2).zero?
      resolution_capable = random.rand(2).zero?
      attempts = random.rand(0..5)
      max_attempts = random.rand(1..5)
      expected = Reference::RecoveryOracle.choose(
        status: status,
        owner_present: owner_present,
        resolution_capable: resolution_capable,
        attempts: attempts,
        max_attempts: max_attempts
      )
      actual = RubyRouting::Routing::Recovery.choose(
        status: status,
        ownership: owner_present ? Object.new : nil,
        capabilities: resolution_capable ? RubyRouting::ProviderCapabilities.new(status_lookup: true) : nil,
        attempts: attempts,
        max_attempts: max_attempts
      ).action

      assert_equal expected, actual, "seed=#{seed} iteration=#{iteration}"
    end
  end
end
