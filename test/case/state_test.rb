# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseStateTest < Minitest::Test
  def provider(**overrides)
    defaults = {
      payment_system: "p", status: "active", traffic_percentage: 10, priority: 1,
      limit_amount_min: 1, limit_amount_max: 100_000, daily_amount_limit: 1_000_000,
      daily_approved_amount: 0, in_progress_count_limit: 10, in_progress_count: 0,
      in_progress_amount_limit: 1_000_000, in_progress_amount: 0,
      available_requisites: 3, conversion_24h: Rational(9, 10), avg_latency_sec: 10,
      banks: [], exclude_banks: false, provider_margin_pct: 1,
      merchant_margin_pct: 1, allow_negative_agreement: false
    }
    RubyRouting::Case::Provider.new(**defaults.merge(overrides))
  end

  def operation(amount: 10, bank: "sberbank", operation_id: "op")
    RubyRouting::Case::Operation.new(
      operation_id: operation_id, created_at: Time.utc(2026, 7, 30, 9), amount: amount,
      bank: bank, card_brand: nil, payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def test_supplied_baseline_is_not_fabricated_as_local_transient_exposure
    state = RubyRouting::Case::ProviderCaseState.new(
      provider(
        in_progress_count: 4,
        in_progress_amount: 380,
        daily_approved_amount: 90
      ),
      rpm_limit: 2
    )

    assert_equal 4, state.in_progress_count
    assert_equal 380, state.in_progress_amount
    assert_equal 0, state.transient_count
    assert_equal 90, state.daily_approved_amount
  end

  def test_state_rejects_invalid_time_and_exposes_immutable_rpm_events
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::ProviderCaseState.new(provider, rpm_limit: -1)
    end
    assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::ProviderCaseState.new(provider, rpm_window_seconds: 0)
    end

    state = RubyRouting::Case::ProviderCaseState.new(provider)
    item = operation
    assert_raises(RubyRouting::Case::InputError) { state.reserve!(item, as_of: item.created_at.iso8601) }
    assert_equal [0, 0], [state.transient_count, state.transient_amount]
    assert_raises(RubyRouting::Case::InputError) { state.rpm_count(item.created_at.iso8601) }

    state.reserve!(item, as_of: item.created_at)
    events = state.rpm_events
    assert events.frozen?
    assert_raises(FrozenError) { events << item.created_at }
    state.release!(item)
  end

  def test_state_fetch_uses_canonical_provider_identity
    state = RubyRouting::Case::CaseState.new(
      RubyRouting::Case::Dataset.new(
        snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
        providers: [provider], history: [], operations: []
      )
    )
    structured = Object.new
    def structured.to_s
      "p"
    end

    assert_raises(RubyRouting::Case::InputError) { state.fetch(structured) }
  end

  def test_approved_attempt_releases_transient_load_and_increments_daily_only_after_outcome
    state = RubyRouting::Case::ProviderCaseState.new(provider(daily_approved_amount: 90))
    item = operation(amount: 10)

    state.reserve!(item, as_of: item.created_at)
    assert_equal [1, 10, 90], [state.transient_count, state.transient_amount, state.daily_approved_amount]
    state.release!(item)
    state.record_outcome!(item, :approved)
    state.record_route!(item)

    assert_equal [0, 0, 100], [state.transient_count, state.transient_amount, state.daily_approved_amount]
    assert_equal [1, 10], [state.routed_count, state.routed_volume]
  end

  def test_rejected_and_expired_attempts_do_not_increment_daily_turnover
    state = RubyRouting::Case::ProviderCaseState.new(provider)
    item = operation

    %i[rejected expired].each do |status|
      state.reserve!(item, as_of: item.created_at)
      state.release!(item)
      state.record_outcome!(item, status)
    end

    assert_equal 0, state.daily_approved_amount
    assert_equal 1, state.rejected_count
    assert_equal 1, state.expired_count
  end

  def test_rpm_is_a_rolling_hard_gate_with_exact_boundary
    state = RubyRouting::Case::ProviderCaseState.new(provider, rpm_limit: 1, rpm_window_seconds: 60)
    item = operation
    evaluator = RubyRouting::Case::HardConstraintEvaluator.new
    state.reserve!(item, as_of: item.created_at)
    state.release!(item)
    state.record_outcome!(item, :rejected)

    blocked = evaluator.call(state, item, as_of: item.created_at + 30)
    at_boundary = evaluator.call(state, item, as_of: item.created_at + 60)
    assert_equal :rpm_limit, blocked.reason
    assert at_boundary.eligible?
  end

  def test_invalid_release_fails_without_corrupting_transient_state
    state = RubyRouting::Case::ProviderCaseState.new(provider)
    item = operation(amount: 10)

    assert_raises(RubyRouting::Case::OutputError) { state.release!(item) }
    assert_equal [0, 0], [state.transient_count, state.transient_amount]

    state.reserve!(item, as_of: item.created_at)
    assert_raises(RubyRouting::Case::OutputError) { state.release!(operation(amount: 11)) }
    assert_equal [1, 10], [state.transient_count, state.transient_amount]
    assert_raises(RubyRouting::Case::OutputError) { state.release!(operation(amount: 5)) }
    assert_equal [1, 10], [state.transient_count, state.transient_amount]
    state.release!(item)
    assert_equal [0, 0], [state.transient_count, state.transient_amount]
  end

  def test_all_hard_exclusions_are_outside_the_score_and_have_stable_codes
    evaluator = RubyRouting::Case::HardConstraintEvaluator.new
    checks = {
      inactive_provider: [provider(status: "inactive"), :inactive_provider],
      zero_participation: [provider(traffic_percentage: 0), :zero_participation],
      amount_below_minimum: [provider(limit_amount_min: 20), :amount_below_minimum],
      amount_exceeds_limit: [provider(limit_amount_max: 5), :amount_exceeds_limit],
      daily_amount_limit: [provider(daily_amount_limit: 5), :daily_amount_limit],
      in_progress_count_limit: [provider(in_progress_count_limit: 0), :in_progress_count_limit],
      in_progress_amount_limit: [provider(in_progress_amount_limit: 5), :in_progress_amount_limit],
      bank_not_in_list: [provider(banks: ["alfa"]), :bank_not_in_list],
      bank_excluded: [provider(banks: ["sberbank"], exclude_banks: true), :bank_excluded],
      negative_margin_without_agreement: [provider(provider_margin_pct: 2, merchant_margin_pct: 1), :negative_margin_without_agreement],
      no_available_requisite: [provider(available_requisites: 0), :no_available_requisite]
    }

    checks.each do |label, (candidate, expected)|
      result = evaluator.call(
        RubyRouting::Case::ProviderCaseState.new(candidate),
        operation,
        as_of: operation.created_at
      )
      assert_equal expected, result.reason, label
      refute result.eligible?, label
    end
  end
end
