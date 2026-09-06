# SPEC-009 — Pre-TZ Economic Effect Safety & Adapter Readiness

Status: ACTIVE

## Purpose

Continue pre-TZ work only where a new falsifiable hypothesis can materially improve the Hack.Genesis «Умный роутинг выплат» case. v0.3.4/SPEC-008 is a completed protected baseline. v0.3.5 targets the remaining boundary between live provider execution, durable economic ownership and external provider observations, then closes a small set of provider-adapter readiness gaps.

The public case remains the authority for pre-TZ relevance: configurable count/volume distribution, safe fallback to the next suitable provider, complete attempt history and final distribution/success analytics.

## Version Goal

Prove that no concurrent callback, recovery action or late provider completion can open a second money-moving provider path while an earlier money-moving invocation is still live, and make the generic provider boundary operationally credible without introducing speculative distributed infrastructure.

## Protected inherited guarantees

All compatible guarantees from SPEC-008 and earlier remain mandatory, especially:

- exact Integer/Rational money and allocation arithmetic;
- one payout submission is one economic intent;
- at most one unresolved economic owner per payout;
- ambiguous-after-possible-send is UNKNOWN unless provider semantics prove otherwise;
- UNKNOWN blocks cross-provider fallback;
- same-provider retry/status resolution is distinct from fresh fallback;
- provider-local idempotency is not cross-provider idempotency;
- hard eligibility/admission precedes allocation/optimization;
- primary allocation, recovery and settlement are distinct accounting views;
- provider operation identity/payload/contract is immutable and restart-safe;
- live provider interaction guards are invocation-owned and process-local;
- active configuration is one coherent immutable generation per decision;
- additive analytics never mixes incompatible measure/currency populations;
- provider I/O stays outside Coordinator/configuration locks;
- replay/restart reconstructs unresolved economic state exactly;
- public audit/explanation surfaces remain privacy-safe;
- deterministic/property/model/concurrency/fault evidence remains reproducible.

Do not redesign a protected mechanism without a new reproducer or measurement.

## P0 requirements

### S9-001 — Live money-moving invocation blocks fresh economic ownership

A provider callback may arrive independently while a provider `initiate` call for the same payout/operation is still executing. The callback may even normalize to a safe-to-release failure. Releasing durable ownership is not sufficient proof that the live money-moving invocation can no longer produce an economic effect.

Required invariant:

> While a money-moving provider invocation is live for a payout inside the process, no new cross-provider money-moving assignment may be committed for that payout unless provider semantics explicitly prove the live invocation is economically impossible to succeed.

At minimum prove this for:

1. initial primary `assign/initiate` blocked in provider A;
2. same-provider idempotent `retry_same/initiate` blocked in provider A after UNKNOWN;
3. independent `safe_route_failure` callback with `safe_to_release=true` for the same operation;
4. independent `temporary_provider_failure` with explicit `safe_to_release=true` where supported;
5. terminal payout failure arriving while a live money-moving invocation exists.

A losing/racing caller may defer/wait/reconcile, but must not start provider B while provider A's live money-moving invocation can still succeed.

Status: OPEN — deterministic reproducer required before implementation.

### S9-002 — Late live-invocation completion is economically safe

After an independent callback changes canonical lifecycle state, the still-running money-moving invocation may later return:

- success;
- definitely-not-sent failure;
- ambiguous transport result;
- adapter/contract exception.

Required behavior:

- provider B was not started before the live invocation ceased to be economically live;
- late success never becomes an unnoticed second effect;
- contradictory late monetary evidence becomes settlement or explicit reconciliation/conflict according to the canonical state, never silent overwrite;
- a genuine definitely-not-sent completion can unblock safe fallback exactly once;
- UNKNOWN remains pinned when ambiguity survives;
- provider interaction tokens are released only by their owner and cannot remain stuck after normal/exception completion.

Status: OPEN.

### S9-003 — Observation release authority is explicit and conservative

`NormalizedOutcome#safe_to_release?` describes normalized provider evidence. It must not be interpreted as a universal causal statement that every concurrently executing money-moving call is already impossible to succeed.

The implementation must make the distinction explicit between:

- lifecycle evidence for an operation;
- the invocation that produced an observation, when known;
- an independently delivered callback/webhook;
- a currently live money-moving invocation;
- an authoritative provider ordering/sequence contract.

