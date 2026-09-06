# AGENTS.md

## Mission

Build RubyRouting into the strongest submission-grade smart payout-routing product we can produce **before** the official Hack.Genesis TZ arrives, then reconcile the authoritative TZ as a bounded delta rather than restarting implementation.

Ruby is mandatory. Current baseline: **CRuby 4.0.6**.

Current Version Goal: **v0.3.2 — Semantic Control Plane & Recovery Readiness**.

v0.3.1 / SPEC-005 is a completed historical checkpoint at baseline revision `01c00f2f258a82fcf6e3b2ee843947a68ba62ed1`. Preserve its proven safety/correctness; do not treat its completion as the current stop condition.

## Fresh-session read order

For substantial project work read, in order:

1. `README.md`
2. `specifications/006-pre-tz-semantic-control-plane.md`
3. `docs/exec-plans/active/pre-tz-semantic-control-plane.md`
4. `docs/PRE_TZ_BACKLOG.md`
5. `docs/ROADMAP.md`
6. `docs/PRE_TZ_ARCHITECTURE.md` as the protected v0.3.1 architecture baseline/delta
7. `specifications/005-pre-tz-maximum-hardening.md` only for inherited guarantees/detail
8. `docs/COMPLETION_POLICY.md`
9. `docs/TZ_RECONCILIATION.md`
10. `docs/RUBY.md`, `docs/TESTING.md`, `docs/WORKFLOW.md` when the current task reaches those concerns
11. older specs/backlogs/decisions/reviews only when a concrete question requires them.

Do not ingest the large historical backlog/decision logs by default before understanding the active SPEC-006 goal.

Before coding, inspect the actual tree, current implementation, tests and HEAD. Documentation describes intended authority; actual code determines what is already implemented and what needs reconciliation.

## Source-of-truth precedence before official TZ

`direct current instruction > SPEC-006 > active v0.3.2 ExecPlan > active PRE_TZ_BACKLOG > SPEC-005 > PRE_TZ_ARCHITECTURE/CURRENT_ARCHITECTURE > older specs > durable current decisions > implementation/tests`

When the authoritative TZ is published, execute `docs/TZ_RECONCILIATION.md`; the authoritative TZ then supersedes provisional pre-TZ semantics.

Code is not the spec. Tests are evidence, not permission to shrink a requirement.

## Protected strengths — do not restart or casually rewrite

Preserve unless new evidence proves a defect:

- exact Integer/Rational financial arithmetic;
- one payout submission = one economic intent;
- at most one unresolved money-moving economic owner;
- ambiguous-after-possible-send = `UNKNOWN` unless provider semantics prove otherwise;
- `UNKNOWN` retains ownership and blocks cross-provider fallback;
- same-provider resolution/retry is distinct from fresh fallback;
- primary assignment, recovery attempts and settlement are distinct views;
- functional opportunity is distinct from operational admission;
- capacity exposure is distinct from time-window throughput;
- hard safety/eligibility/admission precede allocation and optimization;
- optimizer cannot trade away higher-priority allocation authority;
- provider I/O stays outside the atomic state boundary;
- raw provider events are normalized at provider-specific boundaries;
- provider operation payload is immutable and restart-safe;
- dimensional analytics never mixes incompatible units;
- restart continuation preserves unresolved economic state;
- explanation/public audit privacy boundaries remain intact;
- deterministic/property/model/concurrency/fault evidence remains reproducible.

## Current problem

The financial kernel is no longer the weak point. The active work is to finish the **semantic control plane and timed recovery layer around it**.

The main inconsistencies to remove are:

- provider execution understands method/rail/context, while routing eligibility and quality segmentation do not yet share one canonical typed route identity;
- automatic policy resolution can still inherit registration-order behavior;
- recovery knows the legal next action but not a complete domain-level due schedule;
- strong quality uses bounded sample evidence but not independent time staleness or canonical route cohorts;
- health accepts rich signals but canonical provider interaction timing/telemetry is not yet a first-class evidence source;
- configuration is programmable through Ruby objects but lacks one typed application/control-plane model;
- canonical live evaluation improved in v0.3.1, but compatibility/live-restore duplicate semantics remain to converge;
- admission `max_slots` versus `max_count` needs one unambiguous business meaning;
- analytics is mathematically dimensioned, but product queries are still coarse.

## Current priority vector

