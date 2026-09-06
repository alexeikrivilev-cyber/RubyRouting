# Goal Mode + SpecOps Workflow

Current Version Goal: **v0.4.1 / SPEC-017 — VERSION_COMPLETE**.

Operating loop:

`Discover authoritative release gap → inspect exact entrypoint/output → reproduce → specify semantic authority → implement → focused verify → finalization-equivalent verify → serialized artifact verify → skeptical adjacency → update matrix/plan → push → inspect exact-head CI → continue`.

## Critical workflow rule

Do not equate library capability with release activation. For v0.4.1 every scoring-critical claim must be demonstrated through the same configuration path used by `bin/finalize_submission` or a strictly equivalent controlled runner.

## Artifact rule

Validators must inspect the artifacts that would be submitted. In-memory object validation is necessary but insufficient. Reparse decisions/report after serialization and verify types, enums, coverage, accounting and report consistency.

## Accounting rule

Do not silently move the traffic objective between assignment and settlement. Name the accounting point, test fallback scenarios, and report the other projection separately.

## Candidate/closure

Known SPEC-017 scope green → candidate only. Then blind code/data/output review. Any material P0/P1 → ACTIVE. The clean blind pass, fresh full matrix, finalization, public/strict validators and exact pushed-head CI have passed for v0.4.1.
