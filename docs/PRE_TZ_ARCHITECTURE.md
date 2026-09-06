# Pre-TZ Architecture Delta — v0.3.2

This document is the current architecture delta for v0.3.2. It inherits the proven v0.3.1 structure in `docs/CURRENT_ARCHITECTURE.md` and changes only the semantic-control-plane areas that the post-v0.3.1 audit found materially incomplete.

If this document and `docs/CURRENT_ARCHITECTURE.md` differ for active v0.3.2 work, this document and SPEC-006 take precedence.

## 1. Target flow

The canonical product flow remains:

`Intent`
→ `Policy Resolution`
→ `Functional Opportunity`
→ `Operational Admission`
→ `Allocation Authority`
→ `Recovery Legality / Role Semantics`
→ `Constrained Optimization`
→ `Atomic Commit / Ownership / Reservations`
→ `Provider Operation Payload`
→ `Provider Adapter`
→ `Normalized Observation`
→ `Lifecycle / Recovery / Reconciliation`
→ `Durable Facts / Working State`
→ `Dimensioned Analytics / Explainability / Application`.

The v0.3.1 changes are not a new architecture. They close weak contracts inside the existing one.

## 2. Provider operation payload

`ProviderOperationRequest` is the canonical real payout execution value. It is
constructed from the intent and the operation-time contract before provider I/O
and is immutable after construction.

The generic operation payload should contain immutable provider-relevant economic data, for example:

- payout id;
- provider/operation/attempt identity;
- amount/currency;
- stable idempotency key;
- typed generic payout destination/recipient representation;
- payout method/rail when applicable;
- immutable provider-relevant routing context required to execute the operation.

The current implementation models this boundary as `PayoutDestination` plus
`ProviderOperationPayload`, with `ProviderOperationContract` pinned inside the
payload. `ProviderOperationRequest.from_intent` is the single construction path
used by assignment, resolve/retry and restart reconstruction. `to_h` provides a
semantic comparison surface for tests and does not replace the typed objects
used by adapters.

Do not give generic core knowledge of PSP-specific JSON/body fields. Adapters map the generic operation payload into provider-specific request contracts.

The same operation payload must survive retry/resume/restart semantically unchanged.

### v0.3.2 route identity and capability boundary

`PayoutIntent#routing_context` is the canonical immutable interpretation of
generic route dimensions. Raw `PayoutIntent#context` remains available to an
adapter as opaque metadata, but policy hard constraints, provider functional
eligibility, quality cohorts and the executable operation payload consume the
typed value for dimensions the core understands.

`ProviderRouteCapabilities` is the corresponding provider-side boundary. It
matches supported payment methods, rails and destination kinds before a
provider enters the functional cohort. A missing declaration is an
unconstrained dimension for backward-compatible generic providers; an
explicit empty set is a fail-closed declaration that supports no value. The
resulting typed exclusion is evidence for eligibility and explanation, not an
operational health signal or an allocation score.

Provider capability definitions are serialized inside the existing provider
catalog `definition` and reconstructed through the durable whitelist. This
keeps live catalog state, replay and allocation-cohort accounting on one
semantic path without introducing PSP-specific fields into the core.

### v0.3.2 admission boundary

`CapacityBudget` has one physical concurrent-exposure metric per provider:
each money-moving payout reserves one in-flight unit and releases that same
unit only at the lifecycle boundary. `max_slots` is the canonical name;
`max_count` remains accepted as a backward-compatible durable cap, not a
second dimension. When both are configured, the effective concurrent limit is
their stricter bound, preserving historical behavior without pretending the
two counters are independent. `CapacityUsage` stores one in-flight value and
the compatibility `used_slots`/`used_count` projection names are required to
match. Amount exposure remains a separate exact minor-unit constraint.

`ThroughputBudget` owns time-window operation counts independently. Completing
or safely releasing a payout changes concurrent exposure but does not refund a
consumed throughput event.

### v0.3.2 policy resolution boundary

`PolicySelector` is the bounded immutable selector for automatic policy
resolution. It recognizes only currency, the canonical method/rail/destination
dimensions, normalized labels/segments and an explicit non-negative priority;
aliases are normalized into the same generic route identity and conflicting
aliases fail closed. It is deliberately not a general rules DSL.

`PolicyRegistry#resolve_for_intent` returns a typed `PolicyResolution`. It first
filters by scope and `RoutingPolicy#applies_to?`, then ranks compatible
policies by the lexicographic key `[priority, specificity]`. A unique winner is
matched; no winner is a typed no-match; equal-precedence winners are a typed
ambiguity. Registration order is not a routing input, and ambiguity never
chooses an arbitrary policy.

