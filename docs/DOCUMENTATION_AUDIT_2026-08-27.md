# Documentation Audit — 2026-08-27

## Purpose

Second project-wide documentation audit after the v0.2 technical-review reset.

The objective is to ensure a fresh coding agent receives one coherent instruction set:

- current version is v0.2, not v0.1;
- pre-TZ work continues toward full generic routing logic;
- completion cannot be declared from green tests/checklists alone;
- mandatory full-core scope cannot be shrunk to match current implementation;
- legacy v0.1 documents remain useful only as inherited baseline/history where explicitly stated.

## Findings and resolution

### 1. Premature-completion loophole — RESOLVED

`SESSION_POLICY.md` originally said phases are not stop conditions, but version completion was still weak enough for an agent to mark a predefined phase list complete and stop without fresh repository-wide discovery.

Resolution:

- `docs/COMPLETION_POLICY.md` defines evidence-gated statuses and mandatory Version Closure Protocol;
- `docs/SESSION_POLICY.md` now requires `VERSION_CANDIDATE` before closure;
- `AGENTS.md` explicitly forbids “all done / wait for TZ” from green checklists/suites alone.

### 2. Active workflow reference was stale — RESOLVED

`WORKFLOW.md` referenced the archived v0.1 active plan.

Resolution: it now references `docs/exec-plans/active/pre-tz-comprehensive-core.md` and SPEC-001/002/003 precedence.

### 3. Testing authority still named only SPEC-001 — RESOLVED

The former `TESTING.md` opening authority line predated SPEC-002/003.

Resolution: `docs/TESTING.md` has been reconciled to current v0.2 scope, explicitly governed by SPEC-001/002/003 and the completion policy. Its verification layers now include dispatch, policy, capacity, health/ranking, replay, conflict/reversal and full cross-feature interaction evidence.

### 4. Architecture document is v0.1 provenance — RESOLVED BY EXPLICIT INHERITANCE

`ARCHITECTURE.md` deliberately describes the detailed v0.1 starting architecture. Most rules remain valid, but its version labels are historical provenance rather than the current Version Goal.

Resolution:

- `docs/CURRENT_ARCHITECTURE.md` is the current v0.2 architecture supplement;
- it inherits the modular-monolith/mutex/provider-I/O rules;
- it adds policy, operation dispatch, capacity, health, lifecycle reducer, replay, conflict/reversal and workflow responsibilities;
- D-032 records this inheritance model.

### 5. Ruby guide uses v0.1 labels in baseline sections — REVIEWED / NOT A CURRENT SEMANTIC CONFLICT

`RUBY.md` contains “v0.1” labels around runtime/tooling/concurrency choices. These choices remain intentionally inherited:

- CRuby 4.0.6 baseline;
- Minitest/Rake;
- Integer minor-unit money and Rational ratios;
- Thread/Mutex baseline;
- Ruby-only executable logic;
- provider I/O outside lock;
- deterministic time/random boundaries.

Fresh-agent current-version authority comes from AGENTS/ROADMAP/CURRENT_ARCHITECTURE. The Ruby guide's v0.1 labels describe provenance, not permission to stop at v0.1 scope.

### 6. “Supported scope” wording could allow scope shrink — RESOLVED

Earlier wording such as “supported generic pre-TZ scope” could be interpreted as permission to implement only a convenient subset.

Resolution:

- SPEC-003 fixes the mandatory v0.2 capability envelope;
- D-031 forbids implementation-defined scope reduction;
- ROADMAP now contains mandatory C1–C14 capability families;
- backlog P1-001 was expanded to the complete generic policy model;
- plans cannot move required work to LATER solely to obtain closure.

### 7. Green tests were over-weighted as closure evidence — RESOLVED

The v0.1 plan had strong recorded green local evidence, yet later source review found material untested interaction defects.

Resolution:

- green tests are explicitly necessary but insufficient;
- current TESTING distinguishes slice/phase evidence from version completion;
- closure requires source/spec reconciliation, capability sweep, unfinished-code discovery, red-team counterexamples, current full verification, backlog/blocker audit and docs audit.

### 8. Plans could self-close after original checklist — RESOLVED

A fixed phase list could become a hidden completion definition.

Resolution:

- `docs/PLANS.md` says plans cannot redefine/narrow the Version Goal;
- active plan remains open during `VERSION_CANDIDATE` closure;
- closure can reopen prior phases or create new slices;
- progress checkboxes are explicitly non-monotonic when evidence changes.

### 9. Pre-TZ scope was broad but not explicitly “full logic” — RESOLVED

Earlier v0.2 direction listed many mechanisms but still left room to treat some generic policy dimensions as optional.

Resolution: SPEC-003 and ROADMAP now require the coherent full generic domain envelope:

- lifecycle/dispatch safety;
- complete typed policy primitives;
- count/volume allocation;
- provider opportunity;
- live capacity;
- health/exposure;
- deterministic ranking;
- recovery/time/TTL/reconciliation;
- provider operation contracts;
- event reducer/order semantics;
- settlement/reversal/conflict;
- lifecycle replay;
- typed trace/analytics;
- controlled concurrency/cross-feature verification.

Unknown official thresholds/defaults become configurable semantics, not omitted concepts.

## Current documentation authority map

### Behavioral authority

1. direct current user instruction;
2. official hackathon TZ when available;
3. reconciled specification after TZ;
4. SPEC-003 current pre-TZ full-logic/completion contract;
5. SPEC-002 implementation-review amendments;
6. SPEC-001 baseline;
7. implementation/tests.

### Development/completion authority

- `AGENTS.md` — agent contract/read order;
- `docs/ROADMAP.md` — current Version Goal, mandatory C1–C14 envelope and exit criteria;
- `docs/COMPLETION_POLICY.md` — mandatory rules for claiming completion;
- `docs/SESSION_POLICY.md` — continuation/blocker rules;
- active ExecPlan — factual execution state;
- `docs/WORKFLOW.md` / `docs/PLANS.md` — operating/planning protocol.

### Architecture authority

- `docs/CURRENT_ARCHITECTURE.md` — current v0.2 supplement;
- `docs/ARCHITECTURE.md` — inherited detailed v0.1 baseline where not superseded;
- `docs/RUBY.md` — inherited/current Ruby implementation rules.

### Verification authority

- SPEC-001/002/003 acceptance/invariants;
- `docs/TESTING.md` current v0.2 verification catalog;
- active ExecPlan current required suites/regressions;
- `docs/COMPLETION_POLICY.md` closure evidence gate.

## Required fresh-agent interpretation

A fresh agent must understand:

1. v0.1 is historical checkpoint, not current end state;
2. v0.2 targets complete generic routing mechanics before TZ;
3. all SPEC-003/ROADMAP C1–C14 capability families are mandatory unless user/TZ/equivalent durable decision explicitly changes them;
4. P0 correctness precedes health/ranking/optimization, but later mandatory phases remain part of v0.2;
5. absence of TZ blocks final external semantics, not generic domain development;
6. a slice/phase cannot prove the whole version;
7. all originally planned phases being green means `VERSION_CANDIDATE`, not `VERSION_COMPLETE`;
8. closure is an active attempt to find missing behavior and may reopen earlier phases;
9. an important locally solvable discovery becomes new work, not “optional scope”;
10. full domain logic now is intentionally paired with minimal speculative infrastructure.

## Audit status

Current documentation is aligned around one vector:

**full generic payout-routing domain logic + deep verification before TZ; authoritative external integration and judged optimization after TZ.**

No active document should instruct a coding agent to stop because the v0.1 foundation or the originally known v0.2 phase list is green.
