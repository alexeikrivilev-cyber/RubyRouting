# Decisions — v0.3.5 Economic Effect Safety & Adapter Readiness

Status: ACTIVE decision supplement for SPEC-009.

This file inherits all compatible accepted decisions from v0.3.4 and earlier. It changes authority only where stated below.

## D-351 — v0.3.4 is a protected completed baseline

Status: accepted.

Decision: SPEC-008/v0.3.4 remains `VERSION_COMPLETE` historical baseline. v0.3.5 may reopen a mechanism only when a new reproducer or measurement demonstrates a material gap.

## D-352 — live invocation and economic ownership are independent safety dimensions

Status: accepted as v0.3.5 hypothesis/target.

Decision: absence of durable economic ownership is not by itself sufficient to permit fresh cross-provider money movement if a previous provider `initiate` invocation is still live and can independently produce an economic effect.

Rationale: an independently delivered callback may release lifecycle ownership while the request that can move money is still executing outside the Coordinator lock.

## D-353 — money-moving live interaction fences fresh cross-provider assignment

Status: proposed normative rule pending reproducer/fix verification.

Decision: while a live `assign` or `retry_same` provider `initiate` exists for a payout, a fresh provider assignment must fail closed/defer unless provider semantics explicitly prove the live invocation cannot succeed.

Status lookup/resolution is not itself money-moving and must not be over-serialized merely because it is a provider interaction.

## D-354 — `safe_to_release` is lifecycle evidence, not universal causal dominance

Status: accepted.

Decision: `NormalizedOutcome#safe_to_release?` may authorize lifecycle release under normalized provider semantics, but does not automatically prove that every concurrent money-moving invocation for that payout has ceased to be economically live.

Rationale: provider event ordering and request execution are distinct dimensions, especially for independently delivered webhooks and providers without authoritative sequence semantics.

## D-355 — prefer a narrow live-money-moving fence over new provider-specific causal metadata

Status: accepted as implementation preference.

Decision: first attempt the smallest conservative solution using the existing process-local invocation ownership model. Do not add generalized causal tokens, distributed leases or provider-event vector clocks unless a deterministic counterexample proves the narrow fence insufficient.

## D-356 — late contradictory success is reconciliation-grade evidence

Status: accepted.

Decision: if canonical lifecycle state was released/terminated by independent evidence while a protected live money-moving invocation later returns success, the product must not silently overwrite history or route a second provider during the live interval. Contradictory late success is explicit settlement/conflict/reconciliation evidence according to canonical lifecycle rules.

## D-357 — adapter network deadlines belong to adapters

Status: accepted.

Decision: provider adapters own connect/read/request timeouts and transport uncertainty classification. Generic core code must not use unsafe asynchronous thread termination as a substitute for provider-specific timeout semantics.

Operation TTL/deadline remains an economic/recovery contract and is distinct from low-level network timeout configuration.

## D-358 — no pre-TZ distributed exactly-once claim

Status: accepted.

Decision: process-local live interaction ownership/fencing is not a cross-process guarantee. Do not introduce Redis/database/distributed leases before the authoritative process/deployment contract exists. Documentation and demos must not claim distributed exactly-once execution.

## D-359 — architecture/performance work remains evidence-gated

Status: accepted.

Decision: large Coordinator/Analytics files, history growth or aesthetic concerns are not enough to justify pre-TZ refactoring. Extract only a clear invariant owner or optimize only a measured case-relevant bottleneck.
