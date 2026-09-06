# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseRouterResolverAuthorityTest < Minitest::Test
  def test_direct_resolver_policy_is_preserved_in_canonical_configuration
    providers = [provider("a", traffic: 50), provider("b", traffic: 50), terminal]
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )
    resolver = RubyRouting::Case::ConflictResolver.new(
      weights: { amount: 1, turnover_min: 1 },
      preferred_amount_ranges: { a: { min: 100, max: 100 }, b: { min: 1_000, max: 1_000 } },
      min_turnovers: { a: 500, b: 700 }
    )
    preferred_amount_ranges = {
      "a" => { min: 100, max: 100 }.freeze,
      "b" => { min: 1_000, max: 1_000 }.freeze
    }.freeze
    min_turnovers = { "a" => 500, "b" => 700 }.freeze

    router = RubyRouting::Case::Router.new(
      dataset, resolver: resolver, terminal_provider_id: "spacepayments"
    )

    assert_equal resolver.weights.values, router.configuration.weights.values
    assert_equal preferred_amount_ranges, router.configuration.preferred_amount_ranges
    assert_equal min_turnovers, router.configuration.min_turnovers
    assert_equal preferred_amount_ranges, router.configuration.to_h.fetch(:preferred_amount_ranges)
    assert_equal min_turnovers, router.configuration.to_h.fetch(:min_turnovers)
  end

  def test_direct_resolver_rejects_unknown_provider_policy_instead_of_dropping_it
    providers = [provider("a", traffic: 50), provider("b", traffic: 50), terminal]
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )
    resolver = RubyRouting::Case::ConflictResolver.new(
      weights: { amount: 1 }, preferred_amount_ranges: { ghost: { min: 1, max: 2 } }
    )

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Router.new(
        dataset, resolver: resolver, terminal_provider_id: "spacepayments"
      )
    end

    assert_includes error.message, "preferred_amount_ranges contains unknown providers: ghost"
  end

  private

  def operation
    RubyRouting::Case::Operation.new(
      operation_id: "resolver-authority", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
  end

  def provider(id, traffic:)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: "active", traffic_percentage: traffic, priority: 1,
      limit_amount_min: 1, limit_amount_max: 10_000, daily_amount_limit: 10_000,
      daily_approved_amount: 0, in_progress_count_limit: 100, in_progress_count: 0,
      in_progress_amount_limit: 10_000, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 2), avg_latency_sec: 1, banks: [], exclude_banks: false,
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
end
