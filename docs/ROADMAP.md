# Long-Horizon Development Roadmap

## 1. Project Goal

Build RubyRouting into a coherent, deeply verified, submission-ready smart payout-routing product in Ruby for Hack.Genesis.

The project no longer treats the official TZ as the starting point for product development. We build the product first and use the TZ later to reconcile exact external semantics, interfaces and scoring constraints.

Work hierarchy:

`Project Goal -> Version Goal -> Phase Goal -> Slice Goal`

A verified slice or phase is a checkpoint, never an automatic stop condition.

## 2. Current Version Goal

**v0.3 — Product Convergence & Full Routing Product — CURRENT**

Purpose: transform the strong but partially fragmented routing repository into one coherent product centered on the payout-routing case.

v0.3 is complete only when the product has a single canonical routing pipeline, no misleading disconnected production branches, a universal policy/admission/allocation/recovery model, restart-safe durable semantics, strong analytics/audit/application boundaries, and deep reproducible verification.

Normative scope: SPEC-004 plus inherited applicable behavior from SPEC-003/002/001.

Active plan: `docs/exec-plans/active/product-convergence.md`.

Completion authority: `docs/COMPLETION_POLICY.md`.

## 3. Version map

### v0.1 — Deterministic Foundation — HISTORICAL CHECKPOINT

Delivered exact money/allocation, initial economic ownership/recovery, simulator, facts/analytics and baseline test infrastructure.

### v0.2 — Comprehensive Routing Core — STRONG CHECKPOINT

Delivered the important generic routing core:

- operation dispatch safety;
- operation-scoped recovery contract;
- count/volume allocation with committed work;
- primary/recovery separation;
- policy fingerprinting;
- context eligibility/opportunity;
- capacity reservations;
- deterministic provider health;
- recovery budgets/time/reconciliation;
- duplicate/out-of-order reduction;
- settlement/reversal/economic-conflict handling;
- lifecycle/allocation/capacity/health replay;
- multi-currency policy registry;
- deep property/model/concurrency/fault coverage.

This checkpoint is valuable but is not the finished product.

### v0.3 — Product Convergence & Full Routing Product — CURRENT

Build the nearly finished product before the TZ.

Mandatory outcomes:

1. one canonical end-to-end routing pipeline;
2. coherent internal architecture with focused ledgers/reducers and one atomic correctness boundary;
3. universal policy model for allocation strategy, targets, scope, constraints, windows and recovery;
4. correct opportunity/admission model for eligibility, availability, capacity, throughput/rate and health;
5. exact allocation accounting with explicit deviation/debt semantics;
6. constrained optimization that cannot violate higher-priority safety/allocation obligations;
7. mature provider contract/normalization/recovery/reconciliation lifecycle;
8. restart-safe durability for unresolved payouts before durability is called complete;
9. causal analytics and auditable decision trace;
10. safe application/API boundary and demonstrable product flow;
11. deterministic simulator plus seeded adversarial/fault/concurrency/crash testing;
12. measured performance/load evidence;
13. clean repository with no fake production adapters, misleading product claims or dead experimental core hooks.

### v0.4 — Official TZ Reconciliation & Judge Integration

Entry condition: authoritative full case/TZ is published.

Purpose:

- classify current semantics as `CONFIRMED / CHANGED / REMOVED / NEW / AMBIGUOUS`;
- adapt exact allocation definitions/defaults;
- map official provider/status/input/output contracts;
- satisfy runtime/dependency restrictions;
- integrate supplied judge/simulator/API contract;
- convert official load/scoring constraints into executable gates.

The goal is adaptation of an already mature product, not construction from scratch.

### v0.5 — Judged Optimization & Demo Hardening

Only after scoring and official data are known:

- tune reliability/cost/latency objectives;
- add adaptive/statistical routing only when it has measurable value and safe exploration;
- optimize performance against actual limits;
- polish judged analytics/demo/UI.

### v1.0 — Submission Candidate

Requires full official-TZ compliance, no open P0/P1 acceptance defects, clean setup/run, stable demo, restart-safe behavior where applicable, and final deterministic/property/model/fault/concurrency/performance evidence.

## 4. Product-convergence capability matrix

### PC1 — Canonical routing pipeline

Every production feature has a clear place in:

`Intent -> Policy -> Opportunity -> Admission -> Allocation -> Optimization -> Atomic Commit -> Provider -> Observation -> Lifecycle/Recovery -> Durable State -> Analytics/API`.

No alternate routing semantics in API, persistence or demo code.

### PC2 — Economic safety/lifecycle

- one economic intent;
- one unresolved owner max;
- dispatch phase;
- stable operation/attempt identity;
- provider idempotency semantics;
- UNKNOWN/pending handling;
- safe release;
- late conflicts and remediation.

### PC3 — Policy engine

- count/volume strategies;
- provider target shares/weights;
- policy identity/epoch/fingerprint;
- scope/segment;
- accounting point;
- explicit window semantics;
- tolerance/corridor;
- provider share min/max obligations distinct from per-payout amount eligibility;
- hard/soft constraints;
- static and runtime infeasibility;
- recovery policy;
- optimization policy.

### PC4 — Provider opportunity and admission

Separate:

- functional eligibility;
- administrative enablement;
- live availability;
- concurrency exposure;
- throughput/rate budget;
- amount exposure;
- operational health/quarantine/probing.

Admission is a hard gate before allocation optimization.

### PC5 — Allocation controller

- exact count/volume accounting;
- committed/in-flight primary work;
- large indivisible payouts;
- opportunity-aware denominator;
- policy epochs/windows;
- target deviation attribution;
- explicit recoverable versus unavoidable deviation;
- bounded catch-up/debt where enabled;
- no recovery pollution of primary ledger under primary-assignment accounting.

