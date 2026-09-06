# Architecture

This document defines the **concrete starting architecture for v0.1** of RubyRouting. It is no longer only a list of logical boundaries: coding may begin against this structure immediately.

The architecture is intentionally concrete where correctness and testability benefit from an early decision, and intentionally replaceable where the official hackathon TZ is still unknown.

Read together with:

- `specifications/001-smart-payout-routing.md` — behavioral source of truth;
- `docs/RUBY.md` — Ruby 4.0 engineering baseline;
- `docs/TESTING.md` — required verification methods;
- `docs/ROADMAP.md` and the active ExecPlan — implementation sequencing.

If the official TZ later contradicts an external-architecture choice, adapt the shell while preserving the financial kernel and its tests wherever possible.

## 1. Architecture decision in one sentence

v0.1 is a **plain-Ruby modular monolith using ports/adapters around a deterministic financial kernel, with an application orchestrator and a single in-memory atomic coordinator guarded by `Thread::Mutex`; provider I/O is always outside the critical section**.

This is the default implementation architecture. Do not replace it with Rails, microservices, event sourcing, Ractors, a database, queues, or a framework unless a confirmed requirement or measured limitation earns that change.

## 2. Why this architecture

The current case has two difficult correctness problems and many still-unknown external details.

Known difficult problems:

1. economic ownership/recovery — a timeout may leave an unresolved external money-moving operation;
2. proportional allocation under concurrency — simultaneous decisions must observe committed traffic strongly enough to avoid stale-deficit stampedes.

Unknown details:

- final API/UI;
- persistence/restart contract;
- provider/judge interface;
- exact runtime limits;
- exact allocation accounting/window semantics;
- whether adaptive routing is scored.

A modular monolith lets us prove the known hard rules with the fewest moving parts. Ports/adapters keep unknown external contracts replaceable. A deliberately coarse in-memory coordinator gives us a simple linearizable reference implementation for concurrency before a final database/coordination mechanism is justified.

The architecture optimizes first for **correctness, explainability, deterministic testing, and reversibility**.

## 3. System shape

Conceptually:

```text
                  Entrypoint / tests / future API
                            |
                            v
                  Application Orchestrator
                            |
              +-------------+-------------+
              |                           |
              v                           v
      Atomic State Coordinator      Provider Port
              |                           |
              |                    +------+------+
              |                    |             |
              |                 Simulator    future real
              |                              adapter
              v
       Deterministic Kernel
       +------------------+
       | domain values    |
       | eligibility      |
       | allocation       |
       | recovery         |
       | decision engine  |
       +------------------+
              |
              v
        Facts / Projections
              |
              v
        Trace / Analytics
```

The arrows express dependency/authority, not network services.

Everything above is one Ruby process in v0.1.

## 4. Layer responsibilities

### 4.1 Domain values

Pure/immutable domain concepts:

- payout/economic intent identity;
- provider identity;
- exact `Money`;
- currency;
- policy epoch and allocation targets;
- normalized outcome and attribution;
- economic ownership value;
- decision/result/fact values;
- immutable snapshots used by decisions.

These objects do not perform I/O, access clocks directly, acquire locks, or know provider SDK payloads.

Use `Data.define` for simple immutable facts/records and regular classes for invariant-heavy values. Follow `docs/RUBY.md` for shallow-immunity precautions.

### 4.2 Deterministic kernel

Pure or effectively pure business algorithms:

- eligibility filtering over already supplied capabilities/state;
- policy feasibility evaluation;
- count/volume discrepancy calculation;
- deterministic provider selection among feasible candidates;
- recovery action selection from normalized state;
- state transition validation;
- decision explanation generation.

Given the same immutable context, this layer returns the same result.

It does not:

- call providers;
- acquire the state mutex;
- mutate global state;
- read wall clock/global random;
- write logs/database;
- sleep/retry I/O.

### 4.3 Application orchestrator

Coordinates one payout lifecycle step/end-to-end flow.

Responsibilities:

