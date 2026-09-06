# Long-Horizon Development Roadmap

## 1. Project Goal

Build a competitive, correct, explainable smart payout-routing system in Ruby for Hack.Genesis.

The pre-TZ period is used to implement **all high-value generic routing mechanics** that can be designed, configured, simulated and verified without guessing the official external contract. The official TZ should mainly trigger reconciliation/integration, not first-time construction of the financial core.

Work hierarchy:

`Project Goal -> Version Goal -> Phase Goal -> Slice Goal`

A verified slice or phase is a checkpoint, never an automatic stop condition.

## 2. Current Version Goal

**v0.2 — Pre-TZ Comprehensive Routing Core — CURRENT**

v0.2 must turn the first deterministic foundation into a coherent generic payout orchestration engine covering safety, policy, allocation, eligibility, capacity, health, ranking, recovery, lifecycle, replay, analytics and concurrency together.

Normative scope comes from SPEC-001 + SPEC-002 + SPEC-003.

Active plan: `docs/exec-plans/active/pre-tz-comprehensive-core.md`.

Completion authority: `docs/COMPLETION_POLICY.md`.

## 3. Continuation contract

Goal Mode continues while required current-version work is locally actionable.

Stop only when:

1. v0.2 reaches `VERSION_COMPLETE` through the mandatory closure protocol; or
2. every remaining required v0.2 path passes the genuine external-blocker test.

The following are not stop reasons:

- all originally planned phases are green;
- full tests are green;
- all issues known at session start are fixed;
- the official TZ is not yet available;
- a difficult local bug/refactor remains;
- one subtask is blocked while other required work can advance.

When planned phases appear complete, move to `VERSION_CANDIDATE`, perform fresh closure discovery and reopen implementation if new gaps are found.

## 4. Version map

### v0.1 — Deterministic Foundation — HISTORICAL CHECKPOINT

Delivered:

- CRuby 4.0.6 / Minitest / Rake harness;
- exact Money and deterministic count/volume allocator;
- initial economic ownership / UNKNOWN safety;
- coarse linearizable in-memory coordinator;
- provider I/O outside lock;
- provider simulator;
- initial reference/property/model/concurrency evidence;
- append-preserved facts and baseline analytics;
- benchmark baseline.

The 2026-08-27 technical review proved this was not the end of useful pre-TZ development.

Historical plan: `docs/exec-plans/completed/pre-tz-foundation.md`.

### v0.2 — Pre-TZ Comprehensive Routing Core — CURRENT

Purpose: make the core broadly complete across plausible official-TZ variants while keeping external interfaces replaceable.

### v0.3 — Official TZ Reconciliation and Integration

Entry condition: authoritative full case/TZ becomes available.

Purpose:

- classify SPEC-001/002/003 as `CONFIRMED`, `CHANGED`, `REMOVED`, `NEW`, `AMBIGUOUS`;
- update spec/oracle/tests with changes;
- adapt production behavior;
- choose only now-justified API/framework/persistence/provider integration;
- turn judge limits/scoring into executable gates.

### v0.4 — Competitive/Judged Optimization

Only after scoring/data are known:

- advanced quality/success optimization;
- cost/latency multi-objective tuning;
- failure-domain awareness;
- richer judged UI/demo;
- adaptive/statistical routing when measurable;
- measured performance specialization.

### v1.0 — Submission Candidate

Requires full TZ compliance, no P0/P1 acceptance defects, clean setup/run, final deterministic/property/model/fault/concurrency evidence, official performance gates and stable demo/analytics.

## 5. Mandatory v0.2 capability matrix

These are required capability families, not suggestions. Exact official defaults remain configurable/provisional.

### C1 — Economic intent and operation lifecycle

- one economic intent;
- single unresolved economic owner;
- operation/attempt identity;
- committed versus dispatching/dispatched;
- pending/unknown/terminal/released;
- safe release rules;
- economic conflict detection.

