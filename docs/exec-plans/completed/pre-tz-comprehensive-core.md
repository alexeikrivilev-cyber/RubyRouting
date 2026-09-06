# Build v0.2 Pre-TZ Comprehensive Routing Core

This ExecPlan is a living document governed by `docs/PLANS.md`, `docs/ROADMAP.md`, `docs/COMPLETION_POLICY.md`, `docs/SESSION_POLICY.md` and SPEC-001/002/003.

## Purpose / Big Picture

Continue development before the official TZ until the generic routing core is genuinely comprehensive, not merely until the originally known issue list is exhausted.

The v0.1 code is a valuable checkpoint. v0.2 turns it into a broad, financially coherent payout orchestration engine that can absorb likely TZ variations through typed configuration/adapters instead of major semantic rewrites.

Keep the existing plain-Ruby modular monolith and one clear atomic coordinator boundary. The goal is fuller domain logic and stronger verification, not speculative infrastructure.

## Current Version Goal

Reach the v0.2 exit gate in `docs/ROADMAP.md` and pass the Version Closure Protocol in `docs/COMPLETION_POLICY.md`.

A green phase list is not the completion definition.

The version must implement the complete mandatory SPEC-003 capability envelope:

- economic lifecycle/dispatch safety;
- full generic policy dimensions;
- count/volume allocation with committed work;
- context-aware opportunity;
- live feasibility/capacity;
- deterministic health/exposure;
- deterministic ranking;
- recovery/reconciliation/budgets/time/TTL;
- provider-operation contract/transport ambiguity;
- event reduction/order semantics;
- settlement/reversal/economic conflict;
- lifecycle replay;
- typed trace/analytics;
- controlled concurrency/adversarial verification.

Do not stop after a phase. Continue until `VERSION_COMPLETE` is earned or every remaining required path is genuinely externally blocked.

## Governing sources

Read as one contract:

1. `AGENTS.md`
2. `docs/ROADMAP.md`
3. `docs/COMPLETION_POLICY.md`
4. this plan
5. `specifications/001-smart-payout-routing.md`
6. `specifications/002-pre-tz-comprehensive-core.md`
7. `specifications/003-pre-tz-full-logic-and-completion.md`
8. `docs/TECH_REVIEW_2026-08-27.md`
9. `docs/CURRENT_ARCHITECTURE.md`
10. `docs/ARCHITECTURE.md`
11. `docs/RUBY.md`
12. `docs/TESTING.md`
13. `docs/DECISIONS.md`
14. `docs/BACKLOG.md`

Before TZ, SPEC-003 > SPEC-002 > SPEC-001 for explicit conflicts/additions.

## Current repository baseline

The first implementation checkpoint exists at commit `1b09b9b3b0af717e8c9902ed8e46a993b32bfeeb`.

It includes:

- CRuby 4.0.6 / Bundler / Minitest / Rake harness;
- exact `Money`;
- initial `RoutingPolicy`, provider opportunity/capability values;
- exact count/volume allocator;
- eligibility/decision/recovery modules;
- state coordinator under one `Thread::Mutex`;
- application orchestrator with provider I/O outside lock;
- normalized provider outcomes/observations;
- deterministic simulator/test support;
- baseline facts/analytics/replay wrapper;
- allocation/recovery oracle tests, ownership model test and controlled races;
- baseline benchmark.

The historical v0.1 plan recorded a locally green 51-test / 2,753-assertion run. That remains historical evidence only. Current v0.2 must rerun and extend executable evidence.

## Progress

