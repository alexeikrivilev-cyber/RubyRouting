# AGENTS.md

## Mission

Build the strongest submission-grade Ruby solution for Hack.Genesis **«Умный роутинг выплат»** under the authoritative TZ and rubric.

Current Version Goal: **v0.4.2 — Submission Contract Fidelity & Scoring Semantics Closure — VERSION_COMPLETE**.

Opening baseline: `e9a24923aebfdb1b01223a360b3f3f2b4e84ee45` (completed v0.4.1 submission-policy baseline).

## Read before coding

1. `README.md`
2. `AGENTS.md`
3. `docs/AUTHORITY.md`
4. SPEC-018
5. compatible SPEC-017/SPEC-016 baseline semantics
6. `docs/TZ_REQUIREMENT_MATRIX.md`
7. `docs/exec-plans/completed/submission-contract-fidelity-scoring-semantics.md` (closure plan)
8. `docs/POST_TZ_BACKLOG.md`
9. current architecture/decisions/completion/testing/workflow docs
10. actual `data/`, organizer sample/reference/validator, case code/tests and exact-head CI.

Documentation sets intended authority. Code and generated artifacts prove reality.

## Why v0.4.2 is VERSION_COMPLETE

The v0.4.1 code is strong and its exact-head CI was green, but a fresh code-first audit found material competition-boundary defects:

- submitted report shape drifts from the base structure shown by the TZ;
- post-write report validation is correlated with the same report builder and cannot independently detect that drift;
- fallback ranking can apply count/volume counterfactuals after the current operation is already recorded as a primary assignment;
- Case `active?` accepts `enabled` while authoritative/public eligibility requires exact `active`;
- selected reasons are generic;
- release amount preferences are non-discriminating;
- neutral factors claim full contribution;
- recommendation/feasibility output needs stronger causal, quantitative evidence.

The known P0/P1 scope is covered by fresh case/artifact evidence. An independent
blind code/data/output pass found two material local issues—misleading workload
granularity advice for hard-forced routing and permissive empty/out-of-range report
projections—and both were fixed with deterministic regressions. Fresh exact-head
verification and Actions are green; no material local P0/P1 remains.

## Mandatory order

### P0 — authoritative report contract

Preserve the TZ base report fields/types instead of replacing them with the rich internal schema. Keep rich analytics as additive extensions.

At minimum the organizer-facing report projection must expose:

- scalar `period`;
- `total_operations`;
- `distribution.<provider>.count/share_pct/target_pct`;
- `skip_reasons`;
- `projected_daily_utilization.<provider>.used/limit/utilization_pct`;
- judge-readable string `recommendations`.

Create an independent contract validator whose required fields/types are encoded from the TZ, not reconstructed from `ReportBuilder`. Run it on the serialized file from finalization.

Internal exact Rational arithmetic remains exact; percentage conversion occurs only at the compatibility boundary under an explicit rounding rule.

### P1-A — exact Case status semantics

For the bounded competition domain, only literal `status == "active"` is eligible. Do not let a broader production status vocabulary leak into organizer semantics.

### P1-B — phase-correct fallback scoring

Primary count/volume objectives apply to the provider initially assigned the new payout. Once primary assignment is recorded, fallback must not counterfactually add the same operation again.

Keep one resolver and one policy authority. Pass explicit phase/context so fallback ranks remaining eligible providers with the applicable business factors without mutating or double-projecting primary distribution.

Write an independent regression where the old phantom count/volume term changes B-vs-C fallback order. A replay that copies Router logic is not an independent oracle.

### P1-C — concrete selection reasons

Do not emit `reason: selected` as the only explanation. Use stable minimal codes such as `only_eligible_provider`, `highest_composite_score`, `fallback_highest_composite_score`, and terminal reasons. Keep full factor traces in report/internal evidence.

### P1-D — amount strategy and factor honesty

The canonical profile must use meaningful independent preferred amount bands that can actually distinguish hard-eligible providers. Do not overfit exact public rows.

If a factor has equal raw value for every candidate, it is non-discriminating: it must not claim full causal contribution. Deterministic tie-break remains separate.

### P1-E — analytics / recommendations / feasibility

Recommendations must name the evidence and the concrete rule/parameter/action. Add strong cases for near-limit daily utilization, structural under-target exclusions, hard-forced over-target traffic and bounded workload granularity.

Keep base `recommendations` judge-readable strings; put structured evidence in additive `recommendation_details`.

### P2 — evidence-gated semantics

Only after P0/P1 closure:

- reconsider volume target provenance so count and volume goals are explicitly distinct;
- audit candidate-relative normalization against domain-normalized counterexamples;
- separate terminal identity from generic zero-participation semantics where useful.

Do not destabilize the submission for theoretical purity without a failing or materially misleading example.

## Protected architecture

Keep one competition path:

`Input -> SubmissionProfile -> CaseState -> HardConstraintEvaluator -> Traffic/Attempt/Settlement ledgers -> Factors -> ConflictResolver -> Router/Simulator -> organizer projections -> independent validators`.

Hard constraints stay absolute and rerun on fallback. A score never revives an ineligible provider.

## Protected production kernel

Never weaken production UNKNOWN/economic ownership to satisfy synthetic judge expiry. Judge `expired -> next provider` remains inside `RubyRouting::Case`.

## Evidence discipline

For every material fix:

`reproduce on exact HEAD -> state invariant -> smallest semantic change -> focused tests -> adjacent fallback/accounting/scoring tests -> fresh finalization -> public decisions validator -> independent TZ report validator -> strict serialized validator -> inherited relevant suites -> matrix/plan/docs -> coherent commit/push`.

Do not use public-validator permissiveness or a self-generated validator as the only oracle.

## Candidate gate

Before `VERSION_CANDIDATE`, prove:

- serialized report preserves the TZ base contract and rich extensions;
- independent report validator passes on fresh finalization;
- public decisions validator remains green;
- Case only routes literal active providers;
- fallback no longer applies a phantom count/volume counterfactual;
- accounting conservation remains exact;
- selected reasons are concrete;
- canonical amount strategy can affect a finalization-equivalent decision;
- neutral factors are contribution-neutral;
- recommendation and constrained-under-target evidence are causal and quantitative;
- requirement matrix has no material P0/P1 `PARTIAL/MISSING/CONFLICT`.

This produces candidate only. Completion additionally requires the independent blind
code/data/artifact pass, fresh exact-head verification and exact pushed-head CI; those
gates are satisfied for the current release.

## Non-goals

No Rails/ORM, DB, Redis/Sidekiq, queues, microservices, real PSP integrations, ML/bandits/neural networks, generic DSL/plugins, broad Coordinator rewrite or generic recovery work without a direct SPEC-018 blocker.

## Goal Mode

Work continuously while the next release/scoring step is derivable. Do not stop after one green fix, one validator, or one checklist. Stop only after genuine v0.4.2 completion under `docs/COMPLETION_POLICY.md`, a non-resolvable external blocker, or new authoritative organizer clarification that changes the contract.
