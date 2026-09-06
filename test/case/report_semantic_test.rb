# frozen_string_literal: true

require "json"
require "tempfile"
require_relative "../test_helper"

class OrganizerReportSemanticValidatorTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_canonical_serialized_report_passes_independent_raw_input_recomputation
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      result = semantic_validator(decisions_path, report_path).call

      assert result.valid?, result.errors.inspect
    end
  end

  def test_independent_oracle_rejects_factor_trace_contribution_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      trace = report.fetch("explanations").fetch("op_101").fetch("considered").first
        .fetch("factors").fetch("vipay").first
      trace["contribution"] = "0/1"
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?
      assert result.errors.any? { |error| error.include?("factor contributions differ from score") }
    end
  end

  def test_independent_oracle_rejects_factor_raw_normalization_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      trace = report.fetch("explanations").fetch("op_101").fetch("considered").first
        .fetch("factors").fetch("vipay").find { |candidate| candidate.fetch("factor") == "conversion_24h" }
      trace["raw"] = "0/1"
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?
      assert result.errors.any? { |error| error.include?("normalized differs from fixed semantic scale") }
    end
  end

  def test_independent_oracle_rejects_factor_weight_provenance_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      entry = report.fetch("explanations").fetch("op_101").fetch("considered")
        .find { |candidate| candidate.fetch("provider") == "vipay" }
      factors = entry.fetch("factors").fetch("vipay")
      count = factors.find { |candidate| candidate.fetch("factor") == "count" }
      volume = factors.find { |candidate| candidate.fetch("factor") == "volume" }
      count["weight"] = 0
      count["contribution"] = "0/1"
      volume["weight"] = 4
      volume["contribution"] = "8/5"
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?
      assert result.errors.any? { |error| error.include?("weight differs from canonical configuration") }
    end
  end

  def test_independent_oracle_rejects_factor_reason_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      trace = report.fetch("explanations").fetch("op_101").fetch("considered").first
        .fetch("factors").fetch("vipay").find { |candidate| candidate.fetch("factor") == "conversion_24h" }
      trace["reason"] = "conversion was excellent because of an unrelated rule"
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?
      assert result.errors.any? { |error| error.include?("reason differs from canonical factor semantics") }
    end
  end

  def test_independent_oracle_rejects_recommendation_cause_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      detail = report.fetch("recommendation_details").find do |candidate|
        candidate.fetch("kind") == "count_target_unmet"
      end
      detail.fetch("evidence").fetch("causes").fetch("hard_exclusions")["bank_not_in_list"] = 999
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected recommendation cause tampering to be rejected"
      assert result.errors.any? { |error| error.include?("recommendation[0].evidence.causes differs") }
    end
  end

  def test_independent_oracle_rejects_recommendation_kind_eligibility_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      distribution = report.fetch("assignment_distribution").fetch("quickpay")
      detail = report.fetch("recommendation_details").first
      detail["provider"] = "quickpay"
      detail.fetch("evidence").update(
        "target" => distribution.fetch("target_count_share"),
        "actual" => distribution.fetch("count_share"),
        "gap" => 0,
        "causes" => report.fetch("deviation_causes").fetch("quickpay")
      )
      report.fetch("recommendations")[0] =
        "quickpay is below its count target by 0.00 percentage points; review count target or hard eligibility/capacity."
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected an ineligible recommendation kind to be rejected"
      assert result.errors.any? { |error| error.include?("recommendation[0] count_target_unmet condition") }
    end
  end

  def test_independent_oracle_rejects_hard_forced_kind_without_over_target_condition
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      distribution = report.fetch("assignment_distribution").fetch("payflow")
      detail = report.fetch("recommendation_details").find do |candidate|
        candidate.fetch("kind") == "target_infeasible_hard_forced"
      end
      detail["provider"] = "payflow"
      detail.fetch("evidence").update(
        "target_count" => distribution.fetch("target_count_share"),
        "actual_count" => distribution.fetch("count_share"),
        "target_volume" => distribution.fetch("target_volume_share"),
        "actual_volume" => distribution.fetch("volume_share"),
        "hard_forced_assignments" => report.fetch("deviation_causes").fetch("payflow").fetch("hard_forced_assignments")
      )
      report.fetch("recommendations")[2] =
        "payflow is above target because 1 assignments were hard-forced; raise the target or improve alternatives."
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected hard-forced recommendation without over-target evidence to be rejected"
      assert result.errors.any? { |error| error.include?("target_infeasible_hard_forced condition") }
    end
  end

  def test_independent_oracle_rejects_structural_recommendation_evidence_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      detail = report.fetch("recommendation_details").find do |candidate|
        candidate.fetch("kind") == "structurally_constrained_under_target"
      end
      detail.fetch("evidence")["hard_excluded_operations"] = 999
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected structural recommendation evidence tampering to be rejected"
      assert result.errors.any? { |error| error.include?("hard_excluded_operations differs") }
    end
  end

  def test_independent_oracle_rejects_terminal_kind_without_terminal_fallback
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      distribution = report.fetch("assignment_distribution").fetch("spacepayments")
      detail = report.fetch("recommendation_details").first
      detail["kind"] = "terminal_fallback_deviation"
      detail["provider"] = "spacepayments"
      detail["evidence"] = {
        "terminal_fallback_assignments" => 0,
        "target_count" => distribution.fetch("target_count_share"),
        "actual_count" => distribution.fetch("count_share"),
        "target_volume" => distribution.fetch("target_volume_share"),
        "actual_volume" => distribution.fetch("volume_share"),
        "hard_excluded_alternatives" => {}
      }
      detail["action"] = "terminal fallback is the configured safety path; restore external coverage before changing traffic targets"
      report.fetch("recommendations")[0] =
        "spacepayments exceeded its zero target because 0 operation(s) used the configured terminal fallback after external hard exclusions; restore external coverage before changing targets."
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected terminal recommendation without terminal fallback to be rejected"
      assert result.errors.any? { |error| error.include?("terminal_fallback_deviation condition") }
    end
  end

  def test_independent_oracle_rejects_daily_limit_kind_without_near_limit_utilization
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      utilization = report.fetch("projected_daily_utilization").fetch("vipay")
      detail = report.fetch("recommendation_details").first
      detail["kind"] = "daily_utilization_near_limit"
      detail["provider"] = "vipay"
      detail["evidence"] = {
        "used" => utilization.fetch("used"),
        "limit" => utilization.fetch("limit"),
        "remaining" => utilization.fetch("limit") - utilization.fetch("used"),
        "utilization" => "0/1"
      }
      detail["action"] = "preserve #{detail.fetch("evidence").fetch("remaining")} units of daily headroom or raise the daily limit before increasing this target"
      report.fetch("recommendations")[0] =
        "vipay is near its daily limit at 0.00%; preserve #{detail.fetch("evidence").fetch("remaining")} units of headroom or raise the daily limit."
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected daily recommendation below the near-limit threshold to be rejected"
      assert result.errors.any? { |error| error.include?("daily_utilization_near_limit condition") }
    end
  end

  def test_independent_oracle_rejects_workload_kind_without_count_granularity_condition
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      distribution = report.fetch("assignment_distribution").fetch("payflow")
      detail = report.fetch("recommendation_details").first
      detail["kind"] = "workload_granularity"
      detail["provider"] = "payflow"
      detail["evidence"] = {
        "operation_count" => report.fetch("total_operations"),
        "target_count" => "7/2",
        "actual_count" => distribution.fetch("count"),
        "attainable_counts" => [3, 4]
      }
      detail["action"] = "use a larger workload before changing policy; whole-operation granularity bounds this target gap"
      report.fetch("recommendations")[0] =
        "payflow target is bounded by whole-operation granularity; use a larger workload before changing policy."
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected workload recommendation without a granularity condition to be rejected"
      assert result.errors.any? { |error| error.include?("workload_granularity condition") }
    end
  end

  def test_independent_oracle_rejects_volume_workload_kind_without_small_gap_condition
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      distribution = report.fetch("assignment_distribution").fetch("payflow")
      detail = report.fetch("recommendation_details").first
      detail["kind"] = "volume_workload_granularity"
      detail["provider"] = "payflow"
      detail["evidence"] = {
        "operation_count" => report.fetch("total_operations"),
        "total_volume" => report.fetch("assignment_totals").fetch("volume"),
        "target_volume" => 135_030,
        "actual_volume" => distribution.fetch("volume"),
        "gap" => 134_230,
        "minimum_operation_amount" => 800
      }
      detail["action"] = "use a larger workload or adjust the volume target before changing policy"
      report.fetch("recommendations")[0] =
        "payflow volume target is bounded by whole-operation granularity; use a larger workload or adjust the target before changing policy."
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected volume recommendation without a small-gap condition to be rejected"
      assert result.errors.any? { |error| error.include?("volume_workload_granularity condition") }
    end
  end

  def test_independent_oracle_rejects_subset_sum_kind_without_unreachable_target
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      distribution = report.fetch("assignment_distribution").fetch("quickpay")
      detail = report.fetch("recommendation_details").first
      detail["kind"] = "volume_subset_sum_granularity"
      detail["provider"] = "quickpay"
      detail["evidence"] = {
        "operation_count" => report.fetch("total_operations"),
        "total_volume" => report.fetch("assignment_totals").fetch("volume"),
        "target_volume" => 96_450,
        "actual_volume" => distribution.fetch("volume"),
        "nearest_attainable_volume_below" => 0,
        "nearest_attainable_volume_above" => 96_450,
        "search_bound" => "100 operations / 1000000 volume units"
      }
      detail["action"] = "use a larger or differently sized workload, or adjust the volume target before changing policy"
      report.fetch("recommendations")[0] =
        "quickpay volume target is not reachable by the bounded whole-operation workload; nearest attainable volume is 0 or 96450; use a larger or differently sized workload before changing policy."
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected subset-sum recommendation without an unreachable target to be rejected"
      assert result.errors.any? { |error| error.include?("volume_subset_sum_granularity condition") }
    end
  end

  def test_independent_oracle_rejects_omitted_recommendation_detail
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      report.fetch("recommendations").shift
      report.fetch("recommendation_details").shift
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected omission of a canonical recommendation to be rejected"
      assert result.errors.any? { |error| error.include?("recommendation set differs") }
    end
  end

  def test_independent_oracle_rejects_empty_factor_trace_for_zero_score
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      trace = report.fetch("explanations").fetch("op_103").fetch("considered").first
      trace.fetch("factors").fetch("quickpay").clear
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected an empty zero-score factor trace to be rejected"
      assert result.errors.any? { |error| error.include?("factor evidence must not be empty") }
    end
  end

  def test_independent_oracle_rejects_causal_chain_identity_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      report.fetch("explanations").fetch("op_101").fetch("causal_chain").first["provider"] = "quickpay"
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected causal-chain provider identity tampering to be rejected"
      assert result.errors.any? { |error| error.include?("causal_chain[0].provider differs from attempt") }
    end
  end

  def test_independent_oracle_rejects_causal_chain_selection_reason_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      chain = report.fetch("explanations").fetch("op_101").fetch("causal_chain")
      resolver_entry = chain.find { |entry| entry.fetch("selection_authority") == "resolver" }
      resolver_entry["selection_reason"] = "fallback_highest_composite_score"
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected resolver selection-reason tampering to be rejected"
      assert result.errors.any? { |error| error.include?("selection_reason differs from recomputed resolver semantics") }
    end
  end

  def test_independent_oracle_rejects_decision_summary_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      report.fetch("explanations").fetch("op_101")["decision_summary"] = "arbitrary explanation"
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected decision-summary tampering to be rejected"
      assert result.errors.any? { |error| error.include?("decision_summary differs from causal_chain") }
    end
  end

  def test_fallback_artifact_passes_primary_assignment_accounting_semantics
    dataset = RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, "data/operations_queue_10.json")
    )
    operation = dataset.operations.fetch(0)
    queue = Tempfile.new(["semantic-queue", ".json"])
    queue.write(JSON.generate([operation.to_h]))
    queue.close
    profile = RubyRouting::Case::SubmissionProfile.load(
      path: File.join(ROOT, "data/submission_profile.json"), dataset: dataset
    )
    simulator = RubyRouting::Case::DeterministicSimulator.new(
      outcomes: {
        [operation.operation_id, "vipay"] => :rejected,
        [operation.operation_id, "payflow"] => :approved
      }
    )
    one_operation = RubyRouting::Case::Dataset.new(
      snapshot_at: dataset.snapshot_at, gateway: dataset.gateway, merchant: dataset.merchant,
      providers: dataset.providers, history: dataset.history, operations: [operation]
    )
    router = RubyRouting::Case::Router.new(one_operation, profile: profile, simulator: simulator)
    decisions = router.run
    report = RubyRouting::Case::ReportBuilder.new(
      one_operation, router.state, router.traffic, router.configuration, decisions,
      profile: profile, attempt_ledger: router.attempt_ledger,
      settlement_ledger: router.settlement_ledger
    ).call

    Tempfile.create(["semantic-decisions", ".json"]) do |decisions_file|
      Tempfile.create(["semantic-report", ".json"]) do |report_file|
        RubyRouting::Case::Serializer.write_json(decisions_file.path, decisions.map(&:to_h))
        RubyRouting::Case::Serializer.write_json(report_file.path, report.to_h)

        result = RubyRouting::Case::OrganizerReportSemanticValidator.new(
          providers_path: File.join(ROOT, "data/providers.json"),
          queue_path: queue.path,
          profile_path: File.join(ROOT, "data/submission_profile.json"),
          decisions_path: decisions_file.path,
          report_path: report_file.path
        ).call

        assert result.valid?, result.errors.inspect
      end
    end
  ensure
    queue&.unlink
  end

  def test_configured_volume_target_is_recomputed_for_rich_assignment_distribution
    profile_value = JSON.parse(File.read(File.join(ROOT, "data/submission_profile.json")))
    profile_value["volume_target_source"] = "configured"
    profile_value["volume_share"] = {
      "vipay" => 0.1, "payflow" => 0.2, "quickpay" => 0.7, "spacepayments" => 0
    }

    Tempfile.create(["configured-volume-profile", ".json"]) do |profile_file|
      profile_file.write(JSON.generate(profile_value))
      profile_file.flush
      run = RubyRouting::Case::Runner.new(profile_path: profile_file.path).call

      with_artifacts(run) do |decisions_path, report_path|
        result = RubyRouting::Case::OrganizerReportSemanticValidator.new(
          providers_path: File.join(ROOT, "data/providers.json"),
          queue_path: File.join(ROOT, "data/operations_queue_10.json"),
          profile_path: profile_file.path,
          decisions_path: decisions_path,
          report_path: report_path
        ).call

        assert result.valid?, result.errors.inspect
        report = JSON.parse(File.read(report_path))
        assert_equal "1/5", report.fetch("assignment_distribution").fetch("payflow").fetch("target_volume_share")
        assert_equal "7/10", report.fetch("assignment_distribution").fetch("quickpay").fetch("target_volume_share")
      end
    end
  end

  def test_independent_oracle_rejects_configured_volume_target_mass_above_one
    profile_value = JSON.parse(File.read(File.join(ROOT, "data/submission_profile.json")))
    profile_value["volume_target_source"] = "configured"
    profile_value["volume_share"] = {
      "vipay" => 0, "payflow" => 1, "quickpay" => 1, "spacepayments" => 0
    }

    Tempfile.create(["overmass-volume-profile", ".json"]) do |profile_file|
      profile_file.write(JSON.generate(profile_value))
      profile_file.flush
      run = RubyRouting::Case::Runner.new.call

      with_artifacts(run) do |decisions_path, report_path|
        report = JSON.parse(File.read(report_path))
        report.fetch("assignment_distribution").fetch("payflow").update(
          "target_volume_share" => 1, "volume_deviation" => "-1925/1929"
        )
        report.fetch("assignment_distribution").fetch("quickpay").update(
          "target_volume_share" => 1, "volume_deviation" => "-514/1929"
        )
        report.fetch("assignment_distribution").fetch("spacepayments").update(
          "target_volume_share" => 0, "volume_deviation" => 0
        )
        report.fetch("assignment_distribution").fetch("vipay").update(
          "target_volume_share" => 0, "volume_deviation" => "510/1929"
        )
        File.write(report_path, JSON.generate(report))

        result = RubyRouting::Case::OrganizerReportSemanticValidator.new(
          providers_path: File.join(ROOT, "data/providers.json"),
          queue_path: File.join(ROOT, "data/operations_queue_10.json"),
          profile_path: profile_file.path,
          decisions_path: decisions_path,
          report_path: report_path
        ).call

        refute result.valid?, "expected independent oracle to reject target mass above one"
        assert_includes result.errors.join("; "), "volume target shares must sum to at most one"
      end
    end
  end

  def test_independent_oracle_rejects_incomplete_provider_traffic_target_mass
    providers = JSON.parse(File.read(File.join(ROOT, "data/providers.json")))
    providers.fetch("providers").find { |provider| provider.fetch("payment_system") == "quickpay" }["traffic_percentage"] = 15

    Tempfile.create(["semantic-providers-under-mass", ".json"]) do |providers_file|
      providers_file.write(JSON.generate(providers))
      providers_file.flush
      run = RubyRouting::Case::Runner.new.call

      with_artifacts(run) do |decisions_path, report_path|
        result = RubyRouting::Case::OrganizerReportSemanticValidator.new(
          providers_path: providers_file.path,
          queue_path: File.join(ROOT, "data/operations_queue_10.json"),
          profile_path: File.join(ROOT, "data/submission_profile.json"),
          decisions_path: decisions_path,
          report_path: report_path
        ).call

        refute result.valid?, "expected independent oracle to reject incomplete provider traffic target mass"
        assert_includes result.errors.join("; "), "traffic targets must sum exactly to one"
      end
    end
  end

  def test_independent_oracle_rejects_final_provider_not_backed_by_last_selected_attempt
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      decisions = JSON.parse(File.read(decisions_path))
      forged_decision = decisions.find { |decision| decision["operation_id"] == "op_101" }
      forged_decision["selected_provider"] = "quickpay"
      File.write(decisions_path, JSON.generate(decisions))

      report = JSON.parse(File.read(report_path))
      report.fetch("projected_daily_utilization").fetch("vipay").update("used" => 3252000, "utilization_pct" => 65.04)
      report.fetch("projected_daily_utilization").fetch("quickpay").update("used" => 1433000, "utilization_pct" => 17.91)
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected selected provider/attempt identity mismatch to be rejected"
      assert_includes result.errors.join("; "), "selected_provider must match the last selected attempt"
    end
  end

  def test_independent_oracle_rejects_final_outcome_not_backed_by_last_selected_attempt
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      decisions = JSON.parse(File.read(decisions_path))
      forged_decision = decisions.find { |decision| decision["operation_id"] == "op_101" }
      forged_decision["simulated_result"] = "rejected"
      File.write(decisions_path, JSON.generate(decisions))

      report = JSON.parse(File.read(report_path))
      report.fetch("projected_daily_utilization").fetch("vipay").update("used" => 3252000, "utilization_pct" => 65.04)
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected final outcome/attempt mismatch to be rejected"
      assert_includes result.errors.join("; "), "simulated_result must match the last selected attempt"
    end
  end

  def test_independent_oracle_rejects_selected_attempt_without_an_outcome
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      decisions = JSON.parse(File.read(decisions_path))
      forged_decision = decisions.find { |decision| decision["operation_id"] == "op_101" }
      forged_decision.delete("simulated_result")
      forged_decision.fetch("attempts").find { |attempt| attempt["decision"] == "selected" }.delete("simulated_result")
      File.write(decisions_path, JSON.generate(decisions))

      report = JSON.parse(File.read(report_path))
      report.fetch("projected_daily_utilization").fetch("vipay").update("used" => 3252000, "utilization_pct" => 65.04)
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected missing selected-attempt outcome to be rejected"
      assert_includes result.errors.join("; "), "selected attempt must contain a valid simulated_result"
    end
  end

  def test_independent_oracle_rejects_attempt_after_the_final_selected_attempt
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      decisions = JSON.parse(File.read(decisions_path))
      forged_decision = decisions.first
      forged_decision.fetch("attempts") << {
        "provider" => "vipay",
        "decision" => "skipped",
        "reason" => "forged_trailing_skip"
      }
      File.write(decisions_path, JSON.generate(decisions))

      report = JSON.parse(File.read(report_path))
      report.fetch("skip_reasons")["forged_trailing_skip"] = 1
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected a trailing attempt after the final selected attempt to be rejected"
      assert_includes result.errors.join("; "), "final attempt must be selected"
    end
  end

  def test_independent_oracle_rejects_selected_attempt_without_reason
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      decisions = JSON.parse(File.read(decisions_path))
      decision = decisions.first
      selected = decision.fetch("attempts").find { |attempt| attempt["decision"] == "selected" }
      selected.delete("reason")
      File.write(decisions_path, JSON.generate(decisions))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected a selected attempt without reason to be rejected"
      assert_includes result.errors.join("; "), "selected attempt reason must be a non-empty String"
    end
  end

  def test_independent_oracle_rejects_duplicate_attempt_provider
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      decisions = JSON.parse(File.read(decisions_path))
      decision = decisions.find do |candidate|
        candidate.fetch("attempts").any? { |attempt| attempt["decision"] == "skipped" }
      end
      index = decision.fetch("attempts").index { |attempt| attempt["decision"] == "skipped" }
      duplicate = decision.fetch("attempts").fetch(index).dup
      reason = duplicate.fetch("reason")
      decision.fetch("attempts").insert(index + 1, duplicate)
      File.write(decisions_path, JSON.generate(decisions))

      report = JSON.parse(File.read(report_path))
      report.fetch("skip_reasons")[reason] += 1
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected duplicate attempt provider to be rejected"
      assert_includes result.errors.join("; "), "duplicate attempt provider"
    end
  end

  def test_independent_oracle_rejects_unsupported_attempt_reason
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      decisions = JSON.parse(File.read(decisions_path))
      selected = decisions.first.fetch("attempts").find { |attempt| attempt["decision"] == "selected" }
      selected["reason"] = "forged_reason"
      File.write(decisions_path, JSON.generate(decisions))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected an unsupported attempt reason to be rejected"
      assert_includes result.errors.join("; "), "attempt reason must be supported"
    end
  end

  def test_independent_oracle_rejects_unsupported_skipped_reason
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      decisions = JSON.parse(File.read(decisions_path))
      decision = decisions.find do |candidate|
        candidate.fetch("attempts").any? { |attempt| attempt["decision"] == "skipped" }
      end
      skipped = decision.fetch("attempts").find { |attempt| attempt["decision"] == "skipped" }
      original_reason = skipped.fetch("reason")
      skipped["reason"] = "forged_reason"
      File.write(decisions_path, JSON.generate(decisions))

      report = JSON.parse(File.read(report_path))
      skip_reasons = report.fetch("skip_reasons")
      skip_reasons[original_reason] -= 1
      skip_reasons.delete(original_reason) if skip_reasons[original_reason].zero?
      skip_reasons["forged_reason"] = 1
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected an unsupported skipped reason to be rejected"
      assert_includes result.errors.join("; "), "attempt reason must be supported"
    end
  end

  def test_independent_oracle_rejects_unknown_attempt_decision
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      decisions = JSON.parse(File.read(decisions_path))
      decision = decisions.find do |candidate|
        candidate.fetch("attempts").any? { |attempt| attempt["decision"] == "skipped" }
      end
      skipped = decision.fetch("attempts").find { |attempt| attempt["decision"] == "skipped" }
      reason = skipped.fetch("reason")
      skipped["decision"] = "forged_unknown_decision"
      File.write(decisions_path, JSON.generate(decisions))

      report = JSON.parse(File.read(report_path))
      skip_reasons = report.fetch("skip_reasons")
      skip_reasons[reason] -= 1
      skip_reasons.delete(reason) if skip_reasons[reason].zero?
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected an unknown attempt decision to be rejected"
      assert_includes result.errors.join("; "), "attempt decision must be skipped or selected"
    end
  end

  def test_independent_oracle_rejects_non_object_attempt
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      decisions = JSON.parse(File.read(decisions_path))
      decision = decisions.find do |candidate|
        candidate.fetch("attempts").any? { |attempt| attempt["decision"] == "skipped" }
      end
      index = decision.fetch("attempts").index { |attempt| attempt["decision"] == "skipped" }
      reason = decision.fetch("attempts").fetch(index).fetch("reason")
      decision.fetch("attempts")[index] = nil
      File.write(decisions_path, JSON.generate(decisions))

      report = JSON.parse(File.read(report_path))
      skip_reasons = report.fetch("skip_reasons")
      skip_reasons[reason] -= 1
      skip_reasons.delete(reason) if skip_reasons[reason].zero?
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected a non-object attempt to be rejected"
      assert_includes result.errors.join("; "), "attempt must be an Object"
    end
  end

  def test_shape_valid_business_tampering_is_rejected_without_report_builder_oracle
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      baseline = JSON.parse(File.read(report_path))
      mutations = {
        "total_operations" => ->(report) { report["total_operations"] += 1 },
        "distribution count" => ->(report) { report.fetch("distribution").fetch("vipay")["count"] += 1 },
        "distribution share" => ->(report) { report.fetch("distribution").fetch("vipay")["share_pct"] = 99.0 },
        "distribution target" => ->(report) { report.fetch("distribution").fetch("vipay")["target_pct"] = 99.0 },
        "assignment volume target" => ->(report) {
          report.fetch("assignment_distribution").fetch("payflow")["target_volume_share"] = 0
        },
        "utilization used" => ->(report) { report.fetch("projected_daily_utilization").fetch("payflow")["used"] += 1 },
        "utilization percentage" => ->(report) { report.fetch("projected_daily_utilization").fetch("payflow")["utilization_pct"] = 1.0 },
        "period" => ->(report) { report["period"] = "2099-01-01" }
      }

      mutations.each do |label, mutation|
        forged = Marshal.load(Marshal.dump(baseline))
        mutation.call(forged)
        File.write(report_path, JSON.generate(forged))

        result = semantic_validator(decisions_path, report_path).call

        refute result.valid?, "expected semantic rejection for #{label}"
      end
    end
  end

  def test_independent_oracle_rejects_shape_valid_population_accounting_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      baseline = JSON.parse(File.read(report_path))
      mutations = {
        "skip reasons" => lambda { |report|
          report["skip_reasons"] = report.fetch("skip_reasons").merge("forged_reason" => 1)
        },
        "attempt outcomes" => lambda { |report|
          report["outcomes"] = report.fetch("outcomes").merge("approved" => report.fetch("outcomes").fetch("approved") + 1)
        },
        "final outcomes" => lambda { |report|
          report["final_outcomes"] = report.fetch("final_outcomes").merge("rejected" => report.fetch("final_outcomes").fetch("rejected") + 1)
        },
        "fallback count" => lambda { |report|
          report["fallbacks"] = { "count" => report.fetch("fallbacks").fetch("count") + 1 }
        },
        "assignment totals" => lambda { |report|
          report["assignment_totals"] = report.fetch("assignment_totals").merge("count" => report.fetch("assignment_totals").fetch("count") + 1)
        },
        "skipped attempt outcome" => lambda { |_report|
          decisions = JSON.parse(File.read(decisions_path))
          skipped = decisions.flat_map { |decision| decision.fetch("attempts") }.find { |attempt| attempt["decision"] == "skipped" }
          skipped["simulated_result"] = "approved"
          File.write(decisions_path, JSON.generate(decisions))
        }
      }

      mutations.each do |label, mutation|
        File.write(report_path, JSON.generate(Marshal.load(Marshal.dump(baseline)).tap { |report| mutation.call(report) }))

        result = semantic_validator(decisions_path, report_path).call

        refute result.valid?, "expected independent semantic rejection for #{label}"
      end
    end
  end

  def test_independent_oracle_rejects_recommendation_provenance_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      baseline = JSON.parse(File.read(report_path))
      mutations = {
        "unknown provider" => lambda { |report|
          detail = report.fetch("recommendation_details").first
          detail["provider"] = "ghost"
          report.fetch("recommendations")[0] = "ghost forged recommendation"
        },
        "distribution evidence" => lambda { |report|
          detail = report.fetch("recommendation_details").find { |candidate| candidate.fetch("kind") == "count_target_unmet" }
          detail.fetch("evidence")["target"] = "0"
        },
        "action" => lambda { |report|
          report.fetch("recommendation_details").first["action"] = "forged operator advice"
        }
      }

      mutations.each do |label, mutation|
        File.write(report_path, JSON.generate(Marshal.load(Marshal.dump(baseline)).tap { |report| mutation.call(report) }))

        result = semantic_validator(decisions_path, report_path).call

        refute result.valid?, "expected independent recommendation rejection for #{label}"
      end
    end
  end

  def test_independent_oracle_rejects_recommendation_text_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      detail = report.fetch("recommendation_details").first
      report.fetch("recommendations")[0] = "#{detail.fetch("provider")} forged operator advice"
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected recommendation text tampering to be rejected"
      assert result.errors.any? { |error| error.include?("recommendation") }, result.errors.inspect
    end
  end

  def test_independent_oracle_rejects_explanation_identity_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      baseline = JSON.parse(File.read(report_path))
      mutations = {
        "selected provider" => lambda { |report|
          report.fetch("explanations").fetch("op_101")["selected_provider"] = "quickpay"
        },
        "hard exclusions" => lambda { |report|
          report.fetch("explanations").fetch("op_101")["hard_exclusions"] = [
            { "provider" => "quickpay", "reason" => "bank_not_in_list" }
          ]
        },
        "considered score provider" => lambda { |report|
          report.fetch("explanations").fetch("op_101").fetch("considered").first.fetch("scores")["ghost"] = 1
        }
      }

      mutations.each do |label, mutation|
        File.write(report_path, JSON.generate(Marshal.load(Marshal.dump(baseline)).tap { |report| mutation.call(report) }))

        result = semantic_validator(decisions_path, report_path).call

        refute result.valid?, "expected explanation #{label} tampering to be rejected"
        assert_includes result.errors.join("; "), "explanations.op_101."
      end
    end
  end

  def test_independent_oracle_rejects_rich_projection_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      baseline = JSON.parse(File.read(report_path))
      mutations = {
        "dataset metadata" => lambda { |report|
          report.fetch("dataset")["queue_volume"] = 0
        },
        "provider state" => lambda { |report|
          report.fetch("provider_state").fetch("vipay")["daily_approved_amount"] = 0
        },
        "deviation causes" => lambda { |report|
          report.fetch("deviation_causes").fetch("vipay")["hard_exclusions"] = { "forged_reason" => 99 }
        }
      }

      mutations.each do |label, mutation|
        File.write(report_path, JSON.generate(Marshal.load(Marshal.dump(baseline)).tap { |report| mutation.call(report) }))

        result = semantic_validator(decisions_path, report_path).call

        refute result.valid?, "expected rich #{label} tampering to be rejected"
        assert result.errors.any? { |error| error.include?(label.split.first) }, result.errors.inspect
      end
    end
  end

  def test_independent_oracle_rejects_history_analytics_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      baseline = JSON.parse(File.read(report_path))
      mutations = {
        "history rows" => lambda { |report|
          report.fetch("history")["rows"] = 0
        },
        "history provider approval" => lambda { |report|
          report.fetch("history").fetch("by_provider").fetch("vipay")["approved"] = 0
        }
      }

      mutations.each do |label, mutation|
        File.write(report_path, JSON.generate(Marshal.load(Marshal.dump(baseline)).tap { |report| mutation.call(report) }))

        result = semantic_validator(decisions_path, report_path).call

        refute result.valid?, "expected #{label} tampering to be rejected"
        assert result.errors.any? { |error| error.include?("history") }, result.errors.inspect
      end
    end
  end

  def test_independent_oracle_rejects_period_window_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      report.fetch("period_window")["from"] = "2026-01-01T00:00:00Z"
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected period_window tampering to be rejected"
      assert result.errors.any? { |error| error.include?("period_window") }, result.errors.inspect
    end
  end

  def test_independent_oracle_rejects_submission_profile_identity_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      report.fetch("submission_profile")["profile_id"] = "forged-profile"
      File.write(report_path, JSON.generate(report))

      result = semantic_validator(decisions_path, report_path).call

      refute result.valid?, "expected submission profile tampering to be rejected"
      assert result.errors.any? { |error| error.include?("submission_profile") }, result.errors.inspect
    end
  end

  def test_independent_oracle_rejects_configuration_and_infeasibility_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      baseline = JSON.parse(File.read(report_path))
      mutations = {
        "configuration" => lambda { |report|
          report.fetch("configuration").fetch("weights")["count"] = 999
        },
        "infeasibility" => lambda { |report|
          report["infeasibility"] = [{ "provider" => "ghost", "reason" => "forged" }]
        },
        "final distribution" => lambda { |report|
          report.fetch("distribution").fetch("quickpay")["count"] += 1
        }
      }

      mutations.each do |label, mutation|
        File.write(report_path, JSON.generate(Marshal.load(Marshal.dump(baseline)).tap { |report| mutation.call(report) }))

        result = semantic_validator(decisions_path, report_path).call

        refute result.valid?, "expected #{label} tampering to be rejected"
        expected_error = label == "final distribution" ? "distribution" : label
        assert result.errors.any? { |error| error.include?(expected_error) }, result.errors.inspect
      end
    end
  end

  def test_malformed_history_input_returns_validation_errors_without_raising
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      result = RubyRouting::Case::OrganizerReportSemanticValidator.new(
        providers_path: File.join(ROOT, "data/providers.json"),
        history_path: File.join(ROOT, "data/missing-history.csv"),
        queue_path: File.join(ROOT, "data/operations_queue_10.json"),
        profile_path: File.join(ROOT, "data/submission_profile.json"),
        decisions_path: decisions_path,
        report_path: report_path
      ).call

      refute result.valid?
      assert_includes result.errors.join("; "), "history input not found"
    end
  end

  def test_independent_oracle_rejects_shape_valid_attempt_and_settlement_tampering
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      baseline = JSON.parse(File.read(report_path))
      mutations = {
        "attempt distribution" => lambda { |report|
          report.fetch("attempt_distribution").fetch("vipay")["count"] += 1
        },
        "attempt outcome distribution" => lambda { |report|
          report.fetch("attempt_distribution").fetch("vipay").fetch("outcomes")["approved"] += 1
        },
        "attempt totals" => lambda { |report|
          report.fetch("attempt_totals")["count"] += 1
        },
        "final selection distribution" => lambda { |report|
          report.fetch("final_selection_distribution").fetch("quickpay")["count"] += 1
        },
        "final selection totals" => lambda { |report|
          report.fetch("final_selection_totals")["count"] += 1
        },
        "settlement distribution" => lambda { |report|
          report.fetch("settlement_distribution").fetch("quickpay")["volume"] += 1
        }
      }

      mutations.each do |label, mutation|
        File.write(report_path, JSON.generate(Marshal.load(Marshal.dump(baseline)).tap { |report| mutation.call(report) }))

        result = semantic_validator(decisions_path, report_path).call

        refute result.valid?, "expected independent semantic rejection for #{label}"
      end
    end
  end

  def test_malformed_raw_inputs_return_validation_errors_instead_of_raising
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      Tempfile.create(["semantic-providers", ".json"]) do |providers_file|
        providers = JSON.parse(File.read(File.join(ROOT, "data/providers.json")))
        providers.fetch("providers").first["traffic_percentage"] = "not-exact"
        providers_file.write(JSON.generate(providers))
        providers_file.close

        result = semantic_validator(
          decisions_path, report_path, providers_path: providers_file.path
        ).call

        refute result.valid?
        assert_includes result.errors.join("; "), "traffic_percentage must be exact"
      end
    end
  end

  def test_null_raw_artifact_roots_return_validation_errors
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      Tempfile.create(["semantic-null-providers", ".json"]) do |providers_file|
        Tempfile.create(["semantic-null-queue", ".json"]) do |queue_file|
          Tempfile.create(["semantic-null-profile", ".json"]) do |profile_file|
            Tempfile.create(["semantic-null-decisions", ".json"]) do |decisions_file|
              Tempfile.create(["semantic-null-report", ".json"]) do |report_file|
                [providers_file, queue_file, profile_file, decisions_file, report_file].each do |file|
                  file.write("null")
                  file.close
                end

                canonical_providers = File.join(ROOT, "data/providers.json")
                canonical_queue = File.join(ROOT, "data/operations_queue_10.json")
                canonical_profile = File.join(ROOT, "data/submission_profile.json")
                cases = {
                  "providers" => [providers_file.path, canonical_queue, canonical_profile, decisions_path, report_path, "providers artifact"],
                  "queue" => [canonical_providers, queue_file.path, canonical_profile, decisions_path, report_path, "queue artifact"],
                  "profile" => [canonical_providers, canonical_queue, profile_file.path, decisions_path, report_path, "submission profile input"],
                  "decisions" => [canonical_providers, canonical_queue, canonical_profile, decisions_file.path, report_path, "decisions artifact"],
                  "report" => [canonical_providers, canonical_queue, canonical_profile, decisions_path, report_file.path, "report artifact"]
                }
                cases.each do |label, (provider_path, queue_path, profile_path, decision_path, result_path, expected_error)|
                  result = RubyRouting::Case::OrganizerReportSemanticValidator.new(
                    providers_path: provider_path, queue_path: queue_path, profile_path: profile_path,
                    decisions_path: decision_path, report_path: result_path
                  ).call

                  refute result.valid?, "expected JSON null root rejection for #{label}"
                  assert_includes result.errors.join("; "), expected_error
                end
              end
            end
          end
        end
      end
    end
  end

  def test_malformed_raw_provider_returns_validation_errors_instead_of_raising
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      {
        "missing required field" => lambda { |provider|
          provider.delete("daily_amount_limit")
        },
        "wrong exact field type" => lambda { |provider|
          provider["daily_amount_limit"] = "not-exact"
        }
      }.each do |label, mutation|
        Tempfile.create(["semantic-providers", ".json"]) do |providers_file|
          providers = JSON.parse(File.read(File.join(ROOT, "data/providers.json")))
          provider = providers.fetch("providers").find { |item| item.fetch("payment_system") == "vipay" }
          mutation.call(provider)
          providers_file.write(JSON.generate(providers))
          providers_file.close

          result = semantic_validator(
            decisions_path, report_path, providers_path: providers_file.path
          ).call

          refute result.valid?, "expected malformed raw provider rejection for #{label}"
          error_text = result.errors.join("; ")
          if label == "missing required field"
            assert_includes error_text, "missing fields: daily_amount_limit"
          else
            assert_includes error_text, "daily_amount_limit has an invalid value"
          end
        end
      end
    end
  end

  def test_provider_identifier_and_bank_values_follow_typed_input_contract
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      {
        "blank provider identifier" => lambda { |provider|
          provider["payment_system"] = "   "
        },
        "blank bank identifier" => lambda { |provider|
          provider["banks"] = ["   "]
        },
        "duplicate bank identifier" => lambda { |provider|
          provider["banks"] = ["sberbank", "sberbank"]
        }
      }.each do |label, mutation|
        Tempfile.create(["semantic-provider-identifiers", ".json"]) do |providers_file|
          providers = JSON.parse(File.read(File.join(ROOT, "data/providers.json")))
          provider = providers.fetch("providers").first
          mutation.call(provider)
          providers_file.write(JSON.generate(providers))
          providers_file.close

          result = semantic_validator(
            decisions_path, report_path, providers_path: providers_file.path
          ).call

          refute result.valid?, "expected malformed provider identifier rejection for #{label}"
          error_text = result.errors.join("; ")
          assert_includes error_text, label == "blank provider identifier" ? "payment_system has an invalid value" : "banks has an invalid value"
        end
      end
    end
  end

  def test_malformed_raw_provider_root_returns_validation_errors_instead_of_raising
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      {
        "missing gateway" => lambda { |document|
          document.delete("gateway")
        },
        "wrong merchant type" => lambda { |document|
          document["merchant"] = 123
        }
      }.each do |label, mutation|
        Tempfile.create(["semantic-provider-root", ".json"]) do |providers_file|
          providers = JSON.parse(File.read(File.join(ROOT, "data/providers.json")))
          mutation.call(providers)
          providers_file.write(JSON.generate(providers))
          providers_file.close

          result = semantic_validator(
            decisions_path, report_path, providers_path: providers_file.path
          ).call

          refute result.valid?, "expected malformed raw provider root rejection for #{label}"
          error_text = result.errors.join("; ")
          assert_includes error_text, label == "missing gateway" ? "missing fields: gateway" : "merchant has an invalid value"
        end
      end
    end
  end

  def test_malformed_raw_queue_returns_validation_errors_instead_of_raising
    run = RubyRouting::Case::Runner.new.call

    with_artifacts(run) do |decisions_path, report_path|
      {
        "non-object operation" => [nil, "queue input contains an invalid operation"],
        "missing required field" => [->(operation) { operation.delete("bank") }, "missing fields: bank"],
        "invalid timestamp" => [->(operation) { operation["created_at"] = "not-a-timestamp" }, "created_at has an invalid value"],
        "out-of-order timestamp" => [->(operation) { operation["created_at"] = "2026-07-30T10:00:00+03:00" }, "ordered by non-decreasing created_at"]
      }.each do |label, (mutation, expected_error)|
        Tempfile.create(["semantic-queue", ".json"]) do |queue_file|
          queue = JSON.parse(File.read(File.join(ROOT, "data/operations_queue_10.json")))
          if mutation.respond_to?(:call)
            mutation.call(queue.first)
          else
            queue = [mutation]
          end
          queue_file.write(JSON.generate(queue))
          queue_file.close

          result = semantic_validator(
            decisions_path, report_path, queue_path: queue_file.path
          ).call

          refute result.valid?, "expected malformed raw queue rejection for #{label}"
          assert_includes result.errors.join("; "), expected_error
        end
      end
    end
  end

  def test_empty_queue_has_zero_distribution_shares
    Tempfile.create(["semantic-empty-queue", ".json"]) do |queue_file|
      queue_file.write("[]")
      queue_file.close
      run = RubyRouting::Case::Runner.new(queue_path: queue_file.path).call

      with_artifacts(run) do |decisions_path, report_path|
        result = semantic_validator(
          decisions_path, report_path, queue_path: queue_file.path
        ).call

        assert result.valid?, result.errors.inspect
        assert_equal 0, JSON.parse(File.read(report_path)).fetch("total_operations")
      end
    end
  end

  def test_plus_three_semantic_oracle_uses_snapshot_business_calendar
    queue = Tempfile.new(["semantic-midnight-queue", ".json"])
    operation = JSON.parse(File.read(File.join(ROOT, "data/operations_queue_10.json"))).first
    operation["operation_id"] = "local-after-midnight"
    operation["created_at"] = "2026-07-31T00:30:00+03:00"
    queue.write(JSON.generate([operation]))
    queue.close
    run = RubyRouting::Case::Runner.new(queue_path: queue.path).call

    with_artifacts(run) do |decisions_path, report_path|
      report = JSON.parse(File.read(report_path))
      assert_equal "2026-07-31", report.fetch("period")
      result = semantic_validator(decisions_path, report_path, queue_path: queue.path).call
      assert result.valid?, result.errors.inspect

      report["period"] = "2026-07-30"
      File.write(report_path, JSON.generate(report))
      refute semantic_validator(decisions_path, report_path, queue_path: queue.path).call.valid?
    end
  ensure
    queue&.unlink
  end

  private

  def with_artifacts(run)
    Tempfile.create(["semantic-decisions", ".json"]) do |decisions|
      Tempfile.create(["semantic-report", ".json"]) do |report|
        RubyRouting::Case::Serializer.write_json(decisions.path, run.decisions.map(&:to_h))
        RubyRouting::Case::Serializer.write_json(report.path, run.report.to_h)
        yield decisions.path, report.path
      end
    end
  end

  def semantic_validator(decisions_path, report_path, providers_path: File.join(ROOT, "data/providers.json"),
                         queue_path: File.join(ROOT, "data/operations_queue_10.json"),
                         history_path: File.join(ROOT, "data/operations_history.csv"))
    RubyRouting::Case::OrganizerReportSemanticValidator.new(
      providers_path: providers_path,
      history_path: history_path, queue_path: queue_path,
      profile_path: File.join(ROOT, "data/submission_profile.json"),
      decisions_path: decisions_path,
      report_path: report_path
    )
  end
end
