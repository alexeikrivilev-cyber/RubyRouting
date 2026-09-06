# Goal Mode + SpecOps workflow

## Purpose

This document defines how a coding agent should execute work in RubyRouting. The objective is high autonomy with strong correctness: the agent should not need approval for routine implementation choices, but it must not improvise financial semantics or silently violate the governing specification.

The workflow combines:

- specification-first development from SpecOps;
- OpenAI's current Codex guidance on persistent repository context, issue-like goals, lightweight backlogs, progressive disclosure, and first-class plans for complex work;
- project-specific anti-loop, anti-bloat, and deep-verification rules for long-running Goal Mode.

Development is already active before the full TZ. The goal is to implement stable, reversible Ruby foundations now while keeping TZ-dependent interfaces/infrastructure replaceable.

## 1. The operating loop

For a non-trivial goal, use this cycle:

`Discover -> Specify -> Plan -> Implement -> Verify -> Review -> Reconcile`

Do not mechanically produce artifacts for every phase. The phases are reasoning/quality gates; create files only when the information must persist beyond the current run.

### Discover

- Read `AGENTS.md` and the smallest relevant part of the governing specification.
- Read `docs/TESTING.md` when the change affects financial/routing behavior.
- Inspect the active ExecPlan, existing code, tests, and reference/simulator model before proposing structure.
- Identify externally meaningful behavior, invariants, existing patterns, and actual constraints.
- Search official/current documentation when behavior depends on a versioned external API/library rather than guessing.
- Do not explore the entire repository when the goal has a clear local scope.

### Specify

Before writing behavior-changing code, ensure the desired behavior is covered by the governing spec and has testable acceptance criteria.

If the requirement is missing:

- for a reversible, low-impact detail, choose a conservative assumption and record it if it will matter later;
- for a durable domain rule, update the spec as part of the change;
- for a high-impact ambiguity involving money safety, official hackathon scoring/acceptance semantics, irreversible data behavior, or an external contract, surface it instead of inventing an answer.

Pre-TZ implementation may proceed against explicitly provisional semantics if the boundary is reversible and the assumption is already documented. Do not turn a provisional default into an irreversible external contract.

The spec is not bureaucracy. Keep it as small as necessary to make behavior unambiguous and verifiable.

### Plan

Use the smallest planning mechanism that fits the task.

**Small change:** keep a short internal checklist.

**Complex change:** create/update an execution plan when at least one is true:

- the change spans several domain boundaries/modules;
- it changes payout lifecycle, allocation semantics, concurrency, idempotency, or recovery safety;
- it requires a migration or compatibility strategy;
- it is expected to take multiple coherent implementation slices;
- there are important decisions that a later agent run must inherit.

Use `docs/PLANS.md`. Active plans live under `docs/exec-plans/active/`; completed durable plans may move to `docs/exec-plans/completed/`.

The current pre-TZ foundation plan is `docs/exec-plans/active/pre-tz-foundation.md` until completed/replaced.

A useful execution plan contains:

- goal and non-goals;
- governing spec/acceptance criteria;
- required verification layers from `docs/TESTING.md`;
- current-state findings;
- implementation slices;
- verification commands/evidence;
- decision log for material choices;
- progress/checkpoints;
- remaining risks/blockers.

Do not turn plans into diaries of every command.

### Implement

- Work in the smallest coherent vertical slice that can be verified.
- Prefer a simple working domain model over speculative abstraction.
- Keep the deterministic financial kernel independent from optional adaptive optimization.
- Normalize provider-specific behavior at boundaries rather than leaking provider codes into core routing rules.
- Keep all product/reference/simulator/test domain logic in Ruby.
- Build deterministic test seams for time/random/provider I/O only where the domain actually depends on them.
- When a tangential improvement is useful but not required for the active goal, add it to `docs/BACKLOG.md` instead of widening the change.
- Do not “future-proof” by implementing hypothetical features from parked backlog items.

### Verify

Verification should prove the behavior that matters, not merely that files changed.

`docs/TESTING.md` is the governing verification strategy. Choose the relevant layers based on risk:

- focused unit/value tests;
- executable acceptance/regression scenarios;
- property/invariant tests;
- state-machine/model-based tests;
- controlled concurrency/interleaving tests;
- provider contract tests;
- end-to-end fault scenarios;
- stress/performance checks where relevant.