Explicit policy commands cross the same `applies_to?` boundary before durable
intent/policy facts are written. New payouts use the resolver, while resume
uses the durable payout policy binding before consulting current active
configuration. Non-empty selector definitions participate in the policy
fingerprint and are reconstructed by the existing durable policy-definition
path, so changing active configuration cannot rewrite historical routing.

### v0.3.2 active configuration boundary

`Application::RoutingConfiguration` is the immutable control-plane value for
the current policy set and provider-opportunity set. It delegates identity,
selector, target, recovery, capability and admission validation to the
existing domain types, then canonicalizes collection order for stable
serialization. `ConfigurationStore` holds only this active value; it is not a
journal and does not replace payout-pinned policy definitions.

`Application::Commands#apply_configuration` validates the complete typed
replacement before delegating provider-catalog changes and replacing the
automatic `PolicyRegistry` set. `Queries#configuration` returns the same
immutable value. Existing register/replace/availability commands refresh this
view, while unresolved resume continues from the coordinator's durable policy
and operation contract even when active configuration has changed.

`Demo::Scenario` uses this same command path: its default run builds a typed
configuration, and callers may supply a custom typed configuration, provider
adapter map and intent. The demo therefore proves configurable shares,
capabilities, admission and recovery settings without teaching the demo a
second routing algorithm. It remains explicitly simulated; it is not a real
PSP adapter or production-scale benchmark.

### v0.3.2 recovery schedule boundary

`RecoveryPolicy` owns only deterministic timing parameters: an initial delay,
linear exact-integer backoff by resolution-interaction index and an optional
maximum delay. An applied unresolved provider observation creates one immutable
`RecoverySchedule` tied to the current operation/attempt/provider. It records
both wall-clock and exact monotonic anchors, the next action (`resolve` or
`retry_same`), due time and reason. A later decision consumes the schedule;
terminal ownership release and contract expiry clear it.

Coordinator `prepare` and restart resume enforce due-ness using the monotonic
deadline as the safety authority, with wall time retained for product-facing
queries. Operation TTL/deadline expiry is evaluated before schedule
convenience and retains ownership in `reconciliation_blocked`; it cannot
become a fallback or an early provider interaction. `Coordinator#due_recovery_work`
and application `Queries#due_work` are read-only sorted projections for an
external runner. They return due same-provider recovery or explicit
reconciliation work as of a supplied time and do not introduce a queue or
sleeping worker.

## 3. One routing evaluation

The target internal boundary is one immutable `RoutingEvaluation`-like value produced before commit.

It should own the evidence required to build a proposal:

- resolved policy identity;
- functional opportunity set;
- hard/soft eligibility results;
- operational admission evidence;
- allocation snapshot/key;
- measure/corridor exclusions;
- runtime feasibility;
- health/quality snapshots;
- attempted-provider/recovery context;
- candidate allocation results;
- constrained-optimization evidence.

Proposal construction consumes this evaluation. The current
`DecisionEvaluator::Evaluation` is immutable and is passed to
`DecisionEngine`; live proposal construction therefore does not independently
recalculate eligibility or runtime feasibility. The shared pure
`DecisionEvaluator.prepare` contract owns those three preparation steps for
both the live evaluator and the standalone compatibility path, so direct
callers retain compatibility without a second implementation of eligibility
or runtime feasibility.

`Routing::OpportunityRuntime.materialize` is the shared pure seam for composing
static provider gates with dynamic adapter, capacity, health and throughput
evidence. Live evaluation supplies current ledger evidence; restore supplies
validated as-of evidence. The source differences remain intentional, while the
final runtime opportunity semantics cannot drift between the two paths.

The atomic coordinator still revalidates mutable reservations/state immediately before commit where concurrency correctness requires it.

## 4. Primary and recovery decision semantics

Primary selection and recovery selection are related but not identical concepts.

Primary selection owns business distribution accounting.

Recovery selection owns the next legal economic action after an earlier provider operation. It must explicitly define which allocation obligations still constrain fallback and where reliability/cost/latency become the deciding objectives.

Under the current `primary_assignment` accounting point:

- primary assignment advances the primary allocation ledger;
- recovery assignment does not;
- fallback still obeys economic safety, hard eligibility/admission and configured recovery business constraints;
- `Routing::RecoverySelection` explicitly excludes already money-moving providers,
  then deliberately delegates allocation obligations to the same exact primary
  allocation authority;
- the full functional accounting universe remains visible when computing
  discrepancy, so excluded providers do not disappear from target accounting;
- selection logic is therefore staged and owned explicitly rather than inheriting
  semantics accidentally from an unmarked allocator call.

This is the current pre-TZ choice for recovery business allocation: the typed
`RecoveryObjective` selects the named `allocation_constrained` mode, which uses
the primary allocation authority for the next legal fallback, but never
advances its ledger for a recovery role. Constrained quality/cost/latency
optimization still applies only after this selection and its higher-priority
gates. No reliability-first or hybrid mode is enabled before evidence or the
official TZ justifies its exact lexicographic semantics.

