# Ruby Engineering Guide

This document governs Ruby implementation technique below `docs/AUTHORITY.md`, authoritative TZ, SPEC-017 and compatible SPEC-016 baseline semantics.

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

Financial/business integer amounts stay Integer. Exact shares/contributions use `Rational` internally where authority requires exactness. Float may be presentation-only and never feed routing authority.

Provider/operation IDs are validated strings; provider names are data, not source branches.

## v0.4.1 release-path rules

- finalization uses an explicit typed `SubmissionProfile`, not library defaults as hidden policy;
- assignment and settlement accounting remain separate;
- hard exclusions and actual provider attempts remain separate internal states;
- hard min/max and soft preferred amount band remain separate concepts;
- serializers are projections only and never choose providers;
- write JSON, then reparse/validate the actual artifact;
- keep decisions DTO conservative; place rich score evidence in report/internal structures;
- use simple in-memory maps when hidden-like validation needs indexing; do not add persistence infrastructure.

## Determinism

No uncontrolled `rand`, sleep-based correctness or wall-clock routing authority. Use operation timestamps, explicit simulation seed, stable tie-break and deterministic serialization where claimed.

## Error handling

Input/config/output failures fail closed with actionable errors. Do not convert programming errors into provider outcomes or hard exclusions. CLI/finalization exits non-zero on invalid input/generation/validation failure.

## Testing

Use Minitest and repository Rake tasks. Every scoring-critical capability must be tested through a finalization-equivalent configuration, not unit/demo only. Follow `docs/TESTING.md` and `docs/COMPLETION_POLICY.md`.

## Authority

Business behavior comes from TZ/organizer contract → SPEC-017 → compatible SPEC-016 → active plan/matrix. This file cannot redefine case semantics.
