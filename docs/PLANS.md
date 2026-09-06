# PLANS.md

This file defines the repository protocol for substantial execution plans. It is adapted for RubyRouting from OpenAI's current guidance on Codex ExecPlans and from the project's Goal Mode + SpecOps workflow.

An ExecPlan is a self-contained, living implementation plan that another stateless coding agent should be able to pick up and continue without relying on chat history.

Project-level sequencing and version exit criteria live in `docs/ROADMAP.md`. The current pre-TZ implementation plan is `docs/exec-plans/active/pre-tz-foundation.md` until completed or superseded.

## Goal hierarchy

Plans operate under this hierarchy:

`Project Goal -> Version Goal -> Phase Goal -> Slice Goal`

- The **Project Goal** is durable.
- The **Version Goal** defines the current complete outcome and stop gate.
- The **Phase Goal** groups dependent capabilities.
- The **Slice Goal** is the next small vertical unit that can be verified independently.

A long-running agent should keep only a small rolling set of immediate Slice Goals in the active plan rather than expanding the entire version into hundreds of microtasks.

## When an ExecPlan is required

Create an ExecPlan under `docs/exec-plans/active/<short-goal-name>.md` when the task is materially risky, multi-domain, long-running, architecture-changing, concurrency-sensitive, provider-integration work, or requires significant research/prototyping.

Do not create one for a small local change whose behavior and validation are obvious from the spec and code.

When work is complete, move the plan to `docs/exec-plans/completed/` if preserving it adds durable value. Disposable micro-plans do not need to be archived.

## Required properties

Every ExecPlan MUST be:

- self-contained enough for an agent unfamiliar with the current conversation;
- outcome-focused: it describes working observable behavior, not only files to edit;
- a living document updated as implementation proceeds;
- explicit about the active Version Goal and current Phase/Slice Goal for long work;
- explicit about assumptions, discoveries, and decisions;
- independently verifiable through concrete commands/scenarios;
- aligned with requirement/acceptance IDs from `specifications/`;
- explicit about which verification layers from `docs/TESTING.md` are required for the goal;
- minimal in local prescriptions while still delivering the requested goal end-to-end.

The executing agent should proceed through milestones autonomously instead of repeatedly asking for permission to continue. If a new ambiguity is safely reversible, record the assumption and continue. Escalate only under the ambiguity policy in `docs/WORKFLOW.md`.

## Long-session continuation

For a version-level ExecPlan, a completed slice/milestone/phase is a checkpoint, not plan completion.

After each verified slice:

1. update `Progress`, discoveries, decisions, and `Rolling Next Actions` if the plan has one;
2. run the relevant verification gate;
3. select the next required unblocked slice from the same Version Goal;
4. continue without asking for routine confirmation.

The plan may stop only when the version exit gate is satisfied or every remaining version path is genuinely externally blocked. `docs/SESSION_POLICY.md` defines the blocker test.

If one phase becomes externally blocked but another required phase can advance independently, continue with the independent work and record the dependency.

## Required sections

Use the following structure. Prose should carry the reasoning; checklists belong mainly in `Progress`.

# <Short action-oriented title>

State that the ExecPlan is a living document maintained according to `docs/PLANS.md`.

## Purpose / Big Picture

Explain what becomes possible after the change, why it matters, how a reviewer can observe the result, and which Version Goal this plan advances.

Reference governing requirement and acceptance-scenario IDs.

## Current Version Goal

For a long-running version-level plan, restate the observable version outcome and point to the authoritative exit criteria in `docs/ROADMAP.md`. Do not create a competing completion definition.

## Progress

Keep a timestamped checklist representing reality at the current moment.

Example:

- [x] (2026-08-27 10:00Z) Reproduced concurrent allocation overshoot with a focused test.
- [ ] Implement reservation-aware allocation state.
- [ ] Validate AC-004 and the full suite.

If a step becomes partially complete, split done versus remaining work instead of leaving an inaccurate checkbox.

## Rolling Next Actions

For multi-hour/version plans keep a short list, normally 2–5 immediate actions. Replace completed actions rather than endlessly appending future microtasks.

The list must be re-derived from actual repository state at the start of a fresh agent session.

## Surprises & Discoveries

Record evidence that changed understanding: unexpected provider behavior, performance characteristics, Ruby/library behavior, hidden coupling, test failures, failing property/model seeds, or spec ambiguity.

Use concise entries with evidence when available.

## Decision Log

Record material decisions while work proceeds.

Each entry should state:

- decision;
- rationale;
- date/author or agent identifier if useful;
- requirement/constraint affected.

Do not fill this with routine implementation details. Preserve decisions future agents would otherwise have to rediscover.

## Outcomes & Retrospective

