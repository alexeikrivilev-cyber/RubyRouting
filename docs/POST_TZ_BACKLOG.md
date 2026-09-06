# Post-TZ Backlog — v0.4.2 Submission Contract Fidelity & Scoring Semantics Closure

Status: **VERSION_COMPLETE**

Spec: `specifications/018-submission-contract-fidelity-scoring-semantics.md`

Opening baseline: `e9a24923aebfdb1b01223a360b3f3f2b4e84ee45`.

v0.4.1 capabilities remain baseline. This backlog contains only current material gaps and evidence-gated improvements.

## P0 — release artifact contract

### TZ18-001 — TZ-compatible report base projection — CLOSED (2026-09-04)
Current rich report replaces several base fields shown by the TZ. Preserve base `period`, provider `distribution.count/share_pct/target_pct`, `skip_reasons`, `projected_daily_utilization.used/limit/utilization_pct`, and string `recommendations`; keep rich exact fields as additive extensions.

Evidence: `ReportBuilder` emits scalar `period` plus `period_window`, additive base distribution/utilization/recommendation projections and rich exact fields; `test/case/report_contract_test.rb` covers valid and malformed serialized shapes; fresh `bin/finalize_submission` output passed both `SerializedArtifactValidator` and `OrganizerReportContractValidator`. The independent validator also rejects empty provider projections, empty provider identities and utilization percentages above 100.

### TZ18-002 — independent organizer report validator — CLOSED (2026-09-04)
Encode required report keys/types from the authoritative TZ independently of `ReportBuilder`. Finalization must validate the serialized report through this contract after write/read. A self-equality check remains useful but is insufficient.

Evidence: `RubyRouting::Case::OrganizerReportContractValidator` parses and validates the report JSON directly without `Run`/`ReportBuilder`; both case CLIs invoke it after serialization; malformed-field regressions are in `test/case/report_contract_test.rb`.

## P1 — correctness/scoring semantics

### TZ18-101 — exact Case active status — CLOSED (2026-09-04)
Bounded Case eligibility must treat only literal `status == "active"` as active, matching TZ/public validator semantics. Add hidden-like `enabled`/`disabled` regressions without changing production status semantics.

Evidence: `Provider#active?` is literal-only; `test/case/state_test.rb` covers
`enabled` as a hard exclusion; public queue finalization remains green.

### TZ18-102 — phase-correct fallback scoring — CLOSED (2026-09-04)
Primary assignment is recorded once. On rejected/expired fallback, count/volume factors must not add the current operation again through `TrafficLedger#counterfactual`. Add explicit primary/fallback resolution context and an independent fallback ranking regression that fails on the opening baseline.

Evidence: `ConflictResolver` has one explicit `primary`/`fallback` phase; allocation factors are omitted from fallback pressure; Router and strict replay agree; `test/case/fallback_phase_test.rb` proves legacy B vs independent expected C and preserves separate assignment/attempt/settlement ledgers.

### TZ18-103 — concrete selection reason codes — CLOSED (2026-09-04)
Replace generic successful `reason: selected` with stable rubric-readable reason codes while preserving public validator compatibility and rich factor traces in report/internal evidence.

Evidence: Router emits `only_eligible_provider`, `highest_composite_score`,
`fallback_highest_composite_score` and explicit deterministic tie-break reasons when
composite scores are equal; terminal/hard/outcome reasons remain stable. The
tie-break regression proves neutral factor evidence does not masquerade as a
highest-score decision; public validator and case suite pass.

### TZ18-104 — canonical amount strategy is materially active — CLOSED (2026-09-04)
The current committed preferred ranges are identical. Configure meaningful independent preferred bands based on TZ business semantics and prove the amount factor changes a finalization-equivalent conflict without changing hard eligibility or overfitting the public queue.

Evidence: the canonical profile has transparent low/mid/high bands; `test/case/submission_profile_test.rb` loads the profile and proves amount-only selection differs from priority-only selection among the same hard-eligible loaded providers. Public golden operation IDs are not used as the fixture.

