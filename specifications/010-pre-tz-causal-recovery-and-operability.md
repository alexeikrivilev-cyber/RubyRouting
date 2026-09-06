# SPEC-010 — Pre-TZ Causal Recovery Safety & Operator Readiness

Status: VERSION_COMPLETE at exact pushed HEAD `0988a6248e71f2cbc7a859a4813bac029dfdba4d`.

## Purpose

Extend the completed v0.3.5 baseline only where a new falsifiable hypothesis or direct case-operability gap materially improves **«Умный роутинг выплат»**.

v0.3.5 proved that a live money-moving `initiate` blocks fresh cross-provider assignment even when an independent callback releases durable ownership. v0.3.6 challenges the remaining causal boundary around economically decisive status resolution, process death and unclassified transport completion, then closes two narrow product-readiness gaps: configuration ingress and deferred recovery execution.

## Protected inherited guarantees

All compatible guarantees from SPEC-009 and earlier remain mandatory, especially exact money/allocation arithmetic, one economic intent, UNKNOWN safety, immutable provider operation identity, hard admission/allocation authority, invocation-owned interaction guards, v0.3.5 live-initiate fence, coherent configuration generations, replay/restart equivalence, dimension-safe analytics and canonical application paths.

Do not redesign a protected mechanism without new evidence.

## P0 requirements

### S10-001 — Economically decisive status resolution blocks premature fallback

A provider status lookup may be technically read-only but economically decisive because it can establish that the pinned provider operation succeeded.

Deterministic reproducer:

1. provider A operation becomes UNKNOWN and is eligible for `resolve`;
2. worker A starts `resolve` and blocks inside provider I/O;
3. an independent same-operation callback produces lifecycle evidence that currently releases ownership;
4. canonical continuation attempts to route provider B before `resolve(A)` returns;
5. `resolve(A)` is released and returns SUCCESS.

Required invariant:

> Provider B must not begin money-moving execution while an unresolved live interaction can still establish a conflicting monetary effect for provider A, unless authoritative provider semantics prove the interaction economically irrelevant.

The implementation may still distinguish read-only from money-moving interactions for accounting/concurrency. It must not equate “read-only” with “safe to ignore for fallback”.

### S10-002 — Process death cannot erase unresolved dispatch causality

Challenge:

`attempt_started(A)`
→ independent safe-release callback is durably accepted
→ local A invocation has not durably completed/classified
→ process dies
→ fresh process restores facts
→ canonical continuation attempts B.

Required invariant:

A fresh process must not infer safe cross-provider fallback solely because the process-local token disappeared if durable evidence does not establish that the previously started provider interaction is economically closed.

Acceptance requires an actual fresh-process or deterministic crash/journal campaign, exact operation/ownership/fact assertions and restart/replay parity.

Do not solve this with Redis/distributed leases. Prefer the smallest replayable causal-completion evidence necessary for single-process-plus-restart safety.

### S10-003 — Unclassified timeout/exception cannot manufacture safe release

When an independently delivered release observation races a provider interaction and the local interaction then exits via raw timeout/programming/adapter exception, the exception itself is not `definitely_not_sent`.

Required behavior:

- explicit `ProviderTransportResult/Error` classification keeps existing semantics;
- raw timeout/exception does not become safe causal proof;
- if economic uncertainty remains, canonical state stays pinned/reconciliation-safe rather than immediately opening B;
- process-local token cleanup remains owner-only and cannot leak;
- restart preserves the conservative result.

### S10-004 — Late monetary evidence remains explicit and non-duplicative

After any release/callback/restart race, a later A success or ambiguous possible-send result must never be silently overwritten. If provider B has not legally started, the system must settle/reconcile according to canonical rules; if a deliberately supported provider-specific causal proof permits B earlier, contradictory evidence must be explicit and testable.

## P1 requirements

### S10-101 — Canonical typed configuration ingress

