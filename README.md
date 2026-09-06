# RubyRouting

Smart payout-routing system for Hack.Genesis case **«Умный роутинг выплат»**.

## Current direction

Current Version Goal: **v0.3.2 — Semantic Control Plane & Recovery Readiness — VERSION_COMPLETE (pre-TZ)**.

v0.3.1 / SPEC-005 is a completed historical checkpoint at baseline revision `01c00f2f258a82fcf6e3b2ee843947a68ba62ed1`. v0.3.2 has now closed the semantic control plane around it before the official TZ arrives. The next normative change is the bounded reconciliation protocol, not speculative TZ-specific implementation.

Ruby is mandatory. Current development baseline: **CRuby 4.0.6**.

## Product principle

One canonical flow owns the system:

`Payout Intent`
→ `Canonical RoutingContext`
→ `Policy Resolution`
→ `Provider Route Compatibility / Functional Opportunity`
→ `Operational Admission`
→ `Allocation Authority`
→ `Recovery Legality / Due Schedule / Role`
→ `Constrained Optimization`
→ `Atomic Decision + Ownership + Reservations`
→ `Provider Operation`
→ `Operational Telemetry + Normalized Observation`
→ `Lifecycle / Recovery / Reconciliation`
→ `Durable State + Facts`
→ `Dimensioned Analytics / Explainability / Configuration / Queries`.

API, persistence, simulator, configuration endpoints and dashboard layers may not implement alternate provider-selection semantics.

## Protected baseline

The repository already has a strong deterministic payout-routing platform:

- exact `Money` and `Rational` allocation math;
- one economic intent and one unresolved economic owner maximum;
- conservative `UNKNOWN` handling after ambiguous transmission;
- explicit operation/idempotency contract;
- immutable executable provider operation payload with destination/context/method/rail;
- primary/recovery/settlement separation;
- count and volume allocation with committed work;
- opportunity/eligibility and operational admission separation;
- capacity, throughput and provider health;
- deterministic constrained optimization;
- safe retry/status-resolution/fresh fallback;
- confidence-aware bounded deterministic provider quality;
- duplicate/delayed/out-of-order provider event handling;
- settlement, reversal and economic-conflict handling;
- typed facts, replay and restart-safe unresolved continuation;
- dimensionally correct analytics across policy/measure/currency;
- typed decision explanation and public audit privacy boundary;
- application commands/queries and a small Rack-compatible HTTP adapter;
- unit/property/model/concurrency/fault/restart evidence;
- bounded performance/history evidence in CI;
- GitHub Actions on CRuby 4.0.6.

Do not casually rewrite these mechanisms. Extend them only when SPEC-006 or new evidence identifies a real semantic gap.

## What v0.3.2 closed

A fresh audit of the completed v0.3.1 main found the next-order gaps that mattered directly to the case; all required gaps are now closed:

1. **Routing context is now canonical across the product.** `PayoutIntent#routing_context` feeds provider compatibility, policy resolution, quality cohorts and executable provider payloads.
2. **Policy auto-resolution is deterministic.** Typed selectors use explicit priority/specificity and expose no-match and ambiguity.
3. **Recovery timing is explicit.** Injected-clock delay/backoff, TTL/deadline precedence and due-work queries are durable semantics.
4. **Quality evidence is route-aware and time-bounded.** Mature route/context/global evidence is selected deterministically with independent staleness.
5. **Canonical provider interaction timing is first-class exact telemetry.** Only provider-attributable slow interactions feed fast health; economic UNKNOWN remains unchanged.
6. **Configuration is represented by one typed application/control-plane model.** The deterministic demo applies that model before routing and accepts custom typed configuration/providers for operator-facing proof.
7. **Semantic convergence is materially reduced.** The standalone evaluation seam and live/restore/replay outcome reduction are shared; analytics querying now stays on the canonical dimensioned projection.
8. **Admission semantics are now explicit.** One in-flight exposure metric governs both legacy `max_slots`/`max_count` caps; time-window counts remain owned by throughput.
9. **Analytics is mathematically safe and queryable.** The application query surface filters/groups only compatible dimensioned measures and rejects ungrouped policy/unit variation.
10. **Audit retrieval is bounded at the application seam.** Append-only fact indexes preserve sequence order for payout/type filters, and the HTTP page path reads only the requested page without adding a database or changing durable facts.

## Active sources

Read these first for substantial work:

