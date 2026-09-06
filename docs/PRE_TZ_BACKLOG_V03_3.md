# Pre-TZ Backlog — v0.3.3 Skeptical Hardening & Product Semantics

This is the current concise execution queue for SPEC-007. v0.3.2/SPEC-006 is a protected historical checkpoint, not the active stop condition.

Important: this backlog is a **living list of known work**, not proof of completeness. Exhausting it only allows transition to `VERSION_CANDIDATE`; the independent skeptical closure in `docs/COMPLETION_POLICY.md` may discover and add new required work.

Priority: P0 before P1 unless a P1 slice directly unblocks a P0 proof.

## P0 — Must close

### PTZ3-001 — Atomic active configuration generation

Problem: provider catalog and policy registry are replaced sequentially, while submit/resume do not share the configuration mutex. A concurrent new payout may theoretically observe a mixed generation.

Done when:

- one immutable active configuration snapshot/revision is the routing read authority;
- policy resolution and provider evaluation for a new decision use the same revision;
- controlled concurrency proves config A→B versus submit yields entirely A or entirely B, never mixed;
- provider I/O remains outside config/atomic locks;
- failures during replacement cannot leave a mixed active state;
- pinned unresolved payout semantics remain stable after active replacement.

Status: COMPLETE in the current implementation checkpoint. Active configuration now publishes immutable revisioned snapshots; routing readers and configuration publishers share one lock, policy resolution and provider evaluation consume the same snapshot, and controlled concurrency proves whole-generation A-or-B behavior with provider I/O outside the lock. Pinned unresolved payout behavior remains covered.

### PTZ3-002 — Fail-closed RoutingContext/input shape

Problem: malformed non-Hash routing context can currently collapse to an empty context.

Done when:

- nil remains an explicit empty context;
- typed RoutingContext/valid Hash forms canonicalize normally;
- scalar/array/arbitrary object forms fail closed at domain/application boundaries;
- HTTP returns controlled invalid-input behavior;
- restart/provider payload identity remains stable for valid input.

Status: COMPLETE in the current implementation checkpoint. Nil remains an explicit empty route context, while scalar/array/arbitrary object inputs fail closed at the typed domain and HTTP submission seams; explicit false no longer falls through as absent. Deterministic unit and HTTP regressions cover the original broadening behavior.

### PTZ3-003 — Per-sample quality age semantics

Problem: cohort staleness is based on newest evidence timestamp, so old expired samples can still contribute when one fresh sample exists.

Done when:

- only fresh samples contribute to score, maturity and confidence when age limit is configured;
- one fresh sample cannot refresh expired history;
- age filtering versus bounded sample-window order is explicit;
- mixed-age opposite-sign regressions are deterministic;
- replay/restart at the same as-of yields equivalent authority/score.

Status: COMPLETE in the current implementation checkpoint. Routing snapshots
apply the configured age limit to each sample retained in the bounded
append-order window before calculating score, maturity and confidence; durable
evidence snapshots retain the full window for fact validation and replay. A
deterministic opposite-sign mixed-age regression proves that fresh failure
evidence cannot be refreshed by expired successes, and live/replay/restart
snapshots agree at one controlled `as_of`.

### PTZ3-004 — Clock-origin-independent restart timing

Problem: persisted monotonic values are not yet proven portable across process/host restart with a different monotonic origin.

Done when:

- recovery schedules, TTL/deadline and throughput windows reconstruct/rebase into the current process monotonic domain from portable durable anchors or equivalent semantics;
- old monotonic values are never blindly compared with an unrelated new origin;
- restart test uses a second controlled clock with a deliberately different origin;
- due/not-due and expiry/window results remain correct without real sleeps.

Status: COMPLETE in the current implementation checkpoint. Durable restore
rebases payout/operation/evaluation/throughput monotonic references and
recovery deadlines from portable wall anchors into the current clock origin;
persisted raw coordinates are retained as durable data but are not used as the
next process's runtime coordinates. Controlled restart regressions use a
deliberately different monotonic origin and cover recovery due timing, TTL
precedence and throughput-window admission.

### PTZ3-005 — Replay must clear superseded recovery schedule on reconciliation block

Discovery: fresh CI run #87 on documentation-only v0.3.3 governance HEAD exposed a real pre-existing cross-layer defect in the deterministic concurrency campaign. Live `expire_unresolved_operation!` clears the pending recovery schedule before publishing `reconciliation_blocked`, while `Projections::Replay::LifecycleState` currently applies the blocked status without clearing the prior schedule. Replay can therefore attempt to construct an impossible non-unresolved payout that still carries `recovery_schedule`.

Done when:

- lifecycle replay clears/supersedes recovery schedule under the same transition semantics as live reconciliation blocking;
- a deterministic regression reproduces `UNKNOWN/pending + scheduled recovery -> TTL/deadline reconciliation_blocked -> replay`;
- live, replay and fresh restore agree on status, ownership and absence of a stale schedule;
- the high-contention campaign no longer exposes this invalid snapshot under adversarial interleavings;
- the fix uses shared transition semantics where practical rather than weakening `PayoutSnapshot` validation.

Status: COMPLETE in the current implementation checkpoint. The replay transition now clears the superseded schedule while retaining economic ownership; a controlled-clock regression covers live, lifecycle replay and fresh `Coordinator.from_facts`, and the high-contention campaign passes without the invalid snapshot. The original CI failure was reproduced before the fix, not masked by reruns.

## P1 — High-value case semantics

### PTZ3-101 — Currency-aware quality cohorts

Do not silently pool provider quality across materially different currencies merely because route dimensions match. Keep Money authoritative; introduce a bounded typed evidence key and deterministic fallback hierarchy.

Status: COMPLETE in the current implementation checkpoint. Quality evidence
is keyed by provider, normalized currency and bounded route/context cohort;
known-currency queries never fall back to unscoped evidence. Coordinator
facts persist the currency, replay/restoration preserve it, and restoration
rejects a quality fact whose currency disagrees with the source payout. Unit
and controlled-clock scenario coverage proves USD/EUR separation across live,
replay and restart.

### PTZ3-102 — Sparse route-evidence authority

Prevent tiny route samples from automatically overriding mature broader evidence. Define explicit per-scope maturity/confidence or exact deterministic hierarchical shrinkage.

Status: COMPLETE in the current implementation checkpoint. Route cohorts use
an explicit policy threshold derived as at least two samples by default, while
the existing minimum can be explicitly opted into for a deliberately sparse
route. An immature route falls back to mature same-currency broader evidence
and cannot override it; once mature, route evidence is authoritative. Unit
coverage proves the fallback and exact transition boundary.

### PTZ3-103 — Policy selector subsumption + amount bands

Replace field-count-only specificity with semantic narrowing where possible. Equal-priority incomparable matches remain ambiguous. Add exact currency-safe amount bands without a generic DSL. Preserve registration-order invariance.

Status: COMPLETE in the current implementation checkpoint. Same-priority
resolution now uses an explicit semantic narrowing partial order: a selector
must contain every broader constraint and may add a route, label, currency or
contained amount-band constraint; incomparable maxima remain ambiguous under
registration permutations. Amount bands use inclusive exact minor-unit
Integer bounds and require an explicit selector currency. Boundary,
incomparability, permutation, invalid-band and durable selector/fingerprint
tests are green.

### PTZ3-104 — Configuration compiler/source-of-truth

Make active configuration revision ownership explicit and validate policy/provider relationships as a system. Produce typed diagnostics for valid, warning and statically invalid/unreachable relationships where determinable without rejecting legitimate temporary outage/absence semantics.

Status: COMPLETE in the current implementation checkpoint. `ConfigurationCompiler`
now publishes typed deterministic diagnostics alongside each immutable active
configuration revision: missing or currently inadmissible targets are warnings,
while statically infeasible policies and fixed currency/route/amount
incompatibilities are errors rejected before provider or registry mutation.
Application queries expose the revision diagnostics and derived status. Focused
application regressions prove warning publication, invalid rollback and
fail-closed static policy compilation; acceptance traceability includes
PTZ3-104.

### PTZ3-105 — Recovery objective semantics

Keep `allocation_constrained` default. Implement reliability-first/equivalent only if it is generically useful and preserves safety, admission, recovery legality/budgets and primary allocation accounting. If the evidence says the second mode is unjustified, retain the typed seam and record why.

Status: COMPLETE by evidence-gated scope decision. The actual recovery seam
already enforces recovery legality and attempted-provider exclusion, then
dispatches through exact `allocation_constrained` authority; quality, cost and
latency remain a later optimizer stage restricted to allocation ties. A generic
reliability-first mode would either duplicate the existing optimizer or allow
quality to trade away allocation obligations without an authoritative product
objective. The typed default remains explicit, durable and explainable, and a
deterministic regression proves recovery quality cannot select outside the
allocation-authority candidate set.

### PTZ3-106 — Configuration/recovery architecture convergence

Extract only boundaries that remove duplicate semantic sources, especially active config snapshot ownership and portable timing/rebase semantics. Coordinator remains the atomic facade.

Status: COMPLETE in the current implementation checkpoint. Active
configuration publication and portable timing already have single owners from
the preceding slices. The remaining live/restore allocation branch was
centralized behind pure `AllocationAuthority`, which preserves the explicit
primary versus recovery boundary while keeping recovery legality and primary
accounting distinct. Live `DecisionEngine` and durable trace validation now
consume the same allocation seam; focused path-parity and existing replay
regressions cover both consumers without introducing a restorer or changing
the atomic Coordinator facade.

