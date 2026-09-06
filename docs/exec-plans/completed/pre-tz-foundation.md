# Build v0.1 pre-TZ deterministic foundation

This ExecPlan is a living document maintained according to `docs/PLANS.md` and the project sequencing rules in `docs/ROADMAP.md`.

## Purpose / Big Picture

Deliver **v0.1 — Pre-TZ Deterministic Foundation**: a working, heavily verified Ruby payout-routing kernel that survives official-TZ reconciliation without freezing unknown external contracts.

The current implementation baseline is now concrete:

- CRuby 4.0.6 development runtime;
- plain-Ruby modular monolith;
- Minitest + Rake harness;
- deterministic financial kernel;
- application orchestrator;
- one coarse in-memory `Thread::Mutex` coordinator initially;
- provider I/O outside the coordinator critical section;
- provider simulator/test adapter;
- facts + current projections, not mandatory full event sourcing.

The version is complete only when the v0.1 exit criteria in `docs/ROADMAP.md` are satisfied. Completion of a file, class, milestone, phase, or commit is not a stop condition.

Continuous execution:

`select slice -> implement -> verify -> review -> update this plan -> select next slice`

Stop only when v0.1 is complete or a genuine external blocker prevents every remaining v0.1 path. See `docs/SESSION_POLICY.md`.

## Global Goal for this session

Complete the v0.1 pre-TZ deterministic foundation as one coherent Ruby-only
system: exact allocation with committed work, safe economic ownership/recovery,
deterministic provider faults, independent reference/model/property/concurrency
evidence, trace/replay projections, and baseline performance measurements, while
keeping TZ-dependent external contracts reversible.

## Governing sources

Read/use these as a coherent set:

- `AGENTS.md`
- `docs/ROADMAP.md`
- `docs/SESSION_POLICY.md`
- `specifications/001-smart-payout-routing.md`
- `docs/ARCHITECTURE.md`
- `docs/RUBY.md`
- `docs/TESTING.md`
- `docs/WORKFLOW.md`
- `docs/DECISIONS.md`

Behavior comes from the specification. Architecture/Ruby docs constrain implementation, not product semantics.

## Current Version Goal

A clean checkout should provide an executable Ruby system that can deterministically model and verify:

- count/volume proportional allocation with exact money and in-flight commitments;
- economic intent and single unresolved economic ownership;
- normalized provider outcomes and safe retry/fallback/resolve/defer behavior;
- provider faults including `PENDING`, `UNKNOWN`, delayed/duplicate/out-of-order observations;
- opportunity/assignment/attempt/settlement traces and replayable projections;
- property/state-machine exploration and controlled concurrency races;
- baseline performance measurements without guessed judge thresholds.

No Rails/database/queue/public API/provider SDK/ML commitment is required for v0.1.

## Progress

This section must reflect repository evidence, not aspiration.

- [x] (2026-08-27) Baseline specification, decisions, research, Goal Mode workflow, and deep testing strategy documented.
- [x] (2026-08-27) Long-horizon roadmap and session continuation rules documented.
- [x] (2026-08-27) Ruby 4.0.6 engineering baseline and concrete v0.1 modular-monolith/atomic-coordinator architecture selected and documented.
- [x] (2026-08-27) Phase 0 — re-oriented against the actual repository tree: the repository was documentation-only, with no Ruby runtime available on PATH and no existing checks to run.
- [x] (2026-08-27) Phase 1 — created the Bundler/Minitest/Rake harness, `.ruby-version`, canonical `bundle exec rake test`, focused command documentation, and exact immutable `Money` tests.
- [x] (2026-08-27) Phase 2 — built independent allocation and ownership reference models under `test/support/reference` and compared them to production behavior.
- [x] (2026-08-27) Phase 3 — implemented deterministic count/volume post-decision allocation, exact discrepancy, feasible opportunities, committed reservations, opportunity cohorts, and seeded oracle comparisons.
- [x] (2026-08-27) Phase 4 — implemented normalized outcomes, economic ownership, safe release, retry/resolve/fallback/defer/terminate decisions, and atomic coordinator/orchestrator lifecycle.
- [x] (2026-08-27) Phase 5 — implemented deterministic scripted provider behavior, controlled time, timeout/unknown, pending resolution, duplicate and delayed/out-of-order observation handling, and replayable facts.
- [x] (2026-08-27) Phase 6 — added seeded allocation properties and generated ownership state-machine histories with trace-rich assertions.
- [x] (2026-08-27) Phase 7 — added barriers and controlled ownership/allocation races plus a provider-I/O-outside-lock test.
- [x] (2026-08-27) Phase 8 — implemented immutable fact projections/replay for opportunity, assignment, attempt, settlement, outcome attribution, and primary-vs-settlement analytics.
- [x] (2026-08-27) Phase 9 — hardened observation identity/metadata and simulator regressions, ran broad verification, and recorded the performance baseline.
- [x] (2026-08-27) Phase 10 — completed the v0.1 closure review: all current exit criteria are evidenced; only later/TZ-dependent work remains.

