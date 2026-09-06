# ExecPlan — SPEC-020 Submission Safety & Business-Day Semantics

Status: **SLICE_COMPLETE**

Program: **v0.4.4 — Competition 10/10 Convergence**

Opening baseline: `6192c6167d1face2995c5076f1d994cdf9484aff`

## Goal

Close two bounded, high-score risks without mixing in the next scoring/accounting redesign:

1. final submission artifacts cannot be generated from an implicit/wrong queue or silently excluded from Git;
2. daily limits/report dates use the authoritative dataset business calendar rather than UTC-day accident.

Expected terminal state: `SLICE_COMPLETE`; v0.4.4 program remains ACTIVE.

## Phase 0 — exact baseline and reproducers

Before changes:

- fetch exact main and exact-head CI;
- run canonical public finalization and validators;
- prove that `bin/finalize_submission` with no `--queue` currently writes `_test` files from the public queue;
- prove both required root files are ignored by current `.gitignore` / `git check-ignore`;
- build a `+03:00` midnight fixture where 00:30+03 remains previous UTC date and show current daily/report behavior is wrong;
- record expected authoritative invariants in this plan.

Do not start scoring changes.

## Phase 1 — explicit finalization authority

Implement the smallest release-interface change satisfying SPEC-020 R1/R2:

- explicit queue required for `bin/finalize_submission`;
- explicit public-fixture dry-run behavior;
- fixed root output paths;
- no artifact write before required release input is resolved.

Update Rake/CI call sites explicitly; do not preserve an implicit default merely for convenience.

Evidence:

- missing queue returns non-zero and writes nothing;
- explicit public queue produces canonical artifacts and public validator remains green;
- alternate explicit queue is reflected in manifest evidence.

Checkpoint: focused tests + canonical finalization + commit/push.

## Phase 2 — artifact trackability and manifest

Close the 40-point operational seam:

- make required root artifacts safely committable without undocumented force-add;
- add a small release readiness/manifest mechanism;
- include queue digest/count/first-last IDs and output digests/paths;
- fail closed on ignored/missing/wrong-path/invalid artifacts;
- ensure validation occurs on serialized bytes before readiness is reported.

Do not add deployment automation beyond this bounded guard.

Evidence:

- `git check-ignore`/equivalent proves required artifacts are eligible for final commit;
- manifest hashes recompute from actual bytes;
- stale/modified artifact after manifest or validation is detected by the readiness path;
- clean public dry run is still deterministic.

Checkpoint: focused release tests + finalization-equivalent run + commit/push.

## Phase 3 — explicit business calendar

Reproduce baseline UTC-day bug first, then introduce one typed calendar authority.

Preferred minimal direction:

- retain UTC/absolute `Time` for ordering/RPM;
- preserve/derive snapshot UTC offset as dataset-level business-calendar metadata;
- provide one helper/value object for business-date projection;
- inject/use it from CaseState daily buckets rather than repeating `utc.strftime`;
- snapshot daily baseline applies on snapshot business date and resets when business date advances.

Do not use system local timezone, environment TZ or an external timezone database.

Evidence:

- +03 midnight fixture resets at 00:00+03, not 03:00+03;
- pre-midnight and post-midnight daily capacity decisions are hand-checkable;
- mixed display offsets map to the same snapshot business calendar;
- RPM ordering/window behavior is unchanged.

Checkpoint: temporal tests + state/fallback adjacency + commit/push.

## Phase 4 — report and semantic-oracle convergence

Update all calendar-sensitive projections to use the same business calendar:

- report `period`;
- projected daily utilization/latest daily state;
- independent `OrganizerReportSemanticValidator` period/utilization recomputation.

The semantic validator must derive calendar metadata from raw provider snapshot input, not from ReportBuilder output.

Evidence:

- shape-valid UTC-date tampering is rejected on a +03 cross-midnight fixture;
- report and state agree on final business date;
- canonical public report remains TZ-compatible.

Checkpoint: report semantic tests + serialized finalization + commit/push.

## Closure evidence

- Missing `--queue` is a deterministic non-zero failure and leaves existing root
  artifact bytes unchanged.
- Explicit public finalization remains green and identifies
  `queue_kind=public_fixture` in operator output.
- `SubmissionManifest` binds the absolute queue path, queue SHA-256, count,
  first/last operation IDs and both validated output hashes/paths. Its second
  verification detects a post-validation byte change; root output paths are
  fixed and no longer ignored by Git.
- A `+03:00` snapshot regression with `23:59`, `00:01`, `00:30` and a mixed
  display offset proves daily reset at local midnight, while stored instants
  remain UTC-comparable. Report period/utilization and the independent semantic
  validator use the same typed snapshot-offset calendar.
- Focused finalization, temporal and semantic tests are green; the full Case
  task is green (119 tests, 665 assertions).

## Phase 5 — focused blind audit and slice closure

Ignore backlog status and inspect actual code/artifacts for:

- any remaining implicit queue fallback;
- release path writing wrong/non-root filenames;
- ignored or stale artifacts;
- manifest/validated-byte mismatch;
- local-midnight/day-reset off-by-one;
- mixed-offset timestamp drift;
- report/state/oracle calendar disagreement;
- alternate CLI/Rake/CI path divergence.

Any material release/calendar P0/P1 would have returned the slice to ACTIVE.
The blind audit found no such issue. Fresh finalization-equivalent evidence and
exact-head CI below are complete for pushed SHA `fdf3d2dacc545d75b94e3be5c35e0c1c708ba85a`.

Fresh verification performed:

- SPEC-020 focused suites;
- full Case suite (the finalization isolation and byte-parity regressions run
  as Case 120/672);
- relevant inherited matrix;
- explicit public dry run;
- finalization-equivalent release run;
- public decisions validator;
- report contract + semantic validators;
- strict serialized validator;
- trackability/readiness checks;
- docs consistency;
- push exact HEAD and wait for exact-head Actions — workflow `33867261015`.

The exact pushed-head Actions workflow `33867261015` completed successfully:
both `Fast Ruby verification` and `Bounded product evidence` passed. SPEC-020
is now `SLICE_COMPLETE`; this plan is moved to completed. Do not mark v0.4.4
`VERSION_COMPLETE`; the next scoring/accounting slice remains separate.

## Session rule

Continue autonomously while the next phase is derivable. Each material checkpoint gets evidence, coherent commit/push and plan update. Do not broaden scope because another known issue exists; sequence is deliberate.