### PTZ3-107 — Product/demo/query parity

Expose current configuration revision/apply semantics, due-work and dimension-safe analytics queries through thin application/HTTP/CLI paths where useful. Preserve typed no-policy/ambiguous-policy errors where possible without guessing official TZ schema.

Status: COMPLETE in the current implementation checkpoint. The application
surface already owns configuration apply, revision/diagnostic queries,
due-recovery work and dimension-safe analytics. HTTP now exposes those existing
semantics through read-only `/v1/configuration`, `/v1/recovery/due-work` and
typed `/v1/analytics` query parameters; the legacy full analytics response is
preserved when no metric is requested. Controlled HTTP regressions cover
configuration diagnostics, exact due-work identity, query grouping and the
absence of routing logic in the adapter. No speculative configuration transport
schema was introduced before the official TZ.

### PTZ3-108 — Context-scoped health experiment

First prove with a deterministic multi-route provider scenario whether provider-global quarantine suppresses healthy traffic. Implement bounded route health only if the defect is material.

Status: COMPLETE on the current implementation checkpoint. The deterministic
multi-route scenario showed that a provider-global quarantine after a card
failure would suppress the same provider for an otherwise healthy
bank-transfer route. Health now keeps provider-global state for empty/unknown
route context and a separate bounded cohort for canonical
payment_method/rail/destination_kind dimensions when present. Labels are not
part of this fast-health key, preventing arbitrary label cardinality from
turning health into an unbounded per-tenant registry. Live evaluation,
provider observation facts, restart restoration, replay projection and probe
reservation/release use the same cohort semantics; the economic UNKNOWN and
ownership rules are unchanged.

### PTZ3-109 — Larger-history evidence

After correctness work, measure restore/query/audit/memory/throughput curves beyond the current 10k checkpoint. Optimize only measured bottlenecks.

Status: COMPLETE as measured evidence; no unproven optimization was introduced.
The existing `HistoryProfile` harness was run on the current code at the
following sizes (single-process sequential profile unless marked concurrent):

| payouts | facts | lifecycle | analytics | restore | audit page | filtered audit | heap delta |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1,000 | 14,002 | 4.47s | 0.17s | 3.85s | 0.46ms | 1.15ms | 36.8MB |
| 2,500 | 35,002 | 11.46s | 0.76s | 9.91s | 0.48ms | 2.60ms | 92.0MB |
| 5,000 | 70,002 | 27.60s | 1.13s | 20.48s | 0.84ms | 1.12ms | 183.8MB |
| 12,500 | 175,002 | 93.42s | 2.37s | 47.30s | 1.85ms | 1.25ms | 458.8MB |

The 12,500 payout profile is beyond the former 10k lifecycle checkpoint.
The concurrent 12,500/4-worker profile produced the same 175,002 facts in
83.52s (149.7 payouts/s). The observed memory and lifecycle growth is
material evidence for future scale work, but no target or deployment
requirement justifies introducing indexes/checkpoints or a persistence
subsystem before the official TZ; the bounded audit query itself remained
low-latency in this workload.

### PTZ3-110 — SPEC-007 traceability and independent skeptical closure

Done when:

- mandatory SPEC-007 behavior has executable traceability;
- all known P0/P1 are verified;
- status becomes `VERSION_CANDIDATE`, not complete;
- a fresh adversarial discovery pass ignores checklist completion as a premise and searches for unplanned cross-layer counterexamples;
- any material new finding is added here and development resumes;
- only after a no-material-finding pass does exact-HEAD full verification/CI run;
- documentation agrees with actual implementation and current stop rules.

Status: COMPLETE / `VERSION_COMPLETE` — all currently known P0/P1 slices are
green on the exact candidate, the fresh independent skeptical discovery found
no further material locally solvable finding, final local verification and
product evidence are green, and authenticated GitHub Actions run
`33474999166` for `f59bdd60c268a3982e32ad45353bf4c292f14153` completed
successfully in both workflow jobs.

### PTZ3-111 — Supplied configuration bootstrap/source consistency

Discovery: a product/application instance constructed with an active
`ConfigurationStore` but without a matching `PolicyRegistry` created an empty
compatibility registry; the next incremental policy registration could drop
already published policies. A supplied provider generation could also route
successfully through the snapshot while leaving the coordinator catalog
unregistered, making fresh durable restore fail.

Status: COMPLETE. The application and orchestrator now seed/validate the
compatibility registry from the active generation, reject mismatched registry
injection before mutation, and bootstrap supplied provider definitions into
the coordinator before routing. Deterministic tests cover policy preservation,
mismatch fail-closed behavior, successful fresh restore and direct
orchestrator construction.

### PTZ3-112 — Ambiguous HTTP query parameters