## Rolling Next Actions

Keep this list small and factual. Replace completed items immediately with the next highest-value unblocked work.

1. Keep official-TZ reconciliation items B-001…B-005 blocked until authoritative input arrives; do not reopen the verified pre-TZ kernel speculatively.
2. On TZ arrival, classify changed accounting/provider/runtime semantics and update the spec, oracle, tests, and adapters together.

Do not scaffold all future architecture directories in action 2; create only files required by the current vertical slice.

## Surprises & Discoveries

- The repository originally instructed agents to remain pre-implementation until the official TZ. Corrected: stable/reversible implementation begins now.
- Acceptance examples alone do not cover the state space; v0.1 requires oracle, property/state-machine, controlled concurrency, and deterministic fault injection.
- Long-running Goal Mode needs a version-level continuation condition; phase completion is only a checkpoint.
- Architecture was initially intentionally abstract. It is now concrete enough for coding: modular monolith + deterministic kernel + application orchestrator + coarse in-memory Mutex coordinator. Unknown external shell choices remain deferred.
- Current stable Ruby as of this planning update is 4.0.6; this is the v0.1 development baseline, not an assumption about the future judge runtime.
- The initial repository audit on 2026-08-27 found no implementation, test harness, benchmark, or Ruby/Bundler/Rake executable in PATH; Phase 0 therefore selected the documented Phase 1 first slice as the highest-value next action.
- Ruby 4.0.6 is available as a portable RubyInstaller archive, but its Windows integration fails under the repository's Cyrillic absolute path; temporary ASCII drive mappings allow tests to run without changing repository paths. This is an environment limitation, not a project behavior defect.
- Minitest 6 currently pulls a native Prism dependency; the harness pins the final Minitest 5 line (`~> 5.16`) to keep setup compiler-free while retaining the selected Minitest/Rake architecture.
- Opportunity-aware allocation uses a new feasible-provider cohort as the provisional accounting window. Historical facts remain append-preserved, but unavailable providers do not create ordinary allocation debt across a changed opportunity cohort; policy epoch is also part of the allocation scope key.
- Observations from an operation after its economic ownership was released are preserved as facts but cannot mutate lifecycle state or analytics. This protects primary-vs-settlement projections from late old-operation callbacks.
- Focused property/model execution with `RUBY_ROUTING_SEED=9921` passed; default seeded property/model suites and the full suite also pass. Failure messages include the generator seed and iteration/trace context.
- Benchmark task is executable through `bundle exec rake benchmark`; the final CRuby 4.0.6 interpreter baseline (YJIT disabled) is recorded below. These are observations, not gates.
- Acceptance traceability is an executable Ruby manifest covering AC-001…AC-017; a conflicting reuse of an observation identifier is now a deterministic integrity regression.

Add new evidence-driven discoveries while implementing. Preserve meaningful failing seeds/traces/benchmarks.

## Decision Log

### 2026-08-27 — Ruby-only executable logic

All production, oracle, simulator, property/model/concurrency and executable test domain logic is Ruby. Minimal declarative CI/shell orchestration is allowed.

### 2026-08-27 — CRuby 4.0.6 baseline

Use CRuby 4.0.6 as the current development runtime. Follow `docs/RUBY.md`: Integer minor-unit money, exact Rational/integer ratios, deterministic inputs, explicit concurrency/test boundaries. Reconcile immediately when official judge runtime is published.

### 2026-08-27 — v0.1 implementation architecture

Use the architecture in `docs/ARCHITECTURE.md`: plain Ruby modular monolith, deterministic kernel, application orchestrator, narrow ports/adapters and one coarse in-memory Mutex coordinator initially.

