# ExecPlan — v0.4.2 Submission Contract Fidelity & Scoring Semantics Closure

Status: **VERSION_COMPLETE — Phases 1–10 closed**

Specification: `specifications/018-submission-contract-fidelity-scoring-semantics.md`

Opening baseline: `e9a24923aebfdb1b01223a360b3f3f2b4e84ee45`.

## Objective

Move from a strong v0.4.1 submission engine to a competition-safe 10/10 candidate by closing output-contract and scoring-semantic defects found by an independent code audit. Preserve working hard constraints, state/accounting architecture, canonical profile and production safety kernel.

## Phase 0 — reproduce opening findings

Before production changes, add focused tests/probes proving or falsifying:

1. current serialized report misses the TZ base keys/types (`period` scalar, `share_pct`, `target_pct`, `projected_daily_utilization`, string recommendations);
2. current report validator accepts that drift because it validates against the same ReportBuilder projection;
3. after a primary rejection/expiry, fallback resolver sees a TrafficLedger already containing the current assignment and count/volume `counterfactual` adds the operation again;
4. `status: enabled` is treated eligible by Case while authoritative/public validator accepts only `active`;
5. ordinary successful attempts use generic `reason: selected`;
6. canonical profile amount bands do not discriminate external providers;
7. equal raw factor values normalize to full contribution;
8. current recommendations/infeasibility miss a concrete constrained-under-target scenario.

If any finding is false on exact HEAD, update this plan/matrix before implementing the assumed fix.

## Phase 1 — P0 TZ report contract fidelity

Implement a dedicated organizer-facing report projection that preserves the TZ base schema and adds rich fields rather than replacing the base fields.

Acceptance:

- scalar TZ-compatible `period` plus optional rich `period_window`;
- `distribution.<provider>` contains `count`, numeric `share_pct`, numeric `target_pct`;
- `skip_reasons` preserved;
- `projected_daily_utilization.<provider>` contains `used`, `limit`, numeric `utilization_pct`;
- `recommendations` is a judge-readable array of strings;
- rich exact assignment/attempt/settlement/provenance/explanation/recommendation detail remains available under additional fields;
- internal Rational arithmetic remains exact; compatibility percentages convert only at output boundary with an explicit rounding policy.

Create `OrganizerReportContractValidator` (or equivalent) whose required-key/type expectations are independently encoded from the TZ, not generated from `ReportBuilder` output. Finalization must run it after serialization.

Checkpoint: focused report-shape tests, public queue finalization, post-write validators, full case suite.

Evidence (2026-09-04): `test/case/report_contract_test.rb` independently validates the
serialized base shape and rejects missing/type-drifted fields; `ReportBuilder` keeps
exact Rational values while `Serializer` emits `_pct` fields as deterministic
two-decimal JSON numbers. `bin/finalize_submission` and `bin/ruby_routing_case` run
`OrganizerReportContractValidator` after writing the artifact. Fresh public queue
finalization passed `scripts/validate_10.rb` (29 passed, 0 failures, 0 warnings).

## Phase 2 — authoritative Case status semantics

Evidence (2026-09-04): `test/case/state_test.rb` proves `status: "enabled"`
produces the stable `inactive_provider` hard exclusion while the public queue
and strict replay remain green. Case-only `Provider#active?` now requires the
literal organizer value `"active"`; the broader status vocabulary remains
accepted at input parsing and production status semantics are untouched.

Make bounded Case eligibility exact: only `status == "active"` is active for routing. Keep production/provider-domain vocabularies separate.

Acceptance:

- synthetic `enabled` provider is rejected by Case hard eligibility;
- public providers remain green;
- strict replay and terminal rules unaffected.

## Phase 3 — fallback scoring phase semantics

Evidence (2026-09-04): `test/case/factors_test.rb` and
`test/case/fallback_phase_test.rb` contain an independent A-rejected→C oracle;
the legacy no-phase resolver selects B under the same post-primary ledger, while
the explicit `fallback` phase selects C without changing the assignment ledger.
Router and strict replay both carry the phase, and the case suite remains green.

