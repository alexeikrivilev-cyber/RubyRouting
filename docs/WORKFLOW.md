# Goal Mode + SpecOps Workflow

## Purpose

This document defines how a coding agent executes RubyRouting work with high autonomy and strong financial correctness.

Current Version Goal: **v0.2 — Pre-TZ Comprehensive Routing Core**.

The official TZ is not available yet. Development continues on the complete generic routing logic defined by SPEC-001/002/003. External API/persistence/judge contracts remain replaceable.

## 1. Operating loop

For non-trivial work:

`Discover -> Specify -> Plan -> Implement -> Verify -> Review -> Reconcile -> Discover next gap`

The final discovery step is mandatory. A verified slice does not imply that the surrounding phase/version is complete.

### Discover

- Read `AGENTS.md`, `docs/ROADMAP.md`, `docs/COMPLETION_POLICY.md` and the active ExecPlan for project-wide work.
- Read the smallest governing SPEC-001/002/003 sections for the change.
- Inspect actual code/tests/reference/simulator before proposing structure.
- Identify behavior, invariants, concurrency boundaries and existing assumptions.
- Inspect current backlog/discoveries for interactions with the slice.
- Use official/current external documentation only when behavior depends on a versioned external contract/library.

### Specify

Before behavior-changing code, ensure desired behavior is explicit and testable.

- Durable domain rule -> update the governing specification if needed.
- Reversible low-impact ambiguity -> choose a conservative typed/configurable assumption.
- High-impact ambiguity involving money safety or authoritative external semantics -> investigate/escalate rather than inventing a contract.

SPEC-003 prevents scope shrink: unknown official defaults are normally represented as replaceable configuration, not omitted capability families.

### Plan

Small changes may use a short internal checklist. Complex/risky work updates the active ExecPlan.

Current plan:

`docs/exec-plans/active/pre-tz-comprehensive-core.md`

Use `docs/PLANS.md` for plan protocol.

A useful plan records:

- Version/Phase/Slice Goal;
- governing requirements;
- acceptance/invariants;
- verification layers;
- current-state evidence;
- implementation path;
- discoveries/decisions;
- rolling next actions;
- blockers/risks.

A plan is not allowed to make completion easier by narrowing the Version Goal around existing code.

### Implement

- Work in the smallest coherent vertical slice that produces observable behavior.
- Fix P0 correctness before “smart” optimization.
- Keep deterministic financial logic independent from provider transport/framework concerns.
- Normalize provider-specific semantics at the boundary.
- Keep all executable domain/reference/simulator/test logic Ruby-only.
- Make time/random/provider I/O deterministic where domain behavior depends on them.
- Add internal structure only when it protects an invariant, improves replay/testability or removes meaningful duplication.
- Do not add framework/database/queue/microservice/ML infrastructure without current evidence/TZ need.

### Verify

Verification proves behavior, not activity.

Use relevant layers from `docs/TESTING.md` and SPEC-003:

- unit/value tests;
- deterministic acceptance/regressions;
- independent oracle comparison;
- property/invariant tests;
- state-machine/model histories;
- controlled concurrency/interleavings;
- provider/transport fault simulation;
- duplicate/delayed/out-of-order event scenarios;
- replay equivalence;
- stress/benchmarks after correctness;
- fault/mutation seeding where valuable.

A focused green test proves its slice only. Run the smallest broader suite capable of exposing interaction regressions before marking a slice/phase verified.

Never claim an old or unavailable check passed.

### Review

Review changed code as a skeptical maintainer:

- Does it preserve one economic intent / ownership safety?
- Does it accidentally conflate primary allocation, recovery and settlement?
- Can hard eligibility/capacity/health be bypassed by ranking/allocation pressure?
- Are transport ambiguity and provider-operation semantics explicit?
- Is hidden mutable state bypassing facts/replay?
- Are event ordering rules actually justified?
- Are duplicate/late/concurrent paths covered?
- Is a provider/TZ assumption leaking into core behavior?
- Did production/reference implementations accidentally share the same algorithm?
- Did the change introduce unnecessary abstraction/infrastructure?

Fix material findings before advancing.

### Reconcile

After a slice:

- update active ExecPlan progress/evidence/discoveries;
- update specs/decisions only for real durable behavior;
- update backlog for discovered work outside the current slice but inside/later version;
- preserve deterministic regressions/seeds;
- ensure docs are not made stale by the change;
- select the next required slice immediately.

Do not stop simply because the originally selected task is done if the current Version Goal still has locally actionable work.

## 2. Status and completion discipline

Use `docs/COMPLETION_POLICY.md` status vocabulary.

Normal progression:

