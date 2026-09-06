# Current Architecture — Product Convergence

This document defines the current architecture for **v0.3 — Product Convergence & Full Routing Product**.

`docs/ARCHITECTURE.md` remains useful historical rationale. This document is authoritative where they differ.

## 1. Architecture objective

Build one coherent payout-routing product, not a collection of independently plausible modules.

Keep a plain-Ruby modular monolith. The product may contain multiple internal components, but it has one domain model, one routing pipeline and one atomic correctness boundary.

The target architecture is:

`Application Commands / Queries`
→ `Policy Resolver`
→ `Opportunity Builder`
→ `Admission Controller`
→ `Allocation Controller`
→ `Constrained Optimizer`
→ `Atomic State Transaction`
→ `Provider Port / Adapter`
→ `Observation Normalizer`
→ `Lifecycle + Recovery + Reconciliation`
→ `Durable State / Facts`
→ `Replay / Analytics / Audit`

API/dashboard/demo layers sit above application commands and projections. They never own business semantics.

`DecisionProposal` also enforces the state-independent shape of control
decisions at the domain boundary: non-operation controls carry no provider,
operation or attempt identity; ownerless and owner-held defer roles are
validated later against restored ownership state by the durable trace
validator.

## 2. Component responsibilities

### Domain values

Immutable/value-like definitions:

- `Money`;
- `PayoutIntent`;
- policy identity/version/fingerprint;
- allocation strategy and obligations;
- eligibility constraints;
- recovery policy/budgets;
- constrained quality/cost/latency/priority optimization;
- provider capabilities/operation contract;
- normalized outcomes/observations;
- typed reason/deviation/conflict/reversal values.

No wall clock, network call or mutable registry belongs here.

### Policy resolver

Resolves the exact immutable policy definition for an intent and pins it to payout history.

It owns selection/versioning semantics, not routing arithmetic.

### Provider catalog / opportunity builder

Produces the functional opportunity set from payout context and provider capabilities/configuration.

Functional opportunity answers: **could this provider serve this payout in principle?**

It must remain separate from temporary live state.

Catalog replacement records explicit provider-removal facts. Restart therefore
restores the current opportunity set without discarding older admission usage
that may still be needed to release an unresolved operation safely.

`State::ProviderCatalogLedger` owns the current opportunity map and the ordered
registration/removal timeline behind the coordinator atomic facade. Restore
replays the durable catalog from an empty ledger; supplied runtime opportunities
are accepted only when their IDs remain current in that history, so configuration
cannot add or resurrect a provider without a new atomic registration. Timeline
sequences must advance monotonically. The ledger performs no provider I/O and does
not publish facts.

### Admission controller

Answers: **may a new provider operation start now?**

Inputs may include:

- administrative enablement;
- live availability;
- concurrent operation exposure;
- amount exposure;
- time-based throughput/rate budget;
- health/quarantine/probing;
- emergency/provider-specific hard gates.

Admission is hard. An optimizer cannot resurrect a rejected provider.

Important distinction:

- concurrency/amount exposure is reserved and released with operation lifecycle;
- throughput/rate limits are time-window/token style admission state and are not “released” when the payout completes.

Do not reuse one counter for both meanings.

`State::AdmissionLedger` owns the mutable capacity and throughput counters
behind the coordinator atomic facade. It has no provider I/O and does not own
health policy; health exposure is a separate hard input to admission.

`Routing::DecisionEvaluator` is the fact-free evaluation seam that assembles runtime
opportunities, eligibility, admission flags, allocation state, runtime
feasibility and the constrained proposal. It publishes no facts and reserves
no business resources (admission reads may prune expired local window entries);
the coordinator records its output and hands admitted assignment work to
`State::OperationCommitter` inside the same atomic transaction.

