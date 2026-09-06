# Current Decisions — v0.3.3 Skeptical Hardening

Status: ACTIVE decision supplement for SPEC-007.

This file supersedes older decision supplements only where they conflict with current v0.3.3 work. `docs/DECISIONS_CURRENT.md` and `docs/DECISIONS.md` remain historical rationale and inherited accepted decisions where compatible.

## D-300 — v0.3.2 closure is a checkpoint, not current completion

Status: accepted.

Decision: v0.3.2/SPEC-006 remains a verified historical checkpoint, but its statement that no locally solvable P0/P1 remained is superseded by the later skeptical review that opened SPEC-007/v0.3.3.

Rationale: exact-head green verification proves the implemented contract, not that the contract contained every important cross-layer counterexample. Configuration-generation races, evidence-age semantics and clock-origin portability were locally solvable findings discovered after closure.

## D-301 — known backlog exhaustion cannot directly prove version completion

Status: accepted.

Decision: finishing every known P0/P1 item may only move a version to `VERSION_CANDIDATE`. `VERSION_COMPLETE` requires a subsequent adversarial discovery pass that intentionally ignores checklist completion as evidence of completeness and searches for unplanned counterexamples in actual production code.

Any material locally solvable discovery returns the version to ACTIVE.

Rationale: allowing the same prewritten scope to define implementation and prove completeness creates a closed verification loop. The product needs a falsification stage, not only acceptance confirmation.

## D-302 — one active configuration generation is a routing input

Status: accepted for v0.3.3.

Decision: a new routing decision must resolve policy and functional provider definitions from one immutable active configuration snapshot/revision. Publishing a replacement is atomic from routing readers' perspective. Provider I/O remains outside configuration and coordinator locks.

Runtime health/capacity/throughput may evolve independently under their existing atomic state semantics; historical/in-flight payouts retain pinned policy/operation semantics.

Rationale: immutable individual policies/providers do not prevent a concurrent reader from combining old policy state with a new provider catalog when those owners are updated sequentially.

## D-303 — malformed routing context fails closed

Status: accepted for v0.3.3.

Decision: `nil` may represent an explicit empty routing context; an existing typed RoutingContext and valid Hash forms are accepted; unsupported scalar/array/arbitrary-object shapes are errors. Malformed route input may not silently become less specific and broaden policy/provider eligibility.

Rationale: fail-open parsing can transform bad external data into a valid but semantically different routing decision.

## D-304 — quality age applies to contributing samples

Status: accepted for v0.3.3.

Decision: when quality has a maximum evidence age, stale evidence samples themselves are excluded before maturity, confidence and posterior score are calculated. A fresh observation cannot make expired history authoritative again merely by becoming the newest timestamp in the cohort.

Rationale: cohort-level staleness based only on `last_observed_at` does not enforce the stated age bound on the evidence that actually influences routing.

## D-305 — comparable quality evidence includes currency

Status: accepted for v0.3.3.

Decision: the most specific provider-quality comparison key must distinguish currency in addition to bounded typed route dimensions where those dimensions are used. Currency remains authoritative on Money/intent; it does not move into RoutingContext merely for quality storage.

Rationale: provider conversion/reliability can differ materially by currency even on the same payment method/rail/destination route. Pooling them silently creates misleading optimizer evidence.

## D-306 — sparse route evidence needs explicit authority

Status: accepted for v0.3.3.

Decision: route-specific quality may override broader mature evidence only through an explicit maturity/confidence rule. The implementation may use per-scope sample thresholds or exact deterministic hierarchical shrinkage; it may not rely accidentally on a global default such as `minimum_samples = 1`.

Rationale: a single route outcome should not automatically outweigh a large mature broader sample solely because route scope has higher lookup precedence.

## D-307 — persisted monotonic coordinates are not portable identities

Status: accepted for v0.3.3.