- request a consistent state snapshot/atomic decision commit from the coordinator;
- invoke the provider port after a decision has been committed;
- normalize/process provider observations through the appropriate boundary;
- continue the recovery loop only when the resulting state permits another action;
- stop on success, terminal failure, unresolved `UNKNOWN`/`PENDING`, defer, or exhausted policy/budget;
- preserve traceability across primary and recovery decisions.

It owns **workflow**, not the allocation math or provider-specific semantics.

### 4.4 Atomic state coordinator

The only owner of mutable in-process correctness state in v0.1.

It holds/coordinates:

- payout derived states;
- current economic ownership;
- policy/allocation projection and committed assignments;
- provider operational snapshots supplied to routing where needed;
- append-oriented facts/decision traces;
- projection revisions.

Initial implementation: one coordinator object protected by a coarse `Thread::Mutex`.

This is intentionally simple. The mutex is not a future production architecture commitment. It creates a clear atomicity specification that a later database/transaction/CAS adapter must preserve.

### 4.5 Provider port

A narrow semantic boundary, not a giant universal payment SDK abstraction.

The application layer needs operations such as:

- initiate/continue a provider operation using provider-local idempotency semantics;
- query/resolve an existing operation if supported;
- receive normalized provider capabilities required by recovery;
- translate raw simulator/future provider behavior into normalized observations.

Provider-specific response codes/status shapes never enter the kernel directly.

v0.1 implementation: deterministic Ruby simulator adapter.

### 4.6 Facts/projections

Facts preserve what happened; projections describe current derived interpretation.

Facts include, as needed:

- opportunity set evaluated;
- routing decision/assignment committed;
- provider operation attempt initiated;
- provider observation received;
- normalized outcome/attribution;
- ownership acquired/released;
- settlement/final result;
- reconciliation observation.

This is **not** a commitment to full event sourcing.

The in-memory coordinator may hold both current projections and an append-oriented fact list. The important invariant is that history is not overwritten into one ambiguous `provider_id/status` field.

### 4.7 Analytics projections

Read-only projections over preserved facts/current state:

- opportunity distribution;
- primary assignment distribution;
- attempt distribution;
- settlement distribution;
- first-attempt/eventual success;
- fallback recovery;
- normalized failure attribution;
- allocation deviation and known reason.

Analytics does not mutate routing correctness state.

## 5. Concrete v0.1 Ruby layout

Use this as the initial directory shape. Small adjustments are allowed when implementation evidence supports them, but do not invent parallel architectures.

```text
Gemfile
Rakefile
lib/
  ruby_routing.rb
  ruby_routing/
    domain/
      money.rb
      payout_intent.rb
      policy.rb
      outcome.rb
      ownership.rb
      fact.rb
    routing/
      eligibility.rb
      allocation.rb
      recovery.rb
      decision_engine.rb
    application/
      orchestrator.rb
    state/
      coordinator.rb
      snapshot.rb
    ports/
      provider.rb
      clock.rb
    adapters/
      in_memory/
        coordinator.rb
      system_clock.rb
    projections/
      analytics.rb
      replay.rb

test/
  test_helper.rb
  unit/
  scenario/
  property/
  model/
  concurrency/
  support/
    reference/
    simulator/
    controlled_clock.rb
    synchronization.rb

benchmark/
```

Important notes:

- exact file names may evolve, but dependency direction must not;
- the independent oracle belongs under `test/support/reference`, never `lib/`;
- the deterministic provider simulator starts under `test/support/simulator` because v0.1 uses it as verification infrastructure; promote a reusable simulator component only if demo/runtime use earns that move;
- do not create generic `services/`, `utils/`, or `helpers/` dumping grounds;
- do not mirror each production class with an abstract interface file.

## 6. Dependency direction

The permitted direction is:

```text
domain values
   ^
   |
routing kernel
   ^
   |
application orchestration
   ^               ^
   |               |
state/provider ports
   ^
   |
adapters / entrypoints
```

Projections consume facts/domain values and must not become a backdoor dependency of safety decisions.

