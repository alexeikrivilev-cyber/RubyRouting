# Completion Policy — no premature done

Current version: **v0.4.2 / SPEC-018 — VERSION_COMPLETE**.

Completed baseline: **v0.4.1 / SPEC-017**.

Completion is an evidence claim about the exact hidden-queue submission path and generated artifacts under the authoritative TZ, not feature count, self-consistent validators or green unit tests.

Stages: `SLICE_IMPLEMENTED -> SLICE_VERIFIED -> VERSION_CANDIDATE -> VERSION_COMPLETE`.

## Mandatory v0.4.2 gates before candidate

1. serialized `routing_report` preserves the TZ base schema while retaining rich additive analytics;
2. an independently encoded organizer/TZ report validator passes on fresh serialized output;
3. public organizer decisions validator remains green;
4. bounded Case eligibility treats only literal `active` status as active;
5. primary assignment remains exactly once and fallback ranking cannot add a phantom count/volume counterfactual;
6. an independent fallback ranking regression proves intended primary-vs-fallback semantics;
7. assignment/attempt/settlement conservation stays exact;
8. successful selection reasons are concrete and rubric-readable;
9. canonical preferred amount bands can materially affect a finalization-equivalent conflict without changing hard eligibility;
10. non-discriminating factors do not claim full causal contribution;
11. recommendations contain evidence plus a concrete actionable parameter/rule/limit change and have judge-readable string projection;
12. constrained-under-target feasibility evidence is covered without fabricating infeasibility;
13. hidden-like deterministic/scale campaigns remain green;
14. `TZ_REQUIREMENT_MATRIX.md` has no material P0/P1 release row left `PARTIAL/MISSING/CONFLICT`.

These gates produce `VERSION_CANDIDATE` only; the exact current release has also passed
the independent closure gates below.

## Blind skeptical stage

After candidate, ignore backlog completion and attack actual entrypoints/artifacts:

- report base fields/types drift from TZ while rich internal validator stays green;
- report validator is correlated with `ReportBuilder`;
- fallback count/volume double-counterfactual;
- assignment/attempt/settlement denominator mismatch;
- Case status vocabulary broader than organizer semantics;
- hard rules become score penalties or are bypassed at terminal/fallback;
- selected reason says only `selected` despite no concrete rationale;
- release factor enabled but non-discriminating;
- equal-value factor claims causal contribution;
- percentage JSON types/rounding surprise hidden parser;
- volume target provenance is silently invented;
- recommendation action does not address its evidence;
- under-target feasibility is overclaimed/underexplained;
- public data is overfit;
- CLI/demo/finalization diverge;
- hidden-like validation/runtime regresses.

Any material local P0/P1 returns ACTIVE. The current blind pass found and fixed two
material local issues: hard-forced routes no longer receive misleading workload-size
advice, and the independent report validator rejects empty provider projections and
out-of-range utilization percentages.

## Exact evidence before VERSION_COMPLETE

After final material code change, from a fresh tree run:

- `bundle check`;
- `bundle exec rake test`;
- property/model/concurrency/fault;
- full case suite;
- fresh public finalization;
- public organizer decisions validator;
- independent TZ report contract validator against serialized output;
- strict in-memory + post-serialization validation;
- hidden-like scale/determinism/rubric campaigns;
- clean-checkout finalization with canonical profile;
- requirement/rubric traceability;
- exact pushed-HEAD GitHub Actions.

Do not reuse stale CI or declare completion while exact-head CI is pending. Current
exact pushed-head Actions is green.

## Documentation gate

README, AGENTS, AUTHORITY, SPEC-018, completed ExecPlan state, POST_TZ_BACKLOG, TZ
matrix, current decisions, roadmap/session/plans/workflow/testing and exact
code/artifacts agree for v0.4.2.
