# Technical Review — 2026-08-27

## Scope

This review audits `main` at commit `1b09b9b3b0af717e8c9902ed8e46a993b32bfeeb` after the first executable v0.1 implementation. It reviews architecture, financial semantics, Ruby code, concurrency model, test evidence, projections, documentation drift, and the next pre-TZ development direction.

The review is intentionally skeptical. A green suite proves the cases represented by the suite; it is not proof that the current model is complete.

## Executive conclusion

The project is moving in the correct direction. Keep the following foundation:

- plain-Ruby modular monolith;
- exact `Integer` money and `Rational` allocation math;
- deterministic financial kernel;
- explicit economic ownership and `UNKNOWN != failure`;
- provider I/O outside the coordinator lock;
- append-preserved facts plus projections;
- independent Ruby oracle/simulator;
- property/model/concurrency testing;
- no premature Rails/database/queue/ML commitment.

However, the previous conclusion that “v0.1 is complete and only official-TZ reconciliation remains” is too strong. Static review found correctness and modeling gaps that do not depend on the official TZ and therefore should be fixed before waiting.

The next project version is **v0.2 — Pre-TZ Comprehensive Routing Core**. The official TZ becomes v0.3 entry material, not a blocker for current development.

## Verification status of this review

The repository records a successful local v0.1 run: 51 tests / 2,753 assertions, focused seeded property/model/concurrency/fault runs, syntax checks, and baseline benchmarks. That evidence is useful and should be preserved.

This review did not independently execute the repository because the connected GitHub environment exposes source/history rather than a Ruby execution runner. The current GitHub commit has no CI status checks. Therefore statements below distinguish static code findings from previously recorded execution evidence.

A v0.2 first slice must rerun the canonical suite in a clean executable environment and should add a minimal CI check if repository/runtime constraints permit it.

## What is already good

### Domain safety direction

`EconomicOwnership`, normalized `UNKNOWN`, and the coordinator-before-I/O protocol correctly model the key payout hazard: a lost response cannot be treated as a confirmed failure. The coordinator commits the decision/ownership before provider I/O and applies observations later under synchronization.

### Allocation math

`Routing::Allocation` uses exact integer/Rational arithmetic and evaluates post-decision discrepancy deterministically. This is preferable to weighted random as the correctness mechanism and gives an independently testable kernel.

### Concurrency baseline

A coarse `Thread::Mutex` is an appropriate first linearizable implementation. It is simple enough to reason about and tests already force concurrent ownership/allocation cases. Provider I/O is verified to occur outside the lock.

### Testing architecture

The split between scenario, property, model, concurrency, reference and simulator support is appropriate. The project has already avoided the common failure mode where production code is its own oracle.

### Project shape

The codebase is still small. No speculative framework, ORM, queue or service topology has been introduced. That is the right tradeoff before the official case contract.

## P0 findings — correctness before feature growth

### P0-1 — recovery assignments currently mutate primary allocation state

`State::Coordinator#commit_assignment` records `allocation_committed` and advances `@allocation_snapshots` for every `:assign`, including `role == :recovery`.

This conflicts with the current provisional policy decision D-006 / SPEC-001: target shares are accounted on **primary assignment**, while fallback/settlement are observed separately.

Impact: a failed primary A followed by fallback B changes the state used for future primary allocation. Recovery traffic can therefore distort the business allocation controller.

Required correction: maintain explicit accounting semantics. Under current default, only primary assignment commits to the primary allocation projection. Recovery assignments remain decision/attempt facts and settlement analytics. The implementation must make the accounting point replaceable for future TZ reconciliation.

### P0-2 — fallback can select the provider that just failed

A safe failure releases ownership and the next call uses the normal allocation candidate set. `DecisionEngine` does not exclude already attempted providers. With skewed weights, A can safely fail and be selected again as a new provider operation at A.

This violates the intended distinction between explicit same-provider retry and cross-provider fallback/re-routing.

Required correction: recovery context carries attempted providers and failure information. A new money-moving fallback excludes already attempted providers by default. Reusing the same provider occurs only through an explicit safe `retry_same`/provider-specific policy.

### P0-3 — recovery capability is read from current route opportunity instead of the operation contract

When unresolved ownership exists, `DecisionEngine` searches the current `opportunities` list for the owner and reads `status_lookup` / `idempotent_retry` there.

If the provider is disabled, removed, or its routing metadata changes after the attempt, status resolution capability can disappear exactly when it is most needed.

Required correction: snapshot the relevant provider-operation recovery contract when ownership is created. Route eligibility/availability affects new routing; it must not erase the ability to resolve an already-created operation.

### P0-4 — operation lifecycle lacks an explicit dispatch phase

