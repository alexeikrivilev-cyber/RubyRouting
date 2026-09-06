# ExecPlan — v0.4.0 Authoritative TZ Submission Engine

Status: **VERSION_COMPLETE**

Specification: `specifications/016-authoritative-tz-submission-engine.md`

Opening baseline: `f3f341f0493e3b15aab91c8bd4282130b1f21997`.

## Objective

Turn the strong pre-TZ routing kernel into a complete authoritative Hack.Genesis submission pipeline without sacrificing time on non-scoring infrastructure. The session should progress autonomously from official input parsing through hard constraints, mutable simulation state, combined business scoring, fallback, decisions/report generation, strict validation and rubric evidence.

## Operating rule

Do not implement from documentation assumptions alone. For each slice inspect actual `data/`, `scripts/validate_10.rb`, current production code and tests first. Reuse existing primitives only when semantics match the TZ. When the TZ differs from real-payment semantics, isolate the difference in the bounded competition layer instead of weakening the protected production kernel.

Any failure to generate correct required root files, any deterministic public-validator failure, hard-constraint violation, illegal mutable-state transition, or missing queue operation is P0 for this version.

## Phase 0 — exact orientation and authority switch

- verify exact `main`, tree and CI;
- read SPEC-016, TZ requirement matrix, this plan, post-TZ backlog, data files and public validator;
- confirm the public data metrics used by golden tests from files, not copied analysis;
- identify reusable pure components versus incompatible pre-TZ semantics;
- keep v0.3.11 completed and frozen unless a TZ-required integration actually breaks it.

Exit evidence: documented implementation map and no unresolved authority ambiguity blocking P0 work.

## Phase 1 — end-to-end case pipeline skeleton — P0

Status: **SUPPORTED on current working tree; checkpoint pending**.

Evidence: `lib/ruby_routing/case/input.rb`, `case/state.rb`, `case/router.rb`,
`case/report.rb`, `case/runner.rb`, `bin/ruby_routing_case`, and 12 focused
tests under `test/case/`. `bundle exec rake case` is green; generated public
decisions pass `ruby scripts/validate_10.rb <generated-output>` with 0 errors.
The current baseline intentionally uses a deterministic priority-ordered
eligible-provider resolver; multi-factor competition selection remains Phase 4–6.

Implement a single Ruby entry point/use-case that can:

1. load providers/history/queue;
2. validate input shape/types;
3. route every queue item deterministically;
4. serialize decisions;
5. build a report;
6. write caller-specified output paths.

At this stage routing may still use a simple deterministic eligible-provider baseline, but the pipeline must be real and testable. No hand-written output fixture may masquerade as generated evidence.

Required acceptance:

- 10 queue operations produce exactly 10 decisions;
- no duplicate/missing IDs;
- deterministic byte-equivalent output for fixed inputs/config where serializer ordering is defined;
- CLI errors are non-zero and actionable;
- production HTTP/demo paths are not the new routing authority.

## Phase 2 — official provider/input mapping and hard constraints — P0

Status: **SUPPORTED for the fields present in the official snapshot, including
bounded RPM configuration and reporting.**

Evidence: `HardConstraintEvaluator` covers status, zero participation, exact
amount bounds, daily amount, supplied + transient in-progress count/amount,
bank allow/exclude, margin/agreement, requisites and rolling RPM. Public
goldens and generated validator output are green.

Create bounded typed case input/config/state mappings for:

- status;
- amount min/max;
- daily amount limit/current approved amount;
- in-progress count/amount;
- bank allow/exclude lists;
- provider/merchant margin plus negative-margin agreement;
- available requisites;
- configurable rolling RPM;
- traffic participation;
- official priority and conversion metrics.

Hard constraints must run before any soft factor.

Golden acceptance from supplied public data:

- `op_103 -> quickpay`;
- `op_104 -> quickpay`;
- `op_107 -> payflow`;
- `op_108 -> quickpay`;
- stable skip reason codes align with organizer reference vocabulary where known.

Run `scripts/validate_10.rb` against generated public decisions after this phase and keep it green thereafter.

## Phase 3 — sequential ProviderCaseState — P0

Status: **SUPPORTED for baseline/transient/daily/RPM mutation with strict replay.**

