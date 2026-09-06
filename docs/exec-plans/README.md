# Execution Plans

Substantial work uses living ExecPlans governed by `docs/PLANS.md`, version sequencing from `docs/ROADMAP.md` and completion rules from `docs/COMPLETION_POLICY.md`.

## Current pre-TZ plan

- `active/pre-tz-adversarial-edge-hardening.md` — **v0.3.4 Pre-TZ Adversarial Case Fidelity & Edge Hardening**, ACTIVE.

## Completed historical plans

- `completed/pre-tz-foundation.md` — v0.1 deterministic foundation.
- `completed/pre-tz-comprehensive-core.md` — v0.2 comprehensive-core checkpoint.
- `completed/pre-tz-skeptical-hardening.md` — v0.3.3 skeptical hardening closure.
- other completed checkpoints remain available through Git history and references.

## Plan lifecycle

Only the current execution authority belongs under `active/`.

A current plan remains living through implementation and skeptical closure discovery. When known phases appear green, enter `VERSION_CANDIDATE` and execute `docs/COMPLETION_POLICY.md`; any material locally solvable finding reopens implementation.

A v0.3.4 evidence-first hypothesis may close without production code change if adversarial evidence proves the inherited behavior already satisfies it.

Finishing a file, phase, commit, issue list, green suite or benchmark is never sufficient by itself.