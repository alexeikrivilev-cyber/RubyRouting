# RubyRouting

Smart payout-routing system for Hack.Genesis case **«Умный роутинг выплат»**.

Ruby baseline: **CRuby 4.0.6**.

## Current direction

Current Version Goal: **v0.4.2 — Submission Contract Fidelity & Scoring Semantics Closure — VERSION_COMPLETE**.

Opening baseline: `e9a24923aebfdb1b01223a360b3f3f2b4e84ee45` — completed v0.4.1 submission-policy baseline.

v0.4.1 materially closed the previous release-path gap: finalization now uses a typed smart `SubmissionProfile`, assignment/attempt/settlement are separated, fallback attempts are internally honest, amount preference is independently configurable, artifacts are reparsed after serialization, and hidden-like campaigns are green.

A fresh code-first audit reopened development because the remaining risks sat at the competition boundary and scoring semantics:

1. report-contract compatibility and independent serialized validation;
2. fallback scoring must remain phase-correct after primary assignment;
3. Case and organizer status semantics must agree on literal `active`;
4. selection reasons, amount preference and factor causality must be visible and meaningful;
5. P2 evidence-gated questions are now recorded explicitly: volume-target provenance
   and candidate-relative normalization remain evidence-closed without redesign; terminal
   identity inference has been removed.

This is not another framework build. It is a submission-fidelity and scoring-quality closure cycle. The exact pushed release path is now `VERSION_COMPLETE` after an independent blind code/data/artifact pass and fresh closure verification.

## Current authority

`direct current instruction > authoritative TZ/rubric > organizer data/sample/reference/validator > SPEC-018 > compatible SPEC-017/SPEC-016 baselines > active v0.4.2 ExecPlan > POST_TZ_BACKLOG > TZ_REQUIREMENT_MATRIX > current architecture/decisions/governance > protected production invariants > implementation/tests > historical docs`.

Public `scripts/validate_10.rb` is mandatory lower-bound evidence, not the full artifact/rubric contract.

## v0.4.2 objective

`official inputs`
→ `hard eligibility`
→ `canonical SubmissionProfile`
→ `primary count+volume+business scoring`
→ `one ConflictResolver`
→ `primary assignment`
→ `phase-correct fallback ranking`
→ `attempt/settlement accounting`
→ `TZ-compatible minimal decisions/report base projection`
→ `rich extensions`
→ `independent organizer-contract validation`
→ `routing_decisions_test.json + routing_report_test.json`.

## Immediate priorities

1. **Done:** TZ base `routing_report` projection plus independent post-serialization validator.
2. **Done:** strict Case `status == active`, phase-correct fallback, concrete reasons.
3. **Done:** canonical discriminating amount bands and neutral-factor evidence.
4. **Done:** quantitative recommendations and constrained-under-target feasibility evidence.
5. **Evidence-closed:** volume target provenance and candidate-relative normalization remain explicit, tested decisions; terminal identity is explicit configuration only.

## Protected strengths

Do not rewrite without a concrete failing counterexample:

- official hard-constraint evaluator and sequential provider state;
- assignment / attempt / settlement accounting split;
- typed `SubmissionProfile`;
- exact arithmetic;
- deterministic simulation;
- one `ConflictResolver`;
- terminal fallback boundary;
- production UNKNOWN/economic-owner safety;
- property/model/concurrency/fault suites.

## Current read order

1. `README.md`
2. `AGENTS.md`
3. `docs/AUTHORITY.md`
4. `specifications/018-submission-contract-fidelity-scoring-semantics.md`
5. compatible `specifications/017-submission-policy-activation-contract-closure.md`
6. `docs/TZ_REQUIREMENT_MATRIX.md`
7. `docs/exec-plans/completed/submission-contract-fidelity-scoring-semantics.md` (after `VERSION_COMPLETE`)
8. `docs/POST_TZ_BACKLOG.md`
9. `docs/CURRENT_ARCHITECTURE.md`
10. `docs/DECISIONS_CURRENT.md`
11. completion/session/planning/workflow/testing docs
12. actual `data/`, `scripts/validate_10.rb`, case code/tests and exact-head CI.

## Completion discipline

Known scope was advanced to `VERSION_CANDIDATE`, then subjected to a blind code/data/artifact audit. The audit findings were fixed with deterministic regressions; fresh full verification, finalization, validators, clean-checkout evidence and exact pushed-head GitHub Actions are green. No material local P0/P1 remains.

Do not spend scoring-critical time on DB/Redis/queues/microservices/real PSPs/ML/general DSLs or generic recovery hardening while a v0.4.2 P0/P1 remains open.
