# ExecPlan — v0.4.1 Submission Policy Activation & Contract Closure

Status: **VERSION_COMPLETE**

Specification: `specifications/017-submission-policy-activation-contract-closure.md`

Opening baseline: `0187bf2558d58a52dfdb27e76694d6323addbcd6`.

Historical note: the Phase 2 primary-assignment accounting point below was the
v0.4.1 contract. S21-H101 subsequently superseded its online target-ledger
timing for the current v0.4.4 product: primary assignment remains explicit,
while `Router#traffic` now commits the final selected provider after the
cascade. This completed plan is retained as historical provenance.

## Objective

Turn the completed v0.4.0 case engine into a submission path that actually uses its smart routing capabilities and has unambiguous accounting/output semantics. Work evidence-first; do not redesign working hard/state infrastructure.

## Phase 0 — reproduce opening gaps — COMPLETE

Before production changes, add/fix focused tests proving the baseline facts:

1. default `finalize_submission` configuration is priority-only with empty targets;
2. default simulation is always approved;
3. rejected/expired assignments disappear from current TrafficLedger distribution;
4. failed attempted providers are represented as `skipped` internally/output;
5. amount preference is coupled to hard min/max;
6. serialized artifacts are not strict-revalidated after write.

If any finding is false on current HEAD, update plan/matrix instead of implementing the assumed fix.

Evidence on exact opening HEAD `671abc44`: default finalization produced
`priority`-only weights, zero count/volume targets and `approved` simulation;
forced rejection was represented as a `skipped` attempt and was absent from
`TrafficLedger`; `AmountPreferenceFactor` read the hard amount limits; and the
finalizer validated only the in-memory run before writing JSON.

## Phase 1 — canonical SubmissionProfile — VERIFIED

Create one typed profile/default builder and make `Runner`, case CLI and finalization converge on it.

Acceptance:

- count targets derive from loaded `traffic_percentage` for participating externals;
- volume target source is explicit and reported;
- factor weights/profile source/revision are explicit;
- simulation mode/seed explicit;
- no demo-only chooser;
- CLI can override profile/config for controlled tests without changing code;
- a finalization-equivalent controlled scenario exposes count, volume and business-factor traces.

Checkpoint with focused config/CLI/finalization tests plus public validator.

Implemented in the current working tree: typed `SubmissionProfile` loaded from
`data/submission_profile.json`; default `Runner`, `bin/finalize_submission` and
`bin/ruby_routing_case` all use it. The profile derives count and volume targets
from active external `traffic_percentage`, enables count/volume/priority/
amount/conversion/load with exact weights, carries an independent preferred
amount-band map, deterministic conversion seed and terminal identity. Focused
profile, CLI and finalization tests pass. A controlled same-input campaign
proves that changing only profile weights changes the selected provider, and a
default-profile finalization-equivalent run exposes simultaneous count, volume
and current-business factor evidence. The supported CLI also has a deterministic
conversion fallback regression.

## Phase 2 — accounting split — VERIFIED

Introduce explicit primary-assignment, attempt and settlement accounting while keeping exact arithmetic.

Acceptance:

- first selected provider records assignment before simulation outcome;
- rejected/expired first attempt stays in assignment/attempt metrics;
- only approved final provider records settlement/daily approved turnover;
- report recomputes both assignment and settlement distributions;
- strict validator independently recomputes both;
- count/volume routing factors read the documented assignment ledger, not settlement ledger.

Run fallback-heavy campaign and assert next routing decisions do not silently compensate provider failures as if no assignment occurred.

Implemented in the current working tree: `TrafficLedger` is now the explicit
primary-assignment ledger and records the first selected provider before its
outcome. `AttemptLedger` records every invoked provider/outcome and
`SettlementLedger` records approved final providers only. Router replay and
strict conservation checks use the assignment ledger for count/volume targets;
focused fallback/terminal accounting tests pass. Strict stateful replay,
post-serialization validation and dedicated edge campaigns recompute the three
ledgers without double counting fallback attempts.

## Phase 3 — attempt model / organizer projection — VERIFIED WITH DOCUMENTED ASSUMPTION

Separate internal attempt semantics from organizer `selected|skipped` projection.

Acceptance:

- hard exclusion is distinguishable from attempted failure;
- actual attempt order preserved;
- internal primary/final provider identities preserved;
- external DTO assumption is documented and covered by public validator plus strict serializer tests;
- rich score evidence lives in report/internal data, not required in minimal decisions output.

Do not invent organizer facts. Keep projection reversible.

