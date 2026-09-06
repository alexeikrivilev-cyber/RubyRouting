# SPEC-019 — Adversarial Evidence & Contract Semantics Closure

Status: **VERSION_COMPLETE**

Version Goal: **v0.4.3 — Adversarial Evidence & Contract Semantics Closure — VERSION_COMPLETE**

Opening baseline: `277d6b68d568eceb88ece3b3e466987535ff75bd` (completed v0.4.2).

## 1. Objective

Reach a defensible 10/10 submission by resolving the last code-first evidence gaps without expanding architecture. v0.4.2 behavior is preserved unless a fresh independent counterexample proves a material semantic defect.

## 2. Protected completed baseline

The following are not reopened generically:

- TZ-compatible report base shape;
- literal Case `status == active` eligibility;
- primary/fallback scoring phase separation;
- assignment/attempt/settlement ledgers;
- concrete selection reasons;
- meaningful configured amount bands for canonical providers;
- zero contribution for non-discriminating factors;
- deterministic simulation/fallback;
- quantitative recommendations and feasibility evidence;
- public finalization and inherited production safety kernel.

## 3. Evidence rule

A hypothesis must be reproduced before code changes. An implementation self-replay is not an independent semantic oracle. If a hypothesis is falsified, close it explicitly with the test/probe and rationale; do not refactor for theoretical elegance.

## 4. SG19-001 — organizer distribution accounting point

Current internal model distinguishes:

`primary assignment -> provider attempts -> final selected provider -> approved settlement`.

Current base report `distribution` uses primary assignment while decisions expose final selected provider. Build a deterministic fallback case and independently derive primary/final/settlement projections. Re-read the authoritative TZ/report example/rubric and choose the organizer base meaning supported by evidence.

Acceptance:

- no ledger is silently collapsed;
- chosen base projection is explicit in docs/tests;
- fallback artifact demonstrates the chosen semantics;
- if ambiguity remains, the conservative projection is documented and reversible;
- rich report preserves all three distributions.

## 5. AN19-001 — independent semantic report oracle

Add an oracle independent from `ReportBuilder` and Router replay. Inputs are raw provider snapshot, queue, SubmissionProfile and serialized decisions/report.

It must independently verify at least:

- `total_operations`;
- provider identities/population for base distribution;
- distribution count conservation under the chosen accounting point;
- `share_pct` recomputation and rounding tolerance;
- `target_pct` from declared profile source;
- projected daily `used/limit/utilization_pct` from initial snapshot plus approved settlements;
- authoritative report period semantics.

Existing shape and strict validators remain; they do not replace this oracle.

## 6. SG19-002 — normalization stability under candidate perturbation

Current factor normalization is candidate-relative. Build real-factor campaigns that keep A/B facts fixed while adding/removing eligible C. Test canonical and focused weights.

A change is required only if C causes a material A/B ordering or causal-explanation change that is not justified by a real allocation opportunity/denominator change. If confirmed, prefer factor-specific bounded/domain normalization with exact arithmetic and stable trace interfaces.

## 7. STATE19-001 — daily temporal semantics

Public data is single-day. Inspect authoritative material for hidden-queue day-span guarantees. Reproduce a cross-midnight queue near daily limit.

If multi-day is permitted or unspecified and cumulative daily usage is wrong, implement deterministic date-scoped rollover. If authoritative contract is single-day, reject incompatible cross-day queues with a clear InputError. Do not add persistence or schedulers.

## 8. FLEX19-001 — missing amount preference neutrality

A provider without `preferred_amount_ranges` must not obtain implicit maximum preference. Build an additional-provider regression where hard eligibility is unchanged and only amount configuration is absent.

Acceptance: missing optional preference is neutral/non-discriminating; configured canonical providers preserve intended behavior; explanation states absence rather than claiming positive preference.

## 9. Evidence-gated P2

- terminal identity may continue to require zero participation if authoritative data semantics support it; change only with a concrete counterexample;
- direct terminal fallback causality may be enriched only if generated report is materially misleading;
- volume-target provenance stays as the explicit v0.4.2 decision unless new authority appears.

## 10. Verification

Each material slice requires focused tests, adjacent Case regressions, fresh canonical finalization and relevant independent validators. Before candidate run full inherited suites and adversarial campaigns.

Known scope green gives `VERSION_CANDIDATE` only. Then perform a new blind code/data/artifact audit. Any material P0/P1 reopens ACTIVE.

`VERSION_COMPLETE` requires fresh full verification, public decisions validator, independent report shape + semantic validation, strict serialized validation, hidden-like determinism/scale, clean finalization, docs consistency, exact pushed HEAD and exact-head Actions success.

## 11. Non-goals

No DB/Redis/queues/microservices, real PSP, ML/neural networks, generic DSL, broad production refactor or generic recovery hardening without a direct SPEC-019 blocker.
