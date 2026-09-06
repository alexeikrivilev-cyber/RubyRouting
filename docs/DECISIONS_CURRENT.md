# Current Decisions — Post-TZ v0.4.3 — VERSION_COMPLETE

SPEC-018/v0.4.2, SPEC-017/v0.4.1 and SPEC-016/v0.4.0 remain accepted where not superseded below.

## Stable inherited decisions

- authoritative TZ/rubric outrank pre-TZ assumptions;
- hard eligibility stays outside scoring and reruns on fallback;
- `RubyRouting::Case` is bounded from production UNKNOWN/economic ownership;
- priority is lower-is-higher;
- one `ConflictResolver` is the soft-goal authority;
- primary and fallback use explicit phase context;
- assignment, attempts and settlement remain separate ledgers;
- public validator is a lower bound;
- report base shape is TZ-compatible and rich fields are additive;
- exact arithmetic remains internal; compatibility percentages are bounded output values;
- terminal provider identity is explicit configuration;
- neutral equal-valued factors claim zero causal contribution.

## TZD-055 — reopen release claim after fresh code-first audit
Status: accepted.

Decision: v0.4.2 remains a completed baseline, and v0.4.3 closed the five evidence gaps found by the fresh independent review: organizer distribution accounting point, semantic report oracle independence, candidate-set normalization stability, multi-day daily state, and missing amount-range neutrality. TZ19-106/107 were then found and closed during the blind stage.

## TZD-056 — do not collapse primary/final/settlement accounting before authority is proven
Status: accepted for investigation.

Decision: keep current primary assignment, final selected provider and approved settlement facts separate. SPEC-019 must determine which one the organizer base `distribution` is intended to project. Internal ledgers survive any projection choice.

## TZD-057 — report semantic oracle must not use ReportBuilder expected values
Status: accepted.

Decision: shape validation and builder self-consistency are necessary but insufficient. Semantic report evidence must independently recompute totals/shares/targets/utilization/period from raw queue/providers/profile and serialized decisions.

## TZD-058 — candidate-relative normalization is evidence-gated, not presumed safe
Status: accepted.

Decision: the previous no-change decision is reopened only for a focused candidate-addition/removal campaign. Change normalization only if real supported-factor/profile behavior produces a material unjustified A/B inversion or misleading causal trace. Preserve exact arithmetic and one resolver.

## TZD-059 — missing optional amount preference should be neutral
Status: candidate decision pending reproducer.

Decision direction: absence of a preferred amount band must not mean maximum preference. Confirm with an additional-provider regression, then encode neutral/non-discriminating absence with minimal impact on current configured providers.

## TZD-060 — daily limits require an explicit temporal contract
Status: accepted and implemented.

Decision: the TZ permits an ordered queue and does not impose a single-day
restriction. A deterministic cross-midnight reproducer showed that cumulative
daily usage carried the supplied snapshot baseline into a later UTC date. The
case state therefore scopes `daily_approved_amount` to the UTC calendar date:
the snapshot baseline applies on its snapshot date, and later dates start at
zero before that date's approved outcomes. Other sequential state (in-progress,
RPM, attempts, routes and settlements) remains continuous. No persistence or
scheduler is introduced.

## TZD-061 — fallback accounting point remains an explicit authority ambiguity
Status: evidence-closed for the current implementation; organizer meaning remains ambiguous.

Decision: a deterministic `vipay rejected -> payflow approved` probe proves that
primary assignment, final selected provider and approved settlement are different
populations. The literal TZ says `distribution by provider` and requires actual vs
target shares, but does not define which population applies after fallback; the
public sample/validator has no rejected/expired fallback accounting case. Keep the
existing primary-assignment base projection as the conservative reversible choice:
fallback attempts must not silently rewrite allocation-target truth. Preserve final
selection and approved settlement as separate rich projections, with attempts as a
third population. Revisit only on explicit organizer clarification or a material
validator/rubric counterexample.

## TZD-062 — serialized report semantics require a separate raw-input oracle
Status: accepted and implemented.

