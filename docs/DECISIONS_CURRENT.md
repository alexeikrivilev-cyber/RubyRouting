# Current Decisions — Product Convergence

This file is the current decision supplement for v0.3. Historical rationale remains in `docs/DECISIONS.md`.

Where this file conflicts with the late 2026-08-28 D-042..D-048 “v1.0 delivered” feature-burst decisions, this file wins.

## D-049 — false v1.0/product-complete claim revoked

Status: accepted.

Decision: repository state at `30b4fb3...` is a strong routing checkpoint, not a delivered industrial v1.0. v0.3 Product Convergence is current.

Rationale: several added modules were disconnected, misleadingly named, unsafe as product boundaries, or not integrated into the canonical routing path despite green tests.

## D-050 — one canonical routing pipeline

Status: accepted.

Decision: all production behavior integrates through:

`Intent -> Policy -> Opportunity -> Admission -> Allocation -> Optimization -> Atomic Commit -> Provider -> Observation -> Lifecycle/Recovery -> Durable State -> Analytics/API`.

A module outside this flow must be removed, demoted to demo/experimental support, or redesigned.

## D-051 — allocation authority precedes optimization

Status: accepted.

Decision: safety, hard eligibility, operational admission and allocation obligations define the admissible action set before reliability/cost/latency optimization.

A generic weighted score is not allowed to silently trade away the allocation contract.

Rationale: the payout case explicitly requires configured traffic distribution; “smart” optimization is subordinate to that business obligation unless policy explicitly says otherwise.

## D-052 — concurrent exposure and throughput rate are different state

Status: accepted.

Decision:

- concurrent/amount exposure is reserved while an operation can consume provider capacity and released by lifecycle;
- TPS/RPS/throughput budget is consumed over time and is not released when a payout finishes.

Rationale: one counter cannot correctly represent both semantics.

## D-053 — replay is not restart recovery

Status: accepted.

Decision: rebuilding a read projection from facts does not prove a fresh working process can safely continue unresolved payouts.

Any durability/recovery implementation must restore/rebuild the live state required for safe continuation, including ownership, operation contract/idempotency, policy binding, dedup/order and required reservations.

Malformed durable financial history must not be silently skipped.

## D-054 — provider normalization owns economic semantics

Status: accepted.

Decision: raw provider/webhook input cannot directly assert trusted `safe_to_release`, attribution or terminal economic meaning. Provider-specific adapters/normalizers derive normalized domain evidence from authoritative provider semantics.

## D-055 — provider-brand/BIN heuristics are not generic core

Status: accepted.

Decision: generic routing may use typed context such as method/rail/destination/currency, but hardcoded BIN tables, bank-brand assumptions and fake rail-specific “real-world” adapters are not core unless the official TZ/provider contract requires them.

Demo/plugin mappings must be explicit and clearly named.

## D-056 — coordinator remains atomic facade but not final god object

Status: accepted.

Decision: keep one atomic correctness boundary, but incrementally extract focused allocation/admission/lifecycle/fact/health responsibilities behind the facade as tests prove equivalence.

No microservice implication follows from this decomposition.

## D-057 — build the product before the TZ

Status: accepted.

Decision: v0.3 aims at a nearly finished product before authoritative TZ. The later TZ phase reconciles exact semantics/interfaces/scoring rather than starting implementation.

Only truly authoritative unknowns are blocked; generic case-relevant product mechanics remain active work.

## D-058 — cleanup over speculative preservation

Status: accepted.

Decision: disconnected/misleading production modules may be deleted even if they contain potentially useful ideas. Reintroduction requires a current SPEC-004 requirement, canonical architecture placement and adequate tests.

Rationale: a smaller coherent product is superior to a larger repository with contradictory semantics and false maturity signals.

## D-059 — recoverable deviation is not historical debt

Status: accepted and reversible when the official TZ or a later product
decision requires an explicit debt mechanism.

Decision:

- v0.3 records allocation deviation and classifies whether a later admissible
  primary decision may improve it;
- v0.3 does not create a historical catch-up queue or burst obligation;
- recovery/fallback assignments never advance the primary allocation ledger;
- any future debt mode must be an explicit policy capability with durable debt
  state, a bounded catch-up rate/burst, and its own invariant and replay tests.

Rationale: silently treating every recoverable deviation as debt would turn
provider recovery into an uncontrolled traffic burst and would blur the
boundary between primary allocation and recovery safety.

## D-060 — existing health controller is the health state seam

Status: accepted for v0.3 convergence.

Decision: keep mutable provider health state in the focused
`Routing::HealthController`. `State::Coordinator` remains responsible for the
atomic boundary, operation-owned probe reservation/release and durable health
facts. Do not add a `State::HealthLedger` wrapper in v0.3: it would add
indirection without a distinct invariant or persistence contract. Reconsider
only if health state later needs an independently owned durable/admission
transaction.

## D-061 — ambiguous partial durable append poisons the journal

Status: accepted for v0.3 convergence.

Decision: a durable append that is observably complete is reconciled and
published exactly once. An append that leaves a partial or non-prefix durable
history poisons the journal; the current process must reject further writes and
a fresh process must surface the corruption rather than continuing with reused
fact identities. A failure with an unchanged durable prefix may remain a
retryable I/O error.

Rationale: rollback of in-memory projections cannot repair a journal whose
visibility is ambiguous. Continuing after a partial append would silently split
financial history and make subsequent fact identity unsafe.

## D-062 — durable identity and time values stay canonical

Status: accepted for v0.3 convergence.

Decision: provider IDs in durable facts must be canonical non-empty Strings, and
fact timestamp fields must be `Time` or nil. Provider arrays in durable
opportunity traces follow the same identity rule. Live observations and
coordinator clocks enforce the corresponding `Time` contract before facts or
lifecycle state are created.

Rationale: accepting whitespace/symbol provider identities or arbitrary timestamp
values would let a malformed history diverge from live provider lookup or fail
later during TTL/age projection instead of being rejected at the durability
boundary.

## D-063 — policy activation order is explicit

Status: accepted for v0.3 convergence.

Decision: `PolicyRegistry` treats the most recently registered policy for a
scope as active. Policy epochs remain opaque identifiers; registry selection
does not infer numeric or lexicographic ordering from their strings. Registering
an existing immutable epoch may explicitly reactivate it.

Rationale: lexical epoch ordering makes values such as `"9"` and `"10"`
ambiguous and can select an older policy silently. Registration order provides a
small deterministic activation contract while preserving immutable policy
identity and explicit epoch history.

## D-064 — durable decoding rejects floating-point values

Status: accepted for v0.3 convergence.

Decision: `FactCodec` rejects `Float` values during both encoding and decoding,
including nested values in tagged arrays and hashes. A crafted durable record
with a floating-point payload is explicit `DurableCorruptionError`.

Rationale: preventing floats only on the write path is insufficient because a
damaged or adversarial journal can bypass the encoder. Decode-time rejection
keeps durable history aligned with the exact Integer/Rational financial policy.

## D-065 — provider catalog history has an explicit internal seam

Status: accepted for v0.3 convergence.

Decision: `State::ProviderCatalogLedger` owns the current functional opportunity
map and ordered provider registration/removal timeline. `State::Coordinator`
remains the atomic facade and publishes the corresponding facts under its
transaction boundary. During restore, durable catalog facts are replayed from an
empty ledger; optional runtime opportunities are validated as configuration
inputs, but every supplied provider must still be current in the durable
history. They cannot add or resurrect a provider without a new atomic
registration through the coordinator.

The ledger requires strictly advancing fact sequences for timeline events and
does not perform provider I/O.

Rationale: provider identity/currentness is a distinct invariant needed by
durable provider-system and opportunity facts. Making it a focused deep module
prevents the coordinator from duplicating timeline semantics while preserving
one atomic correctness boundary.

## D-066 — observation identity and ordering have one internal owner

Status: accepted for v0.3 convergence.

Decision: `State::ObservationLedger` owns the shared identity signature and
deduplication rule for live observations and durable restore. It also owns the
provider-authoritative sequence rule, transport-classification exception and
late-success conflict classification. `State::Coordinator` remains responsible
for atomic fact publication and lifecycle/capacity/health side effects.

Rationale: implementing the same observation rules separately in live and restore
paths creates a recovery divergence risk at the exact boundary where duplicate,
delayed and out-of-order provider events must remain safe. A focused ledger
centralizes those semantics without introducing a second transaction boundary.

## D-067 — durable observations use the live observation input contract

Status: accepted for v0.3 convergence.

Decision: before a durable `provider_observed` fact can affect working state,
`State::ObservationLedger` requires canonical non-empty String observation,
provider, operation and attempt IDs,
boolean `applied`/`conflict`/`safe_to_release` fields, a non-negative provider
sequence or nil, a `Time`/nil observation timestamp, and supported outcome,
attribution and transport values.

Rationale: restore must not accept values that live `ProviderObservation` could
never produce. In particular, Ruby truthiness would otherwise turn strings or
integers into financial/lifecycle authority during restart.

## D-068 — durable fact collection boundaries are explicit

Status: accepted for v0.3 convergence.

Decision: `FactStore`, `FactCodec.encode_batch` and `FileJournal.append_many`
require enumerable fact collections and reject non-enumerable input with an
explicit `ArgumentError` before attempting conversion or durable mutation. Their
shared collection boundary consumes `#each` directly, so an each-only
enumerable is valid and does not depend on an incidental `#to_a` method.

Rationale: durable state APIs should expose a stable input contract. An internal
`NoMethodError` from `.to_a` obscures whether caller input was invalid and makes
the boundary inconsistent with the provider-catalog and observation contracts.

## D-069 — live and restore outcome reduction share the lifecycle reducer

Status: accepted for v0.3 convergence.

Decision: `State::LifecycleLedger.status_for` is the read-only outcome-to-status
reduction used when durable observations restore derived payout status. Live
observation application continues to use the same ledger's stateful reducer;
restore does not maintain an independent status mapping.

Rationale: durable replay must derive the same status as live processing without
duplicating lifecycle rules or inventing a second transition boundary.

## D-070 — domain boolean inputs are strict

Status: accepted for v0.3 convergence.

Decision: `ProviderOpportunity`, `ProviderCapabilities`,
`ProviderOperationContract` and `NormalizedOutcome` accept only actual Boolean
values for their Boolean fields (apart from the intentional nil default for
`NormalizedOutcome#safe_to_release`). Truthy strings, integers and other
coercible values are rejected.

Rationale: Ruby truthiness can silently turn malformed live or durable provider
configuration into a different routing or recovery contract. Strict domain
construction makes the provider/application boundary and durable restore agree
on the type of operational and release authority.

## D-071 — fallback analytics keep attempt and outcome semantics separate

Status: accepted for v0.3 convergence.

Decision: `fallback_recovery_count` counts distinct payouts that received at
least one recovery assignment, `successful_fallback_recovery_count` counts
those that eventually settled through a recovery assignment, and
`recovery_attempt_count` counts recovery assignment operations. These metrics
must not be aliases.

Rationale: a fallback can be attempted and still end in terminal failure or a
second unresolved state. Collapsing attempted and successful recovery hides
execution quality and makes the analytics contract misleading.

## D-072 — analytics preserve economic role across resolution retries

Status: accepted for v0.3 convergence.

Decision: when a `resolve` or `retry_same` decision reuses an existing
operation, analytics retain that operation's original `primary` or `recovery`
role. A control-plane resolution action must not overwrite the economic role
used to attribute a later provider outcome.

Rationale: an idempotent retry after an UNKNOWN recovery is still the same
fallback operation. Overwriting its role would make successful fallback
recovery disappear from analytics even though the payout settled through the
recovery path.

## D-073 — journal JSON roots are explicitly validated

Status: accepted for v0.3 convergence.

Decision: `FileJournal` accepts only JSON object roots for durable records and
reports any other root shape as `DurableCorruptionError` before dispatching to
the fact decoder.

