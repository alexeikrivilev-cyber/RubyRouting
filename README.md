# RubyRouting

Smart payout-routing system for Hack.Genesis case **«Умный роутинг выплат»**.

## Current direction

Current Version Goal: **v0.3.4 — Pre-TZ Adversarial Case Fidelity & Edge Hardening — VERSION_COMPLETE**.

v0.3.3 / SPEC-007 remains a verified `VERSION_COMPLETE` pre-TZ baseline. v0.3.4 reached a closure checkpoint on `799f6977f07310105c30be9df549a536cc9d665d`, but a fresh post-closure audit found and deterministically reproduced a material recovery-concurrency counterexample. The token-ownership slice fixes that finding; fresh skeptical discovery, exact candidate verification and final docs-only CI are clean, so v0.3.4 is honestly published as `VERSION_COMPLETE` at the published exact head.

Ruby is mandatory. Current development baseline: **CRuby 4.0.6**.

## Case contract we optimize for

Before the authoritative TZ arrives, every substantial improvement should strengthen one of the generic requirements already explicit in the case:

1. route new payouts across providers by configurable strategies such as share by request count and share by payout volume;
2. if the chosen provider safely fails, recompute and try the next suitable provider;
3. if the provider may have accepted the payout, keep the economic owner and resolve safely before any cross-provider fallback;
4. preserve the full attempt/audit history;
5. expose clear analytics for target/actual distribution and payment/provider/fallback success.

The project avoids unrelated platform sophistication unless it produces measurable value for those requirements.

## Canonical product flow

`Payout Intent`
→ `Canonical RoutingContext`
→ `Active Configuration Snapshot / Policy Resolution`
→ `Provider Compatibility / Functional Opportunity`
→ `Operational Admission`
→ `Allocation Authority`
→ `Recovery Legality / Timing / Role`
→ `Constrained Optimization`
→ `Atomic Decision + Ownership + Reservations`
→ `Provider Operation`
→ `Normalized Observation`
→ `Lifecycle / Recovery / Reconciliation`
→ `Durable Facts`
→ `Payout History / Distribution Analytics / Outcome Analytics / Explanation`.

HTTP, demo, persistence and query layers may not implement alternate routing or trusted-provider semantics.

## Protected v0.3.3 baseline

The repository already has:

- exact Integer/Rational money and allocation math;
- deterministic count and volume allocation;
- one unresolved economic owner maximum;
- conservative `UNKNOWN` handling after ambiguous send;
- same-provider resolution/retry separated from fresh fallback;
- immutable provider operation/idempotency contracts;
- provider route capability, eligibility, capacity, throughput and health gates;
- lower-priority deterministic quality/cost/latency optimization;
- one coherent immutable active configuration generation per new decision;
- fail-closed routing/config input;
- restart-safe recovery/TTL/throughput timing across a changed monotonic origin;
- duplicate/out-of-order observation handling, settlement, reversals and economic conflicts;
- append-only facts, replay and restart reconstruction;
- dimension-safe distribution analytics, explanation and public audit;
- application commands/queries and a thin Rack-compatible HTTP adapter;
- unit/property/model/concurrency/fault/restart verification;
- bounded history/performance evidence and GitHub Actions on CRuby 4.0.6.

Do not rewrite these mechanisms merely because v0.3.4 is active.

## v0.3.4 work already verified

The current branch already contains strong verified checkpoints for:

- dimension-safe provider/fallback outcome analytics;
- measured analytics/explanation read-path hardening;
- sparse due-work scanning without a new durable index;
- fresh-process active-configuration crash consistency evidence;
- deterministic exact-case count/volume/fallback/UNKNOWN/restart campaign;
- product-facing multi-attempt history after restart;
- baseline duplicate due-worker serialization when no competing observation interferes.

These are protected checkpoints, not reasons to ignore a new counterexample.

## Why v0.3.4 is reopened

A fresh review of the live recovery interval found a new material hypothesis not covered by the closure campaign and reproduced it with controlled queues:

- `mark_attempt_started` / `mark_resolution_started` install a process-local in-flight provider-interaction guard;
- `resume_operation` correctly refuses to rebuild a provider interaction while that guard exists;
- the operation-keyed marker was cleared by an exact duplicate or other non-applying observation for the operation;
- therefore an old/duplicate callback arriving while a new live `resolve` or same-provider retry was blocked allowed a second recovery worker to start the same provider interaction concurrently.

The race is now fixed with a process-local invocation token/generation. Only the invocation that acquired the token can release it; independent callbacks may update durable evidence but cannot unlock another live call. The fresh skeptical pass, exact candidate verification and final docs-only CI are clean.

