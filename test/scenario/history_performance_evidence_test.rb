# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/history_profile"

class HistoryPerformanceEvidenceTest < Minitest::Test
  def test_bounded_history_profile_measures_density_analytics_and_restore
    report = RubyRouting::Benchmarking::HistoryProfile.run(payout_count: 12)

    assert_equal 12, report.fetch(:payout_count)
    assert_operator report.fetch(:fact_count), :>, report.fetch(:payout_count)
    assert_equal Rational(report.fetch(:fact_count), 12), report.fetch(:facts_per_payout)
    assert_operator report.fetch(:lifecycle_seconds), :>=, 0
    assert_operator report.fetch(:analytics_seconds), :>=, 0
    assert_operator report.fetch(:restore_seconds), :>=, 0
    assert_operator report.fetch(:audit_page_seconds), :>=, 0
    assert_operator report.fetch(:audit_filtered_page_seconds), :>=, 0
    assert_operator report.fetch(:heap_memsize_delta_bytes), :>=, 0
    assert_operator report.fetch(:heap_live_slot_delta), :>=, 0
  end

  def test_bounded_profile_measures_concurrent_canonical_throughput
    report = RubyRouting::Benchmarking::HistoryProfile.run_concurrent(
      payout_count: 12,
      worker_count: 3
    )

    assert_equal 12, report.fetch(:payout_count)
    assert_equal 3, report.fetch(:worker_count)
    assert_operator report.fetch(:fact_count), :>, report.fetch(:payout_count)
    assert_operator report.fetch(:lifecycle_seconds), :>=, 0
    assert_operator report.fetch(:throughput_per_second), :>, 0
  end
end