Discovery: `URI.decode_www_form(...).to_h` silently selected the last value
when a query parameter was repeated, making control/query semantics dependent
on wire ordering.

Status: COMPLETE. The HTTP adapter now rejects duplicate decoded query keys
with the existing controlled invalid-request response. Audit, analytics and
due-work paths share the parser, with deterministic duplicate `limit`,
`metric` and `as_of` regressions.

### PTZ3-113 — Future-dated quality evidence

Discovery: an observation timestamp later than an injected analytics `as_of`
was filtered out of sample counts but still reported as `last_observed_at`,
causing the quality snapshot constructor to reject its own as-of result.

Status: COMPLETE. Quality as-of filtering now excludes evidence after the
requested time from counts and latest-timestamp reporting while preserving
the full durable evidence window for replay. A deterministic future-timestamp
regression covers conservative pre-evidence and later authoritative views.

### PTZ3-114 — Active configuration replacement rollback

Discovery: a post-commit provider-catalog error could leave the durable
catalog on the new generation while the active configuration snapshot stayed
old. This violated the configuration failure atomicity acceptance even though
ordinary replacement tests were green.

Status: COMPLETE. Application configuration/provider-runtime mutations now
perform compensating catalog/registry rollback when a replacement fails after
its lower-level mutation; rollback failure escalates as durable corruption.
Fault injection proves the old snapshot, registry and provider catalog remain
coherent after a one-time post-commit failure.

### PTZ3-115 — Policy currency participates in semantic overlap

Discovery: policy-level `currency` is an independent matching constraint, but
same-priority semantic subsumption compared only the nested selector. A
currency-only policy and a payment-method-only policy could therefore be
treated as an ordered winner on their overlap instead of remaining visibly
ambiguous.

Status: COMPLETE. Policy resolution now compares an effective selector that
includes the policy currency, while preserving the existing explicit priority,
amount-band and registration-order semantics. A deterministic permutation
regression proves the overlapping currency/method maxima remain ambiguous.

### PTZ3-116 — Quality routing-context boundary

Discovery: `QualityController` accepted an explicit scalar or arbitrary object
as `routing_context` and silently treated it as unscoped evidence. That could
pool malformed route evidence into the provider-global quality fallback.

Status: COMPLETE. Explicit quality routing contexts now use the canonical
fail-closed `RoutingContext.from` boundary; legacy label-only `context` forms
remain supported, while malformed route/label values raise before any state is
created. A deterministic regression proves malformed input cannot create
global evidence.

### PTZ3-118 — Policy ambiguity identity retained currency constraints

Discovery: typed ambiguous-policy responses exposed a selector and fingerprint
but omitted an independent policy-level currency constraint. Operators could
therefore see that two policies conflicted without seeing the material
currency dimension that made the overlap meaningful.

Status: COMPLETE. Policy resolution identities now retain policy currency in
the public typed projection, with a deterministic regression for the
currency-only versus route-only overlap.

### PTZ3-117 — Global health safety ceiling for scoped routes

Discovery: after a provider-global operational failure quarantined a provider,
known route-context health lookups returned a fresh scoped `healthy` default.
That allowed route-aware admission to bypass a provider-wide safety signal.

Status: COMPLETE. Scoped health now remains isolated for route-specific
failures, while any global non-healthy state is a conservative safety ceiling
for every canonical route context and its exposure reservation boundary.
Deterministic live/replay/restart evidence covers the global quarantine
boundary.

### PTZ3-119 — Decision trace configuration revision

Discovery: the active configuration snapshot exposed a revision to control-plane
queries, but a routed decision's durable evaluation/decision facts, explanation
and public audit projection did not identify which immutable generation produced
the evaluation.

Status: COMPLETE. The orchestrator now passes one snapshot revision through the
canonical decision path; evaluation and decision facts, explanation entries and
public audit retain that non-semantic trace metadata. Direct Coordinator callers
remain compatible without a revision, while malformed durable revisions fail
closed and acceptance traceability covers both publication and restore edges.

### PTZ3-120 — Duplicate JSON input keys

Discovery: the HTTP JSON boundary accepted repeated object keys and silently
used the last wire value, so a routing-critical field could change meaning
without an explicit request error.

Status: COMPLETE. Request/webhook JSON parsing now rejects duplicate object keys
before any domain command runs; a deterministic HTTP regression proves no intent
is registered from an ambiguous payload.

### PTZ3-121 — Uncoordinated active configuration mutation

Discovery: `ConfigurationStore#replace` and `#update` were publicly callable by
code holding a supplied store reference. That path could publish a new active
snapshot without updating the compatibility policy registry or Coordinator
provider catalog, allowing a payout to use an unregistered provider and making
fresh restore fail with durable corruption.