Rationale: malformed durable history must fail through the explicit corruption
contract. Calling object accessors on an array, scalar or null root would leak
an implementation `TypeError`/`NoMethodError` and weaken the restart boundary.

## D-074 — durable health transitions must match their preceding signal

Status: accepted for v0.3 convergence.

Decision: during working restore, a `health_state_changed` fact is accepted
only immediately after the corresponding `health_signal` and only when its
`from -> to` states equal the transition produced while restoring that signal.
A missing, interleaved, extra or forged transition is durable corruption. The
restore must finish with no unconsumed health transition expectation.

Rationale: validating only the destination state permits a damaged audit trail
to rewrite the causal predecessor while leaving the current health projection
apparently plausible. Ordered linkage preserves the health controller's
state-machine evidence instead of treating the transition fact as an
independent annotation.

## D-075 — probe reservations are single committed-operation facts

Status: accepted for v0.3 convergence.

Decision: working restore accepts `health_exposure_reserved` only once for an
operation, while the operation is still in `committed` phase and before the
payout has acquired an owner. A duplicate or post-release reservation is
durable corruption, even if the health controller's owner-aware API would
return an idempotent success.

Rationale: idempotent runtime reservation APIs protect live retries, but they
must not make duplicate durable facts look valid. Probe exposure is a bounded
resource tied to one committed operation; accepting a second reservation fact
after release could recreate exposure without a new allocation/ownership event.

## D-076 — durable decisions must preserve the operation contract and causal role

Status: accepted for v0.3 convergence.

Decision: working restore treats `decision_committed` as a causal control-plane
fact, not merely an operation lookup. Assignment decisions must be unique,
policy-bound, role-consistent, measure-consistent and backed by the persisted
operation/idempotency contract. `resolve` requires `status_lookup`, while
`retry_same` requires `idempotent_retry`; both require the unresolved owner,
the correct resolution role and no already-pending control-plane dispatch.

Rationale: a duplicated assignment fact could turn a post-dispatch restart into
an unsafe same-operation retry, and a forged resolution action could bypass the
provider contract. Durable restore must preserve the same economic and provider
authority ordering as live decision creation.

## D-077 — durable observation decisions are derived, not trusted

Status: accepted for v0.3 convergence.

Decision: working restore recomputes the `applied` and `conflict` decisions for
each `provider_observed` fact from the restored current owner, attempt phase,
provider sequence and normalized outcome. Persisted Boolean flags must match
that result; a late success cannot be made non-conflicting by changing the
durable annotation or omitting its conflict fact.

Rationale: `applied` and `conflict` are coordinator decisions, not external
provider evidence. Trusting them during restore allowed a resigned durable
history to hide an economic conflict while leaving the final settlement state
apparently valid.

## D-078 — durable releases must follow terminal operation outcomes

Status: accepted for v0.3 convergence.

Decision: working restore accepts capacity, ownership and health-exposure
release facts only after the linked operation has reached a terminal phase with
a compatible outcome and while the payout still owns that operation. Capacity
reservation facts retain their actual live order: a reservation may precede the
assignment decision, but must later link to one committed pending operation;
recreated reservations after release are corruption.

Rationale: release facts change bounded admission and ownership exposure. A
durable history that releases before the provider outcome, or recreates a
reservation after release, can make capacity/health projections appear
conserved while allowing an impossible future dispatch.

## D-079 — throughput consumption is tied to one committed dispatch

Status: accepted for v0.3 convergence.

Decision: working restore accepts `throughput_consumed` only for a known provider
operation in `committed` phase, before ownership acquisition and while its
dispatch is pending. The operation may consume one throughput token only once;
duplicate or post-release consumption is durable corruption.

Rationale: time-window rate tokens are not released with concurrent capacity.
Without causal ordering and multiplicity checks, replay could permanently
inflate provider rate exposure after a safe failure or terminal settlement.

## D-080 — allocation facts are unique and pre-dispatch

Status: accepted for v0.3 convergence.

Decision: working restore accepts one `allocation_committed` fact per operation,
only while that assignment is committed, owner-free and pending dispatch.
Primary allocation facts update `AllocationLedger` exactly once; recovery facts
retain their operation identity without changing primary allocation authority.

Rationale: allocation is contractual state, not an analytics annotation. A
duplicate or post-release fact must not increment the exact allocation ledger a
second time or recreate a historical assignment.

## D-081 — settlement is a single finalization fact

Status: accepted for v0.3 convergence.

Decision: working restore rejects a second `settlement_recorded` fact for a
payout, including one appended after a reversal. A settlement is accepted only
for the linked settled successful operation and can establish final success once.

Rationale: settlement is the economic finalization boundary. Replaying it twice
could double settlement analytics or overwrite a valid reversed final state.

## D-082 — economic conflicts are unique by observation identity

Status: accepted for v0.3 convergence.

Decision: working restore accepts at most one `economic_conflict` fact for each
late observation identity, after validating its released operation and observed
linkage. A duplicate conflict fact is durable corruption.

Rationale: a late provider success is one economic incident even if delivery is
replayed. Explicit observation identity prevents durable replay from inflating
conflict counts or incident history.

## D-083 — observation-derived facts retain their source identity

Status: accepted for v0.3 convergence.

Decision: durable `health_signal`, `quality_signal` and
`transport_classified` facts emitted from provider observations carry the
canonical source payout and observation identity. Working restore requires the
source `provider_observed` fact to have already been restored, validates the
derived provider/outcome/transport semantics and projection values, and rejects
duplicate derived facts. Source-free manual health signals remain explicit
operator events and are not conflated with observation evidence.

Rationale: observation deduplication protects the live coordinator, but a
crafted durable history could append a derived fact without replaying the source
observation. That could inflate health/quality state or transport analytics and
would make the durable audit trail disagree with the provider evidence.

## D-084 — conflicting observations require an economic-conflict fact

Status: accepted for v0.3 convergence.

Decision: when working restore derives `conflict: true` for a late monetary
success observation, it records a pending conflict obligation. The matching
`economic_conflict` fact must follow that observation (after an optional
transport classification for the same source), must validate the released
operation linkage, and must be consumed before restore completes. An omitted or
misordered conflict fact is durable corruption.

Rationale: the observation decision and the incident record are separate facts.
Accepting the former without the latter leaves payout lifecycle status plausible
while silently erasing the economic conflict from state and analytics.

## D-085 — assignments must match the durable feasibility evaluation

Status: accepted for v0.3 convergence.

Decision: working restore accepts an assignment only when its provider appears in
the preceding `opportunity_evaluated` feasible cohort. That evaluation's
provider-specific throughput and health traces must also match the durable
provider catalog and health projection before the assignment is restored.

Rationale: policy weight and operation contract alone do not prove eligibility.
Without the evaluation linkage, a damaged history could assign a provider that
was unavailable, ineligible or outside the evaluated opportunity cohort while
leaving a plausible pending owner.

## D-086 — an assignment's atomic side-fact bundle is complete

Status: accepted for v0.3 convergence.

Decision: working restore requires every committed assignment to publish its
allocation fact before optional throughput/probe reservations and ownership
acquisition. A provider with a throughput budget must have its matching
`throughput_consumed` fact; a probing provider must have its
`health_exposure_reserved` fact; a committed pending operation must have
ownership. Missing bundle members are durable corruption.

Rationale: the coordinator publishes these facts as one atomic mutation. Letting
restore accept a partial bundle would undercount contractual allocation or
operational exposure and could unlock a payout without preserving its economic
owner.

## D-087 — the evaluated allocation snapshot is an exact durable trace

Status: accepted for v0.3 convergence.

Decision: working restore requires an `opportunity_evaluated` allocation key,
revision and provider measures to equal the exact `AllocationLedger` snapshot
at that fact boundary. Shape-compatible but forged allocation traces are durable
corruption.

Rationale: the allocation evaluation is the durable bridge between contractual
allocation and the later assignment. Checking only that its fields look like a
snapshot would let damaged history claim a different corridor or ledger revision
while the committed allocation facts continue from another state.

## D-088 — the evaluated capacity trace is an exact admission snapshot

Status: accepted for v0.3 convergence.

Decision: working restore requires an `opportunity_evaluated` capacity trace for
every evaluated provider, and each trace must equal the exact
`AdmissionLedger` capacity projection at that fact boundary. Shape-compatible
but forged capacity usage is durable corruption.

Rationale: capacity is a hard admission gate, not an informational annotation.
If restore trusted a forged `used_slots`, `used_count` or amount exposure trace,
the durable evaluation could claim a different operational state from the one
that admitted the assignment and hide an admission-accounting defect.

## D-089 — durable health signals preserve their provenance kind

Status: accepted for v0.3 convergence.

Decision: every durable `health_signal` records whether it is a manual control
signal or an observation-derived signal. Restore requires manual signals to be
source-free and observation-derived signals to retain the canonical source
payout/observation pair and matching outcome evidence.

Rationale: manual health control is a valid source-free operation, so the mere
absence of a source cannot prove corruption. An explicit provenance kind keeps
that operation while preventing damaged observation-derived evidence from being
silently downgraded into manual state.

## D-090 — allocation facts retain the exact evaluated ledger key

Status: accepted for v0.3 convergence.

Decision: working restore requires every `allocation_committed` fact to carry
the exact allocation key from the immediately preceding `opportunity_evaluated`
fact for that payout. A key with the same policy prefix but a different
opportunity cohort or window is durable corruption.

Rationale: the full allocation key determines the policy/accounting universe.
Checking only the policy prefix allows a damaged history to write contractual
allocation under another cohort while the decision and evaluation appear valid.

## D-091 — provider admission configuration has one durable representation

Status: accepted for v0.3 convergence.

Decision: provider-registration restore requires the top-level `capacity` and
`throughput` fields to equal the same values in the canonical provider
`definition`. A split or forged duplicate admission definition is durable
corruption.

Rationale: the registration fact feeds both working admission restoration and
projection/replay consumers. Accepting disagreement lets those consumers use
different capacity or rate limits for the same provider history.

## D-092 — explicit throughput availability is an admission hard gate

Status: accepted for v0.3 convergence.

Decision: `AdmissionLedger#throughput_available?` rejects an opportunity whose
explicit `throughput_available` flag is false before considering whether a
time-window budget exists or has remaining tokens.

Rationale: the provider runtime gate is an operational admission condition in
its own right. A missing rate budget does not authorize routing through a
provider explicitly marked unavailable for throughput operations.

## D-093 — durable opportunity feasibility is recomputed, not merely nested

Status: accepted for v0.3 convergence.

Decision: working restore recomputes each `opportunity_evaluated` functional and
feasible cohort, exclusion maps, allocation exclusions and runtime-feasibility
assessment from the restored intent, policy, provider catalog and exact
admission/health projections. Throughput evaluation uses the fact's controlled
`evaluated_at` boundary rather than the restart process's current wall clock.

Rationale: nested provider ID lists and copied traces do not prove that an
assignment was actually eligible or admitted. Recomputing the hard gate prevents
forged availability, health, capacity, throughput or policy-constraint results
from becoming a durable decision basis.

## D-094 — opportunity evaluations preserve exact decision context

Status: accepted for v0.3 convergence.

Decision: working restore requires the persisted opportunity-evaluation quality,
ranking, health-policy, static-policy and previous-outcome traces to equal the
corresponding typed state at that fact boundary. A decision evaluation may not
silently replace its quality or policy context while retaining a plausible
eligibility cohort.

Rationale: eligibility recomputation closes the routing safety gate, but the
evaluation also feeds explainability and optimization audit. Accepting forged
context would make durable analytics describe a different decision basis than
the one used by the restored coordinator, even when the selected provider remains
operationally admissible.

## D-095 — assignment decisions preserve the exact allocation/optimization trace

Status: accepted for v0.3 convergence.