The evaluator now materializes one immutable `DecisionEvaluator::Evaluation`
before proposal construction. `DecisionEngine` consumes its eligibility,
allocation exclusions, runtime feasibility, allocation snapshot and quality
evidence instead of recomputing eligibility/runtime feasibility. Standalone
engine calls retain their compatibility path by computing the same inputs when
no prepared evaluation is supplied. Atomic commit still revalidates mutable
state at the coordinator boundary.

The pure `Routing::OpportunityRuntime` module owns the shared composition of a
provider definition with adapter availability, capacity, health and throughput
evidence. Live evaluation and durable opportunity-trace validation use this
same seam while retaining their distinct current-time and as-of evidence
sources.

### Allocation controller

Owns business distribution obligations independently from provider quality optimization.

It supports exact count/volume measures and tracks the configured accounting point/window.

Responsibilities:

- target weights/shares;
- provider share minimum/maximum obligations when configured;
- tolerance/admissible allocation corridor;
- committed/in-flight primary assignments;
- opportunity-aware denominator;
- policy epochs/windows;
- deviation attribution;
- explicit `none`/`recoverable`/`unavoidable` deviation classification;
- recoverable/non-recoverable debt if enabled;
- bounded recovery/catch-up only if an explicit debt policy is enabled; v0.3
  does not infer catch-up from recoverable deviation (D-059).

`tolerance` has one meaning: the absolute post-decision L1 discrepancy across
the policy allocation universe, in that policy's measure units. Count uses
count units; volume uses exact minor units of the policy currency. It is a
preferred corridor after share obligations, not a license to bypass them. If
no candidate is inside the corridor, allocation chooses the least-bad
admissible state and records `tolerance_exceeded`.

Per-payout amount eligibility limits are not provider share minimum/maximum obligations. Keep these concepts separate.

`State::AllocationLedger` owns keyed committed primary snapshots and exact
revision progression. The coordinator supplies the atomic timing and the
policy-derived key; recovery attempts remain outside the primary ledger.

`State::LifecycleLedger` owns operation phase transitions and the deterministic
reduction from normalized provider outcomes to payout status/release intent.
`State::OperationCommitter` owns the fact-producing assignment, retry/resolve,
phase-transition and ownership-release side effects around that reducer. The
coordinator remains responsible for atomic fact publication and external
capacity/health effects through this explicit seam, so lifecycle reduction
cannot bypass the correctness boundary.

`State::WorkingStateRestorer` owns ordered durable-prefix replay, validation that
supplied runtime opportunities are current in durable provider history and the
boundary that classifies reducer shape failures as durable corruption. The
coordinator supplies the individual fact reducers, while
`State::RestoredStateValidator` owns final restored-state ownership,
reservation, phase/outcome and release-order checks. These are orchestration
seams, not a second durable transaction owner.

`State::ProviderCatalogRestorer` owns provider-definition and provider-runtime
fact replay through the catalog, admission and quality seams. It does not append
facts, perform provider I/O or own the transaction; the coordinator supplies
identity/order validation and current component references.

`State::AdmissionFactRestorer` owns durable capacity reservation/release and
throughput-consumption reduction through `State::AdmissionLedger`, while the
coordinator supplies payout, provider-history and operation-linkage callbacks.
Exact money and monotonic-time validation therefore remains at the admission
boundary without making the restorer a second transaction owner.

`State::OperationFactRestorer` owns durable ownership-acquisition,
attempt-start, reconciliation-block and health-exposure reservation/release
replay. It uses coordinator-supplied operation, lifecycle and health-order
validation callbacks, and does not publish facts or perform provider I/O.

`State::ProviderEvidenceFactRestorer` owns provider-derived transport, health,
quality and health-transition replay. `State::FinancialFactRestorer` owns
late-success conflict and settlement-reversal replay. `State::PayoutFactRestorer`
owns intent and policy registration replay, while
`State::OpportunityEvaluationFactRestorer` and `State::DecisionFactRestorer`
own the recomputed evaluation and assignment/recovery decision replay seams.
`State::DecisionTraceValidator` owns the policy/allocation/admission/operation
cross-fact proof used by decision replay. All of these remain callback-driven
and behind the coordinator's durable atomic facade; none publishes facts or
performs provider I/O.