Evidence: `test/case/state_test.rb` proves supplied baseline separation,
reserve/release ordering, approved-only daily mutation, exact RPM window
boundary and no-mutation invalid-release handling. The provider snapshot's
initial counters are never reconstructed from history.

Model official mutable provider state separately from the existing in-flight execution ledger:

- baseline daily approved amount;
- daily limit;
- external snapshot in-progress count/amount;
- local transient in-progress exposure;
- requisites availability;
- rolling RPM events;
- attempt/outcome counters.

For every actual attempt:

`check -> reserve transient load -> consume RPM -> simulate -> release transient load -> approved-only daily increment`.

Acceptance:

- later operations observe earlier approved daily turnover;
- no selected attempt can exceed daily/in-progress/RPM limits at its decision time;
- external baseline load is not fabricated as fake payout history;
- state updates affect only the attempted/chosen provider;
- deterministic tests cover payflow's tight public daily headroom.

## Phase 4 — simultaneous TrafficLedger — P1 highest ROI

Status: **SUPPORTED as an exact case primitive with fresh strategy campaign.**

Evidence: `case/traffic.rb` and `test/case/traffic_test.rb` track count and
volume in one ledger, expose exact shares and counterfactual post-decision
values, reject explicit null targets and empty provider identities, and are now
the report distribution source. `case/factors.rb` and configuration tests also
reject malformed bounded minimum-turnover maps before execution.

Add one case ledger that tracks both routed count and routed volume simultaneously and supports exact counterfactual post-decision evaluation per candidate.

Reuse exact Integer/Rational math from the existing allocation implementation where coherent; do not duplicate inconsistent share arithmetic.

Acceptance:

- count and volume can both contribute to one decision;
- exact shares/deviations are reproducible;
- hard-forced quickpay public cases are recognized as target-feasibility constraints;
- count-only and volume-only configurations remain possible through weights/config.

## Phase 5 — typed routing factors — P1

Status: **SUPPORTED as typed factor evidence; isolated all-factor and weight-conflict campaign is green.**

Evidence: `case/factors.rb` implements count, volume, official priority,
amount preference, current conversion, load/headroom, RPM intensity and
minimum-turnover urgency. `test/case/factors_test.rb` proves exact evidence,
lower numeric priority and simultaneous count/volume traces.

Implement/configure factor results for:

- count share;
- volume share;
- cascade priority (lower official rank = stronger preference);
- amount preference independent of hard amount gate;
- `conversion_24h`;
- load/headroom;
- intensity/RPM headroom;
- daily-turnover-min urgency.

Each factor exposes raw input, normalized score, weight, contribution and concise reason. Avoid arbitrary DSL/plugin infrastructure.

Acceptance: one focused scenario/test per factor proves that changing only that factor can change ranking between otherwise eligible providers.

## Phase 6 — one ConflictResolver — P1 / rubric critical

Status: **SUPPORTED as the sole current case selection authority; broader
conflict campaigns remain closure work.**

Evidence: `Case::ConflictResolver` is the only Router ranking path; hard
eligibility is evaluated before it, and all selected candidate traces expose
raw/normalized/weight/contribution values.

Combine all enabled factor results through one deterministic formal authority. Default baseline is weighted normalized score with explicit deterministic tie-break.

Requirements:

- hard constraints never become score penalties;
- weights are configuration data;
- no hidden second ranking path;
- score trace is preserved for decisions/report;
- impossible targets remain visible as infeasibility/deviation evidence.

Required conflict campaigns:

1. count pressure vs volume pressure;
2. conversion vs load/headroom;
3. traffic target vs minimum-turnover obligation;
4. priority/amount preference vs another business factor;
5. target impossible because hard eligibility/capacity forces another provider.

## Phase 7 — deterministic simulation and fallback — P1

Status: **SUPPORTED: deterministic approved/rejected/expired and terminal
fallback are implemented; terminal non-approval is preserved as a final case
decision without approved-route accounting.**

Implement competition-specific provider outcome simulation with fixed documented seed/algorithm.

- support approved/rejected/expired;
- rejected/expired exclude that provider and rerun current hard filtering/ranking;
- every fallback sees current mutable provider state;
- exhausted external pool uses configured `spacepayments` terminal fallback;
- `spacepayments` never competes as an ordinary zero-target external provider.

