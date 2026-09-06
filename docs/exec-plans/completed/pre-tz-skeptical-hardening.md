# ExecPlan — v0.3.3 Pre-TZ Skeptical Hardening & Product Semantics

Status: VERSION_COMPLETE

## Purpose

Continue development after the strong v0.3.2 checkpoint. The project does not wait for the official TZ while material case-relevant defects can still be found and solved locally.

This plan is governed by `specifications/007-pre-tz-skeptical-hardening.md`. It preserves the financial/economic correctness established by earlier versions and focuses on cross-layer correctness where configuration, time, evidence, restart and smart-routing semantics interact.

## Current Version Goal

Make RubyRouting resilient to skeptical counterexamples that are not captured by the previous checklist, then close only after an independent adversarial discovery pass finds no remaining locally solvable P0/P1 case-relevant defect.

## Current findings that reopened development

A fresh review of exact `main` after the v0.3.2 closure identified these material gaps:

1. `Application::Commands#apply_configuration` updates provider catalog and policy registry sequentially under a config mutex that `submit/resume` do not share. A concurrent new payout can theoretically resolve one configuration generation and evaluate providers from another.
2. `RoutingContext.from` treats arbitrary non-Hash values as an empty context, creating fail-open routing semantics at malformed boundaries.
3. quality age staleness is cohort-level via newest observation time; expired samples can still contribute to score/maturity when one newer sample keeps the cohort fresh.
4. persisted monotonic recovery/throughput values are not proven portable across a restart with a different monotonic origin.
5. [closed PTZ3-101] route quality cohorts omitted currency, so comparable evidence could pool materially different currency populations.
6. [closed PTZ3-102] route cohort authority could become mature with the global `minimum_samples` default and override much stronger broader evidence too early.
7. [closed PTZ3-103] selector specificity was count-based rather than semantic subsumption and could not express generic amount bands.
8. typed active configuration represents policies/providers together but their active/durable ownership semantics are not yet one coherent revisioned source of truth.
9. post-governance CI #87 exposed a pre-existing live/replay divergence: live reconciliation blocking clears a pending recovery schedule, while lifecycle replay can retain that superseded schedule and then fail to construct a valid blocked payout snapshot. This is PTZ3-005 and is the current first repair because exact-main verification is red until the semantic divergence is resolved rather than retried away.
10. the public low-level Coordinator catalog could drift after Application::Service bootstrap, leaving the active snapshot stale; a new payout could route through a provider already removed from durable current history, and resume could mutate state before discovering the mismatch. This is PTZ3-129 and reopens the skeptical phase until the application boundary fails closed.
11. a rejected second Application::Service could synchronize provider history into its Coordinator before discovering that the supplied PolicyRegistry was already owned by another active application. This PTZ3-150 bootstrap side effect left failed construction with partial catalog state.
12. policy lookup, executable operation and recovery identity boundaries accepted arbitrary values and coerced them into strings, so malformed structured input could collide with a legitimate identity. This PTZ3-151 is now fail-closed without changing raw provider metadata.
13. adjacent core state and routing boundaries still accepted arbitrary provider/operation/fact values and coerced them independently. PTZ3-152 centralizes strict scalar identity normalization across live value objects, allocation, lifecycle, facts, snapshots, health/quality and coordinator/application lookups.
14. provider configuration still coerced arbitrary currency and capability-version objects through `to_s`. A malformed value whose string form matched a valid token could enter capacity admission, provider eligibility or executable capability semantics. PTZ3-153 closes this typed configuration seam without changing valid String/Symbol normalization.
15. provider exclusion reasons were another typed configuration scalar that accepted arbitrary objects through `to_s`, allowing malformed admission diagnostics to enter active configuration. PTZ3-154 closes that adjacent boundary while leaving raw adapter payload fields schema-free.
16. HTTP provider-normalizer mapping keys accepted arbitrary provider-id objects through `to_s`, which could bind a spoofed configuration key to a real webhook provider. PTZ3-155 routes that API/control mapping through strict identity normalization.

These findings invalidate the earlier statement that no locally solvable P0/P1 work remains. v0.3.2 remains a verified historical checkpoint; it is not the current stop condition.

## Governing sources

Read in this order for a substantial session:

1. `AGENTS.md`
2. `README.md`
3. `specifications/007-pre-tz-skeptical-hardening.md`
4. this ExecPlan
5. `docs/PRE_TZ_BACKLOG.md`
6. `docs/ROADMAP.md`
7. `docs/COMPLETION_POLICY.md`
8. `docs/PRE_TZ_ARCHITECTURE_V03_3.md`
9. `docs/DECISIONS_V03_3.md`
10. `docs/PRE_TZ_ARCHITECTURE.md` / `docs/CURRENT_ARCHITECTURE.md` as inherited architecture baseline
11. SPEC-006/005 only for inherited guarantees and historical rationale
12. `docs/TZ_RECONCILIATION.md`.

