# Long-Horizon Development Roadmap

This document defines the project-level development path for RubyRouting. It is deliberately more stable than a task checklist and less prescriptive than an implementation design.

The roadmap tells a long-running coding agent **what outcome to reach next and how to know that it is reached**. The active ExecPlan tells the agent how the current version is progressing. The specification remains authoritative for behavior.

## 1. Goal hierarchy

Work is organized at four levels:

1. **Project Goal** — build a competitive, correct, explainable smart payout-routing system in Ruby for the Hack.Genesis case.
2. **Version Goal** — the complete observable capability expected from the current project version.
3. **Phase Goal** — a coherent capability needed to reach the version goal.
4. **Slice Goal** — the next smallest vertical unit that can be implemented and independently verified.

The agent should reason from top to bottom and execute from bottom to top.

A Slice Goal is not the end of a run. After a slice is verified, the agent updates the living plan, selects the next highest-value unfinished slice in the active version, and continues.

## 2. Long-session continuation contract

A Goal Mode run is expected to continue through multiple phases without waiting for routine approval.

The agent MUST NOT voluntarily stop merely because:

- one file, class, test, milestone, or phase is complete;
- the next local implementation choice is not uniquely determined;
- a test failed and needs debugging;
- a reversible assumption is required;
- a dependency/tool choice needs ordinary engineering judgment;
- the current solution is not aesthetically perfect;
- a tangential improvement was discovered;
- the agent has already made substantial progress.

After each verified slice:

1. update the active ExecPlan so `Progress`, discoveries, and material decisions reflect reality;
2. run the appropriate narrow/full verification gate;
3. inspect the remaining version goal;
4. choose the next unblocked slice with the best dependency/value leverage;
5. continue implementation.

### Permitted stop conditions

A run may stop only when one of these conditions is true:

**A. Current Version Goal is achieved.**

All version exit criteria are satisfied, relevant checks pass, remaining work belongs to a later version or is explicitly blocked on external information, and the active plan records the outcome.

**B. Genuine external blocker.**

Progress on every remaining path required for the current version depends on something outside the agent's control, such as unavailable official TZ information, missing repository/tool permissions, inaccessible required external service/contracts, or an action requiring explicit authorization that cannot safely be substituted.

A local implementation problem, failing test, uncertain design, missing helper, or difficult bug is **not** an external blocker.

If one phase is blocked but independent current-version work remains, switch to that work rather than stopping.

## 3. Planning style: constrained outcomes, flexible means

The roadmap specifies:

- required behavior/outcomes;
- dependency order where correctness requires it;
- verification evidence;
- forbidden premature commitments;
- version completion criteria.

It intentionally does **not** prescribe:

- exact class/file names before implementation reveals good boundaries;
- a fixed object hierarchy;
- a fixed number of commits;
- a particular testing gem when standard Ruby is sufficient;
- micro-level algorithms where the specification permits equivalent correct approaches;
- production infrastructure before the official case requires it.

The agent may merge, split, or reorder slices inside a phase when evidence supports doing so. It may reorder phases only when dependencies remain satisfied and the active ExecPlan records the reason.

## 4. Version map

### v0.1 — Pre-TZ Deterministic Foundation — CURRENT

Purpose: use the pre-TZ period to build a correct, executable, heavily verified Ruby foundation without guessing the final product shell.

Must contain:

- canonical Ruby project/test harness;
- independent Ruby reference/oracle model;
- exact count/volume allocation baseline;
- economic intent and ownership semantics;
- normalized outcomes and safe recovery decisions;
- deterministic provider/fault simulator;
- immutable-enough decision/attempt/observation facts and derived projections needed for verification;
- property/state-machine/concurrency verification infrastructure;
- deterministic trace/replay diagnostics;
- baseline performance measurements.

Must not freeze without evidence:

- web framework;
- production database/ORM;
- queue/event bus/job system;
- deployment topology;
- official provider SDK/contracts;
- final public API/UI;
- ML/bandit strategy.

The active plan is `docs/exec-plans/active/pre-tz-foundation.md`.

### v0.2 — Official TZ Reconciliation and Integration

Entry condition: the full hackathon TZ is available.

Purpose: reconcile the pre-TZ model against authoritative requirements and adapt the stable kernel to the actual judge/interface/provider model.

Expected work:

- classify baseline requirements as `CONFIRMED`, `CHANGED`, `REMOVED`, `NEW`, or `AMBIGUOUS`;
- update spec, oracle, tests, and production behavior consistently;
- choose the minimal external architecture justified by the TZ;
- implement official input/API/provider adapters and persistence only if required;
- convert official limits/scoring criteria into executable gates;
- preserve reusable v0.1 invariants rather than rebuilding the core around infrastructure.

