# Execution Plan Protocol

The current v0.3.2 implementation and closure record lives in
`docs/exec-plans/active/pre-tz-semantic-control-plane.md`; it is
`VERSION_COMPLETE` pending the official-TZ authority switch.

`docs/ROADMAP.md` defines the Version Goal. `docs/COMPLETION_POLICY.md` defines completion. An ExecPlan cannot redefine either.

## Goal hierarchy

`Project Goal -> Version Goal -> Phase Goal -> Slice Goal`

The current Version Goal is v0.3.2 Semantic Control Plane & Recovery Readiness,
now `VERSION_COMPLETE` as a pre-TZ checkpoint.

## Purpose of an ExecPlan

An ExecPlan is a living, self-contained implementation map that another stateless agent can continue from repository state alone.

It must describe observable outcomes, dependencies, risks and falsification/verification. It is not a task dump and not a license to declare completion when its original tasks are exhausted.

## Required plan sections

- Purpose / Big Picture
- Current Version Goal
- Governing specifications/architecture
- Current repository evidence
- Progress
- Rolling Next Actions
- Surprises & Discoveries
- Decision Log
- Context and Orientation
- Plan of Work
- Concrete verification commands
- Validation / acceptance
- Idempotence / recovery where relevant
- Interfaces / dependencies
- Closure / red-team phase

## Planning rules

1. Keep 2–5 immediate next actions concrete.
2. Keep the full phase map outcome-oriented rather than dictating every class/file.
3. Reopen phases when new evidence finds a gap.
4. Do not move required work to later merely to produce a clean checklist.
5. Do not preserve dead/experimental code as a “future phase” when removal improves current product coherence.
6. Record material architectural discoveries immediately.
7. Keep official-TZ unknowns replaceable; do not make them excuses for missing generic mechanisms.

## Product-convergence plan requirements

The active plan must continuously account for:

- canonical pipeline cohesion;
- financial safety;
- internal coordinator decomposition without losing atomicity;
- policy/allocation semantics;
- admission state;
- constrained optimization;
- provider lifecycle/reconciliation;
- restart-safe durability;
- analytics/audit;
- application/API/demo boundaries;
- repository cleanup;
- deterministic deep verification and load evidence.

## Plan completion versus version completion

When the original plan looks finished, move to `VERSION_CANDIDATE` and run `docs/COMPLETION_POLICY.md`.

Closure discovery may create new slices or reopen old phases. Only a fresh successful closure pass permits `VERSION_COMPLETE`.

## Long-session continuation

After every verified slice:

1. record evidence;
2. scan for newly exposed product gaps;
3. choose the next highest-value slice;
4. continue without routine confirmation.

Stop only under `docs/SESSION_POLICY.md`.