Atomic correctness rule: decision fact + allocation commitment + economic ownership are committed under the coordinator before provider I/O; provider I/O is outside the lock; observations are applied in a later synchronized transition.

### 2026-08-27 — Minitest + Rake baseline

Minitest + Rake is the v0.1 harness choice. Do not reopen RSpec/framework selection during ordinary Phase 1 implementation without evidence that the baseline is inadequate.

### 2026-08-27 — implement stable pre-TZ core now

Do not wait for the official TZ. Implement stable domain behavior and deep verification while keeping API/persistence/provider contracts replaceable.

### 2026-08-27 — reference model remains independent

The oracle may share trivial immutable value representations where helpful but may not call production allocator/recovery decision code to compute expected results.

### 2026-08-27 — continuous long-session execution

A Goal Mode run continues across slices/phases until v0.1 exit criteria pass or all remaining v0.1 paths are externally blocked.

### 2026-08-27 — no adaptive ML/bandit in v0.1

Adaptive routing is not required before a deterministic baseline and judged objective/data exist.

### 2026-08-27 — provisional opportunity-cohort accounting

The in-memory allocation projection resets when the current feasible-provider cohort or policy epoch changes. Historical facts remain append-preserved, but unavailable providers do not create ordinary allocation debt across a changed opportunity cohort. This isolates the pre-TZ accounting-window assumption and can be reconciled with the official TZ.

### 2026-08-27 — observation identity hardening

Exact duplicate observations remain idempotent, but reusing an observation ID
with different linkage or normalized outcome is rejected and the original
metadata is retained in the provider-observed fact. This is covered by a
deterministic coordinator regression and reflected in SPEC-001/`docs/DECISIONS.md`.

## Outcomes & Retrospective

Complete for the current pre-TZ Version Goal. The v0.1 foundation now has executable
production and reference code, deterministic provider simulation, deep verification,
facts/projections/replay, and a reproducible baseline command surface. The
implementation stayed within the documented plain-Ruby modular-monolith baseline:
the coordinator owns mutable correctness state under one coarse `Thread::Mutex`,
commits allocation/ownership before provider I/O, and applies observations later
under synchronization.

Closure evidence:

- Runtime/setup: CRuby 4.0.6, Bundler, Minitest 5.27.0, Rake 13.4.2; `bundle check` passes.
- Full canonical suite: `bundle exec rake test` — 51 tests, 2,753 assertions, 0 failures/errors/skips.
- Focused matrix with `RUBY_ROUTING_SEED=9921`: property — 2 tests/550 assertions; model — 1/1,940; concurrency — 3/8; fault scenarios — 22/108; all green.
- Static verification: `ruby -c` passed for 43 Ruby files; `git diff --check` passed.
- Acceptance traceability: all AC-001…AC-017 map to executable test methods and are checked by `AcceptanceTraceabilityTest`.
- Material regressions covered: monotonic pending/unknown lifecycle, late old-operation observations, temporary safe failure state, observation-id payload conflict, duplicate settlement, and replayed successful intent.
- Benchmark (CRuby 4.0.6, YJIT false, workstation baseline): pure volume allocation 71,433.0 ops/s; coordinator lifecycle 7,065.2 ops/s; fact analytics replay 68.9 ops/s over 18,000 facts. These are observations, not acceptance limits.

Provisional/TZ-blocked semantics remain explicit: primary-assignment accounting,
feasible-provider-cohort windows, provider status/idempotency contract details,
external API/runtime/persistence requirements, and official allocation denominator
rules. They are tracked by B-001…B-005 in `docs/BACKLOG.md` and do not block the
completed pre-TZ foundation.

At v0.1 closure record:

- actual implemented modules and any architecture changes earned by evidence;
- canonical commands/runtime/dependencies;
- SPEC/TESTING evidence achieved;
- important regression seeds/traces;
- controlled concurrency evidence;
- baseline benchmark measurements;
- remaining provisional/TZ-blocked semantics;
- architectural lessons requiring docs/decision updates.

## Context and Orientation

The behavioral baseline is `specifications/001-smart-payout-routing.md`.