Before implementation, inspect actual HEAD, production code, tests and current CI. Never infer current implementation solely from statuses written in this plan. Fresh runtime/CI evidence may reprioritize the Rolling Next Actions and must be recorded rather than hidden.

## Protected baseline

Do not casually rewrite:

- exact Integer/Rational financial arithmetic;
- economic ownership and conservative UNKNOWN handling;
- operation-scoped idempotency and provider capability contract;
- primary/recovery/settlement separation;
- functional opportunity versus operational admission;
- atomic commit before provider I/O;
- provider I/O outside the atomic state lock;
- durable facts/replay/restart unresolved continuation;
- dimension-safe analytics;
- provider normalization and public-audit privacy;
- deterministic/property/model/concurrency/fault evidence.

A refactor is justified only when it removes semantic duplication, closes a proven defect or measurably improves the current version goal.

## Execution order

Default dependency order:

`Baseline re-orientation / restore exact-main verification`
→ `Live/replay reconciliation-schedule parity`
→ `Atomic active configuration snapshot/revision`
→ `Fail-closed route input boundary`
→ `Per-sample quality age semantics`
→ `Clock-origin-independent durable timing`
→ `Currency-aware / confidence-safe quality cohorts`
→ `Policy selector semantics + amount bands`
→ `Configuration compiler/source-of-truth`
→ `Recovery objective seam`
→ `Semantic architecture convergence`
→ `Product/demo/query parity`
→ `Evidence-gated context health`
→ `Larger-history measurement`
→ `Independent skeptical closure`.

Independent slices may overlap when safe. A newly discovered correctness regression outranks feature hardening until its semantics and deterministic regression are understood.

## Phase 0 — Re-orient from actual main

Goal: establish the current session baseline without trusting completion labels.

Required:

- record exact HEAD;
- inspect changes since the last known checkpoint;
- inspect current CI, including the exact failing seed/interleaving when red;
- inspect current code paths for live/replay reconciliation, configuration, submit/resume, quality, clocks/restart and policy selection;
- update this plan if implementation or fresh evidence differs from the findings above.

Baseline evidence on 2026-08-31: exact `main` and `origin/main` were both
`4e1fea4f3b9182e6967bf39475f9ceaace758b90`, with a clean worktree before
implementation. The current workflow still requires the full Ruby,
property/model/concurrency/fault matrix plus bounded product evidence. A
minimal fake-clock reproduction confirmed that live expiry produced
`reconciliation_blocked` with no schedule while lifecycle replay raised from
`PayoutSnapshot` because it retained the superseded schedule.

Exit: factual baseline and first slice selected.

## Phase 0A — Restore live/replay semantic parity for reconciliation blocking

Goal: close PTZ3-005 before treating the broad verification baseline as healthy.

Observed evidence: CI #87 reached 533/10,009 green full-suite assertions plus green property/model stages, then the dedicated concurrency campaign failed while building lifecycle replay because a `reconciliation_blocked` payout retained a stale `recovery_schedule`. The failure was reproduced deterministically with a controlled clock and a TTL of 3 seconds followed by a delayed recovery schedule of 10 seconds; the pre-fix replay raised `ArgumentError: recovery_schedule requires an unresolved payout`.

Acceptance:

- reduce the failure to a deterministic regression independent of lucky thread scheduling;
- preserve `PayoutSnapshot` fail-closed invariant rather than weakening it;
- live reconciliation blocking, lifecycle replay and fresh restore agree that ownership is retained, status is `reconciliation_blocked`, and superseded recovery schedule is absent;
- prefer a shared reducer/invariant if that genuinely removes the live/replay duplicate; a narrow correct replay transition fix is acceptable if extracting a new abstraction would only move lines;
- rerun focused replay/recovery tests and the concurrency campaign, then broad risk-appropriate verification;
- record the regression evidence in backlog/plan before moving on.

Implementation evidence: lifecycle replay now clears the superseded schedule on
`reconciliation_blocked`, while preserving ownership and the snapshot's
fail-closed validation. A deterministic scenario asserts live, replay and
`Coordinator.from_facts` parity; the recovery-schedule, recovery-budget,
replay-unit, high-contention, restart-recovery and durable-crash suites pass
locally.

Exit: PTZ3-005 verified and exact-main verification is no longer knowingly red for this defect.

## Phase 1 — One atomic active configuration generation

Goal: a new decision can observe only one complete configuration generation.

Acceptance:

- immutable active configuration snapshot has a revision/identity;
- policy resolution and provider opportunity evaluation for one decision derive from that same snapshot;
- apply A→B is atomic from routing readers' perspective;
- no configuration lock is held across provider I/O;
- unresolved payouts still use pinned historical semantics;
- deterministic controlled concurrency test proves A-or-B, never mixed generation;
- failures during configuration replacement cannot leave a silently mixed active state.

Prefer a coherent snapshot publication design over adding locks around unrelated methods.

Implementation evidence: `ActiveConfigurationSnapshot` is the immutable
revisioned routing read value. `ConfigurationStore#update` publishes a complete
configuration only after candidate validation and coordinated provider-catalog
and policy-registry replacement. Orchestrator preparation and resume use the
same store seam, pass the snapshot's provider definitions into evaluation, and
release the store before adapter invocation. Controlled concurrency covers
whole-generation A-or-B behavior and provider-I/O lock release; the
configuration/revision, application-service and full test suites pass locally.

Exit: PTZ3-001 verified on the current implementation checkpoint.

## Phase 2 — Fail-closed routing context

Goal: malformed routing-critical input cannot silently erase route semantics.

Acceptance:

- nil means explicit empty context;
- `RoutingContext` and valid Hash inputs are accepted/canonicalized;
- unsupported scalar/array/object forms raise typed argument/application errors;
- HTTP/application boundaries return a controlled invalid-input response;
- existing equivalent-input canonicalization and restart payload identity remain stable.

Implementation evidence: `RoutingContext.from` now accepts only nil, an
existing typed value or a Hash and rejects unsupported shapes. `PayoutIntent`
and executable operation payload construction distinguish explicit false from
absence, so malformed routing data cannot silently broaden policy/provider
eligibility. The HTTP adapter returns the existing controlled 400 response.
Deterministic unit, provider-payload, HTTP and quality suites pass, and active
SPEC-007 traceability covers the boundary regressions.

Exit: PTZ3-002 verified on the current implementation checkpoint.

## Phase 3 — Correct quality age semantics

Goal: only fresh samples contribute when age limits are configured.

Acceptance:

- age filtering is defined before score/maturity/confidence calculation;
- one fresh observation cannot refresh expired historical samples;
- bounded sample window ordering versus age filtering is explicit and deterministic;
- route/context/global fallback uses the resulting authoritative snapshots;
- replay/restart produces the same result at the same `as_of`;
- mixed-age regressions include opposite-sign old/new evidence.

Implementation evidence: routing snapshots now filter each retained sample by
the configured age limit before calculating counts, maturity, confidence and
posterior score. The bounded evidence window remains deterministic append
order, while durable evidence snapshots retain the unfiltered window for fact
validation and replay. Unit coverage reproduces the old-success/fresh-failure
counterexample; a controlled-clock scenario proves live, replay and fresh
restart parity at the same `as_of`.

Exit: PTZ3-003 verified on the current implementation checkpoint.

## Phase 4 — Portable durable timing

Goal: recovery, TTL/deadline and throughput semantics survive a new monotonic origin.

Acceptance:

- durable wall anchors or equivalent portable data are sufficient to rebase timing into the current process monotonic domain;
- old persisted monotonic values are never blindly compared to a new unrelated origin;
- restart tests deliberately create a second controlled clock with a different origin;
- recovery due/not-due, TTL/deadline precedence and throughput-window results remain equivalent within defined wall-time semantics;
- no real sleeps.

Implementation evidence: restore now treats durable wall timestamps as the
portable timing anchors and rebases monotonic references into the current
clock domain for payout creation, operation decisions, evaluations,
reconciliation evidence and throughput consumption. Recovery schedules expose
an explicit rebase operation for both deadlines. `SystemClock` now keeps origin
and readings in the same exact seconds unit. Controlled restart regressions
with a second origin prove a delayed recovery remains not due after one second,
TTL still blocks at its wall deadline, and a one-minute throughput event is not
prematurely evicted. A forged wall timestamp remains rejected; process-local
raw monotonic coordinates are not used as cross-restart authority.

Exit: PTZ3-004 verified on the current implementation checkpoint.

## Phase 5 — Comparable quality cohorts

Goal: improve deterministic smart-routing evidence quality without ML.

Required:

- currency participates in the comparable quality evidence key without moving Money authority into RoutingContext;
- define bounded fallback order across currency+route, broader route/context/global and prior;
- sparse route evidence has explicit maturity/confidence authority;
- provider-attributed terminal evidence rules remain unchanged;
- UNKNOWN/pending/recipient/downstream remain neutral;
- allocation authority remains higher priority than quality.

Evaluate the simplest acceptable design first. Per-scope maturity thresholds are acceptable if they solve the counterexample cleanly; hierarchical shrinkage is allowed only if exact, deterministic and materially clearer/better.

