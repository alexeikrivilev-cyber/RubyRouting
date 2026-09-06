# Pre-TZ Backlog — v0.3.2 Semantic Control Plane & Recovery Readiness

This is the active concise execution queue for SPEC-006. v0.3.1 / SPEC-005 remains a completed historical checkpoint and must not be reopened unless new evidence proves a regression.

Priority rule: P0 before P1 unless a P1 slice directly unblocks a P0 acceptance condition. After each verified slice, update status and immediately continue to the next highest-value unblocked item.

## P0 — Must close before v0.3.2 completion

### PTZ2-001 — Canonical typed RoutingContext

Problem: provider execution understands payment method/rail/context, while routing-critical interpretation still relies too heavily on free-form hashes/labels.

Done when:

- one immutable generic route-context value owns canonical method/rail/destination-kind/normalized segment semantics;
- economic amount/currency remain consistent with `PayoutIntent`/`Money`;
- semantically equivalent inputs canonicalize identically;
- provider-operation payload identity/restart behavior remains stable;
- explanation can expose safe route dimensions without copying recipient payload.

Status: VERIFIED on the exact current working tree — immutable canonical `RoutingContext` is owned by `PayoutIntent`, consumed by policy/provider/quality paths, serialized in the executable provider payload and intent facts, and preserved across restart/replay. Focused, full, broad and traceability evidence is recorded in the active ExecPlan.

### PTZ2-002 — Provider route-capability matching

Problem: `ProviderOpportunity` does not yet explicitly express support for the same generic route dimensions used by payout execution.

Done when:

- configured supported methods/rails/destination kinds participate in functional eligibility;
- unsupported dimensions produce typed functional exclusions;
- opportunity-cohort accounting excludes providers that could never serve the route;
- no PSP-specific schema enters generic core.

Status: VERIFIED on exact current working tree — typed method/rail/destination capability matching is a hard functional gate, emits deterministic `unsupported_*` exclusions, shapes the functional allocation cohort, round-trips through provider catalog durable definitions, and is covered by explanation/restart evidence. See the active ExecPlan for exact verification seeds.

### PTZ2-003 — Deterministic PolicyResolver

Problem: automatic policy selection can depend on registration order when multiple same-scope/currency policies match.

Done when:

- policy selectors use typed route context;
- precedence/specificity/priority is explicit and deterministic;
- registration-order permutations do not change a valid winner;
- no-match is visible and typed;
- unresolved equal-precedence matches produce visible ambiguity rather than an arbitrary winner;
- selected immutable policy identity remains pinned to payout history.

Status: VERIFIED on exact current working tree — immutable typed selectors use canonical route context, precedence is explicit as `[priority, specificity]`, no-match and equal-precedence ambiguity are typed, registration order is not business semantics, explicit mismatches fail before state registration, and selector identity/fingerprint survive durable restart. Focused, full, broad and traceability evidence is recorded in the active ExecPlan.

### PTZ2-004 — Active configuration boundary and DTOs

Problem: the engine is configurable through Ruby objects but the product does not yet have one explicit application-level configuration model/control-plane boundary.

Done when:

- typed configuration values represent policy definitions/selectors and provider definitions/capabilities/admission settings;
- validation delegates to domain semantics rather than duplicating them;
- startup/current configuration is explicitly separate from durable historical payout facts;
- unresolved payout restart remains correct across active config changes;
- application commands can apply/query configuration;
- any HTTP mapping remains thin and optional before official TZ.

Status: VERIFIED on the current working tree — `Application::RoutingConfiguration` is an immutable, canonically serialized value over existing typed policy/provider definitions; `Commands#apply_configuration` validates the complete replacement before delegating provider state and active policy replacement; `Queries#configuration` exposes the same active snapshot. Active config is separate from durable payout policy/history, and unresolved pinned routing remains executable after active provider/policy replacement.

### PTZ2-005 — Recovery schedule and due-work semantics

Problem: recovery knows the next legal action but the domain does not fully define when that action becomes due; external callers can repeatedly call `resume` without an explicit backoff contract.

Done when:

- deterministic recovery delay/backoff semantics use injected time;
- unresolved state/explanation exposes `next_action_at` or equivalent;
- early repeated resume cannot bypass the configured schedule;
- TTL/deadline interaction is explicit and safety-first;
- due recovery/reconciliation work is queryable as of a supplied time;
- restart/replay preserves equivalent due-work semantics;
- tests use fake clocks, never correctness sleeps.