1. **Canonical RoutingContext.** One immutable typed route identity for generic method/rail/destination/segment semantics.
2. **Provider route capabilities.** Functional eligibility must explicitly match the same route dimensions.
3. **Deterministic PolicyResolver.** Registration order may not silently determine business policy; no-match and ambiguity must be visible.
4. **Recovery scheduling/due work.** Express when resolution/retry becomes due using injected time; expose due unresolved work without adding queue infrastructure.
5. **Active configuration boundary.** Typed policy/provider configuration model separate from pinned durable payout history.
6. **Route-aware, time-stale quality.** Bounded cohorts plus age-based evidence staleness; preserve conservative fallback and allocation priority.
7. **Canonical provider interaction telemetry.** Controlled latency/transport evidence feeds fast health without changing economic UNKNOWN meaning.
8. **Architecture convergence.** One prepared-evaluation source, shared live/restore transition semantics, clearer Coordinator responsibility and admission semantics.
9. **Product query/configuration surface.** Dimension-safe analytics filters, configuration commands and due-recovery queries; HTTP remains a thin adapter.
10. **SPEC-006 traceability and fresh closure.** Completion is an exact-revision code-level claim, not a docs status.

The concise active queue is `docs/PRE_TZ_BACKLOG.md`.

## Canonical product flow

Target flow for v0.3.2:

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
→ `Dimensioned Analytics / Explanation / Configuration / Queries`.

Every production feature must have one clear owner in this flow. API, persistence, simulator, configuration endpoints and dashboard never own alternate provider-selection semantics.

## RoutingContext rule

Routing-critical dimensions must not remain scattered across arbitrary hashes.

Prefer one immutable provider-agnostic typed context exposing only generic route semantics needed by the engine, such as payment method, rail, destination kind and bounded normalized labels. Currency/amount remain authoritative on `Money`/intent.

Raw provider-operation context may be richer, but PSP-specific request fields remain in adapters.

Eligibility, policy resolution, quality cohorting and explanation should consume the same canonical interpretation where applicable.

Do not build a generic DSL or feature-vector framework before the official TZ.

## Policy resolution rule

Automatic policy selection must be deterministic and explainable.

Required behavior:

- explicit/pinned policy identity has highest authority when valid;
- selectors operate on canonical route context;
- priority/specificity ordering is explicit;
- registration-order permutations must not change the result;
- no match is visible;
- equal-precedence competing matches remain visibly ambiguous until configuration is corrected or a deterministic authoritative rule resolves them.

Never silently choose “latest registered” as a business tie-break unless the authoritative TZ explicitly defines that semantics.

## Recovery timing rule

Recovery safety and recovery timing are separate concerns.

The existing legality classifier protects ownership. Add deterministic due-time semantics without weakening it:

- configured delays/backoff use injected time;
- TTL/deadline outrank backoff convenience;
- repeated early `resume` may not bypass schedule;
- unresolved state/explanation should expose the next due action/time;
- application queries should be able to list due work as-of a supplied time;
- no sleeping worker/thread is needed to prove correctness.

Do not add Sidekiq/Redis/queues merely to implement a domain schedule.

## Allocation and recovery objective rule

Never collapse correctness into one scalar weighted score.

Required precedence remains:

1. economic safety;
2. hard functional/business constraints;
3. operational admission;
4. allocation obligations where authoritative;
5. recovery legality/budgets/due schedule;
6. reliability/quality;
7. cost/latency/priority;
8. bounded exploration only if explicitly justified later.

SPEC-005's recovery allocation behavior remains the current default. If an extension seam is introduced, make the recovery objective typed and lexicographic; do not let it modify the primary allocation ledger under current `primary_assignment` accounting.

## Quality rule

Quality remains deterministic and lower priority than safety/eligibility/admission/allocation authority.

Preserve confidence-aware prior shrinkage and bounded sample evidence, then add:

- canonical bounded route cohorts where enough evidence exists;
- time-based staleness independent of sample-window eviction;
- mature route -> mature broader provider -> conservative prior fallback;
- exact/reproducible calculations;
- provider attribution and unresolved neutrality.

Do not add adaptive exploration before the official objective is known and deterministic quality has been measured against it.

## Health / telemetry rule

Fast health protects **future admission**; it never retroactively changes an ambiguous payout's economic meaning.

Canonical provider interactions may measure monotonic duration/transport evidence and normalize it into the existing typed health vocabulary. Recipient/downstream failures remain neutral for provider health unless provider semantics prove otherwise.

Context-scoped health is optional and requires a bounded, demonstrated route-specific failure case.

## Active configuration rule

Distinguish active routing configuration from durable payout history.

