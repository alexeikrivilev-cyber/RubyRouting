# AGENTS.md

## Mission

Build RubyRouting into the strongest submission-grade implementation of the Hack.Genesis **«Умный роутинг выплат»** case that can be engineered before the authoritative TZ arrives. Ruby is mandatory. Current development baseline: **CRuby 4.0.6**.

Current Version Goal: **v0.3.4 — Pre-TZ Adversarial Case Fidelity & Edge Hardening — VERSION_COMPLETE**.

v0.3.3 / SPEC-007 is a verified `VERSION_COMPLETE` baseline. v0.3.4 reached a closure publication at `799f6977f07310105c30be9df549a536cc9d665d`, but a later code audit found and reproduced a new material recovery-concurrency counterexample. The token-ownership slice fixes it, fresh skeptical discovery and exact verification passed, and final docs-only CI is green; v0.3.4 is `VERSION_COMPLETE` at the published exact head. A closure checkpoint is evidence, not immunity from a newly discovered counterexample.

## Fresh-session read order

For substantial work read in this order:

1. `README.md`
2. `AGENTS.md`
3. `specifications/008-pre-tz-adversarial-edge-hardening.md`
4. `docs/exec-plans/active/pre-tz-adversarial-edge-hardening.md`
5. `docs/PRE_TZ_BACKLOG.md`
6. `docs/ROADMAP.md`
7. `docs/COMPLETION_POLICY.md`
8. `docs/PRE_TZ_ARCHITECTURE_V03_4.md`
9. `docs/DECISIONS_V03_4.md`
10. SPEC-007/v0.3.3 docs only for inherited guarantees or rationale
11. `docs/TESTING.md`, `docs/RUBY.md`, `docs/WORKFLOW.md` when relevant
12. `docs/TZ_RECONCILIATION.md` for the authority-switch protocol.

Then inspect actual `main`: exact HEAD, production code, reachable application paths, tests and current CI. Documentation is authority for intent; implementation/tests are evidence, not proof of completeness.

## Source-of-truth precedence before TZ

`direct current instruction > SPEC-008 > active v0.3.4 ExecPlan > active PRE_TZ_BACKLOG > PRE_TZ_ARCHITECTURE_V03_4 > DECISIONS_V03_4 > compatible SPEC-007 guarantees > older inherited architecture/decisions > implementation/tests`

When the authoritative TZ arrives, execute `docs/TZ_RECONCILIATION.md`; the full TZ becomes highest domain authority.

## Case relevance rule

Prefer work that directly strengthens the case:

1. configurable routing by request-count share and payout-volume share;
2. next-suitable-provider fallback after a confirmed safe failure;
3. conservative handling when the provider may already have accepted the payout;
4. complete, replayable history of routing/provider attempts;
5. analytics for target/actual distribution and payment/provider/fallback success.

Do not spend pre-TZ time on generic infrastructure sophistication unless a reproducer, benchmark or authoritative requirement ties it to one of these outcomes.

## Protected correctness baseline

Preserve unless new evidence proves a defect:

- money is exact Integer minor units with explicit currency;
- allocation/proportion arithmetic is exact Integer/Rational, never Float;
- one payout submission represents one economic intent;
- at most one unresolved money-moving economic owner exists per payout;
- ambiguous-after-possible-send is `UNKNOWN` unless provider semantics prove otherwise;
- `UNKNOWN` retains ownership and blocks cross-provider fallback;
- same-provider lookup/retry is distinct from fresh provider fallback;
- provider-local idempotency is not cross-provider idempotency;
- primary assignment, recovery attempts and settlement are distinct accounting views;
- functional opportunity is distinct from operational admission;
- capacity exposure is distinct from time-window throughput;
- hard safety/eligibility/admission precede allocation and optimization;
- lower-priority quality/cost/latency cannot trade away allocation authority;
- provider I/O stays outside atomic/configuration locks;
- raw provider events are normalized at provider-specific boundaries;
- operation payload/contract identity is immutable and restart-safe;
- active policy/provider definitions for one new decision come from one immutable configuration revision;
- malformed routing-critical input fails closed;
- quality evidence age/currency/route authority is bounded and deterministic;
- restart timing is portable across a changed monotonic origin;
- additive analytics never mixes incompatible measures or currencies;
- unresolved restart/replay preserves economic state;
- public audit/explanation privacy boundaries remain intact;
- randomized/property/model/concurrency/fault evidence remains reproducible.

