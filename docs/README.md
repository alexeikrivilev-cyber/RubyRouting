# Documentation Authority Index

This index exists because the repository intentionally preserves historical specifications, architecture and decision records. File names containing `CURRENT` or old version numbers are historical unless listed below as active authority.

## ACTIVE before authoritative TZ

Read in this order for substantial development:

1. `../README.md`
2. `../AGENTS.md`
3. `../specifications/008-pre-tz-adversarial-edge-hardening.md`
4. `exec-plans/active/pre-tz-adversarial-edge-hardening.md`
5. `PRE_TZ_BACKLOG.md`
6. `ROADMAP.md`
7. `COMPLETION_POLICY.md`
8. `PRE_TZ_ARCHITECTURE_V03_4.md`
9. `DECISIONS_V03_4.md`
10. `PLANS.md` / `SESSION_POLICY.md` / `WORKFLOW.md`
11. `TESTING.md` / `RUBY.md` as relevant
12. `TZ_RECONCILIATION.md` for the authority-switch protocol.

Current Version Goal: **v0.3.4 — Pre-TZ Adversarial Case Fidelity & Edge Hardening — ACTIVE**.

## Protected completed baseline

v0.3.3 / SPEC-007 is `VERSION_COMPLETE` and remains the immediate protected baseline. Its archived queue is `PRE_TZ_BACKLOG_V03_3.md`; its completed ExecPlan is `exec-plans/completed/pre-tz-skeptical-hardening.md`.

The following remain inherited rationale/guarantees unless SPEC-008 explicitly supersedes them:

- `PRE_TZ_ARCHITECTURE_V03_3.md` and `DECISIONS_V03_3.md` — v0.3.3 baseline;
- `PRE_TZ_ARCHITECTURE.md`, `CURRENT_ARCHITECTURE.md`, `DECISIONS_CURRENT.md`, `DECISIONS.md` — older accepted rationale;
- SPEC-007/006/005/004/003/002/001 — historical requirements and regression intent.

Do not treat historical `ACTIVE`, `current`, `complete` or stop wording as authority for v0.3.4.

## Completion rule

The active backlog records known v0.3.4 hypotheses, not a closed universe of possible defects. A hypothesis may close because current code is proven safe; production code need not change merely to satisfy a backlog item.

After all known P0/P1 work is green, v0.3.4 becomes only `VERSION_CANDIDATE` and must execute the fresh skeptical discovery stage in `COMPLETION_POLICY.md`. Any material locally solvable discovery returns the version to ACTIVE.

## When the authoritative TZ arrives

`TZ_RECONCILIATION.md` becomes the transition protocol. The full authoritative TZ then supersedes provisional pre-TZ semantics through explicit requirement-by-requirement reconciliation.