# Long-Session Goal Mode Policy

Current Version Goal: **v0.3 — Product Convergence & Full Routing Product**.

A long Goal Mode session continues until the current Version Goal is legitimately complete or every remaining required path is genuinely externally blocked.

## Continuous execution rule

Repeat:

`orient -> choose highest-value slice -> implement -> verify -> skeptical review -> update plan -> discover next gap -> continue`

Do not stop after a file, issue, commit, milestone, phase, refactor, green suite, benchmark or demo.

## What is not a blocker

Do not stop for:

- missing official TZ;
- failing tests;
- difficult bugs/refactors;
- a reversible design choice;
- dependency selection that can be evaluated locally;
- completion of the original plan/checklist;
- green CI;
- uncertainty that can be resolved through code/tests/research;
- one blocked subtask while independent product work remains.

The project now explicitly aims to build the nearly finished product before the TZ.

## Current priority discipline

Prefer work in this order unless dependencies prove otherwise:

1. financial safety/correctness;
2. product cohesion and single-source semantics;
3. architecture boundaries that protect invariants;
4. policy/allocation/admission correctness;
5. recovery/reconciliation/durability;
6. constrained smart optimization;
7. analytics/application surface;
8. deep verification/performance;
9. demo polish.

Do not add broad new features while a higher-priority layer is inconsistent.

## After every phase

1. record current evidence;
2. inspect actual code for new coupling/gaps;
3. reconcile backlog and active plan;
4. run broader relevant verification;
5. select the next required slice and continue.

If all known phases look green, enter `VERSION_CANDIDATE` and execute `docs/COMPLETION_POLICY.md`; do not stop.

## Genuine external blocker

A blocker is external only if:

1. a required capability depends on unavailable authoritative information/access/service;
2. ordinary engineering or reversible generic configuration cannot resolve it safely;
3. continuing would invent an incompatible external contract;
4. all independent required work is exhausted;
5. the blocker is documented precisely.

## Anti-loop

- after two similar failed approaches, change tactic;
- after three materially different failed approaches, reduce to a minimal reproducer and re-plan;
- never repeatedly patch symptoms without revisiting the model;
- do not replace product work with aesthetic cleanup.

## Status discipline

Use `SLICE_IMPLEMENTED`, `SLICE_VERIFIED`, `PHASE_VERIFIED`, `VERSION_CANDIDATE`, `VERSION_COMPLETE`, `EXTERNALLY_BLOCKED`.

The phrase “wait for TZ” is invalid while product-convergence work remains.
