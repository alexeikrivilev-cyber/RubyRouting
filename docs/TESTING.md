# Testing Strategy

This document defines how RubyRouting proves correctness for the current **v0.2 — Pre-TZ Comprehensive Routing Core**.

Behavior is governed by SPEC-001, SPEC-002 and SPEC-003. `docs/COMPLETION_POLICY.md` governs whether test evidence is sufficient for a version-complete claim.

The goal is not maximum line coverage. The goal is evidence that payout routing preserves safety, allocation correctness, recovery semantics, replayability and causal analytics across normal, boundary, concurrent, delayed, duplicated, reordered and degraded execution.

## 1. Green tests are not completeness proof

A green suite is necessary but never sufficient to declare the version complete.

It proves only behavior represented by current tests. Version closure also requires source/spec reconciliation, full capability-matrix sweep, repository discovery, adversarial review, backlog audit and documentation consistency.

Test counts, assertion counts and coverage are evidence, not the definition of done.

## 2. Ruby-only test policy

Production implementation, routing algorithms, reference/oracle models, simulators, property generators, state-machine models, concurrency harnesses and executable domain tests are Ruby-only.

Minimal CI/shell/YAML orchestration is allowed. Do not create a second router/oracle in another language.

## 3. Verification objectives

The test system must prove, as applicable:

1. **Economic safety** — one intent cannot accidentally create multiple independent monetary effects.
2. **Dispatch safety** — committed, dispatching, definitely-not-sent, ambiguous and observed operation states are distinguished.
3. **Allocation correctness** — count/volume policies follow explicit scope/accounting/window/tolerance/constraints using exact arithmetic and committed work.
4. **Policy correctness** — identity/fingerprint/epoch and static/runtime feasibility cannot silently change meaning.
5. **Eligibility correctness** — functional opportunity is context-aware and separate from live feasibility.
6. **Capacity correctness** — reservations are atomic, bounded and duplicate-safe.
7. **Health correctness** — only attributable signals change provider exposure; hysteresis/probing prevents flapping/recovery stampede.
8. **Ranking correctness** — ranking operates only inside the safe feasible set.
9. **Recovery correctness** — retry, resolve, fallback, defer, reconciliation and terminal stop obey operation contracts/budgets/time.
10. **Event correctness** — duplicate/delayed/out-of-order observations do not corrupt state or invent chronology.
11. **Settlement correctness** — settlement, reversal/return and economic conflict are distinct.
12. **Replay correctness** — facts rebuild supported lifecycle/ownership/settlement/conflict state deterministically.
13. **Analytics correctness** — primary/recovery/settlement/deviation/attribution metrics are conserved and typed.
14. **Concurrency correctness** — critical histories are equivalent to legal sequential behavior for required invariants.
15. **Performance fitness** — measured after correctness; official gates only after TZ provides limits.

## 4. Test architecture

### 4.1 Production system under test

Prefer domain/application boundaries over private-method tests when observable behavior can be exercised directly.

### 4.2 Independent reference/oracle model

Maintain a deliberately simple Ruby reference model for semantics that benefit from an oracle:

- allocation discrepancy/constraints;
- ownership and operation legality;
- recovery action legality;
- capacity conservation;
- health transition baseline where useful;
- lifecycle replay/projection invariants.

The oracle must not call the production algorithm it verifies.

### 4.3 Deterministic provider simulator

The simulator must support scripted behavior including:

- immediate success;
- safe route/provider failure;
- terminal recipient/payout failure;
- definitely-not-sent transport failure;
- ambiguous-after-send timeout -> UNKNOWN;
- PENDING -> success/failure;
- long unresolved pending;
- delayed success after timeout;
- duplicate callbacks;
- delayed/out-of-order observations;
- authoritative sequence/version where configured;
- malformed/unknown provider response;
- temporary provider unavailable/rate-limited/capacity constrained;
- same-provider idempotent retry;
- status lookup;
- provider disablement after operation creation;
- success followed by return/reversal;
- late old-operation success after fallback/new settlement.

Time, IDs, ordering and random choices must be controllable.

### 4.4 Controlled time

Core tests must not depend on real `sleep`.

Use injectable/controlled time for:

- deadlines;
- pending age;
- idempotency/status TTL;
- health windows/cooldowns;
- probing/recovery exposure;
- allocation windows where time-based semantics are configured.

### 4.5 Reproducible randomness

Deterministic core routing should not require randomness. Generated/property tests use explicit seeds and report them. Material failures become deterministic regressions.

## 5. Verification layers

### Layer A — value/unit tests

