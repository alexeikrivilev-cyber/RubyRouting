# SPEC-008 — Pre-TZ Adversarial Case Fidelity & Edge Hardening

Status: VERSION_COMPLETE

## Purpose

Open v0.3.4 after the verified v0.3.3/SPEC-007 closure and continue only with newly observed, case-relevant edges. A v0.3.4 closure checkpoint existed at `799f6977f07310105c30be9df549a536cc9d665d`; a later audit found and reproduced a new material recovery-concurrency counterexample, therefore this specification was active again under the repository completion policy. Its token-ownership fix, fresh skeptical pass, exact candidate verification and final docs-only CI are verified; this specification is `VERSION_COMPLETE` at the published exact head.

The Hack.Genesis case requires configurable count/volume distribution, safe fallback to another suitable provider, complete attempt history and final analytics for distribution and payment success. v0.3.4 strengthens the correctness and evidence behind those judge-visible capabilities without speculative infrastructure.

## Version Goal

Make the existing financial kernel directly case-complete and operationally credible before the authoritative TZ.

A v0.3.4 candidate must make these statements true:

1. provider/fallback success questions are answered with typed dimension-safe outcome analytics;
2. duplicate recovery consumers cannot cause duplicate live provider interaction or a second economic effect;
3. duplicate/stale/non-applying observations cannot release another currently executing provider invocation's process-local interaction guard;
4. abrupt process failure during active configuration publication cannot silently produce mixed-generation routing after restart;
5. important read paths are measured and any optimization preserves exact projection parity;
6. due-work discovery is measured under sparse actionable work and optimized only when justified;
7. one deterministic end-to-end campaign proves count and volume strategies, fallback, history and success/distribution analytics compose correctly;
8. v0.3.3 protected guarantees remain intact.

## Protected inherited guarantees

All compatible guarantees from SPEC-007 and earlier versions remain mandatory, especially:

- exact Integer/Rational money and allocation arithmetic;
- at most one unresolved money-moving economic owner per payout;
- ambiguous-after-possible-send remains `UNKNOWN` and retains ownership;
- no cross-provider fallback while unresolved ownership exists;
- provider I/O stays outside atomic/configuration locks;
- one coherent active configuration snapshot/revision is used for a new decision;
- primary allocation, recovery attempts and settlement remain distinct;
- malformed routing-critical input fails closed;
- provider-local idempotency is not cross-provider idempotency;
- restart/replay preserves unresolved economic state and pinned operation semantics;
- additive analytics never mixes incompatible measures/currencies;
- lower-priority health/quality/cost/latency cannot bypass safety, eligibility, admission or allocation authority.

## P0 requirements

### S8-001 — Case-level outcome analytics

The canonical analytics/product surface must answer, without unsafe dimensional mixing:

- first money-moving attempt success count by primary provider;
- eventual payout settlement count by settlement provider;
- provider-attributed route/provider failure count by provider;
- fallback/recovery success count by recovery provider and role;
- unresolved/reconciliation counts separately from terminal failures;
- target-versus-primary-assignment distribution using existing allocation dimensions.

If a rate is exposed, numerator and denominator semantics must be explicit and exact. Do not divide settlement volume by attempt count or combine incompatible count/volume/currency populations.

Status: VERIFIED checkpoint. Reopen only with a new metric counterexample.

### S8-002 — Duplicate recovery-consumer and live interaction ownership safety

`due_work` is observational work discovery, not a lease. Two or more workers may observe the same due item and call resume concurrently.

Required behavior:

- at most one provider dispatch/resolution call is live for one committed operation token inside one process;
- losing workers return safely without creating a second operation, owner, allocation or provider interaction;
- the same guarantee holds after restart and for status-resolution and idempotent same-provider retry;
- a due-work race cannot unlock cross-provider fallback while ownership remains unresolved;
- a duplicate, stale, out-of-order or otherwise non-applying observation for an operation cannot release the process-local guard owned by another still-executing provider invocation;
- adapter exceptions release only the guard owned by the failing invocation;
- normal invocation completion cannot leak/stick the guard;
- callback-before-dispatch/resolution may invalidate a durable pending token when semantically valid, but must not impersonate completion of a different live invocation;
- fresh process restart discards process-local guard identity and rebuilds recovery only from durable operation/contract state.

