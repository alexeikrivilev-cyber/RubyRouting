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
    ],
    "PTZ3-001" => [
      "test/scenario/application_service_test.rb#test_active_configuration_publishes_immutable_monotonic_revisions",
      "test/concurrency/coordinator_races_test.rb#test_active_configuration_race_publishes_a_whole_generation",
      "test/concurrency/coordinator_races_test.rb#test_configuration_lock_is_released_before_provider_io"
    ],
    "PTZ3-002" => [
      "test/unit/routing_context_test.rb#test_malformed_routing_context_shapes_fail_closed",
      "test/unit/routing_context_test.rb#test_false_explicit_routing_context_is_not_treated_as_absent",
      "test/scenario/http_app_test.rb#test_http_rejects_a_scalar_routing_context_instead_of_broadening_the_route"
    ],
    "PTZ3-003" => [
      "test/unit/quality_test.rb#test_quality_filters_each_expired_sample_instead_of_refreshing_the_cohort",
      "test/scenario/quality_hardening_test.rb#test_mixed_age_route_quality_has_live_replay_restart_parity"
    ],
    "PTZ3-004" => [
      "test/scenario/recovery_schedule_test.rb#test_restart_rebases_recovery_schedule_and_ttl_for_a_new_monotonic_origin",
      "test/scenario/restart_recovery_test.rb#test_restart_rebases_throughput_window_for_a_new_monotonic_origin"
    ],
    "PTZ3-005" => [
      "test/scenario/recovery_schedule_test.rb#test_replay_clears_delayed_schedule_when_live_expiry_blocks_reconciliation"
    ],
    "PTZ3-101" => [
      "test/unit/quality_test.rb#test_quality_route_cohorts_are_partitioned_by_currency",
      "test/scenario/quality_hardening_test.rb#test_currency_scoped_route_quality_survives_replay_and_restart"
    ],
    "PTZ3-102" => [
      "test/unit/quality_test.rb#test_sparse_route_evidence_falls_back_until_route_minimum_is_reached"
    ],
    "PTZ3-103" => [
      "test/unit/policy_resolution_test.rb#test_semantic_subsumption_wins_independently_of_registration_order",
      "test/unit/policy_resolution_test.rb#test_equal_priority_incomparable_matches_remain_ambiguous_even_with_different_field_counts",
      "test/unit/policy_resolution_test.rb#test_amount_band_boundaries_and_currency_are_exact",
      "test/unit/policy_resolution_test.rb#test_selector_definition_and_fingerprint_survive_durable_restart"
    ],
    "PTZ3-104" => [
      "test/scenario/application_service_test.rb#test_configuration_snapshot_exposes_non_blocking_diagnostics",
      "test/scenario/application_service_test.rb#test_configuration_compiler_rejects_static_provider_incompatibility_without_mutation",
      "test/scenario/application_service_test.rb#test_configuration_compiler_rejects_static_infeasible_policy_before_publish"
    ],
    "PTZ3-105" => [
      "test/unit/policy_test.rb#test_recovery_objective_is_typed_explicit_and_default_compatible",
      "test/unit/allocation_test.rb#test_recovery_objective_keeps_allocation_authority_before_quality"
    ],
    "PTZ3-106" => [
      "test/unit/allocation_test.rb#test_allocation_authority_keeps_primary_and_recovery_paths_explicit",
      "test/unit/decision_evaluation_test.rb#test_standalone_decision_engine_uses_the_shared_preparation_contract",
      "test/scenario/projection_replay_test.rb#test_lifecycle_replay_preserves_status_resolution_counters_and_contract"
    ],
    "PTZ3-107" => [
      "test/scenario/http_app_test.rb#test_http_exposes_configuration_diagnostics_and_due_recovery_work",
      "test/scenario/http_app_test.rb#test_http_adapter_exposes_submit_query_and_analytics_without_routing_logic",
      "test/scenario/analytics_dimensions_test.rb#test_application_query_filters_and_groups_only_compatible_dimensioned_measures"
    ],
    "PTZ3-108" => [
      "test/scenario/health_ranking_test.rb#test_route_scoped_provider_failure_does_not_quarantine_another_route",
      "test/scenario/health_ranking_test.rb#test_canonical_provider_path_records_exact_latency_and_replays_provider_health",
      "test/scenario/restart_recovery_test.rb#test_working_restore_rejects_missing_health_transition_fact"
    ],
    "PTZ3-109" => [
      "test/scenario/history_performance_evidence_test.rb#test_bounded_history_profile_measures_density_analytics_and_restore",
      "test/scenario/history_performance_evidence_test.rb#test_bounded_profile_measures_concurrent_canonical_throughput"
    ],
    "PTZ3-111" => [
      "test/scenario/application_service_test.rb#test_supplied_configuration_store_seeds_and_remains_the_policy_source_of_truth",
      "test/scenario/application_service_test.rb#test_supplied_configuration_store_bootstraps_provider_history_for_restore"
    ],
    "PTZ3-112" => [
      "test/scenario/http_app_test.rb#test_http_rejects_ambiguous_duplicate_query_parameters"
    ],
    "PTZ3-113" => [
      "test/unit/quality_test.rb#test_quality_as_of_excludes_future_dated_evidence_from_counts_and_latest_timestamp"
    ],
    "PTZ3-114" => [
      "test/scenario/application_service_test.rb#test_configuration_publish_rolls_back_provider_catalog_after_post_commit_failure"
    ],
    "PTZ3-115" => [
      "test/unit/policy_resolution_test.rb#test_policy_currency_participates_in_semantic_subsumption"
    ],
    "PTZ3-116" => [
      "test/unit/quality_test.rb#test_quality_rejects_malformed_routing_context_instead_of_pooling_global_evidence",
      "test/scenario/restart_recovery_test.rb#test_working_restore_rejects_malformed_quality_routing_context"
    ],
    "PTZ3-117" => [
      "test/scenario/health_ranking_test.rb#test_global_health_quarantine_is_a_safety_ceiling_for_scoped_routes"
    ],
    "PTZ3-118" => [
      "test/unit/policy_resolution_test.rb#test_policy_currency_participates_in_semantic_subsumption"
    ],
    "PTZ3-119" => [
      "test/scenario/application_service_test.rb#test_decision_trace_records_active_configuration_revision_for_explanation_and_audit",
      "test/scenario/restart_recovery_test.rb#test_working_restore_rejects_malformed_configuration_revision"
    ],
    "PTZ3-120" => [
      "test/scenario/http_app_test.rb#test_http_rejects_duplicate_json_keys_before_registering_a_payout"
    ],
    "PTZ3-121" => [
      "test/scenario/application_service_test.rb#test_configuration_store_rejects_uncoordinated_public_mutation"
    ],
    "PTZ3-122" => [
      "test/scenario/quality_hardening_test.rb#test_application_quality_query_uses_current_time_for_staleness",
      "test/scenario/http_app_test.rb#test_http_quality_query_replays_evidence_as_of_injected_time"
    ],
    "PTZ3-123" => [
      "test/scenario/health_ranking_test.rb#test_route_scoped_health_query_exposes_the_admission_state_without_global_pooling",
      "test/scenario/http_app_test.rb#test_http_health_query_exposes_route_scoped_admission_state"
    ],
    "PTZ3-124" => [
      "test/scenario/health_ranking_test.rb#test_route_assignment_accepts_global_degraded_health_without_bypassing_the_ceiling",
      "test/scenario/health_ranking_test.rb#test_route_probe_uses_global_probe_budget_and_recovers_the_global_state"
    ],
    "PTZ3-125" => [
      "test/unit/routing_context_test.rb#test_explicit_canonical_routing_context_rejects_unknown_keys",
      "test/scenario/restart_recovery_test.rb#test_working_restore_rejects_unknown_persisted_routing_context_key"
    ],
    "PTZ3-126" => [
      "test/unit/quality_test.rb#test_quality_rejects_malformed_routing_context_instead_of_pooling_global_evidence",
      "test/unit/quality_test.rb#test_quality_snapshot_rejects_unknown_explicit_route_keys",
      "test/unit/provider_operation_test.rb#test_direct_payload_rejects_unknown_explicit_route_keys",
      "test/scenario/health_ranking_test.rb#test_health_rejects_unknown_explicit_route_keys_instead_of_using_global_state"
    ],
    "PTZ3-127" => [
      "test/scenario/http_app_test.rb#test_http_submit_uses_and_exposes_explicit_canonical_routing_context",
      "test/scenario/http_app_test.rb#test_http_rejects_unknown_explicit_routing_context_keys"
    ],
    "PTZ3-128" => [
      "test/scenario/http_app_test.rb#test_http_preserves_typed_no_matching_policy_error",
      "test/scenario/http_app_test.rb#test_http_preserves_typed_ambiguous_policy_error"
    ],
    "PTZ3-129" => [
      "test/scenario/application_service_test.rb#test_application_fails_closed_when_coordinator_catalog_drifts_out_of_band",
      "test/scenario/application_service_test.rb#test_application_resume_checks_catalog_drift_before_expiring_unresolved_state",
      "test/scenario/http_app_test.rb#test_http_reports_configuration_drift_without_registering_a_payout"
    ],
    "PTZ3-130" => [
      "test/scenario/application_service_test.rb#test_resume_recovery_decision_records_the_active_configuration_revision"
    ],
    "PTZ3-131" => [
      "test/scenario/http_app_test.rb#test_http_rejects_unknown_health_route_query_parameters_instead_of_using_global_state",
      "test/scenario/http_app_test.rb#test_http_rejects_alias_health_route_query_parameters_instead_of_silently_broadening"
    ],
    "PTZ3-132" => [
      "test/scenario/application_service_test.rb#test_provider_query_projects_current_runtime_over_the_active_definition"
    ],
    "PTZ3-133" => [
      "test/unit/fact_codec_test.rb#test_durable_codec_and_file_journal_reject_duplicate_json_object_keys"
    ],
    "PTZ3-134" => [
      "test/scenario/http_app_test.rb#test_http_query_endpoints_reject_unsupported_parameters_instead_of_broadening"
    ],
    "PTZ3-135" => [
      "test/scenario/http_app_test.rb#test_http_rejects_malformed_route_filters_even_when_projections_are_empty"
    ],
    "PTZ3-136" => [
      "test/scenario/http_app_test.rb#test_http_routes_without_query_semantics_reject_parameters"
    ],
    "PTZ3-137" => [
      "test/scenario/application_service_test.rb#test_application_policy_registry_is_read_only_compatibility_view"
    ],
    "PTZ3-138" => [
      "test/scenario/application_service_test.rb#test_application_cannot_share_a_policy_registry_with_another_active_generation"
    ],
    "PTZ3-139" => [
      "test/scenario/application_service_test.rb#test_failed_application_bootstrap_does_not_capture_policy_registry"
    ],
    "PTZ3-140" => [
      "test/scenario/application_service_test.rb#test_configuration_compiler_rejects_disjoint_selector_and_hard_amount_ranges"
    ],
    "PTZ3-141" => [
      "test/scenario/application_service_test.rb#test_query_policy_registry_view_tracks_the_active_application_registry"
    ],
    "PTZ3-142" => [
      "test/scenario/http_app_test.rb#test_http_rejects_unknown_payout_fields_before_route_broadening"
    ],
    "PTZ3-143" => [
      "test/unit/policy_resolution_test.rb#test_orchestrator_policy_registry_view_tracks_supplied_registry"
    ],
    "PTZ3-144" => [
      "test/scenario/application_service_test.rb#test_policy_registry_views_do_not_expose_a_partially_published_generation"
    ],
    "PTZ3-145" => [
      "test/scenario/http_app_test.rb#test_http_resume_rejects_a_body_because_it_has_no_body_semantics"
    ],
    "PTZ3-146" => [
      "test/unit/provider_operation_test.rb#test_payload_constructor_preserves_or_rejects_an_explicit_contract"
    ],
    "PTZ3-147" => [
      "test/unit/provider_operation_test.rb#test_payload_constructor_rejects_duplicate_legacy_route_fields"
    ],
    "PTZ3-148" => [
      "test/scenario/capacity_test.rb#test_capacity_amounts_remain_currency_dimensioned_when_active_budget_changes"
    ],
    "PTZ3-149" => [
      "test/unit/admission_ledger_test.rb#test_capacity_release_underflow_does_not_mutate_usage"
    ],
    "PTZ3-150" => [
      "test/scenario/application_service_test.rb#test_rejected_application_bootstrap_does_not_mutate_a_second_provider_catalog"
    ],
    "PTZ3-151" => [
      "test/unit/provider_operation_test.rb#test_executable_operation_identities_reject_non_scalar_values",
      "test/unit/policy_resolution_test.rb#test_policy_resolution_rejects_non_scalar_scope_input",
      "test/scenario/recovery_schedule_test.rb#test_recovery_work_identities_reject_non_scalar_values"
    ],
    "PTZ3-152" => [
      "test/unit/identity_test.rb#test_core_routing_and_state_identities_reject_structured_values"
    ],
    "PTZ3-153" => [
      "test/unit/identity_test.rb#test_provider_configuration_scalars_reject_arbitrary_string_coercion"
    ],
    "PTZ3-154" => [
      "test/unit/identity_test.rb#test_provider_configuration_scalars_reject_arbitrary_string_coercion"
    ],
    "PTZ3-155" => [
      "test/scenario/http_app_test.rb#test_normalizer_configuration_rejects_arbitrary_provider_id_coercion"
    ],
    "PTZ4-001" => [
      "test/scenario/outcome_analytics_test.rb#test_mixed_case_exposes_typed_provider_and_fallback_outcome_counts",
      "test/scenario/outcome_analytics_test.rb#test_exact_duplicate_observation_does_not_duplicate_typed_outcome_counts",
      "test/scenario/outcome_analytics_test.rb#test_http_outcome_query_uses_the_same_canonical_projection"
    ],
    "PTZ4-002" => [
      "test/concurrency/due_recovery_workers_test.rb#test_concurrent_due_workers_start_one_status_resolution_after_restart",
      "test/concurrency/due_recovery_workers_test.rb#test_concurrent_due_workers_start_one_idempotent_retry_after_restart",
      "test/concurrency/due_recovery_workers_test.rb#test_unclassified_adapter_failure_releases_only_the_live_guard"
    ],
    "PTZ4-003" => [
      "test/scenario/configuration_crash_consistency_test.rb#test_fresh_process_crash_after_provider_publication_restarts_only_with_a_coherent_generation"
    ],
    "PTZ4-004" => [
      "test/concurrency/due_recovery_workers_test.rb#test_duplicate_observation_during_blocked_resolution_cannot_release_live_guard",
      "test/concurrency/due_recovery_workers_test.rb#test_duplicate_observation_during_blocked_idempotent_retry_cannot_release_live_guard",
      "test/concurrency/due_recovery_workers_test.rb#test_non_applying_observation_during_blocked_resolution_cannot_release_live_guard",
      "test/concurrency/due_recovery_workers_test.rb#test_stale_interaction_token_cannot_release_a_newer_invocation"
    ],
    "PTZ4-101" => [
      "test/scenario/read_path_hardening_test.rb#test_revision_cache_reprojects_only_age_and_invalidates_after_new_facts",
      "test/scenario/read_path_hardening_test.rb#test_explanation_uses_indexed_payout_facts_without_changing_the_projection"
    ],
    "PTZ4-102" => [
      "test/scenario/read_path_hardening_test.rb#test_revision_cache_reprojects_only_age_and_invalidates_after_new_facts"
    ],
    "PTZ4-103" => [
      "test/scenario/case_fidelity_campaign_test.rb#test_case_campaign_preserves_count_volume_fallback_unknown_and_restart"
    ],
    "PTZ4-104" => [
      "test/scenario/case_fidelity_campaign_test.rb#test_public_surfaces_preserve_every_multi_attempt_history_entry_after_restart"
    ],
    "PTZ5-001" => [
      "test/concurrency/economic_effect_safety_test.rb#test_safe_release_callback_cannot_open_provider_b_while_primary_initiate_is_live"
    ],
    "PTZ5-002" => [
      "test/concurrency/economic_effect_safety_test.rb#test_safe_release_callback_cannot_open_provider_b_while_same_provider_retry_is_live"
    ],
    "PTZ5-003" => [
      "test/concurrency/economic_effect_safety_test.rb#test_safe_temporary_release_callback_cannot_open_provider_b_while_primary_initiate_is_live",
      "test/concurrency/economic_effect_safety_test.rb#test_definitely_not_sent_late_completion_allows_fallback_only_after_live_call_ends",
      "test/concurrency/economic_effect_safety_test.rb#test_adapter_exception_releases_fence_only_after_live_initiate_ends",
      "test/concurrency/economic_effect_safety_test.rb#test_ambiguous_late_completion_does_not_open_fallback_after_live_call_ends",
      "test/concurrency/economic_effect_safety_test.rb#test_terminal_callback_during_live_initiate_stops_without_opening_fallback"
    ],
    "PTZ5-004" => [
      "test/concurrency/economic_effect_safety_test.rb#test_live_read_only_resolution_fences_fresh_assignment_after_release"
    ],
    "PTZ5-101" => [
      "test/concurrency/economic_effect_safety_test.rb#test_authoritative_out_of_order_callbacks_do_not_regress_live_money_movement",
      "test/concurrency/economic_effect_safety_test.rb#test_safe_release_callback_cannot_open_provider_b_while_primary_initiate_is_live",
      "test/scenario/coordinator_safety_test.rb#test_callback_before_dispatch_invalidates_pending_dispatch_token",
      "test/scenario/coordinator_safety_test.rb#test_callback_before_resolution_invalidates_pending_resolution_token"
    ],
    "PTZ5-102" => [
      "test/scenario/orchestrator_simulator_test.rb#test_explicit_transport_error_is_conservatively_ambiguous_and_resolvable",
      "test/scenario/orchestrator_simulator_test.rb#test_definitely_not_sent_transport_failure_releases_ownership",
      "test/scenario/orchestrator_simulator_test.rb#test_raw_adapter_timeout_is_not_guessed_as_definitely_not_sent",
      "test/scenario/orchestrator_simulator_test.rb#test_unclassified_adapter_fault_surfaces_without_losing_resumable_operation"
    ],
    "PTZ5-103" => [
      "test/scenario/durable_crash_campaign_test.rb#test_crash_after_safe_release_restarts_with_fresh_fallback",
      "test/scenario/restart_recovery_test.rb#test_restart_with_unknown_owner_never_unlocks_cross_provider_fallback",
      "test/scenario/restart_recovery_test.rb#test_provider_catalog_removal_survives_restart_without_losing_admission_history",
      "test/scenario/coordinator_safety_test.rb#test_stale_committed_decision_cannot_start_after_ownership_release",
      "test/concurrency/due_recovery_workers_test.rb#test_concurrent_due_workers_start_one_status_resolution_after_restart"
    ],
    "PTZ5-104" => [
      "test/scenario/case_fidelity_campaign_test.rb#test_case_campaign_preserves_count_volume_fallback_unknown_and_restart",
      "test/scenario/case_fidelity_campaign_test.rb#test_public_surfaces_preserve_every_multi_attempt_history_entry_after_restart",
      "test/scenario/deterministic_scenario_matrix_test.rb#test_canonical_orchestrator_matrix_preserves_lifecycle_safety",
      "test/scenario/demo_scenario_test.rb#test_demo_is_explicitly_simulated_and_exercises_safe_fallback",
      "test/scenario/long_history_replay_test.rb#test_long_seeded_history_preserves_live_replay_and_restart_conservation"
    ],
    "PTZ5-105" => [
      "test/scenario/history_performance_evidence_test.rb#test_bounded_history_profile_measures_density_analytics_and_restore",
      "test/scenario/history_performance_evidence_test.rb#test_bounded_profile_measures_concurrent_canonical_throughput"
    ],
    "PTZ5-106" => [
      "test/scenario/projection_replay_test.rb#test_stale_authoritative_observation_cannot_change_health_projection",
      "test/scenario/projection_replay_test.rb#test_late_authoritative_sequence_cursor_prevents_older_health_evidence",
      "test/unit/observation_ledger_test.rb#test_restore_rejects_health_evidence_that_violates_authoritative_order",
      "test/unit/observation_ledger_test.rb#test_restore_keeps_an_exact_duplicate_idempotent_after_a_newer_authoritative_event"
    ],
    "S10-001" => [
      "test/concurrency/economic_effect_safety_test.rb#test_economically_decisive_live_resolution_cannot_open_provider_b_before_late_success"
    ],
    "S10-002" => [
      "test/scenario/durable_crash_campaign_test.rb#test_fresh_process_after_independent_release_without_completion_cannot_start_provider_b",
      "test/scenario/durable_crash_campaign_test.rb#test_fresh_process_after_held_release_and_ttl_expiry_keeps_reconciliation_owner"
    ],
    "S10-003" => [
      "test/concurrency/economic_effect_safety_test.rb#test_raw_timeout_after_independent_release_does_not_open_cross_provider_fallback",
      "test/concurrency/economic_effect_safety_test.rb#test_adapter_exception_releases_fence_only_after_live_initiate_ends",
      "test/concurrency/economic_effect_safety_test.rb#test_status_lookup_definitely_not_sent_does_not_release_original_unknown",
      "test/concurrency/economic_effect_safety_test.rb#test_direct_definitely_not_sent_resolution_observation_cannot_release_original_unknown",
      "test/concurrency/economic_effect_safety_test.rb#test_live_status_lookup_transport_variants_keep_fallback_closed_after_callback"
    ],
    "S10-004" => [
      "test/concurrency/economic_effect_safety_test.rb#test_owning_completion_closes_external_causal_hold_when_provider_reuses_observation_id",
      "test/concurrency/economic_effect_safety_test.rb#test_owning_completion_identity_ignores_local_interaction_duration",
      "test/concurrency/economic_effect_safety_test.rb#test_transport_observation_ids_distinguish_initiate_and_resolution_exchanges",
      "test/concurrency/economic_effect_safety_test.rb#test_any_external_safe_release_retains_owner_until_live_resolution_is_classified",
      "test/unit/observation_ledger_test.rb#test_restore_rejects_causal_hold_for_a_non_current_operation",
      "test/unit/replay_test.rb#test_lifecycle_replay_rejects_causal_completion_after_ownership_release",
      "test/unit/replay_test.rb#test_lifecycle_replay_canonicalizes_padded_causal_completion_identity",
      "test/concurrency/economic_effect_safety_test.rb#test_economically_decisive_live_resolution_cannot_open_provider_b_before_late_success",
      "test/concurrency/economic_effect_safety_test.rb#test_safe_release_after_ttl_keeps_reconciliation_blocked_owner_without_owning_completion"
    ],
    "S10-101" => [
      "test/scenario/configuration_ingress_test.rb#test_canonical_count_configuration_round_trips_through_hash_and_json",
      "test/scenario/configuration_ingress_test.rb#test_canonical_volume_configuration_preserves_exact_rational_values",
      "test/scenario/configuration_ingress_test.rb#test_decoder_rejects_unknown_duplicate_and_malformed_transport_fields",
      "test/scenario/configuration_ingress_test.rb#test_decoded_configuration_publishes_only_through_commands_and_keeps_diagnostics"
    ],
    "S10-102" => [
      "test/scenario/recovery_executor_test.rb#test_one_pass_is_sorted_bounded_and_uses_canonical_resume",
      "test/scenario/recovery_executor_test.rb#test_zero_limit_is_a_bounded_noop_and_invalid_limits_fail_closed",
      "test/scenario/recovery_executor_test.rb#test_provider_exception_is_structured_without_becoming_a_payout_outcome",
      "test/scenario/recovery_executor_test.rb#test_duplicate_executor_workers_share_existing_coordinator_authority"
    ],
    "S10-103" => [
      "test/scenario/operator_composition_campaign_test.rb#test_decoded_configuration_drives_count_volume_fallback_executor_and_restart"
    ],
    "S11-001" => [
      "test/scenario/recovery_executor_test.rb#test_durable_corruption_aborts_the_pass_instead_of_becoming_an_item_error",
      "test/scenario/recovery_executor_test.rb#test_programming_failure_aborts_the_pass_instead_of_becoming_an_item_error",
      "test/scenario/recovery_executor_test.rb#test_configuration_drift_aborts_the_pass_instead_of_becoming_an_item_error",
      "test/scenario/recovery_executor_test.rb#test_typed_provider_failure_does_not_hide_independent_due_work"
    ],
    "S11-002" => [
      "test/scenario/recovery_executor_test.rb#test_future_scan_timestamp_is_rejected_instead_of_misrepresenting_execution_time",
      "test/scenario/recovery_executor_test.rb#test_scan_timestamp_is_not_reported_as_the_execution_timestamp"
    ],
    "S11-003" => [
      "test/concurrency/economic_effect_safety_test.rb#test_unknown_without_resolution_capability_keeps_owner_after_independent_safe_release",
      "test/concurrency/economic_effect_safety_test.rb#test_owning_completion_closes_external_causal_hold_when_provider_reuses_observation_id",
      "test/concurrency/economic_effect_safety_test.rb#test_economically_decisive_live_resolution_cannot_open_provider_b_before_late_success"
    ],
    "S11-004" => [
      "test/unit/observation_ledger_test.rb#test_restore_uses_the_same_identity_rule_as_live_observation",
      "test/unit/observation_ledger_test.rb#test_causal_hold_blocks_safe_release_until_owning_completion",
      "test/unit/replay_test.rb#test_lifecycle_replay_rejects_causal_completion_after_ownership_release",
      "test/concurrency/economic_effect_safety_test.rb#test_unknown_without_resolution_capability_keeps_owner_after_independent_safe_release"
    ],
    "S11-101" => [
      "test/scenario/http_app_test.rb#test_http_put_configuration_uses_the_canonical_decoder_and_application_publication",
      "test/scenario/http_app_test.rb#test_http_configuration_surface_round_trips_exact_rational_values",
      "test/scenario/http_app_test.rb#test_http_put_configuration_rejects_malformed_input_without_mutating_the_active_generation",
      "test/scenario/http_app_test.rb#test_http_put_configuration_returns_bounded_compiler_diagnostics_without_partial_publication"
    ],
    "S11-102" => [
      "test/scenario/http_app_test.rb#test_http_recovery_run_delegates_to_the_bounded_executor_and_resolves_the_pinned_provider",
      "test/scenario/http_app_test.rb#test_http_recovery_run_rejects_unbounded_or_malformed_controls_without_execution",
      "test/scenario/http_app_test.rb#test_http_recovery_run_does_not_expose_raw_provider_exception_messages",
      "test/scenario/recovery_executor_test.rb#test_zero_limit_is_a_bounded_noop_and_invalid_limits_fail_closed"
    ],
    "S11-103" => [
      "test/scenario/demo_scenario_test.rb#test_case_demo_reports_canonical_count_volume_fallback_unknown_recovery_and_analytics",
      "test/scenario/demo_scenario_test.rb#test_case_demo_report_is_deterministic_and_contains_no_runtime_timestamps"
    ],
    "S11-104" => [
      "test/scenario/decision_explanation_test.rb#test_explanation_describes_held_safe_release_without_leaking_causal_hold",
      "test/scenario/decision_explanation_test.rb#test_application_and_http_explanation_projects_routing_evidence_without_recipient_data"
    ],
    "S12-001" => [
      "test/scenario/orchestrator_simulator_test.rb#test_malformed_provider_observation_surfaces_without_synthetic_unknown",
      "test/scenario/recovery_executor_test.rb#test_post_return_provider_validation_failure_aborts_instead_of_becoming_an_item_error",
      "test/scenario/orchestrator_simulator_test.rb#test_raw_adapter_timeout_is_not_guessed_as_definitely_not_sent"
    ],
    "S12-002" => [
      "test/scenario/http_app_test.rb#test_http_due_work_is_bounded_by_default_and_explicit_limit",
      "test/scenario/http_app_test.rb#test_http_due_work_rejects_invalid_bounds_before_querying"
    ],
    "S12-003" => [
      "test/scenario/demo_scenario_test.rb#test_case_demo_isolates_count_vs_volume_on_the_same_skewed_workload",
      "test/scenario/case_fidelity_campaign_test.rb#test_case_campaign_preserves_count_volume_fallback_unknown_and_restart"
    ],
    "S12-004" => [
      "test/scenario/configuration_ingress_test.rb#test_configuration_export_is_the_explicit_fresh_bootstrap_input",
      "test/scenario/configuration_crash_consistency_test.rb#test_fresh_process_crash_after_provider_publication_restarts_only_with_a_coherent_generation"
    ],
    "S12-005" => [
      "test/scenario/http_app_test.rb#test_http_provider_projection_exposes_configured_but_uncallable_adapters",
      "test/scenario/allocation_opportunity_test.rb#test_missing_adapter_is_operational_exclusion_not_functional_cohort_loss"
    ],
    "S12-006" => [
      "test/acceptance_traceability_test.rb#test_every_spec_acceptance_scenario_maps_to_an_executable_test_method"
    ],
    "PTZ9-001" => [
      "test/scenario/http_app_test.rb#test_http_does_not_report_post_provider_contract_failure_as_invalid_request"
    ],
    "PTZ9-002" => [
      "test/scenario/recovery_executor_test.rb#test_raw_initiate_failure_becomes_immediate_due_work_without_changing_identity",
      "test/scenario/recovery_executor_test.rb#test_raw_resolve_failure_stays_due_for_executor_and_retries_same_operation",
      "test/scenario/recovery_executor_test.rb#test_raw_provider_failure_without_recovery_capability_is_not_advertised_as_due",
      "test/scenario/restart_recovery_test.rb#test_fresh_process_discovers_and_resumes_durable_raw_provider_failure"
    ],
    "PTZ9-003" => [
      "test/scenario/demo_scenario_test.rb#test_case_demo_isolates_count_vs_volume_on_the_same_skewed_workload",
      "test/scenario/demo_scenario_test.rb#test_case_demo_uses_distinct_fresh_runtimes_for_strategy_evidence"
    ],
    "PTZ9-004" => [
      "test/scenario/provider_adapter_contract_test.rb#test_universal_executable_port_is_rejected_before_any_payout_work",
      "test/scenario/provider_adapter_contract_test.rb#test_idempotent_retry_capability_uses_initiate_and_never_resolve",
      "test/scenario/recovery_executor_test.rb#test_raw_provider_failure_without_recovery_capability_is_not_advertised_as_due"
    ],
    "PTZ9-005" => [
      "test/acceptance_traceability_test.rb#test_every_spec_acceptance_scenario_maps_to_an_executable_test_method"
    ],
    "PTZ9-006" => [
      "test/unit/replay_test.rb#test_lifecycle_replay_rejects_provider_failure_evidence_that_does_not_match_current_operation",
      "test/scenario/recovery_executor_test.rb#test_raw_resolve_failure_stays_due_for_executor_and_retries_same_operation"
    ],
    "PTZ9-007" => [
      "test/scenario/orchestrator_simulator_test.rb#test_not_implemented_adapter_fault_releases_guard_without_provider_failure_marker"
    ],
    "PTZ9-008" => [
      "test/scenario/orchestrator_simulator_test.rb#test_post_return_duration_processing_error_is_not_provider_contract_or_recovery",
      "test/scenario/orchestrator_simulator_test.rb#test_application_fault_after_valid_provider_return_is_not_provider_contract_error"
    ],
    "PTZ10-001" => [
      "test/scenario/http_app_test.rb#test_http_payout_surfaces_allowlist_outcomes_but_preserve_internal_provider_evidence"
    ],
    "PTZ10-002" => [
      "test/scenario/recovery_executor_test.rb#test_historical_due_work_does_not_expose_a_future_raw_failure_marker",
      "test/scenario/recovery_executor_test.rb#test_historical_due_work_does_not_expose_a_future_reconciliation_block"
    ],
    "PTZ10-003" => [
      "test/scenario/durable_crash_campaign_test.rb#test_fresh_process_after_independent_release_without_completion_cannot_start_provider_b",
      "test/scenario/recovery_executor_test.rb#test_fresh_recovery_executor_discovers_crashed_dispatching_status_lookup",
      "test/scenario/recovery_executor_test.rb#test_fresh_recovery_executor_discovers_crashed_dispatching_idempotent_retry",
      "test/scenario/recovery_executor_test.rb#test_crashed_dispatching_without_recovery_capability_stays_pinned_and_not_due",
      "test/concurrency/due_recovery_workers_test.rb#test_concurrent_recovery_executors_start_one_restart_resolution"
    ],
    "PTZ10-004" => [
      "test/scenario/orchestrator_simulator_test.rb#test_malformed_provider_observation_surfaces_without_synthetic_unknown",
      "test/scenario/orchestrator_simulator_test.rb#test_raw_adapter_timeout_is_not_guessed_as_definitely_not_sent",
      "test/scenario/orchestrator_simulator_test.rb#test_application_fault_after_valid_provider_return_is_not_provider_contract_error",
      "test/scenario/http_app_test.rb#test_http_reports_post_return_application_fault_as_internal_error"
    ],
    "PTZ10-005" => [
      "test/scenario/orchestrator_simulator_test.rb#test_fatal_apply_failure_does_not_strand_the_process_local_interaction_guard",
      "test/scenario/durable_crash_campaign_test.rb#test_fatal_apply_process_death_restarts_from_durable_attempt_without_provider_b"
    ],
    "PTZ10-006" => [
      "test/scenario/demo_scenario_test.rb#test_case_demo_isolates_count_vs_volume_on_the_same_skewed_workload",
      "test/scenario/demo_scenario_test.rb#test_case_demo_uses_distinct_fresh_runtimes_for_strategy_evidence"
    ],
    "PTZ10-007" => [
      "test/acceptance_traceability_test.rb#test_every_spec_acceptance_scenario_maps_to_an_executable_test_method"
    ],
    "PTZ11-001" => [
      "test/scenario/recovery_executor_test.rb#test_post_return_contract_failure_is_not_same_process_restart_work",
      "test/scenario/recovery_executor_test.rb#test_post_return_application_failure_is_not_same_process_restart_work",
      "test/scenario/recovery_executor_test.rb#test_fatal_adapter_failure_is_live_only_but_fresh_process_recovery_remains_discoverable",
      "test/scenario/orchestrator_simulator_test.rb#test_fatal_apply_failure_does_not_strand_the_process_local_interaction_guard",
      "test/scenario/orchestrator_simulator_test.rb#test_not_implemented_adapter_fault_releases_guard_without_provider_failure_marker"
    ],
    "PTZ11-002" => [
      "test/scenario/recovery_executor_test.rb#test_raw_resolve_failure_respects_resolution_budget_in_due_work_and_restart",
      "test/scenario/recovery_executor_test.rb#test_raw_resolve_failure_uses_backoff_for_the_next_allowed_interaction",
      "test/scenario/recovery_executor_test.rb#test_restart_recovery_respects_zero_resolution_budget_before_provider_io"
    ],
    "PTZ11-003" => [
      "test/scenario/http_app_test.rb#test_http_raw_provider_failure_is_generic_non_leaking_and_keeps_canonical_due_work"
    ],
    "PTZ11-004" => [
      "test/scenario/recovery_executor_test.rb#test_due_work_as_of_is_not_historical_time_travel",
      "test/scenario/recovery_executor_test.rb#test_historical_due_work_does_not_expose_a_future_raw_failure_marker",
      "test/scenario/recovery_executor_test.rb#test_historical_due_work_does_not_expose_a_future_reconciliation_block"
    ]
  }.freeze
end
