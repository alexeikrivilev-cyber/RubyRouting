# frozen_string_literal: true

require "json"
require_relative "../test_helper"

class AuthoritativeSubmissionProfileTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def profile_path
    File.join(ROOT, "data/submission_profile.json")
  end

  def test_default_runner_uses_typed_smart_profile_and_loaded_targets
    run = RubyRouting::Case::Runner.new.call

    assert_instance_of RubyRouting::Case::SubmissionProfile, run.profile
    assert_equal "official-smart-v0.4.2", run.profile.profile_id
    assert_equal "data/submission_profile.json", run.profile.source
    assert_equal 2, run.profile.revision
    assert_equal Rational(2, 5), run.configuration.targets.count_share.fetch("vipay")
    assert_equal Rational(7, 20), run.configuration.targets.count_share.fetch("payflow")
    assert_equal Rational(1, 4), run.configuration.targets.count_share.fetch("quickpay")
    assert_equal run.configuration.targets.count_share, run.configuration.targets.volume_share
    assert_equal(
      %i[count volume priority amount conversion_24h load],
      run.configuration.weights.values.keys
    )
    assert_equal :conversion, run.configuration.simulation_mode
    assert_equal "spacepayments", run.configuration.terminal_provider_id
    assert_equal run.profile.to_h, run.report.to_h.fetch(:submission_profile)
  end

  def test_profile_round_trip_keeps_exact_values_and_preferred_bands_are_independent
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    profile = RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)

    ranges = profile.configuration.preferred_amount_ranges
    refute_equal ranges.fetch("vipay"), ranges.fetch("payflow")
    refute_equal ranges.fetch("payflow"), ranges.fetch("quickpay")
    assert_equal({ min: 5_000, max: 50_000 }, ranges.fetch("vipay"))
    assert_equal Rational(87, 100), dataset.providers.find { |p| p.payment_system == "vipay" }.conversion_24h
    assert_equal profile.configuration.to_h, profile.configuration.to_h
  end

  def test_canonical_amount_factor_changes_a_hard_eligible_conflict
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    profile = RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)
    operation = RubyRouting::Case::Operation.new(
      operation_id: "canonical-amount-case", created_at: Time.utc(2026, 7, 30, 9), amount: 1_000,
      bank: "sberbank", card_brand: nil,
      payout_requisite: { "sbp" => { "phone" => "79000000000" } }
    )
    states = dataset.providers.reject(&:self_provider?).map do |provider|
      RubyRouting::Case::ProviderCaseState.new(provider)
    end
    eligible = states.select do |state|
      RubyRouting::Case::HardConstraintEvaluator.new.call(
        state, operation, as_of: operation.created_at
      ).eligible?
    end
    assert_equal %w[payflow quickpay vipay], eligible.map { |state| state.provider.payment_system }.sort

    traffic = RubyRouting::Case::TrafficLedger.new(dataset.providers.map(&:payment_system), targets: profile.configuration.targets)
    amount_winner = RubyRouting::Case::ConflictResolver.new(
      weights: { amount: 1 }, preferred_amount_ranges: profile.configuration.preferred_amount_ranges
    ).resolve(candidates: eligible, operation: operation, traffic: traffic, as_of: operation.created_at)
    priority_winner = RubyRouting::Case::ConflictResolver.new(weights: { priority: 1 }).resolve(
      candidates: eligible, operation: operation, traffic: traffic, as_of: operation.created_at
    )

    assert_equal "payflow", amount_winner.selected_provider
    assert_equal "vipay", priority_winner.selected_provider
    refute_equal priority_winner.selected_provider, amount_winner.selected_provider
    assert_operator amount_winner.traces.fetch("payflow").first.raw, :>, amount_winner.traces.fetch("vipay").first.raw
  end

  def test_volume_target_source_is_explicit_and_configured_override_remains_available
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    value = JSON.parse(File.read(profile_path))
    value["volume_target_source"] = "configured"
    value["volume_share"] = { "vipay" => 0.5, "payflow" => 0.25, "quickpay" => 0.25, "spacepayments" => 0 }

    Tempfile.create(["configured-volume-profile", ".json"]) do |file|
      file.write(JSON.generate(value))
      file.flush
      profile = RubyRouting::Case::SubmissionProfile.load(path: file.path, dataset: dataset)

      assert_equal "configured", profile.volume_target_source
      assert_equal Rational(1, 2), profile.configuration.targets.volume_share.fetch("vipay")
      refute_equal profile.configuration.targets.count_share, profile.configuration.targets.volume_share
      assert_equal "configured", profile.to_h.fetch(:volume_target_source)
    end
  end

  def test_profile_loader_rejects_unknown_fields_and_non_numeric_weight_values
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    Tempfile.create(["submission-profile", ".json"]) do |file|
      value = JSON.parse(File.read(profile_path))
      value["unexpected"] = true
      file.write(JSON.generate(value))
      file.flush

      error = assert_raises(RubyRouting::Case::InputError) do
        RubyRouting::Case::SubmissionProfile.load(path: file.path, dataset: dataset)
      end
      assert_includes error.message, "unknown fields"
    end

    Tempfile.create(["submission-profile", ".json"]) do |file|
      value = JSON.parse(File.read(profile_path))
      value["volume_share"] = { "vipay" => 1 }
      file.write(JSON.generate(value))
      file.flush

      error = assert_raises(RubyRouting::Case::InputError) do
        RubyRouting::Case::SubmissionProfile.load(path: file.path, dataset: dataset)
      end
      assert_includes error.message, "volume_share must not be supplied"
    end

    Tempfile.create(["submission-profile", ".json"]) do |file|
      value = JSON.parse(File.read(profile_path))
      value["weights"]["count"] = "0.5"
      file.write(JSON.generate(value))
      file.flush

      assert_raises(RubyRouting::Case::InputError) do
        RubyRouting::Case::SubmissionProfile.load(path: file.path, dataset: dataset)
      end
    end

    Tempfile.create(["submission-profile", ".json"]) do |file|
      value = JSON.parse(File.read(profile_path))
      value["volume_target_source"] = "configured"
      value.delete("volume_share")
      file.write(JSON.generate(value))
      file.flush

      error = assert_raises(RubyRouting::Case::InputError) do
        RubyRouting::Case::SubmissionProfile.load(path: file.path, dataset: dataset)
      end
      assert_includes error.message, "requires volume_share"
    end

    Tempfile.create(["submission-profile", ".json"]) do |file|
      value = JSON.parse(File.read(profile_path))
      value["weights"] = { "count" => 1, "volume" => 1 }
      value["count_target_source"] = "provider.traffic_percentage"
      value["volume_target_source"] = "configured"
      value["volume_share"] = {}
      file.write(JSON.generate(value))
      file.flush

      error = assert_raises(RubyRouting::Case::InputError) do
        RubyRouting::Case::SubmissionProfile.load(path: file.path, dataset: dataset)
      end
      assert_includes error.message, "non-zero volume target"
    end
  end

  def test_runner_rejects_ambiguous_profile_and_configuration_authorities
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    profile = RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)
    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: dataset.providers.map(&:payment_system), terminal_provider_id: "spacepayments"
    )

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Runner.new(profile: profile, configuration: configuration).call
    end
    assert_includes error.message, "either profile or configuration"
  end

  def test_profile_rejects_a_second_policy_authority
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    profile = RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Router.new(
        dataset, profile: profile,
        resolver: RubyRouting::Case::ConflictResolver.new(weights: { priority: 1 })
      )
    end
    assert_includes error.message, "policy overrides"

    configuration = RubyRouting::Case::CaseConfiguration.new(
      provider_ids: dataset.providers.map(&:payment_system), terminal_provider_id: "spacepayments",
      weights: { count: 1 }
    )
    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Router.new(
        dataset, configuration: configuration,
        resolver: RubyRouting::Case::ConflictResolver.new(weights: { priority: 1 })
      )
    end
    assert_includes error.message, "policy overrides"
  end

  def test_profile_rejects_malformed_policy_override_without_a_boundary_crash
    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Runner.new(rpm_limits: nil).call
    end
    assert_includes error.message, "policy overrides"
  end

  def test_explicit_false_authorities_and_overrides_do_not_select_the_default_policy
    {
      profile: "runner profile",
      configuration: "case configuration",
      traffic_targets: "policy overrides",
      terminal_provider_id: "policy overrides",
      resolver: "resolver must be ConflictResolver"
    }.each do |keyword, message|
      error = assert_raises(RubyRouting::Case::InputError) do
        RubyRouting::Case::Runner.new(**{ keyword => false }).call
      end
      assert_includes error.message, message
    end
  end
end