At major milestones and completion, summarize what now works, what evidence proves it, remaining gaps, and lessons that should move to spec/architecture/testing/backlog/decisions.

## Context and Orientation

Describe relevant current repository state as if the reader knows nothing about the task. Name exact paths and define domain terms used by the plan.

Do not rely on chat history. Link repository-local source-of-truth files and restate task-specific assumptions required to act correctly.

## Plan of Work

Describe implementation path in narrative phases/milestones. Each should explain:

- what behavior is added or changed;
- which logical boundary/files are likely affected without prematurely freezing exact structure;
- why the approach preserves spec invariants;
- which verification layer(s) will falsify incorrect behavior;
- how the milestone is independently validated.

Prefer vertical, verifiable slices. Avoid broad scaffolding milestones that produce no working behavior.

A plan is allowed to merge, split, or reorder slices when evidence supports it. Record material replanning instead of following stale steps mechanically.

## Concrete Steps

List exact commands to run from repository root or named working directory once those commands actually exist, including focused tests, full tests, property/model tests, concurrency/fault suites, lint/static checks, local scenario commands, migrations, or simulator setup.

Show short expected results when that helps detect false success.

If randomized/property/model tests are used, specify how to reproduce failures by seed/trace.

Do not invent commands before tooling exists; the plan should be updated when the harness establishes canonical commands.

## Validation and Acceptance

Map validation explicitly to relevant requirement/acceptance IDs and `docs/TESTING.md`. Include failure-path tests, not only happy paths.

For payout-domain changes, consider whether the change needs evidence for:

- duplicate economic-effect prevention;
- timeout/UNKNOWN handling;
- concurrent ownership or allocation commitments;
- provider error normalization;
- fallback after safe failure;
- terminal payout failure preventing provider hopping;
- duplicate/out-of-order observations;
- allocation versus settlement accounting;
- policy infeasibility/deviation attribution;
- replay/projection stability.

Only include scenarios relevant to the change; do not mechanically create every test for every task.

A requirement is not complete merely because one example passes if state/combinatorial risk requires property/model/concurrency verification.

## Idempotence and Recovery

Explain whether implementation steps can be rerun safely. If a migration, external provider action, generated artifact, or destructive step can partially fail, describe a safe retry/rollback path.

For provider-facing behavior, explicitly distinguish technical retry idempotence from economic payout safety.

## Interfaces and Dependencies

Name interfaces, provider contracts, Ruby gems, external services, persistence semantics, or new dependencies the change requires, and explain why each is necessary now.

All executable product/reference/simulator/test domain logic remains Ruby. If a dependency is only speculative, remove it from the plan.

## Artifacts and Notes

Keep small evidence snippets or pointers useful for future continuation: important test output, failing seeds/traces, example payloads, measured behavior, or compact diff observations. Do not paste large logs or source files.

## Anti-loop and replanning

If the same approach fails twice without new evidence, update `Surprises & Discoveries`, re-evaluate the hypothesis, and change the plan before rerunning it. After three materially different approaches fail, reduce to the smallest reproducer, reject/downgrade unsupported hypotheses, and pursue a simpler approach or record a precise external blocker.

A difficult unresolved implementation problem is not itself a valid reason to stop a long session. Replan or move to another independent required slice where possible.

## Relationship to backlog

An ExecPlan represents the current goal/version. `docs/BACKLOG.md` represents active priorities and valuable future work.

When work is discovered that is not necessary for the active goal:

1. add or update one concise backlog item;
2. link evidence/requirement IDs if useful;
3. do not expand the ExecPlan to absorb it unless it blocks current acceptance.

`NOW` backlog items do not automatically enlarge an active plan; they are candidates for current/future slices only if they advance the Version Goal.

## Completion

Before closing a version-level ExecPlan:

- satisfy the authoritative version exit gate in `docs/ROADMAP.md`;
- run stated validation and relevant `docs/TESTING.md` quality gates;
- update governing specification if implementation taught a durable behavioral fact;
- update architecture/decisions/testing docs if a lasting design/verification choice changed;
- update backlog for unrelated remaining work;
- preserve meaningful regression tests and failing-seed reproductions;
- complete `Outcomes & Retrospective`;
- ensure Progress has no hidden current-version unfinished items;
- inspect final diff/project state for accidental scope growth;
- separate later-version improvements from genuine external blockers.

The standard is a demonstrably working version that conforms to the specification and survives relevant adversarial verification, not a plan whose edit checklist happens to be complete.

## Source

This protocol is intentionally based on OpenAI's current ExecPlan/harness guidance: self-contained living plans, explicit progress/discoveries/decisions/outcomes, repository-local state, depth-first verifiable building blocks, autonomous milestone execution, and prototypes only when they de-risk material uncertainty. See `docs/RESEARCH.md` for references.