### TZ18-105 — neutral factor contribution honesty — CLOSED (2026-09-04)
Equal raw values across candidates must be treated as non-discriminating rather than receiving full normalized contribution. Preserve deterministic tie-break outside causal factor evidence. Fix any amount/factor test that passes only through provider-id tie-break.

Evidence: `ConflictResolver` marks equal raw factors non-discriminating, assigns zero normalized/contribution values and labels the trace; tie-break remains priority/provider identity; focused factor tests pass.

### TZ18-106 — quantitative causal recommendations — CLOSED (2026-09-04)
Add concrete evidence-based actions for near-limit utilization, structural hard exclusions, target deviations and hard-forced alternatives. Base `recommendations` must be judge-readable strings; rich structured evidence moves to additive `recommendation_details`.

Evidence: `ReportBuilder` derives near-limit, target-gap, hard-exclusion and hard-forced details from canonical ledgers/state; `test/case/recommendation_test.rb` checks exact used/limit/headroom, exclusion causes and string projection.

### TZ18-107 — symmetric target feasibility evidence — CLOSED (2026-09-04)
Support constrained-under-target analysis in addition to hard-forced over-target analysis. Distinguish structural hard-rule constraints from small/integer workload granularity; do not overclaim infeasibility.

Evidence: observed exclusions are reported as `structurally_constrained_under_target`; a fresh one-operation `1/2` target is reported as `workload_granularity` and produces no infeasibility entry when no structural cause is present. The same granularity advice is suppressed when the provider is hard-excluded or hard-forced, so workload size is not presented as a remedy for a current hard rule; regression coverage is in `test/case/recommendation_test.rb`.

## P2 — evidence gated

### TZ18-201 — independent volume target provenance — EVIDENCE CLOSED (2026-09-04; no production change)
Count and volume are distinct TZ concepts. Evaluate a configured or clearly history-derived volume target source with explicit provenance after P0/P1 closure. History remains calibration/trends, not current eligibility truth.

Evidence: the canonical profile explicitly records `volume_target_source: provider.traffic_percentage`; the loader rejects a `volume_share` override in that mode and a focused regression proves a `configured` source can supply an independent exact volume map. No authoritative independent volume target is supplied, so silently promoting history would be less honest than the current explicit source.

### TZ18-202 — normalization robustness audit — EVIDENCE CLOSED (2026-09-04; no production change)
Construct candidate-set counterexamples for current min/max normalization. Change to domain normalization only if material ranking instability, weight non-interpretability or misleading explanation is demonstrated.

Evidence: the candidate-relative normalization preserves factor ordering for the supported factor traces; the hidden-like factor campaign found no material inversion or misleading contribution. Raw, normalized and weighted contribution remain independently visible.

### TZ18-203 — terminal identity vs zero participation — CLOSED (2026-09-04)
Prefer explicit `terminal_provider_id` as terminal authority rather than deriving self-provider identity from zero traffic target. Avoid broad refactor unless a concrete ambiguity is reproduced.

Evidence: `test/case/terminal_identity_test.rb` reproduces ambiguous multiple zero-participation providers and requires explicit configuration. `Router`, `ReportBuilder`, strict replay and `bin/ruby_routing_case_demo` now consume that explicit profile identity; canonical profile finalization remains green.

## Completion gate

Known P0/P1 green produced `VERSION_CANDIDATE`; the independent code/data/artifact
audit then found and closed the hard-forced granularity and permissive report-validator
gaps. The fresh full matrix, finalization, validators, clean-checkout run and exact
pushed-head Actions are green. No material local P0/P1 remains.

Any material local P0/P1 returns ACTIVE. v0.4.2 is now `VERSION_COMPLETE` after fresh
full inherited verification, organizer public decisions validation, independent TZ
report validation, strict serialized validation, hidden-like campaigns,
clean-checkout finalization and exact pushed-head Actions success.

## Frozen

No generic recovery/restart hardening, HTTP polish, DB/Redis/queues/microservices, real PSP adapters, ML/neural networks, generic DSL or broad production refactor unless directly required by SPEC-018.
