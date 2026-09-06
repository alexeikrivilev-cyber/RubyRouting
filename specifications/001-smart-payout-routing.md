# Smart payout routing — baseline specification

**ID:** SPEC-001  
**Status:** PRE-TZ BASELINE / ACTIVE FOUNDATION DEVELOPMENT  
**Authority:** provisional until reconciled with the official hackathon TZ  
**Language constraint:** Ruby implementation is mandatory; executable product/reference/simulator/test domain logic is Ruby-only

## 1. Purpose

Build a configurable payout-routing engine that distributes new payout intents across payment providers according to explicit allocation policies, safely reacts to provider failures/non-responses, preserves the complete history of routing decisions and attempts, and exposes analytics that separates intended allocation from actual execution/settlement.

The core problem is not “pick the highest-score PSP”. It is a constrained online decision process with a deterministic financial-safety kernel and an optional adaptive optimization layer.

## 2. Baseline and implementation status

This document fixes domain logic that should survive most reasonable versions of the full TZ. It intentionally does **not** choose a framework, storage technology, API shape, queue, deployment topology, provider SDK, or ML algorithm.

The repository is **not waiting for the full TZ before coding**. Stable/reversible parts of this baseline are being implemented now according to `docs/exec-plans/active/pre-tz-foundation.md` and verified under `docs/TESTING.md`.

Safe pre-TZ implementation includes:

- deterministic Ruby domain/reference model;
- economic-intent/ownership semantics;
- count/volume allocation mechanics with committed work;
- normalized outcomes and recovery actions;
- deterministic provider simulator/fault harness;
- immutable decision/attempt/observation facts and minimal projections;
- property/state/concurrency verification infrastructure.

Unknown external contracts remain replaceable. In particular, do not freeze final API/UI, persistence schema, queue/service topology, provider SDK/transport, judge-specific runtime behavior, or adaptive ML before evidence.

Where the full TZ conflicts with this document, the TZ wins. Reconciliation must be explicit rather than silently changing semantics. A changed provisional rule requires corresponding reference-model/test updates before dependent production behavior is considered reconciled.

## 3. Core domain terms

- **Payout intent** — one business/economic intention to pay a recipient a specific amount. It is not an HTTP request and not a provider attempt.
- **Opportunity** — a provider was eligible to receive a routing assignment for a payout under the governing policy/context.
- **Routing decision / assignment** — the orchestrator selects a provider for a primary or recovery action.
- **Provider attempt** — one orchestrator-level interaction intended to initiate/continue processing through a provider.
- **Provider operation** — the provider-side operation created or observed by an attempt; it can outlive the initiating request.
- **Economic ownership** — the currently unresolved provider operation permitted to create the monetary effect for the payout intent.
- **Settlement outcome** — where/how the economic effect finally completed, failed, remained unresolved, or was later returned/reversed if the provider model includes that lifecycle.
- **Policy epoch** — the version of business policy governing a routing decision.
- **Derived state** — the current interpretation of historical facts/events; later facts may refine it.

## 4. Mandatory safety requirements

### SAFE-001 — one economic intent

One submitted payout represents one economic intent regardless of retries, duplicate deliveries, workers, provider attempts, or callbacks.

### SAFE-002 — effectively-once economic semantics

The system does not promise that every technical call executes exactly once. It must prevent repeated technical execution from intentionally creating multiple accepted monetary effects for the same economic intent, to the extent allowed by provider contracts.

### SAFE-003 — single unresolved economic ownership

At most one unresolved money-moving provider operation may own a payout intent at a time.

Conceptually:

`count(active unresolved economic owners for payout) <= 1`

### SAFE-004 — timeout is not failure

A lost/late response after a provider request is `UNKNOWN` unless the integration contract proves that the operation could not have been accepted. `UNKNOWN` does not release economic ownership.

### SAFE-005 — cross-provider fallback requires safe release

