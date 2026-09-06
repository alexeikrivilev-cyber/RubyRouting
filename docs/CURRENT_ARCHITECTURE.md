# Current Architecture — v0.2

This document is the current architecture supplement for **v0.2 — Pre-TZ Comprehensive Routing Core**.

`docs/ARCHITECTURE.md` remains the detailed v0.1 starting architecture and is still valid as the inherited structural baseline. Where this document adds or changes a responsibility for v0.2, this document wins until the official TZ requires another architecture.

## 1. Architecture stance

Do not restart the system.

Keep a plain-Ruby modular monolith with:

- deterministic domain/routing kernel;
- application orchestration/use cases;
- one in-memory atomic coordinator boundary guarded by `Thread::Mutex` for current mutable correctness state;
- provider I/O outside the coordinator lock;
- explicit provider/time boundaries;
- append-preserved typed facts and replayable projections;
- independent Ruby oracle/simulator/test models.

The goal of v0.2 is **fuller domain logic**, not infrastructure expansion.

## 2. Current logical components

The architecture should evolve toward these responsibilities. Exact class/file boundaries may differ.

### Domain / policy values

Own immutable definitions:

- economic intent;
- exact money;
- policy identity/fingerprint;
- allocation policy;
- recovery policy;
- hard constraints plus explicitly advisory soft constraints;
- provider profile/functional constraints;
- operation-scoped provider recovery contract;
- normalized outcomes/observations;
- typed reason/deviation/conflict values.

### Deterministic routing kernel

Own pure decision logic:

- opportunity/functional eligibility;
- static/runtime policy feasibility;
- primary allocation discrepancy;
- live feasible-set filtering from capacity/health/administrative state;
- deterministic ranking inside the feasible envelope;
- recovery action selection;
- legal lifecycle transitions.

### Atomic coordinator

Own the atomic transaction boundary across correctness state. Internally it may delegate to focused ledgers/reducers, but those collaborators remain under one correctness transaction unless evidence earns another model.

Likely internal responsibilities:

- payout/operation registry;
- primary allocation ledger;
- capacity ledger;
- operation/provider-contract state;
- lifecycle reducer;
- fact journal/revision;
- provider opportunity configuration facts needed to replay capacity and health
  projections;
- health projection or a synchronized snapshot of health state where routing correctness depends on it.

### Application orchestration

Own workflow commands, not business math:

- submit/create intent;
- prepare/commit a new route;
- dispatch provider operation;
- classify transport evidence;
- apply provider observation;
- resume/advance unresolved payout;
- reconcile old operation/callback;
- stop/defer/return typed result.

A repeated call to continue an unresolved payout must not masquerade semantically as a new economic intent.

### Provider boundary

Own raw-provider semantics and expose structured domain evidence:

- executable adapter availability;
- initiate using stable operation identity/idempotency key;
- resolve/status lookup for an existing operation;
- definitely-not-sent transport failure;
- ambiguous-after-possible-send transport failure;
- normalized provider observation;
- provider sequence/version only when contractually meaningful.

Provider-specific error strings/statuses never drive core routing directly.

### Projections

Own deterministic read models over facts:

- current payout/operation/ownership state;
- primary allocation state;
- recovery/attempt history;
- settlement/reversal/conflict state;
- decision trace;
- analytics.

Replay must be able to rebuild supported lifecycle state without hidden coordinator-only inputs.

## 3. Decision pipeline

The current intended pipeline is:

`Payout Intent`
→ `Policy identity/fingerprint`
→ `Functional opportunity`
→ `Live availability`
→ `Capacity feasibility`
→ `Health/quarantine feasibility`
→ `Hard business constraints`
→ `Primary allocation pressure / recovery constraints`
→ `Deterministic ranking within admissible choices`
→ `Atomic decision + relevant reservations + ownership + operation contract + dispatch phase`
→ release lock
→ `Provider dispatch`
→ `Transport/provider observation`
→ `Lifecycle reducer`
→ `success | wait/resolve | safe fallback | terminal | reconciliation-blocked | conflict/remediation`

Hard constraints are not blended into a single scalar score.
Soft constraints are advisory in the current pre-TZ core: they never widen the
route beyond hard feasibility or eliminate a safe provider, and any violation
is preserved in typed opportunity/decision facts as `soft_constraint_relaxed`.
The official TZ may later define a different relaxable-objective ordering.

## 4. Atomic commit contract

Before a new money-moving provider call, one coordinator transaction must establish all state that prevents concurrent correctness violations.

For a primary assignment this may include:

- current payout legality;
- current policy fingerprint;
- provider opportunity/live feasibility;
- primary allocation reservation;
- capacity reservation;
- decision/operation/attempt identity;
- economic ownership;
- operation-scoped provider recovery contract;
- operation dispatch phase initialized as committed/not-yet-dispatched;
- typed facts/revision.

