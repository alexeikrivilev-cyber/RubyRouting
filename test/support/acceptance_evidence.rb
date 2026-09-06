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
    ],
    "PTZ-001" => [
      "test/scenario/provider_operation_payload_test.rb#test_adapter_can_execute_from_canonical_request_and_resolution_reuses_it",
      "test/scenario/provider_operation_payload_test.rb#test_restart_reconstructs_the_same_operation_payload"
    ],
    "PTZ-002" => [
      "test/scenario/analytics_dimensions_test.rb#test_measure_and_currency_dimensions_prevent_ambiguous_provider_totals"
    ],
    "PTZ-003" => [
      "test/unit/allocation_test.rb#test_count_tolerance_is_an_absolute_post_decision_l1_measure",
      "test/unit/allocation_test.rb#test_volume_tolerance_is_in_exact_policy_currency_minor_units",
      "test/unit/allocation_test.rb#test_indivisible_assignment_can_exceed_tolerance_but_keeps_exact_evidence"
    ],
    "PTZ-004" => [
      "test/unit/allocation_test.rb#test_recovery_selection_excludes_attempted_provider_before_primary_allocation_authority",
      "test/scenario/coordinator_safety_test.rb#test_recovery_assignment_does_not_advance_primary_allocation"
    ],
    "PTZ-005" => [
      "test/unit/quality_test.rb#test_sparse_success_does_not_outrank_mature_success_evidence",
      "test/unit/quality_test.rb#test_quality_uses_only_the_bounded_recent_evidence_window",
      "test/scenario/quality_hardening_test.rb#test_full_recent_quality_window_is_durable_and_replayable"
    ],
    "PTZ-101" => [
      "test/scenario/health_ranking_test.rb#test_generic_provider_operational_signals_share_hysteresis_but_non_provider_evidence_is_neutral",
      "test/scenario/health_ranking_test.rb#test_ambiguous_transport_marks_provider_timeout_pressure_without_releasing_unknown_owner",
      "test/scenario/health_ranking_test.rb#test_normalized_provider_service_failure_emits_typed_service_health_signal",
      "test/scenario/health_ranking_test.rb#test_definitely_not_sent_transport_emits_typed_transport_health_signal",
      "test/scenario/restart_recovery_test.rb#test_restart_replays_ambiguous_transport_health_without_changing_unknown_ownership"
    ],
    "PTZ-102" => [
      "test/unit/decision_evaluation_test.rb#test_decision_engine_consumes_one_immutable_precomputed_evaluation"
    ],
    "PTZ-103" => [
      "test/unit/opportunity_runtime_test.rb#test_materialization_composes_dynamic_evidence_with_static_hard_gates"
    ],
    "PTZ-104" => [
      "test/scenario/decision_explanation_test.rb#test_application_and_http_explanation_projects_routing_evidence_without_recipient_data"
    ],
    "PTZ-105" => [
      "test/scenario/http_app_test.rb#test_http_public_audit_omits_recipient_and_raw_provider_fields",
      "test/unit/public_audit_fact_test.rb#test_public_projection_is_fail_closed_for_sensitive_and_unknown_payload_fields"
    ],
    "PTZ-106" => [
      "test/scenario/attribution_precision_test.rb#test_deviation_cause_is_exposed_as_a_deterministic_reason_not_causal_inference"
    ],
    "PTZ-107" => [
      "test/scenario/history_performance_evidence_test.rb#test_bounded_history_profile_measures_density_analytics_and_restore",
      "test/scenario/history_performance_evidence_test.rb#test_bounded_profile_measures_concurrent_canonical_throughput"
    ],
    "PTZ2-001" => [
      "test/unit/routing_context_test.rb#test_equivalent_inputs_produce_one_immutable_canonical_route_value",
      "test/unit/routing_context_test.rb#test_persisted_context_is_validated_against_the_raw_context",
      "test/scenario/provider_operation_payload_test.rb#test_restart_reconstructs_the_same_operation_payload"
    ],
    "PTZ2-002" => [
      "test/unit/provider_route_capabilities_test.rb#test_each_explicit_route_dimension_is_a_hard_typed_functional_exclusion",
      "test/scenario/provider_route_capability_test.rb#test_route_capabilities_shape_functional_cohort_explanation_and_restart"
    ],
    "PTZ2-003" => [
      "test/unit/policy_resolution_test.rb#test_specificity_wins_independently_of_registration_order",
      "test/unit/policy_resolution_test.rb#test_equal_precedence_is_ambiguous_under_registration_permutations",
      "test/unit/policy_resolution_test.rb#test_no_match_is_typed_and_orchestrator_does_not_register_state",
      "test/unit/policy_resolution_test.rb#test_selector_definition_and_fingerprint_survive_durable_restart",
      "test/unit/policy_resolution_test.rb#test_explicit_selector_mismatch_is_rejected_before_payout_registration"
    ],
    "PTZ2-004" => [
      "test/scenario/application_service_test.rb#test_typed_configuration_is_applied_and_queryable_as_one_active_snapshot",
      "test/scenario/application_service_test.rb#test_active_configuration_change_does_not_rewrite_an_unresolved_pinned_route",
      "test/scenario/application_service_test.rb#test_invalid_configuration_is_rejected_before_provider_catalog_mutation"
    ],
    "PTZ2-005" => [
      "test/scenario/recovery_schedule_test.rb#test_early_resume_cannot_bypass_schedule_and_exact_due_boundary_allows_resolution",
      "test/scenario/recovery_schedule_test.rb#test_backoff_progression_and_repeated_early_resume_are_deterministic",
      "test/scenario/recovery_schedule_test.rb#test_ttl_expiry_precedes_delayed_recovery_and_reconciliation_is_due_immediately",
      "test/scenario/recovery_schedule_test.rb#test_restart_and_replay_preserve_schedule_and_due_work"
    ],
    "PTZ2-101" => [
      "test/unit/quality_test.rb#test_typed_route_cohorts_precede_labels_and_ignore_label_variations",
      "test/scenario/quality_hardening_test.rb#test_typed_route_quality_timestamp_survives_restart_and_replay"
    ],
    "PTZ2-102" => [
      "test/unit/quality_test.rb#test_quality_staleness_is_independent_from_maturity_and_exact_at_boundary",
      "test/unit/quality_test.rb#test_quality_rejects_non_positive_age_policy_and_non_time_evidence"
    ],
    "PTZ2-103" => [
      "test/scenario/health_ranking_test.rb#test_canonical_provider_path_records_exact_latency_and_replays_provider_health",
      "test/scenario/health_ranking_test.rb#test_canonical_latency_boundary_is_not_pressure",
      "test/scenario/health_ranking_test.rb#test_recipient_latency_does_not_create_provider_pressure",
      "test/scenario/health_ranking_test.rb#test_ambiguous_transport_latency_keeps_unknown_owner_and_transport_health_precedence"
    ],
    "PTZ2-104" => [
      "test/unit/policy_test.rb#test_recovery_objective_is_typed_explicit_and_default_compatible",
      "test/unit/allocation_test.rb#test_recovery_selection_dispatches_through_the_typed_allocation_constrained_objective"
    ],
    "PTZ2-105" => [
      "test/unit/decision_evaluation_test.rb#test_standalone_decision_engine_uses_the_shared_preparation_contract",
      "test/unit/decision_evaluation_test.rb#test_decision_engine_consumes_one_immutable_precomputed_evaluation"
    ],
    "PTZ2-106" => [
      "test/unit/lifecycle_ledger_test.rb#test_pure_outcome_reduction_is_the_shared_status_phase_and_release_contract"
    ],
    "PTZ2-107" => [
      "test/unit/admission_ledger_test.rb#test_capacity_budget_uses_one_concurrent_limit_and_keeps_count_as_legacy_cap",
      "test/unit/admission_ledger_test.rb#test_admission_snapshots_reject_malformed_values_and_accept_each_only_times"
    ],
    "PTZ2-108" => [
      "test/scenario/analytics_dimensions_test.rb#test_application_query_filters_and_groups_only_compatible_dimensioned_measures"
    ],
    "PTZ2-109" => [
      "test/scenario/demo_scenario_test.rb#test_demo_accepts_typed_configuration_without_creating_a_second_routing_path"
    ],
    "PTZ2-110" => [
      "test/unit/fact_store_test.rb#test_indexed_audit_queries_and_pages_preserve_fact_order"
    ]
  }.freeze
end
