# RubyRouting

Smart payout-routing engine for the Hack.Genesis case **«Умный роутинг выплат»**.

## Current state

Current Version Goal: **v0.1 — Pre-TZ Deterministic Foundation**.

Development is active before the full TZ. We are building the stable, reversible parts now: deterministic financial kernel, count/volume allocation, economic ownership/recovery, provider simulator, reference model, deep verification harness, decision trace/replay, and concurrency correctness.

Unknown external contracts remain deliberately replaceable until the official TZ arrives.

The v0.1 pre-TZ foundation is implemented and its closure evidence is recorded
in the active ExecPlan; remaining work is official-TZ reconciliation.

**Ruby is mandatory. Current development baseline: CRuby 4.0.6.** Product logic, routing algorithms, oracle/reference model, simulator, property/model/concurrency tests, and domain benchmarks are Ruby-only.

## Architecture baseline

v0.1 uses a concrete architecture so coding can proceed without another design round:

- plain Ruby modular monolith;
- root namespace `RubyRouting`;
- deterministic financial/routing kernel;
- application orchestrator for lifecycle workflow;
- provider/time/external-state boundaries as narrow ports/adapters;
- one in-memory atomic coordinator guarded initially by a coarse `Thread::Mutex`;
- allocation reservation + routing decision + economic ownership committed atomically before provider I/O;
- provider I/O **outside** the coordinator lock;
- provider observations applied in a later synchronized transition;
- facts + current projections, not mandatory full event sourcing;
- Minitest + Rake baseline test harness;
- independent reference model under test support;
- Threads + controlled interleavings for concurrency verification; no Ractor core in v0.1.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the detailed decision/commit/observation protocol and [`docs/RUBY.md`](docs/RUBY.md) for Ruby-specific engineering rules.

## Core thesis

The system is not merely a weighted provider selector. It is a **policy-constrained payout orchestrator** that must answer four distinct questions correctly:

1. Is a new money-moving operation safe?
2. Which providers are admissible for this payout now?
3. Which admissible provider best satisfies allocation policy and permitted reliability objectives?
4. After an attempt, is retry/fallback safe, or must the current provider operation be resolved first?

Financial correctness precedes optimization.

## Critical invariants

- One payout submission is one **economic intent**.
- Target behavior is effectively-once economic effect, not literal distributed exactly-once execution.
- At most one unresolved money-moving economic owner exists per intent.
- Timeout after possible provider acceptance is `UNKNOWN`, not automatic failure.
- `UNKNOWN` does not release ownership.
- Cross-provider fallback requires safe release/proof that the previous operation cannot create the monetary effect.
- Same-provider retry, status resolution, fallback, reconciliation, and defer are distinct actions.
- Hard safety/eligibility constraints precede allocation/ranking.
- Count/volume allocation uses exact arithmetic and includes committed/in-flight assignments under concurrency.
- Opportunity, assignment, attempt, observation, and settlement remain distinct facts.
- Payout outcome and provider reliability attribution are separate.
- `NO_SAFE_ROUTE`/defer is valid.

Behavioral details and provisional semantics live in the specification.

## Repository map

Read a fresh project-wide Goal Mode session in roughly this order:

- [`AGENTS.md`](AGENTS.md) — coding-agent contract, source precedence, safety/continuation rules.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — project/version/phase/slice goals and v0.1 exit gate.
- [`docs/exec-plans/active/pre-tz-foundation.md`](docs/exec-plans/active/pre-tz-foundation.md) — living current execution state.
- [`specifications/001-smart-payout-routing.md`](specifications/001-smart-payout-routing.md) — behavioral/product source of truth.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — concrete v0.1 architecture and atomicity model.
- [`docs/RUBY.md`](docs/RUBY.md) — professional Ruby 4.0 engineering guide for this project.
- [`docs/TESTING.md`](docs/TESTING.md) — deterministic, oracle, property/model, concurrency and fault-verification methodology.
- [`docs/WORKFLOW.md`](docs/WORKFLOW.md) — Goal Mode + SpecOps development loop.
- [`docs/PLANS.md`](docs/PLANS.md) — living ExecPlan protocol.
- [`docs/SESSION_POLICY.md`](docs/SESSION_POLICY.md) — long-session continuation/stop rules.
- [`docs/BACKLOG.md`](docs/BACKLOG.md) — NOW/BLOCKED/NEXT/LATER work.
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — durable project decisions/provisional assumptions.
- [`docs/RESEARCH.md`](docs/RESEARCH.md) — external research/evidence.

