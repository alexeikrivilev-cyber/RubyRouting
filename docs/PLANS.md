# Execution Plan Protocol

The current plan is `docs/exec-plans/active/pre-tz-adversarial-edge-hardening.md` for **v0.3.4 — Pre-TZ Adversarial Case Fidelity & Edge Hardening**.

`docs/ROADMAP.md` defines the Version Goal. `docs/COMPLETION_POLICY.md` defines completion. An ExecPlan cannot redefine either.

## Goal hierarchy

`Project Goal -> Version Goal -> Phase Goal -> Slice Goal`

Current Version Goal: **v0.3.4 — ACTIVE**.

v0.3.3/SPEC-007 is a completed protected baseline, not an active plan.

## Purpose of an ExecPlan

An ExecPlan is a living, self-contained implementation map that another stateless agent can continue from repository state alone.

It must describe observable outcomes, hypotheses, falsification, dependencies, risks and verification. It is not a task dump and not a requirement that every hypothesis change production code.

## Required plan sections

- Purpose / Big Picture
- Current Version Goal
- Governing sources
- Current repository evidence/findings
- Protected baseline
- Phase/Dependency plan
- Rolling Next Actions
- Verification matrix
- Independent skeptical closure phase
- Stop policy

## Planning rules

1. Keep 2–5 immediate next actions concrete.
2. Start v0.3.4 slices with a counterexample or measurement when the item is hypothesis-driven.
3. Keep phase outcomes authoritative, not guessed class/file shapes.
4. Reopen phases when new evidence finds a gap.
5. Do not preserve dead/experimental code as “future work” when removal improves current coherence.
6. Record material architectural discoveries immediately.
7. Treat the official TZ as an authority switch, not an excuse to stop generic work.
8. Treat backlog items as known hypotheses/work, not a closed universe of possible defects.
9. Do not refactor a verified v0.3.3 mechanism merely to make v0.3.4 appear active.

## Current plan requirements

The active plan must account for:

- financial safety and canonical routing flow;
- provider/fallback outcome analytics with explicit denominator semantics;
- duplicate recovery-consumer races;
- abrupt configuration-publication restart behavior;
- payout-local history completeness;
- measured analytics/explanation and due-work cost;
- exact replay parity for any new derived cache/index;
- count-versus-volume case composition;
- deep deterministic/property/model/concurrency/fault/restart verification;
- exact-case campaign and exact-HEAD CI.

## Plan completion versus version completion

When known mandatory work looks finished, set `VERSION_CANDIDATE` and run `docs/COMPLETION_POLICY.md`.

The closure stage must search for unplanned counterexamples from actual code rather than merely confirm the plan checklist. Any material locally solvable finding adds/reopens work and returns the version to ACTIVE.

Only a fresh skeptical pass with no material finding plus exact-HEAD verification permits `VERSION_COMPLETE`.

## Long-session continuation

After every verified slice:

1. record evidence and whether the hypothesis was falsified or required a fix;
2. scan adjacent layers for newly exposed case-relevant gaps;
3. choose the next highest-value required slice;
4. continue without routine confirmation.

Stop only under `docs/SESSION_POLICY.md`.