Decision: working restore recomputes an assignment decision from the preceding
opportunity evaluation's allocation snapshot, feasible cohort, accounting
universe and quality evidence. It requires the selected provider, allocation
candidate trace, discrepancy, share violations, tolerance, optimization trace,
runtime feasibility and soft-constraint evidence to match that recomputation.

Rationale: checking only that an assignment provider was feasible preserves
economic safety but permits durable audit history to claim a different allocation
or optimization basis. The decision fact is both a control-plane input and the
typed explanation of the committed choice, so its trace must be coherent with
the exact evaluation that preceded it.

## D-096 — allocation facts preserve policy and reservation linkage

Status: accepted for v0.3 convergence.

Decision: working restore requires the duplicated policy identity, epoch, scope
and fingerprint in `allocation_committed` to match the pinned policy. Its
`capacity_reserved` flag must also match the operation's restored capacity
reservation at that causal point.

Rationale: allocation facts feed replay, analytics and the durable assignment
bundle. Accepting split policy metadata or a forged reservation flag would let
audit/projection consumers describe a different contract from the one enforced
by the coordinator, even when the operation linkage itself remains valid.

## D-097 — resolution decisions preserve recovery classification

Status: accepted for v0.3 convergence.

Decision: working restore recomputes the recovery classification for each
`resolve` or `retry_same` decision from the restored payout status, owner,
operation phase/contract and policy budgets. The action, reason and reason codes
must match that classification; a durable fact may not change a status lookup
into a same-operation retry or rewrite its explanation.

Rationale: both actions retain the same economic operation but have different
provider semantics and retry risk. Capability checks alone allow a history to
choose the wrong control action when both capabilities exist, so restore must
preserve the same classification that live routing would have committed.

## D-098 — non-operation decisions preserve their durable rationale

Status: accepted for v0.3 convergence.

Decision: working restore must not return early for a decision without an
operation. It recomputes final/defer classification, switch-budget deferral and
no-route allocation/runtime traces; the persisted action, reasons,
reason-codes and runtime-feasibility payload must match. The adapter-unavailable
branch additionally requires canonical provider-availability context that
excludes the unresolved owner.

Rationale: no-operation decisions do not mutate ownership, but their audit
payload still describes why routing stopped. Accepting a forged payload would
let replay/analytics claim a different safety or admission outcome while the
working state remained superficially plausible.

## D-099 — assignment rationale is shared with live proposal construction

Status: accepted for v0.3 convergence.

Decision: the `DecisionEngine` owns construction of assignment reasons, reason
codes and deviation classification alongside the constrained allocation. Working
restore invokes that same construction from the preceding validated evaluation
and requires matching rationale, `allocation_deviation_cause` and
`allocation_deviation_recoverability`, in addition to the exact selection trace.

Rationale: recomputing only the selected provider and allocation numbers could
leave audit and analytics semantics forged. A shared proposal path keeps live
routing and restart validation aligned without turning lower-level optimization
into a safety or allocation score.

## D-100 — intent registration is unique in durable history

Status: accepted for v0.3 convergence.

Decision: working restore rejects every second `intent_registered` fact for the
same payout, including an identical replay of the original intent. A payout may
have one immutable economic intent registration; subsequent lifecycle facts
must build on that state rather than reopen its identity.

Rationale: treating duplicate intent registration as idempotent during restore
could make a malformed history look like two ownership roots or hide a broken
append boundary. Live duplicate submission remains idempotent at the command
surface, while the durable fact stream remains strictly singular.

## D-101 — policy registration is unique per payout binding

Status: accepted for v0.3 convergence.

Decision: working restore rejects a second `policy_registered` fact for the same
payout, whether it repeats the same scope or attempts a different binding. A
payout's policy identity is pinned once before its opportunity evaluation.

Rationale: multiple policy-registration facts would make the durable decision
basis depend on replay interpretation and could conceal a policy switch without
an explicit lifecycle boundary.

## D-102 — durable static-feasibility evidence matches the policy definition

Status: accepted for v0.3 convergence.

Decision: working restore recomputes the typed `RoutingPolicy` from its durable
definition and requires the persisted `static_feasibility` field to equal that
policy's canonical result, in addition to the existing identity and fingerprint
checks.

Rationale: a policy fingerprint proves identity, but a split static-feasibility
field could still make replay and audit describe a different admission basis.

## D-103 — provider registration policy snapshots are coherent

Status: accepted for v0.3 convergence.

Decision: each `provider_opportunity_registered` fact must carry health and
quality policy snapshots equal to the coordinator's canonical controllers.
Registration definitions may not silently replace the operational policy used
by later admission, health or quality decisions.

Rationale: provider registration is the durable source for restoring the
controller policies when no external configuration is supplied. Every repeated
registration must therefore agree, so a provider replacement cannot fork the
policy context across history.

## D-104 — health-signal policy provenance is validated

Status: accepted for v0.3 convergence.

Decision: working restore requires the `health_signal.policy` snapshot to equal
the canonical health controller policy before applying the signal.

Rationale: health state reduction may remain numerically plausible while an
audit consumer is shown a different threshold/probing contract. The policy
snapshot is typed durable context, not an ignored annotation.

## D-105 — provider interaction start follows the operation phase

Status: accepted for v0.3 convergence.

Decision: restore accepts `attempt_started` only for `assign`, `resolve` or
`retry_same`, with pending mode and operation phase matching the action
(`dispatching` for assignment/retry and `resolving` for resolution).

Rationale: the phase-change fact is the causal proof that the process crossed
into provider interaction. Accepting an interaction start while the attempt was
still `committed` could strand ownership after restart while falsely recording
that dispatch had begun.

## D-106 — probing reservation keeps attempt identity

Status: accepted for v0.3 convergence.

Decision: restore requires `health_exposure_reserved.attempt_id` to match the
committed operation's attempt identity, alongside provider, phase, ownership,
allocation and probe-state checks.

Rationale: operation IDs scope the reservation ledger, but the durable fact also
claims which attempt acquired exposure. Dropping that link would leave a
plausible capacity/health bundle with a forged attempt explanation.

## D-107 — ownership release reason matches the terminal outcome

Status: accepted for v0.3 convergence.

Decision: restore requires `ownership_released.reason` to equal the restored
attempt outcome status before releasing ownership and capacity.

Rationale: release reason is emitted from the normalized lifecycle outcome and
is consumed by replay/audit. Accepting a divergent reason would preserve the
state transition while corrupting the causal explanation of why economic
ownership ended.

## D-108 — durable operation contracts match provider capabilities

Status: accepted for v0.3 convergence.

Decision: working restore recomputes the operation contract from the durable
provider capabilities and pinned policy recovery overrides. Every contract
field, including retry/status capabilities, idempotency identity, TTL,
deadline, version and authoritative sequence, must match the canonical
contract used at assignment.

Rationale: provider-operation contracts determine whether restart may resolve
or retry an unresolved operation and how observations are ordered. Checking
only the provider and idempotency key could make a forged history grant or
remove a safe recovery capability.

## D-109 — provider interaction starts preserve the committed action

Status: accepted for v0.3 convergence.

Decision: working restore records the latest operation decision action and
requires every `attempt_started.action` to match it, in addition to the
existing pending-mode, phase and identity checks.

Rationale: `assign`, `retry_same` and `resolve` have different interaction
budgets and provider semantics. A forged action could change resolution
accounting or recovery behavior while leaving the operation phase plausible.

## D-110 — analytics is idempotent for duplicate observations

Status: accepted for v0.3 convergence.

Decision: analytics deduplicates an exact repeated `provider_observed` fact by
its payout/observation identity and rejects a conflicting repeated payload.
This keeps first-attempt, failure and eventual-success metrics aligned with
the working observation ledger's idempotency semantics.

Rationale: exact duplicate observation delivery is a supported boundary. A
projection that counted every repeated fact could inflate reliability metrics
even though the live coordinator correctly applied the event only once.

## D-111 — reconciliation blocks preserve exact expiry evidence

Status: accepted for v0.3 convergence.

Decision: working restore requires a reconciliation block to use the canonical
`operation_contract_expired` reason, a `Time` `blocked_at`, exact non-negative
elapsed seconds from the operation's committed time, and a TTL/deadline that
was actually expired at that timestamp.

Rationale: reconciliation is a safety stop that preserves economic ownership
until an explicit observation. Accepting forged expiry evidence could make a
non-expired operation appear safely blocked or corrupt unresolved-age and
recovery audit semantics after restart.

## D-112 — policy scope identity is globally immutable in restore

Status: accepted for v0.3 convergence.

Decision: working restore rejects a second `policy_registered` fact that reuses
the same `(policy_id, policy_epoch, policy_scope)` with a different policy
definition or fingerprint, even when it belongs to another payout.

Rationale: the coordinator resolves pinned policies through one shared scope
registry. Allowing a later payout to replace that entry would make restored
working behavior depend on fact interleaving and could invalidate earlier
allocation, admission or recovery decisions.

## D-113 — policy registry construction uses the shared collection boundary

Status: accepted for v0.3 convergence.

Decision: `PolicyRegistry` consumes initial policies through the shared
each-based collection helper, while retaining the existing nil-as-empty
constructor behavior.

Rationale: the product's public collection contract is enumeration, not
`Array()` coercion. Keeping one boundary prevents valid each-only policy
sources from failing in the application facade or creating a special path
that differs from the coordinator and projection APIs.

## D-114 — durable policy identity fields remain canonical strings

Status: accepted for v0.3 convergence.

Decision: restore requires policy ID, epoch, scope and fingerprint fields in
policy registration, opportunity evaluation and allocation facts to be
non-empty, trimmed Strings; it does not normalize crafted symbols or numbers
with `.to_s`.

Rationale: live facts serialize immutable policy identity as Strings. Silent
normalization at restore would make malformed history appear valid and would
allow different transport representations to bypass the same identity and
fingerprint checks.

## D-115 — durable operation identities remain canonical strings

Status: accepted for v0.3 convergence.

Decision: restore requires operation IDs, attempt IDs, observation IDs and
reversal IDs used by lifecycle, admission, settlement, conflict and derived
facts to be non-empty, trimmed Strings; it does not coerce numeric or symbolic
values with `.to_s`.

Rationale: these identifiers bind economic ownership, provider idempotency,
release ordering and reconciliation evidence. Accepting alternate transport
types would allow malformed history to alias a real operation while appearing
valid to the working coordinator.

## D-116 — money-moving attempts have unique identities per payout

Status: accepted for v0.3 convergence.

Decision: restore rejects a new assignment whose `attempt_id` is already used
by another money-moving attempt for the same payout. Resolution and retry
decisions may continue to reference their existing attempt as defined by the
operation contract.

Rationale: attempt identity scopes provider interaction, observation ordering
and recovery attribution. Reusing it across primary/recovery assignments could
alias two economic operations while leaving distinct operation IDs plausible.

## D-117 — available-provider filters use the shared collection contract

Status: accepted for v0.3 convergence.

Decision: the coordinator normalizes `available_provider_ids` by consuming its
`#each` interface, accepting each-only collections and preserving canonical
provider ID validation before routing or durable decision context is created.

Rationale: adapter availability is an operational admission input. A special
`.map` requirement at this boundary would make valid application/provider
collections fail before the canonical routing flow, while inconsistent input
handling could leak transport concerns into routing decisions.

## D-118 — durable hash entries cannot silently overwrite keys

Status: accepted for v0.3 convergence.

Decision: `FactCodec` rejects a tagged durable Hash whose entry list decodes to
the same key more than once, instead of allowing the later value to overwrite
the earlier one.

Rationale: the canonical Ruby Hash encoder cannot emit duplicate keys. A
crafted journal with duplicate entries must be classified as corruption rather
than changing a financial, policy or lifecycle payload during decode.

## D-119 — allocation keys are exact at both evaluation and commit

Status: accepted for v0.3 convergence.

