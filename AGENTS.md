# AGENTS.md

## Mission

Build **RubyRouting** as a high-quality smart payout-routing engine for a highly competitive hackathon.

Ruby is mandatory. Current development baseline is **CRuby 4.0.6**. All product, routing, reference/oracle, simulator, property/model/concurrency/fault executable domain logic is Ruby.

The current Version Goal is **v0.2 — Pre-TZ Comprehensive Routing Core**.

The official TZ is not available yet. That is not a reason to stop locally actionable development. The pre-TZ objective is to implement the complete high-value generic payout-routing logic that can be specified and verified without inventing external API/persistence/judge contracts.

## Mandatory fresh-session read order

For project-wide work read:

1. `README.md`
2. `docs/ROADMAP.md`
3. `docs/COMPLETION_POLICY.md`
4. `docs/exec-plans/active/pre-tz-comprehensive-core.md`
5. `specifications/001-smart-payout-routing.md`
6. `specifications/002-pre-tz-comprehensive-core.md`
7. `specifications/003-pre-tz-full-logic-and-completion.md`
8. `docs/TECH_REVIEW_2026-08-27.md`
9. `docs/CURRENT_ARCHITECTURE.md`
10. `docs/ARCHITECTURE.md` for inherited detailed baseline rules
11. `docs/RUBY.md`
12. `docs/TESTING.md`
13. `docs/WORKFLOW.md`
14. `docs/PLANS.md`
15. `docs/SESSION_POLICY.md`
16. `docs/BACKLOG.md`
17. `docs/DECISIONS.md`
18. `docs/DOCUMENTATION_AUDIT_2026-08-27.md`
19. `docs/RESEARCH.md` when external evidence is needed.

For a narrow local task, load only the governing subset after this file, but never ignore the active Version Goal and completion policy.

## Source-of-truth precedence

For behavior before the official TZ:

`direct current instruction > official hackathon TZ when available > reconciled specification > SPEC-003 > SPEC-002 > SPEC-001 > implementation/tests`

The official TZ does not yet exist in the repository. Never invent it or describe provisional choices as official requirements.

`docs/ROADMAP.md` controls version sequencing and exit gates. `docs/COMPLETION_POLICY.md` controls whether an agent may claim the version is complete. `docs/CURRENT_ARCHITECTURE.md` supplements the inherited v0.1 architecture. `docs/TESTING.md` defines detailed evidence methodology.

Code is not the spec. Tests are not the entire spec. A green suite does not authorize scope reduction.

## Current development vector

Do **not** restart the architecture. Keep:

- plain-Ruby modular monolith;
- deterministic financial/routing kernel;
- exact money;
- application orchestration outside pure routing functions;
- one clear in-memory atomic coordinator boundary under `Thread::Mutex` for current correctness state;
- provider I/O outside the mutex;
- append-preserved typed facts + replayable derived projections;
- independent Ruby oracle/simulator;
- Minitest/Rake and controlled concurrency tests.

The v0.2 goal is full domain logic, not enterprise infrastructure.

Internal coordinator responsibilities may be factored into ledgers/reducers when current mechanics justify it. Do not convert them into services, DB tables, queues or generic frameworks without evidence.

## Mandatory v0.2 capability families

SPEC-003 fixes the capability envelope. A fresh agent may not narrow it to the already convenient subset.

Implement and integrate:

1. economic intent/ownership and operation dispatch safety;
2. count and volume allocation with exact post-decision discrepancy and committed work;
3. policy identity/fingerprint, scope, accounting/window/tolerance and generic hard/soft constraints;
4. context-aware functional opportunity/eligibility;
5. live availability and deterministic capacity reservations;
6. attributable provider health, hysteresis/quarantine/probing;
7. deterministic ranking inside the already safe feasible set;
8. retry/status-resolution/fallback/defer/reconciliation with separate budgets/time/TTL;
9. duplicate/delayed/out-of-order lifecycle reduction;
10. settlement, reversal and economic-conflict handling;
11. full lifecycle replay from facts;
12. typed decision trace, deviation attribution and primary/recovery/settlement analytics;
13. controlled concurrency and cross-feature adversarial verification.