Implementation evidence: quality controller state is keyed by normalized
provider/currency/cohort, while `Money` remains the authority for payout
currency and `RoutingContext` remains provider-agnostic. Routing snapshots
use route → context → same-currency global → conservative prior, and legacy
unscoped (`currency: nil`) evidence is never used for a known-currency query.
Route evidence defaults to a two-sample threshold even when global evidence
uses `minimum_samples: 1`; an explicit route threshold preserves deliberate
legacy sparse behavior. Currency is persisted in quality facts and validated
against the source payout during restore. Unit, scenario, replay, restart,
corruption and full test/property/model/concurrency/fault matrices cover the
boundary.

Exit: PTZ3-101 and PTZ3-102 verified on the current implementation checkpoint.

## Phase 6 — Policy selector semantics

Goal: deterministic selection models actual narrowing, not merely number of fields.

Required:

- explicit priority remains primary authority;
- where selector B is a strict semantic subset of selector A, B may win as more specific;
- equal-priority incomparable overlapping matches are ambiguous;
- registration order permutations are invariant;
- exact amount bands are supported with currency-safe semantics;
- no generic rules DSL.

Use metamorphic permutation and boundary tests.

Implementation evidence: `PolicyRegistry` now selects the highest explicit
priority and computes maximal same-priority selectors under
`PolicySelector#strictly_narrows?`; field count is retained only as a
compatibility/diagnostic value. Equal-priority incomparable selectors remain
ambiguous. Selectors support inclusive `minimum_amount_minor` and
`maximum_amount_minor` bounds only with explicit currency, using Integer
comparisons against the payout Money amount. Focused resolution, invalid
input, exact boundary, permutation and durable definition/fingerprint tests
cover the new semantics.

Exit: PTZ3-103 verified on the current implementation checkpoint.

## Phase 7 — Configuration compiler/source-of-truth

Goal: make active configuration coherent as a system.

Required:

- one immutable revisioned active snapshot is the routing read authority;
- provider/policy active bootstrap and durable historical facts have explicit ownership;
- cross-object diagnostics classify at least valid / warning / statically invalid-unreachable cases where determinable;
- do not reject legitimate temporary absence/outage solely because a target provider is not currently feasible;
- config application/query exposes revision and diagnostics through application semantics.

Implementation evidence: `ConfigurationCompiler` validates each typed
`RoutingConfiguration` as a system and returns immutable deterministic
diagnostics. Missing targets and runtime admission loss are warnings, while
statically infeasible policies and fixed currency/route/amount incompatibility
are errors. Commands compile candidates before mutating the coordinator or
policy registry, and `ConfigurationStore` publishes only valid generations
with diagnostics attached to the revisioned snapshot. Queries expose
diagnostics and the derived `valid` / `valid_with_warnings` status. Focused
application and acceptance-traceability regressions prove warning publication,
invalid rollback and static infeasibility handling.

Exit: PTZ3-104 verified on the current implementation checkpoint.

## Phase 8 — Recovery objective

Goal: make fallback strategy product-capable without weakening safety.

Keep `allocation_constrained` default. Implement a reliability-first/equivalent mode only after defining a safe lexicographic boundary:

`economic safety -> hard eligibility -> admission -> recovery legality/budgets -> reliability/quality -> cost/latency -> deterministic tie break`.

Primary allocation accounting must not be advanced or rewritten by recovery optimization.

If implementation evidence shows a second mode adds complexity without generic case value, record that finding and keep the typed seam; this phase then exits through evidence, not feature-count pressure.

Implementation evidence: the current recovery path first applies the legal
candidate boundary (including attempted-provider exclusion), then reuses the
exact allocation authority. `ConstrainedOptimizer` applies quality/ranking
only inside that authority's tie set, so recovery cannot trade away allocation
obligations. No second reliability objective is justified before an
authoritative product objective exists; adding one now would duplicate the
existing optimizer or weaken the required precedence. The typed
`allocation_constrained` mode remains explicit, durable and explainable, with a
deterministic regression proving the ordering.

Exit: PTZ3-105 verified by evidence-gated scope decision on the current implementation checkpoint.

## Phase 9 — Semantic architecture convergence

Goal: reduce sources of truth, not class size.

Candidates:

- active configuration snapshot owner;
- shared recovery schedule/expiry/rebase semantics between live and restore;
- any remaining duplicate live/restore transition found during previous phases.

Coordinator remains the atomic transaction facade. Do not create restorer/validator objects merely to shorten the file.

Implementation evidence: active configuration and portable timing retain their
single owners from the earlier phases. The remaining duplicated primary versus
recovery allocation branch is now one pure `AllocationAuthority` seam shared by
live `DecisionEngine` and durable `DecisionTraceValidator`. It keeps recovery
attempt exclusion and primary allocation accounting explicit, while the
Coordinator remains the atomic facade. Focused path-parity and existing
decision/replay regressions cover both consumers.