Rules:

1. `domain/` never depends on `application/`, adapters, tests, HTTP, persistence, or provider brands.
2. `routing/` may depend on domain values, not adapters/state implementation.
3. `application/` may depend on routing and ports.
4. adapters implement ports and may depend inward.
5. `lib/` never requires `test/`.
6. reference/oracle code may construct production immutable values if useful, but may not call the production decision algorithm it validates.
7. provider-specific mapping lives only at the provider adapter boundary.

Circular requires/dependencies are architecture defects.

## 7. Core value model

The initial model should be explicit enough for tests but not over-generalized.

### Money

Concept:

```text
Money(amount_minor: Integer, currency: String)
```

Invariants:

- exact integer minor units;
- explicit normalized currency code;
- no cross-currency arithmetic without a conversion policy;
- immutable.

### PayoutIntent

Contains stable identity and the minimum routing context currently needed:

```text
id
money
recipient/context attributes required by eligibility
created/policy reference if relevant
```

Do not embed current provider/attempt as mutable fields that erase history.

### RoutingPolicy

Represents the already documented allocation contract:

```text
policy id/epoch
scope
measure: count | volume
accounting point (provisional primary assignment in v0.1)
targets/min/max/tolerance as currently supported
window/scope configuration when supported
relaxation/priority semantics when supported
```

Do not implement a generic expression DSL in v0.1.

### ProviderOpportunity

Represents a provider that is functionally eligible plus normalized capabilities/state needed for this decision.

Eligibility facts and reliability ranking are separate concerns.

### EconomicOwnership

Represents the one unresolved money-moving right for an intent.

It should identify at least the provider/operation/attempt context needed to prevent a second cross-provider operation while unresolved.

### NormalizedOutcome

Closed semantic result family, not raw HTTP status:

```text
SUCCESS
PENDING
UNKNOWN
SAFE_ROUTE_FAILURE
TEMPORARY_PROVIDER_FAILURE (if required by implemented recovery semantics)
TERMINAL_PAYOUT_FAILURE
```

Attribution is a separate value (`provider`, `recipient`, `downstream`, `policy`, `unknown`, etc.).

### Decision

A decision is not just `provider_id`.

It includes:

- action (`assign`, `retry_same`, `resolve`, `fallback/assign`, `defer`, `terminate`);
- chosen provider if applicable;
- primary/recovery position;
- policy epoch;
- material reasons/exclusions sufficient for replay/explainability;
- expected state versions/snapshot identity if used for commit validation.

## 8. Pure decision contract

The core decision engine conceptually receives an immutable `DecisionContext`:

```text
payout intent
policy snapshot
eligible opportunities
live provider availability/capability snapshot
allocation snapshot including committed assignments
current payout ownership/state
prior attempt/recovery context
optional deterministic reliability ranking inputs
```

It returns a **DecisionProposal** or domain result without mutating shared state.

Possible outcomes:

- propose assignment to provider X;
- propose safe same-provider retry/status resolution;
- defer/no-safe-route;
- terminate payout;
- report policy/runtime infeasibility as part of explanation.

The proposal is not economically effective until the coordinator atomically commits it.

## 9. Atomic commit protocol

This is the most important implementation-level architecture rule.

### 9.1 Primary/fallback provider decision

Inside one coordinator critical section:

1. read/check current payout state and current relevant allocation projection;
2. ensure no incompatible unresolved economic owner exists;
3. obtain/validate the snapshot used for decision;
4. run/re-run the pure decision if necessary against the current snapshot;
5. if a provider assignment is chosen, atomically:
   - record the routing decision fact;
   - reserve/commit its allocation measure at the configured accounting point;
   - acquire economic ownership for the provider operation;
   - increment relevant revisions/projections;
6. return the committed decision to the application layer.

Then **release the mutex**.

Only after release may the application call the provider adapter.

This prevents both:

- two workers granting different unresolved owners;
- multiple workers consuming the same stale allocation deficit.

### 9.2 Provider call

