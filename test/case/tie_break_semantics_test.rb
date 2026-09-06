# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseTieBreakSemanticsTest < Minitest::Test
  def provider(id, priority:)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: 50, priority: priority,
      limit_amount_min: 1, limit_amount_max: 10_000, daily_amount_limit: 1_000_000,
      daily_approved_amount: 0, in_progress_count_limit: 100, in_progress_count: 0,
      in_progress_amount_limit: 1_000_000, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def terminal
    RubyRouting::Case::Provider.new(
      payment_system: "spacepayments", status: "active", traffic_percentage: 0, priority: 99,
      limit_amount_min: nil, limit_amount_max: nil, daily_amount_limit: nil,
      daily_approved_amount: 0, in_progress_count_limit: nil, in_progress_count: 0,
      in_progress_amount_limit: nil, in_progress_amount: 0, available_requisites: 1,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 0, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def operation
    RubyRouting::Case::Operation.new(
      operation_id: "disabled-priority-tie", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def route(a_priority:, b_priority:)
    providers = [provider("a", priority: a_priority), provider("b", priority: b_priority), terminal]
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: providers.map(&:payment_system), weights: { conversion_24h: 1 },
      terminal_provider_id: "spacepayments"
    )
    router = RubyRouting::Case::Router.new(dataset, configuration: configuration)
    decision = router.run.fetch(0)
    selected_attempt = decision.attempts.find { |attempt| attempt.decision == :selected }
    [decision.selected_provider, selected_attempt.selection]
  end

  def test_disabled_priority_cannot_change_an_exact_score_tie
    low_a = route(a_priority: 1, b_priority: 2)
    low_b = route(a_priority: 2, b_priority: 1)

    assert_equal "a", low_a.fetch(0)
    assert_equal "a", low_b.fetch(0)
    assert_equal low_a.fetch(1).fetch(:scores), low_b.fetch(1).fetch(:scores)
    assert_equal Rational(0, 1), low_a.fetch(1).fetch(:scores).fetch("a")
    assert_equal Rational(0, 1), low_a.fetch(1).fetch(:scores).fetch("b")
  end

  def test_disabled_priority_cannot_change_a_non_tied_multi_factor_winner
    without_priority = scoring_route(weights: { conversion_24h: 1, load: 1 })
    with_disabled_priority = scoring_route(weights: { conversion_24h: 1, load: 1, priority: 0 })

    assert_equal "c", without_priority.fetch(:selected)
    assert_equal without_priority.fetch(:selected), with_disabled_priority.fetch(:selected)
    assert_equal without_priority.fetch(:scores).fetch("a"), with_disabled_priority.fetch(:scores).fetch("a")
    assert_equal without_priority.fetch(:scores).fetch("b"), with_disabled_priority.fetch(:scores).fetch("b")
  end

  def test_every_other_zero_weight_factor_is_inert_on_the_router_path
    baseline = scoring_route(weights: { conversion_24h: 1 })
    factors = %i[count volume priority amount load intensity turnover_min]

    factors.each do |factor|
      with_disabled_factor = scoring_route(weights: { conversion_24h: 1, factor => 0 })

      assert_equal baseline.fetch(:selected), with_disabled_factor.fetch(:selected), factor
      assert_equal baseline.fetch(:scores), with_disabled_factor.fetch(:scores), factor
      with_disabled_factor.fetch(:traces).each_value do |provider_traces|
        trace = provider_traces.fetch(factor.to_s)
        assert_equal 0, trace.fetch(:weight), factor
        assert_equal Rational(0, 1), trace.fetch(:contribution), factor
      end
    end
  end

  def test_common_positive_weight_scale_preserves_router_winner_and_normalized_evidence
    baseline = scoring_route(weights: { conversion_24h: 1, load: 1 })
    scaled = scoring_route(weights: { conversion_24h: 3, load: 3 })

    assert_equal baseline.fetch(:selected), scaled.fetch(:selected)
    assert_equal baseline.fetch(:scores).keys, scaled.fetch(:scores).keys
    baseline.fetch(:scores).each do |provider_id, score|
      assert_equal score * 3, scaled.fetch(:scores).fetch(provider_id)
    end
    baseline.fetch(:traces).each do |provider_id, factors|
      factors.each do |factor, trace|
        scaled_trace = scaled.fetch(:traces).fetch(provider_id).fetch(factor)
        assert_equal trace.fetch(:raw), scaled_trace.fetch(:raw)
        assert_equal trace.fetch(:normalized), scaled_trace.fetch(:normalized)
        assert_equal trace.fetch(:reason), scaled_trace.fetch(:reason)
        assert_equal trace.fetch(:weight) * 3, scaled_trace.fetch(:weight)
        assert_equal trace.fetch(:contribution) * 3, scaled_trace.fetch(:contribution)
      end
    end
  end

  private

  def scoring_route(weights:)
    providers = [
      scoring_provider("a", conversion: Rational(1, 2), daily: 500, priority: 0),
      scoring_provider("b", conversion: Rational(9, 10), daily: 900, priority: 2,
                       in_progress_count: 99, in_progress_amount: 999_900),
      scoring_provider("c", conversion: Rational(3, 5), daily: 0, priority: 5),
      terminal
    ]
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: providers.map(&:payment_system), weights: weights,
      terminal_provider_id: "spacepayments"
    )
    router = RubyRouting::Case::Router.new(dataset, configuration: configuration)
    decision = router.run.fetch(0)
    attempt = decision.attempts.find { |candidate| candidate.decision == :selected }
    {
      selected: decision.selected_provider,
      scores: attempt.selection.fetch(:scores),
      traces: attempt.selection.fetch(:factors).transform_values do |values|
        values.to_h { |evidence| [evidence.fetch(:factor), evidence] }
      end
    }
  end

  def scoring_provider(id, conversion:, daily:, priority:, daily_limit: 1_000,
                       in_progress_count: 0, in_progress_amount: 0)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: 30, priority: priority,
      limit_amount_min: 1, limit_amount_max: 10_000, daily_amount_limit: daily_limit,
      daily_approved_amount: daily, in_progress_count_limit: 100, in_progress_count: in_progress_count,
      in_progress_amount_limit: 1_000_000, in_progress_amount: in_progress_amount, available_requisites: 10,
      conversion_24h: conversion, avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end
end