### PC6 — Constrained optimization

Optimization is lexicographic/constrained, not one arbitrary scalar.

Required priority:

`safety -> hard eligibility -> operational admission -> allocation admissibility -> reliability/quality -> cost/latency/priority -> exploration`.

Reliability estimates must account for attribution, maturity and confidence. Pending/unknown must not be blindly scored as provider failures.

### PC7 — Recovery and reconciliation

- same-provider status/retry only when safe;
- fresh fallback after safe release;
- attempted-provider exclusion;
- operation/switch/resolution budgets;
- deadline/TTL;
- explicit defer/resume/reconcile;
- returned/reversed outcomes;
- economic-conflict remediation;
- no blind fallback on ambiguous timeout.

### PC8 — State architecture

Keep one atomic transaction boundary while decomposing internal responsibility into focused components such as:

- payout/operation registry;
- allocation ledger;
- admission/capacity ledger;
- health projection/controller;
- lifecycle reducer;
- fact/state repository.

Coordinator size alone is not the objective; ownership of invariants is.

### PC9 — Durable continuation

If durable mode exists, restart must preserve enough state to continue safely, not only display replay projections.

At minimum preserve/rebuild:

- intents;
- policy bindings;
- operations/phases;
- ownership;
- idempotency/provider contracts;
- dedup/order state;
- allocation/admission reservations needed for correctness;
- settlement/reconciliation state.

Corruption/truncation is explicit. Silent history loss is forbidden.

### PC10 — Provider boundary

Raw provider status/error/webhook data is translated through provider-specific normalization into typed domain evidence.

External callers cannot directly assert `safe_to_release` or provider attribution as trusted core facts.

### PC11 — Analytics/audit

At minimum:

- target vs actual by count/volume;
- opportunity -> primary assignment -> attempt -> settlement;
- first-attempt and eventual success;
- fallback recovery;
- attempts/amplification;
- provider-attributable failures;
- unknown/pending/reconciliation age;
- availability/capacity/health exclusions;
- deviation attribution;
- conflict/reversal counts;
- complete decision trace.

### PC12 — Application/product surface

A stable application command/query layer exposes product behavior without bypassing the core. API/demo UI may be implemented only over those commands/queries and normalized provider adapters.

### PC13 — Verification

- deterministic acceptance/regressions;
- independent oracle/property/model tests;
- controlled concurrency races;
- seeded fault/chaos tests;
- restart/crash-at-boundary tests;
- corrupted durable-history tests where persistence exists;
- replay equivalence;
- end-to-end multi-provider scenarios;
- performance/load campaigns after correctness.

### PC14 — Repository coherence

No production path contains:

- hardcoded provider-brand/BIN trivia without an explicit plugin/demo reason;
- fake real-world adapters labeled as production;
- unreachable optional feature hooks;
- broad raw external trust of financial semantics;
- false completion/version claims;
- warnings or nondeterministic tests that are knowingly ignored at closure.

## 5. Development phases

### Phase A — Convergence baseline and cleanup

- remove/demote misleading disconnected feature burst;
- get clean CI on the reduced coherent core;
- inventory public/reachable modules;
- establish canonical pipeline ownership.

### Phase B — Internal architecture convergence

- extract focused ledgers/reducer responsibilities from `State::Coordinator` where this improves invariant ownership;
- keep one atomic facade/transaction boundary;
- remove duplicate decision/recovery semantics.

### Phase C — Policy/allocation completeness

- separate per-payout eligibility limits from provider share obligations;
- complete policy windows/tolerance/min-max/deviation/debt semantics;
- prove count/volume behavior under concurrency and changing opportunity.

### Phase D — Admission controller

- unify availability/capacity/throughput/health into explicit admission;
- distinguish concurrent exposure from time-based throughput budget;
- recheck admission atomically for fallback/primary decisions.

### Phase E — Constrained smart optimization

- define admissible allocation envelope first;
- add deterministic reliability/quality/cost/latency optimization within it;
- add confidence/maturity/segment semantics before considering adaptive ML.

### Phase F — Provider lifecycle/reconciliation hardening

- consolidate operation contract/normalization/recovery/reconciliation;
- verify all ambiguous and late-event paths.

### Phase G — Durable state and restart safety

- specify durable store contract;
- implement a minimal correct durable adapter;
- prove restart continuation for unresolved operations and atomic state;
- prove explicit corruption behavior.

### Phase H — Analytics and audit productization

- complete causal ledgers/metrics and decision trace;
- verify conservation/replay.

### Phase I — Application/API/demo layer

- stable commands/queries;
- provider webhook through normalization;
- safe error surface;
- useful demo/dashboard only after core contracts are stable.

### Phase J — Deep verification and performance

- seeded adversarial fuzz;
- model histories;
- controlled races;
- crash injection;
- long-history replay;
- 10k/100k load campaigns where claimed;
- optimize measured bottlenecks only.

### Phase K — Product closure/red-team

Enter `VERSION_CANDIDATE`, then execute the full completion protocol from current code. Any material locally solvable finding reopens development.

## 6. Current next actions

The implementation phases are materially exercised in the current working-tree
candidate. The remaining actions are closure gates, not a return to the
historical baseline sequence:

1. Run CI on the exact candidate revision after the working-tree changes are
   committed/published through the repository workflow.
2. Recheck the full completion protocol and keep `VERSION_CANDIDATE` if CI or
   a fresh red-team pass finds a material local gap.
3. Reconcile exact external semantics, interfaces and scoring only when the
   official TZ is published; its absence is not a v0.3 blocker.

## 7. Stop condition

Do not stop because v0.2 was green or because the TZ is missing.

Stop v0.3 only after the Product Closure Protocol passes or every remaining required product path is genuinely externally blocked.