Exit: PTZ3-106 verified on the current implementation checkpoint.

## Phase 10 — Product/demo/query parity

Goal: demonstrate the engine's actual control plane through thin adapters.

Consider:

- active configuration/revision query and controlled apply path;
- due-recovery query;
- dimension-safe analytics query parameters;
- typed no-policy/ambiguous-policy application errors;
- demo showing configured shares/capabilities/recovery rather than hardcoded behavior.

Do not guess the official judge API.

Implementation evidence: application queries expose the active configuration
revision/diagnostics, due-work and dimension-safe analytics already present in
the canonical core. The HTTP adapter now exposes those values through
read-only `/v1/configuration`, `/v1/recovery/due-work` and metric/group/filter
query parameters on `/v1/analytics`, while preserving the legacy full response
and keeping routing decisions in the application/core. Controlled HTTP,
analytics and recovery tests cover the transport mapping and exact due-work
identity without introducing a speculative config-write schema.

Exit: PTZ3-107 verified on the current implementation checkpoint.

## Phase 11 — Context health experiment

Goal: determine whether provider-global fast health is materially wrong for multi-route providers.

The deterministic scenario used one provider supporting card and bank transfer.
After one provider-attributed card failure, the provider-global implementation
would have quarantined bank-transfer traffic as well, which is a material
future-admission error. The implementation therefore adds a bounded typed
health cohort over canonical payment_method/rail/destination_kind only;
labels remain outside this fast-health key. Empty/unknown route context keeps
the historical provider-global state, so manual signals and legacy facts keep
their semantics. Provider observation health facts carry the canonical cohort,
evaluation/restoration validate it, and operation probe reservations use the
same route key.

Focused live, replay, restart and legacy-global health suites pass. The
route-scoped acceptance additionally proves that card quarantine does not
quarantine bank transfer and that restored health plus the next bank-transfer
assignment match live state.

Exit: PTZ3-108 verified on the current implementation checkpoint.

## Phase 12 — Larger-history evidence

After semantic correctness is green, measure at multiple history sizes beyond 10k where practical. Record workload shape, facts, restore time, analytics/query time, bounded audit-page time, memory after GC and routing throughput.

Evidence run on the current implementation used the existing
`RubyRouting::Benchmarking::HistoryProfile` immediate-success, two-provider
workload. Sequential results were: 1,000 payouts / 14,002 facts / lifecycle
4.47s / analytics 0.17s / restore 3.85s / heap +36.8MB; 2,500 / 35,002 /
11.46s / 0.76s / 9.91s / +92.0MB; 5,000 / 70,002 / 27.60s / 1.13s /
20.48s / +183.8MB; and 12,500 / 175,002 / 93.42s / 2.37s / 47.30s /
+458.8MB. At 12,500, the bounded audit page took 1.85ms for its 101
repeated page queries and the filtered page 1.25ms. The concurrent
12,500/4-worker profile produced 149.7 payouts/s and the same fact density.
The curve is now measured beyond 10k; it does not by itself authorize a
database, checkpoint or indexing subsystem, so no speculative performance
rewrite was made.

Only optimize a measured bottleneck. Do not introduce a database/checkpoint subsystem because a hypothetical future scale might need it.

## Phase 13 — Independent skeptical closure

This phase is deliberately not a checklist confirmation.

Status: VERSION_COMPLETE. The known P0/P1 matrix and PTZ3-109 measurements
passed. Fresh code-level discovery found and resolved forty-five material
cross-layer gaps (PTZ3-111 through PTZ3-155), including the final strict HTTP
normalizer identity boundary. The independent discovery pass found no further
material locally solvable P0/P1 finding on the candidate checkpoint. Final
exact-head verification and authenticated CI then passed, so no external
blocker remains.

Entry condition: all known P0/P1 items appear verified.

Then ignore their completion statuses and perform a fresh adversarial discovery pass from code. Challenge at minimum:

- configuration apply versus submit/resume/provider-runtime races;
- malformed route/config/provider inputs;
- mixed-age, mixed-currency and sparse quality evidence;
- process restart with changed clock origin and changed active config;
- overlapping policy selectors and amount boundaries;
- recovery schedule versus TTL/deadline/provider capabilities;
- duplicate/delayed/out-of-order observations across restart;
- live versus restore/replay semantic equivalence;
- API/query adapters versus canonical application logic;
- full-history paths and scale assumptions.

Rules:

