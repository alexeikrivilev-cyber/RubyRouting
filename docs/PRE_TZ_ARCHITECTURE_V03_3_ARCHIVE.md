# Pre-TZ Architecture Delta — v0.3.3

Status: ACTIVE

This is the current architecture delta for SPEC-007. It inherits the proven v0.3.2/v0.3.1 structure documented in `docs/PRE_TZ_ARCHITECTURE.md` and `docs/CURRENT_ARCHITECTURE.md` and changes only areas where the skeptical review found a real semantic source-of-truth or restart problem.

If this document conflicts with the older pre-TZ architecture for active v0.3.3 work, SPEC-007 and this delta take precedence. Older architecture remains historical baseline/rationale.

## 1. Canonical flow

`Payout Intent`
→ `Canonical RoutingContext`
→ `ActiveConfigurationSnapshot(revision)`
→ `Policy Resolution from snapshot`
→ `Provider Compatibility / Functional Opportunity from same snapshot`
→ `Operational Admission`
→ `Allocation Authority`
→ `Recovery Legality / Portable Due Timing / Role`
→ `Constrained Optimization`
→ `Atomic Decision + Ownership + Reservations`
→ `Provider Operation`
→ `Telemetry + Normalized Observation`
→ `Lifecycle / Recovery / Reconciliation`
→ `Durable Facts + Working State`
→ `Dimensioned Analytics / Explanation / Control Queries`.

The key v0.3.3 change is that configuration and time evidence become explicit coherent inputs to the existing atomic financial kernel rather than independently mutable side channels.

## 2. Active configuration snapshot

Current risk: active policies and provider catalog live in different mutable owners. Sequential replacement can create a mixed-generation read for a concurrent new payout.

Target architecture:

```text
Configuration input
      |
      v
validate/compile complete candidate
      |
      v
ActiveConfigurationStore
  immutable Snapshot(revision, policies, provider definitions, diagnostics)
      |
      +--> policy resolution
      +--> provider opportunity materialization
      |
      v
atomic routing decision commit
```

Rules:

- one immutable snapshot/revision is captured for a new decision;
- policy resolution and provider functional definitions derive from that same revision;
- publishing a new snapshot is atomic from routing-reader perspective;
- no configuration lock is held during provider I/O;
- runtime health/capacity/throughput remain operational state and may advance independently under the coordinator atomic boundary;
- payout history pins only the immutable historical policy/operation semantics needed for replay/continuation, not a mutable active-config pointer;
- configuration revision may be recorded in decision trace/explanation where useful for auditability.
- if the low-level Coordinator catalog is mutated outside the application
  publication path, application submit/resume/query boundaries fail closed
  until the provider generation matches again; they may not route from a
  stale snapshot or expire an unresolved payout first.
- the compatibility `PolicyRegistry` exposed through application objects is
  read-only; only coordinated application commands may publish the registry
  alongside the active snapshot. A supplied registry is sealed after
  successful bootstrap and bound to one application service, so it cannot become a
  second mutable policy source shared by independent active generations.

Do not introduce a database/config service solely for this. An in-memory revisioned store is sufficient before authoritative deployment requirements.

## 3. Configuration compiler

`RoutingConfiguration` remains the typed external/application value. Add a compile/validation stage that returns a canonical snapshot plus typed diagnostics.

The compiler may detect:

- duplicate/reused identities;
- policy/provider references that are statically impossible;
- selector/currency/amount inconsistencies;
- unreachable policy/provider relationships;
- warnings where a target is absent from active provider definitions but this may be intentional/temporary.

Do not confuse static definition consistency with runtime availability.

## 4. Fail-closed routing input

`RoutingContext` remains the generic route identity. Parsing rule:

- `nil` -> explicit empty context;
- existing `RoutingContext` -> identity;
- valid Hash -> canonical typed value;
- all other shapes -> error.

Malformed route data may not silently become a less-specific route and thereby broaden provider/policy eligibility.

Currency/amount remain on `Money`/intent.

## 5. Quality evidence key and age

Quality remains a lower-priority deterministic optimizer input.

A comparable evidence key should be bounded and typed. For v0.3.3 the most specific useful cohort is conceptually:

```text
provider + currency + payment_method + rail + destination_kind
```

Labels may remain a broader bounded context cohort when explicitly useful; they are not part of the typed route identity used for exact comparability unless the quality design proves otherwise.

Age semantics apply to individual evidence samples. At `as_of`, stale samples are excluded before maturity/confidence/score are computed. Then bounded sample-window semantics apply in one documented deterministic order.

Evidence fallback should be explicit, for example:

`mature fresh currency+route -> mature fresh broader route/context -> mature fresh global -> conservative prior`.

Sparse route evidence must not gain authority solely because one global `minimum_samples` default happens to be 1. Use explicit per-scope maturity or exact hierarchical shrinkage; prefer the simpler design that passes counterexamples.

## 6. Portable time architecture

Monotonic values are process/runtime-local measurement coordinates. They are not portable durable identities.

Persist portable wall anchors/deadlines and enough exact duration/policy information to reconstruct current-process monotonic references after restart. The running process may use monotonic time for elapsed correctness, but restore must rebase from portable durable time into the new origin.

Applies to:

- recovery schedule due time;
- operation TTL/deadline checks;
- throughput-window reservations/consumption where monotonic state is restored.

Controlled restart tests must use different monotonic origins.

## 7. Policy selection

`PolicyRegistry`/resolver remains deterministic. v0.3.3 strengthens precedence:

1. explicit policy identity when valid;
2. selector priority;
3. semantic subsumption/narrowing when one matching selector is a strict subset of another;
4. otherwise ambiguity for equal-authority incomparable matches.

Exact amount bands may be added with minor-unit/currency semantics. Do not build a general-purpose rules engine.

## 8. Recovery objective

Safety, ownership and recovery legality remain unchanged.

`allocation_constrained` stays default. If a reliability-first mode is justified, it is selected only after legal recovery candidates are known and uses lexicographic priorities. It must not modify the primary assignment ledger.

## 9. Coordinator boundary

`State::Coordinator` remains the atomic transaction facade.

Extraction is allowed only when it removes semantic duplication. Preferred candidates:

- configuration snapshot publication/reading outside money-moving mutable state;
- shared recovery expiry/schedule/rebase semantics used by live and restore;
- pure reducers shared across live/restore/replay.

Do not split the Coordinator merely because it is large.

## 10. Product adapters

Application/HTTP/CLI/demo are control and projection adapters. They may expose:

- active config revision/diagnostics/apply;
- due recovery work;
- dimension-safe analytics query;
- typed policy-resolution errors;
- payout/explanation/audit views.

They may not own routing algorithms or trusted provider outcome semantics. Do not guess the official judge HTTP schema.

Payout command adapters fail closed on unsupported top-level request fields.
Provider-specific nested context remains opaque to the core, while canonical
route identity is carried by the explicit typed `routing_context` field.

## 11. Performance stance

Correctness first. Measure larger history curves after semantic work. Only add indexes/checkpoints/incremental projections when a measured bottleneck justifies them.

## 12. Non-goals

Before TZ, do not introduce microservices, distributed consensus, Rails/ORM, queue infrastructure, brand-specific PSP schemas or ML/bandits without authoritative/measurement evidence.