Use for:

- Money;
- policy fingerprint/validation;
- exact discrepancy;
- provider constraints;
- capacity arithmetic;
- normalized outcome/transport classification;
- health state predicates;
- typed reason/deviation values.

### Layer B — deterministic acceptance/regression tests

Every implemented normative requirement has executable evidence. Critical safety rules need positive and negative cases.

Every material bug gets a deterministic regression before/with the fix where practical.

### Layer C — property/invariant tests

Generate many valid policies, provider sets, amounts, availability/capacity/health states and histories.

Important properties:

- selected provider is functionally/live feasible;
- one unresolved economic owner;
- UNKNOWN retains ownership;
- fresh fallback excludes attempted money-moving providers;
- primary recovery accounting conservation;
- allocation choice is oracle-optimal within hard constraints;
- capacity never negative/leaked;
- recipient failure does not degrade provider health;
- ranking never resurrects hard-excluded provider;
- duplicate observations are idempotent;
- replay equals live supported projection;
- analytics conservation.

### Layer D — state-machine/model tests

Generate long command/event histories across:

- create/submit intent;
- primary route;
- dispatch begin/evidence;
- provider success/failure/pending/unknown;
- resolve/status lookup;
- same-provider retry;
- safe fallback;
- provider enable/disable;
- capacity changes;
- health transitions;
- policy epoch/fingerprint changes;
- duplicate command;
- delayed/out-of-order observation;
- reconciliation;
- return/reversal;
- replay.

Compare expected state/actions/invariants after every step.

### Layer E — controlled concurrency/interleaving

Force races with barriers/hooks rather than hoping stress finds them.

Required race families:

- two workers acquire owner for same payout;
- duplicate submit while dispatch is blocked;
- two primary allocations consume same deficit;
- two capacity reservations compete for last slot/budget;
- safe release versus fallback worker;
- UNKNOWN/callback versus fallback/recovery decision;
- reconciliation versus status resolution;
- provider live-state update versus decision commit;
- policy epoch/fingerprint update versus decision commit where supported.

### Layer F — provider contract tests

For each provider/simulator adapter verify:

- idempotency identity;
- status lookup;
- TTL/expiry when modeled;
- definitely-not-sent versus ambiguous transport;
- terminal versus non-terminal status;
- normalized attribution;
- duplicate/out-of-order behavior;
- unknown raw state conservative handling.

### Layer G — end-to-end fault scenarios

Exercise full flow from intent through route/dispatch/observation/recovery/reconciliation/analytics.

High-value combinations:

- A UNKNOWN while B healthy -> B cannot start;
- A safe-fails, B goes unavailable, C succeeds;
- A safe-fails under skewed 90/10 allocation -> fresh A operation forbidden;
- fallback occurs but primary allocation state is unchanged;
- provider disabled after unresolved operation -> old operation still resolves;
- missing adapter -> no money-moving commit;
- large volume during partial outage/capacity pressure;
- allocation pressure cannot override quarantine;
- capacity last-slot race;
- UNKNOWN + duplicate submit + idempotency TTL boundary;
- fallback + late old-provider success -> economic conflict;
- settlement -> reversal -> replay/analytics;
- policy change during concurrent primary decisions;
- health recovery with bounded probing and allocation deviation.

### Layer H — replay verification

For every complex scenario, compare:

- live coordinator/application projection;
- projection rebuilt from immutable facts.

No hidden mutable state may be required for a capability claimed replayable.

### Layer I — stress/performance

Before TZ, record baselines without inventing acceptance limits. Measure relevant paths:

- allocation/decision throughput;
- lifecycle/replay cost;
- memory growth over long histories;
- high concurrency correctness;
- attempt amplification under degradation;
- health/fallback recovery behavior.

Correctness failure always fails the test regardless of throughput.

### Layer J — mutation/fault seeding

Use targeted fault seeding to prove critical tests can detect regressions such as:

- release owner on UNKNOWN;
- recovery advances primary allocation;
- fallback reuses failed provider;
- ignore committed allocation/capacity reservation;
- recipient failure degrades provider health;
- ranking bypasses quarantine;
- use status rank as chronology;
- duplicate callback double-counts settlement;
- stale old success silently ignored;
- replay omits hidden coordinator state;
- Float money.

No universal mutation-score target is required.

## 6. Reusable invariant catalog

### SAFETY-P1 — single unresolved owner

`active_unresolved_economic_owners <= 1` for every payout history.

### SAFETY-P2 — UNKNOWN retains ownership

No cross-provider money-moving operation while prior operation may still pay.