- finding a material locally solvable defect returns status to ACTIVE and adds a backlog item;
- finishing the known backlog cannot transition directly to `VERSION_COMPLETE`;
- a green suite is evidence but not proof of discovery completeness;
- closure requires exact-HEAD full verification and current CI after the final material code change;
- documentation is reconciled only after the skeptical pass, not used to suppress findings.

Fresh discovery findings resolved on the current working checkpoint:

- supplied `ConfigurationStore` construction could leave an empty/stale
  policy registry and an unregistered provider catalog; the active generation
  now seeds/validates the registry and bootstraps provider history
  (`PTZ3-111`);
- repeated HTTP query keys silently selected the last wire value; shared
  query parsing now rejects duplicates (`PTZ3-112`);
- future-dated quality evidence could make an as-of snapshot reject its own
  latest timestamp; per-sample as-of filtering now excludes future evidence
  from counts and latest reporting (`PTZ3-113`);
- post-commit provider replacement failure could leave catalog and active
  snapshot on different generations; application mutation now compensates
  provider/registry state and escalates rollback failure (`PTZ3-114`).
- policy-level currency was omitted from same-priority selector subsumption;
  a currency-only and method-only overlap could resolve as an ordered winner;
  effective policy resolution now includes currency and preserves ambiguity
  (`PTZ3-115`).
- quality normalization silently collapsed malformed explicit routing context
  into provider-global evidence; the boundary now delegates to canonical
  fail-closed `RoutingContext.from` while retaining legacy label-only context
  compatibility (`PTZ3-116`).
- provider-global health quarantine could be bypassed by a known route-context
  lookup returning a fresh scoped healthy default; global non-healthy health is
  now a conservative safety ceiling while route-specific failures remain
  isolated, and the same ceiling is enforced before scoped exposure reservation
  (`PTZ3-117`).
- typed ambiguous-policy identity omitted an independent policy-level currency
  constraint; resolution projections now retain that currency so the visible
  ambiguity remains actionable (`PTZ3-118`).
- active configuration revision was queryable only as current control-plane
  state; routed evaluation/decision facts and their explanation/public audit
  projections did not identify the immutable generation used for a decision;
  the canonical orchestrator path now carries the revision as trace metadata
  and durable shape validation rejects malformed values (`PTZ3-119`).
- the HTTP JSON boundary accepted duplicate object keys and silently used the
  last wire value for routing-critical fields; request/webhook parsing now
  rejects ambiguous JSON before domain mutation (`PTZ3-120`).
- a caller retaining a supplied `ConfigurationStore` could publish a snapshot
  without the coordinated registry/catalog mutation, allowing an unregistered
  provider route and making fresh restore fail; store mutation is now private
  to the application command publication path (`PTZ3-121`).
- quality replay/application queries omitted the injected as-of time and
  currency/route cohort, so a valid fresh cohort could be displayed as a
  neutral prior; projections now use explicit dimensional filters and current
  time by default (`PTZ3-122`).
- route-specific provider quarantine affected admission but the global-only
  operator query displayed healthy; health projections and application/HTTP
  queries now expose an explicit bounded route context without pooling global
  state (`PTZ3-123`).
- a global degraded provider remained exposed during evaluation but route
  reservation rejected every global non-healthy state, and a route probe could
  miss the global probe budget; one effective health state now preserves
  degraded traffic, blocks quarantine, and accounts global probing
  (`PTZ3-124`).
- the permissive raw-context parser was also used for explicit durable route
  identity; an unknown-only key in `intent_registered.routing_context` could
  restore as an empty route and broaden eligibility. Explicit canonical route
  values now use a strict known-key boundary while raw provider metadata stays
  permissive (`PTZ3-125`).
- public quality/health route filters and provider-operation payloads repeated
  that permissive explicit-hash path, and quality label keys stringified
  arbitrary objects. The canonical parser is now strict by default; only
  explicitly marked raw-context paths remain permissive, and legacy label keys
  require String/Symbol values (`PTZ3-126`).
- HTTP payout submission did not pass an explicit `routing_context` into the
  typed intent and payout responses did not expose the normalized route
  identity, so the public product surface could not exercise the same route
  capability semantics as the Ruby API (`PTZ3-127`).
- HTTP policy-resolution failures collapsed the canonical no-match and
  ambiguity values into one generic invalid-request response, hiding the
  corrective operator action (`PTZ3-128`).
- the public low-level Coordinator catalog could be changed after application
  bootstrap while the active snapshot remained old, allowing routing through a
  provider absent from current durable history and allowing resume expiry
  before drift was noticed (`PTZ3-129`). Application submit/resume and config
  queries now fail closed on catalog drift, with a stable HTTP boundary and
  no payout mutation regression. The guard compares the immutable provider
  definition only; availability, capacity, enabled, health and throughput flags
  remain operational runtime evidence, and live evaluation overlays their
  current atomic values onto the active definition. This preserves the
