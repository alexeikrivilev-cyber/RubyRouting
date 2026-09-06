# Execution Plan Protocol

This file defines how substantial RubyRouting work is planned and how plans interact with version completion.

Current version sequencing lives in `docs/ROADMAP.md`. Completion authority lives in `docs/COMPLETION_POLICY.md`. Current substantial work lives in `docs/exec-plans/active/pre-tz-comprehensive-core.md`.

## 1. Purpose

An ExecPlan is a self-contained living implementation plan that another stateless coding agent can continue without chat history.

It describes how to reach the current Version Goal. It does **not** redefine the Version Goal and it cannot declare the version complete merely because its original checklist is exhausted.

## 2. Goal hierarchy

`Project Goal -> Version Goal -> Phase Goal -> Slice Goal`

- Project Goal is durable.
- Version Goal defines the complete current product capability and stop gate.
- Phase Goal groups dependent capabilities.
- Slice Goal is the next smallest independently verifiable unit.

A slice/phase may be added or reopened whenever new evidence exposes a missing capability.

## 3. When an ExecPlan is required

Use an active ExecPlan for work that is multi-slice, financially risky, concurrency-sensitive, architecture-changing, provider-integration-heavy or likely to span agent sessions.

Do not create one for a small obvious local change.

Active plans live under `docs/exec-plans/active/`. Completed historical plans may move to `docs/exec-plans/completed/` only after their own scope is genuinely historical.

## 4. Required plan properties

Every substantial plan must be:

- self-contained;
- outcome-focused;
- explicit about current Version/Phase/Slice Goal;
- aligned with governing SPEC-001/002/003 requirements;
- explicit about required verification layers;
- factual about current repository state;
- updated when discoveries/decisions change reality;
- small in rolling next actions while complete at the version-capability level;
- unable to silently narrow the version scope.

## 5. Required sections

### Purpose / Big Picture

What observable capability will exist and why it matters.

### Current Version Goal

Reference the authoritative roadmap; do not invent a competing completion definition.

### Governing requirements

Name relevant specification IDs and architecture/completion constraints.

### Progress

Use factual status only. Checkboxes represent implementation/verification progress, not proof of version completeness.

Allowed examples:

- `[x] Phase B behavior implemented and relevant suites green`
- `[ ] Phase B cross-feature closure review`

Do not write “all complete / wait for TZ” into Progress before version closure protocol passes.

### Rolling Next Actions

Normally 2–5 immediate actions derived from actual repository state.

### Surprises & Discoveries

Record evidence that changes understanding, including failing seeds, hidden coupling, new correctness gaps, performance behavior and spec ambiguity.

A new material discovery can reopen an earlier phase.

### Decision Log

Record durable material decisions, not routine code edits.

### Outcomes & Retrospective

At phase/version boundaries record what works and what evidence exists. Do not label a version outcome complete before closure protocol.

### Context and Orientation

Enough repository/domain context for a fresh agent.

### Plan of Work

Vertical verifiable slices, dependency reasoning, expected falsification/verification and current non-goals.

### Concrete Steps

Real canonical commands only. Never claim old output as current evidence.

### Validation and Acceptance

Map behavior to requirements and relevant test layers.

### Idempotence and Recovery

Explain safe reruns/rollback where provider/external/destructive behavior exists.

### Interfaces and Dependencies

Only current required dependencies/contracts. Keep speculative infrastructure out.

## 6. Plan completion versus version completion

These are different concepts.

A plan can reach the end of its originally imagined phases while the Version Goal remains incomplete because closure discovery found new work.

When all planned phases look green:

1. set version state to `VERSION_CANDIDATE`;
2. execute `docs/COMPLETION_POLICY.md` closure passes;
3. add/reopen slices for every newly found locally actionable gap;
4. return to `VERSION_CANDIDATE` only after those are implemented/verified;
5. declare `VERSION_COMPLETE` only after a fresh closure pass succeeds.

Therefore an ExecPlan must remain editable during closure. Do not archive it merely because the initial checklist reached the bottom.

## 7. Mandatory closure additions in active plan

Every version-level plan must contain a final closure phase that includes:

- source/spec reconciliation;
- SPEC-003 capability matrix sweep;
- repository TODO/placeholder/duplicate-semantics discovery;
- adversarial/red-team counterexample pass;
- full current verification;
- NOW/P0/P1 backlog audit;
- external-blocker classification;
- documentation consistency audit.

A checklist item for these passes is not enough: record actual findings/evidence.

## 8. No scope shrinking in plans

An ExecPlan may reorder/split/merge implementation slices, but may not remove required observable capability to make progress look complete.

Do not:

- move required P0/P1 work to `LATER` without authoritative evidence/user instruction;
- replace a required capability with a comment saying “TZ may define it” when a generic configurable model can be built now;
- rename unsupported behavior as “out of scope” without a durable governing decision;
- change acceptance semantics solely to match accidental production code.

## 9. Long-session continuation

After every verified slice:

1. update progress/evidence;
2. review for newly exposed gaps;
3. select the next highest-value current-version slice;
4. continue without routine permission.

Stop only under `docs/SESSION_POLICY.md` and `docs/COMPLETION_POLICY.md`.

## 10. Verification obligations

For payout-domain changes consider applicable evidence for:

- duplicate economic-effect prevention;
- dispatch/UNKNOWN semantics;
- primary vs recovery accounting;
- allocation discrepancy/conservation;
- policy identity/feasibility;
- opportunity/live feasibility;
- capacity reservation;
- provider health/exposure;
- fallback/recovery budgets;
- duplicate/out-of-order observations;
- conflict/reversal;
- replay stability;
- typed analytics;
- concurrency/interleavings.

One example test is insufficient when state/combinatorial/concurrency risk exists.

## 11. Anti-loop and replanning

After two similar failed approaches, change hypothesis/tactic. After three materially distinct failures, reduce to a minimal reproducer and simplify/replan.

A hard local bug is not an external blocker.

## 12. Relationship to backlog

The active plan owns current execution. `docs/BACKLOG.md` stores durable priority and future work.

Every NOW/P0/P1 item must be reconciled before v0.2 completion. A plan does not make a backlog requirement disappear by omitting it.

## 13. Completion report

A version-level plan may be archived only when:

- roadmap exit gate passes;
- completion closure protocol passes;
- current full verification evidence is recorded;
- newly discovered material defects have regressions;
- remaining work is truly TZ-blocked or optional post-core optimization;
- documentation is synchronized.

The standard is a demonstrably complete current Version Goal, not an exhausted edit list.