Introduce one explicit resolution phase (`primary` / `fallback`) or equivalent semantic context. Count/volume routing objectives govern primary assignment. Once the operation is recorded in the primary assignment ledger, fallback ranking must not add a phantom counterfactual assignment.

Preferred direction:

- primary resolver: count + volume + enabled business factors;
- fallback resolver: eligible remaining providers ranked by enabled non-allocation business factors (priority/amount/conversion/load/intensity/turnover as configured);
- do not mutate the primary assignment ledger on fallback;
- do not introduce a second chooser or duplicate scoring implementation.

Acceptance:

- controlled A reject -> B/C fallback case where the old phantom counterfactual changes ranking;
- independent expected ranking/oracle fails on baseline and passes fix;
- assignment remains A, attempts contain A then fallback provider, settlement is final approved provider;
- next operation sees exactly one prior assignment;
- strict replay independently models the intended phase semantics, not simply copy/pastes router control flow.

## Phase 4 — concrete selection reasons

Evidence (2026-09-04): successful attempts now expose stable
`only_eligible_provider`, `highest_composite_score`,
`fallback_highest_composite_score` or explicit deterministic tie-break reasons;
terminal and hard/outcome reasons remain unchanged. Public goldens and
`scripts/validate_10.rb` remain green.

Define stable minimal reason codes:

- `only_eligible_provider`;
- `highest_composite_score`;
- `fallback_highest_composite_score` or another explicit fallback code;
- `terminal_fallback` / `external_providers_exhausted`;
- existing hard-exclusion and provider outcome reasons remain stable.

Rich score decomposition stays in report/internal evidence. Public validator compatibility must remain green.

## Phase 5 — amount strategy activation and factor honesty

Evidence (2026-09-04): `data/submission_profile.json` now contains explicit
low/mid/high business bands (`payflow`, `vipay`, `quickpay`) independent from
hard gates. `test/case/submission_profile_test.rb` proves the loaded canonical
amount factor changes a hard-eligible 1,000-unit conflict against priority-only
routing without changing eligibility. `test/case/factors_test.rb` proves equal
raw factors have zero normalized/contribution evidence and retain a separate
deterministic tie-break.

Update the canonical submission profile so preferred amount bands genuinely differentiate providers using TZ-backed business semantics rather than public-row fitting. Keep bands independent of hard min/max in implementation.

Fix/replace any test that passes only because deterministic provider-id tie-break picks the expected winner while the amount factor itself is non-discriminating.

For all factors, when raw values are equal across candidates, mark the factor non-discriminating and give zero causal contribution rather than full weight contribution. Preserve deterministic tie-break separately.

Acceptance:

- finalization-equivalent conflict where changing only amount preference changes winner;
- hard eligibility unchanged;
- neutral factor trace explicitly shows no decision pressure;
- final score/explanation remains exact and deterministic.

## Phase 6 — analytics/recommendations/feasibility

Evidence (2026-09-04): `test/case/recommendation_test.rb` covers the loaded
near-limit payflow snapshot, observed bank/amount hard exclusions and a fresh
one-operation fractional target. Reports now emit quantitative near-limit and
structural-under-target details, and classify the small-workload case as
`workload_granularity` rather than infeasibility. Base strings are derived from
the same rich details and strict/public finalization remains green.

Add quantitative causal recommendation rules and symmetric feasibility evidence.

Minimum cases:

- daily utilization near limit -> suggest a concrete target/limit adjustment;
- under-target provider dominated by bank/amount/capacity exclusions -> identify causes and suggest target/coverage adjustment;
- hard-forced over-target provider -> adjust target or alternatives, not that provider's capacity by default;
- integer/small-workload target mismatch is reported as bounded workload granularity, not fabricated hard infeasibility.

Keep `recommendations` as judge-readable strings and richer structured objects in `recommendation_details`.

## Phase 7 — target provenance and normalization audit

