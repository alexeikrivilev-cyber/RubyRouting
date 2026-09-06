# Testing Strategy

Current Version Goal: **v0.4.2 / SPEC-018 — VERSION_COMPLETE**.

Preserve all inherited production and v0.4.1 case suites. Add independent contract/scoring tests for gaps that self-consistent replay cannot catch.

## 1. TZ report contract tests

Generate the actual report artifact, parse it back and validate independently encoded TZ base requirements:

- scalar `period`;
- `total_operations`;
- provider `distribution.count/share_pct/target_pct`;
- `skip_reasons`;
- `projected_daily_utilization.used/limit/utilization_pct`;
- judge-readable string `recommendations`.

Rich fields must remain additive and recomputable. Do not implement the validator by asking `ReportBuilder` for the expected object and comparing equality only.

Add tamper tests for missing/wrong-type base fields. Keep public decisions validator separate.

## 2. Fallback phase tests

Build a controlled three-provider case where:

- primary provider A is selected and then rejected/expired;
- B/C fallback order differs if count/volume `counterfactual` incorrectly adds the current operation again;
- independent expected ranking asserts the intended fallback choice;
- assignment ledger remains A exactly once;
- attempt ledger records A plus fallback provider;
- settlement ledger records only approved final provider.

Strict replay must model the documented phase invariant, not merely duplicate Router control flow.

## 3. Case status tests

Synthetic `status: enabled` must be hard-ineligible in the bounded Case layer because authoritative/public rules require literal `active`. Preserve tests for inactive/disabled and public active providers.

## 4. Explanation tests

Assert concrete selection reasons for:

- one eligible provider;
- primary composite winner;
- fallback composite winner;
- terminal fallback/exhaustion;
- hard exclusions.

Rich factor evidence remains internal/report-only unless explicitly safe externally.

## 5. Amount/factor honesty tests

Canonical-profile finalization-equivalent case must prove preferred amount range can change winner while both providers remain hard eligible.

Remove/repair any assertion that succeeds only via provider-id tie-break when amount raws are equal.

When a factor has equal raw values across candidates, assert zero/non-discriminating contribution and separate deterministic tie-break behavior.

## 6. Analytics/recommendation tests

Cover:

- provider near daily limit -> concrete utilization action;
- provider under target due repeated bank/amount/capacity exclusions -> causal recommendation;
- hard-forced over-target provider -> target/alternative action, not expanding the same provider by default;
- small workload/integer target granularity -> report as granularity, not fabricated hard infeasibility;
- base `recommendations` strings and rich `recommendation_details` agree on provider/evidence/action.

## 7. Target/normalization evidence tests

After P0/P1 closure:

- prove volume target source/revision/provenance is explicit;
- history-derived values, if used, come only from history analytics and never change current hard eligibility;
- construct candidate-set normalization counterexamples and compare current vs proposed domain-normalized behavior before changing implementation.

## 8. Hidden-like robustness

Use additional provider identities and hundreds/thousands of operations. Assert deterministic output, no fallback double-assignment, stable percentage projection/rounding, strict artifact validation and acceptable runtime without new infrastructure.

## 9. Verification order

For each material slice:

`reproducer -> focused test -> independent oracle/contract test -> adjacent accounting/fallback/profile tests -> public queue -> fresh serialization/reparse -> public decisions validator -> TZ report validator -> relevant inherited suites`.

Before candidate/final closure:

`bundle check; rake test; property; model; concurrency; fault; rake case; public finalization; public validator; independent TZ report validator; strict serialized validation; hidden-like/rubric campaign; clean finalization; blind skeptical pass; exact pushed-head CI` — all green for the exact completion head.
