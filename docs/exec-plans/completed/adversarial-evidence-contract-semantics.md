# ExecPlan — v0.4.3 Adversarial Evidence & Contract Semantics Closure

Status: **VERSION_COMPLETE — Phases 0–9 closed**

Specification: `specifications/019-adversarial-evidence-contract-semantics.md`

Opening baseline: `277d6b68d568eceb88ece3b3e466987535ff75bd`.

## Objective

Resolve or evidence-close the final five code-first risks standing between the strong v0.4.2 baseline and a defensible 10/10 release. No broad architecture expansion.

## Phase 0 — exact baseline and reproducers

Before material code changes:

- fetch exact HEAD and exact-head Actions;
- rerun canonical finalization/public validator;
- capture current fallback case where primary != final;
- capture current serialized report and profile;
- add focused probes for semantic report recomputation, candidate perturbation, cross-midnight state and missing preferred amount range.

Classify each finding `CONFIRMED`, `FALSIFIED`, or `AUTHORITY_AMBIGUITY` with evidence.

## Phase 1 — accounting-point contract

Build a hand-checkable A-rejects -> B-final case. Independently compute primary assignment distribution, final selected-provider distribution and approved settlement distribution. Compare to authoritative TZ/report/rubric language.

Deliverable: explicit decision about base `distribution`, regression and docs. Preserve rich three-ledger output. If ambiguous, choose/document conservative reversible projection rather than silently changing core accounting.

Checkpoint: focused fallback/accounting tests + fresh artifact.

Evidence (2026-09-04): `test/case/accounting_semantics_test.rb` independently
derives primary assignment, final selected and approved settlement populations for
both rejected and expired primary outcomes. The report base matches primary
assignment; rich assignment/attempt/settlement projections remain distinct. The
literal TZ/sample/public validator do not define fallback accounting population, so
this is `AUTHORITY_AMBIGUITY`, not a confirmed implementation defect. TZD-061 records
the conservative reversible primary projection; no production accounting change was
justified.

## Phase 2 — independent semantic report oracle

Implement a validator/oracle that consumes raw inputs/profile plus serialized decisions/report and does not use ReportBuilder expected values.

Recompute:

- queue count and provider identities;
- base distribution counts, denominator and shares;
- target percentages;
- daily used/limit/utilization from initial snapshot + approved settlements;
- period semantics.

Add mutations that keep schema valid but alter counts/shares/targets/utilization/period and prove the oracle rejects them.

Checkpoint: shape validator + semantic validator + SerializedArtifactValidator all pass canonical finalization for different reasons.

Evidence (2026-09-04): added `OrganizerReportSemanticValidator` in
`lib/ruby_routing/case/semantic_validator.rb`. It reads raw JSON inputs and the
serialized artifacts, independently derives primary-assignment counts/shares,
profile targets, approved-settlement daily utilization and UTC period, and is
invoked by both release CLIs after serialization. `test/case/report_semantic_test.rb`
passes canonical and A-rejects->B-approved fallback artifacts and rejects
shape-valid mutations of totals/counts/shares/targets/utilization/period. No
`ReportBuilder`/Run expected-value path is used.

## Phase 3 — normalization perturbation audit

Construct A/B/C campaigns using actual FactorRegistry factors and canonical-like mixed weights. Hold A/B static, introduce C as hard-eligible but non-winning.

Separate legitimate changes caused by count/volume opportunity from pure scaling artifacts. If a material unjustified inversion exists, implement the smallest exact factor-domain normalization change and verify weights/traces remain interpretable. If not, evidence-close current normalization with explicit perturbation tests.

Checkpoint: focused resolver tests + public finalization unchanged/intentional.

Evidence (2026-09-04): the deterministic A/B/C campaign uses the real
count/volume/priority/amount/conversion/load factors and canonical mixed
weights. With A/B facts and traffic ledger fixed, adding hard-eligible C (which
does not win) changed the old candidate-relative result from B to A because it
changed factor ranges, while A/B raw values stayed identical. This is a
`CONFIRMED` unjustified scale artifact, not a new allocation opportunity.
`ConflictResolver` now requires an explicit normalization pool, rejects a pool
that omits a scored candidate, and uses the same complete eligible pool in the
canonical Router and strict replay. The campaign verifies stable A/B selection
and normalized differences; canonical public outputs remain unchanged.

