# SPEC-006 — Pre-TZ Semantic Control Plane & Recovery Readiness

Status: ACTIVE pre-TZ specification supplement.

SPEC-006 starts after the completed v0.3.1 / SPEC-005 checkpoint. It preserves every compatible safety, allocation, provider-operation, analytics, durability and verification guarantee already proven by SPEC-005 and inherited specifications.

The purpose of this version is not to rebuild the financial kernel. It is to close the remaining generic product-semantic gaps around **what route a payout belongs to, which policy applies, when unresolved work becomes due, and how routing evidence is segmented and operated** before the authoritative Hack.Genesis TZ arrives.

Where SPEC-006 is more specific, it is authoritative before the official TZ.

## 1. Objective

RubyRouting SHALL evolve from a strong routing kernel with a programmable configuration surface into a coherent generic smart payout-routing product whose semantic control plane is explicit and deterministic.

The product SHALL enter TZ reconciliation with:

- one typed routing context shared by policy resolution, provider eligibility, quality segmentation and explainability;
- explicit generic provider support for payout method/rail/destination dimensions where applicable;
- deterministic, explainable policy resolution with visible ambiguity instead of registration-order side effects;
- domain-level recovery scheduling semantics for unresolved payout operations without committing to a queue/framework;
- a queryable notion of due recovery/reconciliation work;
- quality evidence that handles both sample uncertainty and time staleness;
- operational telemetry capable of producing provider degradation evidence from the canonical interaction path;
- a clear boundary between durable payout history and active routing configuration;
- a product-facing configuration model suitable for later HTTP/judge mapping;
- continued convergence toward one routing evaluation and shared live/restore transition semantics;
- filtered dimension-safe analytics suitable for an operator/demo surface.

The expected official-TZ delta after this work SHOULD primarily concern exact schemas, formulas, numeric limits, scoring and runtime integration rather than missing generic payout-routing mechanisms.

## 2. Protected invariants

No SPEC-006 implementation may weaken:

1. one payout submission = one economic intent;
2. at most one unresolved money-moving economic owner per payout;
3. ambiguous-after-possible-send remains `UNKNOWN` unless provider semantics prove a stronger state;
4. `UNKNOWN` retains ownership and blocks unsafe cross-provider fallback;
5. same-provider resolution/retry is distinct from fresh fallback;
6. provider-local idempotency is not cross-provider idempotency;
7. provider I/O remains outside the atomic correctness boundary;
8. hard economic safety, functional eligibility and operational admission precede allocation/optimization;
9. primary assignment, recovery attempts and settlement remain separate accounting views under current `primary_assignment` semantics;
10. exact Integer/Rational arithmetic remains the financial correctness basis;
11. current replay/restart/fact integrity remains protected;
12. API/demo/configuration layers may not implement an alternate provider-selection algorithm.

## 3. Typed routing context

The current generic payout context SHALL become an explicit routing-semantic boundary rather than relying primarily on arbitrary labels.

Introduce a typed immutable routing context or equivalent value capable of representing generic route-relevant dimensions such as:

- currency and amount from the economic intent;
- payment method;
- rail;
- destination kind/type where relevant;
- optional normalized segment/labels;
- other generic dimensions only when they are demonstrably useful and remain provider-agnostic.

The exact class/file layout is intentionally not prescribed.

Requirements:

- raw arbitrary context may remain available as provider-operation metadata, but routing-critical dimensions SHALL have canonical typed access;
- normalization SHALL be deterministic;
- semantically equivalent input SHALL produce equivalent route context;
- the context SHALL be immutable and safe to persist/explain;
- PSP-specific recipient/request schema MUST remain outside the core.

## 4. Provider route capabilities

`ProviderOpportunity` or its successor SHALL be able to express generic route compatibility beyond currency and free-form labels.

At minimum the architecture SHALL support explicit generic matching for the route dimensions that the product itself exposes, such as:

- supported payment methods;
- supported rails;
- supported destination kinds where applicable;
- existing currency and amount boundaries;
- existing hard policy constraints and operational admission.

A provider MUST NOT be considered functionally eligible for a route dimension it explicitly does not support.

The design SHALL avoid hardcoding one provider brand or PSP request schema.

## 5. Deterministic policy resolution

Policy resolution SHALL become a first-class deterministic decision, not an incidental “latest registered compatible policy wins” behavior.

The resolver SHALL support an explicit precedence model that can be explained and tested. A reasonable generic ordering is:

1. explicitly requested/pinned policy identity when valid;
2. scope compatibility;
3. route-context selectors such as currency/method/rail/segment as configured;
4. explicit policy priority and/or deterministic specificity;
5. unique winner requirement.

Requirements:

- registration order SHALL NOT silently change business routing when competing policy definitions are otherwise equivalent;
- no match SHALL be a typed visible result/error;
- unresolved equal-precedence multiple matches SHALL be a typed ambiguity rather than a hidden arbitrary winner;
- payout execution SHALL pin the chosen immutable policy identity/fingerprint as it does today;
- policy resolution evidence SHOULD be available to decision explanation/audit without exposing sensitive recipient data.

Do not overdesign a general rules language before the authoritative TZ. Prefer a small typed selector model that can be extended or mapped later.

## 6. Active configuration boundary

The product SHALL explicitly distinguish:

- durable payout/history facts needed for replay, audit and unresolved continuation;
- active routing configuration used to route new payouts.

Before the official TZ, a generic default is acceptable in which active policies/provider definitions are bootstrap/control-plane state supplied at application startup, while each routed payout durably pins the policy/provider-operation semantics needed for historical correctness.

Requirements:

- restart of unresolved payouts MUST remain safe even if active configuration later changes;
- new payout routing MUST have a clear source for current configuration;
- configuration definitions SHALL have typed validation and stable serialization suitable for future HTTP/judge mapping;
- configuration mutation SHALL not silently rewrite historical payout semantics.

A production database, Rails, ORM, distributed configuration service or queue is NOT required by this specification.

## 7. Recovery schedule semantics

Recovery currently knows **what** action is legal. SPEC-006 SHALL also define enough domain semantics to express **when** an unresolved action becomes due.

Introduce a deterministic recovery schedule or equivalent representation capable of expressing, where applicable:

- initial resolution/retry delay;
- deterministic backoff progression;
- optional maximum delay;
- TTL/deadline interaction;
- next action due time;
- reason/action identity (`resolve`, `retry_same`, `defer`, etc.).

The core does not need to own a background worker. Instead it SHOULD expose values/queries that an external runner can use, for example:

- `next_action_at` on unresolved state/explanation; and/or
- a query for recovery/reconciliation work due as of a supplied time.

Requirements:

- repeated immediate `resume` calls SHALL NOT accidentally bypass a configured schedule;
- schedule decisions SHALL be deterministic under the injected clock;
- TTL/deadline safety outranks backoff convenience;
- `UNKNOWN` ownership safety remains unchanged;
- restart/replay SHALL preserve or deterministically reconstruct the same due-work semantics;
- no sleeping threads are required in correctness tests.

## 8. Recovery provider objective

Recovery-provider selection SHALL remain explicitly separate from recovery legality.

SPEC-005's current `allocation_constrained` behavior is a valid mode, not the only conceivable generic objective.

The architecture SHOULD permit a small typed recovery-selection mode, for example:

- `allocation_constrained` — preserve applicable allocation obligations before quality/ranking;
- `reliability_first` — after safety/business/admission/recovery legality, prefer mature quality before softer distribution preferences that do not affect primary accounting;
- `hybrid` — explicit bounded compromise defined lexicographically rather than one scalar score.

Do not implement multiple modes merely for feature count. Implement the minimum abstraction that makes the current business rule explicit and leaves a safe extension seam for the official TZ.

Safety, hard constraints, already-attempted-provider exclusion and operation/switch budgets remain non-negotiable.

## 9. Quality maturity, staleness and route cohorts

The deterministic quality layer SHALL remain lower priority than safety, eligibility, admission and allocation authority.

SPEC-006 extends SPEC-005 quality with two concerns.

### 9.1 Time staleness

A bounded observation-count window is not sufficient by itself to describe stale evidence.

The model SHOULD support a deterministic maximum evidence age or equivalent time-based staleness rule using injected time. Old evidence that has not been refreshed for a long period SHOULD be capable of losing routing authority even when fewer than `evidence_window` newer observations exist.

### 9.2 Route-comparable cohorts

Quality segmentation SHOULD use the typed routing context where enough evidence exists, rather than only arbitrary labels.

A practical hierarchy is:

`mature route cohort -> mature broader/provider evidence -> conservative prior/default`.

The exact cohort cardinality MUST remain bounded and explainable. Do not create uncontrolled high-cardinality feature combinations.

Requirements:

- sparse cohorts SHALL not dominate mature broader evidence;
- pending/UNKNOWN and recipient/downstream failures remain neutral unless provider semantics authoritatively attribute otherwise;
- exact/reproducible calculations remain required;
- replay must preserve evidence semantics;
- tests must cover sample maturity and time staleness independently.

## 10. Operational interaction telemetry

Fast health SHALL be capable of receiving evidence produced by the canonical provider-interaction path, not only manually preclassified signals.

The application/provider boundary SHOULD measure deterministic operational evidence where available, such as:

- interaction start/end monotonic time;
- observed duration;
- transport classification;
- normalized timeout/service/overload outcome.