Outside the coordinator lock:

1. invoke provider adapter using the committed operation identity/idempotency context;
2. receive raw/simulated result;
3. normalize it to a project observation/outcome;
4. feed the observation back to the coordinator.

Never hold a mutex across network/provider latency.

### 9.3 Observation application

Inside a new coordinator critical section:

1. deduplicate/record the observation fact, rejecting an `observation_id` reused
   with different linkage or normalized outcome;
2. validate it against known operation/ownership state;
3. derive/update payout state;
4. preserve or release ownership according to normalized semantics;
5. update settlement/projections if applicable;
6. record attribution/facts;
7. expose the resulting next-action state to the application.

For `UNKNOWN`/unresolved `PENDING`, ownership remains.

For a confirmed safe failure that proves no monetary effect can occur, ownership may be released and a fresh routing decision may follow.

For terminal payout failure, the lifecycle stops rather than hopping providers.

## 10. Coordinator design

The v0.1 in-memory coordinator intentionally uses a **coarse single Mutex** before any keyed-lock optimization.

Why:

- easiest semantics to prove;
- strongest baseline for controlled concurrency tests;
- no lock-order deadlocks across payout and allocation scope;
- allows us to discover real contention before adding complexity.

The coordinator object owns hashes/arrays internally; they are not global constants.

Suggested internal state categories:

```text
payout_states[payout_id]
allocation_states[policy_scope_key]
provider_states[provider_id]        # only if needed by current decision path
facts[]
revision
```

Snapshots returned to pure code must not expose mutable internal collections.

### Evolution path

If benchmarks later show the global lock is material, evolve in measured steps:

1. separate read-only provider/analytics projections where safe;
2. key coordination by policy allocation scope plus payout while defining lock order;
3. or replace with database transaction/optimistic revision semantics after TZ.

Do not optimize locking before v0.1 correctness evidence exists.

## 11. Revision/CAS semantics

Even though v0.1 uses a mutex, model snapshots/commits with revision awareness where it materially clarifies stale-decision behavior.

The essential semantic is:

> a decision calculated from state S must not be committed after correctness-relevant state changed to S' without revalidation/recalculation.

A later DB implementation may enforce this with row versions, transactions, compare-and-swap, or locking. The domain contract is stale-decision rejection/re-evaluation, not a particular primitive.

Do not scatter generic version numbers over every value object. Version the mutable aggregate/projection boundary where stale decisions matter.

## 12. Orchestrator lifecycle

A simplified flow:

```text
route(payout_id)
  |
  v
coordinator.prepare_and_commit_decision
  |
  +-- defer/terminal/resolution-only -> return/resolve path
  |
  +-- committed provider operation
             |
             v
       provider.initiate/continue       (NO coordinator lock)
             |
             v
       normalize observation
             |
             v
       coordinator.apply_observation
             |
       +-----+--------------------+
       |     |                    |
    success terminal        pending/unknown
       |     |                    |
      stop  stop                  stop/wait/resolve
       |
  safe failure
       |
 release owner
       |
 fresh routing decision loop
```

The application may loop through multiple **safe** recovery decisions, but must not spin indefinitely. Attempt/time budgets become explicit policy inputs when implemented/required.

`UNKNOWN` is not a loop trigger for a new provider.

## 13. Provider boundary

Do not define a 30-method universal gateway interface.

Start with the minimum semantic contract needed by the simulator/current orchestrator.

Conceptually:

```text
initiate(operation_request) -> provider observation
resolve(operation_reference) -> provider observation   # if capability supports it
```

The request contains a stable provider-local idempotency/reference key produced from committed domain operation identity.

The adapter owns:

- transport/protocol details;
- timeout/exception handling;
- provider status/error mapping;
- provider idempotency semantics/capabilities;
- raw callback parsing when later relevant.

The adapter returns normalized project values/facts, not provider SDK objects.

## 14. Simulator architecture

The v0.1 deterministic provider simulator lives in test support and implements the same semantic port expected by the orchestrator.

