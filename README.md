# RubyRouting

Smart payout-routing system for Hack.Genesis case **«Умный роутинг выплат»**.

## Current direction

Current Version Goal: **v0.3 — Product Convergence & Full Routing Product**.

We are not waiting for the official TZ. We are building the product now: a coherent, deeply tested payout-routing platform whose core behavior should survive most plausible TZ variants. When the official TZ arrives, it becomes a reconciliation/integration task, not the beginning of implementation.

The project must stay centered on the case:

- configurable distribution of new payouts between providers;
- count/volume and related allocation strategies;
- provider eligibility, availability, capacity and health;
- safe retry/status-resolution/fallback when a provider fails or does not answer;
- complete attempt/decision history;
- analytics for distribution and success;
- explainable, deterministic financial behavior.

Ruby is mandatory. Current development baseline: **CRuby 4.0.6**.

## Product principle

One canonical flow owns the system:

`Payout Intent`
→ `Policy Resolution`
→ `Functional Opportunity`
→ `Operational Admission`
→ `Allocation Authority`
→ `Constrained Optimization`
→ `Atomic Decision + Ownership + Reservations`
→ `Provider Operation`
→ `Normalized Observation`
→ `Lifecycle / Recovery / Reconciliation`
→ `Durable State + Facts`
→ `Analytics / Audit / API / Demo`

Every new module must strengthen this flow. A feature that cannot be integrated into it with a clear responsibility is not core product work.

## What already exists

The repository has a strong deterministic routing checkpoint:

- exact `Money` and `Rational` allocation math;
- economic intent and single unresolved ownership;
- explicit dispatch state and provider-operation contract;
- `UNKNOWN != failure` and transport ambiguity;
- primary/recovery accounting separation;
- count/volume allocation with committed work;
- opportunity/eligibility, capacity and provider health;
- fallback/retry/status-resolution/reconciliation basics;
- duplicate/delayed/out-of-order event handling;
- typed deviation attribution with explicit recoverable/unavoidable classification;
- settlement/reversal/economic-conflict handling;
- typed facts, replay and analytics;
- restart-safe `FileJournal` continuation for unresolved provider operations;
- application commands/queries, a minimal sanitized Rack-compatible API adapter,
  and an explicitly simulated fallback demo;
- property/model/concurrency/fault tests;
- GitHub Actions on CRuby 4.0.6.

This is a checkpoint, not a finished product.

## Current correction

A later feature burst incorrectly described the repository as a delivered industrial v1.0 and added several disconnected/demo components. That claim is revoked.

The current product-convergence phase deliberately removes or redesigns modules that are misleading, unsafe, hardcoded, unintegrated or contrary to the project architecture. Useful concepts may be reintroduced through the canonical routing pipeline with proper contracts and tests.

See `docs/PRODUCT_CONVERGENCE_REVIEW_2026-08-28.md` and `specifications/004-product-convergence.md`.

## Architecture stance

Keep the good foundation, but converge it into one product:

- plain-Ruby modular monolith;
- deterministic financial kernel;
- one explicit atomic state transaction boundary;
- provider I/O outside the transaction lock;
- focused internal ledgers/reducers instead of a growing god object;
- provider-specific semantics normalized at adapters;
- durable state must be safe to resume after restart before it may be called recovery;
- optimization may only act inside a safety/policy-admissible envelope;
- APIs and dashboards are application/demo layers, never alternate sources of business truth.

Current architecture: `docs/CURRENT_ARCHITECTURE.md`.

## Governing specifications

Before the official TZ, precedence is:

1. direct current user instruction;
2. `specifications/004-product-convergence.md`;
3. `specifications/003-pre-tz-full-logic-and-completion.md`;
4. `specifications/002-pre-tz-comprehensive-core.md`;
5. `specifications/001-smart-payout-routing.md`;
6. durable current decisions;
7. implementation/tests.

The official TZ will supersede provisional semantics through explicit reconciliation, never silent edits.

## Read order for a coding agent

1. `AGENTS.md`
2. `docs/ROADMAP.md`
3. `docs/COMPLETION_POLICY.md`
4. `docs/exec-plans/active/product-convergence.md`
5. SPEC-004 → SPEC-003 → SPEC-002 → SPEC-001
6. `docs/PRODUCT_CONVERGENCE_REVIEW_2026-08-28.md`
7. `docs/CURRENT_ARCHITECTURE.md`
8. `docs/ARCHITECTURE.md`
9. `docs/RUBY.md`
10. `docs/TESTING.md`
11. `docs/WORKFLOW.md`
12. `docs/PLANS.md`
13. `docs/SESSION_POLICY.md`
14. `docs/BACKLOG.md`
15. `docs/DECISIONS_CURRENT.md`
16. `docs/DECISIONS.md` for historical rationale
17. `docs/RESEARCH.md` when external evidence is required.

## Non-negotiable financial invariants

- One payout submission is one economic intent.
- At most one unresolved money-moving economic owner exists per intent.
- A timeout after possible transmission is `UNKNOWN` unless provider semantics prove otherwise.
- `UNKNOWN` retains ownership and blocks cross-provider fallback.
- Same-provider retry/status lookup is distinct from fresh fallback.
- Fresh fallback re-evaluates current feasibility and excludes already money-moving providers by default.
- Provider-local idempotency does not protect cross-provider duplication.
- Hard safety, eligibility and operational admission precede allocation/optimization.
- Primary allocation, recovery attempts and settlement are distinct accounting views.
- Provider outcome attribution is distinct from payout business outcome.
- Late evidence of a second monetary effect is an economic conflict requiring reconciliation.
- No-safe-route/defer/reconciliation-blocked are valid outcomes.

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
ruby -Ilib bin/ruby_routing_demo
```

Old green runs are historical evidence only. Changed code requires current verification.

## Completion

Do not call the project complete because a checklist or test suite is green. Product completion requires the closure protocol in `docs/COMPLETION_POLICY.md`, including architecture-cohesion review, source/spec reconciliation, restart-safety evidence, deterministic fault/concurrency evidence, repository cleanup and a fresh red-team pass.
