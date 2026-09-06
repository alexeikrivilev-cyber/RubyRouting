# Long-Session Goal Mode Policy

This document is intentionally short. `docs/ROADMAP.md` contains the project/version phases; `docs/exec-plans/active/` contains current execution state.

## Continuous execution rule

For a long-running Goal Mode session, finishing a slice, milestone, phase, commit, or local refactor is not a reason to stop.

The agent continuously repeats:

`orient -> select slice -> implement -> verify -> review -> update plan -> select next slice`

until the current version's exit gate is satisfied or a genuine external blocker prevents every remaining path required by that version.

## What is not a blocker

Do not stop for:

- a failing test;
- an implementation bug;
- a reversible design choice;
- an ordinary dependency/tool decision;
- uncertainty that can be investigated from repository/runtime/official documentation;
- completion of one milestone;
- desire to ask whether to continue;
- desire to polish already-correct code;
- a blocked subtask when independent current-version work remains.

Use the anti-loop/replanning rules in `AGENTS.md`, `docs/WORKFLOW.md`, and `docs/ROADMAP.md` instead.

## Genuine external blocker

A blocker is external only when required progress depends on unavailable information, access, authorization, or service outside the agent's control, and no independent work needed for the current version remains.

Before declaring a blocker:

1. identify the exact version exit criterion affected;
2. show what evidence/search/debugging was attempted;
3. check whether another slice can advance the same version;
4. record the blocker in the active ExecPlan/backlog;
5. stop only if the remaining version work cannot progress without it.

## Version completion

The active version is complete only when its explicit exit criteria in `docs/ROADMAP.md` and the active ExecPlan are satisfied and relevant verification is green.

At version completion:

- run the project-wide closure review;
- update spec/docs/plan/backlog/decisions to match actual state;
- record outcomes and remaining external/later-version work;
- move/close the active ExecPlan if appropriate;
- then the session may stop.