A scenario should be scriptable as a sequence such as:

```text
initiate -> UNKNOWN
resolve after +30s -> SUCCESS
```

or:

```text
initiate -> SAFE_ROUTE_FAILURE
```

or:

```text
initiate -> PENDING
callback duplicate -> PENDING
callback success -> SUCCESS
late duplicate -> SUCCESS (idempotent logical effect)
```

Simulator requirements:

- controlled clock;
- deterministic scripted responses;
- provider-local operation/idempotency map;
- ability to simulate response loss after accepting an operation;
- duplicate/out-of-order observation injection;
- trace output.

It must not encode production routing decisions.

## 15. State/fact model without event-sourcing overreach

We need both current state and history.

v0.1 approach:

- append domain facts to an in-memory fact list;
- update explicit current projections in the same atomic coordinator transaction;
- provide replay/projector logic for selected projections as a verification tool;
- compare live projection vs replay in tests.

Do **not** make every class an event handler or require rebuilding the whole application from an event log on every operation.

If official persistence/restart requirements later favor event sourcing, current facts/replay discipline provides a migration path without forcing it now.

## 16. Allocation architecture

Allocation is a pure algorithm plus mutable projection/commit boundary.

Pure inputs:

- target weights/constraints;
- opportunities/feasible provider IDs;
- current counted allocation values;
- committed/in-flight values;
- incoming measure (`1` for count; exact Money minor units for volume);
- deterministic tie order.

The inherited v0.1 cohort-reset rule is superseded by SPEC-002/D-025. The
current v0.2 provisional in-memory ledger is keyed by policy identity/epoch and
scope. The functional opportunity universe supplies the accounting denominator;
live availability, capacity and health only filter current candidates. A
transient live-feasibility change therefore does not erase allocation history
or create a hidden fresh window. This remains an isolated pre-TZ accounting
choice, not a public persistence contract.

Pure output:

- chosen provider or no feasible choice;
- candidate post-decision discrepancies;
- explanation/deviation information.

The allocator does not mutate counters directly.

The coordinator applies the selected allocation commitment atomically with the routing decision/ownership.

Reference tests brute-force all feasible choices for small generated states and compare the production choice to the minimum permitted discrepancy.

## 17. Eligibility architecture

Eligibility is evaluated before allocation/ranking.

Separate:

- **functional eligibility** — provider can handle the payout/policy context;
- **operational admissibility** — provider currently enabled/capacity-safe/available;
- **optimization/ranking** — relative preference among remaining providers.

The kernel should make exclusion reasons explicit enough for decision trace.

Do not hide all three inside one opaque numeric score.

## 18. Reliability/adaptive optimization boundary

v0.1 does not require adaptive ML/bandits.

If a deterministic reliability preference is used, it is an input ranking over already-feasible providers.

Future adaptive logic must obey:

```text
Safety + hard eligibility + hard policy constraints
        -> feasible actions
        -> optimizer ranking only inside feasible actions
```

The optimizer cannot acquire/release ownership or override a hard exclusion.

## 19. Recovery architecture

Recovery consumes normalized domain state, not raw exceptions.

It distinguishes:

- same-provider idempotent technical retry;
- status resolution/reconciliation;
- fresh cross-provider routing after safe release;
- wait/defer;
- terminal stop.

The recovery decision must consider ownership safety first.

Provider-specific retryability is supplied as normalized capability/observation, not hard-coded by provider brand in core recovery code.

## 20. Reconciliation architecture

Reconciliation is another observation source using the same state-transition rules as live responses/callbacks.

It may:

- resolve `UNKNOWN`/long `PENDING`;
- introduce a later failure/return fact;
- repair a derived projection based on new provider evidence.

It may not:

- delete historical facts;
- directly force ownership release without a normalized semantic proof;
- bypass ordinary transition validation.

In v0.1 reconciliation is driven by simulator/test actions rather than background jobs.

## 21. Time and randomness

Use narrow ports only where needed.

### Clock

Production adapter:

- UTC wall timestamp when creating audit facts;
- monotonic elapsed-time source for durations/timeouts.

Tests:

- controlled clock advanced synchronously.

### Random

The deterministic core does not require randomness.

Property tests use explicit `Random.new(seed)`. Optional future exploration receives a Random source explicitly.

No global `rand` in routing correctness logic.

## 22. Concurrency architecture

v0.1 correctness target is stronger than stress testing.

Use Ruby Threads to execute competing application operations and deterministic synchronization hooks/barriers to force critical interleavings.

Must test at least:

- acquire ownership vs acquire ownership;
- duplicate intent submission;
- concurrent allocation reservation from the same under-target state;
- ownership release vs fallback;
- observation/reconciliation vs recovery decision.

The initial single Mutex should make these histories linearizable. Tests should deliberately seed/remove synchronization where practical to prove the tests can detect the defect.

Do not use Ractor for the coordinator in v0.1; see `docs/RUBY.md`.

## 23. Test architecture

Default framework: Minitest.

Suggested structure:

```text
test/unit/         pure values/algorithms
test/scenario/     SPEC acceptance + fault lifecycles
test/property/     generated invariant/oracle comparisons
test/model/        long state-machine histories
test/concurrency/  forced interleavings
test/support/reference/  independent oracle
test/support/simulator/  provider scripts
test/support/      clock/barrier/trace utilities
```

Production/test separation:

- unit tests may instantiate production values directly;
- reference expected-choice/history code must not invoke production decision helpers;
- simulator implements the provider port but not routing logic;
- concurrency helpers expose scheduling points without leaking test-only behavior throughout the domain model.

Canonical commands are established in Phase 1 and recorded in the active ExecPlan/README.

## 24. Configuration architecture

Do not add a rules DSL/config platform yet.

v0.1 policies are constructed as Ruby domain values/fixtures.

When the official case requires runtime configuration:

1. parse/validate external JSON/YAML/API input at a boundary;
2. convert to validated `RoutingPolicy` domain values;
3. reject infeasible/malformed policies explicitly;
4. keep external field naming out of the allocator.

## 25. Serialization and public API

No final public API is selected in v0.1.

When it arrives, use an adapter/entrypoint over the application orchestrator. Do not move financial rules into controllers/serializers.

Expected future shape:

```text
HTTP/CLI/judge input
   -> parse/validate
   -> application command
   -> domain result
   -> explicit serializer
```

This lets Rails/Rack/CLI/judge harness be swapped without rewriting routing logic.

## 26. Persistence evolution

No production DB in v0.1.

If the TZ requires persistence/restarts, select the smallest adapter that preserves these semantics:

- single economic owner atomicity;
- allocation commitment atomicity;
- stale-decision prevention;
- append/preserved history;
- idempotent observation handling.

Likely implementations may use a relational transaction plus row versions/unique constraints, but the choice must follow actual deployment/runtime constraints.

Do not make in-memory Hash structure the future storage schema by accident.

## 27. Failure handling

Expected business/provider outcomes are values.

Exceptions may cross into the application layer only for unexpected infrastructure/programmer failures. Provider transport exceptions are normalized by adapters when semantics are known.

The orchestrator must not contain broad logic like:

```ruby
rescue StandardError
  try_next_provider
end
```

That is explicitly unsafe for payouts.

## 28. Observability/trace

No external observability platform is required now.

Every committed decision should be representable in a compact deterministic trace containing enough data to answer:

- which payout/policy epoch;
- which providers were opportunities/feasible/excluded;
- allocation state relevant to selection;
- chosen action/provider;
- primary vs recovery position;
- provider observations/outcomes;
- ownership changes;
- final settlement/result.

Tests should print this trace on generated/scenario failure.

Later logging/metrics may consume the same facts.

## 29. Performance posture

The architecture deliberately accepts a coarse lock in v0.1.

Do not infer that the final system is single-threaded or slow. First measure:

- pure allocation decision throughput;
- coordinator contention under synthetic concurrent routing;
- simulator/replay cost;
- memory growth of fact/projection representations.