### Constrained optimizer

Chooses among already safe/admitted allocation-compatible candidates.

It must not be one arbitrary weighted scalar that can violate higher-priority obligations.

Priority order:

1. economic safety;
2. hard functional/business constraints;
3. operational admission;
4. allocation admissibility/obligations;
5. reliability/quality;
6. cost;
7. latency/priority;
8. bounded exploration if explicitly enabled.

A simple deterministic lexicographic implementation is preferred before statistical/adaptive routing.

Reliability estimates are separate from fast operational health. Slow quality
uses an exact deterministic Beta/Laplace posterior over a bounded recent
evidence window rather than a raw success ratio. The default neutral prior is
`1/1`; sparse evidence therefore shrinks toward `1/2`, `minimum_samples`
controls maturity, and `evidence_window` bounds the relevance of old outcomes.
Context snapshots use mature context evidence, then mature global evidence,
then the prior/default. Only provider-attributed terminal success/provider
failure outcomes enter quality; pending/UNKNOWN and recipient/downstream
outcomes remain neutral. Snapshot/fact payloads preserve counters, prior,
window and exact Rational score for deterministic replay and optimization
traceability. Slow quality must account for:

- attribution;
- comparable route/context cohort;
- maturity/delayed feedback;
- sample confidence;
- stale evidence.

Pending/UNKNOWN does not automatically equal provider failure.

### Lifecycle / recovery / reconciliation

Owns legal action after a committed provider operation:

- dispatch state;
- provider observation reduction;
- observation identity/deduplication and provider-event ordering;
- same-provider status resolution;
- same-operation idempotent retry;
- safe release;
- fresh fallback;
- wait/defer;
- deadline/TTL expiry;
- reconciliation-blocked;
- settlement;
- return/reversal;
- economic conflict/remediation.

Fresh fallback is a new routing decision over current opportunity/admission
state. `Routing::RecoverySelection` owns the recovery-only legality boundary:
it excludes already money-moving providers, retains the full functional
accounting universe for exact discrepancy evidence, and deliberately reuses
the canonical allocation authority for the next legal fallback. Recovery
assignments keep role `:recovery`, so `primary_assignment` accounting is not
advanced by fallback work.

A non-operation `defer` with no economic owner is a durable current-state
transition to `:deferred`, so no-route and exhausted-budget payouts are
distinguishable from untouched `:new` intents. A `defer` while ownership is
retained remains an owner-held unresolved state such as `:unknown` or
`:reconciliation_blocked`; it does not release or relabel that ownership.

### Atomic state coordinator

The coordinator is the correctness transaction facade, not the owner of every algorithm.

It serializes the state changes that must be atomic together, including as applicable:

- payout/operation legality;
- policy pinning;
- primary allocation reservation;
- admission/capacity reservation;
- decision/operation identity;
- economic ownership;
- operation contract;
- dispatch token/phase;
- fact/state revision.

Provider I/O is always outside the coordinator mutex/transaction.

Current `State::Coordinator` is too large to remain the final internal design. Decompose it incrementally into focused ledgers/reducers while preserving one atomic facade. Do not turn this refactor into microservices.

Likely internal components:

- `PayoutRegistry` / operation registry;
- `ProviderCatalogLedger` / ordered opportunity history;
- `AllocationLedger`;
- `AdmissionLedger` / exposure/rate state;
- `ProviderHealth` projection/controller;
- `LifecycleLedger` / operation lifecycle reducer;
- `OperationCommitter` / operation fact and ownership side effects;
- `WorkingStateRestorer` / ordered durable replay and supplied-catalog validation;
- `ProviderCatalogRestorer` / provider definition/runtime fact replay;
- `AdmissionFactRestorer` / capacity and throughput fact replay;
- `OperationFactRestorer` / ownership, dispatch, reconciliation and probe fact replay;
- `ProviderEvidenceFactRestorer` / provider transport, health and quality fact replay;
- `FinancialFactRestorer` / conflict and reversal fact replay;
- `PayoutFactRestorer` / intent and policy registration fact replay;
- `OpportunityEvaluationFactRestorer` / recomputed historical evaluation replay;
- `DecisionFactRestorer` / assignment and recovery decision replay;
- `DecisionTraceValidator` / cross-fact decision proof;
- `RestoredStateValidator` / final durable working-state invariants;
- `ObservationLedger` / observation identity and provider-event ordering;
- `FactRepository` / durable state repository.

