# AGENTS.md

## Mission

Drive RubyRouting to a defensible 10/10 Hack.Genesis submission under the authoritative TZ and rubric.

Current Version Goal: **v0.4.3 — Adversarial Evidence & Contract Semantics Closure — VERSION_COMPLETE**.

Opening baseline: `277d6b68d568eceb88ece3b3e466987535ff75bd` (completed v0.4.2 baseline).

## Read before coding

`README.md -> AGENTS.md -> docs/AUTHORITY.md -> SPEC-019 -> compatible SPEC-018/SPEC-017/SPEC-016 -> TZ_REQUIREMENT_MATRIX -> completed v0.4.3 ExecPlan -> POST_TZ_BACKLOG -> current architecture/decisions/completion/testing/workflow -> actual data/code/artifacts/CI`.

Documentation states intended authority. Exact code and generated artifacts prove reality.

## Operating rule

This cycle is an adversarial evidence session, not a feature sprint.

For every finding:

`exact HEAD -> independent reproducer/counterexample -> state the invariant/contract -> classify confirmed or falsified -> smallest justified change OR evidence-close unchanged behavior -> focused tests -> adjacent tests -> real finalization/artifacts -> independent oracle -> broad verification -> docs/matrix/plan -> commit/push`.

Do not “fix” a hypothesis before reproducing it. Do not preserve a design merely because existing tests replay the same implementation.

## Mandatory work order

### P1-A — organizer distribution accounting point — CLOSED

Current code intentionally records count/volume against the first selected provider, while `selected_provider` is the final cascade provider. SPEC-019 evidence-closed the authority ambiguity with a conservative, reversible primary-assignment base projection and retained rich final/settlement ledgers.

Required evidence:

- build a deterministic rejection/expiry case where primary provider != final provider;
- independently compute three candidate projections: primary assignment, final selected route, approved settlement;
- compare each to the literal TZ language and report example/rubric;
- document the chosen contract and keep all three rich ledgers regardless;
- if authority is genuinely ambiguous, choose the most conservative projection and make the ambiguity explicit/reversible.

Do not silently move TrafficLedger accounting just to make decisions/report totals look alike.

### P1-B — independent semantic report oracle — CLOSED

`OrganizerReportContractValidator` proves shape/types, not business truth. The separate `OrganizerReportSemanticValidator` now recomputes the required business fields from raw inputs plus serialized decisions/report without rebuilding `ReportBuilder` output.

At minimum validate from raw queue/providers/profile/serialized decisions/report:

- `total_operations` equals queue length;
- distribution provider identities are valid and complete under the chosen base contract;
- distribution counts sum to the intended population;
- `share_pct` is recomputed from counts and denominator under the chosen accounting semantics within explicit rounding tolerance;
- `target_pct` is recomputed from the submission profile/source;
- projected utilization recomputes `used`, `limit`, `utilization_pct` from initial snapshot + approved settlement semantics;
- report period matches the authoritative temporal interpretation;
- recommendations may be additive, but no semantic validator may use `ReportBuilder` as its expected-value oracle.

Keep existing shape validator and strict self-consistency validator; this is an additional independent layer.

### P1-C — candidate-set normalization robustness — CLOSED

The adversarial real-factor campaign reproduced candidate-relative scale drift and the resolver now requires an explicit complete normalization pool:

- hold A and B provider/business values constant;
- add/remove C while keeping C non-winning and hard-eligible;
- test whether A-vs-B ordering changes materially;
- run across count/volume, priority, conversion, load and canonical mixed weights;
- distinguish legitimate change (C changes allocation denominator/business opportunity) from pure normalization artifact.

Change normalization only if a material routing or explanation defect is reproduced. Prefer bounded/domain normalization per factor if necessary; preserve exact arithmetic and inspectable raw/normalized/contribution traces.

### P1-D — daily-state temporal semantics — CLOSED

Public data is single-day; hidden queue semantics must not be guessed. The cross-midnight campaign established deterministic UTC date-scoped daily state for the ordered Case queue.

- inspect authoritative TZ/sample for period/day guarantees;
- reproduce a queue crossing midnight with daily limits;
- if multi-day input is permitted/unspecified and current cumulative behavior becomes wrong, implement deterministic day-bucket/reset semantics from the supplied snapshot and operation timestamps;
- if the contract is explicitly single operational day, document and fail closed on incompatible cross-day queues rather than silently applying stale daily usage.

Do not introduce persistence or scheduling infrastructure.

### P1-E — missing preferred amount configuration — CLOSED

`AmountPreferenceFactor` no longer returns maximum raw preference when a provider has no preferred range. The missing-band campaign established neutral/non-discriminating semantics.

Build a new-provider regression where only one provider lacks a band. Missing optional soft configuration must be explicitly neutral/non-discriminating, not silently best. Choose the minimal representation that keeps existing configured providers unchanged and explanations honest.

### P2 follow-ups

Only after P1 closure:

- verify explicit terminal identity is not semantically coupled to zero traffic more than the TZ requires;
- improve terminal/direct-fallback deviation causality only if a concrete report counterexample shows judge-facing ambiguity;
- do not reopen volume-target provenance, generic recovery or production architecture without new evidence.

## Protected boundaries

Keep one Case path:

`Input -> SubmissionProfile -> CaseState -> HardConstraintEvaluator -> ledgers -> Factors -> ConflictResolver -> Router/Simulator -> decisions/report projections -> independent validators`.

Hard constraints are absolute. Judge `expired -> next provider` remains bounded to Case and must not weaken production UNKNOWN/economic-ownership guarantees.

## Candidate gate

Before `VERSION_CANDIDATE`:

- accounting-point semantics are explicitly proven or conservatively documented;
- serialized report passes independent shape and semantic validation;
- normalization adversarial campaign is either fixed or evidence-closed with concrete tests;
- daily-state behavior is correct/fail-closed for the authoritative temporal contract;
- missing amount-range configuration cannot gain hidden preference;
- public validator and canonical finalization remain green;
- no material P0/P1 row remains PARTIAL/MISSING/CONFLICT in the current matrix.

Candidate was followed by a fresh blind pass. New material P0/P1 found there were closed by TZ19-106/107; the subsequent exact-head gate is VERSION_COMPLETE.

## Non-goals

No database, Redis, queues, microservices, real PSP, ML, general DSL, broad Coordinator refactor or generic pre-TZ hardening without a direct SPEC-019 blocker.

## Goal Mode

Continue autonomously while the next step is derivable. Do not stop after one green probe or one commit. Do not ask “continue?” when the plan determines the next action. Stop only at genuine VERSION_COMPLETE, a non-resolvable external ambiguity that cannot be conservatively handled, or a new authoritative organizer clarification requiring replanning.
