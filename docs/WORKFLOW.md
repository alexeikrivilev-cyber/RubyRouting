# Goal Mode + SpecOps Workflow

Current Version Goal: **v0.4.2 / SPEC-018 — VERSION_COMPLETE**.

Operating loop:

`Discover authoritative release/scoring gap -> inspect exact entrypoint/artifact -> reproduce -> define invariant/contract -> implement minimally -> focused independent verify -> finalization-equivalent verify -> serialized artifact verify -> skeptical adjacency -> update matrix/plan -> commit/push -> inspect exact-head CI -> continue`.

## Critical workflow rules

1. **External contract outranks internal elegance.** If TZ base report fields are missing, fix the compatibility projection before optimizing scoring internals.
2. **Independent evidence matters.** A validator generated from the same builder cannot independently prove that builder matches TZ. A replay that duplicates Router control flow cannot independently prove routing semantics.
3. **Primary and fallback phases are explicit.** Count/volume objectives cannot silently counterfactually assign one operation twice.
4. **Feature active != feature causal.** A configured factor must be able to discriminate candidates in evidence. Equal raw values are neutral, not full contribution.
5. **Hard constraints remain absolute.** Never convert hard failure to score.
6. **Finalization is the release path.** CLI/demo/library-only success does not close a submission requirement.

## Artifact rule

Validators inspect the exact artifacts that would be submitted. Reparse decisions/report after serialization. Run both:

- organizer/public decisions compatibility validator;
- independent TZ report base-contract validator;
- strict rich internal consistency validator.

## Candidate/closure

Known SPEC-018 P0/P1 scope reached `VERSION_CANDIDATE`; blind code/data/output review
closed its findings. Fresh full matrix, clean finalization and exact pushed-head CI are
green, so the tree is `VERSION_COMPLETE`.
