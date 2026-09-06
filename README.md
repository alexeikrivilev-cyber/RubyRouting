# RubyRouting

Smart payout-routing engine for Hack.Genesis case **«Умный роутинг выплат»**.

## Current state

Current Version Goal: **v0.2 — Pre-TZ Comprehensive Routing Core**.

The first deterministic v0.1 foundation is an executable checkpoint, not the end of pre-TZ development. A second technical review found important locally solvable interaction gaps, so development continues until the generic routing core is genuinely comprehensive and evidence-backed.

The official TZ is **not available yet**. We do not guess its exact API, storage, simulator, scoring or final allocation contract. Instead, we implement every high-value generic routing mechanism that can be made explicit, configurable and testable now.

**Ruby is mandatory. Current development baseline: CRuby 4.0.6.** Product logic, routing algorithms, oracle/reference model, simulator, property/model/concurrency/fault tests and domain benchmarks are Ruby-only.

## What “comprehensive pre-TZ core” means

The current target is not a minimal weighted selector. The engine must coherently cover:

- one economic intent / effectively-once economic semantics;
- operation dispatch, idempotency and transport ambiguity;
- count and monetary-volume allocation;
- policy identity, scope, accounting/window/tolerance and generic hard/soft constraints;
- context-aware provider opportunity/eligibility;
- live availability and atomic capacity reservations;
- deterministic provider health, quarantine/probing and controlled exposure;
- deterministic ranking inside the already safe feasible set;
- retry, status resolution, fallback, defer, reconciliation, budgets, time and TTL;
- duplicate/delayed/out-of-order observation reduction;
- settlement, return/reversal and economic-conflict handling;
- lifecycle replay from typed facts;
- typed decision trace, deviation attribution and primary/recovery/settlement analytics;
- controlled concurrency and cross-feature adversarial verification.

Exact external representation remains replaceable until the TZ. The concepts themselves are not omitted merely because official defaults are unknown.

See [`specifications/003-pre-tz-full-logic-and-completion.md`](specifications/003-pre-tz-full-logic-and-completion.md).

## Direction verdict

The architectural vector remains correct and should not be restarted:

- plain-Ruby modular monolith;
- deterministic financial kernel;
- exact `Integer` money / `Rational` allocation math;
- economic intent + single unresolved ownership;
- `UNKNOWN != failure`;
- one clear atomic coordinator boundary;
- provider I/O outside the coordinator lock;
- append-preserved typed facts and replayable projections;
- independent Ruby oracle/simulator;
- deep scenario/property/model/concurrency testing;
- no premature Rails/DB/queue/microservice/ML commitment.

Current architecture supplement: [`docs/CURRENT_ARCHITECTURE.md`](docs/CURRENT_ARCHITECTURE.md).  
Detailed first-foundation architecture remains in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Active behavioral specification

Before the official TZ, behavior precedence is:

1. [`specifications/003-pre-tz-full-logic-and-completion.md`](specifications/003-pre-tz-full-logic-and-completion.md) — mandatory full-logic/completion envelope;
2. [`specifications/002-pre-tz-comprehensive-core.md`](specifications/002-pre-tz-comprehensive-core.md) — implementation-review amendments;
3. [`specifications/001-smart-payout-routing.md`](specifications/001-smart-payout-routing.md) — baseline domain specification.

When the official TZ arrives it supersedes provisional semantics through explicit reconciliation, not silent edits.

## Critical current corrections

The v0.2 work specifically fixes/proves that:

- primary allocation is not polluted by fallback under `primary_assignment` accounting;
- fresh fallback cannot silently start a new operation at a PSP that already failed;
- provider-operation recovery semantics survive route disablement;
- committed-but-not-dispatched is distinct from unresolved/UNKNOWN;
- definitely-not-sent and ambiguous-after-send transport failures differ economically;
- functional opportunity is distinct from live availability/capacity/health;
- transient outage does not silently reset allocation history;
- event chronology is not guessed by status severity;
- late contradictory monetary evidence becomes an explicit economic conflict;
- replay rebuilds lifecycle state, not only aggregate analytics.

See [`docs/TECH_REVIEW_2026-08-27.md`](docs/TECH_REVIEW_2026-08-27.md).

## Completion is evidence-gated

A green suite or a fully checked plan is not permission to say the version is done.

Before `VERSION_COMPLETE`, the agent must enter `VERSION_CANDIDATE` and perform a fresh:

- source/spec reconciliation;
- full capability-matrix sweep;
- repository unfinished-code discovery sweep;
- adversarial/red-team counterexample pass;
- current full verification run;
- NOW/P0/P1 and blocker audit;
- documentation consistency audit.

If that discovers an important locally solvable gap, the version returns to active development even if every previous phase checkbox was green.

See [`docs/COMPLETION_POLICY.md`](docs/COMPLETION_POLICY.md).

## Repository map

Fresh project-wide Goal Mode read order:

1. [`AGENTS.md`](AGENTS.md)
2. [`docs/ROADMAP.md`](docs/ROADMAP.md)
3. [`docs/COMPLETION_POLICY.md`](docs/COMPLETION_POLICY.md)
4. [`docs/exec-plans/active/pre-tz-comprehensive-core.md`](docs/exec-plans/active/pre-tz-comprehensive-core.md)
5. [`specifications/001-smart-payout-routing.md`](specifications/001-smart-payout-routing.md)
6. [`specifications/002-pre-tz-comprehensive-core.md`](specifications/002-pre-tz-comprehensive-core.md)
7. [`specifications/003-pre-tz-full-logic-and-completion.md`](specifications/003-pre-tz-full-logic-and-completion.md)
8. [`docs/TECH_REVIEW_2026-08-27.md`](docs/TECH_REVIEW_2026-08-27.md)
9. [`docs/CURRENT_ARCHITECTURE.md`](docs/CURRENT_ARCHITECTURE.md)
10. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
11. [`docs/RUBY.md`](docs/RUBY.md)
12. [`docs/TESTING.md`](docs/TESTING.md)
13. [`docs/WORKFLOW.md`](docs/WORKFLOW.md)
14. [`docs/PLANS.md`](docs/PLANS.md)
15. [`docs/SESSION_POLICY.md`](docs/SESSION_POLICY.md)
16. [`docs/BACKLOG.md`](docs/BACKLOG.md)
17. [`docs/DECISIONS.md`](docs/DECISIONS.md)
18. [`docs/DOCUMENTATION_AUDIT_2026-08-27.md`](docs/DOCUMENTATION_AUDIT_2026-08-27.md)
19. [`docs/RESEARCH.md`](docs/RESEARCH.md)

The v0.1 plan is historical evidence at `docs/exec-plans/completed/pre-tz-foundation.md`.

## Architecture baseline

Keep the inherited architecture while v0.2 evolves internals:

- `RubyRouting` root namespace;
- domain/routing kernel independent of provider transport;
- application orchestrator/use cases;
- provider/time/external-state boundaries as narrow ports/adapters;
- one in-memory coordinator guarded by `Thread::Mutex` as the current atomic baseline;
- primary allocation/capacity/ownership/operation state committed atomically where required before provider I/O;
- provider I/O outside the lock;
- provider observations applied later through explicit lifecycle reduction;
- facts + derived projections without requiring event-sourcing infrastructure;
- Minitest + Rake;
- independent reference model under test support;
- Threads/controlled interleavings, not Ractor, for current concurrency verification.

`State::Coordinator` may be decomposed into internal ledgers/reducers as mechanics grow, but those are internal correctness responsibilities, not automatic services.

## Critical financial invariants

- One payout submission represents one economic intent.
- At most one unresolved money-moving economic owner exists per intent.
- Timeout after possible provider acceptance is `UNKNOWN`, not failure.
- `UNKNOWN` does not release ownership.
- Cross-provider fallback requires safe ownership release.
- Same-provider retry/status resolution is different from fresh fallback.
- Fresh fallback excludes already money-moving attempted providers by default.
- Hard safety/eligibility/capacity/health constraints precede allocation/ranking.
- Primary allocation, recovery attempts and settlement are distinct accounting views.
- Allocation concurrency includes committed/in-flight primary assignments.
- Operation recovery contract is pinned for the operation lifetime.
- Provider outcome attribution is separate from payout business outcome.
- Late evidence of a possible second monetary effect is an incident, not a callback to ignore.
- `NO_SAFE_ROUTE`, defer and reconciliation-blocked are valid outcomes.

## Development commands

Current canonical command surface:

```text
bundle check
bundle exec rake test
bundle exec rake property
bundle exec rake model
bundle exec rake concurrency
bundle exec rake fault
bundle exec rake benchmark
```

Focused test:

```text
bundle exec ruby -Ilib -Itest <test-file>
```

Generated tests use deterministic seeds; preserve seed/trace for failures.

The v0.1 plan recorded a locally green 51-test / 2,753-assertion baseline. That is historical evidence only. v0.2 begins by rerunning current code and should add minimal CI evidence when feasible.

## What stays TZ-dependent

Do not freeze without evidence:

- final web/API/UI shape;
- production database/ORM/persistence topology;
- queue/background-job/event-bus product;
- deployment/microservice topology;
- official provider SDK/transport payloads;
- exact judge runtime/dependency restrictions;
- official allocation denominator/window/default thresholds;
- judged scoring weights;
- adaptive ML/bandit layer.

These unknowns do not justify omitting the corresponding generic domain concepts.

## Long-running development model

`Project Goal -> Version Goal -> Phase Goal -> Slice Goal`

A slice, test, commit or phase is a checkpoint, not permission to stop. Goal Mode continues until the v0.2 closure protocol and exit gate pass or every remaining required path is genuinely externally blocked.

The absence of the official TZ is explicitly **not** a blocker for v0.2.

## Full-TZ transition

When the official TZ arrives:

1. advance to roadmap v0.3;
2. classify SPEC-001/002/003 rules as `CONFIRMED`, `CHANGED`, `REMOVED`, `NEW`, `AMBIGUOUS`;
3. update oracle/tests with changed semantics before or alongside production behavior;
4. choose only the external API/framework/persistence/provider integration actually required;
5. convert judge scoring/load constraints into executable gates;
6. preserve the verified v0.2 core wherever semantics remain valid.