### v0.3 — Competitive Feature Complete

Purpose: maximize judged value once the real scoring model and data are known.

Potential work, only if justified:

- stronger provider-health/adaptive ranking;
- dynamic capacity handling;
- richer decision explanation/analytics;
- required API/UI/demo surface;
- failure-domain awareness;
- policy configuration/validation surfaces;
- measured algorithmic optimization.

Every promoted feature must have a measurable judged benefit or close a confirmed requirement gap.

### v1.0 — Submission Candidate

Purpose: produce the version presented and submitted to the hackathon.

Exit expectations:

- full TZ compliance;
- no unresolved P0 safety or acceptance defects;
- clean setup/run path;
- complete deterministic, property/model, fault, and concurrency verification appropriate to the final architecture;
- performance gates derived from actual limits;
- stable demo scenarios including failure/fallback/analytics;
- current documentation and decision trace;
- no hidden provisional semantics that conflict with the official case.

## 5. v0.1 phase graph

The default order is dependency-oriented, not bureaucratic:

`Orientation -> Harness -> Reference Model -> Core Algorithms -> Simulator/Lifecycle -> Combinatorial Verification -> Concurrency -> Trace/Analytics -> Hardening -> Version Closure`

Allocation and recovery can progress partly independently after common domain primitives exist. The simulator may be started as soon as normalized outcomes are stable enough. Verification is continuous; the dedicated verification phases deepen coverage rather than postponing testing.

## 6. v0.1 phases

### Phase 0 — Repository orientation and baseline integrity

Goal: establish the actual repository state before changing code.

Actions:

- read `AGENTS.md`, SPEC-001, architecture, testing, workflow, plans, decisions, backlog, and the active ExecPlan;
- inspect the current tree, tests, and implementation rather than assuming documentation progress is current;
- run any existing canonical checks;
- reconcile the active plan's `Progress` with actual evidence;
- identify the next missing capability, not merely the next unchecked bullet.

Exit gate:

- the active plan accurately reflects repository reality;
- no known contradiction between the intended current goal and the actual implementation is being ignored;
- a concrete first Slice Goal has been selected.

### Phase 1 — Ruby harness and feedback loop

Goal: make every later change cheap to verify.

Required outcomes:

- minimal conventional Ruby layout;
- one canonical full-suite command from repository root;
- focused-test command;
- deterministic seed handling for generated tests;
- clear test-support boundary;
- exact money representation decision sufficient for the baseline;
- no application framework unless already justified by a new authoritative requirement.

Verification:

- clean checkout/setup path works with documented commands;
- an intentionally failing test fails visibly and the canonical command returns failure;
- randomized test failures can report/replay a seed once such tests exist.

Freedom:

The agent may select Minitest/RSpec or a small property-testing dependency if evidence shows it improves reliability and does not create likely judge compatibility risk. Prefer fewer dependencies when capability is equivalent.

### Phase 2 — Independent executable reference model

Goal: create a simple oracle that expresses intended semantics independently from optimized production implementation.

Required outcomes:

- pure Ruby reference representation for payout intent, provider opportunity, allocation state, ownership, normalized outcomes, and recovery actions needed by current baseline tests;
- deliberately straightforward algorithms suitable for correctness comparison;
- no reuse of production allocator/recovery decision code inside the oracle.

Verification:

- deterministic examples from SPEC-001 run against the reference model;
- oracle can evaluate one-step allocation choices by brute force/reference calculation;
- oracle can reject illegal ownership/recovery histories.

Exit principle:

The reference model need not be production-fast or architecturally elegant. It must be small enough to trust and different enough from production code to catch shared defects.

### Phase 3 — Allocation kernel

Goal: implement correct deterministic allocation before adaptive intelligence.

Required outcomes:

- provider opportunities/feasible candidates represented explicitly;
- count policy using exact discrete measure;
- volume policy using exact money;
- post-decision discrepancy evaluation;
- committed/in-flight assignment accounting;
- no artificial debt from providers that were not opportunities when policy semantics require opportunity-aware accounting;
- explicit handling of no feasible provider and mathematically unavoidable deviation;
- provisional accounting/window semantics isolated behind a narrow boundary.

Verification:

- SPEC allocation acceptance scenarios;
- oracle comparison for generated small states;
- boundary/large-amount cases;
- provider-order/name invariance where applicable;
- deterministic tie behavior;
- first controlled committed-assignment race.

Exit gate:

No known allocation correctness defect remains in the supported v0.1 semantics, and the implementation remains replaceable around provisional TZ-dependent accounting details.

### Phase 4 — Economic ownership and recovery kernel

Goal: make retry/fallback semantics safe independently of transport/framework details.

Required outcomes:

- stable economic-intent identity;
- at most one unresolved money-moving owner;
- ownership acquire/release semantics;
- normalized `SUCCESS`, `PENDING`, `UNKNOWN`, safe route/provider failure, and terminal payout failure categories as required by the baseline;
- distinct actions for retry same provider, resolve status, fallback, defer, and terminal stop;
- cross-provider fallback prohibited while an unresolved prior owner can still create the monetary effect;
- outcome attribution separated from provider-health signal.

Verification:

- negative tests for illegal fallback after `UNKNOWN`;
- duplicate/replayed intent behavior;
- safe failure enables a fresh decision;
- terminal recipient/payout failure does not provider-hop;
- same-provider retry only under an explicitly safe simulated contract;
- reference-model history comparison for generated sequences.

### Phase 5 — Provider simulator, observations, and reconciliation model

Goal: make difficult provider behavior reproducible without live external services.

Required outcomes:

- deterministic Ruby provider script/scenario mechanism;
- immediate success/failure;
- `PENDING`;
- timeout/`UNKNOWN` after possible acceptance;
- delayed resolution;
- duplicate and out-of-order observations;
- optional reversal/return path where useful to test non-final success semantics;
- explicit provider idempotency/status-resolution capabilities in simulator contracts;
- virtual/controlled time when timing matters.

Verification:

- scripted scenarios replay identically;
- duplicated observations do not duplicate economic effects;
- out-of-order observations do not corrupt derived state;
- unresolved ownership remains safe across time progression/reconciliation.

### Phase 6 — Property and state-machine verification

Goal: move beyond hand-picked cases and search the state space automatically.

Required outcomes:

- generators for valid amounts, policies, provider sets, eligibility, and outcome sequences;
- reusable invariant assertions from `docs/TESTING.md`;
- model/state-machine sequences that exercise multiple operations over time;
- seed/trace output and deterministic replay of failures;
- regression capture for every material discovered bug.

High-value properties include:

- single unresolved economic owner;
- selected provider belongs to feasible set;
- `UNKNOWN` preserves ownership;
- duplicate observations are idempotent;
- allocation result matches or is no worse than oracle post-decision discrepancy for generated small states;
- accounting/projection conservation;
- replay derives the same state.

The agent should bias generators toward rare/high-risk states instead of spending most cases on easy happy paths.

### Phase 7 — Controlled concurrency correctness

Goal: prove the two concurrency-sensitive invariants rather than hope stress testing finds races.

Required outcomes:

- deterministic barriers/hooks/interleavings sufficient to force ownership acquire/acquire races;
- deterministic committed-allocation reservation races;
- duplicate submission races;
- ownership release vs fallback races;
- relevant callback/reconciliation races;
- history assertions consistent with legal sequential domain semantics.

Verification:

- forced races repeatedly satisfy single ownership;
- concurrent routing cannot make all workers consume the same stale deficit;
- concurrency tests fail when critical synchronization is deliberately removed/seeded where practical;
- stress tests supplement but do not replace controlled interleavings.

No final distributed lock/database mechanism is required in v0.1 unless independently justified.

### Phase 8 — Decision trace and baseline analytics projections

Goal: prove that the system can explain intended routing versus actual execution.

Required outcomes:

- preserve enough facts to distinguish opportunity, assignment, attempt, observation, and settlement;
- identify primary versus recovery decisions;
- expose material exclusion/decision reasons;
- project target vs assignment distribution and effective settlement distribution for baseline scenarios;
- attribute deviations/failures where the domain model knows the cause;
- replay projections from durable facts.

Do not build a dashboard before the TZ asks for one.

Verification:

- primary provider may differ from settlement provider after fallback without losing either fact;
- replay reconstructs the same projections;
- recipient failure does not appear as provider-attributable reliability failure;
- runtime policy infeasibility is visible rather than silently hidden.

### Phase 9 — Hardening and performance baseline

Goal: make v0.1 robust enough that official-TZ work starts from a trusted kernel.

Actions:

- run the full deterministic suite;
- run larger property/state-machine workloads with captured seeds;
- run concurrency/fault suites repeatedly;
- add regression tests for discovered defects;
- perform targeted mutation/fault seeding of critical invariants where practical;
- remove speculative abstractions and duplicated helpers revealed by implementation;
- benchmark allocation/decision/replay paths and record observed throughput/latency/memory without inventing pass/fail limits;
- verify clean setup and canonical commands.

Exit gate:

No known P0/P1 correctness defect remains in implemented v0.1 behavior, tests are deterministic/reproducible, and the active plan contains current evidence rather than aspirational checkboxes.

### Phase 10 — v0.1 version closure

Goal: decide whether the session may legitimately stop.

The agent performs a skeptical project-wide review:

- compare implementation to current SPEC-001 and decisions;
- compare acceptance IDs to executable evidence;
- inspect architecture boundaries for provider/framework leakage;
- inspect `docs/TESTING.md` quality gates;
- review backlog and separate true TZ blockers from unfinished current work;
- update docs that became stale during implementation;
- ensure all product/reference/simulator/test logic remains Ruby;
- run canonical full verification from a clean state;
- summarize benchmark baseline and remaining provisional semantics.

If any current-version exit criterion is not met and can be addressed locally, the version is not complete: create/select another Slice Goal and continue.

## 7. v0.1 exit criteria

The current version is complete only when all of the following are true:

1. A clean checkout can run the documented Ruby test suite with one canonical command.
2. The reference/oracle model exists and is independent enough to catch implementation defects.
3. Count and volume allocation baseline behavior is implemented and checked against the oracle for representative/generated states.
4. Committed/in-flight allocation prevents stale-deficit stampedes in controlled concurrency tests.
5. Economic ownership, `UNKNOWN`, safe release, terminal failure, retry/fallback/resolve/defer semantics have executable evidence.
6. The provider simulator can deterministically reproduce the high-risk lifecycle/fault scenarios used by the suite.
7. Property/state-machine tests explore multi-step histories and emit replayable seeds/traces.
8. Controlled concurrency tests cover ownership and allocation critical sections.
9. Opportunity/assignment/attempt/settlement remain distinguishable and baseline projections/replay are verified.
10. All material bugs found during the run have deterministic regressions.
11. Full verification is green or any unavailable check has an exact external reason; no hidden flaky retry policy masks failures.
12. Baseline performance measurements exist without pretending guessed limits are official requirements.
13. Ruby-only implementation policy is respected.
14. No unjustified framework/database/queue/ML/public-contract commitment has entered the codebase.
15. The active ExecPlan, backlog, decisions, and relevant docs reflect the actual final state.
16. Remaining work is either a later-version improvement or genuinely blocked on external TZ information.

Only then may the active pre-TZ ExecPlan be closed/moved to completed and the Goal Mode run stop for version completion.

## 8. How to select the next Slice Goal

At any checkpoint, choose the next slice using this priority:

1. fix a failing safety/correctness invariant;
2. unblock the current phase's exit gate;
3. build a missing verification capability required to trust upcoming code;
4. implement the smallest missing dependency of the next high-value behavior;
5. reduce a known high-risk uncertainty with a focused prototype/test;
6. only then perform non-blocking cleanup or optimization.

Do not select work merely because it is easy or interesting.

Keep at most a small rolling set of immediate next actions in the active ExecPlan. Do not pre-expand every future phase into hundreds of microtasks.

## 9. Replanning rules

The roadmap is not permission to follow a bad path stubbornly.

Replan when evidence shows:

- an assumption is false;
- a phase dependency was misunderstood;
- tests reveal a missing invariant;
- the chosen abstraction makes a key invariant difficult to prove;
- Ruby/runtime behavior invalidates the approach;
- the full TZ arrives and changes semantics;
- a simpler design can satisfy the same verified outcome with less risk.

When replanning:

1. preserve the version goal unless authoritative requirements change it;
2. update the active ExecPlan's discoveries/decision log;
3. adjust phases/slices only as much as necessary;
4. add tangential opportunities to backlog instead of absorbing them;
5. continue from the best current state rather than restarting the project.

## 10. Commit/checkpoint discipline

Commits are engineering checkpoints, not permission gates.

- Commit coherent, verified changes when doing so improves recoverability and reviewability.
- Do not create a commit for every tiny edit merely to show activity.
- Do not postpone all verification until one giant final commit.
- Do not ask for routine permission before the next verified slice.
- Never force-rewrite shared `main` history unless explicitly instructed.
- If the current tool/session policy requires a particular branch/commit strategy, obey it without changing the roadmap semantics.

A commit or phase boundary never implies that the long-running goal is complete.

## 11. Relationship to other documents

- `AGENTS.md` — operating constraints and navigation map.
- `specifications/001-smart-payout-routing.md` — behavioral source of truth.
- `docs/ARCHITECTURE.md` — dependency/domain boundaries.
- `docs/TESTING.md` — evidence methodology and scenario catalog.
- `docs/WORKFLOW.md` — execution loop and autonomy rules.
- `docs/PLANS.md` — how living ExecPlans are maintained.
- `docs/exec-plans/active/pre-tz-foundation.md` — current v0.1 execution state.
- `docs/BACKLOG.md` — work not necessarily inside the active slice/version.
- `docs/DECISIONS.md` — durable rationale/provisional decisions.

This roadmap defines sequencing and completion. It does not override the specification.