Do not change production raw-timeout/UNKNOWN semantics. Judge `expired` maps to safe fallback only inside the competition simulation boundary.

Acceptance:

- rejection fallback;
- expiry fallback;
- multiple failed external attempts;
- self-provider terminal fallback;
- same fixed inputs produce identical attempt sequence/outcome.

## Phase 8 — judge decision output and explanations — P1/P0 delivery

Status: **SUPPORTED: organizer-compatible decisions, deterministic factor
traces and privacy-safe case explanations are generated.**

Build organizer-compatible decisions from the actual case run.

Mandatory fields and enum values must satisfy public validator. Preserve full actual attempt order. Additional fields must be compatibility-tested.

Selected/excluded explanations must include stable reason codes; scored candidates should expose concise factor/score evidence without leaking unrelated production internals.

Resolve and document the chosen semantics of top-level `selected_provider` versus final settlement provider. If the TZ/sample/validator remains ambiguous, make the assumption explicit, cover both concepts internally and minimize hidden-validator risk.

## Phase 9 — report and deterministic recommendations — P1

Status: **SUPPORTED: report projects the required period/operation totals plus
TrafficLedger/state/history with exact deviations, utilization, explanations,
success metrics, hard-forced causes and infeasibility.**

Evidence: `case/report.rb`, generated public report, and runner/strict-validator
tests. History is explicitly labeled calibration/trends only and does not feed
current hard eligibility.

Generate mandatory report fields plus:

- count and volume distribution;
- targets and deviations;
- approved/rejected/expired;
- provider utilization/limits;
- fallback metrics;
- skip/exclusion reasons;
- infeasible-target reasons;
- actionable recommendations.

Recommendation rules must be evidence-backed and specific, e.g. target/weight/limit/bank coverage changes. No LLM/neural runtime.

## Phase 10 — history calibration — P1 after core

Status: **SUPPORTED for typed historical count/volume/outcome/latency analytics;
derived-target policy remains explicitly configurable and not enabled by default.**

Load the 100-row history for analytics/calibration:

- count/volume baselines;
- provider outcome rates;
- latency/tail statistics;
- optional confidence/trend context;
- explicit derived defaults such as volume targets if selected.

Never use current hard rules to label historical routing as invalid ground truth. Current snapshot `conversion_24h` remains the primary current conversion input.

Derived values must be configurable and report their source.

## Phase 11 — strict internal validator — P1

Status: **SUPPORTED for current case run invariants and deterministic replay of
hard eligibility, resolution, simulation, traces and state mutation at every
attempt.**

Evidence: `case/validator.rb`, `test/case/validator_test.rb`, and the
clean-checkout public finalization dry run. The validator checks coverage,
attempt legality, state/traffic conservation and report recomputability.

Build validation stricter than `validate_10.rb`:

- complete/unique queue coverage;
- attempts/top-level consistency;
- exact stateful hard eligibility at each selected attempt;
- no limit overshoot;
- legal terminal fallback;
- deterministic outcomes;
- report recomputation consistency;
- output location/name checks for final submission.

Keep organizer validator as a separate compatibility gate.

## Phase 12 — scoring/traceability campaign — P1

Update `docs/TZ_REQUIREMENT_MATRIX.md` with real file/test/command evidence for every mandatory/rubric row.

Demonstrate executable scenarios for all scored factors and combined-strategy reconciliation. Missing rubric evidence remains open even if tests are green.

## Phase 13 — finalization dry run — P0 release gate

Status: **SUPPORTED on the public queue; hidden/test queue remains an external
data input, with the same clean-checkout command path and no basename-based
public-validator confusion.**

Evidence: `bin/finalize_submission --queue data/operations_queue_10.json` and
`rake finalize_submission` generate both required root files, run strict
validation, and run the public validator with 0 errors.

Provide one command accepting the hidden/test queue path and generating exactly:

- `routing_decisions_test.json`;
- `routing_report_test.json`.

Then run strict validation and organizer-compatible validation automatically. The workflow must succeed from a clean checkout without code changes or manual JSON edits.