For financial/routing work, verify applicable SPEC-001 behavior and reusable invariants, especially:

- economic ownership and duplicate intent behavior;
- `UNKNOWN` vs safe failure;
- fallback after safe release only;
- terminal recipient/payout failure preventing pointless provider hopping;
- count/volume discrepancy;
- concurrent committed allocations;
- opportunity-aware denominators;
- outcome attribution;
- duplicate/delayed/out-of-order observations;
- primary assignment vs settlement accounting;
- no-safe-route behavior.

Start with the narrowest check that can falsify the approach quickly, then run the relevant broader suite before completion.

Random/property/model tests must be reproducible by seed/trace. A material randomized failure should be reduced and preserved as a deterministic regression when practical.

Do not use automatic test retries to hide flakiness. If a test/check cannot run, report exactly why and what evidence was used instead. Never state that checks passed if they were not run.

### Review

Before declaring the goal done, review the complete diff as a skeptical maintainer:

- Does every behavior map to the governing goal/spec?
- Did the implementation accidentally weaken a financial invariant?
- Is any provider-specific assumption leaking into core logic?
- Is provisional TZ-dependent behavior isolated?
- Is there speculative infrastructure or abstraction with no current requirement?
- Did the change introduce duplicate concepts/helpers or a second implementation in another language?
- Are failure/empty/concurrent/delayed paths tested where relevant?
- Does the test oracle independently verify the production behavior rather than call the same helper?
- Did an implementation convenience silently become a public contract?
- Is the code legible enough for a future agent run to modify safely?

Fix material findings; do not churn working code for stylistic perfection.

### Reconcile

At the end of the task:

- update specification only for real domain/product decisions;
- update the backlog for deferred cross-cutting work;
- update the active execution plan if one exists;
- update decisions/architecture/testing docs only for durable changes;
- preserve failing seeds/regressions that reveal a real defect class;
- remove obsolete planning notes instead of letting them rot;
- report what changed, what was verified, and any material assumptions/blockers.

## 2. Goal Mode autonomy policy

Goal Mode should continue through routine engineering work without constant confirmation.

### Proceed autonomously

Proceed when the choice is reversible and does not define unknown business semantics, for example:

- local Ruby naming/organization consistent with the repo;
- test structure and deterministic simulator structure;
- refactoring needed to make requested behavior clear/testable;
- standard-library vs a small Ruby helper/gem decision when both preserve the contract and runtime risk is low;
- local performance improvements that preserve behavior and are evidenced.

### Proceed with a recorded assumption

Use a conservative assumption when uncertainty is real but reversible and low-risk. Record it in the active plan/backlog/decisions only if later tasks can depend on it.

Do not create an “assumptions log” full of trivial choices.

### Escalate

Escalate only when proceeding could materially choose the wrong product:

- double-payout/economic ownership semantics;
- meaning of timeout/unknown under a provider contract;
- target allocation accounting semantics from the official TZ when the choice would harden a public/persistence contract;
- irreversible data/migration behavior;
- public API/compatibility decisions that cannot be changed cheaply;
- destructive operations outside the explicit goal.

If repository code/tests or official documentation can resolve the issue, investigate first.

## 3. Anti-loop protocol

Long-running agents must detect when work is not converging.

### Rule A — no identical retries without changed state

Do not rerun the same command/action with the same relevant state and expect a different result. A legitimate repeat must have a reason: a fix/config/state change or explicit reproducibility verification.

### Rule B — change tactic after two similar failures

After two failed attempts based on the same hypothesis or mechanism, stop patching symptoms. Reassess the failure, inspect evidence, and change tactic/tool/design.

### Rule C — reduce after three distinct failures

After three materially different approaches fail:

1. reduce to the smallest reproducer;
2. state what is known vs assumed;
3. inspect authoritative docs/runtime evidence;
4. select a simpler route or record a concrete blocker.

Do not spend the remainder of Goal Mode cycling among the same approaches.

### Rule D — prevent local fixation

Maintain awareness of acceptance criteria and verification obligations. If a local issue is not blocking the goal, park it. Do not optimize one function, lint detail, abstraction, or benchmark while core acceptance criteria remain unfinished.

