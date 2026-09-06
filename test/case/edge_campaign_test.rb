# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../test_helper"

class AuthoritativeCaseEdgeCampaignTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def public_queue
    JSON.parse(File.read(File.join(ROOT, "data/operations_queue_10.json")))
  end

  def run_with_queue(operations, configuration: nil, simulator: nil, providers_path: nil,
                     profile_path: File.join(ROOT, "data/submission_profile.json"))
    queue_dir = Dir.mktmpdir("ruby-routing-edge")
    queue_path = File.join(queue_dir, "queue.json")
    File.write(queue_path, JSON.generate(operations))
    RubyRouting::Case::Runner.new(
      providers_path: providers_path || File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: queue_path, configuration: configuration, simulator: simulator,
      profile_path: profile_path
    ).call
  ensure
    FileUtils.remove_entry(queue_dir) if queue_dir && File.exist?(queue_dir)
  end

  def operation_template(id:, created_at:, amount: 1_000)
    public_queue.first.merge(
      "operation_id" => id, "created_at" => created_at,
      "amount" => amount, "payout_requisite" => {
        "sbp" => { "phone" => "7900#{id.gsub(/\D/, "0").ljust(7, "0")[0, 7]}" }
      }
    )
  end

  def profile_path(directory, overrides = {})
    path = File.join(directory, "profile.json")
    profile = JSON.parse(File.read(File.join(ROOT, "data/submission_profile.json")))
    overrides.each { |key, value| profile[key] = value }
    File.write(path, JSON.generate(profile))
    path
  end

  def test_equal_timestamps_keep_queue_order_and_strict_replay
    timestamp = "2026-07-30T09:00:00+03:00"
    run = run_with_queue([
      operation_template(id: "equal-a", created_at: timestamp),
      operation_template(id: "equal-b", created_at: timestamp)
    ])

    assert_equal %w[equal-a equal-b], run.decisions.map(&:operation_id)
    result = RubyRouting::Case::StrictValidator.new(run).call
    assert result.valid?, result.errors.inspect
  end

  def test_rpm_exact_cutoff_is_eligible_after_intermediate_operation_is_blocked
    operations = [
      operation_template(id: "rpm-first", created_at: "2026-07-30T09:00:00+03:00"),
      operation_template(id: "rpm-middle", created_at: "2026-07-30T09:00:30+03:00"),
      operation_template(id: "rpm-boundary", created_at: "2026-07-30T09:01:00+03:00")
    ]
    queue_dir = Dir.mktmpdir("ruby-routing-rpm-profile")
    run = run_with_queue(
      operations,
      profile_path: profile_path(
        queue_dir,
        "rpm_limits" => { "vipay" => 1 }, "simulation_mode" => "approved",
        "weights" => { "priority" => 1 }
      )
    )

    assert_instance_of RubyRouting::Case::SubmissionProfile, run.profile
    assert_equal "vipay", run.decisions.fetch(0).selected_provider
    assert_equal "payflow", run.decisions.fetch(1).selected_provider
    assert_equal "vipay", run.decisions.fetch(2).selected_provider
    assert_equal "rpm_limit", run.decisions.fetch(1).attempts.find { |attempt| attempt.provider == "vipay" }.reason
    refute run.decisions.fetch(2).attempts.any? { |attempt| attempt.provider == "vipay" && attempt.reason == "rpm_limit" }
    result = RubyRouting::Case::StrictValidator.new(run).call
    assert result.valid?, result.errors.inspect
  end

  def test_daily_approval_mutation_rechecks_capacity_and_preserves_assignment_accounting
    operations = [
      operation_template(id: "daily-first", created_at: "2026-07-30T09:00:00+03:00", amount: 100_000),
      operation_template(id: "daily-second", created_at: "2026-07-30T09:01:00+03:00", amount: 100_000)
    ]
    providers_dir = Dir.mktmpdir("ruby-routing-daily-providers")
    providers_path = File.join(providers_dir, "providers.json")
    providers = JSON.parse(File.read(File.join(ROOT, "data/providers.json")))
    providers.fetch("providers").each do |provider|
      provider["limit_amount_max"] = 50_000 if %w[payflow quickpay].include?(provider["payment_system"])
      next unless provider["payment_system"] == "vipay"

      provider["daily_amount_limit"] = 200_000
      provider["daily_approved_amount"] = 100_000
    end
    File.write(providers_path, JSON.generate(providers))
    run = run_with_queue(
      operations, providers_path: providers_path,
      profile_path: profile_path(
        providers_dir, "simulation_mode" => "approved", "weights" => { "priority" => 1 }
      )
    )

    assert_instance_of RubyRouting::Case::SubmissionProfile, run.profile
    assert_equal %w[vipay spacepayments], run.decisions.map(&:selected_provider)
    assert_equal 200_000, run.state.fetch("vipay").daily_approved_amount
    assert_equal 2, run.report.to_h.fetch(:assignment_totals).fetch(:count)
    assert_equal 200_000, run.report.to_h.fetch(:assignment_totals).fetch(:volume)
    assert_equal 2, run.report.to_h.fetch(:settlement_totals).fetch(:count)
    assert_equal 200_000, run.report.to_h.fetch(:settlement_totals).fetch(:volume)
    result = RubyRouting::Case::StrictValidator.new(run).call
    assert result.valid?, result.errors.inspect
  ensure
    FileUtils.remove_entry(providers_dir) if providers_dir && File.exist?(providers_dir)
  end
end
