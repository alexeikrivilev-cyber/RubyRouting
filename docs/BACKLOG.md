# RubyRouting Backlog

This backlog is subordinate to the active Version Goal, SPEC-003 and active ExecPlan. It separates locally actionable v0.2 work from genuinely official-TZ-dependent questions.

A backlog item cannot be moved to `LATER` merely to make version completion easier. `docs/COMPLETION_POLICY.md` and `docs/ROADMAP.md` control closure.

## Historical checkpoint — v0.1 deterministic foundation

The first executable foundation exists: Ruby harness, exact allocation, economic ownership/recovery baseline, simulator, facts/analytics, oracle/property/model/concurrency tests and benchmark.

It is historical checkpoint evidence only. Current development is v0.2.

## NOW — v0.2 Pre-TZ Comprehensive Routing Core

Active plan: `docs/exec-plans/active/pre-tz-comprehensive-core.md`.

### Closure candidate ledger — 2026-08-27

The implementation and focused evidence currently cover P0-001 through P0-008
and P1-001 through P1-011. They remain listed below as auditable requirements,
not deleted checklist items. P1-012 is the active `VERSION_CANDIDATE` closure
protocol; it is not considered resolved until the fresh source/spec,
capability, repository, red-team, verification, backlog and documentation
passes are recorded in the active ExecPlan. Any new material finding reopens
the corresponding item.

### P0-001 — isolate primary allocation from recovery

Under `primary_assignment`, fallback/recovery must not advance primary allocation state. Preserve separate primary/recovery/settlement facts and conservation.

### P0-002 — fresh fallback excludes attempted provider

A safe failure at A may enable a fresh decision but not a new money-moving A operation by accident. Same-provider retry remains explicit/operation-scoped.

### P0-003 — explicit operation dispatch phase

Distinguish committed/not-yet-dispatched, dispatching, ambiguous/observed and terminal phases. Duplicate commands cannot prematurely resolve/retry during original dispatch.

### P0-004 — operation-scoped provider recovery contract

Snapshot idempotency/status/TTL semantics with the operation so old unresolved work remains resolvable after provider disable/removal from new routing.

### P0-005 — transport ambiguity normalization

Distinguish definitely-not-sent from ambiguous-after-possible-send. Missing adapter/executable transport is rejected before money-moving commit.

### P0-006 — lifecycle reducer replaces status ranking

Remove arbitrary outcome-rank chronology. Use explicit transitions and authoritative provider ordering only when contractually meaningful.

### P0-007 — economic-conflict detection

Late old-operation success/evidence after newer operation/settlement becomes explicit reconciliation/economic conflict, never silent ignore.

### P0-008 — lifecycle replay from facts

Facts must rebuild supported payout/operation/ownership/settlement/reversal/conflict state, not only analytics.

### P1-001 — complete policy model and identity

Implement immutable policy fingerprint plus explicit generic primitives for:

- count/volume strategy;
- scope/segment;
- accounting point;
- window/epoch;
- targets/weights;
- tolerance/deviation;
- min/max constraints;
- hard vs soft/relaxable business constraints;
- static/runtime feasibility;
- recovery policy/budgets;
- deterministic ranking inputs.

No generic rules DSL.

### P1-002 — context-aware provider opportunity

Provider profile/constraints for currency, amount bounds, administrative state and explicit capability/context labels. Functional opportunity is separate from live feasibility.

### P1-003 — transient live infeasibility does not reset allocation history

Temporary outage/capacity/health change creates typed runtime deviation rather than silently erasing accounting. Any catch-up/debt pressure is bounded.

### P1-004 — deterministic capacity reservations

Support concurrent slots plus configurable count/amount budgets. Reserve/release atomically where required, retain unresolved capacity appropriately, prevent duplicate/late leaks and recheck fallback capacity.

### P1-005 — operational health/exposure controller

Implement attributable health, minimum evidence, hysteresis, degraded/quarantine/probing and controlled recovery. Recipient failure is neutral to provider health; allocation cannot bypass quarantine.

### P1-006 — deterministic feasible-set ranking

Replaceable ranker inside safe feasible set using configured priority and available health/quality/cost/latency inputs. Hard constraints stay lexicographic.

### P1-007 — recovery budgets/time/resume

Separate money-moving operation, provider-switch and resolution-interaction budgets; controlled deadline/elapsed semantics; idempotency/status TTL; explicit resume/advance/reconcile use case.

### P1-008 — return/reversal lifecycle

Post-settlement return/reversal in simulator/reducer/replay/analytics as remediation, not ordinary fallback continuation.