1. `README.md`
2. `specifications/006-pre-tz-semantic-control-plane.md`
3. `docs/exec-plans/active/pre-tz-semantic-control-plane.md`
4. `docs/PRE_TZ_BACKLOG.md`
5. `docs/ROADMAP.md`
6. `docs/PRE_TZ_ARCHITECTURE.md` for the protected v0.3.1 architecture baseline
7. `docs/CURRENT_ARCHITECTURE.md` for the inherited v0.3 baseline
8. `docs/COMPLETION_POLICY.md`
9. `docs/TZ_RECONCILIATION.md`
10. `specifications/005-pre-tz-maximum-hardening.md` for inherited detail.

Historical large backlogs/decision logs are not required reading for every new session.

## Governing specifications before TZ

Precedence:

1. direct current user instruction;
2. `specifications/006-pre-tz-semantic-control-plane.md`;
3. active v0.3.2 ExecPlan and active backlog;
4. `specifications/005-pre-tz-maximum-hardening.md`;
5. `docs/PRE_TZ_ARCHITECTURE.md` / `docs/CURRENT_ARCHITECTURE.md` for compatible baseline architecture;
6. older specifications and durable decisions;
7. implementation/tests.

When the official TZ arrives, use `docs/TZ_RECONCILIATION.md`. The authoritative TZ then overrides provisional semantics through explicit reconciliation.

## Closed implementation vector

The v0.3.2 implementation vector is complete:

1. canonical immutable `RoutingContext`;
2. explicit provider method/rail/destination capability matching;
3. deterministic registration-order-independent `PolicyResolver`;
4. recovery scheduling, backoff and due-work query semantics;
5. typed active policy/provider configuration model;
6. route-aware and age-stale deterministic quality evidence;
7. explicit recovery-objective seam;
8. prepared-evaluation and live/restore convergence plus admission semantic cleanup;
9. filtered dimension-safe analytics/configuration/due-recovery product queries;
10. bounded/indexable audit retrieval over the append-only fact history;
11. SPEC-006 executable traceability and fresh exact-revision closure.

Only optional P2 ideas remain in `docs/PRE_TZ_BACKLOG.md`; the next required
change is official-TZ reconciliation through `docs/TZ_RECONCILIATION.md`.

## Non-negotiable financial invariants

- One payout submission is one economic intent.
- At most one unresolved money-moving economic owner exists per intent.
- Ambiguous-after-possible-send is `UNKNOWN` unless provider semantics prove otherwise.
- `UNKNOWN` retains ownership and blocks cross-provider fallback.
- Same-provider retry/status lookup is distinct from fresh fallback.
- Fresh fallback re-evaluates current feasibility and excludes already money-moving providers by default.
- Provider-local idempotency does not protect cross-provider duplication.
- Hard safety, functional eligibility and operational admission precede allocation/optimization.
- Primary allocation, recovery attempts and settlement are separate accounting views.
- Provider outcome attribution is distinct from payout business outcome.
- Late evidence of a second monetary effect is an economic conflict requiring reconciliation.
- No-safe-route/defer/reconciliation-blocked are valid outcomes.
- Additive analytics never mixes incompatible measures/currencies.

## Architecture stance

Keep a plain-Ruby modular monolith with one atomic correctness boundary.

Prefer:

`typed command/context -> prepared evaluation -> shared pure transition/reducer -> atomic state mutation + durable facts`

and restore:

`fact -> validation/linkage -> same/shared transition/invariant semantics -> reconstructed state`.

Do not introduce microservices, Rails/ORM, queues, PSP-specific core schemas or ML/bandits before an authoritative requirement or measured need exists.

## Development commands

```text
bundle check
bundle exec rake test
bundle exec rake property
bundle exec rake model
bundle exec rake concurrency
bundle exec rake fault
bundle exec rake benchmark
bundle exec rake load_10k
bundle exec rake degradation_metrics
bundle exec rake history_profile
ruby -Ilib bin/ruby_routing_demo
```

Old green runs are historical evidence only. Changed code requires current verification.

## Current stage

RubyRouting is a mature, deeply verified pre-TZ payout-routing product with a strong financial kernel. v0.3.2 is a `VERSION_COMPLETE` checkpoint focused on route semantics, policy/control-plane determinism, timed recovery and product operability rather than feature-count expansion.

The v0.3.2 stop condition has been met by a fresh SPEC-006 closure on exact
HEAD. Do not add speculative pre-TZ scope merely because optional P2 ideas
remain. When the authoritative TZ arrives, switch immediately to
`docs/TZ_RECONCILIATION.md`.
