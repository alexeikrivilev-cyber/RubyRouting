# Current Decisions — Post-TZ v0.4.2

This file is the current decision overlay. SPEC-017/v0.4.1 and SPEC-016/v0.4.0 decisions remain accepted where not superseded below.

## Stable inherited decisions

- authoritative TZ outranks pre-TZ assumptions;
- hard eligibility stays outside scoring and reruns on fallback;
- `RubyRouting::Case` is bounded from production UNKNOWN/economic ownership;
- official priority is lower-is-higher;
- current `conversion_24h` leads historical calibration;
- `spacepayments` is terminal self-provider, not an ordinary competitor;
- deterministic simulation only;
- one `ConflictResolver` is the competition soft-goal authority;
- assignment, attempt and settlement accounting stay separate;
- public validator is a lower bound;
- finalization is a product feature;
- rich internal semantics may be projected conservatively to organizer DTOs.

## TZD-045 — reopen after artifact/scoring audit
Status: accepted.

Decision: v0.4.1 remains a completed baseline. The v0.4.2 audit found and closed
the release-critical report-shape, fallback/scoring and explainability gaps; after
blind closure and exact-head verification the current release is VERSION_COMPLETE
under SPEC-018.

## TZD-046 — TZ report base schema is mandatory compatibility surface
Status: accepted.

Decision: the report structure shown by the TZ is treated as a required base projection even without a public organizer report validator. Rich fields are additive. Do not replace base `period`, provider `distribution.count/share_pct/target_pct`, `projected_daily_utilization`, `skip_reasons` or string recommendations with an internal-only schema.

An independent validator encodes these expectations from the TZ. Self-equality against `ReportBuilder` is not sufficient contract evidence. It also requires non-empty provider projections and bounds compatibility utilization percentages to 0..100.

## TZD-047 — exact arithmetic internally, percentage numbers at compatibility boundary
Status: accepted.

Decision: routing/accounting remains exact Rational/Integer internally. TZ percentage fields are organizer-facing numeric percentages produced only at serialization/projection boundary, rounded deterministically to two decimal places. Rich exact ratios remain available separately; `OrganizerReportContractValidator` checks the resulting JSON shape independently.

## TZD-048 — primary allocation objectives stop after primary assignment
Status: accepted as current bounded TZ interpretation.

Decision: count/volume distribution objectives govern the primary provider assignment. Rejected/expired outcome does not erase or move that assignment. Therefore fallback ranking must not run another count/volume counterfactual for the same operation. Fallback uses the same resolver with explicit phase/context and applicable non-allocation business factors; no second chooser is introduced.

If stronger organizer clarification defines allocation targets over final/settled provider instead, reconcile this decision explicitly before code changes.

## TZD-049 — Case active status matches organizer literal semantics
Status: accepted.

Decision: in the bounded competition model, only literal `status == "active"` is hard-eligible. Broader status aliases may exist elsewhere in production code but cannot change Case eligibility.

## TZD-050 — minimal selection reasons must be concrete
Status: accepted.

Decision: external attempts keep stable compatibility-minimal reasons, but generic successful `selected` is insufficient. Use explicit reason codes such as `only_eligible_provider`, `highest_composite_score`, fallback composite selection, and terminal fallback/exhaustion. Full factor evidence stays in rich report/internal traces.

## TZD-051 — neutral factor is not causal evidence
Status: accepted.

Decision: if every candidate has the same raw value for a factor, that factor is non-discriminating and contributes zero decision pressure. Deterministic tie-break is separate and must not masquerade as factor causality.

Resolution reasons also distinguish equal composite scores
(`deterministic_tie_break` / `fallback_deterministic_tie_break`) from a genuine
highest-score selection.

## TZD-052 — canonical amount preference must be meaningful
Status: accepted.

Decision: preferred amount ranges remain independent of hard min/max and the release profile must make them materially different enough to demonstrate the TZ amount strategy among hard-eligible providers. Configuration must be explainable and general, not fitted to exact public operation IDs.

Evidence: v0.4.2 profile uses explicit broad low-ticket (`payflow` 1,000–20,000),
mid-ticket (`vipay` 5,000–50,000) and higher-ticket (`quickpay` 20,000–150,000)
bands. The canonical-profile regression uses a new 1,000-unit loaded-data
operation and proves amount-only routing differs from priority-only routing while
all three providers remain hard-eligible.

## TZD-053 — recommendations have base strings plus structured details
Status: accepted.

Decision: `recommendations` in the organizer-facing base report is an array of judge-readable action strings. Structured provider/evidence/action objects remain as additive `recommendation_details`. Both projections must be consistent and causal.

## TZD-054 — feasibility is two-sided and evidence-bounded
Status: accepted.

Decision: report both hard-forced over-target and structurally constrained under-target conditions when evidence supports them. Small queue/integer granularity is reported as workload granularity, not automatically called hard infeasibility.

Evidence: `test/case/recommendation_test.rb` verifies observed hard-exclusion
counts/reasons for constrained under-target and a one-operation fractional target
that yields `workload_granularity` with no infeasibility claim.

The same test suite also verifies that a fractional target with an observed hard
exclusion or hard-forced assignment does not receive a misleading workload-size
recommendation: neither a hard exclusion nor a sole eligible provider is repaired
by changing workload size.

## Evidence-gated decisions

- volume target provenance is explicit: the canonical profile declares
  `provider.traffic_percentage`, rejects an undeclared `volume_share` override in that
  mode, and supports a tested `configured` override. No authoritative independent
  volume target is present, so history is not promoted to current target truth;
- candidate-relative min/max normalization remains unchanged after an evidence-first
  monotonicity/weight audit: no material ranking inversion or misleading trace was
  reproduced, and raw/normalized/contribution values stay visible in the trace;
- terminal provider identity is explicit via configuration/profile only. `Router`,
  `ReportBuilder` and strict replay no longer infer it from an arbitrary zero-
  participation provider.

## Open authoritative assumptions

- exact organizer encoding of multiple actually attempted providers inside the `selected|skipped` enum beyond the supplied sample;
- exact `expired` generation algorithm;
- requisite lifecycle beyond availability;
- absent official RPM/minimum-turnover values;
- hidden validator behavior beyond the documented/sample/public contracts.

Keep projections reversible and do not present these as organizer facts.
