# SPEC-018 — Submission Contract Fidelity & Scoring Semantics Closure

Status: **VERSION_COMPLETE**

Version goal: **v0.4.2**

Opening baseline: `e9a24923aebfdb1b01223a360b3f3f2b4e84ee45` (v0.4.1 completed submission-policy baseline).

## Authority

`direct current instruction > authoritative Hack.Genesis TZ/rubric > organizer data/sample/reference/validator > this specification > compatible SPEC-017/SPEC-016 baseline > active ExecPlan > current backlog/matrix/governance > implementation/tests > historical documents`.

Public `scripts/validate_10.rb` is mandatory lower-bound evidence only. It is not the complete output/rubric contract.

## Objective

Close the remaining gap between a strong internal case engine and a competition-safe, rubric-maximizing submission. Do not add a new router or infrastructure. Make the supported finalization path conform to the TZ base artifact contract, remove semantic scoring defects discovered by fresh code audit, strengthen explanations/recommendations, and preserve the mature production safety kernel.

Canonical flow remains:

`official inputs -> hard eligibility -> canonical SubmissionProfile -> primary routing factors -> ConflictResolver -> primary assignment -> deterministic provider attempt/fallback -> settlement -> organizer-compatible decisions/report -> independent artifact validation`.

## Confirmed opening findings

### P0 — TZ report base contract drift

Current `routing_report*.json` is internally rich but does not preserve the base structure shown by the TZ. The TZ base contract includes a scalar `period`, provider `distribution` entries with `count`, `share_pct`, `target_pct`, `projected_daily_utilization`, and string recommendations; teams may add fields. Current output instead uses a period object, internal Rational-oriented distribution fields, `utilization`, and recommendation objects.

This is a release-critical risk because the TZ states that a report with the wrong structure may be treated as not attached. The existing post-serialization validator is correlated with `ReportBuilder` and therefore cannot independently detect this drift.

Required direction: preserve a TZ-compatible base projection and keep rich extensions under additional fields.

### P1 — fallback allocation counterfactual reuses the already-recorded primary assignment

`TrafficLedger` correctly records the first provider as primary assignment before outcome. On rejected/expired fallback, the same ledger is passed to `ConflictResolver`; count/volume factors call `counterfactual`, which adds the current operation again. This creates a phantom second assignment during fallback ranking even though the assignment ledger ultimately contains the operation only once.

Required direction: explicit routing phase semantics. Count/volume distribution objectives apply to primary assignment. After primary assignment has been recorded, fallback ranking must not counterfactually reassign the same operation. Business factors may continue to rank remaining providers.

### P1 — case `active?` is broader than authoritative eligibility

The TZ/public validator requires `status == "active"`. Current Case provider logic treats `enabled` as active. The bounded competition model must use the authoritative exact active semantics; production status vocabularies remain independent.

### P1 — selected reasons are insufficiently concrete

A successful invoked provider currently commonly projects `reason: "selected"`. Rubric explainability requires a concrete reason. Stable reason codes must distinguish at least only-eligible, highest-composite-score, fallback selection and terminal fallback while rich score evidence stays in the report.

### P1 — canonical amount strategy is enabled but non-discriminating

The committed profile gives external providers the same preferred amount band, so amount weight is formally active but normally contributes no routing distinction. Capability tests prove independent preferred bands work, but release policy should expose a meaningful, explainable amount strategy without overfitting the ten public operations.

### P1/P2 — neutral factor contribution is misleading

If all candidates have equal raw value, min/max normalization returns `1`, giving every provider full factor contribution even though the factor did not discriminate. This does not change the winner but weakens explanation integrity. Neutral factors should contribute zero/no decision pressure and be labeled non-discriminating.

### P1 — recommendations are not yet maximally actionable

Recommendations should map evidence to a specific configurable target/rule/limit action. High daily utilization, structural bank/amount exclusions, persistent under-target share and hard-forced over-target share need quantitative, causal recommendations.

### P1 — infeasibility diagnosis is asymmetric

The report handles hard-forced over-target cases better than providers structurally unable to reach an under-target objective. Add evidence-backed constrained-under-target analysis; do not claim mathematical infeasibility without evidence.

### P2 — volume target provenance is semantically weak

The current release profile derives both count and volume targets from `traffic_percentage`. The TZ treats count traffic share and volume share as distinct concepts. Keep volume target source explicit; evaluate a configured or history-derived volume target source only after P0/P1 closure and without treating history as current hard eligibility truth.

### P2 — candidate-relative normalization deserves a skeptical audit