A new money-moving attempt at provider B may start only after provider A's ownership is safely released or proven incapable of producing the monetary effect. Same-provider idempotent retry/status lookup may be used to resolve A only when the provider contract allows it.

### SAFE-006 — no route is valid

If no safe admissible route exists, defer/`NO_SAFE_ROUTE` is correct. Safety is never relaxed to satisfy allocation, success, latency, cost, or demo expectations.

### SAFE-007 — historical facts are preserved

Routing decisions, attempts, provider observations, and reconciliation observations are historical facts. Current state may be recomputed/refined; past facts are not overwritten to make the lifecycle appear linear.

## 5. Allocation policy model

A percentage alone is insufficient. A complete allocation policy must eventually define, to the extent required by the TZ:

- **scope** — which payouts/opportunities participate;
- **measure** — count (`1`), volume (`amount`), or another explicit measure;
- **accounting point** — primary assignment, attempt, provider acceptance, settlement, or another defined point;
- **window** — policy lifetime, fixed period, rolling window, last N items, etc.;
- **constraints** — targets and/or minimum/maximum quotas;
- **tolerance** — exact/min-discrepancy behavior or an allowed band;
- **priority/relaxation** — hard vs soft constraints and behavior when they become infeasible.

**Provisional default until the TZ says otherwise:** count/volume shares describe **primary assignment allocation**, while actual settlement distribution is reported separately. This assumption must remain isolated and reversible.

The v0.1 in-memory implementation uses the current feasible-provider cohort plus
policy epoch as its provisional allocation window. When that cohort changes, the
allocation projection starts a fresh window; historical opportunity/assignment
facts remain preserved. This prevents a provider outage or ineligibility period
from creating unbounded catch-up debt when the provider returns. The official TZ
may replace this window/accounting rule during explicit reconciliation.

## 6. Opportunity-aware allocation

Eligibility is evaluated before allocation. A provider that could not legally or technically receive a payout should not automatically accrue artificial allocation debt for that payout.

Preserve four conceptually different ledgers/views:

1. **Opportunity** — who could receive it.
2. **Assignment** — who the router selected.
3. **Attempt** — where provider operations were initiated.
4. **Settlement** — where the economic result completed.

These views may share efficient storage later, but their semantics must remain distinguishable.

## 7. Allocation decision rule

For count strategies, the item measure is `1`. For volume strategies, the item measure is the payout amount in an exact monetary representation.

For each admissible provider, reason about the **post-decision** allocation state and select an action that best satisfies hard constraints and minimizes required allocation discrepancy.

Weighted random may be used as optional tie-breaking/exploration, but not as the primary correctness mechanism for maintaining target shares.

### ALLOC-001 — post-decision discrepancy

The allocation controller evaluates how the incoming payout changes policy state if assigned to each feasible provider, rather than choosing solely from current deficits.

### ALLOC-002 — concurrent commitments

Allocation calculations include committed/in-flight assignments according to the policy accounting semantics, not only completed payouts. Otherwise concurrent workers can observe the same deficit and stampede an under-target provider.

### ALLOC-003 — indivisible payouts

Large indivisible payouts can make perfect ratios mathematically impossible. The router chooses the best achievable post-decision state and records/attributes the deviation; this is not automatically a routing failure.

### ALLOC-004 — exact money

Monetary volume must not use binary floating-point arithmetic for correctness.

### ALLOC-005 — assignment must be feasible

A provider assignment may be committed only if the provider is in the safe feasible set at the decision/commit point under the chosen consistency semantics.

## 8. Allocation deviation and debt

Not every deficit is recoverable router debt. Attribute deviation to causes such as:

- router choice inside permitted policy freedom;
- provider ineligibility;
- provider outage/quarantine;
- capacity/limit exhaustion;
- safety/unknown ownership;
- policy conflict/infeasibility;
- recovery/fallback effects.

Do not blindly catch up historical deficit after an outage. Recovery pressure must be bounded by the current policy window and current provider health/capacity. Historical impossibility must not cause a traffic avalanche when a provider returns.

