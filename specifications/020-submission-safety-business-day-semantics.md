# SPEC-020 — Submission Safety & Business-Day Semantics

Status: **SLICE_COMPLETE**

Program: **v0.4.4 — Competition 10/10 Convergence**

Opening baseline: `6192c6167d1face2995c5076f1d994cdf9484aff`.

## Objective

Close two bounded high-ROI risks before broader score convergence: fail-safe organizer artifact finalization and one explicit business-calendar authority for daily limits/report dates.

## Completed requirements

- final submission requires explicit `--queue`;
- organizer outputs are fixed repository-root `routing_decisions_test.json` and `routing_report_test.json`;
- serialized strict/report-contract/report-semantic validators run before release evidence;
- `SubmissionManifest` binds queue bytes, operation count/IDs and output hashes and rejects ignored/wrong-path/stale artifacts;
- required root artifacts are Git-trackable and LF byte parity with Git blobs is tested;
- `BusinessCalendar` derives the bounded daily calendar from provider snapshot UTC offset;
- ordering/RPM remain absolute-instant based;
- daily approved reset, report period/utilization and independent semantic validation use the same business calendar;
- `+03:00` midnight and mixed-offset regressions cover the prior UTC-day bug;
- production UNKNOWN/ownership semantics remain untouched.

## Closure evidence

Implementation slice completed at `fdf3d2dacc545d75b94e3be5c35e0c1c708ba85a`; follow-up byte-parity evidence is present on baseline `50b969575f482610460b805d199acc725e8eb37b`. Exact-head Actions for the baseline passed. Detailed evidence remains in `docs/exec-plans/completed/submission-safety-business-day-semantics.md`.

SPEC-020 is a protected compatible baseline for SPEC-021. Reopen only with a new material counterexample or stronger organizer authority.