Unknown official values/defaults should become replaceable typed configuration, not omitted concepts.

Do not implement adaptive ML/bandits while deterministic lifecycle/accounting/full-core gaps remain.

## Priority order

Unless evidence changes dependencies:

1. P0 financial correctness and regressions;
2. operation dispatch/provider-contract/replay correctness;
3. policy/eligibility/accounting completeness;
4. capacity correctness;
5. deterministic health/ranking;
6. recovery/time/reconciliation;
7. typed trace/analytics;
8. deep cross-feature verification and maintainability/performance hardening;
9. closure/red-team audit.

## Non-negotiable financial invariants

These outrank allocation targets, ranking, performance and demo polish:

- One payout is one **economic intent**.
- At most one unresolved money-moving **economic ownership** exists per intent.
- A timeout/lost response after possible transmission is `UNKNOWN` unless the contract proves no provider side effect.
- `UNKNOWN` retains ownership.
- Cross-provider fallback requires safe release/proof the previous operation cannot create the effect.
- Same-provider retry/status lookup is distinct from fresh fallback.
- Fresh fallback excludes already money-moving attempted providers by default.
- Primary allocation accounting and recovery traffic are distinct under the current `primary_assignment` default.
- Hard safety/eligibility/capacity/health constraints precede allocation/ranking.
- Operation recovery capability is operation-scoped and survives new-route disablement.
- Ownership alone does not authorize premature retry/resolve while original dispatch is still in progress.
- Transport ambiguity is classified economically, not hidden in generic exceptions.
- Historical observations remain facts; chronology is not guessed from arbitrary status rank.
- Late evidence of a second possible monetary effect creates an explicit reconciliation/conflict signal.
- Provider outcome attribution is separate from payout business outcome.
- `NO_SAFE_ROUTE`, defer and reconciliation-blocked are valid.

Target behavior is effectively-once **economic effect**, not a false distributed exactly-once claim.

## Critical atomicity rule

Before a new provider money-moving call, the atomic state boundary establishes all correctness state required by the configured model, including as applicable:

- current payout/operation legality;
- pinned policy identity/fingerprint;
- provider opportunity/live feasibility;
- primary allocation reservation at the configured accounting point;
- capacity reservation;
- decision/fact identity;
- economic ownership;
- operation/provider-contract snapshot;
- dispatch phase.

Release the mutex before provider I/O.

Apply dispatch evidence/provider observations later under synchronization. Never fix a race by moving provider/network I/O inside the lock.

## Ruby-only policy

All executable domain logic is Ruby:

- production implementation;
- routing/allocation/recovery/health algorithms;
- oracle/reference model;
- provider simulator;
- property/model/concurrency/fault harness;
- domain benchmarks.

Minimal CI/shell/YAML orchestration is allowed. Do not build a second router/oracle in another language.

Follow `docs/RUBY.md`:

- CRuby 4.0.6 current baseline;
- money = `Integer` minor units + explicit currency;
- proportions/discrepancy = integer weights / `Rational`, never Float;
- deterministic ordering/tie-breaking;
- explicit controlled time/randomness;
- no accidental global mutable correctness state;
- never rely on GVL for correctness;
- no provider I/O under coordinator mutex;
- expected provider/business outcomes are domain values, not broad exception control flow.

## Goal Mode loop

For each slice:

1. inspect governing spec/current plan/tests/code;
2. choose the smallest slice advancing the current phase/version gate;
3. state invariants/acceptance and the verification capable of falsifying the approach;
4. implement autonomously;
5. run focused checks early;
6. run relevant broader suites;
7. self-review skeptically for safety, accounting, concurrency, provider/TZ assumptions and unnecessary complexity;
8. update the active ExecPlan when reality/discoveries change;
9. select the next required slice and continue.

A test/file/commit/milestone/phase is a checkpoint, not a stop condition.

## Anti-premature-completion rule

`docs/COMPLETION_POLICY.md` is mandatory.

The agent MUST NOT say the active version/project is `done`, `complete`, `finished`, `all implemented`, `nothing left`, or `waiting for TZ` merely because:

