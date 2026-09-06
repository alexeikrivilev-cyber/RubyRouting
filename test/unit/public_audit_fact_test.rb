# frozen_string_literal: true

require_relative "../test_helper"
require "json"

class PublicAuditFactTest < Minitest::Test
  def test_public_projection_is_fail_closed_for_sensitive_and_unknown_payload_fields
    fact = RubyRouting::Fact.new(
      sequence: 1,
      type: :intent_registered,
      fact_id: "fact-1",
      payout_id: "payout-1",
      payload: {
        money: RubyRouting::Money.new(100, "RUB"),
        recipient: { account_number: "recipient-secret" },
        context: { private_label: "context-secret" },
        newly_added_sensitive_field: "must-not-leak"
      }
    )

    projected = RubyRouting::Projections::PublicAuditFact.from_fact(fact)

    assert_equal({ amount_minor: 100, currency: "RUB" }, projected.payload.fetch(:money))
    assert_equal ["context", "newly_added_sensitive_field", "recipient"], projected.redacted_fields
    refute projected.payload.key?(:recipient)
    refute projected.payload.key?(:context)
    refute_includes JSON.generate(projected.to_h), "recipient-secret"
    refute_includes JSON.generate(projected.to_h), "must-not-leak"
  end
end