established disabled-for-new-routes versus same-provider recovery contract.
- application resume used the active configuration snapshot for its guarded
  state transition but omitted that generation from the durable restart
  `decision_committed` fact (`PTZ3-130`). The canonical Orchestrator now passes
  the snapshot revision through `Coordinator#resume_operation`; direct
  low-level callers may continue to omit it for compatibility, while the
  application path has the same revision traceability as live assignment and
resolution.
- route-scoped HTTP health and quality queries silently ignored unknown or
  alias parameters, so a typo could fall back to a provider-global view
  (`PTZ3-131`). The transport boundary now rejects unsupported routing query
  keys before any projection is returned; only canonical route dimensions are
accepted.
- provider application queries returned active-snapshot runtime flags after a
  direct runtime-only Coordinator update (`PTZ3-132`). The provider projection
  now validates the static definition and overlays current atomic runtime
  values, keeping control-plane configuration immutable while exposing actual
  admission state.
- durable fact and batch envelopes were parsed with default JSON duplicate-key
  behavior, so an ambiguous key could be collapsed before checksum/schema
  validation (`PTZ3-133`). Fact decoding and FileJournal record dispatch now
  reject duplicate object keys before interpreting durable input; codec and
  journal regressions cover both fact and batch records.
- application analytics, due-work, audit, configuration and provider queries
  silently ignored unsupported parameters, so a typo could broaden a product
  result (`PTZ3-134`). Each endpoint now has an explicit accepted-key boundary;
  the shared regression covers all five surfaces while route-scoped health and
  quality keep their existing strict canonical-dimension checks.
- route and currency filter validation was delegated to a projection that can
  be empty, so malformed HTTP values could return `200` when no providers were
  registered (`PTZ3-135`). The adapter now canonicalizes the route and
  validates currency before projection work, with an empty-catalog regression.
- routes without query semantics silently ignored query parameters, allowing
  an operator typo on health, payout, explanation, resume or webhook requests
  to look successful (`PTZ3-136`). The adapter now rejects those parameters
  before domain work, with one deterministic regression covering every route.
- application-facing policy registry access exposed a mutable compatibility
  object that could diverge from the active configuration snapshot (`PTZ3-137`).
  The application now exposes a read-only registry view, seals the supplied
  registry after bootstrap, and reserves mutation for coordinated commands;
  direct-mutation and command-publication regressions cover the seam.
- two independent application services could share one supplied registry,
  allowing one active generation to mutate the other's compatibility view
  (`PTZ3-138`). The registry is now exclusively bound to one successfully
  constructed application service, with a deterministic bootstrap regression.
- registry binding occurred before application construction completed, so a
  failed provider-adapter bootstrap could permanently capture a supplied
  registry (`PTZ3-139`). Binding now occurs only after successful construction,
  with deterministic retry-after-failure coverage.
- configuration compilation treated selector and hard amount bounds as
  independent, allowing a policy with no satisfiable payout range
  (`PTZ3-140`). Static feasibility now checks their exact interval
  intersection, and currency-fixed provider diagnostics use the same bounds.
- the query compatibility registry was a bootstrap clone and became stale
  after coordinated policy publication (`PTZ3-141`). Queries now read the
  application-owned registry through a read-only view, with post-publication
  parity coverage.
- the payout HTTP command ignored unknown top-level JSON fields, so a typo in
  `routing_context` could silently broaden route semantics (`PTZ3-142`). The
  adapter now rejects unsupported request fields before creating an intent,
  while preserving the nested provider-specific context boundary.
- the orchestrator retained a bootstrap clone of the supplied policy registry,
  so its compatibility view went stale after coordinated publication
  (`PTZ3-143`). It now shares the application-owned registry while exposing
  only the existing read-only view.
- the shared registry itself could become visible before the atomic
  `ConfigurationStore` snapshot was published (`PTZ3-144`). Application
  compatibility views now read the immutable active snapshot under its lock,
  so the command-owned mutation/index seam cannot expose a partial generation.
- the bodyless HTTP resume route silently discarded non-empty request bodies
  (`PTZ3-145`). It now consumes and rejects them before payout lookup, keeping
  the command boundary explicit.
- a `ProviderOperationRequest` silently dropped a separately supplied contract
  when an executable payload was provided (`PTZ3-146`). The constructor now
  attaches the contract to the immutable payload or rejects a conflict.
- a provider request silently ignored legacy destination/context/route fields
  beside an executable payload (`PTZ3-147`). The constructor now rejects that
  mixed source rather than pretending both interpretations were accepted.
- capacity amount usage crossed currencies when an active provider budget was
  changed while an older reservation remained in flight (`PTZ3-148`). Admission
  and replay now select per-currency usage for the current capacity budget.