Decision: working restore requires the allocation key embedded in an
`opportunity_evaluated` snapshot and the key carried by its corresponding
`allocation_committed` fact to equal the canonical key structurally. Restore
does not normalize key segments with `.to_s` before comparison.

Rationale: the evaluation snapshot and allocation fact are both durable inputs
to the allocation ledger. Type-normalizing either copy could accept a crafted
symbol or numeric segment as the same key while preserving a noncanonical,
ambiguous financial trace.

## D-120 — durable fact envelope identities remain canonical strings

Status: accepted for v0.3 convergence.

Decision: `FactCodec` requires durable fact `type`, `fact_id` and `payout_id`
envelope fields to be non-empty, trimmed Strings, and requires a positive
Integer sequence before constructing a domain `Fact`. It does not allow
`Fact.new`'s in-memory `.to_s` normalization to alias malformed journal
identity values.

Rationale: the envelope identifies the fact and its economic stream before
working restore can validate payload semantics. Accepting numeric or padded
values and normalizing them would make malformed durable history appear to be
an ordinary fact and could alias a payout stream across transport types.

## D-121 — interaction starts validate the live decision commit

Status: accepted for v0.3 convergence.

Decision: `mark_attempt_started` and `mark_resolution_started` validate a
caller-supplied `DecisionCommit` against the current payout operation before
consuming its dispatch token or appending an `attempt_started` fact. The
validated boundary includes payout, operation, attempt, provider, policy epoch,
action, role, lifecycle phase, pending token and provider-operation request
identity/money. Ordinary resolution and restart-resume mutations also update
the live operation-action index used by this validation.

Rationale: a commit is an application command boundary, not an authority to
write arbitrary operation identifiers. Without this check, a stale or forged
commit could append a provider interaction fact whose request and economic
owner referred to different operations, potentially sending the wrong payout
or poisoning durable continuation. Valid stale commits still return `false`
through the existing dispatch-token guard; only identity/request divergence is
rejected.

## D-122 — public collection inputs consume `#each`

Status: accepted for v0.3 convergence.

Decision: public policy, provider-opportunity, eligibility, allocation,
feasibility and quality collection inputs use the shared collection boundary,
which consumes `#each` and materializes a local Array before transformation.
Each-only enumerables are valid wherever the API documents an enumerable
collection; non-enumerable values receive an explicit `ArgumentError`.

Rationale: requiring `.map` at one layer while neighboring coordinator,
catalog, journal and projection boundaries accept any `#each` collection makes
the product API dependent on incidental collection class behavior. The
normalization boundary keeps deterministic ordering and domain validation
without widening routing semantics or introducing a second collection type.

## D-123 — provider transport uncertainty is explicit

Status: accepted for v0.3 convergence.

Decision: the application orchestrator converts only the explicit
`ProviderTransportError` contract into a normalized transport observation.
Provider adapters should return `ProviderTransportResult` values or raise that
typed transport error for classified uncertainty. Malformed observations,
invalid adapter return values and unclassified adapter/programming errors are
not rescued into synthetic `UNKNOWN` outcomes. Because the interaction start
fact is committed before provider I/O, those surfaced errors leave the
operation identity/ownership/phase available for safe resume or operator
repair.

Rationale: a broad `StandardError` rescue at the orchestration boundary hid
provider contract violations and could make a programming error look like
financial evidence. Transport uncertainty is a domain-relevant result and
must be explicit; adapter failures must remain diagnosable without losing the
already-committed economic operation.

## D-124 — payout context label collections use the shared boundary

Status: accepted for v0.3 convergence.

Decision: provider opportunity and policy constraint evaluation consumes
`context[:labels]` through the shared `#each` collection boundary, while
retaining scalar String/Symbol labels as a one-label convenience. Each-only
context collections therefore participate in functional eligibility and hard
policy checks instead of being treated as one opaque object. `PayoutIntent`
materializes nested each-only collections into immutable Arrays before the
intent can enter durable facts, so live and journal-backed routing share the
same canonical value shape.

Rationale: context labels are payout input to the Opportunity and Policy
stages, not merely construction-time configuration. Using `Array(raw)` there
made the public each-only contract inconsistent and could silently exclude a
valid provider from routing; retaining the caller's collection object would
also make the accepted live value impossible to encode in durable history.

## D-125 — facts materialize nested each-only values before durability

Status: accepted for v0.3 convergence.

Decision: `RubyRouting::Fact` materializes nested values that expose `#each`
into immutable Arrays during construction, matching the accepted collection
boundary used by payout inputs and routing APIs. A fact therefore cannot retain
an enumerable object that is accepted in memory but becomes unencodable only
when a journal append is attempted.

Rationale: facts are the durable state boundary, and `FactCodec` supports
materialized domain values rather than arbitrary enumerable objects. Normalizing
at fact construction keeps live and journal-backed facts equivalent and makes
the accepted each-only input contract observable before a financial append.

## D-126 — application provider-event boundaries canonicalize provider IDs

Status: accepted for v0.3 convergence.

Decision: `Application::Commands#reconcile_provider_event` trims and validates
the provider identity once before passing it to a provider normalizer and
compares the normalized observation against that canonical identity. Provider
normalizers therefore receive the same provider key used by the core catalog,
including when an external route supplies surrounding whitespace.

Rationale: provider-event reconciliation is an application boundary, so
noncanonical transport identifiers must not cause a valid normalized event to
be rejected by comparing it with the raw route value. The canonical identity
still enters the existing provider-specific normalizer and core observation
linkage checks; no raw provider outcome fields gain trust.

## D-127 — HTTP normalizer lookup uses canonical provider identity

Status: accepted for v0.3 convergence.

Decision: `Application::HttpApp` canonicalizes the provider path segment before
normalizer lookup and rejects empty or colliding normalized provider-normalizer
configuration keys. The canonical ID is then passed through
`Application::Commands` to the provider-specific normalizer and core
observation linkage.

Rationale: normalizing configuration keys alone is insufficient when an HTTP
route is looked up by its raw path segment; a valid provider event could be
rejected before reaching the application boundary. Silent collision overwrite
would also make webhook semantics depend on hash insertion order.

## D-128 — reversal linkage uses canonical provider and operation identity

Status: accepted for v0.3 convergence.

Decision: `State::Coordinator#record_reversal` canonicalizes provider and
operation IDs before matching settlement/conflict ownership, checking repeated
reversal payloads or aggregating prior reversal amounts. The canonical values
are also passed to `SettlementReversal` and the durable reversal fact.

Rationale: the domain reversal value already treats these identifiers as
trimmed identities, so comparing them against raw command values made a valid
financial reversal dependent on caller whitespace and could break idempotent
replay. Canonicalizing once at the mutation boundary keeps linkage and durable
state consistent without changing the settlement/reversal separation.

## D-129 — public payout lookup uses canonical payout identity

Status: accepted for v0.3 convergence.

Decision: coordinator payout snapshot, policy lookup, restart-operation lookup
and reversal state lookup canonicalize payout IDs before accessing the payout
registry. Application audit filtering and the replay lifecycle projection apply
the same canonicalization before matching durable facts.

Rationale: `PayoutIntent` stores a trimmed payout identity, but several public
read/resume/mutation and replay projection paths previously used raw `to_s`
lookup. A caller using the equivalent external form with surrounding whitespace
could therefore miss an existing payout or its history. One boundary rule keeps
API reads, resume, reversal and durable state addressing aligned.

## D-130 — replay provider snapshots use canonical provider identity

Status: accepted for v0.3 convergence.

Decision: direct replay capacity and throughput projections canonicalize provider
IDs before snapshot lookup, matching the application query and live admission
boundaries. Replay health and quality projections already delegate to
controllers with the same identity rule.

Rationale: durable provider identities are canonical strings, but direct
projection consumers can still supply the equivalent external identifier with
surrounding whitespace. Keeping replay snapshots aligned with live/application
lookup prevents an avoidable read-path divergence without changing admission or
financial semantics.

## D-131 — policy provider boundaries use canonical IDs and shared collections

Status: accepted for v0.3 convergence.

Decision: policy ranking/weight/measure/share accessors canonicalize provider IDs
before lookup. `RoutingPolicy#weights_for` and `#measure_exclusions` consume
provider collections through the shared `Collection.to_array` boundary before
their deterministic reduction.

Rationale: policy definitions store canonical provider identities, while direct
policy callers may provide equivalent padded IDs or valid each-only enumerables.
Keeping these public policy boundaries explicit prevents provider selection and
policy exclusions from diverging based on collection shape or caller whitespace.

## D-132 — canonical policy map collisions are rejected

Status: accepted for v0.3 convergence.

Decision: ranking metrics, per-provider measure limits and per-provider share
limits reject duplicate keys after provider-ID canonicalization instead of
silently allowing a later Hash entry to overwrite an earlier configuration.

Rationale: policy configuration is business truth for allocation and
optimization. Treating `"A"` and `" A "` as different input keys would make the
result depend on Hash insertion order and could change routing without an
explicit policy change.

## D-133 — allocation snapshot identity is canonical and collision-safe

Status: accepted for v0.3 convergence.

Decision: `AllocationSnapshot` canonicalizes provider IDs for construction,
lookup and commit updates, and rejects duplicate input keys after
canonicalization.

Rationale: the allocation snapshot is authoritative primary-distribution state.
Allowing `"A"` and `" A "` to address different buckets could create a second
allocation counter or silently overwrite committed measures, violating exact
distribution accounting. The value object now enforces the same identity rule
as policy and provider boundaries.

## D-134 — quality snapshots use canonical provider identity

Status: accepted for v0.3 convergence.

Decision: `ProviderQualitySnapshot` canonicalizes provider IDs at construction,
and `QualityController#snapshots` canonicalizes each provider ID before
deduplicating and sorting batch lookup. This keeps optimizer evidence keys
aligned with live, application and replay provider identity.

Rationale: quality is an input to constrained optimization; equivalent padded
provider IDs must not create divergent evidence keys or duplicate result
entries when valid each-only collections cross the public boundary.

## D-135 — allocation decision identity is canonical and collision-safe

Status: accepted for v0.3 convergence.

Decision: `AllocationDecision` canonicalizes the chosen provider and all
provider-keyed discrepancy, post-measure, share-violation and optimization-trace
maps. It rejects duplicate keys after canonicalization, and corridor/optimizer
lookups use the same canonical provider identity.

Rationale: allocation decisions are the authoritative input to constrained
optimization and durable decision traces. A padded provider key must not split
candidate evidence or make discrepancy/corridor checks address a different
provider bucket.

## D-136 — runtime feasibility uses canonical attempted-provider identity

Status: accepted for v0.3 convergence.

Decision: `RuntimeFeasibility` canonicalizes policy, eligibility, attempted and
measure-exclusion provider IDs at assessment and canonicalizes its public result
sets. Recovery cohort subtraction therefore treats equivalent provider IDs as
the same attempted route.

Rationale: recovery must not retry a money-moving provider because caller input
contained surrounding whitespace. Keeping feasibility identity canonical also
aligns the persisted trace with allocation and provider eligibility evidence.

## D-137 — allocation chooser inputs use canonical provider identity

Status: accepted for v0.3 convergence.

Decision: `Allocation.choose` canonicalizes candidate and accounting provider
collections before filtering by policy and intersecting with weighted provider
state. It accepts valid each-only collections while rejecting blank provider IDs.

Rationale: policy weights and allocation snapshots use canonical provider keys.
Comparing raw padded candidate IDs with those keys could turn an eligible route
into a false no-route and bypass the allocation stage.

## D-138 — decision-engine provider inputs use canonical identity

Status: accepted for v0.3 convergence.

Decision: `DecisionEngine` canonicalizes available and attempted provider IDs
before checking an existing operation's adapter availability or subtracting
money-moving providers from recovery candidates.

Rationale: resume and fallback safety depend on those two provider sets. An
equivalent padded ID must not cause a false adapter-unavailable defer or allow
the same provider back into a recovery decision.

