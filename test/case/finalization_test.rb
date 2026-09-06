# frozen_string_literal: true

require "open3"
require "fileutils"
require "json"
require "digest"
require_relative "../test_helper"

class AuthoritativeCaseFinalizationTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  REQUIRED_ARTIFACTS = %w[routing_decisions_test.json routing_report_test.json].freeze

  def setup
    @artifact_snapshots = REQUIRED_ARTIFACTS.to_h do |name|
      path = File.join(ROOT, name)
      [path, File.exist?(path) ? File.binread(path) : nil]
    end
  end

  def teardown
    @artifact_snapshots&.each do |path, bytes|
      if bytes.nil?
        File.delete(path) if File.exist?(path)
      else
        File.binwrite(path, bytes)
      end
    end
  end

  def test_finalization_requires_explicit_queue_before_writing_artifacts
    paths = %w[routing_decisions_test.json routing_report_test.json].map { |name| File.join(ROOT, name) }
    before = paths.to_h { |path| [path, File.exist?(path) ? Digest::SHA256.file(path).hexdigest : nil] }

    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", File.join(ROOT, "bin/finalize_submission"), chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "--queue"
    after = paths.to_h { |path| [path, File.exist?(path) ? Digest::SHA256.file(path).hexdigest : nil] }
    assert_equal before, after
  end

  def test_non_public_queue_with_same_filename_is_not_checked_against_public_queue
    queue_dir = Dir.mktmpdir("ruby-routing-queue")
    queue_path = File.join(queue_dir, "operations_queue_10.json")
    public_queue = JSON.parse(File.read(File.join(ROOT, "data/operations_queue_10.json")))
    File.write(queue_path, JSON.generate([public_queue.first]))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", File.join(ROOT, "bin/finalize_submission"),
      "--queue", queue_path, chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "generated"
    assert_includes stdout, "queue_kind=explicit_submission_queue"
    manifest_line = stdout.lines.find { |line| line.start_with?("submission_manifest=") }
    refute_nil manifest_line
    assert_equal File.expand_path(queue_path),
                 JSON.parse(manifest_line.delete_prefix("submission_manifest=")).fetch("queue_path")
    refute_includes stdout, "Проверка routing_decisions.json"
  ensure
    FileUtils.remove_entry(queue_dir) if queue_dir && File.exist?(queue_dir)
  end

  def test_finalization_uses_the_canonical_smart_profile
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", File.join(ROOT, "bin/finalize_submission"),
      "--queue", File.join(ROOT, "data/operations_queue_10.json"), chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "queue_kind=public_fixture"
    manifest_line = stdout.lines.find { |line| line.start_with?("submission_manifest=") }
    refute_nil manifest_line
    manifest = JSON.parse(manifest_line.delete_prefix("submission_manifest="))
    assert_equal 10, manifest.fetch("operation_count")
    assert_equal "op_101", manifest.fetch("first_operation_id")
    assert_equal "op_110", manifest.fetch("last_operation_id")
    assert_equal Digest::SHA256.file(File.join(ROOT, "data/operations_queue_10.json")).hexdigest,
                 manifest.fetch("queue_sha256")
    report = JSON.parse(File.read(File.join(ROOT, "routing_report_test.json")))
    profile = report.fetch("submission_profile")
    assert_equal "official-smart-v0.4.2", profile.fetch("profile_id")
    assert_equal "provider.traffic_percentage", profile.fetch("count_target_source")
    assert_equal "provider.traffic_percentage", profile.fetch("volume_target_source")
    assert_equal "conversion", profile.fetch("configuration").fetch("simulation_mode")
    refute_empty profile.fetch("configuration").fetch("count_share")
    refute_empty profile.fetch("configuration").fetch("volume_share")
  end

  def test_submission_manifest_detects_a_post_validation_artifact_change
    queue_path = File.join(ROOT, "data/operations_queue_10.json")
    decisions_path = File.join(ROOT, "routing_decisions_test.json")
    report_path = File.join(ROOT, "routing_report_test.json")
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", File.join(ROOT, "bin/finalize_submission"), "--queue", queue_path, chdir: ROOT
    )
    assert status.success?, stderr

    manifest = RubyRouting::Case::SubmissionManifest.build(
      root: ROOT, queue_path: queue_path, decisions_path: decisions_path, report_path: report_path
    )
    manifest.verify!
    original_report = File.binread(report_path)
    File.binwrite(report_path, original_report + "\n")

    error = assert_raises(RubyRouting::Case::OutputError) { manifest.verify! }
    assert_includes error.message, "changed after manifest validation"
  ensure
    File.binwrite(report_path, original_report) if report_path && original_report
  end

  def test_submission_manifest_rejects_validated_artifacts_not_present_in_head
    queue_dir = Dir.mktmpdir("ruby-routing-release-queue")
    queue_path = File.join(queue_dir, "queue.json")
    public_queue = JSON.parse(File.read(File.join(ROOT, "data/operations_queue_10.json")))
    File.write(queue_path, JSON.generate([public_queue.first]))
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", File.join(ROOT, "bin/finalize_submission"),
      "--queue", queue_path, chdir: ROOT
    )
    assert status.success?, stderr

    manifest = RubyRouting::Case::SubmissionManifest.build(
      root: ROOT,
      queue_path: queue_path,
      decisions_path: File.join(ROOT, "routing_decisions_test.json"),
      report_path: File.join(ROOT, "routing_report_test.json")
    )
    error = assert_raises(RubyRouting::Case::OutputError) { manifest.verify_committed! }
    assert_includes error.message, "committed bytes differ"
  ensure
    FileUtils.remove_entry(queue_dir) if queue_dir && File.exist?(queue_dir)
  end

  def test_submission_artifacts_use_canonical_lf_bytes_for_git_release
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", File.join(ROOT, "bin/finalize_submission"),
      "--queue", File.join(ROOT, "data/operations_queue_10.json"), chdir: ROOT
    )
    assert status.success?, stderr
    manifest_line = stdout.lines.find { |line| line.start_with?("submission_manifest=") }
    manifest = JSON.parse(manifest_line.delete_prefix("submission_manifest="))

    {
      "decisions_path" => manifest.fetch("decisions_sha256"),
      "report_path" => manifest.fetch("report_sha256")
    }.each do |manifest_key, expected_digest|
      path = manifest.fetch(manifest_key)
      bytes = File.binread(path)
      refute_includes bytes, "\r".b
      assert_equal expected_digest, Digest::SHA256.hexdigest(bytes)
    end
  end

  def test_supported_case_cli_reaches_deterministic_conversion_fallback_with_profile_override
    queue_dir = Dir.mktmpdir("ruby-routing-conversion-queue")
    queue_path = File.join(queue_dir, "queue.json")
    profile_path = File.join(queue_dir, "profile.json")
    decisions_path = File.join(queue_dir, "decisions.json")
    report_path = File.join(queue_dir, "report.json")
    queue = JSON.parse(File.read(File.join(ROOT, "data/operations_queue_10.json")))
    File.write(queue_path, JSON.generate([queue.first]))
    profile = JSON.parse(File.read(File.join(ROOT, "data/submission_profile.json")))
    profile["simulation_seed"] = "ruby-routing-v0.4.1-5"
    File.write(profile_path, JSON.generate(profile))

    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", File.join(ROOT, "bin/ruby_routing_case"),
      "--queue", queue_path, "--profile", profile_path,
      "--decisions", decisions_path, "--report", report_path, chdir: ROOT
    )

    assert status.success?, stderr
    decision = JSON.parse(File.read(decisions_path)).first
    assert_equal "expired", decision.fetch("attempts").first.fetch("simulated_result")
    assert_equal "selected", decision.fetch("attempts").first.fetch("decision")
    assert_equal "payflow", decision.fetch("selected_provider")
    assert_equal 1, JSON.parse(File.read(report_path)).fetch("fallbacks").fetch("count")
  ensure
    FileUtils.remove_entry(queue_dir) if queue_dir && File.exist?(queue_dir)
  end

  def test_profile_weight_change_changes_a_controlled_decision_without_code_changes
    queue_dir = Dir.mktmpdir("ruby-routing-profile-sensitivity")
    queue_path = File.join(queue_dir, "queue.json")
    queue = JSON.parse(File.read(File.join(ROOT, "data/operations_queue_10.json")))
    File.write(queue_path, JSON.generate([queue.first]))
    base_profile = JSON.parse(File.read(File.join(ROOT, "data/submission_profile.json")))
    base_profile["simulation_mode"] = "approved"
    base_profile["preferred_amount_ranges"] = {
      "vipay" => { "min" => 100_000, "max" => 200_000 },
      "payflow" => { "min" => 1, "max" => 20_000 },
      "quickpay" => { "min" => 1, "max" => 200_000 }
    }

    profiles = {
      priority: base_profile.merge("weights" => { "priority" => 1 }),
      amount: base_profile.merge("weights" => { "amount" => 1 })
    }
    runs = profiles.to_h do |name, value|
      path = File.join(queue_dir, "#{name}.json")
      File.write(path, JSON.generate(value))
      [name, RubyRouting::Case::Runner.new(queue_path: queue_path, profile_path: path).call]
    end

    assert_equal "vipay", runs.fetch(:priority).decisions.first.selected_provider
    assert_equal "payflow", runs.fetch(:amount).decisions.first.selected_provider
    refute_equal runs.fetch(:priority).decisions.first.selected_provider,
                 runs.fetch(:amount).decisions.first.selected_provider
    assert_equal({ priority: 1 }, runs.fetch(:priority).configuration.weights.values)
    assert_equal({ amount: 1 }, runs.fetch(:amount).configuration.weights.values)
  ensure
    FileUtils.remove_entry(queue_dir) if queue_dir && File.exist?(queue_dir)
  end

  def test_default_profile_emits_simultaneous_count_volume_and_business_factor_evidence
    queue_dir = Dir.mktmpdir("ruby-routing-factor-evidence")
    queue_path = File.join(queue_dir, "queue.json")
    queue = JSON.parse(File.read(File.join(ROOT, "data/operations_queue_10.json")))
    File.write(queue_path, JSON.generate([queue.first]))

    run = RubyRouting::Case::Runner.new(queue_path: queue_path).call
    attempt = run.decisions.first.attempts.find(&:selection)
    factors = attempt.selection.fetch(:factors).values.flat_map { |entries| entries.map { |entry| entry.fetch(:factor) } }

    assert_includes factors, "count"
    assert_includes factors, "volume"
    assert_includes factors, "conversion_24h"
    assert_includes factors, "load"
  ensure
    FileUtils.remove_entry(queue_dir) if queue_dir && File.exist?(queue_dir)
  end

  def test_public_validator_accepts_a_real_multi_attempt_projection
    run = RubyRouting::Case::Runner.new(
      simulator: RubyRouting::Case::DeterministicSimulator.new(
        mode: :approved, outcomes: { ["op_101", "vipay"] => :rejected }
      )
    ).call
    Tempfile.create(["routing-decisions-fallback", ".json"]) do |file|
      RubyRouting::Case::Serializer.write_json(file.path, run.decisions.map(&:to_h))
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, File.join(ROOT, "scripts/validate_10.rb"), file.path, chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "op_101: payflow в списке допустимых"
      assert_equal ["vipay", "payflow"], run.decisions.find { |item| item.operation_id == "op_101" }.attempts.map(&:provider).first(2)
    end
  end
end
