# Long-Session Goal Mode Policy

This document defines when a long-running RubyRouting coding session continues, when it may stop, and how a version-complete claim is earned.

`docs/ROADMAP.md` defines the current Version Goal. `docs/COMPLETION_POLICY.md` is authoritative for version-completion evidence. The active ExecPlan records current execution state.

## Continuous execution rule

For a long-running Goal Mode session, finishing a slice, milestone, phase, commit, refactor, benchmark or currently known issue list is not a reason to stop.

Repeat:

`orient -> select slice -> implement -> verify -> review -> update plan -> discover next gap -> select next slice`

until either:

1. the current version passes the full Version Closure Protocol; or
2. every remaining required current-version path passes the genuine external-blocker test.

## Status discipline

Use the status vocabulary from `docs/COMPLETION_POLICY.md`.

A phase becoming green means `PHASE_VERIFIED`, not `VERSION_COMPLETE`.

When all planned phases appear green, the next state is `VERSION_CANDIDATE`. The agent must then perform a fresh closure/discovery pass. If that pass finds a material locally solvable gap, the version immediately returns to active implementation.

## What is not a blocker

Do not stop for:

- a failing test;
- an implementation bug;
- a difficult refactor;
- a reversible design choice;
- an ordinary dependency/tool decision;
- uncertainty resolvable from repository/runtime/research/engineering judgment;
- completion of one or all previously listed phases;
- a green full suite by itself;
- desire to ask whether to continue;
- a blocked subtask when independent current-version work remains;
- absence of the official TZ while generic v0.2 mechanics remain implementable;
- the fact that a capability's exact official threshold/default is unknown when it can be expressed as replaceable configuration.

## What the agent must do after every phase

After a phase is verified:

1. update actual progress/evidence;
2. inspect the next dependency in the roadmap;
3. scan discoveries/backlog for newly exposed gaps;
4. run the broader checks appropriate to the changed behavior;
5. continue to the next required slice.

Do not convert a phase exit into a session exit.

## Genuine external blocker

A blocker is external only when all are true:

1. the missing capability is required by the current version;
2. progress depends on unavailable authoritative information/access/service outside the agent's control;
3. ordinary investigation or a reversible generic model cannot resolve it safely;
4. proceeding would require inventing an external contract or making an irreversible incompatible choice;
5. no independent required current-version work remains;
6. the exact blocker and affected exit criterion are recorded.

Before declaring a blocker:

- identify the exact requirement/exit criterion;
- show what was investigated;
- inspect SPEC-003 to ensure the missing item is not a required generic capability;
- inspect NOW/P0/P1 backlog;
- check whether another slice can advance the version;
- record the blocker only if all independent work is exhausted.

## Version closure is a separate phase

Planned implementation phases being complete triggers closure review, not completion.

A closure attempt must perform all passes in `docs/COMPLETION_POLICY.md`, including:

- source/spec reconciliation;
- full capability matrix sweep;
- repository unfinished-code discovery;
- adversarial/red-team counterexample search;
- current full verification;
- backlog/blocker audit;
- documentation consistency audit.

Closure review is expected to find issues occasionally. Finding a new important issue is not a closure failure to hide; it is useful evidence that the version was not complete yet. Add a regression/slice and continue.

## No premature “wait for TZ” state

The phrase “wait for TZ” is valid only after v0.2 is `VERSION_COMPLETE` or the official blocker test proves that every remaining required v0.2 path truly needs authoritative external information.

It is invalid while locally solvable work remains in areas such as:

- lifecycle/ownership/dispatch;
- allocation/policy constraints;
- eligibility/opportunity;
- capacity;
- deterministic health/ranking;
- recovery/time/TTL;
- replay/conflict/reversal;
- analytics/trace;
- concurrency/fault/property/model verification.

## Version-complete report

Do not report “all done” without the evidence required by `docs/COMPLETION_POLICY.md`.

If only a slice/phase is proven, report that narrower status and continue.
