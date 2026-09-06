# Goal Mode + SpecOps Workflow

Current Version Goal: **v0.3 — Product Convergence & Full Routing Product**.

## Operating loop

`Discover -> Specify -> Plan -> Implement -> Verify -> Review -> Reconcile -> Discover next gap`

The final discovery step is mandatory.

### Discover

For project-wide work read the current goal/plan/spec/architecture first. Inspect actual code and tests before deciding that a capability exists or is missing.

Inventory which modules are:

- canonical core;
- integrated application/infrastructure;
- test/demo support;
- experimental/dead/misleading.

Do not preserve experimental code merely because deleting it feels destructive.

### Specify

Behavior changes must map to SPEC-004 or inherited requirements.

When an official value is unknown, prefer a reversible typed/configurable model. Do not invent provider-specific facts or case-irrelevant heuristics.

Safety ambiguity is resolved conservatively.

### Plan

Use `docs/exec-plans/active/product-convergence.md` for substantial work.

Plans are outcome-based and may reopen phases. They do not define completion by exhausting a checklist.

### Implement

Work in coherent vertical slices.

Rules:

- preserve financial invariants first;
- integrate features through the canonical routing pipeline;
- keep provider-specific semantics at provider adapters;
- keep provider I/O outside atomic state transaction;
- use exact Ruby arithmetic for money/allocation;
- use controlled time/randomness in correctness-sensitive code/tests;
- decompose internal responsibilities only when it improves invariant ownership;
- remove duplicate/misleading paths after replacement is proven;
- do not add new speculative infrastructure while existing product layers are incoherent.

### Verify

Use the relevant layers from `docs/TESTING.md`:

- unit/value;
- deterministic acceptance/regression;
- oracle/property;
- model histories;
- controlled concurrency;
- seeded provider/fault scenarios;
- replay equivalence;
- crash/restart tests;
- corruption tests for durable state;
- load/benchmark after correctness.

Every material randomized failure must be reproducible by seed/trace.

### Review

Review as a skeptical payout-platform maintainer:

- Can this create a second monetary effect?
- Can UNKNOWN release/switch accidentally?
- Did we mix primary allocation, recovery and settlement?
- Can optimization bypass eligibility/admission/allocation obligations?
- Did a provider-specific assumption leak into generic core?
- Can restart lose ownership or idempotency state?
- Does raw external input get to declare trusted financial semantics?
- Is a module actually integrated or merely required/instantiated in tests?
- Is the claimed scale/product maturity supported by evidence?
- Did we add complexity unrelated to the case?

### Reconcile

After each slice:

- update active ExecPlan;
- update SPEC/decisions only for durable behavior;
- update backlog for discoveries;
- remove superseded code paths;
- preserve regressions/seeds;
- confirm docs still point to the current version;
- choose the next required slice immediately.

## Product-convergence sequencing

Default order:

1. clean coherent baseline;
2. coordinator/internal responsibility convergence;
3. policy/allocation semantics;
4. admission controller;
5. constrained smart optimization;
6. provider lifecycle/reconciliation;
7. durable restart safety;
8. analytics/audit;
9. application/API/demo;
10. deep verification/performance;
11. closure/red-team.

Reorder only when dependency evidence justifies it.

## No fake progress

Do not report product progress through names or marketing claims.

Examples of forbidden substitutions:

- calling an always-success simulator a real PSP adapter;
- calling weighted-sum ranking Pareto optimization;
- calling replay projections crash recovery;
- calling a 300-payout test a 100k battle test;
- calling a generic webhook trusted because the request includes `safe_to_release`.

Fix the semantics or narrow the name/claim.

## Autonomy

Proceed autonomously for reversible internal design, refactoring, tests, reference models, small dependencies and configuration defaults that preserve governing behavior.

Escalate only when the choice truly depends on authoritative external semantics and no generic reversible approach is valid.

## Anti-loop

After two similar failures change tactic. After three materially different failures reduce to a minimal reproducer and re-plan.

Do not optimize completion by weakening requirements.

## Official TZ transition

When the TZ arrives:

1. fully read it;
2. create v0.4 reconciliation;
3. classify current behavior `CONFIRMED/CHANGED/REMOVED/NEW/AMBIGUOUS`;
4. update spec/tests/reference behavior coherently;
5. adapt the product;
6. implement only TZ-justified external integrations/limits;
7. preserve the mature core wherever compatible.
