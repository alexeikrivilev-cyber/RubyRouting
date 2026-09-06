# RubyRouting backlog

This is the durable lightweight backlog. It is intentionally prioritized and separates work that should start now from questions genuinely blocked on the official TZ. GitHub Issue #1 is a discussion/tracking surface; this file is authoritative when they differ.

Do not implement `LATER` items opportunistically. The active Goal/ExecPlan defines scope.

## COMPLETED — v0.1 pre-TZ foundation (2026-08-27)

The absence of the full TZ was not a reason to remain pre-implementation. The
stable, reversible domain/test foundation below was completed according to
`docs/exec-plans/active/pre-tz-foundation.md`.

### NOW-001 — Ruby test harness and canonical commands

Create the minimal Ruby project/test setup and one documented full-suite command. All executable product/reference/simulator/test logic is Ruby. Keep judge-runtime-specific assumptions minimal.

### NOW-002 — independent reference model and executable specification

Build a pure Ruby oracle/reference model for stable invariants: economic ownership, outcome/recovery semantics, allocation discrepancy/accounting, and simple lifecycle projections. Keep it independent from production implementation so tests can detect shared-algorithm defects.

### NOW-003 — deep test harness

Implement the verification approach in `docs/TESTING.md`:

- deterministic provider simulator;
- virtual/controlled time where needed;
- property generators;
- state-machine/model tests;
- controlled concurrency/interleaving utilities;
- trace/replay diagnostics;
- regression-seed preservation.

### NOW-004 — deterministic allocation kernel

Implement the baseline count/volume allocator with exact money, opportunities/feasible candidates, post-decision discrepancy, and committed/in-flight assignments. Keep accounting point/window semantics configurable/isolated because the TZ may refine them.

### NOW-005 — economic ownership and recovery core

Implement payout economic-intent identity, single unresolved economic ownership, normalized outcomes/attribution, safe retry/fallback/resolve/defer semantics, and immutable lifecycle facts to the extent these do not depend on unknown provider APIs.

### NOW-006 — decision trace and minimal projections

Implement only enough opportunity/assignment/attempt/settlement projection and explainability to test the baseline semantics. Do not build a dashboard or analytics platform without TZ requirements.

### NOW-007 — pre-TZ concurrency and performance baseline

Prove ownership/allocation race invariants under controlled concurrency and record baseline routing throughput/latency/memory characteristics without turning guessed values into acceptance limits.

## BLOCKED — official TZ required to finalize

These are high-priority unknowns, but they no longer block the stable pre-TZ foundation above.

### B-001 — reconcile baseline against full TZ

When the official TZ is published, classify every relevant baseline rule in `specifications/001-smart-payout-routing.md` as `CONFIRMED`, `CHANGED`, `REMOVED`, `NEW`, or `AMBIGUOUS`. Update spec, reference model, tests, and implementation consistently.

### B-002 — allocation semantics

Confirm:

- exact meaning of “share by count”;
- exact meaning of “share by volume”;
- scope/denominator (all payouts vs eligible opportunities vs other);
- accounting point (primary assignment / attempt / acceptance / settlement);
- time/window semantics;
- allowed deviation/tolerance or exact minimization requirements;
- min/max/contractual quota semantics if present;
- behavior after fallback and policy changes.

### B-003 — provider/recovery contract

Confirm:

- provider statuses and terminality;
- exact meaning of “provider does not respond”;
- whether a timeout may represent accepted work;
- idempotency support and TTL;
- status lookup/reference capability;
- retryable vs terminal errors;
- whether cross-provider fallback after unknown is allowed/expected by the judge;
- retry/fallback/time budgets and deadlines.

### B-004 — judge/runtime/interface contract

Confirm:

- expected interface/input/output/API/UI;
- exact Ruby version/runtime;
- dependency restrictions;
- concurrency/load profile;
- data sizes/performance limits;
- simulation model for providers;
- persistence/restart expectations;
- required analytics output;
- scoring/acceptance criteria.

