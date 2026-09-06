# Completion Policy — no premature done

Current version: **v0.4.3 / SPEC-019 — VERSION_COMPLETE**.

Completed compatible baseline: **v0.4.2 / SPEC-018** at opening SHA `277d6b68d568eceb88ece3b3e466987535ff75bd`.

Completion is an evidence claim about the exact hidden-queue submission path and generated artifacts under the authoritative TZ. Green unit tests, self-consistent replay and shape-valid JSON are not enough.

Stages: `ACTIVE -> SLICE_VERIFIED -> VERSION_CANDIDATE -> independent blind pass -> VERSION_COMPLETE`.

## Mandatory v0.4.3 gates before candidate

1. organizer base distribution accounting point is supported by authoritative wording or a documented conservative ambiguity decision;
2. fallback counterexample proves report/decision/accounting semantics are intentional;
3. independent semantic report oracle recomputes total count, provider set, share_pct, target_pct, projected utilization and period without ReportBuilder expected values;
4. report shape validator and semantic validator both pass real serialized finalization output;
5. candidate-addition/removal normalization campaign either demonstrates and fixes a material defect or evidence-closes current normalization with concrete cases;
6. hidden-queue daily temporal contract is established and current code is correct or fail-closed for cross-day input;
7. a provider missing preferred amount configuration cannot obtain silent maximum soft preference;
8. public organizer decisions validator remains green;
9. assignment/attempt/settlement conservation stays exact;
10. current matrix has no material P0/P1 PARTIAL/MISSING/CONFLICT.

Known-scope green gives VERSION_CANDIDATE only.

## Independent blind stage

After candidate, ignore backlog completion and attack actual code/artifacts again for:

- builder/semantic-oracle correlation;
- report distribution disagreement with decisions under fallback;
- wrong denominator or percentage rounding at small counts;
- provider-set omissions/extras;
- target provenance drift;
- utilization recomputation errors after rejection/fallback;
- irrelevant-candidate normalization inversion;
- missing optional factor config acting as positive preference;
- cross-midnight daily-limit leakage;
- direct terminal fallback causality gaps;
- CLI/demo/finalization divergence and public-data overfit.

Any material P0/P1 returns ACTIVE.

## Exact evidence before VERSION_COMPLETE

After the final material code change run fresh:

- `bundle check`;
- `bundle exec rake test`;
- property/model/concurrency/fault suites;
- full Case suite;
- all SPEC-019 adversarial campaigns;
- canonical finalization;
- public organizer decisions validator;
- independent report shape validator;
- independent report semantic validator;
- strict in-memory + serialized validation;
- clean-checkout finalization;
- requirement/rubric traceability and docs consistency;
- exact pushed-HEAD GitHub Actions success.

Never reuse stale CI and never declare completion while exact-head CI is pending.

## Closure evidence

v0.4.3 completed on exact pushed HEAD
`13efbeba48f1726b91b71b1677d3541dd4f9f433`. The fresh full matrix, Case and
adversarial campaigns, canonical and clean-checkout finalization, public and
independent validators, docs sync and exact-head Actions run `33852436704`
passed with zero failures/errors. The independent blind stage found and closed
TZ19-106/107 before the final matrix; no material local P0/P1 remained.