If the mutex is the measured bottleneck under official/relevant load, change coordination while keeping the atomic domain contract and concurrency tests.

Do not introduce Ractors, lock striping, Redis, or queues preemptively.

## 30. Security posture

The core is provider/input agnostic, but boundaries must validate:

- IDs;
- money/currency;
- policy weights/constraints;
- supported outcome/status codes;
- duplicate observation identifiers;
- provider references.

No `eval`/dynamic code execution for policies.

No secrets in trace facts.

## 31. Architecture decisions that are now fixed for v0.1

The following are no longer open questions for the current version unless evidence forces reconsideration:

- CRuby 4.0.6 development baseline;
- plain Ruby modular monolith;
- one process for v0.1;
- root namespace `RubyRouting`;
- Minitest + Rake baseline harness;
- Integer minor-unit money;
- Rational/integer exact policy weights;
- deterministic pure routing/recovery kernel;
- application orchestrator for workflow;
- one coarse in-memory `Thread::Mutex` coordinator for atomic state;
- provider I/O outside the mutex;
- provider simulator as v0.1 provider adapter;
- facts + current projections, without full event sourcing;
- independent test oracle under `test/support/reference`;
- Threads/controlled interleavings for concurrency verification;
- no Ractor/framework/DB/queue/ML dependency in the v0.1 core.

These decisions are **implementation architecture**, not business requirements. The official TZ may change the external shell/runtime constraints without automatically invalidating the kernel.

## 32. Architecture changes that require a durable decision update

Before changing any of the following, record evidence/rationale in `docs/DECISIONS.md` and update the active ExecPlan:

- replacing the modular monolith with services;
- introducing a production DB/ORM/queue;
- changing the atomic coordinator model;
- moving provider I/O inside a state transaction/critical section (normally forbidden);
- adopting Ractor/async runtime as a core assumption;
- changing exact money representation;
- letting adaptive scoring override feasibility/safety;
- merging reference oracle with production implementation;
- adopting full event sourcing;
- changing the canonical test framework in v0.1.

Routine class/file refactors do not require an ADR-style decision.

## 33. Architecture fitness checklist

Before accepting a substantial design/code change, verify:

1. Can it create two unresolved economic owners for one intent?
2. Can provider I/O occur while the coordinator lock/transaction is held?
3. Can two workers commit against the same stale allocation state?
4. Can `UNKNOWN` release ownership accidentally?
5. Can an optimizer select a hard-ineligible provider?
6. Does provider-specific status/error logic leak into the kernel?
7. Does it collapse opportunity/assignment/attempt/settlement?
8. Can duplicate/out-of-order observations double-apply an effect?
9. Is mutable state exposed outside the coordinator?
10. Can deterministic inputs produce different decisions due to iteration/random/time?
11. Is money exact and currency explicit?
12. Does production code depend on the test oracle/simulator implementation?
13. Can a replay reconstruct the relevant projection from preserved facts?
14. Is a new dependency/infrastructure actually required now?
15. Does the design remain easy to reconcile when official TZ semantics arrive?
16. Can the relevant concurrency behavior be forced in tests rather than hoped for?
17. Is all executable domain/reference/simulator/test logic Ruby-only?

If several answers are unfavorable, fix the design before adding more code.

## 34. First implementation slice after this document

The next coding agent should not redesign architecture first.

Unless the repository has already advanced, Phase 1 should create:

1. `.ruby-version` targeting `4.0.6` as the current development baseline;
2. minimal `Gemfile` with Minitest/Rake development tooling;
3. `Rakefile` with canonical `test` task;
4. `lib/ruby_routing.rb` and namespace skeleton;
5. `test/test_helper.rb`;
6. first exact `Money` value and tests;
7. minimal coordinator/test seam only when the first ownership/allocation slice needs mutable state.

Do not scaffold every future directory/class in advance. Create directories/files when the next verified slice needs them.

The active ExecPlan remains the source of actual progress.