The allocation tolerance is intentionally one exact concept: absolute
post-decision L1 discrepancy across the policy accounting universe, expressed
in the policy's count or exact monetary-minor-unit measure. Share obligations
are evaluated first. A candidate at or below tolerance is preferred among
otherwise admissible states; if all candidates exceed it, the least-bad state
is still selected and the excess is preserved as typed evidence. This is not a
normalized share error or a per-provider tolerance.

## 5. Quality versus health

Keep two separate feedback loops.

### Fast health

Purpose: protect new traffic from current operational degradation.

May react to normalized provider operational evidence such as transport failure, timeout pressure, overload/rate rejection, normalized provider service error, latency/deadline pressure and controlled probe results. The canonical health signal vocabulary is typed: `transport_failure`, `timeout_pressure`, `overload_rejection`, `provider_service_error`, `latency_pressure` and `deadline_pressure`, alongside legacy generic signals retained for durable compatibility.

Health can exclude/quarantine a provider for **future** operations. It cannot reinterpret the economic state of an already ambiguous payout.

An observation classified as `definitely_not_sent` emits `transport_failure`; an
`ambiguous_after_possible_send` observation emits provider-attributed
`timeout_pressure` for the health loop only. The normalized observation remains
UNKNOWN with unknown economic attribution, so the payout owner and fallback
safety are unchanged. The health fact records the source observation and is
validated against the same transport classification during restore.

The canonical application provider path measures interaction duration between
injected exact monotonic clock reads and stores it as immutable observation
evidence. When a positive `latency_threshold_ms` is configured, a duration
strictly above that threshold produces provider-attributed `latency_pressure`
for an otherwise successful or unclassified provider observation. More
specific transport and provider-service signals retain precedence; recipient,
downstream and unknown-attribution outcomes never create latency health
pressure. The duration is durable and restore-validated, while it cannot alter
the economic outcome, UNKNOWN ownership or fallback legality.

### Slow quality

Purpose: choose among already legal candidates using mature outcome evidence.

Quality uses a deterministic Beta/Laplace posterior over a bounded recent
evidence window. The current default prior is `1/1`, so sparse evidence is
shrunk toward a neutral conservative baseline; `minimum_samples` controls
maturity and `evidence_window` bounds how long old evidence remains relevant.
Context selection is hierarchical: a mature non-stale typed route cohort,
then a mature non-stale label context cohort, then mature non-stale global
provider evidence, then the prior/default. Route cohorts are keyed only by
canonical payment method, rail and destination kind; labels never expand route
cohort cardinality and remain a separate context dimension. Only
provider-attributed terminal success/provider-failure outcomes enter the
window; pending, UNKNOWN and recipient/downstream outcomes are neutral.

`QualityPolicy#max_evidence_age_seconds` makes evidence freshness explicit.
Each quality observation records an injected wall timestamp; snapshots compute
age as an exact `Rational`, and age is evaluated independently from sample
maturity. At the exact configured boundary evidence remains authoritative; an
older sample (or mature evidence with an unknown timestamp under a configured
max age) is stale and cannot drive routing. The durable quality fact retains
the timestamp, selected scope and typed route identity so live, restore and
replay share the same evidence state. Exact score, counters, prior and window
policy remain included in immutable snapshots and optimizer traces.

A conservative deterministic estimator is preferred before adaptive exploration.

## 6. Analytics dimension model

The canonical additive analytics key must include enough information to guarantee unit compatibility.

Conceptually:

`AnalyticsDimension = policy_id + epoch + scope + allocation_window/cohort + measure_kind + currency_if_volume`.

The current implementation represents this as an immutable
`Projections::AnalyticsDimension`; provider identity is a dimension member
inside the analytical series. Allocation, target, deviation and settlement
maps retain the complete key. JSON/API views serialize explicit dimension rows,
and replay projects the same rows from facts.

Do not expose provider-only additive totals unless the underlying dimensions are
provably compatible. The current convenience summaries omit a provider when
its rows span multiple policy, cohort, measure or currency dimensions rather
than returning a misleading sum.

Target, actual, deviation and settlement must preserve compatible dimensional identity through replay and API serialization.

`Analytics#query` is the application-facing read seam for the additive
dimensioned measure series. A query selects one canonical metric, normalizes
closed dimension filters and group fields, and adds rows only when every
ungrouped dimension is fixed by the selection. Therefore policy identity,
window/cohort, measure kind and volume currency cannot disappear into a
provider-only mixed-unit total. `Application::Queries#analytics_query` delegates
to this projection; transport layers do not implement another aggregation
algorithm.

## 7. Live and durable state

