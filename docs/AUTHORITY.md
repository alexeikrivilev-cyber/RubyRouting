# Documentation Authority

Current Version Goal: **v0.4.2 — Submission Contract Fidelity & Scoring Semantics Closure — VERSION_COMPLETE**.

Opening baseline: `e9a24923aebfdb1b01223a360b3f3f2b4e84ee45`.

v0.4.1 / SPEC-017 is the completed submission-policy baseline. A fresh code-first audit found material artifact-contract and fallback-scoring gaps, so v0.4.2 is governed by SPEC-018.

## Normative order

1. direct current user/instructor requirement;
2. authoritative Hack.Genesis TZ and scoring rubric;
3. organizer data/sample/reference/validator for contracts they actually define;
4. `specifications/018-submission-contract-fidelity-scoring-semantics.md`;
5. compatible completed baselines SPEC-017 and SPEC-016;
6. `docs/exec-plans/completed/submission-contract-fidelity-scoring-semantics.md` (closure plan);
7. `docs/POST_TZ_BACKLOG.md`;
8. `docs/TZ_REQUIREMENT_MATRIX.md`;
9. current architecture/decisions/completion/session/planning/workflow/testing;
10. protected compatible production invariants;
11. implementation/tests;
12. historical specifications/plans.

A lower source cannot silently override a higher source.

## Artifact-contract rule

The public decisions validator is a lower bound. The TZ base structure for `routing_report*.json` is independently authoritative even when no organizer report validator is supplied. Rich report fields may extend the TZ base structure but must not replace its required base fields/types.

A validator that compares a serialized artifact only with the output of the same builder is not an independent contract oracle. v0.4.2 requires an independently encoded organizer/TZ report contract check.

## Scoring semantics rule

Feature existence is not rubric closure. A factor must be active on the supported submission path and must be capable of discriminating candidates in evidence. A neutral factor must not be described as causally decisive.

Primary distribution and fallback execution are separate semantics. If count/volume target authority is primary assignment, fallback must not counterfactually assign the same operation a second time.

## Organizer ambiguity

Where TZ/sample/public validator do not define a detail, preserve richer internal semantics, use a conservative external projection, document the assumption and keep it reversible. Do not invent missing organizer facts.

Current accepted interpretation: top-level `selected_provider` is the final provider selected by the cascade, while primary assignment remains separately available in rich report/internal evidence.

## Completion

v0.4.2 is `VERSION_COMPLETE`: SPEC-018 gates, independent artifact/code skeptical pass,
fresh full verification and exact pushed-head Actions all pass. v0.4.1 evidence remains
valid for unchanged capabilities.
