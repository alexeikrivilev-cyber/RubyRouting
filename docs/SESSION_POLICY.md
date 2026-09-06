# Long-Session Goal Mode Policy

Current Version Goal: **v0.3.2 — Semantic Control Plane & Recovery Readiness**.

A long Goal Mode session continues until the current Version Goal is legitimately complete, the authoritative TZ arrives and forces reconciliation mode, or every remaining required path is genuinely externally blocked.

## Continuous execution rule

Repeat:

`orient -> inspect actual code -> choose highest-value unblocked slice -> establish acceptance -> implement -> verify -> skeptical review -> update plan/backlog -> discover next gap -> continue`

Do not stop after a file, issue, commit, milestone, phase, refactor, green suite, benchmark or demo.

## What is not a blocker

Do not stop for:

- missing official TZ;
- failing tests;
- difficult bugs/refactors;
- a reversible design choice;
- dependency selection that can be evaluated locally;
- completion of the original checklist;
- green CI;
- uncertainty resolvable through repository/code/tests/research;
- one blocked subtask while independent current-version work remains.

## Current priority discipline

Prefer work in this order unless actual dependencies prove otherwise:

1. preserve financial/economic safety;
2. canonical typed route context;
3. provider route compatibility and deterministic policy resolution;
4. recovery legality plus due-time scheduling;
5. active configuration versus pinned historical semantics;
6. route-aware/time-stale deterministic quality and fast-health telemetry;
7. one prepared-evaluation/live-restore semantic source;
8. admission semantic clarity;
9. dimension-safe analytics/configuration/due-work product queries;
10. deep verification and exact-revision closure;
11. demo polish only after semantic acceptance is green.

Do not add broad new features while a higher-priority semantic layer is inconsistent.

## After every verified slice

1. record current evidence;
2. inspect actual code for new coupling/gaps;
3. reconcile `docs/PRE_TZ_BACKLOG.md` and the active ExecPlan;
4. run broader risk-appropriate verification;
5. keep only a small set of rolling next actions;
6. select the next required slice and continue without asking for confirmation when it is derivable.

If all required phases look green, enter `VERSION_CANDIDATE` and execute `docs/COMPLETION_POLICY.md`; do not stop at the checklist.

## Genuine external blocker

A blocker is external only if:

1. a required capability depends on unavailable authoritative information/access/service;
2. ordinary engineering or reversible generic configuration cannot resolve it safely;
3. continuing would invent an incompatible external contract;
4. all independent required work is exhausted;
5. the blocker and affected exit criterion are documented precisely.

If the authoritative TZ arrives, that is not a blocker: switch immediately to `docs/TZ_RECONCILIATION.md` and continue under the new authority.

## Anti-loop

- after two similar failed approaches, change tactic;
- after three materially different failed approaches, reduce to a minimal reproducer and re-plan;
- never repeatedly patch symptoms without revisiting the semantic model;
- do not replace required product work with aesthetic cleanup;
- if one path is blocked, move to another independent current-version slice.

## Status discipline

Use `SLICE_IMPLEMENTED`, `SLICE_VERIFIED`, `PHASE_VERIFIED`, `VERSION_CANDIDATE`, `VERSION_COMPLETE`, `EXTERNALLY_BLOCKED`.

The phrase “wait for TZ” is invalid while SPEC-006 contains locally solvable required work.