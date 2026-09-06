# Long-Session Goal Mode Policy

Current Version Goal: **v0.4.1 — Submission Policy Activation & Contract Closure — VERSION_COMPLETE**.

Continuous loop:

`exact main/data/CI → reproduce release-path gap → minimal semantic fix → focused tests → finalization-equivalent run → serialize/reparse/validate → public validator → adjacent skeptical review → traceability/docs → commit/push → next highest-value gap`.

## Default order

1. blind code/data/output audit of the candidate submission path — complete;
2. fresh exact full verification and clean finalization — complete;
3. exact pushed-head CI and documentation closure — complete.

Do not stop after a feature exists in a unit test. The exact submission path must exercise it.

Do not return to generic recovery/HTTP/infrastructure work while a SPEC-017
release row remains open; a new material finding reopens ACTIVE.