The names are not normative. Responsibility ownership is.

### Provider port and adapters

The provider port represents economic operations, not transport convenience.

Required concepts:

- stable operation/idempotency identity;
- initiate;
- status/resolve when supported;
- definitely-not-sent classification;
- ambiguous-after-possible-send classification;
- provider-specific raw response/webhook normalization;
- terminal/pending/unknown semantics;
- provider sequence semantics only when contractual;
- cancellation semantics when supported.

Core code never trusts an external caller to directly declare `safe_to_release`.

A demo simulator may implement this port. It must be named as a simulator/demo provider, not as a real PSP integration.

### Durable state repository

Durability is a correctness feature, not a file-output feature.

A durable implementation is only acceptable if a fresh process can reconstruct a working state machine that safely continues unresolved payouts.

The current restart evidence includes an actual separate Ruby process opening
the `FileJournal` without the original runtime opportunity/policy catalog and
continuing the committed operation through the public `Application::Service`;
the parent reopens the journal and verifies the persisted terminal attempt.
Same-process coordinator reconstruction is retained for the broader
deterministic crash campaign.

Required continuation material includes, as applicable:

- intents;
- policy bindings/fingerprints;
- operations/attempts/phases;
- economic ownership;
- provider contracts/idempotency identity;
- deduplication/event-order state;
- allocation reservations/state;
- admission/capacity reservations;
- health state needed for routing correctness;
- settlement/reconciliation/conflict state.

A replay projection alone is insufficient if the returned live coordinator forgets unresolved ownership.

Persistence corruption/truncation must fail explicitly or enter a controlled recovery state. Silent dropping of malformed financial history is forbidden.

### Application layer

Owns user/system commands and queries:

- submit payout;
- get payout;
- resume/advance unresolved payout;
- reconcile provider observation;
- update provider/policy configuration;
- query analytics/audit.

Application commands use domain services; they do not build `NormalizedOutcome` from untrusted generic external fields.

Current implementation: `Application::Service` composes focused `Commands` and
`Queries` over `Orchestrator` and `State::Coordinator`. Queries expose payout,
provider, policy, projection and audit views without mutating routing state.
Analytics queries use the coordinator clock as their default age boundary, while
historical callers can pass an explicit `as_of` value or `nil`.

Decision audit facts include the allocation candidate trace and the separate
constrained-optimization trace: every candidate records whether it survived
allocation authority, its quality evidence/ranking key when applicable, and
whether it was selected.

### API / webhook gateway

`Application::HttpApp` is a minimal Rack-compatible adapter that maps transport
to application commands/queries. It is deliberately not a second routing
engine.

Its provider normalizer configuration is validated at construction: every
configured normalizer must provide an executable `#normalize` implementation,
so an exposed webhook route cannot defer a dead adapter failure until its first
event.

Provider webhook route:

`raw request -> provider-specific adapter verification/normalization -> ProviderObservation -> application/core`.

Do not expose Ruby backtraces or internal exception details in normal API responses.
The transport boundary bounds method, path, query-string and JSON-body sizes and
returns a stable 413 response for oversized input before parsing it. Audit facts
are returned through bounded pages with strict `limit`/`offset` validation and
explicit continuation metadata, so a durable journal cannot become one
unbounded API response.

