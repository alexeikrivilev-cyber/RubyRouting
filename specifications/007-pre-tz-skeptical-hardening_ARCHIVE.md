# SPEC-007 — Pre-TZ Skeptical Hardening & Product Semantics

Status: ACTIVE

## Purpose

Continue product development before the authoritative Hack.Genesis TZ instead of treating the green v0.3.2 checkpoint as a reason to wait. Preserve the proven financial kernel and close material locally solvable defects discovered by a fresh skeptical review of actual `main`.

This specification is intentionally case-bound: payout routing, fallback/recovery, provider selection, configuration, evidence quality, durability and operator-facing semantics. It does not authorize speculative infrastructure or PSP-specific schemas.

## Version Goal

Make RubyRouting robust not only against its existing acceptance checklist, but against cross-layer counterexamples that arise when configuration, time, evidence, restart and routing decisions interact.

A v0.3.3 candidate must make these statements true:

1. a routing decision observes one coherent active configuration generation;
2. malformed routing-critical input fails closed rather than silently becoming an empty route context;
3. quality staleness is applied to the evidence that contributes to the score, not only to the newest timestamp of a cohort;
4. durable recovery/throughput timing remains correct when a process restarts with a different monotonic clock origin;
5. quality comparison does not silently pool materially incompatible currency/route populations;
6. sparse route evidence cannot gain disproportionate authority without an explicit confidence/maturity rule;
7. policy resolution semantics are deterministic for overlapping selectors and support generic payout amount bands without a rules DSL;
8. active configuration has explicit revision/source-of-truth semantics and useful cross-object diagnostics;
9. recovery optimization remains safe and can express a case-relevant reliability objective without mutating primary allocation accounting;
10. the application/demo surface exposes the important control/query semantics without owning an alternate routing algorithm;
11. any further decomposition reduces semantic duplication rather than moving lines;
12. closure is based on fresh adversarial discovery, not merely exhaustion of a prewritten backlog.

## Protected inherited guarantees

All compatible guarantees from SPEC-006/005 remain mandatory, especially:

- exact Integer/Rational financial arithmetic;
- at most one unresolved money-moving economic owner per payout;
- ambiguous-after-possible-send remains `UNKNOWN` and retains ownership;
- no cross-provider fallback while unresolved ownership exists;
- provider-local idempotency is not cross-provider idempotency;
- provider I/O stays outside the atomic correctness boundary;
- functional opportunity, operational admission, primary allocation, recovery and settlement remain distinct;
- hard constraints precede optimization;
- raw provider input cannot directly assert trusted economic release semantics;
- additive analytics never mixes incompatible measures or currencies;
- restart/replay preserves unresolved economic state and pinned historical policy/operation semantics.

## P0 requirements

### S7-001 — Atomic active configuration generation

Policy resolution and provider-catalog evaluation for one new decision must use one coherent immutable active configuration snapshot/revision.

Required evidence:

- concurrent `apply_configuration(A -> B)` and payout submit yields a decision entirely under A or entirely under B;
- no valid interleaving can commit `policy(A) + providers(B)` or the reverse;
- the configuration lock/snapshot is released before provider I/O;
- in-flight payouts continue through pinned historical semantics after later configuration changes;
- decision/explanation/audit can identify the active configuration revision used when useful without copying mutable config into payout history unnecessarily.

### S7-002 — Fail-closed routing-context boundary

`RoutingContext.from` and public intent/transport boundaries must reject malformed non-hash/non-typed routing context values instead of silently converting them to an empty context.

`nil` may remain an explicit empty context. Semantically equivalent valid hash forms must still canonicalize identically.

### S7-003 — Evidence-age-correct quality

When `max_evidence_age_seconds` is configured, only evidence that is fresh as of the routing decision may contribute to success/failure counts, maturity, confidence and score.

A single fresh observation must not refresh an arbitrary number of expired observations. Age filtering and bounded sample-window semantics must have one explicit order and deterministic tests.

### S7-004 — Restart-safe clock-origin independence

Durable timing semantics must not assume a persisted monotonic number belongs to the next process/host monotonic origin.

Recovery schedules, TTL/deadline checks and throughput windows must be reconstructed/rebased from durable wall anchors or equivalent portable data into the current process monotonic domain. Tests must restart with a deliberately different controlled monotonic origin.

## P1 requirements

### S7-101 — Currency-aware comparable quality cohorts

Quality evidence used for provider comparison must not silently pool materially different currencies merely because payment method/rail/destination match. Keep currency authoritative on Money/intent; use a bounded typed evidence key rather than moving economic amount semantics into `RoutingContext`.

