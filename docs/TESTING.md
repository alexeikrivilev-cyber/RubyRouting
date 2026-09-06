# Testing Strategy

Current target: **v0.3 — Product Convergence & Full Routing Product**.

Testing exists to falsify financial, routing, restart and integration assumptions. Green tests are necessary but never sufficient for version completion.

## 1. Ruby-only and deterministic by default

All executable product/reference/simulator/property/model/concurrency/fault logic is Ruby.

Correctness-sensitive tests must use controlled time and reproducible randomness. Global `rand`, real `sleep` and wall-clock time are not acceptable in core verification unless the test is explicitly a nondeterministic load experiment outside correctness gates.

Generated/fuzz failures must record seed/trace and become deterministic regressions when material.

## 2. Core verification objectives

Prove:

1. one economic intent cannot accidentally create multiple independent payout effects;
2. dispatch/UNKNOWN/safe-release semantics are correct;
3. count/volume allocation follows explicit policy with exact arithmetic and committed work;
4. opportunity, live admission and optimization stay separate;
5. throughput/rate state is not confused with concurrent capacity exposure;
6. optimizer cannot violate hard/admission/allocation constraints;
7. provider health uses correct attribution and controlled recovery;
8. recovery/reconciliation obey operation contracts, budgets and time;
9. duplicate/delayed/out-of-order events do not corrupt state;
10. settlement/reversal/economic conflict remain distinct;
11. facts/replay match supported live state;
12. durable restart safely restores the state required to continue unresolved payouts;
13. analytics conserve opportunity/assignment/attempt/settlement semantics;
14. critical concurrency histories remain safe;
15. public/provider boundaries cannot inject trusted financial semantics incorrectly.

## 3. Test layers

### A — Value/unit

Money, policy values, constraints, exact discrepancy, provider contracts, normalized outcomes, health/admission arithmetic, typed reasons.

### B — Deterministic acceptance/regression

Every normative behavior and every material bug has explicit executable evidence.

### C — Independent oracle/property

Reference models should cover:

- allocation/discrepancy;
- ownership legality;
- recovery action legality;
- admission/capacity conservation;
- lifecycle/replay invariants;
- policy/share invariants.

The oracle must not invoke production algorithms it verifies.

### D — State-machine/model histories

Generate long histories with submit, dispatch, observations, UNKNOWN/pending, resolve/retry/fallback, provider state changes, policy changes, capacity/admission, health, reconciliation, reversal/conflict and replay.

### E — Controlled concurrency

Required race families include:

- two workers for one payout;
- duplicate submit during dispatch;
- concurrent primary allocation over one deficit;
- competing last capacity/admission slot;
- provider state change versus decision commit;
- safe release versus fallback;
- callback versus reconciliation/status lookup;
- restart/recovery handoff where simulated.

Use barriers/hooks, not hope-based stress.

### F — Provider contract/normalization

For each simulator/real adapter verify raw-to-domain mapping, idempotency identity, status resolution, transport ambiguity, terminal/pending/unknown semantics, ordering and duplicate behavior.

Raw payload fields cannot directly bypass normalization to assert financial safety.

### G — End-to-end scenarios

High-value cases:

- immediate success;
- primary safe failure -> fallback success;
- primary UNKNOWN while alternates healthy -> no cross-provider fallback;
- pending -> resolve -> success;
- provider disabled after operation creation -> old operation still resolves;
- skewed allocation plus fallback;
- outage/capacity/health pressure with target deviation attribution;
- large indivisible volume;
- policy epoch change;
- late old success after newer settlement -> conflict;
- settlement -> reversal;
- no-safe-route/defer/resume;
- ownerless defer is represented as `:deferred` in live state, working restore,
  replay and analytics, while owner-held defer preserves the unresolved status;
- malformed `DecisionProposal` control shapes (invalid defer/terminal roles or
  non-operation provider/operation/attempt identifiers) fail at construction;