### Rule E — stop when done

When the goal and quality bar are verified, stop. Do not repeatedly rewrite correct code for subjective elegance.

## 4. Scope control and architecture taste

The project should grow from requirements and verified invariants, not from a hypothetical production diagram.

### Add structure when earned

A new abstraction/module/dependency is justified when it isolates a real external boundary, removes proven duplication, makes an invariant testable, satisfies a confirmed requirement, or addresses a measured constraint.

A testability seam can also earn structure when hidden time/random/I/O would otherwise make safety behavior nondeterministic or untestable.

### Do not add by default

Do not add merely for future possibility:

- web frameworks;
- production databases/ORMs;
- queue/event-bus infrastructure;
- background worker systems;
- microservices;
- caching;
- distributed locks/consensus;
- provider-independent “platform” abstractions with no second use;
- ML/RL/bandits;
- custom metrics/tracing stacks.

The agent is free to choose a better local implementation than this document could predict, provided it preserves verified boundaries/invariants and demonstrates correctness.

## 5. New-code quality rules

For new Ruby code:

- choose explicit domain names over generic `Manager`, `Helper`, `Service` unless the concept is genuinely that broad;
- keep side effects at clear boundaries;
- use exact money representation;
- make failure/outcome semantics explicit rather than relying on exceptions as business states;
- prefer composable objects/functions with narrow responsibilities;
- avoid metaprogramming unless it removes real complexity and remains easy to test/debug;
- avoid global mutable state for routing/allocation correctness;
- make concurrency-sensitive state transitions explicit and test them;
- keep adaptive scoring optional behind deterministic eligibility/safety logic;
- keep time/random/provider I/O injectable/controllable only where needed for deterministic tests;
- do not optimize allocations or object allocation based only on intuition—use constraints/benchmarks when performance matters.

Comments should explain invariants/reasons, not paraphrase obvious code.

## 6. Backlog protocol

`docs/BACKLOG.md` is the durable lightweight backlog. GitHub Issue #1 is a discussion/tracking surface.

Use the backlog for:

- active pre-TZ foundation work (`NOW`);
- work discovered during a task but outside scope;
- unanswered full-TZ questions (`BLOCKED`);
- post-TZ follow-up (`NEXT`);
- optional enhancements that need evidence before implementation (`LATER`).

Do not use it as a dumping ground for every idea or as a license to expand the current goal. `NOW` indicates priority but the active Goal/ExecPlan still defines the actual work slice.

## 7. Pre-TZ and full-TZ protocol

### Before the TZ

Do implement the stable foundation now:

- Ruby-only deterministic core;
- reference/oracle model;
- deep test/simulator harness;
- economic ownership/recovery semantics;
- count/volume allocation mechanics;
- minimal trace/projections;
- concurrency correctness tests;
- baseline performance measurements.

Do not harden guessed API/persistence/provider/UI semantics.

### When the official TZ arrives

1. snapshot/read it fully;
2. reconcile SPEC-001 item by item as `CONFIRMED`, `CHANGED`, `REMOVED`, `NEW`, `AMBIGUOUS`;
3. resolve the blocked questions in the backlog;
4. update provisional semantics and acceptance criteria;
5. update the independent reference model/oracles/tests first or in the same coherent change;
6. adapt dependent production code;
7. only then select newly justified external framework/persistence/API/integration architecture;
8. convert official load/scoring constraints into explicit test/performance gates.

Do not discard the pre-TZ foundation unless the official requirement genuinely invalidates it.

## 8. Evidence hierarchy

When uncertain, prefer evidence in this order:

1. direct task/user instruction;
2. official hackathon TZ/contracts;
3. repository specification and executable tests/reference model;
4. observed runtime/provider behavior;
5. official language/library/provider documentation;
6. well-established engineering references;
7. assumptions/heuristics.

Do not use a blog/heuristic to override an explicit product contract.

## 9. References

Canonical references live in `docs/RESEARCH.md` to avoid duplicating the knowledge base here.

RubyRouting intentionally adapts strict SpecOps for Goal Mode: low-risk reversible ambiguity should not block autonomous progress, while high-impact financial/product ambiguity must remain explicit and executable verification must be stronger than ordinary happy-path testing.