Status: VERIFIED on the current exact working tree — `RecoveryPolicy` exposes deterministic exact-integer initial/backoff/cap semantics, unresolved observations persist an immutable operation-linked schedule, early resume is blocked by wall and monotonic due checks, TTL/deadline expiry produces reconciliation work first, and application/coordinator queries expose due work without a queue. Focused, full and restart/replay evidence is recorded in the active ExecPlan.

### PTZ2-006 — SPEC-006 executable traceability and fresh closure

Done when:

- all mandatory SPEC-006 scenarios have stable acceptance IDs mapped to executable tests;
- traceability test verifies references remain live;
- full deterministic/property/model/concurrency/fault/restart evidence is green on exact candidate HEAD;
- docs agree with implementation;
- no locally solvable P0/P1 SPEC-006 defect remains.

Status: VERIFIED — fresh SPEC-006 closure/red-team passed on the exact pushed
pre-TZ revision. All mandatory acceptance IDs are live, the full deterministic
and seeded verification matrix is green, active documentation matches the
implementation, and no locally solvable P0/P1 remains. Remaining work is
optional P2 or the authoritative-TZ reconciliation.

## P1 — High-value semantic/product hardening

### PTZ2-101 — Route-aware quality cohorts

Use canonical route context for bounded comparable quality cohorts. Preserve mature route -> mature broader -> conservative prior fallback. Avoid uncontrolled cardinality.

Status: VERIFIED on the exact current working tree — quality records provider-attributed evidence in bounded typed route cohorts keyed only by payment method, rail and destination kind; labels remain a separate broader context cohort, and mature route evidence precedes context/global/prior fallback. Route identity is durable and replayable.

### PTZ2-102 — Time-stale quality evidence

Add deterministic age-based staleness independent of the bounded observation-count window. Old evidence must be capable of losing routing authority without requiring N newer observations.

Status: VERIFIED on the exact current working tree — quality evidence carries an injected observation timestamp, exact Rational age and configured max age; maturity and staleness are independent, the exact allowed-age boundary remains authoritative, stale/unknown-age mature evidence loses routing authority, and restart/replay preserves the evidence timestamp.

### PTZ2-103 — Canonical interaction telemetry into fast health

Measure provider-interaction operational evidence on the canonical application path using injected monotonic time and map it into existing typed health signals. Ambiguous transport remains economically UNKNOWN.

Status: VERIFIED on the current working tree — the canonical `Application::Orchestrator` path measures exact injected monotonic duration for initiate/resolve, persists it on immutable provider observations, maps only provider-attributable slow observations above an explicit millisecond threshold into `latency_pressure`, preserves transport/service signal precedence, and keeps recipient/downstream/unknown-attribution outcomes neutral. Observation duration and health policy round-trip through durable restore/replay; focused and restart evidence is recorded in the active ExecPlan.

### PTZ2-104 — Explicit recovery-objective seam

Current SPEC-005 recovery selection remains the default `allocation_constrained` semantic. Introduce only the minimum typed seam needed to make recovery optimization objective explicit and safely adaptable to the official TZ. Reliability-first/hybrid modes are optional unless evidence shows clear generic value.

Status: VERIFIED on the exact current working tree — `RoutingPolicy` carries an immutable typed `RecoveryObjective`, the current and only pre-TZ mode is explicitly named `allocation_constrained`, and `RecoverySelection` dispatches through that objective only after recovery legality has produced candidates. The default remains omitted from durable policy serialization/fingerprints for compatibility with historical policy facts; unsupported modes fail at typed construction, and recovery exclusion/primary-ledger semantics remain unchanged.

### PTZ2-105 — Eliminate duplicate prepared-evaluation semantics

Remove or redirect the standalone `DecisionEngine` compatibility computation so eligibility/runtime-feasibility rules have one prepared-evaluation builder/source of truth.

Status: VERIFIED on the current working tree — `DecisionEvaluator.prepare` is the shared pure builder for eligibility, allocation-measure exclusions and runtime feasibility; the live evaluator and standalone `DecisionEngine` compatibility path both consume that contract. The immutable production evaluation path remains the source for atomic proposal construction, while direct callers retain compatibility without a second eligibility/runtime implementation.

### PTZ2-106 — Continue shared live/restore transition semantics

Select the highest-value remaining duplicated business rule between live and restore paths and converge it through shared pure reducers/invariants. Do not add a restorer merely to move lines.

Status: VERIFIED on the exact current working tree — `LifecycleLedger::OutcomeReduction` is the pure shared phase/status/release reducer; live commit, observation restore, replay and Analytics now consume the same outcome status semantics. Ownership mutation, durable fact order and provider I/O remain in their existing owners, and no restore-only class was added. Focused and broad regression evidence is recorded in the active ExecPlan.

