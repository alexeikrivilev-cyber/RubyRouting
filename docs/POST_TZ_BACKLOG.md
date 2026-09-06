# Post-TZ Backlog — v0.4.1 Submission Policy Activation & Contract Closure

Status: **VERSION_COMPLETE**

Spec: `specifications/017-submission-policy-activation-contract-closure.md`

Opening baseline: `0187bf2558d58a52dfdb27e76694d6323addbcd6`.

v0.4.0 capabilities are baseline; this backlog contains only current release gaps.

## P0/P1 — release path

### TZ17-001 — canonical smart SubmissionProfile — VERIFIED
`SubmissionProfile` is loaded from `data/submission_profile.json` by the finalization and supported case CLI paths. It derives count/volume targets from active external `traffic_percentage`, carries exact factor weights, independent preferred bands, deterministic conversion seed, terminal identity and report provenance. Same-input profile sensitivity, simultaneous factor traces and controlled fallback are covered on the canonical runner/CLI path.

### TZ17-002 — assignment vs settlement accounting — VERIFIED
Separate primary assignment distribution, attempt outcomes and approved settlement distribution. Routing target authority defaults to primary assignment unless stronger organizer evidence says otherwise.

`TrafficLedger`, `AttemptLedger` and `SettlementLedger` now preserve these
three meanings and strict replay/conservation verifies them. Report exposes
all three projections; strict post-serialization validation and temporal edge
campaigns verify no double accounting on fallback.

### TZ17-003 — fallback attempt semantics / output projection — VERIFIED WITH DOCUMENTED ASSUMPTION
Internal `Attempt#classification` distinguishes hard skip and actual invocation; rejected/expired invocations project as `selected`, hard exclusions as `skipped`, and decisions are compatibility-minimal. A real multi-attempt official-queue artifact passes the public validator. Top-level selected-provider semantics remain an explicit conservative organizer assumption; primary and final identities stay distinct internally.

### TZ17-004 — independent amount preference — VERIFIED
Typed `preferred_amount_ranges` are independent of hard min/max and are loaded by the canonical profile. Factor campaign proves hard-eligible providers can rank differently by preferred band; malformed/reversed bands fail closed.

### TZ17-005 — serialized artifact validation — VERIFIED
Both supported CLIs now reparse and strictly validate written decisions/report artifacts; decisions omit rich selection traces. Report recomputation uses canonical ledgers, declares exact Rational JSON representation, and tampered post-write totals/extra fields, malformed operation-id types or null roots are rejected without validator crashes by focused tests.

### TZ17-006 — finalization intelligence regression — VERIFIED
Finalization/CLI now use the canonical multi-factor profile; controlled runs prove simultaneous count/volume/business-factor traces, profile-only weight sensitivity, deterministic conversion fallback, and public-queue compatibility. The runnable case demo's conversion path now uses the same profile and canonical Router, with only an explicit deterministic expiry fixture to demonstrate fallback.

## P1 — analytics / robustness

### TZ17-101 — assignment/settlement report split — VERIFIED
Expose targets/deviations on assignment distribution and success/settlement separately. Strict validation recomputes assignment, attempt and settlement projections from the run's canonical ledgers.

### TZ17-102 — recommendation causality — VERIFIED
Report recommendations expose hard-exclusion causes and direct hard-forced over-target traffic toward target adjustment or improving alternatives. Fallback metrics now distinguish a real transition from terminal-only non-approval; broader under-target evidence remains.

### TZ17-103 — hidden-like scale — VERIFIED
Index strict-validator lookups and run 1,000 operations across five providers with strict replay, accounting and byte-stable output. Equal-timestamp, RPM-boundary, daily-exhaustion and terminal non-approval edge campaigns also pass.

### TZ17-104 — config/profile traceability — VERIFIED
Generated report carries profile id/source/revision, target sources, exact targets and active weights/simulation mode; focused finalization tests verify these fields and the profile sensitivity campaign changes the decision without code changes.

### TZ17-105 — ambiguity closure evidence — VERIFIED WITH DOCUMENTED ASSUMPTION
Keep the remaining top-level selected-provider meaning explicit. Compatibility
tests and conservative defaults prove the projection without claiming that the
public validator settles the organizer ambiguity.

### TZ17-106 — policy authority collision — VERIFIED
The runner/router reject simultaneous profile/configuration authorities and
policy overrides, the configuration constructor rejects canonical `targets`
combined with non-empty legacy share maps, and the resolver rejects duplicate
canonical preferred-band identities/fields instead of silently overwriting one
policy entry. Profile ingress also rejects a supplied `volume_share` when the
declared volume target source is derived from provider traffic percentages.
Malformed non-Hash `rpm_limits` overrides are also rejected as typed policy
override errors instead of leaking a raw method error. Focused boundary
regressions also reject explicit `false` authorities/overrides and invalid
`targets` instead of silently selecting default or empty-share policy. The
case simulator also rejects malformed seed/outcome maps and structured keys
at construction.

## Completion gate

All items above are green on the pushed completion tree. The independent
code/data/output audit found and closed malformed-authority, malformed
simulator-control and serialized-boundary gaps; fresh exact-HEAD verification
and CI passed. Any new material P0/P1 reopens ACTIVE.

## Frozen

No generic recovery/restart hardening, HTTP polish, DB/Redis/queues/microservices, real PSP adapters, ML, generic DSL or broad production refactor unless directly required by SPEC-017.