## 9. Policy feasibility

Distinguish:

- **static policy infeasibility** — constraints contradict each other even with all providers available;
- **runtime policy infeasibility** — the policy is valid but current availability/capacity/eligibility makes it impossible.

Hard safety and eligibility constraints are never relaxed. Runtime business deviation must be explicit and attributable.

## 10. Decision precedence

Unless the official TZ establishes another hard precedence, use this conceptual ordering:

1. economic safety;
2. hard functional eligibility;
3. hard administrative/provider limits/capacity;
4. hard business constraints;
5. allocation requirements;
6. operational reliability/health;
7. expected success optimization;
8. cost/latency if present;
9. exploration/learning if present.

Do not collapse hard constraints and soft objectives into one weighted score where a cheap/healthy provider can mathematically “compensate” for a forbidden route.

## 11. Decision pipeline

The baseline routing lifecycle is:

`Payout Intent`
→ `Economic Safety Gate`
→ `Policy Resolution`
→ `Opportunity / Hard Eligibility`
→ `Live Availability & Capacity`
→ `Policy Feasibility / Allocation Controller`
→ `Feasible Providers`
→ `Reliability Optimization`
→ `Decision Commit`
→ `Economic Ownership`
→ `Provider Attempt`
→ `Normalized Outcome + Attribution`
→ `Success | Safe Recovery | Resolve UNKNOWN/PENDING | Defer/Reconcile`

Provider ranking happens late, after unsafe/impossible actions have been removed.

## 12. Reliability model

Keep two concepts separate.

### Operational health — fast loop

May use availability, transport errors, timeouts, latency/congestion, hard capacity signals, or other immediate operational evidence.

### Quality estimate — slow/mature loop

Should use sufficiently mature, provider-attributable terminal outcomes and confidence rather than a raw mixed failure rate.

A provider can be historically excellent but currently unavailable. A few recipient-caused failures must not make a healthy provider look broken.

Conceptual exposure states such as `HEALTHY`, `DEGRADED`, `QUARANTINED`, `PROBING`, bounded traffic shifts, and confidence-aware ranking are optional extensions if the TZ/data justify them. Prefer fast fail-down and gradual ramp-up if adaptive health is implemented.

Adaptive bandit/ML ranking is **not** correctness-critical core.

## 13. Outcome normalization and attribution

Provider-specific codes must be normalized into a small decision-oriented semantic taxonomy capable of representing:

- `SUCCESS`;
- `PENDING` / accepted but non-terminal;
- `UNKNOWN` / outcome cannot be determined from the initiating exchange;
- terminal payout/recipient failure (another provider cannot fix the business problem);
- safe route failure (another route may help);
- temporary provider failure (same/other provider may help after safety/policy checks).

Separately attribute the signal where possible: recipient/payout, provider, downstream bank/rail, policy/configuration, or unknown.

One provider attempt can therefore emit at least two conceptual results:

- the **business outcome** of the attempt;
- the **reliability signal** used to evaluate provider/route quality.

Do not increment provider-failure quality statistics for errors clearly caused by invalid recipient data or another non-provider cause.

## 14. Recovery controller

Retry, fallback, resolve, defer, and reconciliation are distinct actions.

### REC-001 — same-provider retry

Allowed only when provider semantics/idempotency make it safe.

### REC-002 — cross-provider fallback

Allowed only after economic ownership is released.

### REC-003 — status resolution

Use provider-safe status lookup, idempotent same-provider retry, callback, or reconciliation to resolve `UNKNOWN`/long `PENDING` when supported.

### REC-004 — reroute, do not walk a stale list

Do not permanently precompute `A -> B -> C` and blindly walk it. After a safe failure, make a **new routing decision** using fresh availability/capacity and the normalized failure reason. A fallback candidate can become invalid between attempts.

### REC-005 — bounded recovery