One payout is one **economic intent** despite multiple technical/provider interactions. At most one unresolved money-moving provider operation may own the economic intent. `UNKNOWN` after possible provider acceptance does not release ownership, so cross-provider fallback is unsafe until that operation is safely resolved/released.

Allocation currently treats count as measure `1` and volume as exact monetary amount, evaluates post-decision discrepancy, and includes committed/in-flight assignments. Primary assignment is a provisional accounting point until the official TZ defines otherwise.

Opportunity, assignment, attempt, observation, and settlement are distinct. Provider-specific outcomes normalize at the adapter boundary. Payout business failure and provider reliability attribution are separate signals.

The architecture now defines the concurrency baseline precisely: the v0.1 in-memory coordinator is the only owner of mutable correctness state and is guarded by a coarse Mutex. Provider calls never occur under that lock. Pure routing/recovery code works from immutable snapshots/values.

The repository must remain testable without live money-moving services. Time, randomness, provider behavior and concurrency schedules are controlled in tests.

## Execution Model

The roadmap phases are dependency guidance, not a rigid class/file script.

For every phase:

1. identify the smallest slice making new behavior observable;
2. add/strengthen verification capable of falsifying it;
3. implement within current architecture/Ruby rules;
4. run focused checks early;
5. run phase-appropriate broader checks;
6. review for invariant leakage, speculative abstraction, provider/TZ assumptions and architecture drift;
7. update this plan with real progress/discoveries;
8. immediately select the next slice.

If an approach fails twice, change tactic. After three materially different failures, reduce to a minimal reproducer and simplify/replan. Do not stop unless remaining version work is externally blocked.

## Plan of Work

### Phase 0 — Orientation and baseline integrity

Inspect actual source/test/config tree, run existing canonical checks if any, compare reality to this plan, and update Rolling Next Actions.

Exit: actual state is understood and one concrete coding slice is selected.

### Phase 1 — Ruby harness and fast feedback

Use the already selected baseline rather than reopening architecture:

- `.ruby-version` -> `4.0.6`;
- minimal Bundler `Gemfile`;
- Minitest + Rake;
- one canonical `bundle exec rake test` full-suite command;
- focused test command;
- root namespace `RubyRouting` via `lib/ruby_routing.rb`;
- `test/test_helper.rb`;
- exact Money representation (`Integer` minor units + explicit currency) and first tests;
- deterministic seed/trace support as soon as generated tests exist.

Keep the dependency surface minimal. Do not add app framework/autoload/ORM/lint/type tooling merely because Phase 1 exists.

Exit evidence:

- clean setup runs the canonical suite;
- an intentional failure returns non-zero visibly;
- Money rejects/handles invalid/cross-currency behavior according to its documented invariant;
- source/test structure follows `docs/ARCHITECTURE.md`/`docs/RUBY.md`;
- future time/random/provider behavior can be injected without sleeps/live APIs.

### Phase 2 — Trusted reference/oracle model

Build a deliberately simple pure-Ruby executable specification under `test/support/reference`.

It must independently represent/evaluate the small state space needed for:

- payout/provider/policy states;
- feasible provider choices;
- one-step count/volume discrepancy by brute force;
- single-owner lifecycle legality;
- normalized outcomes/legal recovery actions;
- simple expected projections.

Exit: core SPEC examples can run through oracle and deliberately illegal/incorrect choices are rejected without calling production algorithms.

### Phase 3 — Deterministic allocation kernel

Implement explicit opportunities/feasible set, exact count/volume measure, post-decision discrepancy, committed/in-flight visibility, stable tie-break, no-route/infeasibility representation, and isolation of provisional accounting/window semantics.

Pure allocator returns choice/explanation; coordinator owns mutation/commit.

Verification: examples + generated brute-force oracle comparisons + large indivisible amounts/ineligible providers + first controlled committed-allocation race.

### Phase 4 — Economic ownership and recovery kernel

Implement stable intent identity, ownership acquire/release, single-owner invariant, normalized success/pending/unknown/safe-failure/terminal semantics, explicit retry/resolve/fallback/defer/terminate actions and separate attribution.

Application/coordinator atomic protocol must follow architecture exactly. Negative tests for illegal fallback after `UNKNOWN` are mandatory.

### Phase 5 — Provider/fault simulator and lifecycle facts