The previous closure also left active docs inconsistent (`VERSION_COMPLETE` in backlog/ExecPlan while README/AGENTS/SPEC/ROADMAP remained ACTIVE). Documentation consistency is itself a completion gate and is repaired by the current reopen checkpoint.

## Active sources

Read these first for substantial work:

1. `README.md`
2. `AGENTS.md`
3. `specifications/008-pre-tz-adversarial-edge-hardening.md`
4. `docs/exec-plans/active/pre-tz-adversarial-edge-hardening.md`
5. `docs/PRE_TZ_BACKLOG.md`
6. `docs/ROADMAP.md`
7. `docs/COMPLETION_POLICY.md`
8. `docs/PRE_TZ_ARCHITECTURE_V03_4.md`
9. `docs/DECISIONS_V03_4.md`
10. SPEC-007/v0.3.3 docs only for inherited guarantees/rationale
11. `docs/TESTING.md`, `docs/RUBY.md`, `docs/WORKFLOW.md` as relevant
12. `docs/TZ_RECONCILIATION.md` when authoritative TZ arrives.

Then inspect exact HEAD, production code, tests and current CI before implementation.

## Current implementation vector

Priority order:

1. reproduce or falsify the live provider-interaction guard ownership race;
2. if reproduced, replace boolean/operation-scoped guard release semantics with invocation-owned interaction identity/generation so only the active invocation can release its guard;
3. prove both status-resolution and idempotent-retry paths under duplicate, stale and non-applying observations;
4. verify adapter-exception cleanup, callback-before-start behavior and restart semantics remain correct;
5. run adjacent concurrency/property/model/fault regression and full exact-HEAD verification;
6. perform a fresh independent skeptical pass after the fix;
7. only then reconsider `VERSION_CANDIDATE` / `VERSION_COMPLETE`.

No new product feature outranks this P0 correctness work.

## Non-negotiable financial invariants

- One payout submission is one economic intent.
- At most one unresolved money-moving economic owner exists per intent.
- Ambiguous-after-possible-send is `UNKNOWN` unless provider semantics prove otherwise.
- `UNKNOWN` retains ownership and blocks cross-provider fallback.
- Same-provider retry/status lookup is distinct from fresh fallback.
- Fresh fallback re-evaluates current feasibility and excludes already money-moving providers by default.
- Provider-local idempotency does not protect cross-provider duplication.
- Hard safety, functional eligibility and operational admission precede allocation/optimization.
- Primary allocation, recovery attempts and settlement are separate accounting views.
- Provider outcome attribution is distinct from payout business outcome.
- Late evidence of a second monetary effect is an economic conflict requiring reconciliation.
- No-safe-route/defer/reconciliation-blocked are valid outcomes.
- Additive analytics never mixes incompatible measures/currencies.
- A process-local provider interaction guard is owned by the live invocation that acquired it; unrelated callbacks must not release another invocation's guard.

## Architecture stance

Keep a plain-Ruby modular monolith with one atomic correctness facade.

The Coordinator remains the atomic correctness boundary. Do not split it cosmetically. Extract a smaller interaction-guard component only if the recovery fix proves that explicit ownership/token semantics materially clarify correctness and tests.

Performance caches/indexes are rebuildable derived state and never economic truth. Prefer existing FactStore indexes, revision-keyed derived projections and sorting only actionable due work before considering heavier infrastructure.

Do not introduce microservices, Rails/ORM, Redis/Sidekiq, distributed leases, a database-backed config service, PSP-specific core schemas or ML/bandits before authoritative requirements or measured need exists.

## Development commands

```text
bundle check
bundle exec rake test
bundle exec rake property
bundle exec rake model
bundle exec rake concurrency
bundle exec rake fault
bundle exec rake benchmark
bundle exec rake load_10k
bundle exec rake degradation_metrics
bundle exec rake history_profile
bundle exec rake read_path_profile
ruby -Ilib bin/ruby_routing_demo
```

For the next coding session, run the focused recovery race reproducer first. Do not burn full-suite time before the counterexample has been made deterministic.

## Completion discipline

The closure publication at `799f6977f07310105c30be9df549a536cc9d665d` is historical evidence, not an immutable declaration of correctness. A later material finding reopens the version by design.

After the recovery guard finding was resolved, finishing known PTZ4 items created only `VERSION_CANDIDATE`. The independent skeptical discovery protocol then found no new material issue, and exact candidate verification/CI passed before this final publication.

Any new material locally solvable finding returns v0.3.4 to ACTIVE. `VERSION_COMPLETE` requires fresh exact-HEAD verification, current CI, and all active normative docs agreeing on the status.

The absence of the official TZ is not a stop condition.