Do a dry run with the public queue into temporary/root-equivalent outputs before candidate.

## Phase 14 — candidate and blind skeptical discovery

Known scope is now **VERSION_CANDIDATE only** after fresh generated public
artifacts, public validator, case suite and inherited matrix on the current
tree.

Run a fresh code/data-first skeptical pass ignoring backlog completion. Attack:

- any hard rule missing from a fallback attempt;
- state mutation order/off-by-one daily/RPM errors;
- priority inversion;
- count/volume denominator mistakes;
- factor normalization/weight dominance mistakes;
- uncontrolled randomness;
- `spacepayments` entering ordinary competition;
- serializer/hidden-validator fragility;
- report values not recomputable from decisions;
- history accidentally overriding current config;
- competition timeout changes leaking into production UNKNOWN safety;
- hand-authored fixture evidence;
- missing root outputs/finalization failure.

Any material locally solvable P0/P1 returns ACTIVE.

The current pass found and closed one such gap: Router evaluates rolling RPM
at each operation's `created_at`, so accepting a decreasing queue timestamp
made the result order-dependent. `Input.load_queue` and `Dataset` now share a
fail-closed non-decreasing queue-order invariant; `test/case/input_test.rb`
covers both construction paths. Equal timestamps remain a valid deterministic
sequence. The same pass found that Router's special terminal fallback bypassed
terminal amount/daily/status/requisite constraints; Router and strict replay
now apply `HardConstraintEvaluator` with `terminal: true`, and
`AuthoritativeCaseRunnerTest#test_terminal_fallback_rechecks_hard_constraints`
proves an ineligible terminal fails closed. The tree must return to
VERSION_CANDIDATE only after fresh case/inherited verification and exact
pushed-HEAD CI for this closure; those checks are green on pushed
`834fdbd93f7b06b0fc72a666e4bcd90ecdbe1c77`.

## Phase 15 — blind terminal outcome closure — VERIFIED

The next code/data-first pass constructed a valid exhausted-pool run with
explicit terminal `rejected`/`expired` simulation. The previous Router raised
and emitted no decision, contradicting the total per-operation output contract.
The minimal fix keeps the eligible terminal as the final selected attempt,
preserves its exact simulated outcome, releases transient state, and counts
traffic/daily/routed state only for approval. Strict replay and conservation
checks use the same rule. Focused runner/validator tests pass; inherited and
exact pushed-HEAD verification remain required. Fresh exact `910f23f` verification
is green: test 793/13220, property 4/1210, model 3/2958, concurrency 45/1444,
fault 407/4900, case 53/257; finalization/public validator 29 passed with zero
errors/warnings.

## Phase 16 — final closure — VERSION_COMPLETE

The independent blind code/data audit found no further material P0/P1 after the
terminal outcome correction. It covered loaded-data goldens, all hard gates,
temporal ordering/equal timestamps, deterministic replay, history isolation,
explicit terminal identity, terminal hard legality, terminal non-approval
accounting, strict report recomputation and output privacy. The final published
tree is required to retain the fresh full matrix, generated public outputs,
clean-checkout finalization and exact pushed-HEAD CI evidence.

## Verification stack

After each material slice: focused tests first, then relevant adjacent case/core tests.

Before candidate/final closure run from exact tree:

- `bundle check`;
- full `bundle exec rake test`;
- property/model/concurrency/fault suites;
- new case input/hard/state/factor/conflict/fallback/output/report tests;
- public golden campaign;
- `ruby scripts/validate_10.rb <generated public decisions>`;
- strict internal case validator;
- clean-checkout finalization dry run;
- requirement/rubric traceability checks;
- exact pushed-HEAD GitHub Actions.

Do not declare completion while exact-head CI is pending.

## Non-goals

No Rails/ORM, DB, queues, Redis, Sidekiq, distributed leases, real PSP integration, ML/bandits/neural networks, generic rules DSL, dynamic plugin framework, broad Coordinator rewrite, or new recovery hardening unless required to unblock the authoritative case.

## Rolling next actions

Keep only 2–5 immediate actions at a time. Current queue:

1. No open v0.4.0 action remains; preserve the bounded case/production boundary.
2. If new organizer authority arrives, reconcile it before TZ-specific changes.