Decision: monotonic time remains authoritative for elapsed calculations inside a running process, but persisted raw monotonic coordinates are not assumed to belong to the next process/host origin. Durable recovery, TTL/deadline and throughput semantics must be reconstructible/rebased from portable wall anchors or equivalent durable data into the current process monotonic domain.

Rationale: `CLOCK_MONOTONIC` coordinates are runtime-local. Blind comparison across a new origin can delay or prematurely permit recovery/rate-limit actions.

## D-308 — policy specificity uses semantic narrowing where possible

Status: accepted for v0.3.3.

Decision: explicit selector priority remains primary. For equal priority, a matching selector that is a strict semantic subset of another may win as more specific; equal-authority incomparable overlapping selectors remain ambiguous. Registration order is never a hidden tie-break.

Exact minor-unit amount bands may participate with explicit currency-safe semantics. No generic rules DSL is introduced.

Rationale: counting configured fields/labels gives deterministic but arbitrary precedence between logically incomparable selectors.

## D-309 — Coordinator remains the atomic facade

Status: accepted for v0.3.3.

Decision: v0.3.3 does not split `State::Coordinator` because of file size. Extraction is justified only when it creates one semantic source of truth or removes duplicated transition/timing/configuration rules. Priority candidates are active configuration publication and shared recovery expiry/schedule/rebase semantics.

Rationale: moving methods into more classes without changing semantic ownership makes correctness harder to audit rather than easier.

## D-310 — application boundary fails closed on Coordinator catalog drift

Status: accepted for v0.3.3.

Decision: when an `Application::Service` uses an active configuration snapshot,
the Coordinator provider catalog must match that immutable provider generation
before submit, resume or configuration-query results are exposed. If a public
low-level Coordinator mutation changes the catalog out of band, application
routing/resume and configuration reads raise a typed configuration-drift
error; the HTTP adapter maps it to a stable service-unavailable response.
The guard runs before expiry or payout mutation, while direct low-level
Coordinator use without an application snapshot remains supported.

The guard compares the immutable provider definition only; operational runtime
flags (availability, capacity, enabled, health and throughput) are overlaid
from the Coordinator for live evaluation.

Rationale: the application snapshot and Coordinator catalog are both public
Ruby seams. Allowing them to diverge creates a mixed routing generation and
can publish provider-dependent facts that fresh restore cannot validate. A
fail-closed guard is the smallest pre-TZ correction without introducing a
second synchronization service or changing the canonical coordinated
publication path.

## D-311 — application policy registry is a read-only compatibility view

Status: accepted for v0.3.3.

Decision: the active configuration snapshot owns the policy set used for new
routing decisions. Application service, command, query and orchestrator
objects may expose the compatibility registry only through read operations;
coordinated application commands are the sole publication path. A supplied
registry is sealed after application bootstrap so a retained external
reference cannot publish a policy outside the active generation.

Rationale: the registry is useful for compatibility lookups, but allowing its
public mutation creates a second policy source that can disagree with the
active snapshot and its operator-facing queries. A read-only view preserves
the existing lookup surface without introducing another configuration store.

## D-312 — one application owns one active policy registry

Status: accepted for v0.3.3.

Decision: a `PolicyRegistry` supplied to an application service is exclusively
bound after successful construction. A second independent active application
may not reuse that registry; it must provide its own active configuration and
compatibility state.

Rationale: a read-only view prevents direct mutation, but two application
instances could still share the underlying command-owned registry and make
their active snapshots disagree. Exclusive ownership closes that cross-instance
configuration boundary without adding a synchronization service.

## D-313 — bind application registry only after successful construction

Status: accepted for v0.3.3.

Decision: a supplied policy registry is bound to an application service only
after orchestrator, command and query surfaces have all constructed
successfully.

Rationale: failed adapter validation must not leave a partially constructed
application holding an exclusive ownership token that prevents a later valid
bootstrap from using the same registry.

## D-314 — compile combined payout amount bounds

Status: accepted for v0.3.3.