`SLICE_IMPLEMENTED -> SLICE_VERIFIED -> PHASE_VERIFIED -> ... -> VERSION_CANDIDATE -> closure audit -> VERSION_COMPLETE`

`VERSION_CANDIDATE` is not a ceremonial label. It triggers a fresh repository-wide attempt to disprove completeness.

The agent must not use “all done”, “nothing left”, or “wait for TZ” before closure protocol passes.

Green tests/checklists are necessary evidence but not proof that:

- all normative behavior exists;
- interactions are complete;
- no untested design flaw exists;
- no current-version backlog item remains;
- docs match code.

## 3. Mandatory closure discovery

When planned phases appear complete, perform the passes from `docs/COMPLETION_POLICY.md`.

At minimum:

1. reconcile source against SPEC-001/002/003 requirement by requirement;
2. inspect every mandatory SPEC-003 capability family and interaction;
3. search repository for TODO/FIXME/NotImplemented/placeholders/prose-parsing/duplicate semantics/untested public behavior;
4. perform deliberate adversarial counterexamples;
5. run current full verification;
6. review every NOW/P0/P1 item;
7. classify remaining work as locally actionable, true TZ-blocked or optional later;
8. audit documentation consistency.

Any material locally solvable finding reopens development. Phase checkboxes may move backwards or gain new slices.

## 4. Goal Mode autonomy

Proceed autonomously when choices are reversible and preserve governing semantics, including:

- local Ruby organization;
- tests/reference/simulator design;
- internal refactors that clarify invariant ownership;
- explicit conservative defaults for generic policy/health/budget configuration;
- standard-library/small dependency choices with low runtime risk;
- measured performance improvements preserving behavior.

Escalate only when proceeding would choose authoritative product semantics or create an irreversible external contract.

The unknown official TZ does not require escalation for generic capabilities already defined by SPEC-003.

## 5. Anti-loop protocol

### No identical retries without changed state

Repeat an action only after a meaningful fix/config/state change or to verify reproducibility.

### Change tactic after two similar failures

Reassess evidence/hypothesis/design instead of patching symptoms.

### Reduce after three distinct failures

Create the smallest reproducer, separate facts from assumptions, inspect authoritative evidence and choose a simpler route or document a real blocker.

### Prevent local fixation

Do not optimize style/one function while higher-priority Version Goal gaps remain.

### Do not optimize completion

Never respond to a difficult remaining requirement by weakening the requirement, moving it to `LATER`, or redefining the version around current implementation.

## 6. Full pre-TZ development rule

Before TZ, implement all mandatory SPEC-003 domain capability families.

Examples of unknowns that should become configuration rather than omissions:

- allocation window/tolerance;
- provider capacity limits;
- retry/switch/resolution budgets;
- health thresholds/cooldowns;
- provider priority/cost/latency inputs;
- timeouts/TTL where provider contract supports them.

Keep final API/storage/provider payload representation unfixed.

This is the intended balance:

**complete routing logic; minimal speculative infrastructure.**

## 7. Scope control

Add structure when earned by current behavior/invariants/testability/measurement.

Do not add by default:

- Rails/Sinatra/Hanami;
- production DB/ORM;
- queue/event bus/background jobs;
- microservices;
- distributed locks;
- final public API/UI;
- live vendor SDKs;
- custom observability platform;
- ML/RL/bandits.

## 8. Backlog protocol

`docs/BACKLOG.md` is durable priority state.

- `NOW` / P0 / P1: must be reconciled before v0.2 closure unless explicitly superseded.
- `BLOCKED`: genuinely official-TZ-specific unknowns.
- `NEXT`: post-TZ integration.
- `LATER`: optional optimization/evidence-driven work.

An agent may not move a current required item to `LATER` solely to close the version.

## 9. Official TZ transition

When the official TZ arrives:

1. read it fully;
2. move to roadmap v0.3;
3. classify SPEC-001/002/003 as `CONFIRMED/CHANGED/REMOVED/NEW/AMBIGUOUS`;
4. update reference/oracle/tests with semantic changes before or alongside production code;
5. adapt the core;
6. choose only now-justified API/framework/persistence/provider architecture;
7. turn official load/scoring constraints into executable gates.

Do not discard the v0.2 core unless authoritative requirements genuinely invalidate it.

## 10. Evidence hierarchy

When uncertain prefer:

1. direct current user instruction;
2. official TZ/contracts when available;
3. SPEC-003/002/001 and durable repository decisions;
4. executable reference/tests/current runtime evidence;
5. official language/provider/library documentation;
6. established engineering evidence;
7. assumptions/heuristics.

A heuristic never overrides a financial invariant or authoritative contract.