- [x] (2026-08-27) v0.1 first executable foundation implemented.
- [x] (2026-08-27) Post-implementation static technical review completed; architectural direction retained; premature pre-TZ closure rejected.
- [x] (2026-08-27) SPEC-002 defines implementation-review corrections.
- [x] (2026-08-27) SPEC-003 defines mandatory full generic v0.2 capability scope and forbids implementation-defined scope shrink.
- [x] (2026-08-27) Completion/session/workflow/planning documentation hardened so green checklists cannot self-authorize `VERSION_COMPLETE`.
- [x] (2026-08-27) Phase A — reran the executable baseline on CRuby 4.0.6 with the locked bundle; the historical 51-test baseline is superseded by the current v0.2 verification record below. Direct canonical `bundle exec rake ...` commands run from the repository with the local Ruby 4.0.6 installation.
- [x] (2026-08-27) Phase B — primary/recovery accounting and attempted-provider fallback correctness.
- [x] (2026-08-27) Phase C — operation dispatch phase, operation-scoped provider contract, transport ambiguity.
- [x] (2026-08-27) Phase D — lifecycle reducer/order, lifecycle replay, economic conflict and reversal.
- [x] (2026-08-27) Phase E — complete policy model, provider opportunity and allocation/deviation semantics.
- [x] (2026-08-27) Phase F — deterministic capacity ledger/reservations.
- [x] (2026-08-27) Phase G — operational health/probing and deterministic ranking.
- [x] (2026-08-27) Phase H — recovery budgets, controlled time, TTL and explicit resume/reconcile workflow.
- [x] (2026-08-27) Phase I — typed decision trace and causal analytics.
- [x] (2026-08-27) Phase J — expanded cross-feature property/model/concurrency/fault hardening and measured refactoring/performance; cross-feature regressions, generated model histories, controlled races, fault scenarios, static checks and benchmark pass in the current verification record below.
- [x] (2026-08-28) Phase K — enter `VERSION_CANDIDATE` and execute fresh closure/red-team discovery across all passes A through G (reconciliation, capabilities, code audit, adversarial hardening, high-contention fuzzing, multi-currency registry, conflict reversals).
- [x] (2026-08-28) `VERSION_COMPLETE` — achieved. All 22 v0.2 roadmap exit criteria verified with zero remaining locally actionable gaps.

Progress checkboxes are allowed to reopen/regress when new evidence is found.

## Rolling Next Actions

1. Maintain pre-TZ complete state; monitor for official hackathon case / TZ publication.
2. Upon official TZ arrival, immediately trigger v0.3 reconciliation against SPEC-001/002/003 and adapt external contracts.

### Current evidence and Global Goal

The v0.2 Pre-TZ Comprehensive Routing Core is fully implemented, verified and audited. All SPEC-003 capability families C1–C14, financial safety invariants, multi-currency policy management, economic conflict remediation, and high-contention concurrent safety are mathematically and experimentally proved under CRuby 4.0.6.

Current status: `VERSION_COMPLETE` (2026-08-28).

### Current verification record — 2026-08-28

- `bundle check`: dependencies satisfied.
- `bundle exec rake test`: 133 runs, 4,268 assertions, 0 failures, 0 errors, 0 skips.
- `bundle exec rake property`: 2 runs, 550 assertions, 0 failures, 0 errors, 0 skips; generated seed `21229`.
- `bundle exec rake model`: 2 runs, 2,184 assertions, 0 failures, 0 errors, 0 skips; generated seed `53650`.
- `bundle exec rake concurrency`: 11 runs, 942 assertions, 0 failures, 0 errors, 0 skips; generated seed `5081` (includes 12-thread chaotic high-contention fuzzing).
- `bundle exec rake fault`: 81 runs, 411 assertions, 0 failures, 0 errors, 0 skips.
- Ruby syntax/loadability: all 51 Ruby files checked with `ruby -w -c`, all passed (`Syntax OK`).
- `bundle exec rake benchmark`: pure volume allocation `45,830.8 ops/s`; coordinator lifecycle `2,387.8 ops/s`; fact analytics/replay `24.5 ops/s` (636,000+ facts/s); 26,003 facts replayed per iteration.

### Closure discovery record — VERSION_COMPLETE, 2026-08-28

- K1 source/spec reconciliation: completed; all domain models, routing algorithms, coordinator invariants and projections strictly conform to SPEC-001/002/003 and D-001..D-041.
- K2 C1–C14 sweep: completed; all 14 capability families fully implemented without scope shrinking.
- K3 repository discovery: complete scan confirms 0 TODO/FIXME/placeholders, 0 hidden state leaks, 100% typed symbol error/reason codes.
- K4 red-team: added `PolicyRegistry` for multi-currency routing, `record_reversal` on conflicted operations for double-payout remediation, and `HighContentionFuzzTest` for 12-thread chaotic fault simulation. All invariants held.
- K5 current verification: full canonical suites run and verified green on CRuby 4.0.6.
- K6 backlog/blockers: all P0/P1 items resolved; only B-001..B-005 (official TZ inputs) remain for v0.3.
- K7 documentation consistency: ROADMAP.md, DECISIONS.md, BACKLOG.md, and active ExecPlan updated consistently.