- concurrent many-payout allocation;
- restart with UNKNOWN/pending owner.

### H — Replay and durable restart

Replay and restart are different tests.

Replay test:

`facts -> read projection` equals live supported projection.

Restart test:

`durable state -> fresh working application/coordinator -> continue commands safely`.

At least one durable continuation regression must cross an actual fresh Ruby
process, not only instantiate a second coordinator in the original process;
the child must restore the durable policy/provider state it needs rather than
receiving the original runtime catalog as an implicit shortcut. The parent must
also reopen the journal after the child exits and verify the terminal facts.

Required restart crash points include, when durability exists:

- after decision/reservation before provider dispatch;
- after provider may have accepted but before response persisted;
- after UNKNOWN persisted;
- after safe release before fallback;
- after settlement before acknowledgement;
- during reconciliation state.

A fresh process must not gain permission to start another provider solely because volatile ownership was lost.

Replay corruption tests must also remove the lifecycle phase transition paired
with an applied pending/unknown observation, including an observation that
arrives after a resolution decision. Restore must reject the resulting
action/outcome/phase mismatch rather than exposing a misleading in-flight
state that suppresses safe recovery.

Durable corruption tests must include truncated/invalid records and explicit failure/controlled repair semantics.

### I — Seeded chaos/fault

A deterministic chaos simulator should support scripted/seeded:

- connection failure definitely not sent;
- timeout after possible send;
- provider reject;
- recipient terminal failure;
- delayed success;
- duplicate callback;
- out-of-order callback;
- provider outage/recovery;
- capacity/rate rejection;
- slow/pending outcome;
- late return/reversal.

### J — Performance/load

Correctness comes first.

Maintain fast CI-sized tests separately from heavy load campaigns.

When claiming 10k/100k scale, a dedicated reproducible harness must actually execute that scale and record environment/results. Do not name a 300-payout test “100k”.

Measure:

- decision/allocation throughput;
- coordinator contention;
- replay/restart time;
- memory growth over long histories;
- attempt amplification under degradation;
- analytics cost.

## 4. Invariants

### SAFETY-1

At most one unresolved economic owner per payout.

### SAFETY-2

UNKNOWN retains ownership and blocks fresh cross-provider money movement.

### SAFETY-3

Fresh fallback excludes already money-moving attempted providers unless explicit same-provider recovery semantics apply.

### SAFETY-4

Restart does not erase unresolved economic authority.

### ALLOC-1

Primary assignment is exact and deterministic under configured accounting semantics.

### ALLOC-2

Recovery does not pollute primary allocation under `primary_assignment`.

### ALLOC-3

Committed primary work is visible to concurrent decisions.

### ALLOC-4

Optimizer selection remains inside the allocation-admissible set.

### ADMISSION-1

Hard-inadmissible provider cannot be selected by allocation pressure or optimization.

### ADMISSION-2

Concurrent exposure counters conserve reserve/release; time-based rate budget is consumed over time and is not released on payout completion.

### HEALTH-1

Recipient/business failure does not degrade provider operational health.

### RECOVERY-1

Terminal payout failure stops provider hopping.

### EVENT-1

Duplicate observation identity is idempotent; conflicting reuse is an integrity error.

### EVENT-2

Chronology is explicit, not semantic status ranking.

### REPLAY-1

Supported live projections equal replay from ordered facts.

### DURABLE-1

A fresh process can continue unresolved payouts without creating new permissions absent from pre-crash state.

### ANALYTICS-1

Opportunity, primary assignment, attempts and settlement conserve their own definitions without silent double counting.

## 5. Closure testing rule

Testing does not self-authorize `VERSION_COMPLETE`.

Before closure, perform the full protocol in `docs/COMPLETION_POLICY.md`, including source/spec, module cohesion, durability, provider/API boundary, repository cleanup and documentation review.

Old green runs are historical only. Changed code requires current evidence.