The engine is configurable internally but the product lacks a transport-neutral input boundary for operator/judge configuration.

Required outcome, only after P0 closure:

- strict Hash/JSON-compatible input maps into existing typed `RoutingConfiguration`, policies, provider opportunities and nested value objects;
- canonical round-trip: `decode(configuration.to_h).to_h == configuration.to_h` for representative count/volume configurations;
- unknown/malformed/duplicate semantic fields fail closed;
- compiler diagnostics remain authoritative;
- publication goes through `Application::Commands#apply_configuration`;
- no provider-brand or judge-specific schema is invented.

An HTTP write endpoint is optional before TZ; the transport-neutral boundary is the requirement.

### S10-102 — Bounded canonical recovery executor

The product exposes `due_work` and `resume`, but deferred recovery currently requires external orchestration boilerplate.

Add or prove unnecessary a small application-level executor that:

- obtains current due work through canonical queries;
- advances each item only through canonical `resume`/Service;
- has explicit bounds (`limit`/one pass), deterministic ordering and structured results;
- owns no routing, provider selection or economic state;
- remains safe when multiple callers observe the same due item because Coordinator remains the correctness authority;
- introduces no queue, background thread, lease or scheduler infrastructure.

### S10-103 — Exact-case and operator composition

After P0/P1 changes, rerun one deterministic composition demonstrating:

`typed configuration -> count/volume routing -> safe/ambiguous failure -> deferred recovery execution -> fallback/UNKNOWN resolution -> full attempt history -> target/actual + success analytics -> restart/replay parity`.

### S10-104 — Evidence-gated smart-routing changes

Do not change recovery objective ordering, tolerance-vs-quality semantics, quality maturity defaults or allocation accounting point without authoritative scoring/TZ or a measured product hypothesis. Record them as reconciliation/optimization seams, not pre-TZ mandatory work.

## Verification requirements

For every P0:

- deterministic barrier/queue/latch; no sleep-based races;
- preserve a pre-fix reproducer when a bug is confirmed;
- assert exact provider A/B calls, attempt/operation IDs, allocation commits, ownership acquire/release, interaction/observation facts, settlements/conflicts and final state;
- run actual fresh-process evidence for process-death semantics;
- test live, replay and restart parity;
- challenge authoritative and non-authoritative provider ordering;
- finish with independent skeptical review after known work is green.

For configuration ingress, add strict round-trip/unknown-field/boundary tests. For recovery executor, test no alternate routing semantics and exact bounded work results.

## Candidate skeptical gate

Known work reaching green creates only `VERSION_CANDIDATE`.

Fresh discovery must challenge at least:

- `resolve(A)` live + release callback + attempted B + late SUCCESS/UNKNOWN;
- process death after release while dispatch completion is not durable;
- raw timeout/exception after release;
- initial/retry v0.3.5 races remain safe;
- authoritative sequence dominance and stale callbacks;
- restart/config/provider removal/stale work;
- configuration ingress round-trip and source-of-truth integrity;
- recovery executor duplicate-worker behavior;
- count/volume allocation, analytics and API/demo parity;
- unsupported multi-process/exactly-once claims.

Any material locally solvable P0/P1 returns v0.3.6 to ACTIVE.

## Explicit non-goals before TZ

No microservices, Rails/ORM, Redis/Sidekiq, distributed leases, DB control plane, PSP-brand core schemas, generalized rule DSL, ML/bandits, new recovery objective modes, speculative tolerance/quality tradeoff changes, dashboard polish or cosmetic decomposition without new evidence.

## Stop conditions

v0.3.6 is `VERSION_COMPLETE` at the exact HEAD above: all S10 P0/P1 are verified/falsified with current evidence, fresh skeptical discovery is clean, exact-head CI is green and all authority documents agree. If new material evidence appears, reopen the version as `ACTIVE`; when authoritative TZ arrives, switch authority to reconciliation.