## Phase 4 — daily temporal contract

Read authoritative material again for day-span semantics. Create a cross-midnight queue around daily limit.

- multi-day allowed/unspecified + bug confirmed -> date-scope daily usage/reset deterministically;
- explicitly single-day -> add strict loader/runner rejection for cross-day queue;
- do not invent scheduled reset/persistence.

Checkpoint: single-day public data unchanged, new temporal regression, strict replay/state conservation green.

Evidence (2026-09-04): the deterministic cross-midnight queue started with a
90/100 snapshot, approved 10 at 23:59, and approved 10 at 00:01. The old
cumulative state rejected A on the second date and selected B. Since the TZ
allows an ordered queue and calls the constraint daily, this was `CONFIRMED`
stale daily state rather than a reason to reject multi-day input. `ProviderCaseState`
now anchors the supplied baseline to the UTC snapshot date and resets only daily
approved amount when the ordered operation date advances. In-progress, RPM,
attempt, route and settlement counters are not reset. The temporal regression
proves A/A selection, latest-day utilization and strict replay conservation.

## Phase 5 — missing amount-band neutrality

Add an external provider with no preferred range. Prove baseline missing config can be favored as raw=1. Replace with explicit neutral/non-discriminating semantics with minimal API change. Existing configured providers and canonical profile must remain stable.

Checkpoint: provider-independence/factor explanation tests + finalization.

Evidence (2026-09-04): a hard-eligible provider with no preferred amount band
was independently compared with a configured provider whose band did not match.
The old factor returned raw `1` for the missing provider and selected it. This
was `CONFIRMED` as a false strongest preference. Missing optional configuration
now returns exact raw `0`; when all candidates have no matching preference the
factor is marked non-discriminating and contributes zero, while configured
bands retain their existing behavior and explanation. Regression:
`test/case/amount_band_neutrality_test.rb`.

## Phase 6 — P2 only if evidence demands

Probe terminal zero-participation coupling and direct-terminal deviation explanations. No code change without a concrete authoritative/material problem.

Evidence (2026-09-04): the explicit-terminal probe with two zero-traffic
providers showed that any configured active zero-participation provider can be
the terminal identity, while another zero-participation provider remains an
external `zero_participation` exclusion. This is `FALSIFIED` as a coupling
defect; no routing change was justified. A separate all-external-hard-excluded
probe produced 100% terminal assignment against a zero target with no report
recommendation, which was `CONFIRMED` misleading causality. The report now
emits terminal fallback counts, hard-excluded alternative reasons, quantitative
target/actual evidence and a deterministic action. Regression:
`test/case/terminal_causality_test.rb`.

## Phase 7 — candidate evidence

Run:

- bundle/full inherited verification;
- full Case suite;
- all five adversarial campaigns;
- canonical finalization;
- public decisions validator;
- independent report shape and semantic validators;
- strict in-memory/serialized validators;
- hidden-like scale/determinism;
- matrix/rubric traceability.

If all P1 items are fixed/evidence-closed, mark `VERSION_CANDIDATE`, not complete.

Evidence (2026-09-04, candidate checkpoint `8f565d8b9ae4191f77b37730032dfbc78042f2fe`):
fresh `bundle check`; full `bundle exec rake test` (852 runs, 13,585
assertions); `property` (4/1,210); `model` (3/2,958); `concurrency`
(45/1,451); `fault` (407/4,900); and `case` (112/628) all pass with zero
failures/errors. Clean finalization generated both root artifacts; the public
decisions validator passed 29/0/0, the independent semantic report oracle
accepted the serialized report, and the serialized/strict Case suites passed.
The 1,000-operation Case scale campaign remains byte-deterministic and passes
strict and independent validation. This is a candidate gate only; Phase 8 blind
closure and exact-head CI remain outstanding.