Status: COMPLETE. Configuration publication is now private to the coordinated
application command path; the store exposes immutable reads/snapshots only to
callers, while commands retain the single registry/catalog publication seam.
A deterministic application regression proves direct mutation cannot alter the
active generation or revision.

### PTZ3-122 — Dimensioned quality query as-of parity

Discovery: quality replay/application queries omitted the injected as-of time
and the currency/route cohort, so a valid fresh cohort could be displayed as a
neutral prior even though the live coordinator held fresh evidence.

Status: COMPLETE. Quality projections now retain explicit as-of, currency and
bounded route filters; application queries default to the coordinator's
controlled current time, and HTTP exposes the same filters without creating a
second quality engine. Deterministic live/application/HTTP regressions cover
staleness and currency/route visibility.

### PTZ3-123 — Route-scoped health query visibility

Discovery: route-specific provider quarantine correctly affected live/replay
admission, but the existing health query serialized only provider-global state
and displayed healthy, hiding the scoped safety decision from operators.

Status: COMPLETE. Health projections and application queries now accept an
explicit bounded canonical route context; global and route views remain
separate, and HTTP exposes `GET /v1/health` route filters without pooling
incompatible scopes. Deterministic live/replay/API coverage proves route
quarantine is visible while the global health view remains unchanged.

### PTZ3-124 — Global degraded/probing health and route admission parity

Discovery: a provider-global `degraded` state remained exposed during
evaluation, but route-scoped health reservation rejected every global
non-healthy state. A valid route assignment therefore failed before commit;
the same seam could also fail to account for a route probe against the global
probe budget.

Status: COMPLETE. Health admission now uses one effective state: global
quarantine remains a hard block, global degraded traffic remains exposed, and
global probing consumes/releases the global probe reservation. Route-scoped
observations update the effective global state when a global safety state is
active, preserving live/replay parity. Deterministic degraded assignment and
global probe recovery regressions cover both boundaries.

### PTZ3-125 — Strict persisted canonical route identity

Discovery: `RoutingContext.from` intentionally ignores unknown keys when it
interprets raw provider-operation context, but the same permissive path was
used for the explicit typed route identity on `PayoutIntent`. A corrupted
`intent_registered` fact containing only an unknown canonical key could
therefore restore as an empty route and broaden policy/provider eligibility.

Status: COMPLETE. Explicit/persisted canonical routing contexts now reject
unknown and non-symbol/string keys while raw adapter context retains its
metadata compatibility. Deterministic domain and restart regressions prove
the malformed fact fails closed before a payout state is created.

### PTZ3-126 — Strict explicit route filters and legacy label identity

Discovery: public quality and health route filters reused the permissive raw
context parser, so an unknown-only explicit route hash could collapse into a
provider-global view. Quality `context_key` also stringified arbitrary objects,
allowing nondeterministic label identities into evidence state.

Status: COMPLETE. The canonical parser is strict by default; explicit
PayoutIntent, provider-operation, quality and health route contexts use that
boundary, while inferred raw adapter context remains permissive. Legacy
quality labels accept only String/Symbol values at both live and snapshot
boundaries. Focused malformed-input regressions prove no global evidence,
health state or broad provider-operation route is created from these inputs.

### PTZ3-127 — HTTP canonical routing-context boundary

Discovery: the HTTP payout adapter accepted only the legacy `context` field
when constructing a `PayoutIntent`. A caller could not submit the explicit
typed `routing_context` used by the canonical policy/provider route path, and
the payout response did not expose the canonical route identity. This left
the public product surface unable to express or verify the same route
semantics as the Ruby application API.

Status: COMPLETE. HTTP submit now passes the optional explicit
`routing_context` through the typed intent boundary, so malformed route keys
fail with the existing controlled invalid-request response. Payout responses
expose the normalized canonical route identity. A route-capability scenario
proves the submitted route reaches the provider operation and the response,
and a malformed explicit route proves no payout is registered.

### PTZ3-128 — HTTP typed policy-resolution errors

Discovery: the canonical application layer distinguished no-match from
ambiguous policy resolution, but `HttpApp#call` rescued both as generic
`400 invalid_request`. Operators and callers could not tell whether to add a
policy or correct an overlap, despite a safe typed resolution projection
already existing.

Status: COMPLETE. The HTTP adapter maps no-match to `422 no_matching_policy`
and ambiguity to `409 ambiguous_policy`, including the sanitized typed
resolution identity. No routing logic or exception details are exposed, and
both paths prove that no payout history is created.

### PTZ3-129 — Application boundary rejects Coordinator catalog drift

Discovery: a caller could mutate the public low-level `Coordinator` provider
catalog after `Application::Service` bootstrap. The service retained the old
active configuration snapshot, so a new payout could be committed through a
provider no longer current in the durable catalog; fresh restore then failed
on provider-registration ordering. The same drift could let `resume` mutate
an unresolved payout before the application noticed the mismatch.