- a malformed capacity release could decrement the in-flight slot before
  detecting wrong-currency, oversized or duplicate usage (`PTZ3-149`). Live
  admission and replay now preflight both slot and currency amount underflow
  before mutating either counter.
- a rejected second application could synchronize provider history before
  discovering an already-owned policy registry (`PTZ3-150`). Service bootstrap
  now reserves registry ownership before provider synchronization and releases
  that reservation on failure; the rejected coordinator remains unchanged.
- policy, executable operation and recovery identities could coerce arbitrary
  values into strings (`PTZ3-151`). Their public normalization now rejects
  non-String/Symbol values, while raw provider metadata remains permissive.
- adjacent core routing/state identities remained inconsistent with that rule
  (`PTZ3-152`). Shared strict normalization now protects allocation,
  lifecycle, durable facts, snapshots, health/quality and coordinator lookup
  boundaries without changing raw provider metadata.
- provider capacity currency, supported currencies and capability version
  accepted arbitrary objects via `to_s` (`PTZ3-153`). These typed
  configuration scalars now reject non-String/Symbol values before
  canonicalization, preventing malformed capability/admission identities from
  colliding with valid configuration.
- provider exclusion reasons accepted arbitrary objects via `to_s`
  (`PTZ3-154`). Typed admission diagnostics now reject non-String/Symbol
  values before normalization, while raw provider payload metadata remains
  schema-free.
- HTTP provider-normalizer mapping keys accepted arbitrary provider identity
  objects via `to_s` (`PTZ3-155`). The API configuration now rejects
  non-String/Symbol keys before executable normalizer bootstrap.

## Verification matrix

Risk-appropriate commands include:

- `bundle check`
- `bundle exec rake test`
- `bundle exec rake property`
- `bundle exec rake model`
- `bundle exec rake concurrency`
- `bundle exec rake fault`
- `bundle exec rake benchmark`
- relevant load/history campaigns
- focused fake-clock/restart/configuration tests
- acceptance traceability for SPEC-007
- CI on exact candidate HEAD.

Every randomized failure must preserve a reproducible seed/trace. Material bugs receive deterministic regressions.

Fresh candidate verification executed after the independent discovery pass:

- `bundle check` passed;
- `bundle exec rake test` passed: 624 runs, 10,894 assertions, 0 failures,
  0 errors, 0 skips;
- `bundle exec rake property` passed: 4 runs, 1,210 assertions;
- `bundle exec rake model` passed: 3 runs, 2,941 assertions;
- `bundle exec rake concurrency` passed: 14 runs, 948 assertions;
- `bundle exec rake fault` passed: 333 runs, 3,958 assertions;
- acceptance traceability passed: 1 run, 729 assertions;
- product evidence passed on CRuby 4.0.6: benchmark, 10k lifecycle load
  (140,002 facts), deterministic degradation (`seed 20260829`), bounded
  history and concurrent history profile, and the simulated safe-fallback
  demo;
- authenticated GitHub Actions run `33474999166` for
  `f59bdd60c268a3982e32ad45353bf4c292f14153` completed successfully; both
  `Fast Ruby verification` and `Bounded product evidence` were green.

Completion report:

- exact product revision: `f59bdd60c268a3982e32ad45353bf4c292f14153`;
- SPEC-007 acceptance traceability: 1 run, 729 assertions;
- correctness matrix: test 624/10,894, property 4/1,210, model 3/2,941,
  concurrency 14/948, fault 333/3,958, with zero failures/errors/skips;
- product evidence: CRuby 4.0.6 benchmark, 10k lifecycle load with 140,002
  facts, deterministic degradation seed `20260829`, bounded and concurrent
  history profiles, and the simulated fallback demo;
- skeptical discovery areas A–I were examined from production code and
  reachable adapters; PTZ3-111 through PTZ3-155 were resolved and no further
  material locally solvable P0/P1 was found;
- CI run `33474999166` was authenticated through the configured credential
  helper and both workflow jobs concluded `success`;
- no external blocker or authoritative TZ exists.

## Rolling Next Actions

1. Preserve the v0.3.3 baseline and switch to `docs/TZ_RECONCILIATION.md`
   immediately when the authoritative TZ arrives.
2. Reopen this plan only for a new material defect, changed authority or
   evidence that falsifies the current completion report.

## Stop policy

Do not stop after a slice, commit, phase, green CI or exhausted initial backlog.

Stop only when:

1. Phase 13 completes with no remaining locally solvable P0/P1 finding and exact-HEAD evidence; or
2. every remaining required path is genuinely external and no independent case-relevant work exists; or
3. the authoritative TZ arrives, then immediately execute `docs/TZ_RECONCILIATION.md`.