Repository documentation is the durable system of record for coding agents.

## Ruby rules in brief

Detailed guidance is in `docs/RUBY.md`. Important defaults:

- CRuby 4.0.6 development baseline until judge runtime is known;
- `Integer` minor units + explicit currency for money;
- exact integer weights/`Rational` for proportions and discrepancy;
- no Float monetary arithmetic;
- `Data.define` for simple immutable value-like records, with nested mutability protected;
- explicit classes for invariant-heavy domain types;
- deterministic ordering/tie-breaking;
- controlled `Random` instances/seeds only where randomness is intentional;
- controlled clock for time-dependent tests; no real sleeps as the primary test mechanism;
- `Thread::Mutex` for v0.1 shared-state correctness; never rely on the GVL;
- provider/time/random state at explicit boundaries;
- expected payment outcomes are explicit values, not broad exception control flow;
- no metaprogramming/framework/dependency merely for appearance.

## Development commands

Install the declared Ruby dependencies with `bundle install`, then run the complete
test suite with the canonical command:

```text
bundle exec rake test
```

For one focused test file, use:

```text
bundle exec ruby -Ilib -Itest test/unit/money_test.rb
```

Property/model and fault/concurrency suites are also available as focused Rake
tasks. Generated checks use a deterministic default seed and accept an explicit
`RUBY_ROUTING_SEED` environment value for replay.

```text
bundle exec rake property
bundle exec rake model
bundle exec rake concurrency
bundle exec rake fault
```

The repository targets CRuby 4.0.6 through `.ruby-version`. The official TZ may
later impose a different judge runtime; that reconciliation is intentionally kept
separate from the pre-TZ foundation.

## Long-running development model

Work is organized as:

`Project Goal -> Version Goal -> Phase Goal -> Slice Goal`

The coding agent works depth-first on a small verified slice, updates the living ExecPlan, then selects the next required slice.

Completing a file, test, commit, milestone, or phase is not permission to stop.

A long Goal Mode run stops only when:

- every active version exit criterion in `docs/ROADMAP.md` is satisfied; or
- every remaining required version path depends on a genuine external blocker outside the agent's control.

See `docs/SESSION_POLICY.md`.

## What v0.1 builds

- minimal Ruby/Bundler/Rake/Minitest harness with one canonical full-suite command;
- exact `Money` and core immutable values;
- independent pure-Ruby reference/oracle model;
- deterministic count/volume allocation with committed assignments;
- economic ownership + normalized recovery kernel;
- deterministic provider/fault simulator;
- model/property tests with replayable seeds;
- controlled concurrency/interleaving tests;
- immutable-enough facts, trace/replay and baseline projections;
- performance baseline without invented judge thresholds.

The first implementation slice is specified at the end of `docs/ARCHITECTURE.md` and sequenced by the active ExecPlan.

## What remains intentionally unfixed before the TZ

The architecture does **not** currently commit to:

- Rails/Sinatra/Hanami;
- production database/ORM;
- queue/event bus/background jobs;
- microservices/deployment topology;
- official provider SDK/transport;
- final public API/UI;
- ML/RL/contextual bandits;
- external observability stack.

This is deliberate reversibility, not inactivity.

## Verification standard

Happy-path unit tests are insufficient. Depending on risk, the project uses:

- deterministic acceptance/regression scenarios;
- independent oracle comparisons;
- property/invariant generation;
- state-machine/model histories;
- controlled concurrency/interleavings;
- deterministic provider fault injection;
- duplicate/delayed/out-of-order observation tests;
- trace/replay/projection checks;
- stress/performance baselines;
- targeted fault/mutation seeding when useful to prove critical tests can detect broken invariants.

Any material bug should gain a deterministic regression. Randomized failures preserve seed/trace. Flaky retries are not a quality strategy.

See `docs/TESTING.md`.

## Full-TZ gate

When the official TZ arrives, advance through the roadmap reconciliation phase rather than rebuilding blindly:

1. classify baseline requirements as `CONFIRMED`, `CHANGED`, `REMOVED`, `NEW`, or `AMBIGUOUS`;
2. update specification and reference/oracle/tests;
3. adapt dependent production behavior;
4. choose only the external framework/persistence/API/provider architecture now justified by the TZ;
5. turn official performance/scoring constraints into executable gates.

The goal is for the verified Ruby financial kernel to survive while provisional external/accounting details remain cheap to change.
