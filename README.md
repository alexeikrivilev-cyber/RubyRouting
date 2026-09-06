# RubyRouting

Smart payout-routing system for Hack.Genesis case **«Умный роутинг выплат»**.

Ruby baseline: **CRuby 4.0.6**.

## Current direction

Current Version Goal: **v0.4.1 — Submission Policy Activation & Contract Closure — VERSION_COMPLETE**.

Opening baseline: `0187bf2558d58a52dfdb27e76694d6323addbcd6` — completed v0.4.0 authoritative case engine.

v0.4.0 / SPEC-016 remains the completed implementation baseline. The opening
v0.4.1 audit found that the supported finalization path ran with default
priority-only routing, empty count/volume targets and `simulation_mode:
approved`, while assignment-vs-success accounting and fallback-output contracts
were incomplete. The completed v0.4.1 path closes those findings through the typed
`SubmissionProfile`, separate ledgers, conservative projection and
post-serialization strict validation. The blind audit and fresh exact-HEAD
verification passed on the pushed completion HEAD.

This is a release-path convergence version, not another broad framework build.

## Current authority

`direct current instruction > authoritative TZ > organizer data/sample/validator > SPEC-017 > SPEC-016 compatible baseline > active v0.4.1 ExecPlan > POST_TZ_BACKLOG > TZ_REQUIREMENT_MATRIX > current architecture/decisions/governance > protected production invariants > implementation/tests > historical documents`.

Public `scripts/validate_10.rb` remains mandatory lower-bound compatibility evidence, not the full rubric.

## v0.4.1 objective

Make the exact submission command exercise the smart routing system we claim to have, with one explicit and reproducible policy profile:

`official inputs`
→ `hard eligibility`
→ `canonical submission policy`
→ `count + volume + enabled business factors`
→ `one ConflictResolver`
→ `primary assignment accounting`
→ `deterministic provider outcome / fallback`
→ `settlement accounting`
→ `minimal organizer DTO + rich report`
→ `post-serialization validation`
→ `routing_decisions_test.json + routing_report_test.json`.

## Candidate closure checks

1. **Profile activation:** exact finalization and CLI paths use the committed typed profile with target, factor, simulation and provenance evidence.
2. **Accounting/fallback:** assignment, attempted providers and final settlements remain separately recomputable, with conservative organizer projection.
3. **Output/analytics:** serialized decisions and reports are strict-revalidated; recommendations cite causal assignment and hard-rule evidence.
4. **Blind closure:** inspect alternate entrypoints, malformed profiles, terminal/fallback paths, exact arithmetic, determinism and hidden-like scale before fresh full verification.

## Protected strengths

Do not rewrite without evidence:

- complete official hard-constraint evaluator;
- sequential `ProviderCaseState`;
- exact `TrafficLedger` arithmetic;
- typed routing factors and `ConflictResolver`;
- deterministic simulator/fallback boundary;
- production economic-owner/UNKNOWN safety;
- property/model/concurrency/fault suites.

The problem is now activation and semantic closure, not missing infrastructure.

## Current read order

1. `README.md`
2. `AGENTS.md`
3. `docs/AUTHORITY.md`
4. `specifications/017-submission-policy-activation-contract-closure.md`
5. `specifications/016-authoritative-tz-submission-engine.md` for completed baseline semantics
6. `docs/TZ_REQUIREMENT_MATRIX.md`
7. `docs/exec-plans/active/submission-policy-activation-contract-closure.md`
8. `docs/POST_TZ_BACKLOG.md`
9. `docs/CURRENT_ARCHITECTURE.md`
10. `docs/DECISIONS_CURRENT.md`
11. completion/session/planning/workflow/testing docs.

## Completion discipline

v0.4.1 became `VERSION_CANDIDATE` after the exact finalization path demonstrated the canonical smart policy and closed the accounting/output contracts. The independent hidden-like code/data audit found and closed additional boundary gaps; fresh full verification and exact pushed-HEAD CI then passed. A new material P0/P1 reopens ACTIVE.