Fallback is not infinite. The confirmed TZ should define or permit attempt/time/provider-switch budgets. Avoid retry storms and pointless cascades. A simple fixed policy is preferable to an elaborate expected-value engine unless evidence requires more.

### REC-006 — terminal payout failure stops route hopping

A failure classified as recipient/payout terminal must not trigger provider fallback merely because another provider exists.

## 15. Provider integration contract

Each real/simulated provider adapter should make relevant semantics explicit:

- idempotency guarantee and TTL;
- request/reference identity;
- status lookup capability;
- terminal/pending/unknown states;
- safe retry conditions;
- callback/event semantics;
- cancellation/reversal semantics if applicable.

Provider-specific behavior should be normalized at the boundary so the financial core remains provider-agnostic.

The pre-TZ deterministic provider simulator is a verification tool, not the final provider API contract.

## 16. Event and state semantics

Assume callbacks/events can be duplicated, delayed, or out of order unless a confirmed provider contract guarantees otherwise.

Provider events/attempt observations are facts. Current payout state is derived from those facts rather than destructively rewriting history.

A provider-level success may not always be economically final if later return/reversal is possible. Preserve the ability to model this if the TZ includes it, but do not invent an elaborate settlement state machine when the judge does not.

Duplicate observations must not double-apply logical settlement/health/accounting effects.
An `observation_id` identifies one immutable observation payload: an exact replay is
idempotent, while reuse with different operation linkage or normalized outcome is
rejected as an integrity error.

## 17. Decision trace and explainability

For each routing decision, the system should be able to explain, at a level appropriate to the TZ:

- governing policy/epoch;
- eligible candidates;
- material exclusions and reasons;
- allocation pressure/deviation relevant to the choice;
- health/capacity restrictions relevant to the choice;
- selected provider and primary/recovery role;
- previous normalized outcome that triggered rerouting.

This is a domain capability, not a requirement to emit verbose debug logs everywhere.

## 18. Analytics baseline

Keep **policy correctness** separate from **execution quality**.

### Allocation / policy

- configured target;
- actual primary assignment share by configured measure;
- effective settlement distribution;
- deviation from target and deviation attribution;
- static/runtime infeasibility or no-route counts.

### Reliability / recovery

- first-attempt success rate;
- eventual success rate;
- fallback recovery contribution;
- terminal failure rate;
- pending/unknown count and age;
- attempts per payout / attempt amplification;
- provider-attributable vs recipient/downstream failures;
- provider performance by primary/fallback position if useful.

Implement only the subset required/valuable under the TZ, but never collapse assignment and settlement semantics into one ambiguous provider field.

## 19. Verification requirements

Detailed test methodology lives in `docs/TESTING.md`; the following are normative project quality requirements for any implemented behavior.

### VER-001 — requirement traceability

Every implemented normative requirement/acceptance scenario has executable evidence. Line coverage alone does not satisfy this requirement.

### VER-002 — independent oracle for algorithmic correctness

Allocation/recovery behavior that benefits from an oracle is checked against a structurally independent Ruby reference model or independently calculated expected state. Tests must not use the production helper as their sole expected-value implementation.

### VER-003 — combinatorial/stateful verification

Safety/allocation/recovery code is tested beyond hand-written examples using invariant/property and/or model/state-machine sequences appropriate to the implemented scope.

### VER-004 — controlled concurrency verification

Concurrency-sensitive invariants such as single economic ownership and committed allocation visibility are tested with controlled races/interleavings, not only opportunistic stress.

### VER-005 — deterministic fault simulation

Provider timeout/pending/safe-failure/duplicate/delayed/out-of-order behavior can be reproduced deterministically without live money-moving services or real sleeps in core tests.

### VER-006 — regressions are permanent evidence

A material bug discovered by example, property, model, concurrency, fault, or demo testing gains a deterministic regression test. Flaky reruns do not count as a fix.

## 20. Acceptance scenarios

Any implementation claiming the corresponding behavior must prove it with deterministic tests/examples and the broader verification layers required by `docs/TESTING.md`.