Use controlled barriers/latches/queues, not sleeps. The implementation may use an invocation token/generation/lease-like value locally, but no distributed lease infrastructure is required.

Status: VERIFIED slice. The observation-during-live-recovery interleaving was reproduced and fixed; candidate exact-head verification/CI and final docs-only CI passed.

### S8-003 — Active-configuration crash consistency

Challenge abrupt termination around configuration publication. After restart the application must either reconcile one coherent externally supplied active generation or fail closed before routing. Silent mixed policy/provider generation is forbidden.

Status: VERIFIED checkpoint by fresh-process campaign. Reopen only with a new crash-phase counterexample.

## P1 requirements

### S8-101 — Measured analytics/explanation query cost

Measure repeated full analytics, typed analytics query, late-payout explanation and fact snapshot cost at 1k, 5k and at least 12.5k payouts. Optimize only a demonstrated bottleneck and preserve exact replay/restart parity.

Status: VERIFIED checkpoint with revision-keyed derived analytics reuse and indexed payout explanation.

### S8-102 — Sparse due-work scale

Measure mostly-terminal histories with sparse actionable due work. Prefer scanning without global sort and sorting emitted work only before adding an index.

Status: VERIFIED checkpoint. No dedicated due index justified by current evidence.

### S8-103 — Executable case-fidelity campaign

One deterministic product-level campaign must demonstrate count-share distribution, skewed volume-share distribution, safe failure/fresh fallback, ambiguous UNKNOWN/same-provider resolution, attempt history, target/actual plus provider/fallback analytics and replay/restart parity.

Status: VERIFIED checkpoint.

### S8-104 — Payout-local history completeness

Product-facing payout/audit/explanation surfaces together preserve every money-moving attempt identity, provider, role, final outcome and relevant observation history after restart without duplicating raw provider payloads into the snapshot.

Status: VERIFIED checkpoint.

## Verification requirements

For every material finding:

- create a deterministic reproducer before or with the fix;
- use independent/oracle/property evidence where metric arithmetic or allocation semantics change;
- use controlled concurrency for recovery/configuration races;
- use a fresh Ruby process for crash/restart boundaries where in-process exception tests are insufficient;
- preserve reproducible seeds/traces for randomized campaigns;
- run focused tests first and the risk-appropriate broad matrix before marking a slice verified;
- for performance work record baseline, changed result, workload, Ruby version and exact revision.

For the reopened S8-002 specifically, verification must cover at least:

1. blocked live status resolution + exact duplicate prior observation + second concurrent resume;
2. blocked live same-provider retry + duplicate/stale/non-applying observation + second concurrent resume;
3. adapter exception cleanup followed by safe retry;
4. accepted observation/completion cleanup with no stuck guard;
5. restart while durable phase is dispatching/resolving, proving local token state is not required for safe continuation;
6. unchanged UNKNOWN ownership and no cross-provider fallback.

## Skeptical closure gate

Finishing known S8 work only creates `VERSION_CANDIDATE`.

A fresh closure pass must inspect the changed production code and challenge at minimum:

- interaction-guard ownership/release under concurrent duplicate/stale observations;
- duplicate recovery workers and stale due-work items;
- success metric numerator/denominator semantics and mixed dimensions;
- crash between configuration publication phases;
- analytics cache invalidation and dynamic `as_of` correctness;
- due-work ordering/replay equivalence;
- count versus volume behavior under skewed amounts/outages;
- UNKNOWN/fallback safety, late success, reversal and restart;
- public API/application parity and history completeness;
- measured scale claims.

Any new material locally solvable P0/P1 returns v0.3.4 to ACTIVE, including a finding discovered after an earlier `VERSION_COMPLETE` publication.

## Stop conditions

Stop only if:

1. v0.3.4 passes a fresh skeptical closure gate on exact HEAD with current CI/evidence and all active normative docs agree; or
2. every remaining mandatory path is genuinely externally blocked and no independent case-relevant work remains; or
3. the authoritative TZ arrives, immediately switching authority to `docs/TZ_RECONCILIATION.md`.

## Explicit non-goals before TZ

Do not introduce microservices, Rails/ORM, Redis/Sidekiq, distributed leases, a database-backed config service, brand-specific PSP schemas, dashboard polish, ML/bandits or generalized rules DSLs unless authoritative requirements or measured evidence make them necessary.