Status: COMPLETE on the current implementation checkpoint. Application
routing and resume now validate the supplied active provider generation under
the Coordinator atomic boundary, while application configuration queries fail
closed on the same mismatch. HTTP reports a stable `503 configuration_drift`
value. Coordinated configuration publication remains unchanged, and focused
regressions prove no payout registration or expiry mutation occurs while drift
is present. Runtime-only availability/capacity/enabled/health/throughput
changes remain operational evidence rather than configuration drift; live
evaluation uses the current Coordinator runtime over the validated active
definition so unresolved same-provider recovery remains compatible with the
pre-existing disabled-for-new-routes contract.

### PTZ3-131 — Strict HTTP route-query boundary

Discovery: route-scoped HTTP health/quality queries silently ignored unknown
or alias parameters. A typo such as `payment_methd=card` could therefore
return a provider-global view while appearing to answer a route-scoped
question, weakening operational admission safety and explainability.

Status: COMPLETE on the current implementation checkpoint. Health and quality
route query parsing now rejects unsupported parameters before projection;
canonical route dimensions remain the only accepted routing query keys.

### PTZ3-132 — Current runtime in provider projections

Discovery: runtime-only Coordinator changes were correctly accepted as
operational state, but application provider queries still returned the old
runtime flags from the active configuration snapshot. Operators could see an
available provider while admission was already disabled.

Status: COMPLETE on the current implementation checkpoint. Provider queries
now validate the active static definition and overlay the Coordinator's
current atomic runtime flags; the configuration snapshot itself remains the
immutable control-plane definition.

### PTZ3-133 — Durable JSON envelope duplicate-key rejection

Discovery: durable fact envelopes and batch journal records were parsed with
the default JSON duplicate-key behavior. A duplicate envelope key could be
silently collapsed to the last value before checksum and schema validation,
making ambiguous durable input acceptable instead of fail-closed.

Status: COMPLETE on the current implementation checkpoint. Fact and batch
decoding, plus the FileJournal record discriminator, now reject duplicate JSON
object keys before checksum/schema interpretation. Deterministic codec and
journal regressions cover fact and batch envelopes.

### PTZ3-134 — Strict application query parameter boundary

Discovery: analytics, due-recovery, audit, configuration and provider HTTP
queries silently ignored unsupported keys. A typo could therefore return a
broader result than the operator requested, especially when an as-of or
dimension filter was misspelled.

Status: COMPLETE on the current implementation checkpoint. Each product query
endpoint now declares its accepted parameters and rejects unsupported keys
before projection work. Analytics still accepts its typed dimension filters,
grouping and as-of controls; health and quality retain their canonical route
filter boundary.

### PTZ3-135 — Validate empty-result route and currency filters at the HTTP boundary

Discovery: health and quality route filters delegated value validation to the
projection. With no registered providers, malformed values such as an empty
`payment_method` or two-letter `currency` therefore returned `200` instead of
failing closed, making malformed input behavior depend on current data.

Status: COMPLETE on the current implementation checkpoint. The HTTP adapter
now constructs the canonical `RoutingContext` and validates currency before
querying projections; deterministic empty-catalog regressions cover malformed
route and currency values.

### PTZ3-136 — Reject query parameters on routes without query semantics

Discovery: the transport adapter parsed query strings only on product query
endpoints. Query parameters on health, payout submit/read/explanation/resume
and provider webhook routes were silently ignored, so an operator typo could
appear successful while not changing the request's meaning.

Status: COMPLETE on the current implementation checkpoint. Routes without
declared query semantics now parse and reject all query parameters before
domain work. A deterministic HTTP regression covers health, submit, payout
read, explanation, resume and webhook paths and proves query rejection does
not register a payout.

### PTZ3-137 — Keep the application policy registry read-only

Discovery: `Application::Service` exposed the live mutable policy registry as
a compatibility seam. Direct registration could make the registry report a
policy that was absent from the active configuration snapshot, producing
conflicting public views even though canonical routing correctly failed
closed.

Status: COMPLETE on the current implementation checkpoint. Application
service/commands/queries/orchestrator registry access is now a read-only view;
the supplied registry is sealed after bootstrap, and only coordinated command
publication may mutate it. A deterministic regression covers rejected direct
mutation and successful command publication.

### PTZ3-138 — Prevent cross-application registry sharing

Discovery: sealing a supplied registry did not prevent two independent
application instances from sharing it. A command in one instance could then
change the shared compatibility view while the other instance retained a
different active snapshot.

Status: COMPLETE on the current implementation checkpoint. A registry is now
bound exclusively to one successfully constructed application service; a
second active generation fails closed at bootstrap before it can share policy
mutation state.