### C2 — Policy model

- immutable policy identity/epoch/fingerprint;
- count and volume measures;
- targets/weights;
- scope/segment;
- accounting point;
- explicit window/epoch semantics;
- tolerance/deviation;
- generic min/max constraints;
- hard versus soft/relaxable business constraints;
- recovery policy/budgets;
- ranking inputs.

### C3 — Allocation controller

- exact arithmetic;
- post-decision discrepancy;
- committed/in-flight primary reservations;
- large indivisible payouts;
- primary versus recovery separation;
- opportunity-aware accounting;
- policy epochs;
- runtime infeasibility/deviation attribution;
- bounded catch-up/debt if debt is enabled.

### C4 — Provider opportunity/eligibility

- currency compatibility;
- amount boundaries;
- administrative enabled state;
- explicit capability/context labels where applicable;
- functional opportunity independent from live health/capacity.

### C5 — Live feasibility and capacity

- availability;
- concurrent slots;
- configurable count budget;
- configurable amount budget;
- atomic reservation/release;
- no capacity leaks under duplicate/late observations;
- fallback re-evaluation.

### C6 — Operational health/exposure

- attributable operational signals;
- minimum evidence;
- hysteresis;
- degraded/quarantined/probing equivalent states;
- fast reduction of exposure for strong evidence;
- controlled recovery/probing;
- recipient failures neutral to provider health.

### C7 — Deterministic ranking

- ranking only inside safe feasible set;
- configured priority;
- available health/quality inputs;
- optional configured cost/latency inputs;
- deterministic tie-breaking;
- hard constraints lexicographic.

### C8 — Recovery/reconciliation

- retry same operation/provider only when contract safe;
- status resolution;
- fresh cross-provider fallback excluding attempted providers;
- wait/defer;
- reconciliation-blocked;
- terminal stop;
- separate operation/switch/resolution budgets;
- controlled time/deadline/TTL;
- explicit resume/advance/reconcile workflow.

### C9 — Provider contract/transport

- operation-scoped idempotency/status lookup semantics;
- contract version/TTL where applicable;
- adapter availability before commit;
- definitely-not-sent versus ambiguous-after-possible-send;
- normalized provider observations.

### C10 — Event reduction

- immutable observation identity;
- duplicate idempotency;
- conflicting identity reuse rejected;
- authoritative provider sequence only when contract says so;
- explicit legal/conservative transitions;
- no arbitrary status-rank chronology.

### C11 — Settlement/reversal/conflict

- settlement distinct from attempt;
- post-settlement return/reversal;
- late old-operation monetary evidence -> explicit economic conflict;
- no ordinary fallback continuation for reversal/conflict remediation.

### C12 — Facts/replay

- facts contain all material lifecycle inputs;
- lifecycle/ownership/operation/settlement/conflict replay;
- live projection equals replayed projection for supported histories;
- no hidden mutable correctness source of truth.

### C13 — Trace/analytics

- typed reason codes;
- policy fingerprint;
- opportunity/live exclusions;
- allocation/capacity/health/ranking snapshots as relevant;
- primary allocation distribution;
- recovery attempts;
- settlement distribution;
- first-attempt/eventual success;
- successful fallback recovery;
- unresolved age;
- attempt/switch amplification;
- failure attribution;
- deviation causes;
- reversal/conflict metrics.

### C14 — Concurrency/deep verification

- owner acquire/acquire;
- duplicate submit during dispatch;
- primary allocation reservation races;
- capacity reservation races;
- ownership release/fallback races;
- callback/reconciliation versus recovery;
- live provider-state update versus commit;
- policy identity/epoch races where supported;
- generated multi-feature histories with replayable seeds.

## 6. v0.2 dependency graph

Default order:

`A audit/regressions`
`-> B primary/recovery correctness`
`-> C operation dispatch/provider contract`
`-> D lifecycle reducer/replay/conflict`
`-> E policy/opportunity/allocation completeness`
`-> F capacity`
`-> G health/ranking`
`-> H recovery/time/reconciliation`
`-> I trace/analytics`
`-> J cross-feature hardening`
`-> K VERSION_CANDIDATE closure/red-team`

Phases may be split/reordered when dependencies remain correct. Closure can reopen any earlier phase.

## 7. Phase A — Executable baseline and regression capture

Required:

- run current canonical suites in an executable environment;
- record actual runtime/results, not historical values;
- add deterministic regressions for audited P0 findings;
- add minimal Ruby CI if reasonably possible;
- reconcile discrepancies between historical evidence and current source.

Priority regressions:

- recovery mutates primary allocation;
- skewed allocation reselects failed provider;
- duplicate command during blocked dispatch;
- unresolved operation loses resolution after route disablement;
- missing adapter commits owner;
- old provider late success after newer settlement;
- status-rank ordering accepts invalid chronology.

Exit: current baseline known and P0 behavior falsifiable.

## 8. Phase B — Primary allocation/recovery correctness

Implement:

- primary allocation commits only at configured accounting point;
- recovery facts/attempts separate from primary ledger;
- attempted-provider history;
- fresh fallback excludes attempted money-moving providers;
- explicit same-provider retry remains operation-scoped;
- successful fallback recovery metric means actual successful recovery.

Verify skewed targets, repeated failures, conservation and concurrency.

## 9. Phase C — Operation dispatch and provider contract

Implement:

- explicit operation dispatch phase;
- operation-scoped provider recovery/idempotency contract;
- adapter availability as admissibility input;
- structured transport result: not-sent / ambiguous / provider-observation;
- duplicate command cannot resolve/retry while first dispatch is still in progress.

Provider I/O remains outside mutex.

## 10. Phase D — Lifecycle reducer, event order, replay and conflicts

Implement:

- legal operation/payout transition reducer;
- removal of `outcome_rank` chronology;
- contract-aware sequence/version handling;
- conservative unordered observations;
- full lifecycle facts/replay;
- live-versus-replay equivalence;
- economic-conflict fact/projection;
- settlement return/reversal path.

## 11. Phase E — Complete policy/opportunity/allocation model

Implement the mandatory generic policy dimensions rather than only weights:

- fingerprint/identity collision prevention;
- count/volume strategy;
- scope/segment;
- accounting/window/epoch;
- tolerance;
- generic min/max and hard/soft constraint primitives;
- static feasibility;
- runtime infeasibility/deviation attribution;
- context-aware provider profile for currency/amount/admin/labels;
- opportunity independent from live feasibility;
- transient outage does not reset history;
- explicit bounded deviation/catch-up semantics.

Do not build a generic expression DSL.

## 12. Phase F — Capacity ledger

Implement:

- concurrent slots;
- configurable count budget;
- configurable amount budget;
- atomic reservation with operation ownership where required;
- explicit release/settle semantics;
- UNKNOWN/pending retention where economically unresolved;
- duplicate-safe/no-leak behavior;
- fallback capacity recheck.

## 13. Phase G — Operational health and deterministic ranking

Implement:

- attributable health signal projection;
- minimum evidence/hysteresis;
- degraded/quarantined/probing lifecycle;
- controlled recovery exposure;
- recipient failure neutrality;
- allocation pressure cannot bypass quarantine/probe caps;
- deterministic feasible-set ranker with configured priority and optional available quality/cost/latency.

No ML/bandit requirement in v0.2.

## 14. Phase H — Recovery budgets, time and reconciliation

Implement:

- separate money-moving operation limit;
- provider-switch limit;
- resolution/retry interaction limit;
- controlled clock/deadline/elapsed budget;
- operation idempotency/status TTL;
- explicit submit versus resume/advance/reconcile use cases;
- reconciliation-blocked state when safe automatic action is no longer possible.

