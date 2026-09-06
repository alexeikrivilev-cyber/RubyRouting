# Decisions — v0.3.7 Case Surface & Semantic Convergence

Status: VERSION_COMPLETE decision supplement for SPEC-011.

Compatible decisions from v0.3.6 and earlier remain inherited.

## D-401 — v0.3.6 closure has two exact revisions

Status: accepted.

Decision: record v0.3.6 last material/candidate revision as `0988a6248e71f2cbc7a859a4813bac029dfdba4d` and final docs-only closure HEAD as `c1dcd5a1b8bb4adc199670b035ddf8342a1bd956`. GitHub Actions run `33630914704` is green on the closure HEAD. Do not call the material revision the current branch HEAD after a later closure commit exists.

## D-402 — operator runners fail closed on corruption/invariant failure

Status: accepted target.

Decision: a bounded application runner may structure expected provider/operational failures per item, but it must not normalize durable corruption, impossible state or programming/invariant failures into routine operator results. Such failures must surface/abort according to the canonical application error contract.

The exact recoverable error set must be derived from real Service behavior and tests rather than guessed from class names.

## D-403 — RecoveryExecutor time has one explicit meaning

Status: accepted target.

Decision: `as_of` cannot simultaneously mean “due-work scan time” and “domain execution time” unless both selection and resume actually use that same canonical timestamp. v0.3.7 must either make it explicitly scan-only with safe bounds/naming or thread one evaluation timestamp through canonical Service/Coordinator without creating a second time authority.

## D-404 — outcome release safety is not causal release authority

Status: accepted.

Decision: `NormalizedOutcome#safe_to_release?` describes the normalized outcome, not universal proof that an independent observation causally supersedes all outstanding/uncertain provider interactions.

If a provider can supply stronger authoritative rejection evidence, model that through explicit provider/event semantics only after deterministic safety/liveness evidence. Do not weaken generic UNKNOWN behavior.

## D-405 — repeated semantic divergence justifies narrow shared predicates

Status: accepted target.

Decision: v0.3.6 repeatedly found current-owner, causal-hold/completion and identity divergence between live, restore and replay paths. v0.3.7 may extract a small pure/shared semantic authority for these rules if inspection proves it removes duplicate decisions.

This is not authorization for a large Coordinator split or new workflow/state owner.

## D-406 — configuration mutation is an adapter over the existing source of truth

Status: accepted target.

Decision: the preferred product write surface is a strict bounded HTTP `PUT /v1/configuration` that delegates to `RoutingConfiguration.decode -> compile -> Service#apply_configuration`. HttpApp owns parsing/serialization only. No second policy registry/provider catalog/configuration model is permitted.

## D-407 — recovery execution is an adapter over RecoveryExecutor

Status: accepted target.

Decision: the preferred product entrypoint is a bounded HTTP `POST /v1/recovery/run` that delegates to `Service#recovery_executor.run`. It does not select providers, schedule background jobs, acquire leases or own economic state.

## D-408 — the primary demo must be canonical product composition

Status: accepted target.

Decision: the runnable judge/demo scenario should promote existing application/operator composition rather than reimplement behavior. It must use the typed configuration boundary, Service, RecoveryExecutor and Queries and visibly prove count/volume, fallback, UNKNOWN/recovery, attempts and analytics.

## D-409 — causal hold must be publicly explainable without exposing internals

Status: accepted target.

Decision: internal `causal_hold` may remain redacted. Public explanation should expose a bounded safe reason/disposition derived from canonical facts/state so `safe_to_release=true` plus `applied=false` is understandable. Do not expose raw provider/recipient-sensitive data.

## D-410 — no pre-TZ smart-routing redesign without evidence

Status: accepted.

Decision: do not change recovery objective modes, allocation accounting point, tolerance-vs-quality ordering, quality statistical defaults or add ML/bandits merely because v0.3.7 is product-facing. These remain explicit TZ/scoring seams.

## D-411 — any new financial P0 preempts case-surface work

Status: accepted.

Decision: v0.3.7 opens with no confirmed financial P0. If deterministic skeptical review reproduces an economic safety defect, immediately prioritize it above executor, HTTP, demo and explainability work and keep the version ACTIVE until resolved.

## D-412 — provider failures are typed at the provider boundary

Status: accepted and implemented.

Decision: `RecoveryExecutor` may report a per-item error only when the
canonical provider invocation boundary has classified the failure as a raw
provider adapter/transport execution failure after the durable operation was
started and its interaction guard can be released. `Orchestrator` raises
`ProviderExecutionError` with the original exception retained as
`original_error` and `cause`. Corruption, configuration drift, invariant and
programming failures outside that boundary retain their original class and
abort the bounded pass. The executor owns no retry or outcome
reclassification.

## D-413 — RecoveryExecutor `as_of` is scan-only

Status: accepted and implemented.

Decision: the bounded recovery runner samples the canonical service current
time, uses `as_of` only for selecting due work, rejects an explicit future
scan timestamp, and delegates each selected item to `Service#resume` without
injecting a second execution timestamp. The compatibility result field
`as_of` and its `scan_as_of` alias identify the scan boundary, not the time at
which every mutating resume ran. This keeps recovery scheduling and its
Coordinator clock authority unchanged.