### PTZ3-139 — Do not capture policy registry on failed bootstrap

Discovery: the application bound a supplied policy registry before its
orchestrator and provider adapter validation completed. A failed construction
could therefore prevent a later valid application from reusing that registry.

Status: COMPLETE on the current implementation checkpoint. Registry binding
now happens only after all application components construct successfully, and a
failed bootstrap followed by a valid bootstrap has deterministic regression
coverage.

### PTZ3-140 — Compile the intersection of selector and hard amount bounds

Discovery: configuration compilation considered a selector amount band and a
policy hard amount constraint independently. A policy requiring a selector
minimum of 100 and a hard maximum of 10 therefore compiled as usable even
though no payout could satisfy both constraints.

Status: COMPLETE on the current implementation checkpoint. Static feasibility
now rejects disjoint selector/hard amount intervals, and provider amount
diagnostics use their exact intersection when the policy fixes a currency.

### PTZ3-141 — Keep query registry views on the active registry

Discovery: `Queries#policy_registry` was a read-only clone made at bootstrap.
After a coordinated policy publication, query projections used the active
configuration but this compatibility view still exposed the old policy set.

Status: COMPLETE on the current implementation checkpoint. Queries now retain
the application-owned registry and expose a read-only view over that same
source, with post-publication parity coverage.

### PTZ3-142 — Reject unknown payout request fields

Discovery: the HTTP payout command ignored unknown top-level JSON fields. A
misspelled `routing_context` could therefore be accepted as an empty route,
silently broadening provider eligibility instead of failing at the input
boundary.

Status: COMPLETE on the current implementation checkpoint. The payout
adapter now rejects unsupported top-level request fields while preserving the
provider-specific nested `context` payload, with a no-mutation regression.

### PTZ3-143 — Keep the orchestrator registry view on the active registry

Discovery: `Application::Orchestrator` cloned a supplied policy registry at
bootstrap. After a coordinated command published a new policy, Service and
Queries showed the active policy set while the nested orchestrator compatibility
view remained stale.

Status: COMPLETE on the current implementation checkpoint. A supplied
registry is now retained as the shared read-only compatibility source, with a
deterministic publication/view regression.

### PTZ3-144 — Keep compatibility policy views atomic with active generation

Discovery: during coordinated policy publication, the command-owned registry
was replaced before `ConfigurationStore` published the new immutable snapshot.
The application compatibility view could therefore expose the new policy set
while the active configuration still exposed the previous generation.

Status: COMPLETE on the current implementation checkpoint. Application
read-only policy views now resolve through the current configuration snapshot
under its publication lock; a deterministic barrier regression proves that no
partial generation is observable.

### PTZ3-145 — Reject non-empty bodies on resume

Discovery: the HTTP resume command had no body semantics but silently ignored
any body before invoking the command. A caller could therefore send an
unknown or future control field and receive a response that looked accepted.

Status: COMPLETE on the current implementation checkpoint. Resume now reads
and rejects non-empty bodies before any payout lookup or mutation, with a
deterministic no-mutation regression.

### PTZ3-146 — Do not drop an explicit provider operation contract

Discovery: `ProviderOperationRequest` accepted both an executable `payload:`
and a separate `contract:` but silently ignored the latter whenever the
payload was supplied. A caller could therefore lose resolution, retry or
expiry semantics without an error.

Status: COMPLETE on the current implementation checkpoint. The constructor
now preserves a supplied contract in the immutable payload or rejects a
conflicting payload contract, with deterministic coverage for both branches.

### PTZ3-147 — Reject duplicate legacy route fields beside executable payload

Discovery: a direct provider-request caller could supply `payload:` and a
different legacy `routing_context:` simultaneously; the legacy route fields
were silently ignored.

Status: COMPLETE on the current implementation checkpoint. Requests carrying
an executable payload now reject any non-default legacy destination/context or
route fields, with deterministic coverage for a conflicting route context.

### PTZ3-148 — Keep capacity amount usage dimensioned across budget changes

Discovery: changing a live provider capacity budget from one currency to
another while an older payout reservation remained in flight reused the old
minor-unit total under the new currency.

Status: COMPLETE on the current implementation checkpoint. Admission and
replay retain per-currency in-flight amounts and expose/use the amount in the
current budget currency, with a deterministic reconfiguration regression.

### PTZ3-149 — Reject capacity-release underflow without partial mutation

Discovery: after the currency-aware capacity change, a malformed public release
could decrement the in-flight slot before detecting a wrong-currency or
over-sized amount, leaving the live ledger inconsistent for later valid
releases.

Status: COMPLETE on the current implementation checkpoint. Live admission and
replay validate both slot and currency-specific amount underflow before
mutating either counter, with deterministic regression coverage for wrong
currency, oversized and duplicate releases.

