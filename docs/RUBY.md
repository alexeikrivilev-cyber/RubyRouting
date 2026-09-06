# Ruby Engineering Guide

This document governs Ruby implementation technique below `docs/AUTHORITY.md`, authoritative TZ, SPEC-018 and compatible SPEC-017/SPEC-016 baseline semantics.

Runtime baseline: **CRuby 4.0.6** unless organizer authority explicitly supersedes it.

## Language/runtime rules

- executable competition logic stays Ruby;
- no second implementation in another language;
- no neural/ML runtime or proprietary routing engine;
- keep dependencies small; standard-library JSON/CSV/Time/filesystem first;
- Bundler + Rake remain canonical dependency/verification surfaces;
- no Rails/ORM/DB/Redis/queues/microservices without direct measured case need.

## Domain/value rules

Use typed immutable values for configuration, factors, decisions and report evidence. Keep mutable case state behind explicit owners.

Financial/business amounts stay Integer. Exact shares/contributions use `Rational` internally. Float/decimal conversion is allowed only in organizer-facing percentage presentation and never feeds routing authority.

Provider/operation IDs are validated strings; provider names are data, not source branches.

## v0.4.2 release-path rules

- finalization uses the typed canonical `SubmissionProfile`;
- assignment, attempts and settlement remain separate;
- hard exclusions and actual provider attempts remain separate internal states;
- primary vs fallback scoring phase is explicit; do not counterfactually assign one operation twice;
- hard min/max and soft preferred amount band remain separate concepts;
- serializers/projections never choose providers;
- preserve the TZ base report schema and add rich fields rather than replacing it;
- validate serialized decisions/report with both internal consistency and independently encoded organizer/TZ contract checks;
- neutral factors must not claim causal contribution;
- use simple in-memory maps/indexes for hidden-like validation; do not add persistence infrastructure.

## Determinism

No uncontrolled `rand`, sleep-based correctness or wall-clock routing authority. Use operation timestamps, explicit simulation seed, stable tie-break and deterministic serialization where claimed.

## Error handling

Input/config/output failures fail closed with actionable errors. Do not convert programming errors into provider outcomes or hard exclusions. CLI/finalization exits non-zero on invalid input/generation/validation failure.

## Testing

Use Minitest and repository Rake tasks. Every scoring-critical capability must be tested through a finalization-equivalent configuration and, where possible, an independent oracle/contract validator. Follow `docs/TESTING.md` and `docs/COMPLETION_POLICY.md`.

## Authority

Business behavior comes from TZ/organizer contract → SPEC-018 → compatible SPEC-017/SPEC-016 → active plan/matrix. This file cannot redefine case semantics.