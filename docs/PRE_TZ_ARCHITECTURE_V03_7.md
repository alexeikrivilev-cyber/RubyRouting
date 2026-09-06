# Pre-TZ Architecture Delta — v0.3.7

Status: VERSION_COMPLETE design record for SPEC-011.

This is a narrow delta over the completed v0.3.6 architecture. It does not replace historical architecture records.

## 1. Architectural objective

Keep the proven financial kernel unchanged while making operator entrypoints and repeated causal semantics converge on the same existing authorities.

Target product flow remains:

`transport/demo -> Application::Service -> Commands/Queries/RecoveryExecutor -> Coordinator/typed domain -> durable facts -> projections`.

No new endpoint, demo or runner may bypass this flow.

## 2. RecoveryExecutor boundary

`RecoveryExecutor` is an application runner, not a workflow engine.

It may:

- query bounded due work;
- call canonical `Service#resume`;
- aggregate bounded structured outcomes.

It may not:

- choose providers;
- mutate Coordinator directly;
- reinterpret transport/provider outcomes;
- own durable schedule/lease state;
- swallow durable corruption or impossible-state failures as routine item errors.

The time contract must have one explicit meaning. A scan timestamp and a domain execution timestamp are separate concepts unless the canonical Service intentionally accepts one shared evaluation time.

## 3. Causal release semantics

Keep these concepts separate:

1. `safe_to_release` — normalized outcome property;
2. authoritative provider event ordering;
3. causal authority over a previous uncertain interaction;
4. current economic owner/operation phase;
5. owning-invocation completion/classification.

v0.3.6 uses conservative causal holds when independent release evidence cannot safely dominate unresolved provider causality. v0.3.7 must not weaken that default merely for progress.

If a provider can truly prove that an old operation was rejected and no contradictory monetary effect can later emerge, represent that as an explicit typed/provider-semantic proof rather than reinterpreting generic `safe_to_release`.

## 4. Shared causal semantic authority

Repeated v0.3.6 bugs showed that live, restore and replay separately encoded overlapping rules around:

- canonical causal identities;
- current-owner linkage;
- held-observation legality;
- causal completion legality;
- duplicate owning completion.

Preferred architecture:

`canonical causal value/predicates`
→ consumed by live ObservationLedger/Coordinator
→ consumed by durable restorer
→ consumed by Replay validation/projection.

The shared layer should be pure and stateless where possible. It does not own lifecycle state or append facts.

Do not create a generic workflow engine or split Coordinator for file size.

## 5. Configuration product surface

Preferred write path:

`PUT /v1/configuration`
→ HttpApp strict request parsing/bounds
→ `RoutingConfiguration.decode`
→ existing compiler
→ `Service#apply_configuration`
→ existing atomic configuration publication.

HttpApp may serialize diagnostics/revision/current configuration. It must not construct an alternate policy/provider model.

Invalid decode/compile must be zero-publication.

## 6. Recovery product surface

Preferred one-pass path:

`POST /v1/recovery/run`
→ strict limit validation
→ `Service#recovery_executor.run`
→ canonical due-work query
→ canonical resume.

No polling thread, queue, background scheduler or lease is part of v0.3.7.

## 7. Demo architecture

The judge/demo executable is a composition adapter over real application primitives.

It may create simulators and test/example configuration, but routing behavior comes only from the same `RoutingConfiguration.decode`, Service, RecoveryExecutor and Queries used by the product.

Machine-readable output should project:

- configuration/revision;
- count/volume target and actual values;
- payout/attempt lifecycle;
- fallback/UNKNOWN/recovery evidence;
- success analytics;
- explanation/reason for intentionally deferred fallback.

No demo-only allocator, fallback loop or analytics formula.

## 8. Public explanation

Internal causal-hold fields may remain redacted. Expose only a safe derived disposition/reason code sufficient to explain product behavior, such as waiting for causal completion/reconciliation.

The reason must be produced from canonical state/facts/projections and must not leak recipient or provider-sensitive payload.

## 9. Performance/state discipline

No new durable state is expected for v0.3.7 unless S11-003 finds a real liveness/safety gap that cannot be expressed by existing facts.

HTTP/demo/executor surfaces are bounded. Any cache is derived and non-authoritative.

Semantic convergence should reduce duplicate rule ownership; it should not introduce new scanning or locking on provider I/O.

## 10. Multi-process boundary

v0.3.7 remains a single-process correctness reference with restart durability. It does not claim distributed exactly-once or cross-process live-invocation serialization.

Do not add Redis/DB leases without authoritative requirement.