Build deterministic Ruby simulator in test support implementing provider semantic port. Script immediate success/failure, terminal failure, PENDING, timeout-after-acceptance -> UNKNOWN, delayed resolution, duplicate/out-of-order observations, safe provider-local idempotent replay/lookup, and optional reversal where useful.

Use controlled time; no real sleeps as primary mechanism.

### Phase 6 — Property/model-state verification

Generate valid/high-risk provider/policy/amount/outcome histories. Preserve seed/trace. Compare production to oracle/invariants. Bias toward UNKNOWN, infeasibility, boundary amounts, duplicate/reordered facts and policy/ownership edge states.

Material discovered bugs become deterministic regressions.

### Phase 7 — Controlled concurrency

Force ownership acquire/acquire, duplicate submit, stale allocation reservation, release/fallback and relevant observation/reconciliation races with barriers/hooks.

The initial coarse coordinator Mutex should provide a simple linearizable baseline. Stress tests supplement controlled schedules.

### Phase 8 — Trace and baseline analytics

Preserve opportunity, decision/assignment, attempt, observation/attribution and settlement distinctions. Implement only projections needed for verification/explainability. Replay must derive equivalent projections.

### Phase 9 — Hardening and baseline measurements

Run full deterministic/property/model/concurrency/fault suites; fault-seed critical synchronization/invariants where practical; remove speculative abstractions; benchmark allocation/decision/replay/coordinator contention; verify clean setup.

Observed performance is baseline evidence, not an invented official limit.

### Phase 10 — Version closure audit

Audit every v0.1 exit criterion, SPEC, architecture, Ruby policy and testing quality gate. If a locally solvable gap remains, create/select another slice and continue.

Only close the plan when all current-version criteria are met or remaining work is genuinely external/TZ-blocked.

## Verification and Acceptance

Use `docs/TESTING.md`. Relevant evidence layers include:

- deterministic acceptance/regression tests;
- independent oracle comparisons;
- property/invariant tests;
- model/state-machine tests;
- controlled concurrency/interleaving tests;
- provider simulator/fault scenarios;
- trace/replay/projection checks;
- baseline stress/performance measurements.

The authoritative v0.1 exit gate is the list in `docs/ROADMAP.md`; do not maintain a second divergent version here.

## Concrete Commands

Phase 1 must establish and then keep these current:

- setup: normally `bundle install`;
- full suite: `bundle exec rake test`;
- focused Minitest execution;
- later property/model suite with seed replay;
- later concurrency/fault suite;
- lint/static command only if such tooling is actually adopted;
- benchmark/baseline command.

Do not create competing undocumented full-suite commands.

## Idempotence and Recovery of Development Steps

Tests/simulator must be safe to rerun and require no live payout service. Random/property failures are reproducible. Generated fixtures/artifacts are regenerable or intentionally versioned.

If later work adds persistent state/migrations, update the active/successor plan with rollback/retry semantics before relying on them.

## Interfaces and Dependencies

Selected baseline:

- CRuby 4.0.6;
- Bundler;
- Minitest;
- Rake;
- Ruby standard library.

A small additional property-testing/dev dependency may be added only after the baseline harness exists and the benefit is concrete.

Not justified by v0.1 alone:

- Rails/Sinatra/Hanami;
- production DB/ORM;
- queue/event bus/job framework;
- distributed locking service;
- live provider SDK;
- Ractor-based core architecture;
- ML/bandit library;
- external observability stack.

## Scope and Replanning

The agent may improve class/module boundaries, merge/split slices, reorder independent work, prototype/discard local approaches, and revise provisional assumptions when evidence appears.

The agent may not casually redesign the accepted v0.1 architecture, weaken safety invariants, encode unknown TZ semantics irreversibly, implement LATER backlog items opportunistically, or stop after a milestone while version work remains actionable.

Material architecture changes require evidence plus `docs/ARCHITECTURE.md`/`docs/DECISIONS.md` updates.

## Anti-loop and Blocker Policy

Follow `docs/SESSION_POLICY.md` and `docs/WORKFLOW.md`.

After two similar failures, change tactic. After three distinct failed approaches, reduce to a reproducer and re-evaluate assumptions/design.

Before declaring an external blocker, prove:

- the exact required version criterion depends on unavailable external input/access;
- reasonable investigation/workarounds were exhausted;
- no independent v0.1 slice remains.

A difficult bug is work, not a blocker.