Decision: configuration compilation treats selector amount bands and policy
hard amount constraints as one interval intersection. A disjoint intersection
is statically invalid; provider amount compatibility uses the same effective
intersection when the policy fixes a currency.

Rationale: independently valid constraints can still describe an impossible
payout population. Publishing that configuration as usable would defer a
deterministic control-plane error until routing and make diagnostics depend on
runtime traffic.

## D-315 — query compatibility views share the application registry

Status: accepted for v0.3.3.

Decision: application queries retain the same command-owned `PolicyRegistry`
used for active publication and expose only its read-only view. They must not
clone the registry during bootstrap.

Rationale: a read-only clone cannot mutate state, but it can still become a
stale public representation after a valid configuration change and contradict
the active policy projection.

## D-316 — reject unknown payout command fields at the HTTP boundary

Status: accepted for v0.3.3.

Decision: the HTTP payout command accepts only its canonical top-level request
fields and rejects unknown fields before constructing a payout intent. The
nested provider-specific `context` remains an opaque adapter payload; the
explicit `routing_context` remains the canonical route boundary.

Rationale: silently ignoring a misspelled route field can turn a constrained
request into an unconstrained one. Failing closed at the transport boundary
preserves route eligibility semantics without inventing PSP-specific schemas.

## D-317 — one application registry backs every compatibility view

Status: accepted for v0.3.3.

Decision: when an application supplies a `PolicyRegistry`, the orchestrator
retains that same application-owned registry and exposes only its read-only
view. It must not create a bootstrap clone that can become stale after
coordinated publication.

Rationale: Service, Commands, Queries and Orchestrator are one application
generation. Their compatibility views must describe the same active policy
set; mutation remains restricted to the coordinated command path.

## D-318 — application registry views follow the atomic configuration snapshot

Status: accepted for v0.3.3.

Decision: compatibility read-only policy views exposed by an application read
the active `ConfigurationStore` snapshot under its publication lock. The
command-owned registry remains an internal mutation/index seam and must not be
used as the public generation source during a configuration transaction.

Rationale: coordinated publication updates the provider catalog and registry
before the immutable configuration snapshot is committed. Reading the
registry directly could expose a new policy while the active generation was
still old. Snapshot-backed views make the application policy surface atomic
without introducing a second configuration publisher.

## D-319 — reject bodies on bodyless HTTP commands

Status: accepted for v0.3.3.

Decision: `POST /v1/payouts/:id/resume` rejects any non-empty request body
before invoking the application command. The endpoint has no body-defined
controls; its only input is the payout identity and the canonical empty query
surface.

Rationale: silently discarding a body makes malformed or future-looking
controls appear accepted while having no effect. Failing closed at the
transport boundary keeps the public command contract explicit without adding
an API-specific resume policy.

## D-320 — provider request payloads cannot drop explicit contracts

Status: accepted for v0.3.3.

Decision: when a `ProviderOperationRequest` receives an executable payload and
an explicit operation contract, the contract is attached to the immutable
payload if absent, and conflicting contracts are rejected. The request
identity check remains authoritative for provider and idempotency linkage.

Rationale: silently ignoring a contract supplied alongside a payload can
remove status-lookup, idempotent-retry or expiry capabilities from a request.
That would change recovery legality at the provider boundary; preserving one
contract source or failing closed keeps operation semantics executable and
restart-safe.

## D-321 — executable operation payloads are the sole route-field source

Status: accepted for v0.3.3.

Decision: when a `ProviderOperationRequest` receives an executable payload, the
legacy destination/context/route fields must remain at their omitted defaults;
otherwise the constructor rejects the mixed request. The explicit contract
compatibility field remains supported by D-320.

Rationale: silently ignoring a second route interpretation makes a provider
request look accepted while carrying different method/rail semantics than its
caller supplied. Rejecting duplicate route fields keeps one immutable payload
as the provider boundary's semantic source of truth.

## D-322 — capacity amount usage is dimensioned by the active budget currency

Status: accepted for v0.3.3.