Keep one atomic transaction facade.

The next decomposition objective is **semantic reuse**, not more files.

Prefer this direction:

`typed command/evaluation -> shared pure transition/reducer -> live ledger mutation + fact emission`

and on restore:

`fact -> validation/linkage -> same/shared transition or invariant logic -> reconstructed ledger/state`.

The current outcome boundary follows this shape through
`State::LifecycleLedger::OutcomeReduction`: live commit obtains phase/status/
release classification from the pure reducer, observation restore uses the same
status result, and replay/Analytics use the reducer's pure status adapter.
The reducer never mutates ownership, capacity, health or durable facts; those
effects remain ordered in their existing atomic/restoration owners.

Do not create a parallel restore-only implementation of business decisions where the live pure reducer can be reused safely.

Restorers remain useful for causal fact linkage and corruption detection. Their number is not itself a quality metric.

## 8. Explainability projection

Decision facts already contain rich evidence. v0.3.1 should make that evidence product-readable through one typed explanation/projection rather than forcing callers to understand raw fact ordering.

A decision explanation should answer:

1. what policy applied;
2. what providers were functional opportunities;
3. what providers were excluded and by which hard/runtime rule;
4. what allocation state existed before the decision;
5. what each candidate would do to allocation obligations;
6. what quality/health evidence was considered among legal candidates;
7. why the selected provider won;
8. whether this was primary or recovery;
9. what happened next and where settlement occurred.

Public explainability/audit views should not expose raw recipient-sensitive fields by default.

`Projections::DecisionExplanation` is the typed product-readable projection for
this evidence. It exposes policy, opportunity, admission, allocation,
optimization, rationale, recovery and lifecycle-result fields through a
whitelist; it does not copy raw fact payloads or recompute a routing decision.
`Application::Queries#explanation` and the HTTP payout explanation route use
this projection as their shared read path.

The public `GET /v1/audit/facts` route uses `Projections::PublicAuditFact`.
It keeps the audit envelope and whitelisted routing evidence but omits
recipient/context data, provider references and provider messages by default;
omitted field names are reported as `redacted_fields`. Internal durable facts
remain available to replay/restore tooling and are not the public API contract.

Allocation fields retain the durable `deviation_cause` vocabulary for
compatibility, but Analytics labels the semantics explicitly as
`deterministic_routing_reason`. The label is derived from observed exclusion
and allocation-rule precedence; no counterfactual causal claim is made.

## 9. Performance architecture

Current evidence indicates pure allocation is much cheaper than full lifecycle/fact/projection work.

Do not optimize selection arithmetic first unless new measurements contradict this.

After semantics stabilize, prefer measured improvements around:

- incremental projections;
- dimension/payout/provider indexes;
- bounded audit retrieval;
- projection checkpointing if justified;
- removal of redundant duplicated fact payload where replay/audit safety is preserved.

Performance work must preserve correctness evidence and deterministic replay semantics.

`benchmark/history_profile.rb` provides a bounded reproducible profile for
100/250/500 successful payouts. It reports exact fact density plus lifecycle,
Analytics replay, fresh restore, bounded public/filtered audit-page reads and
post-GC heap deltas; it is explicitly not a 100k capacity claim. On the exact
candidate CRuby 4.0.6 run without YJIT, 500 payouts produced 7,002 facts,
0.0407 seconds Analytics replay, 0.6982 seconds restore, 0.0003 seconds for
100 unfiltered 256-fact page reads and 0.0007 seconds for 100 payout/type
filtered page reads. The same run measured 500 concurrent payouts across four
workers at 696.9 ops/s and 7,002 facts. The append-only index is deliberately
bounded to payout/type selection; full durable history remains the source for
replay and audit correctness, and no production-scale claim is inferred.

## 10. Architecture red flags during v0.3.1

Treat these as warnings requiring explicit justification:

- adding another independent eligibility calculation;
- adding another weighted provider score that can trade away higher-priority constraints;
- introducing PSP-specific recipient fields into generic core;
- adding a restorer/validator that reimplements a live business rule instead of sharing it;
- exposing additive analytics without measure/currency identity;
- adding adaptive routing before deterministic quality is statistically defensible;
- making API/dashboard own provider-selection logic;
- optimizing away facts needed to prove economic ownership/recovery.

## 11. Desired state before TZ

Before the official TZ, the architecture should have no known generic reason to change fundamentally.

The expected TZ delta should primarily affect:

- exact policy defaults/formulas;
- provider/input/output schema mapping;
- judge/runtime integration;
- scoring-sensitive optimization weights/objectives;
- official load/performance gates;
- specific acceptance behavior.

If the TZ would still require inventing a generic payout execution payload, fixing unit-unsafe analytics or defining what recovery selection means, v0.3.1 is not finished.