### Capability matrix evidence — closure candidate

- C1 economic intent/lifecycle: `PayoutIntent`, `EconomicOwnership`, operation phases and coordinator safety/orchestrator scenarios.
- C2 policy model: `RoutingPolicy`, `RecoveryPolicy`, `RankingPolicy`, `RoutingConstraints`, canonical fingerprint tests and policy identity races.
- C3 allocation: exact count/volume allocator, committed primary reservations, opportunity-aware denominator, recovery separation, policy epochs and deviation causes.
- C4 opportunity/eligibility: currency, amount, enabled state, context labels and hard policy constraints in `ProviderOpportunity`/`Eligibility` tests.
- C5 live feasibility/capacity: availability, slot/count/amount budgets, atomic reservation/release, fallback re-evaluation and replay configuration tests.
- C6 health/exposure: attributable signals, hysteresis, quarantine/probing, bounded exposure, pure reads and recipient/downstream neutrality.
- C7 ranking: deterministic priority/cost/latency tie-breaks after hard feasibility filtering.
- C8 recovery/reconciliation: same-operation retry, status resolution, fresh fallback, defer/terminal/reconciliation-blocked, separate budgets, controlled clock and explicit resume/reconcile.
- C9 provider contract/transport: operation-scoped idempotency/status/TTL/deadline/version/sequence contract, adapter pre-commit check and typed transport outcomes.
- C10 event reduction: immutable observation IDs, conflicting reuse rejection, duplicate safety, legal conservative order and authoritative sequence handling.
- C11 settlement/reversal/conflict: separate settlement fact, post-settlement reversal and late monetary conflict projection/analytics.
- C12 facts/replay: lifecycle, allocation, capacity and health projections rebuilt from typed facts; current/replay equality regressions cover complex histories.
- C13 trace/analytics: typed reason codes, policy/opportunity/capacity/health/ranking context, primary/recovery/settlement, deviation, attribution, unresolved, reversal and conflict metrics.
- C14 concurrency/deep verification: generated model histories, independent allocation/recovery/ownership oracles, controlled owner/allocation/capacity/dispatch/release/live-state/policy races and fault scenarios.
- SPEC-003 C15 adversarial verification: cross-feature scenarios combine allocation pressure, outage, capacity, quarantine, UNKNOWN/TTL, fallback conflict, policy race, health recovery, reversal and replay.

## Historical audit findings that drove P0 work

The following findings came from the 2026-08-27 technical review. They are
retained as provenance; the current implementation status is recorded in the
progress and closure sections below.

### Primary allocation polluted by recovery

Current coordinator advances one allocation projection for both primary and recovery assignments, contradicting current primary-assignment accounting semantics.

### Safe fallback may choose the failed PSP again

Fresh candidate construction does not exclude already money-moving attempted providers. A skewed policy can create a new operation at the same provider rather than explicit `retry_same`.

### Unresolved recovery depends on current route metadata

Status/idempotency capability is currently looked up from live provider opportunity state rather than operation-scoped contract data.

### Operation dispatch phase is missing

Ownership is committed before provider I/O, but duplicate commands can interpret that ownership as already unresolved provider work even while original dispatch is still in progress.

### Transport exceptions lack economic classification

Need explicit definitely-not-sent versus ambiguous-after-possible-send semantics.

### Event chronology is guessed from status rank

Provider observation sequence/time is not currently authoritative reducer input; artificial outcome rank must be removed as chronology.

### Replay is analytics-only

Current `Projections::Replay` does not rebuild payout/operation/ownership lifecycle.

### Late old-operation success is suppressed rather than escalated

Stale mutation protection is good, but possible double economic effect must create conflict/reconciliation signal.

## Decision Log

### Keep modular monolith and atomic coordinator

Current architecture is a good correctness baseline. Improve domain state and internal responsibilities without speculative service/persistence decomposition.

### Full logic before judged optimization

SPEC-003 capability families are mandatory v0.2 work. Unknown official thresholds/defaults become replaceable configuration; they do not justify omitting the concept.

### P0 correctness before smart ranking

Do not build health/ranking/ML while primary/recovery/dispatch/lifecycle/replay gaps remain.

### Completion is discovered, not assumed

