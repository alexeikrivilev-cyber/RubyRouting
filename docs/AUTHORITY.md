# Documentation Authority

Current Version Goal: **v0.4.1 — Submission Policy Activation & Contract Closure — VERSION_COMPLETE**.

Opening baseline: `0187bf2558d58a52dfdb27e76694d6323addbcd6`.

v0.4.0 / SPEC-016 is a completed implementation baseline, not the current completion claim. A fresh audit found material release-path gaps, so current work is governed by SPEC-017.

## Normative order

1. direct current user/instructor requirement;
2. authoritative Hack.Genesis TZ and organizer scoring/rules;
3. organizer data/sample/reference/validator for contracts they actually define;
4. `specifications/017-submission-policy-activation-contract-closure.md`;
5. compatible completed baseline `specifications/016-authoritative-tz-submission-engine.md`;
6. active v0.4.1 ExecPlan;
7. `docs/POST_TZ_BACKLOG.md`;
8. `docs/TZ_REQUIREMENT_MATRIX.md`;
9. current architecture/decisions/completion/session/planning/workflow/testing;
10. protected compatible production invariants;
11. implementation/tests;
12. historical specifications/plans.

A lower source cannot silently override a higher source.

## Important interpretation rule

Feature existence is not submission readiness. If a factor/resolver/simulator exists in the library but the supported hidden-queue finalization path does not activate it, the requirement is `PARTIAL` for release purposes.

Likewise, a green in-memory validator does not prove the serialized JSON artifact contract. External artifacts must be parsed and checked after serialization.

## Organizer ambiguity

Where the TZ/sample/public validator do not resolve a detail, preserve richer internal semantics, use a conservative external projection, document the assumption, and keep it reversible. Current high-impact assumptions include target accounting point and fallback `selected_provider`/attempt projection.

## Completion

v0.4.1 is `VERSION_COMPLETE`: the known SPEC-017 release-path gates, blind
audit and fresh exact-HEAD verification passed on the pushed completion HEAD.
v0.4.0 evidence remains valid for unchanged baseline capabilities, while any
new authoritative clarification or material counterexample reopens ACTIVE.