### B-005 — money/currency semantics

Confirm amount units, currencies, whether multiple currencies can share a volume policy, and any FX conversion rule. Never aggregate incomparable currencies without an explicit rule.

## NEXT — immediately after TZ reconciliation

### N-001 — update executable acceptance suite

Reconcile every implemented test/oracle with confirmed TZ semantics before changing corresponding production behavior. Add new official edge cases and remove/reclassify provisional assumptions.

### N-002 — minimal external architecture decision

Select the smallest framework/API/persistence/concurrency architecture that satisfies the confirmed interface, state, restart, load, and deployment requirements. Reuse the pre-TZ deterministic kernel rather than rebuilding around the chosen framework.

### N-003 — provider/judge integration

Adapt the provider boundary/simulator contracts to the official simulator/API and prove them with adapter contract tests before trusting end-to-end routing tests.

### N-004 — judged analytics/UI/API

Implement exactly the analytics/trace/reporting surfaces required or strategically valuable under the scoring model, using the already-separated opportunity/assignment/attempt/settlement semantics.

### N-005 — submission hardening

Turn TZ limits into explicit performance/stress gates, run the full adversarial/fault/concurrency suite repeatedly, test clean-environment setup, and audit all provisional decisions.

## LATER — only with evidence or TZ requirement

### L-001 — adaptive provider health

Fast operational health vs slower mature provider-quality estimate; optional degraded/quarantine/probing states and bounded recovery exposure.

### L-002 — confidence-aware ranking / exploration

Only if provider performance is dynamic and the judge rewards adaptive success optimization. Start deterministic; add statistical exploration only with enough signal and tests.

### L-003 — failure-domain correlation

Explicit or inferred shared bank/rail failure-domain logic only if provider metadata/events support it and it materially improves routing.

### L-004 — counterfactual/off-policy analysis

Only if the hackathon values policy comparison/replay and the available data supports honest evaluation.

### L-005 — advanced infrastructure

Queues, background jobs, persistent DB, distributed coordination, caching, custom observability, or service decomposition only when confirmed requirements/measurements demand them.

### L-006 — advanced test tooling

Mutation testing, sophisticated schedule exploration, or dedicated property-testing gems are valuable if they improve defect detection, but should be adopted only when the baseline Ruby harness demonstrates the need and judge/dependency constraints allow them.

## Full-TZ question checklist

1. What does a routing percentage measure exactly?
2. What is the denominator/scope for each strategy?
3. Which accounting point is normative after fallback?
4. What is the allocation window and required precision?
5. Are providers eligible by amount/currency/recipient/method/other fields?
6. Are there provider count/volume/TPS/concurrency limits?
7. What does “does not respond” mean semantically?
8. Can the provider have executed after our timeout?
9. What idempotency/status-resolution guarantees exist?
10. Which failures are terminal, retryable, provider-caused, recipient-caused, or downstream-caused?
11. How many attempts/provider switches are allowed?
12. Can/should a payout be deferred?
13. Are callbacks/events duplicated, delayed, or reordered in the simulator?
14. Can success later reverse/return, or is success final in the case model?
15. Which analytics/KPIs are explicitly judged?
16. Is allocation judged on primary routing or effective settlement?
17. Is provider health dynamic during evaluation?
18. Is concurrency tested?
19. What exact Ruby/dependency/environment limitations apply?
20. Is there a required API/UI/storage contract?
21. Are test/simulator hooks supplied by the organizers, and what failure scenarios do they generate?
22. Is deterministic replay/seed control available or expected?

## Backlog maintenance rules

- Add an item only when it is useful beyond the active run.
- Prefer updating an existing item to creating duplicates.
- `NOW` means eligible for current pre-TZ foundation work, not permission to violate the active ExecPlan's scope.
- Keep blockers and priority current.
- Remove resolved low-value detail once repository history/spec/tests preserve the knowledge.
- Do not copy specification requirements here; link to them.
- Do not turn optional research ideas into implementation commitments without evidence.
