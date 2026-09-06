# Long-Session Goal Mode Policy

Current Version Goal: **v0.3.4 — Pre-TZ Adversarial Case Fidelity & Edge Hardening — ACTIVE (REOPENED)**.

A long Goal Mode session continues until the current session Goal and required verification are satisfied, the authoritative TZ forces reconciliation mode, or every remaining mandatory path is genuinely externally blocked.

## Continuous execution rule

Repeat:

`orient -> inspect exact code -> choose highest-risk hypothesis -> deterministic reproduce/falsify -> implement minimal fix if needed -> focused verify -> broad verify -> skeptical adjacent review -> update plan/backlog -> continue`

Do not stop after a file, test, commit, phase, green suite or one closed hypothesis.

## Current session priority

The next coding session has one P0 Goal:

**Prove and enforce single-live-provider-interaction ownership for one committed recovery operation across concurrent workers and concurrent duplicate/stale observations, without weakening UNKNOWN/fallback/restart safety.**

Order:

1. deterministic blocked `resolve` + duplicate observation + second `resume` reproducer;
2. equivalent idempotent retry/stale-observation cases;
3. minimal invocation-owned token/generation fix only if reproduced;
4. adapter-failure/completion/restart regressions;
5. focused concurrency/recovery/fault/restart verification;
6. full test/property/model/concurrency/fault matrix;
7. fresh skeptical review of the changed token lifecycle;
8. documentation/evidence reconciliation;
9. `VERSION_CANDIDATE` only if no material P0/P1 remains.

Do not add broad speculative features while this P0 is unresolved.

## Evidence-first rule

A backlog item closes only when the adversarial test either falsifies current behavior and the fix is verified, or proves the current implementation already satisfies the requirement. Do not manufacture production changes for a falsified hypothesis.

## After every verified slice

1. record exact evidence and revision;
2. inspect adjacent production paths for newly exposed coupling;
3. reconcile backlog/ExecPlan/decisions;
4. run broader risk-appropriate verification;
5. continue to the next requirement without routine confirmation.

## Mandatory candidate stage

When all known P0/P1 appear green, set `VERSION_CANDIDATE`, not complete.

Run the independent skeptical protocol against the changed implementation. Specifically challenge interaction token ownership/release, duplicate recovery workers, restart, UNKNOWN/fallback, stale observations, config crash, analytics/cache parity and exact-case composition.

Any material locally solvable finding returns v0.3.4 to ACTIVE, even after an earlier closure publication.

## What is not a blocker

Do not stop for missing official TZ, failing tests, difficult bugs, reversible design choices, green CI, one blocked subtask while independent work remains, or the need to reopen a phase after new evidence.

## Genuine external blocker

A blocker is external only if a mandatory capability depends on unavailable authoritative information/access/service, ordinary engineering cannot resolve it safely, proceeding would invent an incompatible contract, all independent mandatory work is exhausted, and the exact blocker is documented.

## Anti-loop

- after two similar failed approaches, change tactic/hypothesis;
- after three materially different failed approaches, reduce to a minimal reproducer and re-plan;
- never repeatedly patch symptoms without revisiting the semantic model;
- do not replace required product work with aesthetic cleanup;
- if one path is blocked, move to another independent required slice.

## Status discipline

Use `SLICE_IMPLEMENTED`, `SLICE_VERIFIED`, `PHASE_VERIFIED`, `VERSION_CANDIDATE`, `VERSION_COMPLETE`, `EXTERNALLY_BLOCKED`.

`VERSION_COMPLETE` is forbidden while any material locally solvable finding remains or active normative docs disagree.
