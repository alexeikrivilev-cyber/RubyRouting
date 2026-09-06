# frozen_string_literal: true

require_relative "../test_helper"

class ProviderCatalogRestorerTest < Minitest::Test
  Fact = Struct.new(:type, :payload, :sequence)

  def setup
    @catalog = RubyRouting::State::ProviderCatalogLedger.new
    @admission = RubyRouting::State::AdmissionLedger.new(clock: TestSupport::ControlledClock.new)
    @health = RubyRouting::Routing::HealthController.new
    @quality = RubyRouting::Routing::QualityController.new
    @provider = RubyRouting::ProviderOpportunity.new(provider_id: "provider")
    @restorer = RubyRouting::State::ProviderCatalogRestorer.new(
      provider_catalog: -> { @catalog },
      admission_ledger: -> { @admission },
      quality_controller: -> { @quality },
      health_policy: -> { @health.policy },
      quality_policy: -> { @quality.policy },
      provider_identity: ->(payload, key) { payload.fetch(key) },
      validate_provider_system_fact: ->(_fact, _provider_id, require_registered:) {
        @required_registration = require_registered
      },
      opportunity_from_payload: ->(_payload) { @provider }
    )
  end

  def test_replays_registration_runtime_update_and_removal_as_handled_facts
    registration = Fact.new(
      :provider_opportunity_registered,
      {
        provider_id: "provider",
        capacity: nil,
        throughput: nil,
        health_policy: @health.policy.to_h,
        quality_policy: @quality.policy.to_h
      },
      1
    )
    runtime = Fact.new(
      :provider_runtime_changed,
      {
        provider_id: "provider",
        available: false,
        capacity_available: false,
        enabled: true,
        health_available: true,
        throughput_available: true
      },
      2
    )
    removal = Fact.new(:provider_opportunity_removed, { provider_id: "provider" }, 3)

    assert_equal true, @restorer.apply(registration)
    assert_equal ["provider"], @catalog.provider_ids
    assert_equal ["provider"], @quality.provider_ids

    assert_equal true, @restorer.apply(runtime)
    refute @catalog.fetch("provider").available
    assert_equal :historical, @required_registration

    assert_equal true, @restorer.apply(removal)
    assert_empty @catalog.provider_ids
    assert_equal :current, @required_registration
  end

  def test_returns_false_for_fact_types_owned_by_other_restorers
    fact = Fact.new(:intent_registered, {}, 1)

    assert_equal false, @restorer.apply(fact)
    assert_empty @catalog.provider_ids
  end

  def test_rejects_provider_registration_that_does_not_match_policy_history
    fact = Fact.new(
      :provider_opportunity_registered,
      {
        provider_id: "provider",
        capacity: nil,
        throughput: nil,
        health_policy: { degrade_after: 99, quarantine_after: 99, recover_after: 99, probe_limit: 1 },
        quality_policy: @quality.policy.to_h
      },
      1
    )

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      @restorer.apply(fact)
    end

    assert_match(/health policy does not match provider/, error.message)
    assert_empty @catalog.provider_ids
  end
end
