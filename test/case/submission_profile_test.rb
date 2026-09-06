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

  def test_positive_optional_weights_without_optional_inputs_are_explicitly_neutral
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    base = JSON.parse(File.read(profile_path))

    %w[intensity turnover_min].each do |factor|
      value = Marshal.load(Marshal.dump(base))
      value.fetch("weights")[factor] = 1
      Tempfile.create(["optional-factor-profile", ".json"]) do |file|
        file.write(JSON.generate(value))
        file.flush
        profile = RubyRouting::Case::SubmissionProfile.load(path: file.path, dataset: dataset)
        run = RubyRouting::Case::Runner.new(profile: profile).call
        selected = run.decisions.first.attempts.find { |attempt| attempt.decision == :selected }
        trace = selected.selection.fetch(:factors).fetch(selected.provider).find do |item|
          item.fetch(:factor).to_s == factor
        end

        refute_nil trace
        assert_equal Rational(0, 1), trace.fetch(:raw)
        assert_equal Rational(0, 1), trace.fetch(:contribution)
        assert_includes trace.fetch(:reason), factor == "intensity" ? "neutral" : "non-discriminating"
      end
    end
  end

  def test_additional_active_provider_is_dataset_bound_and_order_invariant
    providers_document = JSON.parse(File.read(File.join(ROOT, "data/providers.json")))
    quickpay = providers_document.fetch("providers").find do |provider|
      provider.fetch("payment_system") == "quickpay"
    end
    additional = JSON.parse(JSON.generate(quickpay))
    additional["payment_system"] = "newpay"
    additional["traffic_percentage"] = 10
    quickpay["traffic_percentage"] -= 10
    providers_document.fetch("providers") << additional

    runs = [providers_document.fetch("providers"), providers_document.fetch("providers").reverse].map do |providers|
      document = providers_document.merge("providers" => providers)
      Tempfile.create(["additional-active-provider", ".json"]) do |file|
        file.write(JSON.generate(document))
        file.flush
        run = RubyRouting::Case::Runner.new(
          providers_path: file.path,
          history_path: File.join(ROOT, "data/operations_history.csv"),
          queue_path: File.join(ROOT, "data/operations_queue_10.json"),
          profile_path: profile_path
        ).call
        validation = RubyRouting::Case::StrictValidator.new(run).call
        assert validation.valid?, validation.errors.first(5).inspect
        assert_equal Rational(1, 10), run.configuration.targets.count_share.fetch("newpay")
        assert_equal Rational(1, 1), run.configuration.targets.count_share.values.sum
        [run.decisions.map(&:to_h), run.report.to_h,
         run.configuration.targets.count_share, run.configuration.targets.volume_share]
      end
    end

    assert_equal runs.first, runs.last
  end

  def test_provider_traffic_target_source_requires_full_target_mass
    providers = JSON.parse(File.read(File.join(ROOT, "data/providers.json")))
    providers.fetch("providers").find { |provider| provider.fetch("payment_system") == "quickpay" }["traffic_percentage"] = 15

    Tempfile.create(["providers-under-mass", ".json"]) do |providers_file|
      providers_file.write(JSON.generate(providers))
      providers_file.flush
      dataset = RubyRouting::Case::Input.load(
        providers_path: providers_file.path,
        history_path: File.join(ROOT, "data/operations_history.csv"),
        queue_path: File.join(ROOT, "data/operations_queue_10.json")
      )

      error = assert_raises(RubyRouting::Case::InputError) do
        RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)
      end
      assert_includes error.message, "traffic targets must sum exactly to one"
    end
  end

  def test_programmatic_provider_source_profile_cannot_lie_about_target_mass
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    base = RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)
    configuration = RubyRouting::Case::CaseConfiguration.from(
      base.configuration.to_h.merge(
        count_share: { "vipay" => Rational(1, 2) },
        volume_share: { "vipay" => Rational(1, 2) }
      ),
      provider_ids: dataset.providers.map(&:payment_system)
    )

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::SubmissionProfile.new(
        profile_id: "forged", source: "programmatic-test", revision: 1,
        count_target_source: "provider.traffic_percentage",
        volume_target_source: "provider.traffic_percentage",
        configuration: configuration
      )
    end
    assert_includes error.message, "provider-derived count targets must sum exactly to one"

    volume_configuration = RubyRouting::Case::CaseConfiguration.from(
      base.configuration.to_h.merge(
        count_share: { "vipay" => Rational(1, 1) },
        volume_share: { "vipay" => Rational(1, 2) }
      ),
      provider_ids: dataset.providers.map(&:payment_system)
    )
    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::SubmissionProfile.new(
        profile_id: "forged", source: "programmatic-test", revision: 1,
        count_target_source: "provider.traffic_percentage",
        volume_target_source: "provider.traffic_percentage",
        configuration: volume_configuration
      )
    end
    assert_includes error.message, "provider-derived volume targets must sum exactly to one"
  end

  def test_programmatic_provider_source_profile_cannot_lie_about_provider_targets
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    base = RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)
    configuration = RubyRouting::Case::CaseConfiguration.from(
      base.configuration.to_h.merge(
        count_share: { "vipay" => Rational(1, 1) },
        volume_share: { "vipay" => Rational(1, 1) }
      ),
      provider_ids: dataset.providers.map(&:payment_system)
    )
    forged = RubyRouting::Case::SubmissionProfile.new(
      profile_id: "forged", source: base.configuration.source, revision: base.configuration.revision,
      count_target_source: "provider.traffic_percentage",
      volume_target_source: "provider.traffic_percentage",
      configuration: configuration
    )

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Runner.new(profile: forged).call
    end
    assert_includes error.message, "provider-derived count targets do not match provider snapshot"

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Router.new(dataset, profile: forged)
    end
    assert_includes error.message, "provider-derived count targets do not match provider snapshot"
  end

  def test_programmatic_profile_cannot_split_provenance_from_configuration
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    base = RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)
    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::SubmissionProfile.new(
        profile_id: "forged", source: "trusted-source", revision: 99,
        count_target_source: "provider.traffic_percentage",
        volume_target_source: "provider.traffic_percentage",
        configuration: base.configuration
      )
    end
    assert_includes error.message, "profile provenance must match configuration"
  end

  def test_programmatic_profile_rejects_empty_identity_and_provenance
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    base = RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)
    configuration = RubyRouting::Case::CaseConfiguration.from(
      base.configuration.to_h.merge(source: base.configuration.source, revision: 1),
      provider_ids: dataset.providers.map(&:payment_system)
    )

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::SubmissionProfile.new(
        profile_id: "", source: "", revision: 1,
        count_target_source: "provider.traffic_percentage",
        volume_target_source: "provider.traffic_percentage",
        configuration: configuration
      )
    end
    assert_includes error.message, "submission profile id must be non-empty"

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::SubmissionProfile.new(
        profile_id: "forged", source: "", revision: 1,
        count_target_source: "provider.traffic_percentage",
        volume_target_source: "provider.traffic_percentage",
        configuration: configuration
      )
    end
    assert_includes error.message, "submission profile source must be non-empty"
  end

  def test_programmatic_profile_rejects_whitespace_identity_and_provenance
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    base = RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)
    configuration = RubyRouting::Case::CaseConfiguration.from(
      base.configuration.to_h.merge(source: base.configuration.source, revision: 1),
      provider_ids: dataset.providers.map(&:payment_system)
    )

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::SubmissionProfile.new(
        profile_id: "   ", source: "trusted-source", revision: 1,
        count_target_source: "provider.traffic_percentage",
        volume_target_source: "provider.traffic_percentage",
        configuration: configuration
      )
    end
    assert_includes error.message, "submission profile id must be non-empty"

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::SubmissionProfile.new(
        profile_id: "forged", source: "   ", revision: 1,
        count_target_source: "provider.traffic_percentage",
        volume_target_source: "provider.traffic_percentage",
        configuration: configuration
      )
    end
    assert_includes error.message, "submission profile source must be non-empty"
  end

  def test_profile_loader_rejects_whitespace_identity_and_provenance
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    value = JSON.parse(File.read(profile_path))

    %w[profile_id source].each do |field|
      value[field] = "   "
      Tempfile.create(["whitespace-profile", ".json"]) do |file|
        file.write(JSON.generate(value))
        file.flush
        error = assert_raises(RubyRouting::Case::InputError) do
          RubyRouting::Case::SubmissionProfile.load(path: file.path, dataset: dataset)
        end
        assert_includes error.message, field == "profile_id" ? "profile id must be non-empty" : "profile source must be non-empty"
      end
      value = JSON.parse(File.read(profile_path))
    end
  end

  def test_programmatic_configured_volume_profile_remains_dataset_independent
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    base = RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)
    configuration = RubyRouting::Case::CaseConfiguration.from(
      base.configuration.to_h.merge(
        volume_share: { "vipay" => Rational(1, 2), "payflow" => Rational(1, 4),
                        "quickpay" => Rational(1, 4), "spacepayments" => Rational(0, 1) }
      ),
      provider_ids: dataset.providers.map(&:payment_system)
    )
    profile = RubyRouting::Case::SubmissionProfile.new(
      profile_id: "programmatic-configured-volume", source: configuration.source,
      revision: configuration.revision, count_target_source: "provider.traffic_percentage",
      volume_target_source: "configured", configuration: configuration
    )

    runner = RubyRouting::Case::Runner.new(profile: profile).call
    router = RubyRouting::Case::Router.new(dataset, profile: profile)
    assert_equal Rational(1, 2), runner.configuration.targets.volume_share.fetch("vipay")
    assert_equal profile.configuration.to_h, router.configuration.to_h
  end

  def test_programmatic_profile_cannot_claim_an_unsupported_target_source
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    base = RubyRouting::Case::SubmissionProfile.load(path: profile_path, dataset: dataset)

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::SubmissionProfile.new(
        profile_id: "forged", source: "programmatic-test", revision: 1,
        count_target_source: "configured",
        volume_target_source: "provider.traffic_percentage",
        configuration: base.configuration
      )
    end
    assert_includes error.message, "unsupported count target source"
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
    states = dataset.providers.reject do |provider|
      provider.payment_system == profile.configuration.terminal_provider_id
    end.map do |provider|
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
    ).resolve(candidates: eligible, normalization_candidates: eligible,
              operation: operation, traffic: traffic, as_of: operation.created_at)
    priority_winner = RubyRouting::Case::ConflictResolver.new(weights: { priority: 1 }).resolve(
      candidates: eligible, normalization_candidates: eligible,
      operation: operation, traffic: traffic, as_of: operation.created_at
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

  def test_profile_loader_rejects_unknown_provider_keys_in_optional_maps
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    base = JSON.parse(File.read(profile_path))
    values = {
      "min_turnovers" => { "ghost" => 1 },
      "rpm_limits" => { "ghost" => 1 },
      "preferred_amount_ranges" => { "ghost" => { "min" => 1, "max" => 2 } }
    }

    values.each do |field, value|
      document = JSON.parse(JSON.generate(base))
      document[field] = value
      Tempfile.create(["unknown-provider-profile", ".json"]) do |file|
        file.write(JSON.generate(document))
        file.flush
        error = assert_raises(RubyRouting::Case::InputError) do
          RubyRouting::Case::SubmissionProfile.load(path: file.path, dataset: dataset)
        end
        assert_includes error.message, "#{field} contains unknown providers: ghost"
      end
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