## D-139 — optimizer quality evidence keys use canonical provider identity

Status: accepted for v0.3 convergence.

Decision: `ConstrainedOptimizer` canonicalizes provider keys in direct quality
evidence maps before lexicographic ranking and rejects duplicate keys after
canonicalization.

Rationale: quality is a lower-priority optimization input, but its provider
identity must still align with allocation candidates. Padded or colliding keys
must not make ranking fail or select based on a different evidence bucket.

## D-140 — authoritative allocation snapshots reject empty provider identity

Status: accepted for v0.3 convergence.

Decision: `AllocationSnapshot` rejects blank provider IDs when constructing,
looking up or committing allocation measures, while preserving surrounding-
whitespace canonicalization and collision rejection.

Rationale: allocation snapshots are authoritative financial distribution state.
An empty key must not become a hidden allocation bucket or be used to address
one, because that would make allocation history diverge from canonical provider
identity used by policy, eligibility and provider ledgers.

## D-141 — quality evidence is typed and identity-aligned

Status: accepted for v0.3 convergence.

Decision: direct optimizer quality maps require `ProviderQualitySnapshot`
values whose canonical `provider_id` matches the canonical map key. Quality
snapshots also require non-negative integer sample counters, a positive sample
threshold and canonical non-empty context labels.

Rationale: quality is a lower-priority optimization input, but malformed or
cross-provider evidence must not influence selection or become misleading
audit trace data. The same value rules keep controller, durable restore and
direct optimizer paths coherent.

## D-142 — admission state uses canonical provider identity and typed projections

Status: accepted for v0.3 convergence.

Decision: `AdmissionLedger` canonicalizes provider IDs for all capacity and
throughput state access, while `CapacitySnapshot` and `ThroughputSnapshot`
reject blank identities, malformed budgets/counters and non-`Time` throughput
timestamps. Throughput timestamp collections may use the shared each-only
boundary.

Rationale: admission is a hard safety gate. Splitting one provider's usage
across padded and canonical IDs could bypass capacity or rate limits, while
malformed projection values could make live and replay admission disagree.

## D-143 — payout/attempt snapshots and decisions enforce typed canonical state

Status: accepted for v0.3 convergence.

Decision: lifecycle snapshots canonicalize non-empty operation/provider/policy
identities and validate typed outcomes, contracts, timestamps, counters and
history collections. Payout snapshots require typed ownership/history with
matching payout linkage and unique attempt/operation identities. Decision
proposals canonicalize identifiers, require typed allocation evidence and
enforce action-specific owner identifiers and role shape.

Rationale: snapshots and proposals are the shared value boundary between live
coordination, replay, application/API and provider orchestration. Letting blank,
untyped or cross-payout values through that boundary could make a read model
look valid while diverging from the working coordinator or durable lifecycle.

## D-144 — replay projections use canonical fact and query identities

Status: accepted for v0.3 convergence.

Decision: replay capacity, throughput, allocation and lifecycle projections
canonicalize provider and operation identities while applying facts and while
serving direct snapshot/look-up requests. Allocation-key leaves use the same
canonical identity rule as live allocation state.

Rationale: replay is a read-side reconstruction of the same product facts, not
an alternate identity domain. Equivalent padded provider or operation IDs must
not create separate capacity, allocation or lifecycle buckets, nor make a
valid direct projection query miss existing state.

## D-145 — analytics preserves canonical provider and operation attribution

Status: accepted for v0.3 convergence.

Decision: analytics canonicalizes provider and operation identities across
opportunity, assignment, attempt, observation, settlement, exclusion, target
and policy-scope maps, and rejects duplicate canonicalized policy targets.

Rationale: analytics is an audit projection of economic and operational facts.
Splitting equivalent identities would undercount attempts, failures or
settlements and could misstate target-versus-actual allocation evidence without
changing the underlying routing state.

## D-146 — lifecycle ledger phase changes use canonical identities

Status: accepted for v0.3 convergence.

Decision: `LifecycleLedger` canonicalizes operation identity before operation
lookup and canonicalizes non-empty operation, attempt and provider identities
in `PhaseChange` values.

Rationale: the extracted lifecycle seam is part of the atomic state model.
Keeping a raw `to_s` boundary there would permit a direct ledger caller or
future internal path to address a different operation key or emit an identity
that disagrees with snapshots, facts and provider contracts.

## D-147 — health admission uses canonical owners and typed exposure flags

Status: accepted for v0.3 convergence.

Decision: health probe reservations and releases canonicalize non-empty owner
identities, health snapshots canonicalize and reject blank provider IDs, and
`HealthController#observe` accepts only Boolean `release_exposure` values.

Rationale: health exposure is a hard admission gate. A raw owner identity could
leave a probe reservation unreleased, while a truthy non-Boolean flag could
change exposure state unexpectedly. Both cases can create false quarantine or
false availability and must fail before state mutation.

## D-148 — policy registry lookups use canonical identity

Status: accepted for v0.3 convergence.

Decision: `PolicyRegistry#fetch` and `#find_for_intent` canonicalize non-empty
policy id, epoch and scope inputs before key lookup or scope matching.

Rationale: stored `RoutingPolicy` values already use canonical identity. Raw
string coercion at the registry boundary could make an equivalent public
request miss the policy, produce an incorrect no-policy result or diverge from
the policy binding used by the coordinator.

## D-149 — HTTP webhook normalizers fail fast at configuration time

Status: accepted for v0.3 convergence.

Decision: `Application::HttpApp` validates every configured provider normalizer
before exposing the transport adapter. A normalizer must provide an executable
`#normalize` implementation rather than only inheriting the abstract
`ProviderNormalizer` guard.

Rationale: a dead normalizer is a provider-boundary configuration error, not a
normal webhook outcome. Deferring detection until the first callback leaves the
API apparently live while the provider event cannot cross into the typed core.

## D-150 — health snapshots enforce typed exposure counters

Status: accepted for v0.3 convergence.

Decision: `ProviderHealthSnapshot` accepts only non-negative Integer health
counters, a positive Integer probe limit and an in-flight probe count no greater
than that limit.

Rationale: health exposure is a hard admission input. A malformed snapshot could
otherwise expose negative counters, disable the probe budget with a zero/invalid
limit or claim impossible in-flight exposure, making live, replay and API health
projections diverge before routing admission is evaluated.

## D-151 — runtime-feasibility construction uses the shared collection boundary

Status: accepted for v0.3 convergence.

Decision: `RuntimeFeasibility` materializes `reason_codes` through the shared
each-only collection contract during direct construction, matching its
`assess` path and other public routing value boundaries.

Rationale: a valid each-only source must not fail only when a caller constructs
the typed feasibility value directly. Keeping both construction paths on the
same boundary prevents an avoidable API inconsistency and preserves the typed
reason trace used by decisions and durable projections.

## D-152 — policy infeasibility errors use the shared collection boundary

Status: accepted for v0.3 convergence.

Decision: `StaticPolicyInfeasibilityError` materializes `reason_codes` through
the shared each-only collection contract during construction.

Rationale: policy construction exposes typed infeasibility metadata to callers.
That metadata must follow the same collection contract as the policy and routing
values that produce it, so a valid each-only source cannot fail at the error
boundary or create a special-case domain API.

## D-153 — analytics fact collections use the shared collection boundary

Status: accepted for v0.3 convergence.

Decision: analytics reductions consume opportunity, functional-provider,
decision-reason-code and runtime-infeasibility collections through the shared
`#each` boundary. Missing optional collections retain the existing empty
default, while non-enumerable values raise `ArgumentError` instead of being
wrapped by `Array(...)`. Allocation-key identity reduction also consumes the
top-level key through the shared boundary.

Rationale: analytics is a durable replay/audit consumer, so accepting an
each-only collection must produce the same metrics as an Array. Ruby's
`Array(value)` would treat a valid each-only object as one provider or reason
code and would turn malformed scalar input into a misleading metric rather
than exposing the bad fact shape.

## D-154 — health-probe reservation restore validates attempt identity

Status: accepted for v0.3 convergence.

Decision: durable `health_exposure_reserved` facts validate `attempt_id` with
the canonical durable operation-identity boundary before comparing it with the
restored attempt.

Rationale: coercing a durable attempt identity with `.to_s` can make a
non-canonical value such as an Integer appear equal to a real operation. A
probe reservation is part of the atomic assignment bundle, so accepting that
alias could make malformed history look restart-safe while weakening the
causal reservation link.

## D-155 — transport classification must agree with normalized outcome safety

Status: accepted for v0.3 convergence.

Decision: `ProviderObservation` rejects a `definitely_not_sent` transport
classification unless the normalized outcome is non-success and safe to
release. It rejects an `ambiguous_after_possible_send` classification unless
the outcome remains `pending` or `unknown` and is not safe to release.

Rationale: transport ambiguity is a provider-boundary safety fact, not an
ordinary failure label. Allowing an ambiguous observation to carry a safe
release flag could free ownership and permit cross-provider fallback after a
possible send; allowing definitely-not-sent transport to carry success could
settle an operation that the transport contract says never reached the
provider. The invariant is enforced in the shared typed observation value so
live adapters, webhooks and durable restore cannot diverge.

## D-156 — recovery operation budget is a hard money-moving limit

Status: accepted for v0.3 convergence.

Decision: after a payout has consumed `recovery.max_operations` money-moving
assignments, a subsequent decision must defer even when the preceding
operation safely released ownership. A safe release permits a reroute only
inside the remaining operation budget; it does not reset or extend that
budget.

Rationale: treating safe release as a fresh budget would allow an unbounded
chain of provider operations and would make the configured recovery policy
non-auditable. The end-to-end coordinator regression checks the hard gate,
the explicit reason code and the absence of a second owner/attempt.

## D-157 — unobservable durable append outcomes fail closed

Status: accepted for v0.3 convergence.

Decision: when a journal append raises and the journal cannot expose a
verifiable durable fact view, `FactStore` marks itself unusable, asks the
journal to poison itself when supported, and raises
`DurableCorruptionError`. The store must not accept later appends after that
condition.

Rationale: without a durable prefix/suffix comparison, an append error cannot
distinguish a pre-write failure from a partial write. Retrying with the next
fact identity could therefore create a durable suffix that the in-memory
store does not know about, violating append-only identity and restart
continuity. Failing closed may require operator recovery, but preserves
financial history instead of guessing about durable visibility.

## D-158 — definitely-not-sent transport cannot claim unresolved lifecycle status

Status: accepted for v0.3 convergence.

Decision: a `definitely_not_sent` provider observation must carry one of the
normalized statuses that the lifecycle reducer can safely release or terminate
(`safe_route_failure`, `temporary_provider_failure` or
`terminal_payout_failure`) and must be marked safe to release. It cannot carry
an unresolved `pending` or `unknown` status, even when the safety flag is true.

Rationale: the transport classification is a statement about the initiating
exchange, while `pending`/`unknown` are unresolved lifecycle states. Accepting
their combination created a released operation with an unresolved status: the
live next-action contract could defer instead of rerouting, while durable
restore correctly rejected the phase/outcome combination. The typed observation
boundary now rejects the contradiction before lifecycle mutation, and focused
live plus durable-restore regressions keep the two paths aligned.

## D-159 — restart-safe Coordinator requires durable journal read-back

Status: accepted for v0.3 convergence.

Decision: `State::Coordinator` rejects a configured journal that does not expose
`#facts`. A durable coordinator must be able to read back the append-only fact
history before it can create working state or continue after a fresh process.

Rationale: a write-only journal may accept a mutation but gives a new process no
way to recover ownership, operation identity, policy binding or fact revision.
Allowing that adapter behind the coordinator would expose persistence without
meeting the restart-safety contract. Low-level `FactStore` still fail-closes on
an append whose durable visibility becomes unobservable; supported coordinator
durability now also makes the read-back requirement explicit at construction.

## D-160 — journal poison hooks cannot mask durable corruption

