# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseTerminalIdentityTest < Minitest::Test
  def test_multiple_zero_participation_providers_require_explicit_terminal_identity
    providers = [provider("zero-provider", traffic: 0), provider("spacepayments", traffic: 0)]
    operation = RubyRouting::Case::Operation.new(
      operation_id: "terminal-identity", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Router.new(dataset).run
    end

    assert_includes error.message, "terminal provider"
    assert_includes error.message, "explicitly configured"
  end

  def test_router_rejects_positive_targets_for_a_non_routable_provider
    providers = [
      provider("active", traffic: 50),
      provider("enabled", traffic: 50, status: "enabled"),
      provider("spacepayments", traffic: 0)
    ]
    operation = RubyRouting::Case::Operation.new(
      operation_id: "non-routable-target", created_at: Time.utc(2026, 7, 30, 9), amount: 100,
      bank: "bank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers, history: [], operations: [operation]
    )
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: providers.map(&:payment_system),
      count_share: { active: 0, enabled: 1, spacepayments: 0 },
      volume_share: { active: 0, enabled: 1, spacepayments: 0 }
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: providers.map(&:payment_system), targets: targets,
      weights: { priority: 1 }, terminal_provider_id: "spacepayments"
    )

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Router.new(dataset, configuration: configuration)
    end

    assert_includes error.message, "non-routable provider targets"
  end

  def test_zero_target_active_provider_is_counted_as_a_soft_goal_and_can_be_fallback
    providers = [
      provider("targeted", traffic: 100, priority: 1),
      provider("reserve", traffic: 0, priority: 2),
      provider("spacepayments", traffic: 0, priority: 99)
    ]
    targets = RubyRouting::Case::TrafficTargets.new(
      provider_ids: providers.map(&:payment_system),
      count_share: { targeted: 1, reserve: 0, spacepayments: 0 },
      volume_share: { targeted: 1, reserve: 0, spacepayments: 0 }
    )
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: providers.map(&:payment_system), targets: targets,
      weights: { count: 1 }, terminal_provider_id: "spacepayments"
    )

    eligible_dataset = dataset_for(providers, operation_bank: "bank", targeted_banks: ["bank"])
    eligible_router = RubyRouting::Case::Router.new(eligible_dataset, configuration: configuration)
    eligible_decision = eligible_router.run.fetch(0)
    assert_equal "targeted", eligible_decision.selected_provider
    refute_includes eligible_decision.attempts.map(&:provider), "spacepayments"

    fallback_dataset = dataset_for(providers, operation_bank: "blocked", targeted_banks: ["other"])
    fallback_dataset = RubyRouting::Case::Dataset.new(
      snapshot_at: fallback_dataset.snapshot_at, gateway: fallback_dataset.gateway,
      merchant: fallback_dataset.merchant, providers: fallback_dataset.providers,
      history: fallback_dataset.history, operations: [
        RubyRouting::Case::Operation.new(
          operation_id: "zero-target-fallback", created_at: Time.utc(2026, 7, 30, 9),
          amount: 100, bank: "blocked", card_brand: nil,
          payout_requisite: { "sbp" => { "phone" => "79000000000" } }
        )
      ]
    )
    fallback_router = RubyRouting::Case::Router.new(fallback_dataset, configuration: configuration)
    fallback_decision = fallback_router.run.fetch(0)

    assert_equal "reserve", fallback_decision.selected_provider
    assert_equal %w[targeted reserve], fallback_decision.attempts.map(&:provider)
    assert_equal ["bank_not_in_list", "only_eligible_provider"], fallback_decision.attempts.map(&:reason)
    refute_includes fallback_decision.attempts.map(&:provider), "spacepayments"
  end

  private

  def provider(id, traffic:, status: "active", priority: 1)
    RubyRouting::Case::Provider.new(
      payment_system: id, status: status, traffic_percentage: traffic, priority: priority,
      limit_amount_min: nil, limit_amount_max: nil, daily_amount_limit: nil,
      daily_approved_amount: 0, in_progress_count_limit: nil, in_progress_count: 0,
      in_progress_amount_limit: nil, in_progress_amount: 0, available_requisites: 10,
      conversion_24h: Rational(1, 1), avg_latency_sec: 1, banks: [], exclude_banks: false,
      provider_margin_pct: 1, merchant_margin_pct: 1, allow_negative_agreement: false
    )
  end

  def dataset_for(providers, operation_bank:, targeted_banks:)
    RubyRouting::Case::Dataset.new(
      snapshot_at: Time.utc(2026, 7, 30, 8), gateway: "gateway", merchant: "merchant",
      providers: providers.map do |item|
        next item if item.payment_system != "targeted"

        RubyRouting::Case::Provider.new(**item.to_h.merge(banks: targeted_banks))
      end,
      history: [],
      operations: [
        RubyRouting::Case::Operation.new(
          operation_id: "zero-target-selection", created_at: Time.utc(2026, 7, 30, 9),
          amount: 100, bank: operation_bank, card_brand: nil,
          payout_requisite: { "sbp" => { "phone" => "79000000000" } }
        )
      ]
    )
  end
end