## D-414 — authoritative observation order is not causal completion

Status: accepted and evidence-closed for v0.3.7.

Decision: an independent provider observation carrying `safe_to_release=true`
does not release an UNKNOWN owner merely because the provider has no
status-lookup/idempotent-retry capability or because its event sequence is
newer. `authoritative_sequence` orders provider observations; it does not
assert that the owning money-moving invocation completed or that all possible
effects of that invocation are superseded. The generic kernel therefore keeps
the causal hold and blocks cross-provider fallback until owning completion,
supported recovery evidence or explicit reconciliation resolves the operation.

Rationale: a generic boolean or sequence number cannot safely infer causal
dominance from an independent callback. The deterministic v0.3.7 campaign
proved both non-authoritative and sequence-authoritative variants preserve
owner, allocation, attempt, observation and replay facts without starting B.
Adding a release-proof field without an actual provider contract would either
be unverifiable or weaken UNKNOWN safety.

## D-415 — HTTP exact values use the canonical Rational transport form

Status: accepted and implemented.

Decision: the operator configuration surface serializes `Rational` values as
the canonical non-negative `"numerator/denominator"` string already accepted
by `RoutingConfiguration.decode`. The HTTP representation must therefore
round-trip `RoutingConfiguration#to_h` for volume tolerance and share fields
without Float conversion or a second ad hoc Rational schema. Internal
fact/public-audit encodings that intentionally use tagged or
numerator/denominator objects remain unchanged.

Rationale: the first PTZ7-101 HTTP round-trip test exposed a real seam where
`json_safe` emitted a hash that the strict decoder rejected. The smallest
coherent fix was to align the transport adapter with the existing canonical
decoder contract and verify exact values through GET→PUT.

## D-416 — live and durable causal predicates remain separate authorities

Status: accepted and evidence-closed.

Decision: do not extract the live Coordinator causal-release predicate into a
single generic helper merely because it shares names with ObservationLedger,
restore and Replay checks. The process-local in-flight interaction token is
live-only evidence; durable observations, fact order, current ownership and
schedule linkage are separate restart-safe evidence. Each layer must retain
its own boundary while parity tests constrain their externally visible result.

Rationale: the PTZ7-004 inventory found no semantics-preserving shared pure
predicate. Merging the live token guard into durable logic would either make
Replay pretend to know live state or weaken the provider-I/O safety boundary.
The existing live/restore/replay and fresh-process regressions provide the
appropriate mechanical parity evidence.

## D-417 — the runnable demo is a projection adapter, not a second router

Status: accepted and implemented.

Decision: the default judge-facing demo composes a decoded
`RoutingConfiguration`, `Service`, `RecoveryExecutor` and `Queries`, then
projects bounded machine-readable evidence. It may choose deterministic sample
inputs and simulated provider outcomes, but it may not calculate provider
selection, allocation, recovery legality or analytics independently.

The report preserves dimensioned target/actual and settlement measures rather
than flattening incompatible count/volume/currency populations. It omits
runtime timestamps so repeated runs are byte-stable without pretending to
provide production-scale or distributed execution guarantees.

## D-418 — causal explanation exposes disposition, not internal hold state

Status: accepted and implemented.

Decision: the public explanation may expose a bounded disposition such as
`awaiting_causal_completion` only when the canonical replayed current status is
unresolved, the latest observation is safe-to-release and unapplied, it is
linked to the current owner, and it is not marked as a conflict. A blocked
reconciliation state uses `awaiting_reconciliation`; otherwise no causal wait
disposition is emitted. The internal `causal_hold` flag and sensitive payloads
remain private.

Rationale: operators need to understand why a safe release did not open a
fallback, but an explanation must not become a second lifecycle reducer or
mislabel a late observation for an old operation. The disposition is derived
from the existing explanation/replay projection and is covered at direct and
HTTP boundaries with privacy assertions.

## D-419 — the recovery batch bound has one owner

Status: accepted and implemented.

Decision: `RecoveryExecutor::MAX_BATCH_SIZE` is the canonical maximum for one
bounded recovery pass. The HTTP adapter references that constant instead of
maintaining a second numeric limit, so direct application callers and the
operator surface have the same pre-execution bound.

Rationale: a bounded product surface must not become unbounded merely because
the transport adapter is bypassed. The bound limits work selection/results;
provider selection, recovery legality and duplicate safety remain owned by the
existing Service/Coordinator path.

## D-420 — provider execution errors are operator-safe

Status: accepted and implemented.

Decision: a bounded recovery pass may return a typed provider execution item
error, but its message is the stable `provider execution failed` text. The
adapter-controlled original exception remains available only inside the Ruby
boundary and is never serialized into the operator HTTP response.

Rationale: provider adapters can include recipient, credential or raw response
data in exception messages. Error taxonomy and resumable payout state remain
visible without making arbitrary provider text part of the public product
contract.