Status: accepted for v0.3 convergence.

Decision: after an ambiguous durable append, `FactStore` marks itself unusable
before invoking the optional journal `poison!` hook. If that hook fails, the
store suppresses the secondary containment error and still raises the primary
`DurableCorruptionError`; later appends remain rejected.

Rationale: poisoning is a best-effort containment extension, not evidence that
the append outcome became safe to retry. Letting a hook exception escape would
hide the financial durability failure behind arbitrary adapter behavior while
leaving the caller without a stable error contract.

## D-161 — provider transport kinds have an explicit input-error boundary

Status: accepted for v0.3 convergence.

Decision: `ProviderTransportResult`, `ProviderTransportError` and
`ProviderObservation` normalize transport kinds through an explicit validator.
Unsupported or non-symbol-like values raise `ArgumentError` rather than leaking
`NoMethodError` from an incidental `to_sym` call.

Rationale: transport classification is part of the provider boundary and must
be either one of the supported typed values or an explicit input failure. A
leaked implementation exception makes adapter contract violations ambiguous and
could bypass the stable error handling expected by the application boundary.

## D-162 — health and quality enum inputs have an explicit input-error boundary

Status: accepted for v0.3 convergence.

Decision: `ProviderHealthSnapshot`, `HealthController#observe` and
`ProviderQualitySnapshot` normalize health state, health signal, health
attribution and quality evidence-scope values through explicit validators.
Unsupported or non-symbol-like values raise `ArgumentError` rather than
leaking `NoMethodError` from an incidental `to_sym` call.

Rationale: health and quality projections are typed routing inputs, including
values reconstructed from durable facts. They must fail with the same stable
input/corruption boundary as provider transport and outcome values instead of
exposing incidental implementation exceptions.

## D-163 — payout context labels use one canonical comparison form

Status: accepted for v0.3 convergence.

Decision: policy hard-constraint checks and provider functional-opportunity
checks trim payout context labels before comparing them with their canonical
configured labels. This keeps equivalent labels such as `" retail "` and
`"retail"` in the same eligibility decision without changing the stored payout
context value.

Rationale: policy and provider configuration already canonicalize required
labels, and quality cohorts use the same normalization. Comparing raw payout
labels in only the eligibility path could incorrectly remove an otherwise
eligible provider and change distribution semantics.

## D-164 — static feasibility and operational availability remain separate

Status: accepted for v0.3 convergence.

Decision: static policy feasibility intersects the target set with hard
allow/exclude constraints and is persisted as typed evidence. A provider that
is functionally in the policy cohort but has no available runtime adapter is
marked operationally unavailable for the current decision; it is not removed
from the functional opportunity/allocation cohort.

Rationale: hard policy contradictions must be distinguishable from a transient
adapter/admission condition. Removing an unavailable provider from the
functional denominator would silently change allocation obligations and create
false historical catch-up pressure.

## D-165 — resume expiry precedes adapter deferral

Status: accepted for v0.3 convergence.

Decision: application resume expires an unresolved operation before checking
whether its existing provider adapter is configured and before rebuilding a
dispatch proposal.

Rationale: restart/resume is a state-changing path. Deferring first could keep
an expired operation indefinitely and bypass the operation contract's TTL or
deadline evidence.

## D-166 — closed durable enum and Hash-key boundaries

Status: accepted for v0.3 convergence.

Decision: external and durable enum values are matched only against already
loaded closed-domain values, and structured Hash keys are accepted only from
explicit whitelists. Fact decoding recursively validates nested values and
does not intern attacker-controlled symbol or key names.

Rationale: arbitrary `to_sym`/`transform_keys` coercion can grow the symbol
table, accept unknown durable shape and turn malformed history into a
different in-memory state. The boundary must reject unknown structure without
weakening exact financial values.

## D-167 — monotonic elapsed-time evidence is durable correctness data

Status: accepted for v0.3 convergence.

Decision: TTL, deadline and throughput-window elapsed calculations use exact
monotonic values. Wall timestamps remain audit data; the default system clock
provides a process-local monotonic translation for older persisted wall-time
facts, and new relevant facts persist monotonic anchors.

Rationale: wall-clock adjustments can move backwards or forwards and change
whether a payout is considered expired or a rate token is reusable. Persisted
monotonic evidence lets a fresh process continue the same elapsed-time
contract without treating a wall-clock subtraction as authoritative.

## D-168 — reconciliation commands distinguish normalized evidence from raw input

Status: accepted for v0.3 convergence.

Decision: the direct reconciliation command accepts only a typed
`ProviderObservation`, which is normalized evidence. Raw provider payloads use
the provider-specific normalizer entry point before they can reach the core.

Rationale: raw callbacks and provider errors do not own the meaning of
`safe_to_release`, outcome status or transport certainty. Keeping the typed
ingress explicit prevents a caller from bypassing the provider boundary.

## D-169 — durable restore never coerces operation identities

Status: accepted for v0.3 convergence.

Decision: durable provider, operation, attempt and policy identities must be
canonical non-empty Strings at restore. Restore code does not use `.to_s` to
turn numeric, padded or otherwise malformed identity values into valid keys.

Rationale: identity coercion can merge corrupted records with live state or
split one economic operation across replay and working projections. The same
canonical identity rule must apply before any durable lookup or linkage.

## D-170 — concurrency invariant failures carry execution traces

Status: accepted for v0.3 convergence.

Decision: the high-contention concurrency harness records a compact per-payout
execution trace and includes it with the fixed fuzz seed when an invariant
assertion or worker exception fails. Provider outcomes remain deterministic
from the seed, while thread scheduling remains an explicit part of the observed
trace; the harness does not retry or suppress failures to make them appear
stable.

Rationale: a seed alone does not explain scheduler-dependent interleavings.
Without the observed payout/action/status/attempt trace, a failed invariant is
hard to diagnose and reproduce. Diagnostic trace output strengthens the
verification evidence without falsely claiming deterministic thread
interleaving.

## D-171 — replay allocation uses the shared collection boundary

Status: accepted for v0.3 convergence.

Decision: the legacy `Replay.allocation` fallback for facts without an explicit
`allocation_key` consumes `policy_scope` through `RubyRouting::Collection`.
Each-only policy-scope collections are accepted and scalar policy-scope values
are rejected rather than being wrapped by Ruby's permissive `Array(...)`
conversion.

Rationale: live and durable projection boundaries must agree on collection
shape. `Array(value)` silently treats a scalar as a one-element allocation key
and does not consume valid each-only enumerables, which can create a replay
bucket that cannot be addressed by the corresponding live policy key.

## D-172 — replay and analytics reject non-symbol-like identity payloads

Status: accepted for v0.3 convergence.

Decision: replay and analytics identity normalization accepts only String or
Symbol values before trimming and lookup. Numeric or arbitrary objects from a
crafted fact payload are rejected instead of being coerced into provider,
operation or allocation identities. Padded String values remain supported for
equivalent direct projection lookups.

Rationale: a durable projection must not turn malformed identity data into a
new valid attribution bucket. The working coordinator already rejects
noncanonical durable identities; applying the same type boundary to replay and
analytics prevents live/replay divergence while retaining intentional external
whitespace canonicalization.

## D-173 — replay stateful fact ingress uses one strict identity boundary

Status: accepted for v0.3 convergence.

Decision: replay lifecycle, health and quality projections normalize every
provider, operation, attempt, observation, reversal, contract and quality
context identity through the String/Symbol boundary before passing data to
domain reducers. Allocation projection lookup applies the same validation even
when the caller supplies a policy-like object with an `allocation_key` method.

Rationale: D-172 closed direct projection buckets and public lookups, but
stateful replay paths still handed crafted numeric or arbitrary IDs to domain
objects that historically used permissive `to_s` normalization. That could
silently create a plausible replay state that working restore would reject.
The projection boundary must fail closed while preserving padded String/Symbol
compatibility and the live-domain input contract.

## D-174 — monotonic ledger anchors are exact boundary inputs

Status: accepted for v0.3 convergence.

Decision: admission capacity traces, restored throughput reservations and
elapsed-time calculations accept only Integer or Rational monotonic values.
Float anchors are rejected at the ledger boundary rather than being rounded or
silently converted.

Rationale: monotonic elapsed time is part of operational correctness for
capacity windows, throughput reuse and expiry. A floating-point anchor could
introduce platform-dependent boundary behavior or hide malformed durable
state, so the exact time contract must be enforced before ledger mutation.

## D-175 — durable fact envelopes and tagged values are closed schemas

Status: accepted for v0.3 convergence.

Decision: `FactCodec` rejects unknown envelope fields and unknown fields inside
tagged Symbol, Rational, Time, Money, Hash and Array values. Checksummed input
is not allowed to decode by silently dropping unsupported payload fields.

Rationale: checksums establish byte integrity, not schema compatibility.
Silently ignoring an added or corrupted field can produce a plausible but
incomplete financial projection. Unsupported durable structure must fail closed
and be repaired or migrated explicitly.

## D-176 — static share feasibility is evaluated after hard constraints

Status: accepted for v0.3 convergence.

Decision: policy static-feasibility checks intersect the configured allocation
targets with hard allow/exclude constraints before validating positive minimum
shares and the effective maximum-share capacity. A target made hard-ineligible
cannot satisfy an allocation obligation, and the remaining hard-eligible
maximums must still be able to cover the full allocation.

Rationale: checking only that one hard-eligible target exists is insufficient
for contractual allocation. Detecting these contradictions before opportunity
and admission prevents an impossible policy from reaching routing decisions.

## D-177 — application reconciliation requires provider normalization

Status: accepted for v0.3 convergence.

Decision: the stable application reconciliation command accepts provider ID,
raw provider event data and an executable provider-specific normalizer. It does
not accept a caller-constructed `ProviderObservation`; only normalized evidence
produced by the provider boundary reaches the coordinator. No-route decisions
also persist typed deviation cause/recoverability and analytics records them.

Rationale: application callers must not bypass provider semantics by forging
`safe_to_release`, attribution or outcome fields. Recording no-route deviations
is required to explain unavailable/capacity-blocked payout decisions rather
than making analytics report only assigned-provider deviations.

## D-178 — operation-commit side effects have a focused state seam

Status: accepted for v0.3 convergence.

Decision: `State::OperationCommitter` owns fact-producing assignment,
retry/resolve, operation-phase and ownership-release side effects, while the
coordinator remains the single atomic transaction facade. The seam receives
the admission, allocation, lifecycle and health components plus explicit fact,
clock and snapshot callbacks; provider I/O remains outside the transaction.

Rationale: `State::Coordinator` had already delegated focused ledgers but still
owned the operation write protocol and its external reservation effects. This
extraction reduces the facade's implementation surface without introducing a
second transaction owner or changing economic ordering. Durable restore and
decision evaluation remain separate follow-up decomposition work.

## D-179 — decision evaluation has a fact-free routing seam

Status: accepted for v0.3 convergence.

Decision: `Routing::DecisionEvaluator` assembles runtime opportunities,
functional eligibility, operational admission flags, allocation snapshot,
runtime feasibility and the constrained decision proposal. It does not publish
facts or reserve capacity, throughput or health exposure; the coordinator
publishes the evaluation and invokes the operation committer inside its single
atomic boundary.

Rationale: the coordinator was still assembling every stage from opportunity
through optimization even after those stages had focused domain components.
Making the fact-free evaluation seam explicit keeps the required ordering
visible and testable while avoiding a second state owner or a weighted shortcut
around safety/allocation constraints. Durable restore remains the next major
concentration to decompose.

## D-180 — ordered durable restore has an explicit orchestration seam

Status: accepted for v0.3 convergence.

Decision: `State::WorkingStateRestorer` owns the durable-prefix replay protocol:
it resets the catalog before replay, applies facts in sequence order, verifies
that supplied runtime opportunities are still current in durable provider
history and classifies reducer shape failures as `DurableCorruptionError`.
Individual fact reducers and final restored-state validation remain supplied by
`State::Coordinator`, which stays the one atomic transaction facade.

