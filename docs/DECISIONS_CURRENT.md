# Current Decisions — Post-TZ v0.4.1

This file is the current decision overlay. SPEC-016/v0.4.0 decisions remain accepted where not superseded below.

## Stable inherited decisions

- authoritative TZ outranks pre-TZ assumptions;
- hard eligibility stays outside scoring and reruns on fallback;
- `RubyRouting::Case` is bounded from production UNKNOWN/economic ownership;
- official priority is lower-is-higher;
- current `conversion_24h` leads historical calibration;
- `spacepayments` is terminal self-provider, not an ordinary competitor;
- deterministic simulation only;
- one ConflictResolver is the competition soft-goal authority;
- public validator is a lower bound;
- finalization is a product feature.

## TZD-031 — reopen release claim after submission-path audit
Status: accepted.

Decision: v0.4.0 is a completed implementation baseline. The opening audit
confirmed that exact finalization used default priority-only/always-approved
configuration while richer policy capabilities were optional; the current
candidate closes that release-path gap. Completion status follows exact release
behavior, not library feature existence.

## TZD-032 — one canonical SubmissionProfile
Status: accepted.

Decision: finalization and supported case CLI use one typed default policy profile. Demo/tests may override it, but no separate demo-only smart chooser exists. Profile source/revision, targets, weights, simulation mode/seed and terminal identity are reportable.

Count target default is derived from official participating-provider `traffic_percentage`. Volume target source must be explicit/provenanced. RPM/min-turnover absent from organizer input remain optional, not silently invented hard facts.

## TZD-033 — separate primary assignment and settlement accounting
Status: accepted as bounded TZ interpretation pending stronger organizer clarification.

Decision: distribution targets apply to primary routing assignment by default because the case asks to distribute new payout requests/volume between providers. Provider failure does not erase that assignment. Attempt outcomes and final approved settlement are separate ledgers/report projections.

If organizer clarification explicitly defines target shares by successful payouts, reconcile this decision before changing code.

## TZD-034 — organizer attempt enum is a projection
Status: accepted.

Decision: internal semantics distinguish hard-skipped provider from selected/attempted approved/rejected/expired provider. Organizer `decision: selected|skipped` is only a compatibility projection. Internal truth must not call an invoked provider a hard skip.

Top-level initial assignment provider and final provider remain separate internal concepts. External `selected_provider` uses one documented conservative assumption until organizer clarification.

## TZD-035 — minimal external decisions, rich report
Status: accepted.

Decision: default decisions JSON minimizes fields to organizer-required/strongly evidenced contract. Factor score matrices and detailed internal traces belong in report/internal evidence unless extra decision fields are proven safe. Generated JSON must be reparsed and validated after serialization.

## TZD-036 — preferred amount band is independent
Status: accepted.

Decision: hard `limit_amount_min/max` controls eligibility. Soft amount preference uses separately configured preferred band/shape. Reusing hard range midpoint as the whole amount strategy is insufficient for the rubric.

## TZD-037 — recommendation actions must be causal
Status: accepted.

Decision: recommendation engine must suggest a change that plausibly addresses the measured cause. For hard-forced over-target traffic, adjust target or improve alternative eligibility/capacity; do not blindly expand the already over-target provider.

## Open authoritative assumptions

- exact external top-level `selected_provider` semantics after fallback;
- exact organizer interpretation of multiple actually attempted providers inside `attempts` enum;
- exact `expired` generation algorithm;
- requisite lifecycle beyond availability;
- official absent values for RPM/minimum turnover;
- hidden validator tolerance for additional decision fields.

Use reversible conservative projections and tests. Do not present these as organizer facts.

The current candidate keeps these assumptions explicit; they are not a reason
to block the tested release projection unless organizer authority changes them.

## TZD-039 — demo conversion uses submission authority

Status: accepted.

Decision: the runnable case demo uses the same typed `SubmissionProfile`,
`Router` and report builder as finalization for its conversion scenario. Its
bounded expiry mapping is an explicit deterministic outcome fixture used to
show fallback, not a second policy or chooser.

## TZD-040 — malformed serialized identity fails as validation

Status: accepted.

Decision: `SerializedArtifactValidator` validates operation-id types before
coverage sorting. A malformed artifact is an invalid submission with explicit
errors, never an uncaught comparison/type exception at the strict boundary.

## TZD-041 — fallback explanations expose primary and final facts separately

Status: accepted.

Decision: report `selected_reason` belongs to the final invoked attempt, while
`primary_assignment_provider` and `primary_assignment_reason` preserve the
initial assignment. Terminal fallback is derived from the final selected
attempt, so a fallback explanation cannot combine one provider with another's
reason.

## TZD-042 — serialized roots are mandatory

Status: accepted.

Decision: strict post-write validation always validates both artifact roots.
JSON `null`/`false` or parse failures cannot be treated as an absent optional
document; they produce an invalid artifact result.

## TZD-043 — canonical case targets cannot be shadowed by share maps

Status: accepted.

`CaseConfiguration#targets` is the canonical target object. Supplying non-empty
`count_share` or `volume_share` alongside it is rejected rather than silently
discarded, preventing a caller from believing a different policy was applied.

`SubmissionProfile` applies the same rule at profile ingress: a profile using
the derived `provider.traffic_percentage` volume source cannot also provide a
`volume_share` override. Explicit configured volume targets must name and
provide that map.

## TZD-044 — malformed case policy overrides fail closed

Status: accepted.

Profile-backed router construction rejects non-Hash policy overrides as typed
boundary errors before a run is built; it must never fail through a raw method
error while checking whether an alternate policy authority was supplied.

Explicit `false` is not an absent authority. Runner, Router and
CaseConfiguration use nil-presence and typed validation so malformed policy
inputs cannot silently fall back to the default profile or empty targets.

The same fail-closed rule applies to deterministic case simulation controls:
seed must remain a String, outcomes must be a Hash keyed by exact
operation/provider identities, and outcome values must be typed statuses
rather than arbitrary values coerced through `to_s`.

## TZD-038 — reject competing case policy authorities

Status: accepted.

`Runner` refuses a call that supplies both a `SubmissionProfile` and a direct
`CaseConfiguration`; `ConflictResolver` refuses duplicate preferred-band keys
after canonicalization. A case run must have one unambiguous policy source,
and malformed configuration must fail closed rather than use last-write-wins.