Evidence (2026-09-04): the explicit volume-target source was audited without
inventing a history-derived target; `test/case/submission_profile_test.rb` proves
the configured override path and the canonical profile records its current source.
Candidate-relative normalization was retained after a monotonicity/weight audit
found no material counterexample. A concrete ambiguity was found for inferred
terminal identity, so `Router`, report terminal explanations, strict replay and the
case demo now use only explicit `terminal_provider_id`; `test/case/terminal_identity_test.rb`
covers multiple zero-participation providers.

Only after P0/P1 closure:

1. evaluate volume target source. Prefer an explicit independent source (`configured` or clearly history-derived with provenance) over silently giving `traffic_percentage` volume semantics. Do not treat history as current eligibility truth.
2. build counterexamples for candidate-relative min/max normalization. Compare current behavior with domain-normalized factors. Change normalization only if evidence shows material ranking instability, weight non-interpretability or explanation distortion.
3. decouple explicit terminal provider identity from any generic zero-participation helper where this improves correctness without broad refactor.

These are evidence-gated; do not destabilize a correct release path for theoretical elegance.

## Phase 8 — hidden-like/rubric campaign

Known-scope evidence (2026-09-04): full Case suite is green at 100 tests/564
assertions; the 250-operation hidden-like campaign is deterministic and passes strict,
serialized and independent report validation; fresh finalization passes the
organizer decisions validator (29/0/0) and produces the canonical root artifacts.
The product benchmark, 10k lifecycle load, degradation metrics and history
profile also completed successfully. This evidence permitted `VERSION_CANDIDATE`
before the independent closure pass.

Run deterministic campaigns covering:

- public queue + organizer decisions validator;
- independent TZ report validator;
- multi-day/date edge only if compatible with authoritative period semantics;
- fallback chains with count/volume targets active;
- status variants;
- hard-forced and constrained-under-target scenarios;
- report recomputation and numeric percentage boundary;
- additional providers;
- hundreds/thousands of operations;
- byte-stable decisions and stable report values across fresh runs.

Map each technical/expert rubric item to concrete code/output evidence.

## Phase 9 — candidate and independent skeptical pass

Known scope green -> **VERSION_CANDIDATE only**.

Then ignore backlog status and attack actual code/data/artifacts for:

- TZ base report schema drift;
- correlated validator/oracle;
- fallback allocation double-counterfactual;
- primary/final provider confusion;
- Case vs organizer status vocabulary;
- neutral factor claiming causal contribution;
- profile factor enabled but non-discriminating;
- percentage type/rounding surprises;
- recommendations with non-causal advice;
- under-target feasibility overclaim/underclaim;
- public-data overfitting;
- finalization/CLI/demo divergence;
- hidden-scale regressions.

Any material P0/P1 returns ACTIVE.

Blind-pass update (2026-09-04): a deterministic one-operation fractional-target
probe found that `workload_granularity` was also emitted for a hard-forced sole
eligible provider, which could suggest an ineffective workload-size remedy. The
report now suppresses granularity advice for both observed hard exclusions and
hard-forced assignments; focused and full Case regressions are green.

Blind-pass update (2026-09-04): the independent report validator accepted a
shape-valid report with empty provider maps and an out-of-range utilization
percentage. It now requires non-empty provider projections, non-empty provider
identities and 0..100 utilization percentages; focused and full Case regressions
remain green.

## Phase 10 — final closure — VERIFIED / VERSION_COMPLETE

From a fresh tree after the last material code change:

- `bundle check`;
- `bundle exec rake test`;
- property/model/concurrency/fault suites;
- full case suite;
- fresh public finalization;
- organizer public decisions validator;
- independent TZ report contract validator;
- strict in-memory and serialized validators;
- hidden-like/rubric campaigns;
- clean-checkout finalization;
- requirement matrix/docs consistency;
- push exact HEAD;
- wait for exact-head GitHub Actions success.

Evidence (2026-09-04): `bundle check`, full inherited test/property/model/
concurrency/fault matrix, full Case suite, public finalization and
`scripts/validate_10.rb` (29 passed, 0 failures, 0 warnings), independent report
contract validation, strict serialized validation, hidden-like deterministic
campaign, concise case demo and clean-checkout finalization all passed. Exact
pushed-head GitHub Actions is green. The blind audit found no further material
local P0/P1.
