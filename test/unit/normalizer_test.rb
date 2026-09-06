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
end