Default pre-TZ architecture may treat policy/provider configuration as bootstrap/control-plane state supplied at startup, while routed payouts pin immutable historical policy/operation semantics needed for replay and unresolved continuation.

Create one typed application configuration model suitable for later HTTP/judge mapping. HTTP is optional before TZ and must remain a thin adapter.

Do not introduce a database/config service unless a real requirement appears.

## Analytics rule

All additive analytics remain dimensioned. Never add count to volume or currencies to one total.

The new work is query usability, not a second analytics engine: filter/group through compatible policy/epoch/scope/measure/currency/provider/cohort dimensions and reject/avoid invalid aggregation.

## Architecture rule

Keep one atomic correctness facade. Decompose only when semantic ownership improves.

Prefer:

`typed command/context -> prepared evaluation -> shared pure transition/reducer -> atomic mutation + facts`

and restore:

`fact -> validation/linkage -> same/shared transition/invariant semantics -> reconstructed state`.

Specific current targets:

- eliminate or redirect the standalone `DecisionEngine` compatibility computation through the canonical prepared-evaluation builder;
- converge the highest-value remaining live/restore duplicate business rule;
- keep `Coordinator` atomic but reduce coherent reasons-to-change where evidence supports it;
- resolve ambiguous `max_slots`/`max_count` admission semantics.

Do not create restorer classes merely to reduce file size.

## Ruby policy

Follow `docs/RUBY.md`:

- money = Integer minor units + currency;
- proportions/discrepancy = Integer/Rational, never Float for financial correctness;
- controlled/injected time and randomness where behavior depends on them;
- deterministic tie-breaking;
- never rely on GVL for correctness;
- provider/network I/O outside atomic lock;
- expected provider/business outcomes are values, not broad exception control flow.

## Goal Mode operating loop

For every substantial implementation session:

1. read active sources;
2. inspect actual code/tree/tests/HEAD;
3. reconcile the active ExecPlan with facts;
4. formulate the current session Goal as advancing the **whole current Version Goal**, not finishing one ticket;
5. choose the smallest highest-value unblocked slice;
6. establish or update executable acceptance evidence;
7. implement;
8. run focused verification;
9. run broader risk-appropriate verification;
10. perform skeptical self-review;
11. fix material findings;
12. update active plan/backlog;
13. immediately select the next slice and continue.

Do not stop after one file, class, test, commit, green suite, backlog item or phase.

Do not ask “continue?” when the next step can be derived from active sources and code.

## Anti-loop

- do not repeat unchanged tactics expecting a different result;
- after two failures with one tactic, change hypothesis/design;
- after three materially different failures, reduce to a minimal reproducer and re-plan;
- do not compensate for unclear semantics by adding validation layers;
- do not rewrite correct code solely for style;
- if one phase is blocked, switch to another independent current-version slice.

## Verification bar

Choose evidence proportional to risk:

- deterministic unit/acceptance regression;
- independent allocation/policy/quality oracle where useful;
- property/invariant generation;
- metamorphic tests, especially registration-order/context canonicalization invariance;
- model/state-machine history;
- controlled concurrency/interleavings;
- seeded fault simulation;
- duplicate/delayed/out-of-order provider events;
- fake-clock scheduling/TTL/deadline boundaries;
- crash/restart where persistence semantics change;
- replay equivalence;
- performance/load only after correctness.

Every randomized failure must expose a reproducible seed/trace. Never hide flakes with retries.

SPEC-006 requires active acceptance traceability in addition to inherited SPEC-005/AC evidence.

## Completion / stop policy

`docs/COMPLETION_POLICY.md` is mandatory.

v0.3.2 is not complete while a material locally solvable gap remains in typed route context, provider route capability matching, deterministic policy resolution, active configuration semantics, recovery due scheduling, route-aware/time-stale quality, canonical operational telemetry, application configuration/query surface, identified duplicate semantics, admission terminology or SPEC-006 traceability.

Stop only when:

1. v0.3.2 legitimately reaches `VERSION_COMPLETE` after a fresh code-level SPEC-006 closure on exact HEAD; or
2. every remaining required item is genuinely externally blocked and no independent case-relevant work remains; or
3. the authoritative TZ arrives, in which case immediately switch to `docs/TZ_RECONCILIATION.md`.

Absence of the official TZ is not itself a blocker.

## Historical context

v0.3.1/SPEC-005 completion evidence remains valid. Historical specs/backlogs/decisions/reviews are rationale and regression archaeology, not the active queue. Do not opportunistically reopen proven durability/safety work unless new evidence demonstrates an actual defect.