### AC-001 — count allocation
Count-based allocation follows target shares with minimal achievable discrepancy across a sequence under the configured policy semantics.

### AC-002 — volume allocation
Volume-based allocation uses exact payout amounts rather than request count.

### AC-003 — large indivisible payout
A payout too large for exact proportions chooses the least-bad feasible post-decision allocation rather than failing or pretending exactness.

### AC-004 — concurrent commitments
Concurrent/in-flight assignments prevent many decisions from all selecting the same apparently under-target provider.

### AC-005 — opportunity denominator
A provider that is ineligible for a payout does not automatically accrue artificial catch-up debt for that payout.

### AC-006 — safe failure reroute
Provider A returns a confirmed safe route failure; ownership is released and the next provider is recomputed from fresh candidates.

### AC-007 — unknown timeout safety
Provider A can have accepted the request but the response times out; provider B is not started until A is resolved safely.

### AC-008 — duplicate economic intent
Duplicate/replayed submission does not create a second accepted economic effect for the same payout intent.

### AC-009 — outcome attribution
Recipient-caused failure does not degrade provider-attributable quality statistics.

### AC-010 — runtime infeasibility
Provider outage can make an otherwise valid allocation policy temporarily infeasible without violating safety; deviation reason is visible.

### AC-011 — bounded recovery pressure
A recovered provider does not instantly receive unlimited historical catch-up traffic solely because it was unavailable.

### AC-012 — no route
All providers unavailable/unsafe produces a safe no-route/defer outcome.

### AC-013 — policy epoch
A policy change creates a new epoch; old routing history is not reinterpreted as if the new policy always applied.

### AC-014 — duplicate/out-of-order facts
Duplicate/out-of-order provider facts do not corrupt the derived payout lifecycle or double-apply logical effects.

### AC-015 — primary vs settlement
After safe fallback, primary assignment and settlement provider may legitimately differ and analytics preserve both.

### AC-016 — terminal payout failure
A normalized terminal recipient/payout failure stops provider hopping; another provider is not attempted merely because one is available.

### AC-017 — replay stability
Rebuilding derived state/analytics from the same applicable historical facts produces the same result.

## 21. Non-goals before the official TZ

Do not commit the project to the following without confirmed need:

- Rails/Sinatra/Hanami or another web framework;
- a production database/persistence technology;
- queues/event buses/background workers;
- microservices/distributed consensus;
- final public API/UI/storage contract;
- ML/RL/contextual or non-stationary bandits;
- automatic correlated failure-domain inference;
- counterfactual/off-policy simulators;
- custom observability infrastructure.

These are non-goals for **external architecture**, not a prohibition on implementing the stable Ruby core/test harness before TZ.

The exact Ruby judge/runtime/version/dependency rules remain a TZ question, but the language itself is not provisional: implementation is Ruby.

## 22. Full-TZ reconciliation protocol

When the official TZ arrives, compare each relevant baseline requirement and mark it:

- `CONFIRMED` — same semantics;
- `CHANGED` — TZ defines different semantics;
- `REMOVED` — outside actual scope;
- `NEW` — TZ adds a missing rule/constraint;
- `AMBIGUOUS` — still needs a decision/clarification.

Then:

1. update this specification;
2. update reference model/oracles and executable acceptance tests for changed semantics;
3. adapt dependent pre-TZ production code;
4. select newly justified external architecture/integration choices;
5. turn official load/scoring constraints into explicit quality/performance gates.

Do not wait for this reconciliation to build stable/reversible foundation work, and do not discard working pre-TZ code unless a confirmed requirement invalidates it.

## 23. Research grounding

The baseline was informed by production payment/payout orchestration, distributed-systems practice, online allocation research, and stateful/concurrency testing practice. References are evidence, not project requirements. See `docs/RESEARCH.md`.

The official hackathon TZ is authoritative over conflicting provisional behavior.