Decision: capacity reservations retain their original payout currency, while
capacity availability and snapshots select used minor units in the current
budget currency. Replay applies the same currency-aware projection.

Rationale: an active provider budget may change currency while an older payout
still owns a reservation. Summing RUB exposure into a USD budget would make
admission depend on incompatible units; preserving per-currency usage avoids
that mixing without releasing or rewriting the old reservation.

## D-323 — capacity release underflow is preflighted before mutation

Status: accepted for v0.3.3.

Decision: live admission and replay capacity release validate the existing slot
and currency-specific amount before changing either usage counter. Wrong-
currency, oversized and duplicate releases are rejected without partial state
mutation.

Rationale: capacity usage is now dimensioned by currency, so a failed release
must not decrement the shared in-flight slot or materialize a negative bucket.
Preflighting both invariants preserves safe recovery after malformed or
duplicated release input.

## D-324 — application ownership is reserved before provider bootstrap

Status: accepted for v0.3.3.

Decision: `Application::Service` reserves exclusive ownership of its policy
registry before an `Orchestrator` can synchronize a supplied configuration's
provider catalog. A failed bootstrap releases the reservation, while a
competing application fails before mutating its coordinator.

Rationale: provider catalog synchronization is an application bootstrap side
effect. Checking registry ownership only after that synchronization allowed a
rejected second application to retain a partially initialized provider
catalog. Reservation makes application construction fail closed at the
earliest boundary and preserves retry-after-failure behavior.

## D-325 — routing and recovery identities reject arbitrary coercion

Status: accepted for v0.3.3.

Decision: policy lookup scope, executable provider operation identities and
recovery work identities accept only String or Symbol values before
normalization. Arrays and arbitrary objects are rejected rather than coerced
to potentially colliding strings.

Rationale: a typed boundary must not turn malformed structured input into a
valid identity. Provider idempotency and recovery linkage are especially
sensitive to collisions, while raw provider metadata remains schema-free and
is not affected by this decision.

## D-326 — core routing and state identities share strict scalar normalization

Status: accepted for v0.3.3.

Decision: transactional routing/state value objects and public provider
selection/configuration lookups use the same strict String-or-Symbol identity
normalization. Arrays and arbitrary objects are rejected before they can enter
allocation, lifecycle, fact, snapshot, health, quality or coordinator state.

Rationale: PTZ3-151 covered several ingress seams, but adjacent core objects
still accepted arbitrary values and could canonicalize them differently. One
shared invariant prevents malformed IDs from colliding across live state,
durable facts and replay without changing provider metadata payload semantics.

## D-327 — provider configuration scalars reject arbitrary coercion

Status: accepted for v0.3.3.

Decision: capacity currency, provider supported currencies and provider
capability version accept only String or Symbol values before normalization.
Arbitrary objects are rejected even when their `to_s` output resembles a
valid currency or protocol version.

Rationale: these values are typed control-plane inputs that participate in
functional eligibility, admission dimensions and executable provider
semantics. Coercing arbitrary objects can turn malformed configuration into a
valid but unintended route or capability identity; fail-closed validation
preserves the canonical configuration boundary.

## D-328 — provider exclusion reasons are typed diagnostics

Status: accepted for v0.3.3.

Decision: `ProviderOpportunity#exclusion_reason` accepts String or Symbol
values, or nil, and rejects arbitrary objects before normalization.

Rationale: an exclusion reason is part of the provider opportunity's typed
admission explanation and configuration projection. It must not inherit the
schema-free coercion reserved for raw provider payload metadata.

## D-329 — HTTP normalizer mappings use canonical provider identities

Status: accepted for v0.3.3.

Decision: provider normalizer configuration keys are normalized through the
strict String/Symbol provider identity boundary. Arbitrary objects are
rejected even when their `to_s` output matches a provider id.

Rationale: the mapping selects executable provider-specific normalization for
webhook input. Coercive keys can bind the wrong normalizer to a real provider
and make the public API's provider boundary depend on malformed configuration.
