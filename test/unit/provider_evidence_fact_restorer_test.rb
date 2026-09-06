# frozen_string_literal: true

require_relative "../test_helper"

class ProviderEvidenceFactRestorerTest < Minitest::Test
  Fact = Struct.new(:type, :payout_id, :payload, :sequence)
  Attempt = Struct.new(:operation_id, :attempt_id, :provider_id)
  PayoutState = Struct.new(:operations)

  def setup
    @health = RubyRouting::Routing::HealthController.new(
      policy: RubyRouting::Routing::HealthPolicy.new(
        degrade_after: 1,
        quarantine_after: 2,
        recover_after: 1,
        probe_limit: 1
      )
    )
    @quality = RubyRouting::Routing::QualityController.new
    @observations = {}
    @transport_sources = {}
    @health_sources = {}
    @quality_sources = {}
    @pending_transitions = {}
    @state = PayoutState.new({ "operation" => Attempt.new("operation", "attempt", "provider") })
    @restorer = RubyRouting::State::ProviderEvidenceFactRestorer.new(
      health_controller: -> { @health },
      quality_controller: -> { @quality },
      payout_state: ->(_payout_id) { @state },
      restored_observations: -> { @observations },
      restored_transport_sources: -> { @transport_sources },
      restored_health_signal_sources: -> { @health_sources },
      restored_quality_signal_sources: -> { @quality_sources },
      pending_health_transitions: -> { @pending_transitions },
      provider_identity: ->(payload, key) { payload.fetch(key) },
      operation_identity: ->(payload, key) { payload.fetch(key) },
      enum_value: lambda do |payload, key, allowed, label|
        RubyRouting::Enum.normalize(payload.fetch(key), allowed, label)
      end,
      validate_provider_system_fact: ->(_fact, _provider_id, require_registered:) {
        raise "missing registration mode" unless require_registered == :historical
      }
    )
  end

  def test_replays_health_signal_and_its_ordered_state_transition
    signal = Fact.new(
      :health_signal,
      "system:provider:provider",
      {
        provider_id: "provider",
        policy: @health.policy.to_h,
        release_exposure: true,
        source_kind: :manual,
        signal: :operational_failure,
        attribution: :provider
      },
      1
    )
    transition = Fact.new(
      :health_state_changed,
      "system:provider:provider",
      { provider_id: "provider", from: :healthy, to: :degraded },
      2
    )

    assert_equal true, @restorer.apply(signal)
    assert_equal [:healthy, :degraded], @pending_transitions["provider"]
    assert_equal true, @restorer.apply(transition)
    assert_equal :degraded, @health.snapshot("provider").state
    assert_empty @pending_transitions
  end

  def test_replays_transport_classification_only_for_its_observation_source
    @observations[["source-payout", "observation"]] = {
      provider_id: "provider",
      operation_id: "operation",
      attempt_id: "attempt",
      transport_kind: :ambiguous_after_possible_send
    }
    fact = Fact.new(
      :transport_classified,
      "payout",
      {
        observation_id: "observation",
        source_payout_id: "source-payout",
        provider_id: "provider",
        operation_id: "operation",
        attempt_id: "attempt",
        kind: :ambiguous_after_possible_send
      },
      1
    )

    assert_equal true, @restorer.apply(fact)
    assert_equal true, @transport_sources[["source-payout", "observation"]]
  end

  def test_returns_false_for_non_provider_evidence_fact
    fact = Fact.new(:allocation_committed, "payout", {}, 1)

    assert_equal false, @restorer.apply(fact)
    assert_empty @transport_sources
  end
end
