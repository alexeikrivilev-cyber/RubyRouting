# Completion Policy — no premature 10/10

Program: **v0.4.4 / SPEC-021 — ACTIVE**.

Completion is a claim about actual code, artifacts and rubric evidence on an exact pushed HEAD. Green tests, a closed finding registry, or a high subjective score are insufficient.

Stages:

`ACTIVE -> VERSION_CANDIDATE -> BLIND_AUDIT -> SCORE_CANDIDATE -> FINAL_REHEARSAL -> VERSION_COMPLETE`.

## VERSION_CANDIDATE gate

- no known material P0/P1 from current code/data/artifact analysis;
- no obvious high-value rubric row remains unsupported without explicit authority/evidence closure;
- no known hidden business objective contradicts configured policy semantics;
- scoring invariants relevant to the current model have independent/metamorphic evidence;
- lifecycle selection rationale/outcome/accounting projections are intentional and testable;
- all material changes have focused and adjacent regression evidence;
- canonical public finalization/validators remain green;
- protected release/calendar and production-safety boundaries remain intact.

## BLIND_AUDIT

Ignore finding-registry status and attack implementation again. At minimum probe:

- hard-gate bypass and fallback recheck;
- allocation denominators/objective correctness;
- factor disablement/zero weights;
- hidden tie-break preferences;
- provider ordering and irrelevant/dominated candidate effects;
- target provenance/mass and missing config defaults;
- fallback chronology and selection-rationale/outcome separation;
- primary/final/settlement report populations;
- terminal behavior and temporal boundaries;
- additional providers/extensibility;
- serializer/report recomputation;
- alternate entrypoints and public-data overfit;
- release artifact freshness/provenance.

Any material P0/P1 returns ACTIVE.

## SCORE_CANDIDATE

Map every scored rubric row to deterministic judge-visible evidence. Unit-test capability alone is insufficient when a compact scenario can prove it safely. For multi-goal scoring, show actual factor evidence/weights and at least several conflicts where the outcome changes for an explainable reason.

Record organizer ambiguity explicitly; do not manufacture certainty.

## FINAL_REHEARSAL

From clean checkout run full inherited/Case/adversarial suites, rubric evidence lab, public decisions validator, independent report validators, serialized strict validation, hidden-like deterministic campaigns and explicit finalization.

For the real hidden queue also confirm:

- queue path/digest and operation count;
- required root artifact names;
- validated artifact hashes;
- Git trackability and committed-byte equality;
- final pushed HEAD contains those exact bytes;
- docs/profile/version metadata describe the actual release sufficiently for judges/operators.

## VERSION_COMPLETE

Only after blind audit is clean, score evidence is strong enough to defend the implementation, final hidden-submission provenance/rehearsal is clean and exact-head Actions succeeds.

New organizer authority or a later material skeptical finding reopens ACTIVE immediately. Completion is never irreversible by policy.
