# RubyRouting

Smart payout-routing system for Hack.Genesis case **«Умный роутинг выплат»**.

Ruby baseline: **CRuby 4.0.6**.

## Current direction

Current Version Goal: **v0.4.3 — Adversarial Evidence & Contract Semantics Closure — VERSION_COMPLETE**.

Opening baseline: `277d6b68d568eceb88ece3b3e466987535ff75bd` — completed v0.4.2 submission-fidelity baseline with exact-head Actions green.

v0.4.2 remains the compatible implementation baseline: TZ-compatible report shape, literal Case `active`, phase-correct fallback, concrete reasons, discriminating amount bands, neutral-factor honesty and stronger recommendations are preserved. v0.4.3 independently closed the five adversarial semantics, hardened validator boundaries, and passed fresh exact-HEAD verification.

## v0.4.3 objective

Do not add architecture. Attack five adversarial questions in order:

1. **report accounting point** — prove whether organizer-facing `distribution` must represent primary assignment, final selected provider, or approved settlement; do not change the ledger until authority/evidence resolves the contract;
2. **independent semantic report oracle** — validate totals, provider sets, shares, targets, utilization and period semantics independently of `ReportBuilder`;
3. **candidate-set normalization robustness** — test whether adding/removing an otherwise irrelevant eligible provider can materially change A-vs-B routing under supported factors/profile;
4. **multi-day state semantics** — determine whether hidden queues can cross operational days; if yes, implement correct daily rollover, otherwise document and enforce the single-day contract;
5. **missing amount preference** — a new provider without `preferred_amount_ranges` must not silently receive maximal soft preference.

Only confirmed defects get production changes. A falsified hypothesis is closed by explicit evidence and documentation, not by speculative refactor.

## Current authority

`direct current instruction > authoritative TZ/rubric > organizer data/sample/reference/validator > SPEC-019 > compatible completed SPEC-018/SPEC-017/SPEC-016 > completed v0.4.3 ExecPlan > POST_TZ_BACKLOG > TZ_REQUIREMENT_MATRIX > current architecture/decisions/completion/testing/workflow > protected production invariants > implementation/tests > historical docs`.

The public decisions validator is a lower bound. Shape-valid output is not sufficient if its business meaning is wrong.

## Protected strengths

Do not rewrite without a concrete failing counterexample:

- official hard-constraint evaluator and sequential Case state;
- assignment / attempt / settlement accounting split;
- typed canonical `SubmissionProfile`;
- exact Integer/Rational arithmetic;
- deterministic simulation;
- one `ConflictResolver` with primary/fallback phase;
- TZ-compatible report base projection;
- production UNKNOWN/economic-owner safety;
- inherited property/model/concurrency/fault evidence.

## Current read order

1. `README.md`
2. `AGENTS.md`
3. `docs/AUTHORITY.md`
4. `specifications/019-adversarial-evidence-contract-semantics.md`
5. compatible completed SPEC-018, SPEC-017 and SPEC-016
6. `docs/TZ_REQUIREMENT_MATRIX.md`
7. `docs/exec-plans/completed/adversarial-evidence-contract-semantics.md`
8. `docs/POST_TZ_BACKLOG.md`
9. `docs/CURRENT_ARCHITECTURE.md`
10. `docs/DECISIONS_CURRENT.md`
11. completion/session/planning/workflow/testing docs
12. actual `data/`, `scripts/validate_10.rb`, Case code/tests, generated artifacts and exact-head CI.

## Completion discipline

Known v0.4.3 scope green required `VERSION_CANDIDATE`, an independent blind code/data/artifact pass, fresh full verification, finalization, public decisions validation, independent shape **and semantic** report validation, hidden-like adversarial campaigns, docs consistency and successful exact pushed-head Actions. Those gates passed on `13efbeba48f1726b91b71b1677d3541dd4f9f433`.

## Non-goals

No Rails/ORM, DB, Redis/Sidekiq, queues, microservices, real PSP integrations, ML/bandits/neural networks, generic DSL/plugins, broad production refactor or generic recovery hardening without a direct SPEC-019 blocker.