The public audit route applies `Projections::PublicAuditFact` to every page
before serialization. This is a fail-closed whitelist of case-relevant
routing evidence: recipient/context fields, provider references and provider
messages are omitted by default, and the response reports only their field
names in `redacted_fields`. Internal `Queries#audit_facts` remains a raw
durable-fact view for trusted replay/restore tooling; it is not the public
HTTP contract.

`deviation_by_cause` and runtime-infeasibility cause counters are deterministic
rule attributions, not causal inference. Analytics exposes this contract as
`deviation_attribution_semantics: deterministic_routing_reason` and
`runtime_infeasibility_attribution_semantics: deterministic_exclusion_reason`;
the explanation projection carries the same routing-reason label.

The direct application reconciliation command is a provider-event ingress that
requires `provider_id`, raw payload and an executable provider-specific
normalizer. It is not a raw callback escape hatch and does not accept a
caller-constructed `ProviderObservation`; transport certainty and
`safe_to_release` are domain evidence produced by that boundary. In-process
provider/orchestrator callbacks still use the typed observation path after the
provider adapter has produced the evidence.

`Demo::ScriptedProvider` and `Demo::Scenario` are explicitly simulated and
exercise the same provider port and application path; they are not real PSP
integrations.

`State::FactStore` appends one coordinator mutation as one durable batch when
the configured journal supports `append_many`. If a durable append fails before
visibility, the coordinator rebuilds working projections from the accepted fact
prefix; if a complete batch is visible despite a post-write error, the store
reconciles it before allowing another fact identity. If the journal exposes a
partial or non-prefix append, it is poisoned and cannot accept further writes;
the corruption is explicit in the current process and on fresh open. Working restoration rejects
unsupported lifecycle facts and validates provider-system, operation, settlement,
conflict, reversal and final payout-state linkage rather than silently dropping
semantically malformed history. `FactCodec` rejects floating-point values on
both encode and decode paths, including nested payloads. Durable provider IDs
remain canonical strings and timestamp fields remain controlled `Time` values;
malformed identity/time payloads are rejected during restore.

The final restored-state validator also binds an in-flight attempt phase to its
latest operation action and applied observation chronology. A pending/unknown
outcome without its corresponding phase transition is therefore treated as
durable corruption instead of being replayed as a misleading dispatching or
resolving state that could suppress safe restart recovery.

TTL, deadline and throughput-window decisions compare exact monotonic values.
Wall timestamps remain audit fields; new lifecycle/admission facts persist
monotonic anchors, and the default system clock translates older wall-time
facts to the current process timeline only at restore. This translation is not
a wall-clock duration calculation.

### Analytics and audit

Facts/projections should answer:

- what providers were opportunities;
- what was excluded and why;
- which provider was assigned primary;
- allocation target vs actual;
- what attempts happened;
- where settlement occurred;
- first-attempt/eventual success;
- fallback recovery;
- provider-attributable reliability;
- unknown/pending/reconciliation age;
- capacity/availability/health effects;
- deviation attribution;
- whether recorded deviation is recoverable or unavoidable;
- conflicts/reversals;
- exact decision rationale.

Distribution metrics use the immutable `Projections::AnalyticsDimension`
(policy id/epoch/scope, allocation window/cohort, measure, currency and
provider). Allocation, target, deviation and settlement are exposed as
dimensioned projection rows and replay/JSON serialization preserve that key.
Provider-only convenience totals are intentionally omitted when a provider's
rows are not dimension-compatible.

`Projections::DecisionExplanation` is the typed, whitelist-based read model for
decision evidence. It groups policy, opportunity, admission, allocation,
optimization, deterministic rationale, recovery and lifecycle-result fields
without copying recipient-sensitive fact payloads. Application queries and the
HTTP payout explanation route consume this same projection.

## 3. Atomic provider-operation protocol

Before provider I/O, under one atomic state boundary:

`validate payout + policy`
→ `build/revalidate opportunity`
→ `revalidate admission`
→ `compute allocation/optimization decision`
→ `reserve required allocation/admission state`
→ `create operation/attempt`
→ `acquire economic ownership`
→ `pin provider operation contract`
→ `mark committed dispatch token`
→ `append durable facts/state`

