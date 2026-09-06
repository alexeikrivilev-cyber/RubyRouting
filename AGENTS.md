# AGENTS.md

## Mission

Build RubyRouting into a submission-ready smart payout-routing product for Hack.Genesis before the official TZ arrives.

Do not wait for the TZ to begin important work. Build the complete generic product now and reconcile it against the official contract later.

Ruby is mandatory. Current baseline: **CRuby 4.0.6**. Product logic, routing algorithms, reference/oracle models, simulators, property/model/concurrency/fault harnesses and domain benchmarks are Ruby-only.

Current Version Goal: **v0.3 — Product Convergence & Full Routing Product**.

## Mandatory fresh-session read order

For project-wide work read, in order:

1. `README.md`
2. `docs/ROADMAP.md`
3. `docs/COMPLETION_POLICY.md`
4. `docs/exec-plans/active/product-convergence.md`
5. `specifications/004-product-convergence.md`
6. `specifications/003-pre-tz-full-logic-and-completion.md`
7. `specifications/002-pre-tz-comprehensive-core.md`
8. `specifications/001-smart-payout-routing.md`
9. `docs/PRODUCT_CONVERGENCE_REVIEW_2026-08-28.md`
10. `docs/CURRENT_ARCHITECTURE.md`
11. `docs/ARCHITECTURE.md`
12. `docs/RUBY.md`
13. `docs/TESTING.md`
14. `docs/WORKFLOW.md`
15. `docs/PLANS.md`
16. `docs/SESSION_POLICY.md`
17. `docs/BACKLOG.md`
18. `docs/DECISIONS_CURRENT.md`
19. `docs/DECISIONS.md`
20. `docs/RESEARCH.md` when external evidence is relevant.

Never infer project status from commit messages or old completion claims without checking the current roadmap and active plan.

## Source-of-truth precedence

Before the official TZ:

`direct current instruction > SPEC-004 > SPEC-003 > SPEC-002 > SPEC-001 > current durable decisions > implementation/tests`

When the official TZ is published it becomes authoritative and triggers explicit reconciliation.

Code is not the spec. Tests are not the whole spec. A green suite is evidence, not permission to shrink scope.

## Current development vector

The repository already has a strong deterministic core. Do not restart it.

Keep:

- exact money and deterministic allocation;
- one economic intent / single unresolved ownership;
- explicit dispatch and provider-operation contract;
- conservative `UNKNOWN` handling;
- primary/recovery/settlement separation;
- current eligibility, capacity, health, recovery and replay concepts;
- provider I/O outside the atomic lock;
- typed facts and projections;
- independent Ruby tests/oracles/models.

But do not preserve accidental complexity merely because it exists. The current task is to converge the repository into one coherent product.

The canonical flow is:

`Intent -> Policy -> Opportunity -> Admission -> Allocation -> Constrained Optimization -> Atomic Commit -> Provider Operation -> Observation -> Lifecycle/Recovery -> Durable State -> Analytics/API/Demo`

Every production module must have an explicit place in this flow.

## Product-convergence rules

1. **Case relevance first.** New work must materially strengthen payout distribution, eligibility, provider selection, load/health, safe fallback/retry, reconciliation, history, analytics, configurability or demonstrability.
2. **One source of business truth.** API, persistence, dashboard and adapters do not implement alternate routing semantics.
3. **No dead optional hooks.** Do not keep non-integrated production modules merely because they might be useful later.
4. **No misleading names.** A simulator is not a real PSP adapter. A projection-only reload is not crash recovery. A weighted sum is not a Pareto optimizer.
5. **No hardcoded business trivia in core.** Brand/BIN/bank/rail heuristics belong only in explicit demo/provider plugins unless required by authoritative TZ.
6. **No speculative product claims.** Never label the repository `v1.0`, industrial, production-ready or complete without closure evidence.

## Architecture direction

Target a plain-Ruby modular monolith with these logical responsibilities:

- immutable domain/policy values;
- provider catalog and functional eligibility;
- operational admission controller;
- exact allocation controller;
- constrained optimization controller;
- recovery/reconciliation policy;
- lifecycle reducer;
- focused allocation/capacity/health/operation ledgers;
- one atomic state transaction coordinator/facade;
- provider adapters and normalization;
- durable state/fact store;
- application commands and queries;
- analytics/audit projections;
- simulator/demo shell.

Internal decomposition is encouraged when it gives responsibilities real ownership, but keep one clear atomic correctness boundary until evidence requires another model.

## Optimization rule

Never collapse safety, contractual allocation and optimization into one arbitrary weighted score.

Required ordering:

1. economic safety;
2. hard eligibility/legal/business constraints;
3. operational admission: availability/capacity/rate/health;
4. allocation obligations/admissible corridor;
5. reliability/quality optimization;
6. cost/latency/priority optimization;
7. exploration only when explicitly safe and bounded.

An optimizer may choose only among actions admitted by higher-priority layers.

## Durability rule

Do not call a persistence mechanism restart-safe unless a fresh process can safely continue unresolved payouts without losing:

- economic ownership;
- operation identity/phase;
- provider contract/idempotency identity;
- policy binding;
- required allocation/capacity reservations;
- event deduplication/order state;
- reconciliation state.

A read-only replay projection is useful but is not equivalent to a recovered working coordinator.

Durable corruption/truncation must be detected explicitly. Never silently drop a malformed financial fact and continue as if history were complete.

## Provider boundary rule

Raw provider callbacks/errors do not create `NormalizedOutcome` by trusting external fields such as `safe_to_release`.

Provider-specific adapter/normalizer code owns conversion from raw transport/provider semantics to domain evidence. Only normalized evidence enters the core reducer.

## Ruby-only policy

Follow `docs/RUBY.md`:

- money = Integer minor units + currency;
- proportions/discrepancy = integer weights / `Rational`, never Float for financial correctness;
- controlled time and randomness when behavior depends on them;
- deterministic tie-breaking;
- no provider/network I/O under the atomic state lock;
- never rely on GVL for correctness;
- expected provider/business outcomes are values, not broad exception control flow.

## Goal Mode operating loop

For every substantial slice:

`orient -> inspect real code -> choose highest-value gap -> specify acceptance -> implement -> focused verify -> broad verify -> skeptical review -> update plan/backlog -> discover next gap -> continue`

Do not stop after a file, commit, milestone, phase or green suite.

The agent should continuously prefer the next dependency-unblocking or correctness-improving slice over aesthetic cleanup.

## Anti-premature-completion rule

`docs/COMPLETION_POLICY.md` is mandatory.

The agent MUST NOT claim the active version/project is complete because:

- all current checkboxes are green;
- all known issues were fixed;
- CI is green;
- a benchmark is fast;
- a demo works;
- all files mentioned in the original plan were implemented;
- the agent cannot immediately think of another task;
- the official TZ is not yet available.

Before any version-complete claim, enter `VERSION_CANDIDATE` and perform a fresh repository-wide closure attempt that actively tries to disprove completeness.

For v0.3 that closure must include at least:

- source/spec reconciliation through SPEC-004;
- canonical-flow cohesion audit;
- public/reachable code inventory and dead/experimental-code audit;
- financial invariant red-team review;
- restart/durability safety review;
- API/provider-boundary review if those layers exist;
- deterministic generated/fault/concurrency review;
- current full CI/test/benchmark evidence;
- backlog P0/P1 audit;
- documentation consistency audit.

A newly found important locally solvable gap reopens implementation.

## No scope shrinking

Do not redefine v0.3 around whatever already works.

Do not move a required product capability to `LATER` simply to reach completion. Unknown official values should normally become configurable/reversible semantics, not missing mechanisms.

The only acceptable reasons to remove a planned mechanism are:

- direct user instruction;
- official TZ contradiction;
- a durable decision proving a simpler mechanism provides equivalent required behavior;
- evidence that the mechanism is irrelevant to the case and its removal increases product coherence.

## Stop policy

Stop only when:

1. v0.3 legitimately reaches `VERSION_COMPLETE` under the closure policy; or
2. every remaining required path is genuinely externally blocked and no independent product work remains.

The absence of the official TZ is not a blocker for building the product.

## Anti-loop

- Do not repeat unchanged actions expecting another result.
- After two failed attempts with the same tactic, change hypothesis or design.
- After three materially different failures, reduce to a minimal reproducer and re-plan.
- Do not spend long sessions polishing formatting while product correctness/cohesion gaps remain.
- Do not rewrite correct code solely for style.

## Testing bar

Use the relevant combination of:

- deterministic regression/acceptance tests;
- independent oracle checks;
- property/invariant generation;
- state-machine/model histories;
- controlled interleavings;
- seeded fault/chaos scenarios;
- crash/restart boundary tests;
- duplicate/delayed/out-of-order event tests;
- replay equivalence;
- load/benchmark evidence after correctness.

Every randomized failure must report/reproduce its seed or trace. Never hide flakes with retries.

## Historical decisions

`docs/DECISIONS.md` contains historical rationale. `docs/DECISIONS_CURRENT.md` is the current convergence supplement and explicitly supersedes the false v1.0/product-complete claims added in the 2026-08-28 feature burst.