Define deterministic fallback from the most comparable mature cohort to broader evidence and finally the prior.

### S7-102 — Sparse-route evidence authority

Route-specific evidence must have an explicit maturity/confidence policy stronger than accidental `minimum_samples = 1` behavior when broader evidence is mature. Prefer a simple deterministic design such as per-scope maturity thresholds or hierarchical prior/shrinkage; do not introduce stochastic learning.

### S7-103 — Policy selector semantics

Improve selector precedence so equal-priority overlapping policies are resolved by semantic specificity/subsumption where one selector clearly narrows another; incomparable equal-authority selectors remain ambiguous.

Support generic amount bands with exact minor-unit semantics and explicit currency compatibility. Registration order must never become the business rule.

### S7-104 — Configuration compilation and ownership

Define one active configuration source-of-truth with immutable revision identity. Validate the configuration as a system, not only as independent objects.

Diagnostics should distinguish valid, valid-with-warning and statically unreachable/inconsistent relationships where determinable, while preserving legitimate opportunity-aware policies whose configured target provider may be temporarily absent/unavailable.

Make provider-catalog durability versus active policy/config bootstrap ownership explicit; avoid two accidental active sources of truth.

### S7-105 — Recovery objective product seam

Keep `allocation_constrained` as the default. Add a reliability-first or equivalent deterministic recovery objective only if it can be implemented without weakening economic safety, recovery legality, provider-switch budgets or primary allocation accounting. The mode must be typed, explained and tested against the default.

### S7-106 — Semantic architecture convergence

Keep `Coordinator` as the atomic transaction facade. Extract only boundaries that remove multiple semantic sources, especially active configuration snapshot semantics and portable recovery/expiry timing. Do not create classes merely to reduce file size.

### S7-107 — Application/demo parity

Expose the already-supported configuration, due-work and dimension-safe analytics query semantics through a thin demonstrable application/HTTP/CLI path where useful. Typed domain/application errors such as no-policy/ambiguous-policy should not be collapsed into indistinguishable generic errors if a stable application error can be expressed without guessing the official TZ schema.

### S7-108 — Context-scoped fast health, evidence-gated

First build a deterministic scenario where one provider route fails while another route remains healthy. Promote route-scoped health only if provider-global quarantine demonstrably suppresses good traffic and a bounded route-health key solves it without cardinality explosion.

### S7-109 — Larger-history evidence

After correctness work, run bounded scale campaigns beyond the current 10k checkpoint and measure actual restore, analytics/query, audit-page, memory and throughput curves. Optimize only measured bottlenecks; do not claim production scale from synthetic success-only routing.

## Verification requirements

For every material defect:

- add deterministic regression evidence;
- use property/metamorphic tests when ordering/canonicalization invariants matter;
- use controlled concurrency for config/decision races;
- use fake clocks with deliberately different origins for restart-time behavior;
- retain reproducible seeds/traces for randomized failures;
- run focused tests first and the risk-appropriate broad matrix before marking the slice verified.

## Skeptical closure gate

Finishing all listed S7 items does **not** prove version completion.

Before `VERSION_COMPLETE` the agent must enter `VERSION_CANDIDATE` and perform a fresh discovery pass from actual code without using backlog completion as a premise. At minimum challenge:

- cross-layer concurrency between configuration, decision and provider runtime state;
- malformed routing/context/config inputs;
- mixed-age/mixed-currency/sparse evidence;
- restart with changed clock origin and changed active configuration;
- policy overlap/subsumption/ambiguity;
- recovery timing versus TTL/deadline and provider capability changes;
- live versus restore/replay transition equivalence;
- query/API behavior versus canonical application semantics;
- scale/history behavior where current implementation is O(history).

Any newly found locally solvable P0/P1 reopens development and is added to the active backlog. A green known checklist is only the entry condition for this audit.

A closure claim requires a fresh exact-HEAD verification matrix, current CI, documentation consistency and an explicit statement of adversarial areas examined with no remaining material locally solvable findings.

## Stop conditions

Stop only if:

1. v0.3.3 passes the skeptical closure gate on exact HEAD; or
2. every remaining required item is genuinely externally blocked and no independent case-relevant work remains; or
3. the authoritative TZ arrives, which immediately switches authority to `docs/TZ_RECONCILIATION.md`.

The absence of the official TZ, exhaustion of the initial backlog, green CI or completion of a phase is not a stop condition.