Current min/max normalization makes factor scale depend on the current candidate set. Do not redesign blindly. Build counterexamples and compare against domain-normalized semantics; change only if the evidence shows material instability or explanation distortion.

### P2 — zero participation and terminal self-provider identity are conceptually distinct

Do not infer terminal identity solely from `traffic_percentage == 0` in new semantics. Release policy already has explicit `terminal_provider_id`; keep that authority explicit.

## Protected invariants

- hard constraints are absolute and never become score penalties;
- exact arithmetic stays internal for allocation/scoring;
- `spacepayments` remains terminal fallback, not an ordinary external competitor;
- primary assignment, attempts and settlement remain distinct accounting concepts;
- judge `expired -> next provider` remains bounded to `RubyRouting::Case` and must not weaken production UNKNOWN/economic ownership;
- one canonical SubmissionProfile and one ConflictResolver remain policy authority;
- no handwritten final artifacts as evidence;
- no Rails/DB/Redis/queues/microservices/ML/neural networks/general DSL/real PSP work unless authoritative evidence requires it.

## Required implementation sequence

1. Reproduce every opening finding on exact baseline before changing production code.
2. Add an organizer/TZ report contract projection and an independent validator not derived from `ReportBuilder` output equality.
3. Fix strict Case active-status semantics.
4. Introduce explicit primary-vs-fallback resolution phase and remove phantom allocation counterfactual on fallback.
5. Add an independent fallback-ranking oracle/regression that would fail under the old double-counterfactual behavior.
6. Improve stable selected reason codes while keeping minimal external DTO compatibility.
7. Make the canonical amount preference profile genuinely discriminating and justify it from TZ business semantics, not public-row fitting.
8. Make non-discriminating factors contribution-neutral and keep traces explicit.
9. Strengthen recommendation and target-feasibility evidence.
10. Audit volume target provenance and candidate-relative normalization only after the release-critical gates are green.
11. Run hidden-like campaigns and exact finalization through both public and independent artifact validators.
12. Known scope green means `VERSION_CANDIDATE` only; then run an independent code/data/artifact skeptical pass before completion.

## TZ-compatible report base projection

The submitted report must retain the base fields expected by the TZ while allowing richer extensions:

- `period` — TZ-compatible scalar period/date representation;
- `total_operations`;
- `distribution.<provider>.count`;
- `distribution.<provider>.share_pct`;
- `distribution.<provider>.target_pct`;
- `skip_reasons`;
- `projected_daily_utilization.<provider>.used`;
- `projected_daily_utilization.<provider>.limit`;
- `projected_daily_utilization.<provider>.utilization_pct`;
- `recommendations` — judge-readable strings.

Rich exact projections remain under additional fields such as assignment/attempt/settlement distributions, exact ratio fields, recommendation details, profile provenance, explanation traces and period window.

Internal exact Rational arithmetic must not be weakened; percentage-number conversion happens only at the compatibility projection boundary with a documented rounding rule.

## Acceptance gates

Before candidate:

- fresh `routing_report_test.json` satisfies an independent TZ-shape validator and retains rich analytics;
- public decisions validator stays 0 errors / 0 warnings on public queue;
- Case status `enabled` is not externally eligible unless organizer authority changes;
- fallback ranking has no phantom second count/volume assignment;
- assignment/attempt/settlement conservation remains green;
- selected reasons are concrete and stable;
- canonical amount preference can influence a finalization-equivalent conflict;
- neutral factors do not claim full causal contribution;
- recommendations include provider, evidence, concrete action and judge-readable string projection;
- constrained-under-target evidence is covered;
- exact outputs are deterministic across fresh runs;
- no new P0/P1 in the TZ requirement matrix.

`VERSION_COMPLETE` additionally requires a fresh blind audit, full inherited verification matrix, public + independent artifact validators, clean-checkout finalization, exact pushed-head Actions success and documentation consistency.

## Closure evidence — 2026-09-04

The known P0/P1 scope was first advanced to `VERSION_CANDIDATE`, then independently
audited against production Case code, source data and serialized artifacts. The blind
pass found and fixed misleading workload-granularity advice for hard-forced routing
and permissive acceptance of empty/out-of-range report projections. Deterministic
regressions cover both findings. Fresh full test/property/model/concurrency/fault and
Case matrices, public decisions validation (29 passed, 0 failures, 0 warnings),
independent report validation, strict serialized validation, hidden-like deterministic
campaigns, clean-checkout finalization and exact pushed-head Actions are green. No
material local P0/P1 remains.