Do not invent a broad provider-specific proof model before the TZ. Prefer the smallest conservative rule that closes S9-001 and remains compatible with adapters that have authoritative sequence semantics.

Status: OPEN.

## P1 requirements

### S9-101 — Provider adapter bounded-execution contract

The generic core must not pretend it can safely cancel arbitrary Ruby network I/O. Production adapters own connect/read/request deadlines and transport classification.

Required outcome:

- document the adapter obligation to return/raise within configured operational bounds;
- classify timeout/connection uncertainty as `definitely_not_sent` or `ambiguous_after_possible_send` only when provider semantics justify it;
- never use unsafe thread termination as a financial correctness primitive;
- provide or strengthen adapter contract/conformance tests where useful;
- preserve operation TTL/deadline as economic/recovery semantics, distinct from low-level socket timeout configuration.

No brand-specific PSP client is required before the authoritative TZ unless supplied by the case.

Status: OPEN.

### S9-102 — Adjacent ordering/restart campaign

Challenge the new live-money-moving fence against:

- authoritative and non-authoritative provider sequence semantics;
- callback-before-provider-return;
- callback-before-start-token consumption;
- adapter exception after callback;
- process crash/restart after dispatch was started;
- provider/configuration change while an unresolved operation remains pinned;
- stale decision commits and stale due-work items.

Fresh restart must not persist process-local interaction identity. It must continue to rely on durable operation phase/contract/ownership and existing status-lookup/idempotent-retry safety.

Status: OPEN.

### S9-103 — Case-level composition regression

After S9 P0 changes, rerun one deterministic canonical product campaign covering count distribution, volume distribution, safe fallback, UNKNOWN resolution, multi-attempt history, target/actual analytics, provider/fallback success analytics and replay/restart parity.

Status: OPEN.

### S9-104 — Evidence-gated maintainability and performance

Do not refactor Coordinator/Analytics merely because they are large. Do not add indexes/caches merely because history grows.

A structural or performance change is allowed only when:

- a new correctness invariant has a clear owner that extraction would simplify; or
- a current benchmark/reproducer proves material cost on a case-relevant path.

The preferred pre-TZ outcome may be no production change.

Status: OPEN as a gate, not a feature requirement.

## Verification requirements

For every P0 finding:

- use controlled barriers/queues/latches, never sleeps;
- reproduce or falsify current behavior before broad implementation;
- assert provider A/B call counts, operation/ownership/allocation facts and final lifecycle state;
- test both initial assignment and idempotent same-provider retry;
- prove no fresh cross-provider assignment occurs while a money-moving invocation is live;
- include late success and late safe failure completions;
- run focused concurrency/recovery tests first;
- then run restart/fault/property/model adjacency and the full verification matrix;
- finish with an independent skeptical pass on exact candidate code.

## Candidate skeptical gate

Known work reaching green creates only `VERSION_CANDIDATE`.

The fresh pass must challenge at least:

- independent safe-release callback during live initial `initiate`;
- independent safe-release callback during live idempotent retry;
- late success after callback release;
- stale/duplicate callback and token ABA;
- status-lookup interaction versus money-moving interaction semantics;
- transport timeout/exception classification;
- UNKNOWN followed by attempted fallback;
- restart while dispatching/resolving;
- configuration/provider removal while operation is unresolved;
- count/volume allocation and outcome analytics after the safety change;
- API/demo path parity;
- unsupported multi-process/exactly-once claims.

Any material locally solvable P0/P1 keeps v0.3.5 ACTIVE.

## Explicit non-goals before TZ

Do not introduce microservices, Rails/ORM, Redis/Sidekiq, distributed leases, a database-backed control plane, provider-brand core schemas, generalized rules DSL, ML/bandits, dashboard polish or horizontal multi-process exactly-once machinery unless authoritative requirements or measured evidence require them.

## Stop conditions

Stop this pre-TZ version only when:

1. all S9 P0/P1 requirements are verified or explicitly falsified with evidence;
2. a fresh skeptical pass finds no material locally solvable case-relevant gap;
3. exact candidate verification and current CI are green;
4. all active normative documents agree; or
5. the authoritative TZ arrives, immediately switching authority to `docs/TZ_RECONCILIATION.md`.
