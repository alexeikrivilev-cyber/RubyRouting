# frozen_string_literal: true

require_relative "../test_helper"

class DecisionTraceValidatorTest < Minitest::Test
  Intent = Struct.new(:id)
  State = Struct.new(:intent, :policy_epoch, :policy_scope_key, :policy_fingerprint)
  Attempt = Struct.new(:operation_id)

  def setup
    @validator = RubyRouting::State::DecisionTraceValidator.new(
      policies: -> { {} },
      provider_catalog: -> { RubyRouting::State::ProviderCatalogLedger.new },
      payout_snapshot: ->(_state) { nil },
      decision_enum: ->(payload, key, allowed, _label) {
        value = payload.fetch(key)
        raise ArgumentError unless allowed.include?(value)

        value
      },
      same_contract: ->(_left, _right) { true }
    )
    @state = State.new(Intent.new("payout"), "epoch", ["policy", "epoch", "scope"], "fingerprint")
  end

  def test_accepts_the_closed_role_for_an_assignment
    assert_equal :primary, @validator.decision_role(:primary, action: :assign)
  end

  def test_rejects_a_role_that_does_not_match_the_decision_action
    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      @validator.decision_role(:primary, action: :resolve)
    end

    assert_match(/invalid for resolve/, error.message)
  end

  def test_validates_the_policy_binding_at_the_cross_fact_boundary
    assert_nil @validator.validate_policy_binding(
      @state,
      policy_epoch: "epoch"
    )

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      @validator.validate_policy_binding(@state, policy_epoch: "other")
    end

    assert_match(/policy binding does not match/, error.message)
  end

  def test_rejects_noncanonical_adapter_context_before_policy_recomputation
    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      @validator.validate_non_operation_decision(
        state: @state,
        action: :defer,
        payload: {
          role: :resolution,
          available_provider_ids: [" provider"]
        }
      )
    end

    assert_match(/malformed available provider context/, error.message)
  end

  def test_accepts_only_the_exact_restart_recovery_resolution_trace
    assert_nil @validator.validate_resolution_trace(
      state: @state,
      attempt: Attempt.new("operation"),
      action: :resolve,
      payload: {
        reasons: ["reconciled provider operation after restart"],
        reason_codes: [:restart_recovery]
      }
    )

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      @validator.validate_resolution_trace(
        state: @state,
        attempt: Attempt.new("operation"),
        action: :resolve,
        payload: {
          reasons: ["reconciled provider operation after restart"],
          reason_codes: [:restart_dispatch]
        }
      )
    end

    assert_match(/missing policy/, error.message)
  end
end
