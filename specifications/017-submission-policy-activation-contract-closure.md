# SPEC-017 — Submission Policy Activation & Contract Closure

Status: **ACTIVE**

Version Goal: **v0.4.1 — Submission Policy Activation & Contract Closure**

Opening baseline: `0187bf2558d58a52dfdb27e76694d6323addbcd6`.

## 1. Purpose

Close the gap between the capable v0.4.0 `RubyRouting::Case` library and the exact command/artifacts used for competition submission. v0.4.1 does not build a third router. It activates one canonical smart policy, separates routing/settlement accounting, hardens the organizer projection, and proves hidden-like robustness.

## 2. Confirmed baseline findings

At the opening baseline:

- `CaseConfiguration` defaults to empty count/volume targets, `priority` as the only factor and `simulation_mode: approved`;
- `bin/finalize_submission` and `bin/ruby_routing_case` instantiate `Runner` without an explicit configuration;
- multi-factor configuration exists mainly in tests/demo, therefore finalization can be priority-only;
- `TrafficLedger` records only approved final decisions, conflating distribution objective with successful settlement;
- failed external provider interactions are projected as `skipped` attempts even though the provider was actually selected/attempted;
- soft amount preference is derived from the same hard min/max interval rather than an independent preferred range;
- strict validation validates the in-memory run, not the serialized files;
- rich `selection` traces are emitted in the decisions DTO although hidden-validator tolerance for additional fields is only an assumption;
- strict replay contains avoidable repeated linear lookups that can be removed before hidden-like scale tests.

These are material P1 release gaps even though exact-head v0.4.0 CI is green.

## 3. Canonical SubmissionProfile

Create one typed configuration authority used by every supported submission entrypoint.

Requirements:

- finalization and normal case CLI use the same profile by default;
- profile identity/source/revision are written to report provenance;
- provider identity comes from loaded data, not hardcoded branches;
- count targets derive from official participating-provider `traffic_percentage` unless stronger authority overrides;
- volume targets have an explicit source (configured or derived with provenance), never an implicit zero map while volume factor is claimed active;
- factor weights are explicit exact values;
- independently configurable amount-preference bands are supported;
- RPM/min-turnover remain optional when organizer data omits them; no invented hard obligation is hidden;
- deterministic simulation seed/mode are explicit;
- terminal self-provider is explicit/validated;
- profile can be overridden for tests/demo without creating another chooser.

The default submission profile must exercise the intended smart routing path. Accidental default `priority-only + approved` is forbidden.

## 4. Distribution accounting authority

Separate at least three projections:

1. **primary assignment ledger** — first external/terminal provider selected for the payout before outcome; default authority for count/volume distribution objectives under current TZ wording;
2. **attempt ledger** — all providers actually invoked in order;
3. **settlement ledger** — final approved provider only.

A rejected/expired first provider remains part of assignment/attempt evidence. Settlement failure must not retroactively erase routing distribution.

Report both assignment and settlement distributions. Keep outcome/success analytics separate.

If new organizer authority explicitly defines share by successful payouts, reconcile before changing the default assignment authority.

## 5. Internal attempt model and external projection

Internal attempt state must distinguish hard exclusion from actual provider invocation.

Minimum semantic states:

- `hard_skipped`;
- `attempted_approved`;
- `attempted_rejected`;
- `attempted_expired`;
- terminal non-approval.

The organizer's `decision: selected|skipped` vocabulary is an external projection. Do not make that enum the internal business model.

Top-level `selected_provider`, initial assignment provider and final provider must be represented internally as distinct concepts where they differ. The external decisions DTO must use one documented conservative assumption and compatibility tests.

## 6. External DTO minimization

Default `routing_decisions*.json` should contain only organizer-required/strongly evidenced fields:

- `operation_id`;
- `selected_provider`;
- `attempts` with `provider`, `decision`, `reason`;
- `simulated_result`;
- `latency_sec` where retained by contract.

Do not require rich score traces in this file. Move detailed factor evidence to report/internal projections unless organizer compatibility proves extra fields safe.

After writing decisions/report, parse them back and validate actual JSON types and contract consistency. Serialized `Rational` representation must be deliberate per field; report percentages/shares should use a judge-readable documented representation rather than accidental internal fraction strings when numeric output is expected.

## 7. Independent amount preference

Add preferred amount configuration separate from hard limits. Hard min/max remains eligibility. Preferred bands only affect soft ranking among eligible providers. Tests must demonstrate a provider can remain eligible outside its preferred band and lose on preference without being excluded.

## 8. Smart finalization acceptance

The exact hidden-queue finalization-equivalent path must prove:

- canonical profile loaded automatically;
- count and volume targets non-empty/provenanced when their factors are enabled;
- at least count + volume + current business factor contributions are visible in selection trace for a controlled eligible conflict;
- changing profile weights changes a controlled decision without code changes;
- deterministic conversion-mode simulation can produce reject/expired fallback in finalization-equivalent tests;
- public four goldens remain correct;
- `spacepayments` remains terminal-only;
- no production UNKNOWN semantics change.

Do not tune weights to reproduce `sample_routing_decisions.json` mechanically; sample is format/golden evidence, not the scoring oracle.

## 9. Report semantics

Report distinct sections for:

- assignment distribution count/volume/targets/deviation;
- settlement distribution and success rate;
- attempt outcome counts;
- fallback metrics;
- hard exclusions;
- utilization;
- infeasible targets;
- configuration/profile provenance;
- history calibration provenance;
- actionable recommendations.

Recommendations must point to a change causally related to the evidence. For a provider forced over target, prefer target adjustment or improvement of alternatives rather than blindly expanding the already over-target provider.

## 10. Hidden-like robustness

Before candidate:

- index operation/decision lookup in strict validation where repeated scans create avoidable O(N²) behavior;
- run deterministic synthetic campaigns with materially larger queues/provider sets;
- test custom queue path and hidden-like filename/path behavior;
- validate serialized artifacts, not only in-memory objects;
- test unknown/additional provider identities through data/config without routing branches;
- test equal timestamps, RPM boundaries, daily exhaustion, repeated fallbacks and terminal non-approval under canonical profile.

No premature database/index infrastructure; simple in-memory maps are sufficient.

## 11. Traceability changes

Rows that were `SUPPORTED` because a library capability existed must be reopened to `PARTIAL` when the supported submission path did not exercise the capability. `docs/TZ_REQUIREMENT_MATRIX.md` is the current release traceability source.

## 12. Protected baseline

Preserve v0.4.0 hard constraints, state, resolver, simulator boundary, reports, production UNKNOWN/ownership kernel and inherited test disciplines unless a SPEC-017 requirement proves a minimal change necessary.

## 13. Non-goals

No DB/queue/microservice/real PSP/ML/general DSL/broad refactor. No generic recovery hardening. No dashboard-first work. No separate submission router.

## 14. Completion contract

Known fixes green → `VERSION_CANDIDATE` only.

`VERSION_COMPLETE` requires:

1. canonical smart profile is the exact default finalization authority;
2. assignment/attempt/settlement accounting is explicit and recomputable;
3. amount preference is independent of hard limits;
4. fallback internal semantics and organizer projection are separated/tested;
5. serialized decisions/report pass strict post-write validation;
6. external decisions DTO is compatibility-minimal;
7. public validator remains green;
8. hidden-like deterministic/scale campaigns are green;
9. requirement matrix has no unresolved material P0/P1/PARTIAL release row;
10. independent blind code/data/output audit finds no new material P0/P1;
11. fresh full inherited + case verification is green;
12. exact pushed-HEAD GitHub Actions is green after final material change;
13. documentation matches that exact tree.
