# AGENTS.md

## Mission

Build **RubyRouting** as a high-quality smart payout-routing engine for a highly competitive hackathon.

Ruby is mandatory. Current v0.1 development baseline is **CRuby 4.0.6**. All product, routing, reference/oracle, simulator, property/model/concurrency test domain logic is Ruby.

The project uses lightweight SpecOps + autonomous Goal Mode: specification defines behavior; architecture/Ruby guide constrain implementation; tests/evidence verify it; roadmap/ExecPlan define sequencing; backlog stores work outside the active goal.

## Fresh project-wide read order

Use progressive disclosure. For a fresh long Goal Mode session read:

1. `README.md` — current state/map.
2. `docs/ROADMAP.md` — Project/Version/Phase/Slice goals and exit criteria.
3. `docs/exec-plans/active/` — actual current execution state.
4. `specifications/001-smart-payout-routing.md` — behavioral source of truth.
5. `docs/ARCHITECTURE.md` — concrete v0.1 implementation architecture and atomicity rules.
6. `docs/RUBY.md` — Ruby 4.0 engineering rules/tool choices.
7. `docs/TESTING.md` — deep verification strategy.
8. `docs/WORKFLOW.md` — SpecOps/Goal Mode operating loop.
9. `docs/PLANS.md` — living ExecPlan protocol.
10. `docs/SESSION_POLICY.md` — continuation/stop rules.
11. `docs/BACKLOG.md` — active/blocked/later work.
12. `docs/DECISIONS.md` — durable decisions and provisional assumptions.
13. `docs/RESEARCH.md` — external evidence when needed.

For a narrow local task, read only the governing subset after `AGENTS.md`.

## Source-of-truth precedence

For behavior:

`direct current instruction > official hackathon TZ > reconciled specification > current baseline specification > implementation`

`docs/ROADMAP.md` controls sequencing/version completion, not product semantics.

`docs/ARCHITECTURE.md` and `docs/RUBY.md` are the current implementation contract. They may be changed by evidence/official requirements, but do not casually redesign them during an ordinary slice.

`docs/TESTING.md` defines required evidence, not business semantics.

Code is not the spec. Never change requirements merely to justify accidental code.

## Current Version Goal

Unless repository state says otherwise, current version is **v0.1 — Pre-TZ Deterministic Foundation**.

Build now:

- plain Ruby project/test harness;
- independent Ruby reference/oracle model;
- exact count/volume allocation;
- economic intent/ownership/recovery kernel;
- deterministic provider simulator;
- property/state-machine/concurrency verification;
- facts/trace/replay/minimal projections;
- baseline benchmarks.

Do not wait for the full TZ.

Do not prematurely freeze:

- Rails/Sinatra/Hanami or another web framework;
- production DB/ORM;
- queue/event bus/job framework;
- microservices/deployment topology;
- final public API/UI;
- live provider SDK;
- ML/RL/bandits;
- external observability platform.

## Current architecture — do not redesign by default

v0.1 is:

- plain-Ruby modular monolith;
- root namespace `RubyRouting`;
- deterministic financial kernel;
- application orchestrator;
- ports/adapters at provider/time/external-state boundaries;
- one in-memory atomic coordinator guarded by a coarse `Thread::Mutex` initially;
- provider I/O always outside the coordinator critical section;
- facts + current projections, not mandatory full event sourcing;
- Minitest + Rake baseline harness;
- reference model in `test/support/reference` and independent from production algorithms;
- Threads/controlled interleavings for concurrency tests, not Ractor.

See `docs/ARCHITECTURE.md` for the exact commit/observation protocol.

## Non-negotiable financial invariants

These outrank optimization, allocation percentages, performance, and demo polish unless an authoritative TZ explicitly changes the safe semantics:

- One submitted payout is one **economic intent**, not one HTTP call.
- At most one unresolved money-moving **economic ownership** exists per intent.
- Timeout/lost response after possible provider acceptance is `UNKNOWN`, not confirmed failure.
- `UNKNOWN` does not release ownership.
- Cross-provider fallback starts only after previous ownership is safely released/proven incapable of the monetary effect.
- Same-provider retry, status resolution, fallback, reconciliation, and defer are distinct actions.
- Hard safety/eligibility constraints precede allocation/ranking.
- Allocation concurrency includes committed/in-flight assignments.
- Historical opportunity/decision/attempt/observation/settlement facts are not collapsed into one mutable provider/status field.
- Payout outcome and provider reliability attribution are separate.
- `NO_SAFE_ROUTE`/defer is valid.

Target semantic is effectively-once **economic effect**, not a false distributed exactly-once claim.

## Ruby-only policy

All executable domain logic is Ruby:

- production implementation;
- routing algorithms;
- oracle/reference model;
- provider simulator;
- property/model/concurrency harness;
- benchmark logic relevant to the domain.

Minimal YAML/shell/CI orchestration is allowed. Do not implement a second router/oracle in Python, JS/TS, Go, Java, Rust, etc.

Follow `docs/RUBY.md`.

Key rules:

- current development baseline CRuby 4.0.6;
- money = Integer minor units + explicit currency;
- exact ratios = integer weights/Rational, never Float;
- use immutable values and protect nested mutability;
- deterministic tie-breaking/order;
- no global mutable routing state;
- no global `rand` or hidden wall-clock reads in core decisions;
- Thread/Mutex synchronization is explicit; never rely on GVL;
- no provider I/O under the coordinator mutex;
- expected payout/provider outcomes are values, not broad exception flow;
- provider-specific statuses/errors normalize at adapter boundary.

## Goal Mode loop

For each non-trivial slice:

1. inspect governing spec, architecture/Ruby rules, current ExecPlan, relevant tests/code;
2. select the smallest coherent Slice Goal that advances current Version Goal;
3. state acceptance/invariants and verification needed;
4. implement autonomously;
5. run focused checks early;
6. run broader relevant verification;
7. self-review as a skeptical maintainer;
8. update Progress/discoveries/decisions only when reality changed;
9. select next required slice and continue.

Do not ask routine permission for reversible engineering choices.

## Long-session continuity

A file/class/test/commit/milestone/phase is a checkpoint, not a stop condition.

Continue:

`orient -> slice -> implement -> verify -> review -> update plan -> next slice`

Stop only when:

1. all active Version Goal exit criteria are satisfied; or
2. **every** remaining required path is blocked by a genuine external dependency outside the agent's control.

A failing test, difficult bug, local design choice, refactor, gem choice, or one blocked subtask while independent work remains is not an external blocker.

See `docs/SESSION_POLICY.md`.

## Ambiguity policy

- High confidence + reversible: choose the simplest spec/architecture-consistent option and proceed.
- Medium confidence + reversible: proceed conservatively; record only if later work depends on it.
- Low confidence/high impact: escalate only if it can change monetary safety, official acceptance semantics, irreversible data behavior, external/public compatibility, or another costly decision.

Investigate repository/tests/runtime/official docs before escalating.

## Anti-loop

- Never repeat an unchanged action expecting a different result.
- After two failures with essentially the same tactic, change hypothesis/tool/design.
- After three materially different failed approaches, reduce to a minimal reproducer, separate fact from assumption, simplify/replan, or document a real external blocker.
- Do not polish local aesthetics while higher-priority version criteria remain unmet.
- Stop rewriting correct code for subjective elegance.

## Scope discipline

The architecture is small intentionally. Add structure only when it:

- protects a confirmed invariant;
- isolates a real external boundary;
- removes proven meaningful duplication;
- materially improves deterministic testability;
- satisfies a confirmed requirement;
- addresses a measured bottleneck.

Do not add infrastructure/abstractions for hypothetical future use.

Do not scaffold every directory/class from `docs/ARCHITECTURE.md` in advance. Create the next files when the current vertical slice needs them.

## Critical atomicity rule

For provider assignment/fallback, the coordinator critical section must atomically establish correctness state before provider I/O:

- validate current payout/ownership state;
- evaluate/revalidate decision against current allocation snapshot;
- record decision fact;
- commit allocation reservation at the current accounting semantics;
- acquire economic ownership;
- publish revision/state.

Then release the mutex.

Only then call the provider.

Apply provider observations in a later synchronized transaction. `UNKNOWN`/unresolved `PENDING` keeps ownership. Confirmed safe failure may release ownership; only then may a fresh provider decision happen.

Never solve a test by moving network/provider calls inside the lock.

## SpecOps rules

- `specifications/` is authoritative for externally meaningful behavior/invariants.
- Behavioral code changes map to a requirement/acceptance rule or update the spec coherently.
- Never mutate the spec solely to match an implementation accident.
- Durable new domain rules are specified before being treated as established.
- Keep specs implementation-agnostic where possible.
- Do not litter production code with requirement IDs unless traceability materially benefits.

## Verification bar

`docs/TESTING.md` is mandatory methodology where relevant.

A financial/routing task is not complete merely because unit/happy-path tests pass or line coverage is high.

Use the applicable combination of:

- deterministic acceptance/regression tests;
- independent oracle comparison;
- property/invariant tests;
- state-machine/model tests;
- controlled concurrency/interleaving tests;
- deterministic provider fault simulation;
- duplicate/delayed/out-of-order observation tests;
- trace/replay/projection tests;
- stress/performance baselines.

Any material bug gets a deterministic regression. Randomized failures preserve seed/trace. Do not hide flaky tests with automatic retries.

## Backlog discipline

`docs/BACKLOG.md` is durable backlog. `NOW` means relevant to current pre-TZ version, not permission to expand any active slice. `LATER` is never implemented opportunistically.

If useful work is discovered but not necessary for the current goal, update an existing backlog item or add one concise item and continue current work.

## Completion report

State concisely:

- version/phase/slice advanced;
- behavior/architecture changed;
- requirements/invariants satisfied;
- tests/checks/seeds/benchmarks actually run;
- assumptions/blockers;
- spec/plan/backlog/decision updates.

Never claim verification that did not run.
