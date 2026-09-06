# Execution Plans

Substantial current work uses living ExecPlans governed by `docs/PLANS.md` and version sequencing from `docs/ROADMAP.md`.

Active plans live under `docs/exec-plans/active/`. When a completed plan contains durable implementation history worth retaining, move it to `docs/exec-plans/completed/`. Git does not preserve empty directories, so directories appear when the first plan is added.

Current active plan:

- `active/pre-tz-foundation.md` — deliver v0.1 Ruby-only deterministic foundation and deep verification harness while keeping TZ-dependent external architecture replaceable.

An active plan is the execution source for the current substantial version goal. Finishing a phase does not close the plan; it remains active until the version exit gate in `docs/ROADMAP.md` is satisfied or all remaining version work is genuinely externally blocked.

`docs/BACKLOG.md` contains other priorities and must not silently expand the active plan.