Then release the lock/transaction.

Immediately before external I/O, claim the dispatch token. A stale/invalidated commit is a non-action.

The resulting `ProviderOperationRequest` is executable without an out-of-band
intent lookup. It contains the immutable generic destination, full routing
context, normalized method/rail values where present, amount/currency,
operation/attempt/idempotency identity and the pinned `ProviderOperationContract`.
Assignment, resolution/retry and restart reconstruction use the same canonical
request factory; provider-specific mapping remains in the adapter boundary.

After external result/callback, re-enter the state transaction and apply normalized evidence.

## 4. Allocation versus optimization

This separation is mandatory.

Allocation answers:

**Which providers are currently acceptable with respect to the business distribution contract?**

Optimization answers:

**Which of those acceptable providers is preferable now?**

When exact targets cannot be met because payouts are indivisible or providers are unavailable, record the least-bad achievable deviation and its cause. Do not silently erase history or allow an optimizer to create arbitrary target drift.

## 5. Fast health versus slow quality

Keep two feedback loops:

### Fast operational health

Uses typed transport/5xx/timeout/overload/service-error/latency/deadline evidence and can rapidly reduce exposure. `HealthController` keeps explicit `transport_failure`, `timeout_pressure`, `overload_rejection`, `provider_service_error`, `latency_pressure` and `deadline_pressure` signals on the same hysteresis/probing path.
The typed `ProviderHealthSnapshot` boundary rejects malformed counters, non-positive
or non-integer probe limits and `probe_in_flight > probe_limit` before health state
is used for admission or exposed to projections.

Transport uncertainty is deliberately split at the provider boundary:
`definitely_not_sent` is provider `transport_failure`, while
`ambiguous_after_possible_send` is provider operational `timeout_pressure`.
That health attribution does not alter the normalized UNKNOWN payout outcome or
its economic owner; the source and typed signal are durably validated on restore.

### Slow quality estimate

Uses mature comparable outcomes and confidence. It should not compare providers using incomparable delayed-feedback populations.

Fast-down/slow-up, bounded probing and traffic-ramp constraints are preferable to instant full recovery.

## 6. Repository boundaries

Core production code must not contain speculative provider-brand trivia.

Allowed:

- generic `payment_method`, `rail`, `destination_bank`, `currency`, `segment` context fields;
- explicit demo/plugin mapping outside core;
- provider-specific adapter behavior when backed by an actual provider contract/TZ.

Not allowed in core by default:

- hardcoded card BIN tables;
- assuming unknown cards are one network;
- fake “real-world” adapters that always return success;
- alternate provider APIs inconsistent with the canonical port.

## 7. Refactoring strategy

Do not rewrite the whole core.

Use strangler-style internal convergence:

1. lock current behavior with tests;
2. extract one responsibility behind the existing coordinator facade;
3. prove replay/concurrency equivalence;
4. remove duplicate old path;
5. continue.

Refactoring must improve invariant ownership or testability, not merely file size.

## 8. External infrastructure

Do not introduce Rails, microservices, queues or distributed locks by default.

A minimal embedded durable database/library is acceptable only when it directly solves restart/transaction correctness and remains compatible with likely hackathon constraints. Exact dependency choice is a later implementation decision, not a reason to postpone the durability contract.

## 9. Architecture closure checks

Before v0.3 completion prove:

- one canonical routing pipeline;
- no provider I/O under atomic state lock;
- one unresolved owner max;
- allocation/admission reservations are atomic and replayable/recoverable where claimed;
- optimizer cannot violate hard/admission/allocation constraints;
- recovery and provider normalization are single-source semantics;
- durable restart can continue UNKNOWN/pending payouts safely;
- raw webhooks cannot forge economic safety semantics;
- analytics reconcile opportunity/assignment/attempt/settlement;
- no disconnected production feature hooks remain;
- demo/provider-specific code is explicitly separated from generic core.
