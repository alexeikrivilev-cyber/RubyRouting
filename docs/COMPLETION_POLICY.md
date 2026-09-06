# Completion Policy — no premature done

Current version: **v0.4.1 / SPEC-017 — VERSION_COMPLETE**.

Completed baseline: **v0.4.0 / SPEC-016**.

Completion is an evidence claim about the exact hidden-queue submission path and generated artifacts, not feature count or green unit tests.

Stages: `SLICE_IMPLEMENTED → SLICE_VERIFIED → VERSION_CANDIDATE → VERSION_COMPLETE`.

## Mandatory v0.4.1 gates before candidate

1. exact finalization/CLI path automatically uses one canonical smart SubmissionProfile;
2. no accidental priority-only or always-approved default can become release authority;
3. count and volume targets are explicit/provenanced when enabled;
4. primary assignment, attempted providers and approved settlement are separate accounting concepts;
5. routing target deviation is recomputable from the documented assignment ledger;
6. amount preference is independently configurable from hard min/max;
7. internal attempt semantics distinguish hard exclusion from provider failure;
8. external decisions DTO is minimal, conservative and organizer-compatible;
9. generated JSON is parsed/strictly validated after serialization;
10. public validator remains green on fresh public output;
11. report exposes assignment/settlement/outcomes/config provenance and evidence-backed recommendations;
12. hidden-like deterministic/scale campaigns are green;
13. `TZ_REQUIREMENT_MATRIX.md` has no material P0/P1 release row still `PARTIAL/MISSING/CONFLICT` except explicitly irreducible organizer ambiguity with conservative tested projection.

These gates produce `VERSION_CANDIDATE` only.

## Blind skeptical stage

After candidate, ignore backlog completion and attack actual entrypoints/artifacts:

- finalization silently bypasses profile;
- profile targets/weights missing or zero unexpectedly;
- assignment counted at wrong point or double-counted on fallback;
- settlement failures alter routing distribution retrospectively;
- hard skip confused with attempted failure;
- top-level selected provider inconsistent with chosen projection;
- extra decision fields break strict hidden-like parser;
- Rational serialization has wrong JSON type;
- amount preference still duplicates hard range;
- fallback/terminal bypasses hard rules;
- recommendations advise causally wrong change;
- large queue validator becomes pathological;
- CLI/demo/finalization choose differently;
- public data overfitting.

Any material local P0/P1 returns ACTIVE.

## Exact evidence before VERSION_COMPLETE

After final material change, from exact tree run:

- `bundle check`;
- `bundle exec rake test`;
- property/model/concurrency/fault;
- full case suite;
- public golden queue;
- public organizer validator against fresh minimal decisions;
- strict in-memory + post-serialization validation;
- hidden-like scale/determinism campaigns;
- clean-checkout finalization with canonical profile;
- requirement/rubric traceability;
- exact pushed-HEAD GitHub Actions.

Do not reuse stale CI or declare completion while exact-head CI is pending.

## Documentation gate

README, AGENTS, AUTHORITY, SPEC-017, active/completed ExecPlan state, POST_TZ_BACKLOG, TZ matrix, current architecture/decisions, roadmap/session/plans/workflow/testing must agree with the exact tree.