Implemented: internal `Attempt#classification` distinguishes hard skips from
invoked approved/rejected/expired and terminal non-approval. Invoked failures
are projected as organizer `selected`, while only hard exclusions are
`skipped`; in-memory selection traces remain available to the report and
replay. Strict validation now permits ordered fallback attempts and checks the
projection. A minimal decisions DTO no longer includes score traces. The
public validator accepts a real multi-attempt projection on the official
queue. The remaining top-level selected-provider meaning is an explicit
conservative organizer assumption, preserved internally as primary versus
final identity and covered by compatibility tests; no organizer fact is
inferred from the validator.

## Phase 4 — independent amount preferences — VERIFIED

Add typed preferred amount bands separate from hard min/max and profile support.

Acceptance:

- provider can be hard-eligible but soft-disfavored by amount preference;
- malformed bands fail closed;
- amount preference weight can change ranking in isolation and conflict scenarios;
- public hard amount goldens unchanged.

`CaseConfiguration#preferred_amount_ranges` and the profile data file provide a
typed preferred band independently of hard provider limits. The factor is
neutral when no band is configured and never participates in hard eligibility.
The factor campaign proves two hard-eligible providers rank differently only
because their preferred bands differ, and malformed/reversed bands fail closed.

## Phase 5 — serialized artifact contract — VERIFIED

Add post-write validation:

- parse generated decisions/report back from disk;
- verify types/enums/coverage/consistency;
- recompute required totals;
- check exact filenames for finalization;
- define stable JSON representation of exact ratios in report;
- keep public validator green.

Add minimal-output mode/default for decisions. Rich report remains available.

`SerializedArtifactValidator` reparses both written files, checks actual JSON
shape/types/coverage, rejects unsupported decision fields, compares the
artifacts with the validated run and requires assignment/attempt/settlement
report projections. Both supported CLIs invoke it after writing. Report
recomputation uses the run's canonical ledgers, and the report explicitly
declares the exact Rational JSON representation. Tampered report totals and
extra decision traces are rejected after parsing; focused serializer tests pass.

## Phase 6 — analytics/recommendation correction — VERIFIED

Update report for assignment vs settlement and correct recommendation causality.

Acceptance:

- over-target hard-forced provider recommendation does not default to expanding that same provider's capacity;
- under-target due to own hard restrictions identifies actual exclusion causes where evidence exists;
- report distinguishes routed/attempted/approved counts and volumes;
- all recommendations include provider, evidence and concrete parameter/rule action.

Implemented slice: reports expose assignment, attempt and settlement
distributions/totals plus per-provider attempt outcomes and hard-exclusion
reasons. Hard-forced over-target recommendations now point to target adjustment
or improving alternatives rather than blindly expanding the already over-target
provider. Fallback metrics count an actual transition to a later attempt, so
terminal-only non-approval is not mislabeled as continuation. Under-target
recommendations carry observed hard-exclusion causes, over-target hard-forced
recommendations point to target/alternative changes, and serializer/report
regressions pass.

## Phase 7 — hidden-like robustness — VERIFIED

Use larger deterministic synthetic datasets. Replace repeated linear lookup in strict validator with maps where useful. Test:

- hundreds/thousands of operations within practical CI bounds;
- more than four providers;
- duplicate/unknown IDs;
- equal timestamps and RPM boundary;
- daily exhaustion after prior approvals;
- repeated rejection/expiry chain;
- terminal approved/rejected/expired;
- custom queue path;
- identical inputs → byte-stable minimal decisions and stable report values.

No premature performance architecture.

The current campaign runs 1,000 deterministic operations through a fresh
five-provider dataset, validates stateful replay and accounting, and compares
serialized decisions/report values across two fresh runs. Edge campaigns also
cover equal timestamps, exact RPM cutoff behavior, daily approved mutation and
terminal settlement under strict replay. Existing input/fallback tests cover
duplicate/unknown IDs, repeated non-approved chains and custom queue paths.
This is evidence for practical scale and determinism, not a 100k benchmark.

## Phase 8 — rubric evidence / finalization — VERIFIED

Run exact supported finalization path and prove it is smart-policy activated. Produce a concise machine-checkable evidence report/config snapshot showing active targets, weights, profile source and simulation mode.

Evidence on the current candidate tree: `bundle exec rake finalize_submission`
generates both root artifacts, post-write strict validation passes, the public
validator reports 29 passed/0 failures/0 warnings, and the report records
profile `official-smart-v0.4.1`, explicit target sources, six active factor
weights, deterministic conversion mode/seed and separate assignment/attempt/
settlement totals. Public queue requirements remain green, but are not the sole
evidence.

## Phase 9 — VERSION_CANDIDATE and blind audit — COMPLETE

After known P1s close, mark candidate only. Start a fresh code/data/output audit with no reliance on backlog status. Attack:

- silent fallback to CaseConfiguration defaults;
- disabled/zero target factor claimed active;
- assignment/settlement denominator mistakes;
- double accounting on fallback;
- output projection semantics;
- Rational JSON type surprises;
- hard-rule bypass at terminal/fallback;
- overfit weights;
- history leaking into current eligibility;
- finalization divergence from CLI/demo;
- O(N²) hidden-scale regressions.

Any material P0/P1 → ACTIVE.

The latest code-first audit found and closed fail-open seams: competing
profile/configuration authorities or policy overrides in `Runner`/`Router`,
duplicate canonical preferred-band keys/fields in `ConflictResolver`, and a
fallback explanation that mixed the primary reason with the final provider.
All now fail closed or project distinct primary/final facts with focused
regressions; no alternate chooser was introduced.

The tree was marked `VERSION_CANDIDATE` before the independent pass. The pass
independently inspected all entrypoints, profile ingress, serialized artifacts,
fallback and terminal paths, exact arithmetic, recommendation/report
recomputation and hidden-like scale. Checklist status was not used as evidence.

That audit also found that the runnable demo's conversion branch bypassed the
submission profile with priority-only empty targets. It now uses the exact
profile/Router/Report path; a bounded explicit expiry fixture demonstrates
fallback without introducing a second policy authority. The demo regression
checks profile provenance, active targets/factors and fallback evidence.

The same audit then reproduced a strict-validator crash on a serialized mixed
String/Integer operation-id list. Validation now reports malformed id types and
skips unsafe sorting, with a deterministic regression proving invalid artifacts
are returned rather than raised as an uncaught `ArgumentError`.

The blind audit also reproduced a second configuration authority: constructing
`CaseConfiguration` with canonical `targets` plus non-empty legacy share maps
silently discarded the maps. The constructor now rejects that ambiguous input;
the boundary regression covers both direct construction and `from` decoding.

The same audit found the equivalent profile ingress ambiguity: a profile whose
volume target source was `provider.traffic_percentage` could include a
`volume_share` map that was silently ignored. Profile loading now rejects that
field for the derived source, while still requiring it for `configured` volume
targets.

The blind boundary pass also found that a malformed non-Hash `rpm_limits`
override on the profile-backed router path raised a raw `NoMethodError` while
checking for a competing policy authority. The router now classifies that
input as a typed policy-override `InputError` before any run is built; the
focused boundary regression is green.

A second blind pass reproduced explicit `false` values being mistaken for
absent optional authorities: profile/configuration inputs and router policy
overrides could fall back to the default policy, while `targets: false` could
fall back to empty shares. Runner/router/configuration now use nil-presence and
typed checks; boundary regressions cover every affected input.

The continued simulator boundary pass found the same class of issue in
case-only controls: a non-Hash outcomes map and a non-String seed previously
leaked a method error or string coercion, and structured outcome keys were
coerced. `DeterministicSimulator` now requires typed seed/outcomes and exact
two-part scalar identities; focused runner/finalization/demo regressions pass.

The final blind pass found no additional material P0/P1. It re-ran malformed
authority and simulator probes, checked default/profile/CLI/demo convergence,
recomputed accounting and report projections, and retained the explicit
organizer ambiguity assumption for top-level selected-provider semantics.

Finally, RPM-boundary and daily-exhaustion campaigns now run through temporary
strict `SubmissionProfile` inputs with explicit test-only policy overrides;
their state assertions therefore cover the canonical profile ingress without
turning a priority-isolation fixture into the submission default.

An additional malformed-artifact campaign found that JSON `null`/`false` roots
were skipped by conditional root validation. The validator now always checks
both expected roots, so null/false documents are invalid rather than silently
accepted; the serialized regression and mixed-type campaign are green.

## Phase 10 — final closure — COMPLETE

Fresh production tree at checkpoint `33011df926599a9b02aefd710fcfa1b00e5fcfaa`:

- `bundle check`;
- `bundle exec rake test`;
- property/model/concurrency/fault;
- `bundle exec rake case`;
- public validator against freshly generated minimal decisions;
- strict post-serialization validators;
- hidden-like campaigns;
- clean-checkout finalization;
- docs/traceability consistency;
- push the reconciled completion tree and wait for exact-head Actions success.

Evidence on the production checkpoint: `bundle check`, full `bundle exec rake test` (822 runs / 13,422
assertions), property/model/concurrency/fault/case suites, public validator
(29 passed / 0 failures / 0 warnings), strict post-serialization validation,
conversion fallback demo, bounded scale/history/read-path/degradation
campaigns, and exact-head GitHub Actions run 33800960272 all passed. The
completion docs below are a docs-only reconciliation of that verified
production tree; the final pushed completion SHA must receive its own exact-head
verification and Actions result.

## Rolling next actions

1. Preserve v0.4.1 as the completed authoritative submission baseline.
2. Reconcile only a new authoritative organizer/TZ clarification or a fresh material counterexample.