Decision: `OrganizerReportContractValidator` remains the independent shape/type
check, while `OrganizerReportSemanticValidator` independently parses raw
providers/queue/profile plus serialized decisions/report. It recomputes queue
coverage, primary-assignment counts/shares, declared targets, approved-settlement
daily utilization and the UTC period. It does not call `ReportBuilder`, `Run` or
Router replay for expected values. Finalization and the case CLI run it after the
write/read boundary; shape-valid tamper regressions prove business-value drift is
rejected.

## TZD-063 — resolver normalization requires an explicit opportunity pool
Status: accepted and implemented.

Decision: candidate-relative min/max normalization is only meaningful when its
reference set is the complete opportunity pool for that resolution. An
independent A/B/C campaign confirmed that adding a hard-eligible non-winning C
could otherwise rescale count/conversion factors and invert A/B without changing
their raw evidence. `ConflictResolver` therefore fails closed unless callers
provide `normalization_candidates` containing every scored candidate. Canonical
Router and stateful replay pass the complete current hard-eligible pool; callers
comparing subsets must pass the same pool explicitly. This preserves the
existing public allocation outputs while removing a silent alternate authority.

## TZD-064 — absent preferred amount configuration is neutral
Status: accepted and implemented.

Decision: an optional provider preferred amount band is a soft preference, not
an implicit universal match. A deterministic additional-provider probe showed
that returning raw `1` for absence made an unconfigured provider the strongest
amount preference. `AmountPreferenceFactor` now returns exact raw `0` when the
band is absent; equal raw values remain non-discriminating with zero causal
contribution. Configured bands and hard min/max eligibility remain separate and
unchanged.

## TZD-065 — terminal zero-participation identity remains explicit
Status: evidence-closed; no change required.

Decision: a deterministic additional-provider probe confirmed that terminal
identity is selected explicitly and is not hardcoded to the provider name
`spacepayments`. The configured terminal must remain an active
zero-participation self-provider, while other zero-participation providers stay
outside the external candidate pool. This matches the supplied provider data
and TZ terminal convention.

## TZD-066 — direct terminal deviation needs report-level causality
Status: accepted and implemented.

Decision: when every external provider is hard-ineligible, terminal fallback can
legitimately produce a positive actual share against a zero target. A generated
probe showed that the previous rich report exposed the decision but not a
quantitative report recommendation. `ReportBuilder` now records terminal
fallback assignment count, hard-excluded alternative reasons and a deterministic
terminal-deviation recommendation with target/actual count and volume. This is
explanatory evidence only; terminal routing and accounting semantics are
unchanged.

## TZD-067 — independent semantic oracle fails closed on malformed raw inputs
Status: accepted and implemented.

Decision: the raw-input semantic validator is a strict validation boundary, so
malformed provider/queue/profile/report roots, identities and non-exact target
values must produce ordinary validation errors rather than uncaught method or
coercion exceptions. This does not replace the canonical Case input loader or
turn malformed data into valid domain input. The blind reproducer and regression
live in `test/case/report_semantic_test.rb`.

## TZD-068 — empty Case queues have exact zero report shares
Status: accepted and implemented.

Decision: because the canonical Case loader permits an empty queue, the
independent report oracle must validate its generated report rather than crash
on a zero denominator. An empty queue has exact zero count shares for every
provider; this is a Case/report boundary fact and does not alter production
routing semantics. Regression coverage lives in
`test/case/report_semantic_test.rb`.

## Open organizer assumptions

- exact accounting population intended by base report `distribution` when fallback occurs;
- exact hidden-queue day-span guarantee;
- exact hidden validator behavior beyond supplied contracts;
- exact simulated expiry algorithm and requisites lifecycle beyond supplied fields.

Keep these reversible and do not present assumptions as organizer facts.

## Closure record

v0.4.3 / SPEC-019 is VERSION_COMPLETE at exact pushed HEAD
`13efbeba48f1726b91b71b1677d3541dd4f9f433`; fresh verification and exact-head
Actions run `33852436704` passed. The remaining assumptions above are explicit
organizer ambiguities, not locally actionable defects.
