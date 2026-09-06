# Pre-TZ Architecture Delta — v0.3.6

Status: VERSION_COMPLETE design at exact pushed HEAD `0988a6248e71f2cbc7a859a4813bac029dfdba4d`.

This document is a delta over the completed v0.3.5 architecture. It does not replace historical architecture records.

## 1. New safety distinction: execution type vs economic decisiveness

v0.3.5 introduced a useful interaction token attribute: whether a call is money-moving. Keep that distinction.

v0.3.6 adds a separate question:

> Can the unresolved result of this interaction still establish or preserve a monetary effect that would conflict with fresh cross-provider movement?

Examples:

- `assign/initiate`: money-moving and economically decisive;
- `retry_same/initiate`: money-moving and economically decisive;
- status `resolve`: technically read-only but potentially economically decisive because it can report SUCCESS/UNKNOWN for the pinned operation.

Do not encode “read-only” as “irrelevant to fallback”.

## 2. Durable causal completion boundary

Process-local invocation tokens are useful for same-process serialization but disappear at process death. A fresh process can only trust durable facts.

The existing durable lifecycle knows operation phases and observations, but an independently delivered release callback is not necessarily proof that an already-started local provider interaction concluded.

If S10-002 reproduces, the minimal target architecture should make durable history capable of distinguishing enough of the following to fail closed:

- provider interaction/dispatch started;
- observation arrived independently;
- observation/result was produced by the owning invocation;
- owning interaction conclusively completed/classified;
- lifecycle ownership released/settled/terminated.

This does **not** imply a distributed lease. It is causal audit state for single-process-plus-restart correctness.

Possible implementations include a narrow interaction-completion/provenance fact or a pending-release/reconciliation condition derived from existing start evidence. Choose only after the reproducer demonstrates what information is actually missing.

## 3. Provider observation provenance

Current `apply_observation` already receives an invocation token when the observation comes from the local owning provider call and receives no token for external reconcile. That boundary may be enough to publish narrow durable provenance if needed.

Provider-specific authoritative sequence remains separate. Sequence orders provider events; it does not automatically establish causal dominance over a concurrently executing request unless the provider contract explicitly says so.

Local interaction duration is telemetry, not provider event identity. It may be
different or absent when one provider event is observed through an external
callback versus the owning invocation, while provider linkage, event outcome,
ordering and transport classification remain identity-checked.

Application-synthesized transport observations additionally carry the
canonical interaction action and a durable-derived provider-interaction
ordinal. This keeps repeated initiate/retry/resolve exchanges distinct without
inventing provider event semantics or using a process-local counter as durable
truth.

Local interaction duration is telemetry, not provider event identity. It may be
different or absent when one provider event is observed through an external
callback versus the owning invocation, while provider linkage, event outcome,
ordering and transport classification remain identity-checked.

## 4. Timeout semantics

Keep three layers distinct:

1. adapter socket/connect/read/request deadline — operational bound;
2. explicit transport classification — `definitely_not_sent` vs `ambiguous_after_possible_send`;
3. operation TTL/deadline/recovery budget — economic recovery semantics.

Raw timeout/programming exception is not a transport classification. If a raw exception occurs after an independent release, the system must not infer economic closure merely because the local Ruby call returned via exception.

## 5. Configuration ingress

Existing typed domain/configuration objects remain the source of semantic truth.

Target boundary:

`Hash/JSON-compatible canonical input`
→ `strict decoder`
→ `RoutingPolicy / ProviderOpportunity / nested typed values`
→ `RoutingConfiguration`
→ `ConfigurationCompiler`
→ `Commands#apply_configuration`.

The decoder must round-trip the existing canonical `to_h` representation where feasible. It must not invent PSP/judge fields or create another configuration source of truth.

## 6. Recovery executor

Target product flow for deferred work:

`Queries#due_work(as_of, limit if supported)`
→ `RecoveryExecutor one bounded deterministic pass`
→ `Service#resume(payout_id)`
→ existing Orchestrator/Coordinator.

The executor is orchestration glue only. It owns no provider choice, budgets, retries or lifecycle transitions. Correctness under duplicate workers stays in Coordinator.

## 7. Canonical flow after v0.3.6

`Intent`
→ `Typed active configuration`
→ `Eligibility / Admission`
→ `Allocation authority`
→ `Recovery legality / optimization`
→ `Atomic commit`
→ `Provider interaction start`
→ `Local/external observation provenance`
→ `Lifecycle + causal completion/reconciliation`
→ `Durable facts`
→ `History/analytics`
→ `Due-work query`
→ `Bounded canonical recovery execution`.

## 8. Non-goals

No distributed exactly-once, DB/Redis queue, generalized causal vector clock, PSP-specific client, new allocation strategy, recovery objective redesign or broad Coordinator split before evidence/TZ.