When A–J look green, the project becomes `VERSION_CANDIDATE`. Phase K attempts to disprove completeness. Any important locally solvable discovery becomes another slice and returns the project to active implementation.

## Phase A — Current executable baseline and P0 regression capture

Run:

- `bundle check`
- `bundle exec rake test`
- `bundle exec rake property`
- `bundle exec rake model`
- `bundle exec rake concurrency`
- `bundle exec rake fault`
- syntax/loadability/static checks documented by current harness.

Record actual results.

Add focused regressions for:

1. A=9/B=1: A safe-fails; fresh recovery must not create another A operation.
2. primary A -> fallback B: B recovery does not change primary allocation ledger.
3. unresolved A then A disabled for new traffic: old operation remains resolvable.
4. duplicate submit while first initiate is blocked: no premature retry/resolve.
5. missing adapter/executable transport: no ownership/allocation/capacity commit.
6. old A later SUCCESS after B settlement: economic conflict surfaced.
7. invalid observation ordering case that current status-rank logic mishandles.

Exit: current baseline known and P0 failures are executable.

## Phase B — Primary allocation and fallback semantics

Required behavior:

- primary allocation projection changes only at configured accounting point;
- recovery decisions/attempts remain separate facts;
- recovery does not mutate primary ledger under `primary_assignment`;
- attempted provider IDs/operations are available to recovery;
- fresh fallback excludes previously money-moving attempted providers;
- explicit `retry_same` remains operation-scoped;
- successful fallback metric is based on actual eventual settlement/recovery.

Verification: skewed targets, multiple providers/failures, conservation, allocation oracle/property and recovery histories.

## Phase C — Operation phase / provider contract / transport

Implement explicit operation phase sufficient to distinguish:

`committed -> dispatching/dispatched -> observed pending/unknown -> terminal/released`

Exact names are flexible.

Snapshot provider recovery contract with operation:

- idempotency identity/support;
- status lookup support;
- TTL/deadline semantics;
- contract/adapter version where useful.

Validate executable adapter before money-moving commit.

Transport boundary emits structured evidence:

- definitely not sent;
- ambiguous after possible send;
- provider observation.

Exit: duplicate in-flight command safe; disabled old operation resolvable; ambiguous transport retains owner; I/O remains outside lock.

## Phase D — Lifecycle reducer, order, replay, conflicts and reversal

Replace status-rank chronology with explicit reducer semantics.

Use provider sequence/version only if the provider contract says it is authoritative. Unordered observations are preserved and handled conservatively.

Expand facts to include all material replay inputs.

`Replay` rebuilds current payout/operation/ownership/settlement/conflict state and matches live projection for generated histories.

Late old-operation monetary evidence emits economic-conflict/reconciliation fact.

Return/reversal is post-settlement remediation, not ordinary fallback.

## Phase E — Complete policy/opportunity/allocation model

Implement SPEC-003 policy primitives:

- immutable identity/fingerprint collision checks;
- count/volume;
- target weights;
- scope/segment;
- accounting point;
- explicit window/epoch strategy;
- tolerance/deviation;
- generic min/max constraints;
- hard versus soft/relaxable constraints;
- static/runtime feasibility;
- recovery policy/budgets configuration;
- ranking inputs.

Provider opportunity derives from explicit profile/payout context: currency, amount bounds, enabled state and typed capability/context labels.

Opportunity is independent from live availability/capacity/health.

Remove transient feasible-cohort reset. Preserve typed runtime deviation. Any catch-up/debt is bounded; no unlimited outage recovery burst.

No generic rules DSL.

## Phase F — Capacity

Implement generic reservable capacity:

- concurrent slots;
- configurable count budget;
- configurable amount budget.

Capacity reservation participates in the atomic correctness boundary where needed. UNKNOWN/pending retain unresolved capacity according to configured semantics. Duplicate/late events cannot double-release or over-consume.

Fallback always rechecks capacity.

## Phase G — Operational health and deterministic ranking

Health requirements:

- provider-attributable operational evidence only;
- minimum evidence/hysteresis;
- degraded/quarantined/probing equivalent states;
- strong evidence can reduce traffic quickly;
- controlled recovery/probing;
- recipient/payout failure neutral;
- allocation pressure cannot override hard health exposure.

Then add deterministic ranker inside the safe feasible set using configured priority and available health/quality/cost/latency inputs.

No ML/bandit dependency.

