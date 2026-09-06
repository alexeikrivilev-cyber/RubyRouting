# frozen_string_literal: true

require_relative "../test_helper"

class NormalizerTest < Minitest::Test
  def test_timeout_is_conservatively_unknown
    outcome = TestSupport::Simulator::Normalizer.normalize(
      raw_status: "timeout",
      attribution: :provider
    )

    assert_equal :unknown, outcome.status
    assert_equal :unknown, outcome.attribution
    refute outcome.safe_to_release?
  end

  def test_recipient_error_is_terminal_business_failure_not_provider_failure
    outcome = TestSupport::Simulator::Normalizer.normalize(
      raw_status: "recipient_invalid",
      attribution: :recipient
    )

    assert_equal :terminal_payout_failure, outcome.status
    assert_equal :recipient, outcome.attribution
    refute outcome.provider_failure?
  end

  def test_unknown_raw_code_never_becomes_success
    outcome = TestSupport::Simulator::Normalizer.normalize(raw_status: "new-provider-code")

    assert_equal :unknown, outcome.status
    refute outcome.success?
  end

  def test_observation_timestamp_is_controlled_time_or_nil
    assert_raises(ArgumentError) do
      RubyRouting::ProviderObservation.new(
        observation_id: "observation-time",
        payout_id: "payout-time",
        provider_id: "A",
        operation_id: "operation-time",
        attempt_id: "attempt-time",
        observed_at: "2026-01-01T00:00:00Z",
        outcome: RubyRouting::NormalizedOutcome.pending
      )
    end
  end

  def test_normalized_outcome_rejects_truthy_non_boolean_release_flag
    assert_raises(ArgumentError) do
      RubyRouting::NormalizedOutcome.new(
        status: :unknown,
        safe_to_release: "false"
      )
    end
  end

  def test_ambiguous_transport_observation_cannot_claim_safe_release
    assert_raises(ArgumentError) do
      RubyRouting::ProviderObservation.new(
        observation_id: "ambiguous-safe-release",
        payout_id: "payout-transport",
        provider_id: "A",
        operation_id: "operation-transport",
        attempt_id: "attempt-transport",
        outcome: RubyRouting::NormalizedOutcome.safe_route_failure(attribution: :provider),
        transport_kind: :ambiguous_after_possible_send
      )
    end
  end

  def test_definitely_not_sent_transport_observation_cannot_settle
    assert_raises(ArgumentError) do
      RubyRouting::ProviderObservation.new(
        observation_id: "not-sent-success",
        payout_id: "payout-transport",
        provider_id: "A",
        operation_id: "operation-transport",
        attempt_id: "attempt-transport",
        outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider),
        transport_kind: :definitely_not_sent
      )
    end
  end

  def test_definitely_not_sent_transport_observation_cannot_claim_unresolved_outcome
    %i[pending unknown].each do |status|
      assert_raises(ArgumentError, "status=#{status}") do
        RubyRouting::ProviderObservation.new(
          observation_id: "not-sent-#{status}",
          payout_id: "payout-transport",
          provider_id: "A",
          operation_id: "operation-transport-#{status}",
          attempt_id: "attempt-transport-#{status}",
          outcome: RubyRouting::NormalizedOutcome.new(
            status: status,
            safe_to_release: true
          ),
          transport_kind: :definitely_not_sent
        )
      end
    end
  end

  def test_invalid_transport_kind_is_reported_as_a_provider_input_error
    assert_raises(ArgumentError) do
      RubyRouting::ProviderTransportResult.new(kind: Object.new)
    end
    assert_raises(ArgumentError) do
      RubyRouting::ProviderTransportError.new(kind: Object.new)
    end
    assert_raises(ArgumentError) do
      RubyRouting::ProviderObservation.new(
        observation_id: "invalid-transport-kind",
        payout_id: "payout-transport",
        provider_id: "A",
        operation_id: "operation-transport",
        attempt_id: "attempt-transport",
        outcome: RubyRouting::NormalizedOutcome.pending,
        transport_kind: Object.new
      )
    end
  end
end
