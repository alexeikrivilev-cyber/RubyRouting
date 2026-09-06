# Execution Plans

Substantial current work uses living ExecPlans governed by `docs/PLANS.md`, version sequencing from `docs/ROADMAP.md`, and completion rules from `docs/COMPLETION_POLICY.md`.

## Current active plan

- `active/pre-tz-comprehensive-core.md` — deliver **v0.2 Pre-TZ Comprehensive Routing Core** across the full SPEC-003 capability envelope: P0 lifecycle/accounting corrections, policy/allocation/eligibility, capacity, deterministic health/ranking, recovery/time, replay/conflict/reversal, typed analytics and cross-feature verification.

## Completed checkpoint

- `completed/pre-tz-foundation.md` — historical v0.1 deterministic foundation and its recorded local evidence. It is a checkpoint, not the current execution contract or proof that pre-TZ development was complete.

## Plan lifecycle

A current version plan remains active through implementation **and** closure discovery.

When its originally planned phases are green, the plan is not immediately archived. The version becomes `VERSION_CANDIDATE` and the active plan records the closure/red-team passes required by `docs/COMPLETION_POLICY.md`.

If closure finds new important locally solvable work, add/reopen slices and continue. Only after `VERSION_COMPLETE` is earned may the plan move to `completed/`.

Finishing a file, phase, commit, issue list or green suite is never sufficient by itself.

`docs/BACKLOG.md` stores durable priority state. Every NOW/P0/P1 item must be reconciled before v0.2 closure; backlog items cannot be hidden merely because the active plan originally omitted them.