### PTZ3-150 — Do not mutate a coordinator after rejected application bootstrap

Discovery: a second `Application::Service` using an already bound policy
registry and a provider-bearing active configuration synchronized its new
Coordinator before failing on registry ownership. The failed construction
therefore left provider history partially initialized despite the application
never becoming active.

Status: COMPLETE on the current implementation checkpoint. Service bootstrap
reserves policy-registry ownership before provider synchronization and releases
the reservation on failed construction, while a competing application now
fails before mutating its coordinator. A deterministic application regression
proves the rejected coordinator remains empty.

### PTZ3-151 — Reject arbitrary coercion at routing and recovery identity boundaries

Discovery: policy scope lookup, executable provider operation contracts/requests
and recovery schedule/work values accepted arrays or arbitrary objects and
coerced them to strings. A malformed value could collide with a legitimate
string identity and bypass the intended typed boundary.

Status: COMPLETE on the current implementation checkpoint. These boundaries
now accept only String or Symbol identities while preserving canonical
normalization for valid values. Deterministic regressions cover policy scope,
operation provider/idempotency/version/request identities and recovery work.

### PTZ3-152 — Enforce strict scalar identities across core state and routing

Discovery: a fresh adjacent-layer probe found that DecisionProposal,
AttemptSnapshot, Fact, lifecycle phase changes, allocation snapshots, policy
constraints, health/quality snapshots and provider catalog lookups still
accepted arrays or arbitrary objects and coerced them to strings. That left
live transactional state and durable identity boundaries inconsistent with
PTZ3-151.

Status: COMPLETE on the current implementation checkpoint. A shared identity
normalizer now rejects non-String/Symbol values across those core boundaries,
while preserving trimming and Symbol compatibility. Deterministic regressions
cover representative live routing/state constructors and provider catalog
lookup behavior.

### PTZ3-153 — Reject arbitrary provider configuration scalar coercion

Discovery: a fresh malformed-input probe found that capacity currency,
provider supported currencies and capability version accepted arbitrary objects
through `to_s`. An object returning `RUB` or a valid protocol version could
therefore collide with typed configuration and change eligibility, admission or
provider operation semantics.

Status: COMPLETE on the current implementation checkpoint. Provider
configuration currency and capability-version boundaries now accept only
String/Symbol values before normalization. Deterministic regressions prove
spoofed scalar objects are rejected while valid canonical values remain
unchanged.

### PTZ3-154 — Reject arbitrary provider exclusion-reason coercion

Discovery: an adjacent configuration probe found that a disabled
`ProviderOpportunity` accepted an arbitrary object as `exclusion_reason` and
coerced it through `to_s`. That value is part of typed admission diagnostics,
not schema-free provider metadata, so the object could enter configuration and
public reason projections under a colliding string identity.

Status: COMPLETE on the current implementation checkpoint. Provider exclusion
reasons now accept only String/Symbol values or nil before normalization, with
deterministic malformed-configuration regression coverage.

### PTZ3-155 — Reject arbitrary HTTP normalizer provider-id coercion

Discovery: `HttpApp` accepted provider normalizer mapping keys through `to_s`,
so an arbitrary object whose string form matched a configured provider could
silently install the normalizer for that provider. This was a typed API/control
mapping boundary, not raw webhook metadata.

Status: COMPLETE on the current implementation checkpoint. HTTP normalizer
configuration now uses canonical strict provider identity normalization and
rejects non-String/Symbol keys before bootstrap. Deterministic application
boundary coverage proves spoofed keys cannot be registered.

### PTZ3-130 — Resume decision configuration traceability

Discovery: application resume used the active configuration snapshot for its
guarded state transition, but the restart `decision_committed` fact omitted
that generation. Recovery interactions therefore lost the configuration
traceability already present on live assignment and resolution decisions.

Status: COMPLETE on the current implementation checkpoint. The canonical
Orchestrator passes the active snapshot revision through `Coordinator#resume_operation`,
which records it on restart recovery decisions. Direct low-level Coordinator
callers may continue to omit the optional revision for compatibility.

## P2 — Optional only after P0/P1 and skeptical discovery

- additional dashboard polish;
- adaptive/statistical exploration only after official scoring;
- production infrastructure only after authoritative/runtime need;
- deeper persistence optimization only if measured history curves justify it.

## Explicit non-priorities

Do not use pre-TZ time for microservices, Rails/ORM/queues, brand-specific PSP core schemas, cosmetic Coordinator splitting, speculative distributed deployment or ML/bandits for presentation value.

## When the authoritative TZ arrives

Immediately freeze speculative expansion, ingest the full source, execute `docs/TZ_RECONCILIATION.md`, classify every authoritative requirement as `CONFIRMED / CHANGED / REMOVED / NEW / AMBIGUOUS`, and reorder development around official compliance/scoring.
