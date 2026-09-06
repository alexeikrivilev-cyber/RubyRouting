# frozen_string_literal: true

module TestSupport
  # Keep the normative acceptance surface traceable without putting requirement
  # identifiers into production code. Each entry names an actual executable
  # Minitest method; the traceability test verifies the references remain live.
  ACCEPTANCE_EVIDENCE = {
    "AC-001" => ["test/unit/allocation_test.rb#test_count_allocation_minimizes_prefix_discrepancy"],
    "AC-002" => ["test/unit/allocation_test.rb#test_volume_allocation_uses_amount_not_request_count"],
    "AC-003" => ["test/unit/allocation_test.rb#test_large_indivisible_amount_chooses_least_bad_feasible_state"],
    "AC-004" => ["test/concurrency/coordinator_races_test.rb#test_concurrent_assignments_see_committed_allocation_reservation"],
    "AC-005" => ["test/scenario/allocation_opportunity_test.rb#test_provider_absent_from_opportunity_cohort_does_not_create_catch_up_debt"],
    "AC-006" => ["test/scenario/coordinator_safety_test.rb#test_safe_failure_releases_owner_and_fresh_decision_can_settle_elsewhere"],
    "AC-007" => ["test/scenario/coordinator_safety_test.rb#test_unknown_keeps_owner_and_blocks_cross_provider_fallback"],
    "AC-008" => ["test/scenario/orchestrator_simulator_test.rb#test_replayed_successful_intent_does_not_initiate_again", "test/concurrency/coordinator_races_test.rb#test_concurrent_same_intent_commits_at_most_one_owner"],
    "AC-009" => ["test/scenario/projection_replay_test.rb#test_recipient_failure_is_not_counted_as_provider_failure"],
    "AC-010" => ["test/scenario/allocation_opportunity_test.rb#test_no_safe_route_is_visible_when_all_opportunities_are_unavailable"],
    "AC-011" => ["test/scenario/allocation_opportunity_test.rb#test_recovered_provider_does_not_receive_unlimited_historical_catch_up_traffic"],
    "AC-012" => ["test/scenario/allocation_opportunity_test.rb#test_no_safe_route_is_visible_when_all_opportunities_are_unavailable"],
    "AC-013" => ["test/scenario/allocation_opportunity_test.rb#test_policy_epoch_has_an_independent_allocation_projection"],
    "AC-014" => ["test/scenario/projection_replay_test.rb#test_out_of_order_observation_is_recorded_without_regressing_derived_state"],
    "AC-015" => ["test/scenario/projection_replay_test.rb#test_primary_assignment_and_settlement_are_distinct_and_replayable"],
    "AC-016" => ["test/scenario/orchestrator_simulator_test.rb#test_terminal_recipient_failure_does_not_call_fallback_provider"],
    "AC-017" => [
      "test/scenario/projection_replay_test.rb#test_primary_assignment_and_settlement_are_distinct_and_replayable",
      "test/scenario/restart_recovery_test.rb#test_restart_preserves_partial_settlement_reversals_and_idempotency"
    ]
  }.freeze
end