This evidence may then be normalized into existing typed health signals.

Requirements:

- telemetry must not change the already determined economic meaning of an ambiguous operation;
- recipient/business failures must not poison provider health;
- health remains fast operational admission evidence distinct from slow settlement quality;
- the clock must be injectable/testable and no wall-clock sleeps are needed for correctness evidence.

Context-scoped health MAY be introduced only where the implementation can bound complexity and prove that provider-global health is insufficient for the relevant route dimension.

## 11. Configuration product surface

RubyRouting SHALL expose a typed application-level configuration model sufficient to demonstrate that the routing strategies are actually configurable.

The application layer SHOULD be able to represent and validate:

- policy definitions and selectors;
- target weights and allocation measure;
- relevant recovery settings;
- provider route capabilities;
- capacity/throughput/availability settings.

A final public HTTP schema is not required before the authoritative TZ. If HTTP endpoints are added, they MUST be thin mappings onto the same typed application commands/configuration model and MUST NOT own routing semantics.

## 12. Analytics query surface

Dimensionally correct analytics already exists. SPEC-006 SHALL improve operator usability without weakening the dimension model.

The query/application surface SHOULD support compatible filtering/grouping by dimensions such as:

- policy id/epoch/scope;
- measure;
- currency;
- provider;
- allocation cohort/window where useful;
- time/as-of where already supported.

The implementation MUST reject or avoid additive aggregation across incompatible units.

Do not build a second analytics engine in HTTP/UI code.

## 13. Architectural convergence

The canonical product path SHALL move toward one semantic source of truth.

Required direction:

`typed command/context -> prepared evaluation -> shared pure transition/reducer -> atomic live mutation + durable facts`

and on restore:

`fact -> validation/linkage -> same/shared transition or invariant semantics -> reconstructed state`.

Specific hardening targets:

- eliminate or route the `DecisionEngine` compatibility computation through the same prepared-evaluation builder instead of maintaining a second independently evolving eligibility/feasibility path;
- continue reducing material live/restore business-rule duplication;
- keep `Coordinator` as the atomic facade while extracting coherent responsibilities only where this reduces reasons-to-change;
- clarify redundant admission concepts such as concurrent `max_slots` versus `max_count` rather than preserving ambiguous duplicate semantics.

Do not refactor correct code for aesthetics. Every architectural slice must reduce semantic duplication, make official-TZ changes safer, or improve verifiability.

## 14. Verification requirements

SPEC-006 SHALL receive executable traceability IDs in the existing acceptance map.

At minimum cover:

- typed routing context canonicalization;
- provider method/rail compatibility filtering;
- deterministic policy selection independent of registration order;
- visible no-policy and ambiguous-policy outcomes;
- active configuration versus pinned historical policy behavior across restart;
- recovery `next_action_at`/due-work semantics;
- backoff and TTL/deadline interaction;
- time-stale quality evidence;
- route-context quality fallback;
- operational latency/transport telemetry feeding health without changing economic UNKNOWN semantics;
- configuration DTO validation;
- filtered analytics preserving dimensional compatibility;
- removal/convergence of duplicate evaluation semantics;
- any admission semantic cleanup;
- exact-revision full test/property/model/concurrency/fault/restart evidence before closure.

Material bugs require deterministic regression tests. Randomized failures require reproducible seed/trace.

## 15. Explicit non-priorities

Before the official TZ, do not prioritize:

- ML/contextual bandits/exploration as a substitute for deterministic routing;
- microservices or distributed consensus;
- Rails/ORM/queue infrastructure without a confirmed requirement;
- brand-specific PSP adapters without an authoritative provider contract;
- dashboard polish before semantic control-plane acceptance is green;
- deeper journal corruption taxonomy absent a newly discovered correctness defect;
- unsupported 100k/production-scale claims;
- cosmetic coordinator/restorer rewrites.

## 16. Completion criteria for v0.3.2

v0.3.2 SHALL NOT be called complete while a material locally solvable gap remains in:

1. typed route-context semantics;
2. provider route-capability matching;
3. deterministic policy resolution and ambiguity handling;
4. active configuration boundary;
5. recovery scheduling/due-work semantics;
6. route-aware quality maturity/time staleness;
7. canonical-path operational telemetry needed for fast health;
8. configuration product surface;
9. dimension-safe analytics querying;
10. duplicate routing/live-restore semantics identified by this version;
11. ambiguous admission concepts materially affecting correctness or explainability;
12. SPEC-006 executable traceability.

Completion requires a fresh skeptical closure on the exact candidate revision under `docs/COMPLETION_POLICY.md`.

When the authoritative TZ arrives, it immediately supersedes provisional SPEC-006 semantics through `docs/TZ_RECONCILIATION.md`.