For recovery, primary allocation is not mutated under the current `primary_assignment` accounting point.

Provider I/O happens only after the lock is released.

## 5. Dispatch protocol

Ownership acquisition does not mean the request has already reached the provider.

The operation must retain enough phase/evidence to distinguish:

- committed but not dispatched;
- dispatch in progress;
- definitely not sent;
- possibly sent / ambiguous;
- provider observation received;
- pending/unknown unresolved;
- terminal/released.

A duplicate command during original dispatch cannot start status resolution or same-provider retry merely because ownership exists.

Health reads are pure snapshots for unknown providers; provider registration and
operational signals are the explicit state-materialization paths. This prevents a
read-only inspection from creating health state that is absent from the fact log.

## 6. Opportunity versus live feasibility

Do not store all provider routing state in one `feasible?` boolean.

Conceptually:

`Provider Profile + Payout Context -> Opportunity`

then:

`Opportunity + Availability + Capacity + Health + Hard Operational Rules -> Live Feasibility`

Temporary outage/capacity/quarantine does not rewrite historical opportunity or silently reset allocation accounting.

## 7. Allocation and recovery separation

Maintain distinct logical views:

- opportunity;
- primary allocation assignment;
- recovery assignment/attempt;
- settlement.

The allocator is responsible for primary target adherence under the active accounting strategy. Recovery is responsible for safely completing the payout after primary failure.

Under the current primary-assignment default, recovery does not alter primary allocation state.

## 8. Capacity

Capacity is mutable reservable correctness state, not merely a ranking hint.

Generic v0.2 primitives:

- concurrent money-moving slots;
- optional count budget;
- optional amount budget.

Reservation/release semantics must be deterministic and duplicate-safe. `UNKNOWN`/pending may retain capacity while the operation can still produce the monetary effect.

Provider opportunity registration facts preserve budget configuration changes,
including an explicit transition to an unbounded (`nil`) budget, so capacity
replay follows the live projection.

## 9. Health and ranking

Operational health is derived from attributable signals and controls exposure before ranking.

A provider may transition through equivalent states to:

`HEALTHY -> DEGRADED -> QUARANTINED -> PROBING -> HEALTHY`

Health must use hysteresis/minimum evidence and controlled recovery. Recipient-caused failure is not provider-health failure.

Health observations tied to a payout operation do not release a probe slot by
themselves. Operation-owned exposure reservations are keyed by operation and
released exactly once when that operation reaches a safe terminal/released
outcome. Standalone controller reservations and signals use a separate direct
exposure count, so an unrelated health signal cannot release an in-flight
payout probe.

Ranking happens only after hard elimination. A ranker may use configured priority, health/quality, cost or latency when present, but cannot override safety/eligibility/capacity/quarantine.

## 10. Lifecycle reducer and event ordering

Do not order observations by semantic status severity.

Reducer decisions use:

- immutable observation identity;
- operation identity;
- explicit legal transition rules;
- provider sequence/version only if the provider contract guarantees its ordering meaning;
- conservative conflict/reconciliation behavior when chronology is unknowable.

Late observations remain facts even when they cannot replace the current main projection.

## 11. Economic conflict and reversal

Two distinct concepts:

- **return/reversal** — a previously completed economic effect later comes back/is reversed;
- **economic conflict** — evidence indicates more than one provider operation may have produced a payout effect for one economic intent.

Neither is ordinary fallback continuation. Both must remain visible in facts/projections/analytics.

Analytics can project unresolved age for ordinary `pending`/`unknown` states
when the caller supplies an explicit controlled `as_of` timestamp. Without
that reference, only an explicit reconciliation-blocked elapsed value is
reported; the projection never invents wall-clock time.

## 12. Refactoring boundary

`State::Coordinator` can be decomposed internally as responsibilities become concrete, but do not use its size alone to justify:

- microservices;
- database/event-store migration;
- queues/background jobs;
- distributed locking;
- framework introduction.

A refactor is earned when it improves invariant ownership, replayability, deterministic testing or removes meaningful duplicated semantics.

`Routing::Recovery` and recovery decisions in the main decision engine should converge to one authoritative recovery rule set rather than drift.

## 13. Architecture completion check

Before v0.2 closure, verify:

- no provider I/O under coordinator lock;
- no hidden mutable correctness state outside intended owners;
- primary allocation/capacity/ownership commits are atomic where required;
- operation contract survives new-route disablement;
- lifecycle state can be replayed from facts;
- health/capacity cannot be bypassed by allocation/ranking;
- recovery does not mutate primary allocation under current semantics;
- duplicate/out-of-order/late observations are safe and explainable;
- application workflow supports unresolved continuation explicitly;
- no speculative external infrastructure entered the core.