Blind-audit finding (2026-09-04): the candidate was returned to ACTIVE after an
independent malformed-input probe passed a raw provider with
`traffic_percentage: "not-exact"` to the semantic oracle and reproduced an
uncaught `NoMethodError` instead of a failed validation result. The same seam
was checked for malformed provider/queue roots. The minimal boundary fix makes
invalid provider/queue/profile/report roots, identities and non-exact traffic
targets fail closed as `ValidationResult` errors; canonical inputs and the
shape-valid semantic corruption tests remain unchanged. Regression coverage is
in `test/case/report_semantic_test.rb`. This finding is closed in code, but the
full candidate matrix must be rerun before a new candidate gate.

The same blind pass then used an empty queue, which the canonical Case loader
permits, and reproduced an uncaught `ZeroDivisionError` while recomputing
distribution shares. The oracle now treats the zero-count denominator as an
exact zero share and has a dedicated empty-queue regression. This second
boundary finding is closed in code; candidate status remains ACTIVE pending a
fresh post-fix matrix.

As an adjacent evidence-hardening step, the hidden-like 1,000-operation scale
campaign was checked for validator correlation: its test previously covered
strict self-artifact equality and public report shape, but not the raw-input
semantic oracle. The campaign now serializes its synthetic provider snapshot,
queue and profile and runs the independent semantic recomputation against the
scale decisions/report. The focused scale test remains deterministic and green;
this adds evidence coverage without changing routing semantics.

Fresh blind closure after TZ19-106/107 (2026-09-04): the changed semantic
validator was reviewed code-first and re-probed with malformed provider/queue
inputs and an empty queue; each now returns a validation result or valid zero
shares without raising. Canonical accounting, serialized report tampering,
candidate perturbation, cross-midnight rollover, missing-band neutrality and
terminal-causality regressions remain green. Both finalization entrypoints
produce byte-identical decisions/report artifacts; the 1,000-operation campaign
passes strict, public-shape and independent semantic validation. No new
material P0/P1 was found in alternate entrypoints, report denominators, target
provenance, configured provider sets, history usage or terminal explanations.
The active scope is therefore a `VERSION_CANDIDATE` again; a fresh final matrix
and exact pushed-head CI are still required before completion.

## Phase 8 — fresh blind closure

Ignore backlog status and re-read actual code/data/artifacts. Attack accounting/report denominators, semantic-oracle independence, target provenance, candidate-set effects, missing configuration defaults, cross-day state, terminal causality, alternate entrypoints and public-data overfit.

Any material P0/P1 returns ACTIVE.

## Phase 9 — VERSION_COMPLETE gate

After the last material change run fresh full matrix, finalization, all validators, adversarial campaigns and clean-checkout evidence; sync docs; push exact HEAD; wait for exact-head GitHub Actions success. Only then move plan to completed and declare v0.4.3 VERSION_COMPLETE.

Evidence (2026-09-04, exact pushed HEAD
`13efbeba48f1726b91b71b1677d3541dd4f9f433`): `bundle check`; fresh full
`test` 855/13,603, `property` 4/1,210, `model` 3/2,958, `concurrency`
45/1,447, `fault` 407/4,900 and Case 115/637 all passed with zero
failures/errors. Canonical and alternate finalization generated deterministic
artifacts; public decisions validation passed 29/0/0; independent report shape
and semantic validation, strict in-memory/serialized validation, all five
SPEC-019 adversarial campaigns, 1,000-operation independent scale validation,
and clean-checkout finalization passed. The post-candidate blind audit found
and closed only TZ19-106/107 validator-boundary defects; the subsequent blind
pass found no material P0/P1. Exact-head GitHub Actions run `33852436704`
completed successfully for this SHA. v0.4.3 is VERSION_COMPLETE.

## Session rule

Do not stop after a single green phase when the next phase is derivable. Each material checkpoint gets a coherent commit/push and evidence note in this plan.