### PTZ2-107 — Admission semantic cleanup

Resolve the meaning of concurrent `max_slots` versus `max_count`. If both remain, prove distinct semantics. If one is redundant, simplify without weakening existing capacity/throughput behavior.

Status: VERIFIED on the exact current working tree — actual code had one payout increment/release both `slots` and `count` together, with no independent time or quantity semantics; `ThroughputBudget` already owns time-window counts. `CapacityBudget#concurrent_limit` now defines the single effective in-flight bound as the stricter configured `max_slots`/legacy `max_count` cap, `CapacityUsage` and replay use one in-flight counter, and snapshots fail closed when compatibility counters diverge. Existing min-limit behavior, durable budget shape, amount exposure and throughput behavior are preserved.

### PTZ2-108 — Dimension-safe analytics query surface

Expose filtering/grouping by compatible policy/epoch/scope/measure/currency/provider/cohort dimensions through application queries. Invalid cross-unit aggregation must remain impossible.

Status: VERIFIED on the exact current working tree — `Analytics#query` is a typed read-only query over the canonical dimensioned measure maps; application `Queries#analytics_query` is a thin projection facade. Closed metric/filter/group dimensions are normalized, policy/epoch/scope/window/cohort/measure/currency/provider identity remains visible in the query contract, and varying ungrouped dimensions are rejected before addition so count/volume/currency values cannot be silently mixed. Focused and broad evidence is recorded in the active ExecPlan.

### PTZ2-109 — Product configuration/API demo path

After PTZ2-004 is stable, expose enough configuration through CLI/HTTP/demo to demonstrate that shares, provider capabilities and recovery settings are genuinely configurable without putting routing logic in the transport layer.

Status: VERIFIED on the exact current working tree — the deterministic demo now constructs or accepts one typed `Application::RoutingConfiguration`, applies it through `Service#apply_configuration`, resolves the configured policy and executes configured provider opportunities. Custom route capability, capacity and recovery settings are exercised without a demo-specific routing algorithm; the Rack adapter remains a thin transport boundary pending any authoritative HTTP schema.

### PTZ2-110 — Bounded/indexable audit query seam

Current public audit output is paginated but the underlying query scans all facts. Introduce a bounded/indexable fact-query abstraction only if current history profiling or implementation simplicity justifies it; do not add a database solely for this item.

Status: VERIFIED on the exact current working tree — `FactStore` maintains append-only payout/type indexes, exposes an immutable bounded `FactPage`, and preserves sequence order across initial restore, committed append and staged transaction reads. `Application::Queries#audit_facts_page` and the HTTP audit endpoint consume the page directly, so pagination no longer materializes a filtered full-history copy. The bounded history profile measures public-page and filtered-page costs alongside lifecycle/analytics/restore; no database or new routing semantics were introduced.

## P2 — Optional only after required P0/P1 work

### PTZ2-201 — Context-scoped health

Consider provider+route operational health only if concrete scenarios show provider-global health incorrectly suppresses healthy rails/methods and cardinality remains bounded.

### PTZ2-202 — Additional UI/dashboard polish

Only after typed configuration, due recovery and filtered analytics are complete. UI must remain a projection/control adapter over the canonical application layer.

### PTZ2-203 — Adaptive/statistical exploration

Do not implement before the official scoring objective is known and deterministic quality is demonstrably insufficient. Any future exploration must remain bounded by safety/allocation constraints.

## Explicit non-priorities

Do not sink major effort into:

- deeper FileJournal corruption taxonomies absent a discovered correctness defect;
- more defensive restore validators for breadth alone;
- microservices/distributed architecture;
- Rails/ORM/queue infrastructure without authoritative need;
- brand-specific PSP adapters before official contracts;
- unsupported production-scale claims;
- ML/bandits for presentation value;
- cosmetic Coordinator/restorer rewrites.

## Historical checkpoint

v0.3.1 / SPEC-005 is complete at baseline revision `01c00f2f258a82fcf6e3b2ee843947a68ba62ed1`. It closed provider-operation payload realism, dimensional analytics, tolerance/recovery selection semantics, confidence-aware bounded quality, richer health signals, prepared evaluation, first live/restore shared seam, explainability/public-audit safety, active traceability and bounded performance evidence.

SPEC-006 extends that baseline; it does not invalidate it.

## When the official TZ arrives

Freeze speculative expansion immediately, ingest the full authoritative text, execute `docs/TZ_RECONCILIATION.md`, classify every requirement against SPEC-006/SPEC-005 as `CONFIRMED / CHANGED / REMOVED / NEW / AMBIGUOUS`, and reorder work around official compliance/scoring.