Ownership is acquired before provider I/O, which is correct, but the state does not distinguish:

- committed but not dispatched;
- dispatching/request possibly sent;
- observation received;
- unresolved pending/unknown.

A concurrent duplicate `submit` can see ownership before the first provider call completes and may choose status lookup/idempotent retry for an operation that is merely being dispatched.

Required correction: model operation/dispatch phase explicitly. Resolution/retry is permitted only after appropriate provider/transport evidence, not merely because ownership exists.

### P0-5 — transport exceptions are not normalized into economic semantics

`Orchestrator` directly calls `provider.initiate/resolve`. Exceptions escape after ownership/attempt state was committed. The core cannot distinguish a definitely-not-sent local failure from an ambiguous failure after possible transmission.

Required correction: provider transport boundary returns/raises a structured dispatch result. At minimum distinguish:

- `NOT_SENT` / locally proven no provider side effect -> ownership may be safely released;
- `AMBIGUOUS_AFTER_SEND` -> `UNKNOWN`, ownership retained;
- normalized provider observation -> apply normally.

A missing provider adapter must be detected before a money-moving ownership commit, not after it.

### P0-6 — arbitrary outcome ranking is not a correct event ordering model

`Coordinator#outcome_rank` imposes `pending < unknown < route failure < terminal < success`. `ProviderObservation#sequence` and `observed_at` are not used.

This guesses chronology from semantic severity. It can discard a legitimate later observation because its status has a lower artificial rank, and it cannot model provider-specific ordering guarantees or later returns/reversals.

Required correction: lifecycle reduction must use explicit transition legality and, where available, provider sequence/version information. Unknown ordering should be conservative and preserve facts; it should not be “solved” by an arbitrary status rank.

### P0-7 — late contradictory economic success is silently ignored

Observations from an old released operation are preserved with `applied: false`. This prevents state corruption, but a late `SUCCESS` from provider A after fallback B succeeded is not merely stale noise: it can indicate two economic effects.

Required correction: preserve current payout correctness state but emit an explicit economic-conflict/invariant-breach fact/projection requiring reconciliation. Never silently treat a possible duplicate economic effect as an irrelevant old callback.

### P0-8 — facts cannot fully rebuild current payout lifecycle

`Projections::Replay` currently only rebuilds analytics. The intent fact omits context and facts are not sufficient to deterministically reconstruct all current payout/ownership/operation state.

Required correction: implement a lifecycle reducer/projector from append-preserved facts. Persist the minimum immutable inputs required to replay payout identity/context, policy identity, operation contract, decisions, observations, ownership and settlement.

## P1 findings — policy and routing completeness

### P1-1 — opportunity and live feasibility are conflated

The current allocation projection resets whenever the **feasible-provider cohort** changes. Feasibility includes availability/capacity, so a temporary outage silently starts a fresh allocation window.

This hides runtime policy deviation rather than attributing it. It also conflates “provider could never receive this payout” with “provider should have received traffic but is temporarily down”.

Required correction:

- **opportunity** = functionally eligible under payout/policy context;
- **live feasibility** = opportunity plus current availability/capacity/health/hard operational constraints;
- policy denominator/window must not silently reset on transient availability changes;
- outage/capacity deviation is explicit;
- any catch-up/debt is bounded by policy, never unlimited.

D-018 is superseded by the v0.2 rule in SPEC-002/D-025.

### P1-2 — provider eligibility is too global

`ProviderOpportunity` is currently a precomputed boolean structure. It does not yet express provider support by currency, amount, recipient/payment context or configurable constraints.

Required correction: introduce a small provider profile/constraint model and evaluate eligibility against each `PayoutIntent`. Keep this deterministic and data-driven rather than adding a rules DSL prematurely.

### P1-3 — policy definition is too narrow and not pinned strongly enough

`RoutingPolicy` currently supports weights, count/volume, one accounting point/window and max attempts. The same `id/epoch/scope` can theoretically be reused with a different definition while sharing allocation state.

Required correction:

- immutable policy definition/fingerprint;
- pin the governing policy definition to the payout/decision history;
- static validation;
- separate allocation policy from recovery budgets;
- support target/min/max/tolerance/hard-vs-soft semantics only through explicit, testable structures;
- reject conflicting reuse of a policy identity.

### P1-4 — capacity is only a boolean

Current `capacity_available` cannot represent concurrent slots, TPS-like budgets, count/amount quotas or reservations.

Required correction: build a deterministic capacity ledger/reservation model independent of final persistence. New/fallback decisions consume/release capacity atomically where required.

### P1-5 — no operational-health controller yet

The spec already distinguishes fast health from slower quality. Current code only has manual availability booleans.