## Protected v0.3.4 checkpoints

Do not reopen these merely because v0.3.4 is ACTIVE again:

- typed provider/fallback outcome analytics and explicit populations;
- revision-keyed derived analytics reuse with full replay parity;
- indexed payout explanation;
- sparse due-work scanning without a durable queue/index;
- fresh-process active configuration crash/restart campaign;
- exact-case count/volume/fallback/UNKNOWN/restart campaign;
- public multi-attempt history completeness after restart;
- baseline N-worker duplicate due-work race with no competing observation.

A new counterexample that directly falsifies one of these is sufficient to reopen that mechanism.

## Current v0.3.4 closure gate — live provider-interaction guard ownership verified

The implementation slice, fresh skeptical discovery, exact candidate verification and final docs-only CI are complete.

Current implementation installs a process-local in-flight marker after consuming a durable dispatch/resolution token and before provider I/O completes. `resume_operation` uses it to block duplicate recovery workers.

Fresh audit found and deterministically reproduced an interleaving: an exact duplicate or otherwise non-applying callback for the same payout/operation could clear the process-local marker while the current live `resolve` / same-provider retry was still blocked. A second worker could then rebuild the same recovery operation and start another provider interaction before the first invocation completed. The fix gives each live invocation an immutable local token/generation and releases only a matching owner.

Required process-local invariant:

> A live provider interaction guard is owned by the invocation that acquired it. Only that invocation's completion/failure path, or an explicitly equivalent ownership-aware transition, may release it. An unrelated callback must never release another invocation's guard.

The guard is not durable and must remain absent after fresh process restart; durable operation phase/contract semantics continue to own restart recovery.

## Current development vector

Priority order for closure:

1. construct a deterministic barrier reproducer for blocked live `resolve` + duplicate old observation + concurrent second `resume`. DONE; pre-fix call count was 2.
2. construct the same class of reproducer for idempotent same-provider retry and for a stale/non-applying observation. DONE.
3. implement the smallest ownership-aware interaction token/generation abstraction; do not add distributed locks/leases. DONE.
4. prove adapter exception cleanup releases only the invocation it owns. DONE.
5. prove accepted observation/completion cannot leave a stuck local guard. DONE.
6. preserve callback-before-dispatch/resolution token invalidation semantics. DONE.
7. preserve fresh restart behavior: process-local interaction identity is discarded and restart is rebuilt only from durable operation state. DONE.
8. run focused concurrency/recovery/restart/fault tests. DONE; green.
9. run full `test/property/model/concurrency/fault` matrix and acceptance traceability. DONE; green.
10. perform a new skeptical adjacent-layer review before candidate closure. DONE; no new material P0/P1 found.

No analytics, dashboard, ranking, storage or API feature outranks this P0.

## Recovery-worker rule

`due_work` is a query, not a lease.

Multiple workers may observe the same work item. The coordinator must guarantee at most one live provider interaction for one committed recovery token inside one process. Losing workers must not create another provider call, operation, owner, allocation or fallback.

A duplicate/stale/out-of-order provider observation is lifecycle evidence, not proof that the currently executing provider invocation finished. Observation application and live invocation ownership are separate concepts.

Do not solve this with Redis, queues, distributed locks or process-wide serialization. The current architecture only needs correct process-local ownership plus the existing durable restart protocol.

## Outcome analytics rule

Distribution measures and outcome counts are separate semantic systems.

- allocation/settlement volume remains exact measure data;
- payout/attempt success denominators are integer populations;
- never divide settlement volume by attempts to call it a success rate;
- mixed count/volume policies and different currencies may not be aggregated into one additive amount;
- if a rate is exposed, publish its numerator/denominator semantics and use exact Rational arithmetic;
- reversal is post-settlement evidence and remains separate from historical routing success unless an explicitly named metric says otherwise;
- application/HTTP consume the canonical projection, not another formula.

## Configuration crash rule

Abrupt configuration-publication restart is already covered by a fresh-process campaign. Preserve the result: restart reconciles one coherent externally supplied generation or fails closed before routing; silent mixed policy/provider generation is forbidden.

Do not introduce a durable config database unless a new reproducer proves the current fail-closed/reconcile contract insufficient.

## Performance rule

Performance work is evidence-gated. Current v0.3.4 read-path optimizations are protected. Do not optimize further unless a new measurement shows material need.

Derived caches/indexes are never economic truth and must rebuild exactly from durable facts.