- all planned checkboxes are marked complete;
- the full test suite is green;
- a benchmark is acceptable;
- every known issue at session start was fixed;
- one closure checklist from an earlier plan passed.

Before any version-complete claim:

1. mark status `VERSION_CANDIDATE`, not complete;
2. perform a fresh source/spec reconciliation;
3. sweep the full SPEC-003 capability matrix and interactions;
4. search the repository for unfinished/placeholder/duplicated semantics;
5. perform an adversarial/red-team attempt to find new counterexamples;
6. re-run current verification from changed code;
7. audit every NOW/P0/P1 item and blocker;
8. audit documentation consistency;
9. return to development if any important locally solvable gap is found.

Completion discovery is allowed to reopen any earlier phase. Do not preserve a neat checklist at the expense of correctness.

## No scope shrinking

Do not make completion easier by redefining the current version around what is already implemented.

Without explicit user or authoritative TZ evidence, do not:

- move unfinished required SPEC-003 behavior to `LATER`;
- relabel a P0/P1 correctness/full-logic gap as optional;
- use “supported subset” to avoid a required capability family;
- change a normative requirement only because production code chose a narrower design.

If a planned mechanism is fully subsumed by a simpler implementation, record the decision and prove equivalent observable behavior.

## Stop / blocker policy

Stop only when:

1. `VERSION_COMPLETE` is legitimately reached under `docs/COMPLETION_POLICY.md`; or
2. every remaining required current-version path passes the genuine external-blocker test.

The absence of the official TZ is **not** a blocker for v0.2 generic mechanics.

Failing tests, difficult bugs, refactors, gem choices, unclear local class boundaries, or one blocked subtask while independent work remains are not external blockers.

## Anti-loop

- Do not repeat unchanged actions expecting a different result.
- After two failures with the same tactic, change hypothesis/tool/design.
- After three materially different failures, reduce to a minimal reproducer, separate facts from assumptions and simplify/replan.
- Do not polish local aesthetics while higher-priority correctness/version criteria remain unfinished.
- Do not rewrite correct code solely for subjective elegance.

## Scope discipline

Implement all important generic routing mechanics that can survive TZ changes, but do not equate comprehensive domain logic with infrastructure bloat.

Add structure only when it protects an invariant, isolates a real boundary, removes meaningful duplication, improves deterministic testability, satisfies a current requirement or addresses a measured bottleneck.

Do not add by default:

- Rails/Sinatra/Hanami;
- production DB/ORM;
- queue/event bus/background-job system;
- microservices;
- distributed lock product;
- final public API/UI;
- live vendor SDK;
- observability platform;
- ML/RL/bandits.

## SpecOps rules

- SPEC-001 = baseline behavior.
- SPEC-002 = implementation-review amendments.
- SPEC-003 = mandatory current pre-TZ full-logic and completion envelope.
- Behavioral changes map to a requirement/acceptance rule or update the governing spec coherently.
- Never change a spec only to bless accidental implementation behavior.
- Keep official-TZ unknowns explicit and replaceable.
- When the TZ arrives, perform explicit `CONFIRMED/CHANGED/REMOVED/NEW/AMBIGUOUS` reconciliation.

## Verification bar

A slice is not complete because its happy path/unit test passes. Use relevant combinations of:

- deterministic regression/acceptance scenarios;
- independent oracle comparison;
- property/invariant generation;
- state-machine/model histories;
- controlled concurrency/interleavings;
- deterministic transport/provider faults;
- duplicate/delayed/out-of-order event tests;
- lifecycle replay equivalence;
- fault/mutation seeding where valuable;
- benchmarks/stress after correctness.

Every material bug gets a deterministic regression. Generated failures preserve seed/trace. Do not hide flakes with automatic retries.

Old green runs are historical evidence only. Changed code requires current verification.

## Completion report

Report the narrowest status actually supported by evidence.

For a version-complete claim include:

- exact revision reviewed;
- exit-criteria result;
- SPEC-001/002/003 reconciliation;
- commands/suites/seeds/CI/benchmarks actually run;
- closure/red-team findings;
- regressions added during closure;
- remaining genuine TZ blockers;
- optional later work;
- documentation consistency result.
