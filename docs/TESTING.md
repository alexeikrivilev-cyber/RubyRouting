# Testing Strategy

Current Version Goal: **v0.4.1 / SPEC-017 — VERSION_COMPLETE**.

Preserve all inherited production and v0.4.0 case suites. Add release-path tests that attack the gaps a component-level suite can miss.

## 1. SubmissionProfile tests

Prove:

- finalization and supported CLI load the same canonical profile;
- count targets derive from official external `traffic_percentage`;
- volume target source is explicit/provenanced;
- enabled factor weights are exact and non-accidental;
- changing profile weights changes a controlled decision without code changes;
- canonical finalization-equivalent selection trace contains the intended factors;
- simulation seed/mode and terminal provider are explicit.

A demo-only factor test does not close release activation.

## 2. Accounting tests

Fallback scenario must assert separately:

- primary assignment provider/count/volume;
- actual attempted provider sequence;
- final approved/settlement provider/count/volume;
- daily approved mutation;
- next operation's count/volume objective uses the documented assignment ledger.

Rejected/expired assignment may not vanish from routing-distribution accounting merely because settlement failed.

## 3. Attempt/output tests

Internal model distinguishes hard exclusion from attempted rejection/expiry. External projection tests assert documented top-level `selected_provider` and `selected|skipped` semantics.

Generate minimal decisions JSON, parse it back, and validate actual JSON types/keys. Rich factor traces should be tested in report/internal evidence rather than required external decisions.
Malformed serialized identity types must return explicit strict-validation errors without crashing the validator.

## 4. Independent amount-preference tests

Provider remains hard eligible outside preferred band, but preferred-band score changes ranking. Malformed/overlapping configuration behavior must be deterministic and documented.

## 5. Serialized report tests

After write/read:

- assignment distribution recomputes;
- settlement distribution recomputes;
- outcomes/fallbacks recompute;
- target deviations use assignment authority;
- ratio/share representation is deliberate and judge-readable;
- configuration/profile provenance is present;
- recommendations reference real causal evidence.

## 6. Finalization intelligence tests

Run the exact finalization-equivalent configuration on controlled datasets and assert:

- not priority-only;
- not forced always-approved;
- count+volume can jointly affect selection;
- conversion/load can affect a conflict;
- reject/expired can cause fallback;
- public four goldens remain valid.

## 7. Hidden-like robustness

Use bounded larger campaigns with additional provider identities and hundreds/thousands of operations. Assert deterministic runtime/output and remove avoidable repeated linear lookup in validators. Do not add a database/index service.

Cover equal timestamps, RPM windows, daily headroom exhaustion, deep fallback, terminal non-approval, custom queue path and extra provider identity.
RPM/daily boundary regressions should use canonical `SubmissionProfile` ingress, with any isolation weights or limits explicit in the temporary profile.

## 8. Verification order

For each material slice:

`reproducer → focused test → adjacent accounting/fallback/profile tests → public queue → fresh serialization/reparse strict validation → public validator → relevant inherited suites`.

Before candidate/final closure:

`bundle check; rake test; property; model; concurrency; fault; rake case; public validator; post-serialization strict validation; hidden-like campaign; clean finalization; blind skeptical pass; exact pushed-HEAD CI`.