## Canonical product flow

`Payout Intent`
→ `Canonical RoutingContext`
→ `Active Configuration Snapshot / Policy Resolution`
→ `Provider Route Compatibility / Functional Opportunity`
→ `Operational Admission`
→ `Allocation Authority`
→ `Recovery Legality / Timing / Role`
→ `Constrained Optimization`
→ `Atomic Decision + Ownership + Reservations`
→ `Provider Operation`
→ `Operational Telemetry + Normalized Observation`
→ `Lifecycle / Recovery / Reconciliation`
→ `Durable State + Facts`
→ `Payout History / Distribution Analytics / Outcome Analytics / Explanation / Control Queries`.

Every production feature gets one owner in this flow. HTTP, demo, persistence and benchmark code may not own alternate routing semantics.

## Architecture rule

Keep `State::Coordinator` as the atomic transaction facade. File size alone is not a refactor reason.

For the current P0, an extraction is justified only if it centralizes the newly proven live-interaction ownership invariant. A small `ProviderInteractionGuard`/token object is acceptable if it improves correctness and reduces release-by-key ambiguity. Cosmetic Coordinator splitting is not.

Provider/network I/O remains outside atomic locks.

## Goal Mode operating loop

For every substantial session:

1. read active sources;
2. inspect actual HEAD/code/tests/CI;
3. reconcile the ExecPlan with reality;
4. formulate one session Goal that advances the current Version Goal;
5. start with the smallest deterministic counterexample for the highest-risk open hypothesis;
6. do not implement until the failure is reproduced or the hypothesis is falsified;
7. implement the narrowest correctness change;
8. run focused verification;
9. run broader risk-appropriate verification;
10. perform skeptical adjacent-layer review;
11. add deterministic regressions for every material defect;
12. update active plan/backlog/decisions with exact evidence;
13. choose the next slice and continue until the Goal is satisfied or a genuine external blocker exists.

A file, test, commit, green CI, benchmark, backlog item, milestone or phase is a checkpoint, never an automatic stop.

Do not ask whether to continue when the next step is derivable from active sources and code.

## Mandatory anti-premature-completion rule

The agent may not transition directly from “all known PTZ4 work is green” to `VERSION_COMPLETE`.

When known P0/P1 work appears exhausted:

1. set `VERSION_CANDIDATE` only;
2. ignore prior closure labels as evidence of current completeness;
3. perform a new adversarial discovery pass from actual changed production code;
4. construct counterexamples outside the exact implementation scenarios;
5. specifically challenge interaction-guard release by duplicate/stale callbacks, adapter exceptions, accepted observations, callback-before-start, restart and concurrent `resume`;
6. challenge outcome denominators, config crash/restart, projection revision invalidation, due-work ordering, exact-case behavior, UNKNOWN/late-success/reversal histories, API/application parity and measured scale claims;
7. classify every new finding;
8. any material locally solvable P0/P1 reopens ACTIVE development;
9. only a fresh pass with no material findings may proceed to exact-HEAD closure verification.

## Verification rules

Use `docs/TESTING.md`. At minimum, select from:

- deterministic unit/acceptance regressions;
- independent oracle/property/metamorphic tests;
- model/state-machine histories;
- controlled concurrency/interleavings;
- fresh-process restart/crash tests;
- seeded fault campaigns;
- full replay/live equivalence;
- focused performance benchmarks after correctness;
- exact-head CI.

No flaky retry masking. Every material randomized failure gets a reproducible seed/trace. Concurrency correctness tests use barriers/latches/queues, not timing sleeps.

## Scope control

Do not add before authoritative need/evidence:

- microservices/distributed deployment;
- Rails/ORM;
- Redis/Sidekiq/queue infrastructure;
- distributed leases/locks;
- brand-specific PSP core schemas;
- generalized rules DSLs;
- ML/bandits;
- dashboard polish that does not improve case evidence;
- cosmetic Coordinator/restorer splitting.

## Stop conditions

Stop only when:

1. v0.3.4 passes its new independent skeptical closure on exact HEAD with current verification/CI and all active docs agree; or
2. every remaining mandatory path is genuinely externally blocked and no independent case-relevant work remains; or
3. authoritative TZ arrives, then immediately execute `docs/TZ_RECONCILIATION.md`.

If one path is blocked, continue another required v0.3.4 slice. After two similar failed approaches, change tactic; after three materially different failures, reduce to a minimal reproducer and re-plan.