## 15. Phase I — Typed trace and causal analytics

Implement machine-readable decision/exclusion/deviation/recovery reason codes and metrics required by capability C13.

Analytics may not parse human explanation strings to infer machine semantics.

## 16. Phase J — Cross-feature verification/hardening

Build long-history generated/model scenarios combining mechanisms rather than testing only isolated components.

Required combinations include:

- allocation + capacity + outage;
- allocation pressure + health quarantine;
- UNKNOWN + duplicate command + TTL;
- safe failure + live fallback changes;
- fallback + late old success;
- policy change + concurrency;
- reversal + replay + analytics;
- capacity + duplicate/late observations;
- health recovery + bounded exposure + deviation.

Expand controlled races and perform targeted fault/mutation seeding of critical protections where practical.

Re-run benchmarks after correctness changes and refactor only evidence-backed responsibility problems.

## 17. Phase K — Version Closure / Red-Team

When A–J appear green, set status **`VERSION_CANDIDATE`**, not complete.

Execute every pass in `docs/COMPLETION_POLICY.md`:

1. source/spec reconciliation against SPEC-001/002/003;
2. complete C1–C14 capability sweep;
3. repository TODO/placeholder/duplicate-semantics/hidden-state discovery;
4. adversarial counterexample/red-team pass;
5. full current verification and CI/static/benchmark evidence as required;
6. every NOW/P0/P1 backlog item classified;
7. genuine blocker test;
8. documentation consistency audit.

If any important locally solvable gap appears, create/reopen a slice/phase and continue. The roadmap does not require progress checkboxes to remain monotonic.

## 18. v0.2 exit criteria

v0.2 reaches `VERSION_COMPLETE` only when all are true:

1. every audited P0 defect has deterministic regression evidence;
2. every SPEC-003 capability C1–C14 is implemented and important interactions are tested;
3. SPEC-001/002/003 applicable pre-TZ requirements are reconciled to actual code/tests;
4. primary/recovery/settlement accounting is unambiguous and conserved;
5. dispatch/transport ambiguity and operation-scoped contracts are explicit;
6. policy identity/scope/window/tolerance/generic constraints and feasibility are explicit;
7. opportunity/live feasibility/capacity/health are distinct;
8. capacity reservations are race-safe and leak-free;
9. deterministic health/probing/ranking works inside hard constraints;
10. recovery budgets/time/TTL/resume/reconcile are explicit;
11. lifecycle observations reduce without artificial status chronology;
12. facts replay supported lifecycle/ownership/settlement/conflict state;
13. late contradictory monetary evidence surfaces a conflict;
14. reversal/return is distinct post-settlement behavior;
15. typed trace/analytics cover causal allocation/recovery/health outcomes;
16. expanded property/model/concurrency/fault suites cover cross-feature histories with replayable seeds/traces;
17. canonical full current verification is green; unavailable checks are explicitly explained, never assumed;
18. closure red-team finds no unresolved material locally solvable generic gap;
19. every NOW/P0/P1 item is resolved, superseded by equivalent behavior, or genuinely external-TZ dependent with evidence;
20. documentation consistently identifies current version, current architecture and completion rules;
21. no unjustified framework/database/queue/ML/public-contract commitment was introduced;
22. remaining work is genuinely official-TZ-specific integration or optional post-core optimization.

Only then may the project legitimately enter pre-TZ maintenance/wait state, or immediately advance to v0.3 if the TZ is available.

## 19. Next-slice priority

At every checkpoint choose:

1. P0 financial/safety defect;
2. failing invariant/regression;
3. missing capability from current phase/C1–C14;
4. verification needed to trust the next mechanism;
5. P1 generic full-core capability;
6. measured maintainability/performance issue;
7. optional judged optimization only after deterministic core completeness.

Do not spend time on speculative external infrastructure or ML while a required deterministic domain gap exists.