Rationale: replay correctness depends on a visible order and on refusing
runtime configuration that was never durably registered. Extracting this
orchestration boundary reduces durable-restore concentration without creating a
second state owner or pretending that reducer decomposition is complete. The
remaining reducer concentration is an explicit P0-003 follow-up.

## D-181 — provider catalog durable facts have a focused restorer

Status: accepted for v0.3 convergence.

Decision: `State::ProviderCatalogRestorer` owns replay of provider registration,
removal and runtime-change facts. It uses the current catalog, admission ledger
and quality controller supplied by the coordinator; provider identity/history
validation and durable fact publication remain outside the seam.

Rationale: provider configuration history is a coherent durable responsibility
with a distinct currentness timeline and runtime replacement behavior. Moving
these reducers behind a focused object reduces coordinator concentration while
preserving the single atomic facade and the rule that supplied runtime
opportunities cannot backdate or resurrect catalog history. Payout/lifecycle
fact reducers remain an explicit P0-003 follow-up.

## D-182 — admission durable facts have a focused restorer

Status: accepted for v0.3 convergence.

Decision: `State::AdmissionFactRestorer` owns replay of capacity reservation,
capacity release and throughput-consumption facts. It routes exact money and
monotonic-time values through `State::AdmissionLedger`, while the coordinator
supplies payout, provider-history and operation-linkage validation callbacks.

Rationale: exposure capacity and time-window throughput are distinct admission
resources and must remain distinct during restart. Extracting their durable
reducer keeps that separation explicit without moving fact publication, payout
ownership or the atomic transaction boundary into another component.

## D-186 — operation durable facts have a focused restorer

Status: accepted for v0.3 convergence.

Decision: `State::OperationFactRestorer` owns replay of ownership acquisition,
attempt start, reconciliation block and health-exposure reservation/release
facts. It uses coordinator-supplied operation, lifecycle and health validation
callbacks; it does not publish facts, own atomic transactions or perform
provider I/O.

Rationale: these facts form the durable continuation protocol around a
committed operation. Keeping their replay in one focused seam makes ownership,
dispatch-pending, reconciliation and probe-exposure ordering auditable while
preserving the coordinator as the single working-state transaction facade.
The remaining cross-fact validation helpers stay open under P0-003 until their
boundaries can be extracted without weakening replay ordering.

## D-187 — provider evidence facts have a focused restorer

Status: accepted for v0.3 convergence.

Decision: `State::ProviderEvidenceFactRestorer` owns replay of provider-derived
transport classification, health signals, quality signals and health-state
transitions. It receives current controller/map references and provider-history
validation from the coordinator, without publishing facts or performing I/O.

Rationale: these facts are an evidence projection sourced from normalized
observations and manual provider signals. Keeping provenance, deduplication and
health transition ordering together makes replay auditable while preserving
the separate health and quality controllers.

## D-188 — financial evidence facts have a focused restorer

Status: accepted for v0.3 convergence.

Decision: `State::FinancialFactRestorer` owns replay of late-success economic
conflicts and settlement reversals. It validates source/linkage and reversal
bounds through payout-state callbacks while leaving ownership and transaction
publication in the coordinator.

Rationale: conflict and reversal facts change financial history after an
operation outcome but must not become a second routing or ownership mechanism.
The focused seam keeps these post-operation invariants explicit.

## D-189 — payout registration facts have a focused restorer

Status: accepted for v0.3 convergence.

Decision: `State::PayoutFactRestorer` owns intent-registration and policy-binding
fact replay, including exact creation anchors, policy fingerprints and static
feasibility agreement. Domain factories and identity checks are supplied by
the coordinator.

Rationale: intent and policy facts establish the durable root of every payout.
Extracting their replay makes the root binding explicit without moving policy
selection or durable transaction ownership outside the coordinator.

## D-190 — historical opportunity evaluation has a focused restorer

Status: accepted for v0.3 convergence.

Decision: `State::OpportunityEvaluationFactRestorer` owns replay of evaluation
facts and recomputes their eligibility, admission, allocation, health, quality
and runtime-feasibility trace against restored projections before recording it
on payout state.

Rationale: a durable evaluation is an auditable input to a later decision, not
an unchecked cache. The seam preserves the recomputation boundary and keeps
current catalog/admission/optimization state supplied by the coordinator.

## D-191 — decision facts have a focused restorer

Status: accepted for v0.3 convergence.

Decision: `State::DecisionFactRestorer` owns replay of assignment and
retry/resolve decision facts. Cross-projection trace, policy and operation
contract validators remain explicit callbacks from the coordinator, while the
restorer mutates only operation and dispatch state.

Rationale: durable decision application is the final routing-replay step before
operation/lifecycle facts. Separating it from the facade reduces reducer
concentration without duplicating validation or creating a second transaction
owner.

## D-192 — final restored-state validation has a focused seam

Status: accepted for v0.3 convergence.

Decision: `State::RestoredStateValidator` owns the final durable working-state
checks for creation anchors, ownership, operation phase/outcome compatibility,
capacity/throughput linkage, pending dispatch linkage, settlement/reversal
state and release ordering. It reads dynamic working-state references supplied
by the coordinator because restore rebuilds the projections.

Rationale: these checks are cross-fact durable correctness, not a single fact
reducer. Giving them one explicit owner keeps restart validation auditable while
preserving the coordinator as the only atomic transaction facade.

## D-193 — decision trace validation has a focused seam

Status: accepted for v0.3 convergence.

Decision: `State::DecisionTraceValidator` owns decision policy binding,
no-route/recovery rationale, assignment proposal recomputation, allocation and
admission reservation linkage, provider contract compatibility and resolution
capability checks. `DecisionFactRestorer` only applies the validated decision to
operation/dispatch state.

Rationale: durable decisions are meaningful only when their cross-projection
trace still agrees with policy, opportunity evaluation, allocation, admission
and operation state. Separating proof from mutation makes that boundary
testable without creating a second transaction owner or an alternate routing
path.

## D-194 — restart-generated resolution decisions are durable control-plane facts

Status: accepted for v0.3 convergence.

`resume_operation` may need to persist a control-plane decision before provider
I/O when an already-started operation is recovered after a process restart. That
decision is not an ordinary recovery classification: it carries the explicit
`restart_recovery` reason and the existing operation identity. The durable
decision validator recognizes only the exact action-specific restart trace,
allows it only for the already-dispatching/resolving operation, and still
requires the operation's status-lookup or idempotent-retry capability. This
preserves the operation token across a second fresh-process boundary without
creating a new attempt or weakening ordinary resolution-trace validation.

## D-195 — settlement reversals remain ordered post-settlement evidence across restart

Status: accepted for v0.3 convergence.

Decision: settlement remains the original economic finalization fact, while one
or more positive reversal facts may be appended against the settled or explicitly
conflicted operation up to that operation's payout amount. A fresh working
coordinator must restore those reversal facts in order, retain the settlement
linkage and treat an exact repeated reversal command as idempotent without
appending another fact.

Rationale: reversal is post-settlement remediation, not a second settlement or a
route reopen. The durable contract must preserve both the original settlement
measure and the later reversal history, including partial returns, across a
process boundary.

## D-196 — live throughput reservations mirror durable consumption facts

Status: accepted for v0.3 convergence.

Decision: when a committed operation consumes a provider throughput budget, the
coordinator's live payout state records the same provider, wall-clock and exact
monotonic consumption anchors as the `throughput_consumed` fact. The reservation
remains until the time-window projection expires; it is not released with
concurrent capacity.

Rationale: restore already rebuilt this operation-linked state from durable
facts. Keeping live and restored working projections identical prevents a
restart-only admission shape and makes the committed admission bundle
auditable before provider I/O.

## D-197 — application analytics expose current unresolved age

Status: accepted for v0.3 convergence.

Decision: `Application::Queries#analytics` uses the coordinator clock as its
default `as_of` boundary, while callers may still pass an explicit boundary or
`nil` for deterministic historical projection. The HTTP analytics route accepts
an optional ISO-8601 `as_of` query value and otherwise uses the current clock.

Rationale: the analytics projection already tracked pending, UNKNOWN and
reconciliation age, but the application surface defaulted to an empty age map.
The query boundary now exposes operationally useful age without changing the
fact-derived metric definitions.

## D-198 — HTTP transport input is explicitly bounded

Status: accepted for v0.3 convergence.

Decision: `Application::HttpApp` bounds request method, path, query-string and
JSON body sizes before parsing or dispatching, returning a stable 413 response
for oversized input. It continues to sanitize malformed and internal errors.

Rationale: the pre-TZ API shape is provisional, but an externally controlled
transport boundary still needs a resource-abuse guard that does not leak parser
or implementation details into the core.

## D-199 — high-contention fuzz starts through a controlled worker barrier

Status: accepted for v0.3 convergence.

Decision: the seeded high-contention fuzz harness releases all worker threads
through a shared barrier before consuming the payout queue. Scheduler-dependent
execution remains observable through the recorded seed and execution trace; the
harness does not retry or claim a fixed schedule.

Rationale: fixed provider outcomes and failure diagnostics make the fuzz history
reproducible, while a common start gate makes the intended concurrent pressure
explicit and strengthens evidence for the coordinator's atomic invariants.

## D-200 — benchmark the public application service path separately

Status: accepted for v0.3 convergence.

Decision: the baseline benchmark measures a separate 2,000-operation run through
`Application::Service` with a fresh coordinator and provider set, in addition to
the existing direct orchestrator lifecycle run. The result is reported as
bounded local application-throughput evidence and is not treated as an API or
production-capacity claim.

Rationale: P1-013 requires application throughput evidence, while the earlier
baseline measured routing lifecycle and projections but did not exercise the
public application facade. A fresh state keeps the measurement interpretable
without changing routing semantics.

## D-201 — bound HTTP audit responses with explicit pagination

Status: accepted for v0.3 convergence.

Decision: `Application::HttpApp` serves `/v1/audit/facts` in pages no larger
than `MAX_AUDIT_PAGE_SIZE`, accepts only strict non-negative decimal `offset`
and positive `limit` values within the page bound, and returns `offset`,
`limit`, `total` and `next_offset` metadata. The route does not silently drop
facts; callers can continue from `next_offset`, while absurd offsets are
rejected at the transport boundary.

Rationale: the audit view is backed by an append-only financial fact history.
Returning the complete history in one HTTP response creates an avoidable
resource hazard as the product grows, while silently truncating it would make
audit evidence incomplete. Explicit bounded pagination preserves both safety
and audit completeness without creating alternate routing semantics.

## D-202 — exercise durable continuation in an actual fresh Ruby process

Status: accepted for v0.3 convergence.

Decision: restart evidence includes a separate child Ruby process that opens a
real `FileJournal`, restores provider and policy state without runtime
opportunity/policy catalog input, resumes the committed owner through the public
`Application::Service` and completes the same operation identity. The parent
then reopens the journal and verifies the persisted terminal attempt. Same-
process reconstruction remains useful for focused fault scenarios but is not
the only evidence for the fresh-process claim.

Rationale: the durable contract is explicitly about a new process safely
continuing unresolved payouts. Crossing the process boundary catches accidental
dependence on in-memory class/object state while preserving the minimal
single-process product architecture.

## D-203 — bind restored in-flight phase to action and outcome

Status: accepted for v0.3 convergence.

Decision: final durable-state validation requires an in-flight attempt's phase,
latest operation action and outcome to describe one valid continuation. Initial
or restarted dispatch may be `dispatching` with no outcome, idempotent retry may
be `dispatching` with an unresolved or unsafe provider outcome, and status
resolution may be `resolving` with no such outcome or with the prior unresolved
evidence. The restored working state also records the durable sequence of the
latest operation decision and applied observation, so an applied pending/unknown
observation after that decision must have its matching lifecycle phase; otherwise
the history is rejected as durable corruption.