Required correction before TZ: implement a deterministic health baseline with attributable signals, minimum evidence, hysteresis, degradation/quarantine/probing and controlled ramp-up. Keep adaptive ML/bandits optional.

## P1 findings — recovery/lifecycle completeness

- Separate money-moving attempt budget, provider-switch budget, resolution interaction budget, and optional elapsed deadline instead of overloading `max_attempts`.
- Add explicit deferred/resume/reconcile use case instead of overloading repeated `submit` calls as both initial command and continuation.
- Model idempotency/status-lookup validity/TTL in the operation contract.
- Add normalized reason code/failure scope/retry-after data where useful.
- Support returned/reversed post-settlement facts in the simulator/projector without turning them into ordinary fallback continuation.

## P1 findings — analytics and explainability

Current analytics are useful but some names/semantics are inaccurate:

- `fallback_recovery_count` increments on recovery allocation, not successful recovery;
- `no_safe_route_count` depends on parsing a human-readable reason string;
- no typed deviation attribution;
- no unresolved age buckets;
- no attempt amplification / provider metrics by attempt position;
- no explicit economic-conflict metric;
- primary allocation control state is currently polluted by recovery assignments.

Required correction: decision/reason codes should be structured values; analytics consume typed facts rather than strings.

## Code quality review

### Strengths

- explicit value validation and freezing;
- exact monetary arithmetic;
- deterministic ordering;
- small dependency surface;
- useful boundaries (`domain`, `routing`, `application`, `state`, `ports`, `projections`);
- provider I/O separated from atomic state mutation;
- tests are readable and scenario names describe business semantics.

### Risks / refactoring targets

`State::Coordinator` has grown to roughly 19.5 KB and owns too many responsibilities: mutable state store, fact journal, allocation projection, lifecycle reduction, observation deduplication, ID generation and decision commit. Do not split it into services, but introduce internal collaborators/objects as v0.2 mechanics demand it. Keep one atomic coordinator boundary while reducing conceptual load.

`Routing::Recovery` and recovery logic inside `DecisionEngine` currently duplicate concepts. Choose one source of recovery decision semantics and make the other delegate/use it; two independently evolving recovery engines are a future drift risk.

`Replay` is currently only an analytics alias. Rename/expand it only after a real lifecycle replay reducer exists; do not let the name imply evidence not present.

## Test review

Current test organization is strong, but coverage depth is narrower than the documentation implied. Add explicit regressions for at least:

1. fallback does not mutate primary allocation state;
2. failed provider is excluded from fresh fallback;
3. owner resolution survives provider disable/removal;
4. duplicate submit while the first provider call is in-flight does not start resolve/retry;
5. adapter missing before commit;
6. definitely-not-sent vs ambiguous transport error;
7. policy definition collision / policy change mid-payout;
8. live availability changes do not erase allocation history;
9. capacity reservation races;
10. callback/reconciliation vs fallback race;
11. ordered and unordered observations;
12. old-provider late success after fallback emits economic conflict;
13. full lifecycle replay from facts;
14. return/reversal after prior success;
15. health hysteresis/probing and recipient failure not degrading provider;
16. recovery budgets/deadline boundaries;
17. primary vs recovery analytics conservation.

Property/model testing should grow from isolated allocation/ownership loops into generated end-to-end histories covering policy, operation phase, observations, fallback, capacity and reconciliation.

## Documentation contradictions found

The following statements are no longer valid and are corrected by the v0.2 documentation set:

- “v0.1 closure means remaining work is only official-TZ reconciliation”;
- backlog with all pre-TZ work marked completed;
- roadmap where v0.2 requires the official TZ;
- D-018 treating transient feasible-provider cohort as an allocation-window reset;
- active ExecPlan instructing the agent not to reopen the pre-TZ kernel.

The official TZ is still unavailable. No document may pretend it is known. The correct approach is to implement generic high-value mechanics now, isolate provisional semantics, and reconcile later.

## Recommended current direction

Keep the architecture. Do not start over.

Move to **v0.2 — Pre-TZ Comprehensive Routing Core** in this order:

1. repair P0 safety/accounting/lifecycle gaps;
2. separate opportunity, live feasibility, primary allocation and recovery accounting;
3. generalize policy/provider constraints without a speculative DSL;
4. add capacity reservations and deterministic operational health;
5. harden recovery/time/idempotency semantics;
6. make fact replay and economic-conflict reconciliation real;
7. expand typed decision traces and causal analytics;
8. deepen state-machine/concurrency/fault tests and CI evidence;
9. only then consider optional adaptive success ranking, and only behind the deterministic feasible-action envelope.

This gives the official TZ a mature engine to configure/adapt rather than a prototype that still needs financial-semantics repair.