### SAFETY-P3 — duplicate intent/effect

Replaying the same economic intent does not create a second logical payout/economic ownership.

### SAFETY-P4 — dispatch phase safety

Committed/dispatching operation is not automatically eligible for resolve/retry until operation evidence permits it.

### SAFETY-P5 — late conflict visible

If an old released operation later indicates a possible effect after newer operation/settlement, conflict is preserved and surfaced.

### ALLOC-P1 — selected provider is admissible

Every primary/recovery assignment satisfies the hard envelope for that action.

### ALLOC-P2 — local allocation optimality

Within allowed allocation choices, selected post-decision discrepancy is no worse than alternatives unless an explicit higher-priority hard/tolerance rule defines the admissible band.

### ALLOC-P3 — committed primary work visible

Concurrent primary decisions see committed reservations.

### ALLOC-P4 — recovery does not pollute primary ledger

Under `primary_assignment`, fallback/recovery contributes zero to primary allocation accounting.

### ALLOC-P5 — opportunity correctness

Functional ineligibility does not create ordinary router-choice debt; temporary live infeasibility is represented as deviation rather than erased history.

### ALLOC-P6 — exact money

No Float may change volume routing correctness.

### POLICY-P1 — immutable definition

Same policy identity/epoch/scope cannot refer to two material definitions.

### CAP-P1 — conservation

Reserved + available/consumed capacity equals configured capacity semantics; duplicates/late events cannot over-release or double-consume.

### HEALTH-P1 — attribution correctness

Recipient/payout-attributable failures are neutral to provider operational health.

### HEALTH-P2 — hard exposure

Quarantined/provider-hard-excluded state cannot be overridden by allocation or ranking.

### REC-P1 — terminal payout failure stops hopping

Recipient/business terminal failure does not start another provider solely because one exists.

### REC-P2 — fresh fallback

Fallback is a fresh current decision, excludes previously attempted providers by default and rechecks capacity/health.

### REC-P3 — bounded recovery

Money-moving/switch/resolution budgets and deadline/TTL semantics prevent unbounded cascades.

### EVT-P1 — duplicate identity idempotent

Exact duplicate observation cannot double-apply state/settlement/health/accounting.

### EVT-P2 — chronology is explicit

No transition depends on arbitrary semantic status ranking.

### REPLAY-P1 — replay equivalence

Applying the same ordered fact set to a fresh projection yields the same supported lifecycle/analytics state.

### ANALYTICS-P1 — conservation and separation

Primary allocation, recovery attempts and settlement each conserve their own defined measure without silent double counting.

## 7. Scenario-space matrix

Generate/systematically cover these axes:

- provider count: 0/1/2/3+/many;
- allocation: count/volume;
- target shape: equal/skewed/tiny/dominant/min/max/tolerance;
- amount: minimum/ordinary/boundary/large-indivisible;
- functional opportunity: all/subset/one/none;
- live state: healthy/degraded/quarantined/unavailable/capacity-limited;
- operation phase: committed/dispatching/unknown/pending/terminal;
- primary outcome: success/safe failure/terminal/pending/unknown;
- delivery: in-order/duplicate/delayed/out-of-order;
- recovery position: primary/first fallback/deeper/budget edge;
- policy: valid/runtime-infeasible/conflicting identity/epoch change;
- allocation history: balanced/under/over/outage deviation;
- capacity: free/last slot/exhausted/budget boundary;
- contract: idempotent/status lookup/TTL expiry/no resolution;
- concurrency: single/two-way/high fan-out;
- settlement: success/return/reversal/conflict.

Property/model tests cover the product space; known dangerous combinations require explicit regressions.

## 8. Slice verification rule

A slice may be marked `SLICE_VERIFIED` only after:

1. focused behavior tests pass;
2. applicable invariant/oracle/model/concurrency evidence passes;
3. the smallest broader suite capable of detecting interaction regression passes;
4. material failure paths are tested;
5. any discovered material bug has a regression.

## 9. Phase verification rule

A phase may be marked `PHASE_VERIFIED` only after its capabilities interact correctly with all prior required phases.

Example: health is not phase-complete if its unit transitions work but allocation pressure can still route into quarantined PSPs.

## 10. Version completion rule

Testing never self-authorizes `VERSION_COMPLETE`.

When all phase evidence is green, follow `docs/COMPLETION_POLICY.md`. Closure can and should add new tests/regressions if the source/spec/red-team sweep finds previously unrepresented gaps.

Never hide flaky behavior with automatic retries. Never report a check as passed if it was not executed on current code.