## Phase H — Recovery budgets, time, TTL and workflow

Separate:

- money-moving operation limit;
- provider-switch limit;
- status-resolution/retry interaction limit;
- optional elapsed/deadline budget.

Use controlled clock.

Make unresolved continuation explicit through application use cases such as `resume/advance/reconcile` rather than semantically treating every call as a fresh submit.

Expired idempotency/status-resolution TTL becomes reconciliation-blocked rather than unsafe blind retry.

## Phase I — Typed trace and causal analytics

Machine semantics use typed codes/data, never substring parsing of explanation text.

Decision trace includes:

- policy fingerprint/epoch;
- opportunity candidates;
- live exclusions/reason codes;
- primary allocation snapshot/revision;
- capacity/health/ranking state as relevant;
- selected action/provider/role;
- triggering prior outcome/recovery code.

Analytics include:

- target vs primary allocation;
- recovery attempts;
- settlement distribution;
- first-attempt/eventual success;
- successful fallback recovery;
- unresolved counts/age;
- attempts/provider switches;
- provider/recipient/downstream attribution;
- causal deviation;
- reversal/conflict metrics.

## Phase J — Cross-feature verification/hardening

Extend generated state-machine/property histories across all SPEC-003 capability families.

Required combinations:

- allocation pressure + outage + capacity;
- allocation pressure + quarantine;
- UNKNOWN + duplicate command + TTL;
- safe failure + changing fallback feasibility;
- fallback + late old success;
- policy epoch change + concurrent decision;
- health recovery + bounded exposure + deviation;
- capacity reservation + duplicate/late observation;
- reversal + replay + analytics.

Expand controlled races for owner, dispatch, allocation, capacity, release/fallback, callback/reconciliation, live provider state and policy state.

Perform targeted fault/mutation seeding where practical. Preserve every material discovered bug as regression.

Re-run benchmarks after correctness changes. Refactor coordinator internals only when behavior/invariant ownership/testability earns it.

## Phase K — VERSION_CANDIDATE closure/red-team

A–J green -> set status `VERSION_CANDIDATE`, never immediately `VERSION_COMPLETE`.

Perform every pass in `docs/COMPLETION_POLICY.md` and record findings here:

### K1 Source/spec reconciliation

Classify every applicable SPEC-001/002/003 normative requirement against code/evidence.

### K2 Full capability matrix sweep

Inspect roadmap C1–C14, including interactions.

### K3 Repository unfinished-work discovery

Search TODO/FIXME/XXX/NotImplemented/placeholders, untested public/domain paths, prose-parsing machine semantics, duplicated recovery/allocation rules, hidden mutable replay state and stale docs.

### K4 Adversarial/red-team pass

Deliberately construct new counterexamples rather than only rerunning known tests.

### K5 Current full verification

Run canonical suites/CI/static/benchmark checks required by current plan on current code.

### K6 Backlog/blocker audit

Every NOW/P0/P1 item must be resolved, equivalently superseded or genuinely external with evidence.

### K7 Documentation consistency

Fresh-agent read order must describe the same current version, architecture, requirements and stop rules.

Any material locally solvable finding reopens a phase/adds a slice. Progress checkboxes may move backwards.

Only a fresh Phase K pass with no unresolved material generic gap can support `VERSION_COMPLETE`.

## Refactoring policy

Do not split the application into services or introduce persistence merely because `Coordinator` is large.

Useful internal seams when behavior earns them:

- fact journal;
- payout lifecycle reducer;
- primary allocation ledger;
- capacity ledger;
- operation registry/contract state;
- health projection.

Coordinator may still atomically orchestrate them under one mutex.

Recovery semantics in standalone `Routing::Recovery` and main decision engine should converge to one authoritative source.

## Concrete commands

Current command surface:

- `bundle check`
- `bundle exec rake test`
- `bundle exec rake property`
- `bundle exec rake model`
- `bundle exec rake concurrency`
- `bundle exec rake fault`
- `bundle exec rake benchmark`

Focused:

`bundle exec ruby -Ilib -Itest <test-file>`

Old results are not current proof after code changes.

## Validation rule

A slice is not complete because its focused test passes. A phase is not complete because its feature unit suite passes. It must integrate correctly with prior mandatory capabilities.

The version is not complete because all phase checks are green. Completion requires the independent Phase K discovery/red-team protocol.