### P1-009 — typed decision trace and causal analytics

Structured policy/candidate/exclusion/allocation/capacity/health/ranking/recovery reason data. Separate primary allocation, recovery attempts, successful recovery and settlement. Include unresolved age, amplification, deviation attribution, reversal/conflict metrics.

### P1-010 — deep cross-feature verification

Generated state-machine/property histories and controlled races across policy, dispatch, allocation, capacity, health, observations, fallback, reconciliation, reversal and replay. Preserve material bugs as regressions.

### P1-011 — executable CI evidence

Add minimal Ruby CI when repository/runtime permits. No deployment pipeline.

### P1-012 — closure/discovery harness

Before v0.2 completion execute `docs/COMPLETION_POLICY.md`: source/spec reconciliation, C1–C14 capability sweep, unfinished-code search, adversarial/red-team pass, current verification, backlog/blocker audit and docs consistency.

Any newly found important generic gap becomes another NOW slice rather than being relabeled optional.

### P2-001 — coordinator internal decomposition

Only as current mechanics demand, extract lifecycle reducer/fact journal/allocation ledger/capacity/health responsibilities while retaining one atomic coordinator boundary.

### P2-002 — baseline performance hardening

Re-run allocation/lifecycle/replay benchmarks after correctness changes and optimize only measured bottlenecks.

## BLOCKED — official TZ required to finalize

These are important external semantics but do not block the mandatory generic v0.2 core.

### B-001 — full specification reconciliation

When authoritative TZ arrives, classify SPEC-001/002/003 as `CONFIRMED`, `CHANGED`, `REMOVED`, `NEW`, `AMBIGUOUS` and update oracle/tests/code coherently.

### B-002 — normative allocation contract values

Confirm exact official denominator/scope/accounting point/window/tolerance/min-max obligations and policy-change behavior. Generic typed concepts are still implemented in v0.2.

### B-003 — official provider/recovery contract

Confirm official statuses, timeout/idempotency/TTL/status lookup, callback ordering/reversal model and supplied provider simulator. Generic operation-contract mechanics remain v0.2 work.

### B-004 — judge/runtime/interface contract

Confirm exact Ruby runtime/dependency limits, input/output/API/UI, persistence/restart, load/data sizes, performance limits, required analytics and scoring.

### B-005 — official money/currency semantics

Confirm amount units/currencies and FX requirements. Never aggregate nominal multi-currency volume without explicit rule.

## NEXT — after official TZ appears

- N-001: v0.3 requirement reconciliation.
- N-002: choose minimal external API/persistence shell.
- N-003: official provider/judge adapters and contract tests.
- N-004: judged UI/analytics/demo surface.
- N-005: submission hardening against official limits.

## LATER — only after deterministic full core or with scoring evidence

- contextual/non-stationary bandit routing;
- automated correlated failure-domain inference;
- counterfactual/off-policy analytics;
- distributed infrastructure beyond confirmed needs;
- advanced schedule/mutation tooling beyond useful current verification.

## Full-TZ question checklist

1. What exactly does each routing percentage measure?
2. What is the official denominator/scope/window?
3. Is primary assignment, attempt, acceptance or settlement normative?
4. What tolerance/min/max contractual rules apply?
5. Which payout fields control provider eligibility?
6. Which count/volume/TPS/concurrency/cost limits exist?
7. What does “provider does not respond” mean in official simulator/contract?
8. Can a timeout represent accepted work?
9. What idempotency/status-resolution/TTL guarantees exist?
10. Which failures are terminal/retryable/provider/recipient/downstream?
11. Which retry/switch/deadline budgets apply?
12. Is defer/resume/reconciliation expected?
13. Can callbacks be duplicate/delayed/out-of-order?
14. Can success return/reverse later?
15. Which analytics/KPIs are judged?
16. Is provider health dynamic during evaluation?
17. Is concurrency tested?
18. What exact Ruby/dependency/environment restrictions apply?
19. Is persistence/restart required?
20. What API/UI/input-output contract is required?
21. Is a provider simulator/test hook supplied?
22. Which scoring criteria reward adaptive optimization?

## Maintenance rules

- Active ExecPlan controls current execution.
- SPEC-003 capability families remain mandatory until user/TZ/durable equivalent decision says otherwise.
- Prefer updating existing items over duplicates.
- Promote LATER only with evidence/scoring value.
- Every NOW/P0/P1 item must be reconciled before `VERSION_COMPLETE`.
- Never hide required work by deleting/relabeling backlog entries without preserved rationale/evidence.