Rationale: observation replay and lifecycle phase replay are separate fact
families. Without a final cross-check, a missing phase fact could leave a payout
status as `unknown` while the operation remained `dispatching`, causing a fresh
process to defer instead of safely resuming provider resolution. The invariant
closes that durable divergence without merging safety, lifecycle and recovery
semantics into one score or reducer.

## D-204 — make ownerless defer visible as a deferred payout state

Status: accepted for v0.3 convergence.

Decision: a non-operation `defer` decision with no economic owner sets the live
payout status to `:deferred`. Durable working restore and lifecycle replay apply
the same transition, and analytics exposes the current number of deferred
payouts. A defer emitted while an owner is retained leaves the existing
unresolved status unchanged.

Rationale: `defer` is an action, but callers also need a durable current-state
answer. Leaving a no-route or exhausted-budget payout at `:new` or a stale
releasable failure status hid the fact that routing was intentionally paused.
The owner guard preserves the stronger UNKNOWN/TTL ownership invariant.

## D-205 — use an explicit role contract for non-operation defer

Status: accepted for v0.3 convergence.

Decision: ownerless non-operation defer decisions use role `:recovery`, while
owner-held defer decisions use role `:resolution`; other control decisions use
the existing resolution role and assignments retain primary/recovery roles.
The durable validator checks the role against the replayed ownership state, and
the decision engine emits this shape for no-route, operation-budget and
provider-switch-budget defers.

Rationale: no-route decisions already used `:recovery`, but the shared defer
helper gave budget defers `:resolution`. The mismatch made valid histories
non-restorable once role validation became explicit. One state-dependent role
contract keeps live decisions and durable validation aligned without conflating
recovery safety with allocation or optimization.

## D-206 — enforce control-decision shape in the domain value object

Status: accepted for v0.3 convergence.

Decision: `DecisionProposal` rejects `defer` with a primary role, terminal
control actions with a non-resolution role, and any non-operation control
decision carrying provider, operation or attempt identifiers. State-dependent
ownership checks remain in `DecisionTraceValidator`; the value object enforces
only the shape that is independent of restored state.

Rationale: durable validation alone was too late to protect callers that
constructed an invalid proposal in memory. Keeping the state-independent
contract at construction prevents malformed control decisions from entering
the coordinator or durable fact path while preserving the separation between
domain shape validation and stateful recovery-role validation.

## D-207 — close v0.3 only on an exact published revision

Status: accepted.

Decision: v0.3 is `VERSION_COMPLETE` on published `main` revision
`000931b205a4ae932b532ada00f9eb21072884c7` after a fresh A–L closure/red-team
pass found no material locally-solvable gap and GitHub Actions run `33333118660`
passed both `Fast Ruby verification` and `Bounded product evidence` jobs.

Rationale: local green tests, a working demo or a plan checklist are not enough
to close the version. This decision preserves the exact-revision CI gate and
records that the official TZ remains a separate v0.4 reconciliation input,
without relabeling the completed v0.3 product as the future judged submission.

## D-208 — tolerance is an absolute policy-measure L1 corridor

Status: accepted for v0.3.1 pre-TZ hardening.

Decision: `RoutingPolicy#tolerance` is a non-negative exact `Rational` defining
the post-decision L1 discrepancy across the policy allocation universe. Its
units are count units for `:count` policies and exact minor units of the policy
currency for `:volume` policies. Share minimum/maximum obligations precede the
tolerance comparison. Candidates within tolerance are preferred; when none is
inside the corridor, the least-bad admissible candidate remains selectable and
the allocation records `tolerance_exceeded`.

Rationale: a single field must not silently alternate between normalized share
error, per-provider corridor and absolute amount. Binding the exact discrepancy
to the policy measure preserves indivisible-payout behavior, keeps count and
monetary volume dimensionally honest, and leaves impossible allocation states
observable rather than silently dropping them.

## D-209 — recovery selection explicitly reuses allocation authority without ledger reuse

Status: accepted for v0.3.1 pre-TZ hardening.

Decision: once recovery safety, hard eligibility/admission and recovery budget
gates permit a fresh fallback, `Routing::RecoverySelection` removes every
provider that already hosted a money-moving attempt. It then calls the same
exact `Allocation.choose` authority used by primary routing, with the full
functional accounting universe, and returns the typed allocation evidence to
the shared proposal/optimization path. Recovery assignments remain role
`:recovery` and therefore do not advance the primary allocation ledger under
`primary_assignment`.

Rationale: recovery has a distinct legal boundary but still needs one source of
truth for exact allocation obligations and discrepancy math. A small explicit
wrapper makes the staged order auditable without duplicating allocation logic;
the role-gated commit preserves separation between fallback selection and
primary distribution accounting. A skewed-target regression proves that an
already-used high-target provider cannot win merely because the allocator was
reused implicitly.

## D-210 — deterministic quality uses prior shrinkage and a bounded recent window

Status: accepted for v0.3.1 pre-TZ hardening.

Decision: slow provider quality is an exact Beta/Laplace posterior with a
neutral `1/1` prior over the latest `evidence_window` provider-attributed
terminal success/provider-failure outcomes. `minimum_samples` controls whether
evidence is mature; context selection uses mature context, then mature global,
then the prior/default. Pending, UNKNOWN and recipient/downstream outcomes do
not enter the quality window. Quality policy and the exact snapshot evidence
are durable, and each relevant outcome emits a quality fact even when a rolling
window's numeric sample count remains unchanged.

Rationale: raw ratios make a single success look perfect and permit sparse
evidence to dominate mature evidence. Prior shrinkage makes uncertainty visible
in the exact ranking score, while a bounded window prevents stale history from
remaining authoritative forever. Retaining every relevant event preserves
replay equivalence for the rolling state without changing economic safety,
allocation authority or the separation from fast operational health.

## D-211 — typed fast-health evidence is separate from payout outcome

Status: accepted for v0.3.1 pre-TZ hardening.

Decision: fast operational health accepts explicit provider-attributed
`transport_failure`, `timeout_pressure`, `overload_rejection`,
`provider_service_error`, `latency_pressure` and `deadline_pressure` signals.
They share the existing hysteresis, quarantine, bounded-probe and slow-up
recovery state machine. Recipient/downstream attribution remains neutral.

At the normalized provider boundary, `definitely_not_sent` maps to
`transport_failure`; `ambiguous_after_possible_send` maps to
`timeout_pressure` for health only. An ambiguous payout remains normalized as
UNKNOWN with its original single economic owner and cannot be released or
fallback-routed because health changed. The observation-derived health fact
stores the source and is replay-validated against the transport kind, with the
health attribution explicitly provider operational evidence rather than a
rewrite of the payout outcome attribution.

Rationale: future admission needs fast, typed operational protection before
slow quality evidence matures, but transport uncertainty is an economic safety
boundary. Keeping the two projections separate prevents a useful health signal
from becoming an unsafe ownership or fallback decision.

## D-212 — live proposal construction consumes one prepared evaluation

Status: accepted for v0.3.1 pre-TZ hardening.

Decision: `DecisionEvaluator` materializes one immutable
`DecisionEvaluator::Evaluation` containing the runtime opportunities,
eligibility, allocation exclusions, runtime feasibility, allocation snapshot,
allocation key and quality evidence. Live `DecisionEngine` proposal
construction consumes that value and does not recalculate eligibility or
runtime feasibility. Calls that use `DecisionEngine` directly retain an
explicit compatibility path that computes those inputs when no prepared
evaluation is supplied.

The coordinator remains the sole atomic commit/revalidation boundary; this
decision does not treat a stale evaluation as a reservation or allow an
optimizer to bypass mutable admission checks.

Rationale: duplicate live evaluation created unnecessary work and a drift risk
between the evidence persisted in `opportunity_evaluated` and the proposal
actually built. A frozen value removes that overlap without expanding the
transaction model; restore-side recomputation remains a separately audited
concern for PTZ-103.

## D-213 — shared runtime-opportunity composition across live and restore

Status: accepted for v0.3.1 pre-TZ hardening.

Decision: `Routing::OpportunityRuntime.materialize` is the pure shared seam for
turning a provider definition plus dynamic evidence into a runtime opportunity.
It applies adapter availability, capacity, health and throughput evidence only
through the provider's existing static gates. `DecisionEvaluator` supplies
current ledger/controller evidence; `OpportunityEvaluationFactRestorer`
supplies validated as-of evidence from the durable trace. Neither path owns a
second copy of the final boolean composition.

Rationale: the live and restore paths legitimately read different temporal
sources, but duplicating their final runtime semantics allowed a small change to
drift across the two paths. A small pure interface improves locality and keeps
the temporal distinction visible without introducing another state machine or
expanding durability.

## D-214 — typed decision explanation is a whitelist projection

Status: accepted for v0.3.1 pre-TZ hardening.

Decision: `Projections::DecisionExplanation` is the single product read model
for routing explanation. It projects each durable `decision_committed` against
the preceding `opportunity_evaluated` evidence and exposes policy identity,
opportunity/exclusion, admission, allocation, optimization, deterministic
rationale, recovery and lifecycle-result fields. The projection copies only
explicitly selected safe fields; it never copies raw fact payloads or recipient
data and never recomputes a routing decision.

`Application::Queries#explanation` and
`GET /v1/payouts/:payout_id/explanation` use this projection. The rationale is
labelled `deterministic_routing_reason`, not scientific causal attribution.

Rationale: operators and judges need one coherent explanation surface, while
the raw audit fact stream contains both sensitive payout data and transport
details that should not become an accidental public contract.

## D-215 — public audit is a fail-closed whitelist projection

Status: accepted for v0.3.1 pre-TZ hardening.

Decision: `GET /v1/audit/facts` maps each durable fact through
`Projections::PublicAuditFact`. The projection preserves envelope metadata and
explicitly safe routing evidence, while omitting recipient/context payload,
provider references and provider messages by default. It reports omitted key
names as `redacted_fields` for auditability. The internal raw fact query stays
available only to trusted application/replay tooling and is not reused as the
public API serializer.

Rationale: durable facts legitimately retain data needed for recovery and
reconciliation, but exposing that payload wholesale would make privacy depend
on every future fact producer remembering to redact itself. A per-type
allowlist gives the public boundary one owner and fails closed for new fields.

## D-216 — cause-named metrics are deterministic reason attributions

Status: accepted for v0.3.1 pre-TZ hardening.

Decision: keep the existing `deviation_cause` and runtime-infeasibility cause
vocabulary in durable facts and compatibility accessors, but publish explicit
semantics with Analytics. `deviation_attribution_semantics` is
`deterministic_routing_reason`; runtime infeasibility is labelled
`deterministic_exclusion_reason`. The labels come from observed exclusion and
allocation-rule precedence, not from a counterfactual experiment and must not
be described as scientific causality. Decision explanations carry the same
non-causal routing-reason label.

Rationale: this removes an overstated product claim without duplicating the
routing model or breaking the existing durable evidence vocabulary.

## D-217 — bounded history profile is the pre-TZ performance evidence boundary

Status: accepted for v0.3.1 pre-TZ hardening.

Decision: keep full durable facts and the existing correctness/replay evidence,
and use `benchmark/history_profile.rb` as the reproducible bounded profile for
fact density, lifecycle/Analytics/restore latency, post-GC heap growth and
concurrent canonical throughput. The clean CRuby 4.0.6 run covers 100/250/500
payout samples plus 500 payouts across four workers. Restore is the measured
history-sensitive cost center, but no product latency threshold currently
justifies an incremental projection/index/checkpoint. The exact-candidate run
measured 0.4329 seconds restore at 500 payouts and 959.8 concurrent ops/s with
four workers. The profile is not a 100k campaign and must not be described as
one.

Rationale: measurement is now attached to the actual fact/replay path without
removing reconciliation evidence or introducing speculative persistence
complexity before authoritative workload limits exist.
