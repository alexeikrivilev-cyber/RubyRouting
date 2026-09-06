# SPEC-016 — Authoritative TZ Submission Engine

Status: **VERSION_COMPLETE**

Version Goal: **v0.4.0 — Authoritative TZ Submission Engine**

Opening code/data baseline: `f3f341f0493e3b15aab91c8bd4282130b1f21997` (`Data&scripts`).

Implementation status: the authoritative case engine and its required output,
validation, rubric-evidence and finalization gates are closed on the published
v0.4.0 tree. The contract remains authoritative for any future organizer
clarification.

## 1. Authority

The Hack.Genesis authoritative TZ is now the product contract. Repository pre-TZ specifications remain historical evidence and protected engineering rationale only where they do not conflict with the TZ.

Current precedence:

`direct current instruction > authoritative TZ > organizer data/sample/validator contract > SPEC-016 > active v0.4.0 ExecPlan > POST_TZ_BACKLOG > current post-TZ architecture/decisions > protected compatible pre-TZ guarantees > implementation/tests > historical pre-TZ plans/specs`.

The public `scripts/validate_10.rb` is a lower bound, not the complete specification. Manual/hidden evaluation is wider and the implementation must satisfy the TZ/rubric even where the public validator is permissive.

## 2. Product objective

Build a deterministic, explainable, configurable Ruby routing decision engine that processes the official dataset end-to-end:

`providers snapshot + operations history + current queue`
→ `hard eligibility`
→ `multi-factor soft-goal evaluation`
→ `formal conflict resolution`
→ `ordered provider attempts/fallback`
→ `sequential provider-state mutation`
→ `decision explanation`
→ `analytics + recommendations`
→ `routing_decisions*.json + routing_report*.json`.

The required competition use case is an offline/judge simulation. The existing real-payment execution-safety kernel remains protected and may be reused, but judge-specific semantics must not be forced into it when they conflict with real-payment safety.

## 3. Required inputs

The case runner must load and validate:

- `data/providers.json` — initial mutable provider snapshot;
- `data/operations_history.csv` — historical routing/outcome evidence for calibration and analytics;
- `data/operations_queue_10.json` and later `operations_queue_test.json` — sequential workload;
- organizer sample/reference decisions — format/golden evidence only;
- `scripts/validate_10.rb` — public compatibility validator.

Input parsing must be strict, deterministic, Ruby-only and fail with actionable errors. Provider names and counts must not be hardcoded into routing logic.

## 4. Required outputs

For every queue operation emit a decision containing at least the authoritative fields:

- `operation_id`;
- `selected_provider`;
- `attempts`;
- `simulated_result`;
- case-compatible latency when available/required by the chosen output contract.

Every attempt must preserve the organizer-compatible `provider`, `decision` (`selected` or `skipped`) and `reason` fields. Additional explanation fields are allowed only when compatible with the validator contract.

The final submission flow must generate in repository root:

- `routing_decisions_test.json`;
- `routing_report_test.json`.

No manual editing of generated submission JSON is part of the supported release workflow.

## 5. Hard-constraint authority

Hard constraints are absolute. A soft score can never resurrect an ineligible provider.

The authoritative hard layer must cover:

1. provider active/enabled status;
2. operation amount within provider min/max;
3. `daily_approved_amount + operation.amount <= daily_amount_limit`;
4. in-progress count limit;
5. in-progress amount limit;
6. bank allow-list and exclude-list semantics;
7. margin economics, including explicit negative-margin agreement where supplied/configured;
8. available requisites greater than zero;
9. requests-per-minute / rolling throughput limit;
10. configured external-provider participation such as zero traffic share where applicable.

Every exclusion emits a stable reason code suitable for attempts and aggregated report analytics.

## 6. Provider case state

The supplied provider snapshot is authoritative initial business state and is not equivalent to the current production `AdmissionLedger` alone.

The case state must model separately:

- daily approved amount and daily limit;
- externally supplied in-progress count/amount baseline;
- local transient in-progress count/amount;
- available requisites;
- rolling RPM events;
- current routing/settlement counters used by scoring/reporting.

Sequential semantics are mandatory: operation N+1 observes state mutations caused by operations/attempts 1..N.

Recommended transition for each attempted provider:

`eligibility check → transient in-progress reserve → RPM consume → deterministic outcome simulation → transient release → approved-only daily turnover increment`.

Do not invent permanent requisite consumption unless the authoritative dataset/clarification defines such lifecycle.

## 7. Traffic ledger

The case engine must track count and volume simultaneously for the relevant routing population.

At minimum:

- routed count per provider and total;
- routed volume per provider and total;
- target count share;
- target volume share;
- counterfactual post-decision count/volume state for every eligible candidate.

Exact Integer/Rational arithmetic from the existing core should be reused where possible. Floating-point drift must not become routing authority.

Historical data may seed/calibrate baselines where explicitly configured, but history is not ground truth for current hard eligibility.

## 8. Soft routing factors

The scored engine must support the rubric's independent business factors and their combination:

1. count-share deficit/correction;
2. volume-share deficit/correction;
3. cascade/priority preference;
4. amount-range preference distinct from hard amount eligibility;
5. current conversion/reliability preference;
6. current load/headroom preference distinct from hard capacity exclusion;
7. intensity/RPM headroom when configured;
8. minimum daily-turnover obligation/urgency;
9. other explicitly configured business parameters only when traceable to TZ/rubric.

Each factor must be typed/configurable and return inspectable evidence such as raw value, normalized score, configured weight/priority, contribution and reason. Do not introduce a general-purpose runtime DSL.

Current `conversion_24h` is the primary current conversion signal. Historical outcome evidence may provide context/confidence/trends but must not silently replace the current snapshot metric.

## 9. Conflict resolution

After hard filtering, multiple soft goals are resolved by one explicit deterministic authority.

The v0.4 case resolver must make simultaneous factors visible rather than selecting one policy measure (`count OR volume`) and using other objectives only on exact allocation ties.

A weighted normalized score is the preferred baseline because it is configurable and judge-explainable, provided:

- hard constraints stay outside the score;
- every contribution is bounded/normalized;
- weights are data/config, not buried constants;
- deterministic tie-breaking is explicit;
- infeasible goals are reported instead of forcing illegal routing.

Existing exact allocation/deviation functions may be reused as factor primitives; the case resolver must not duplicate arithmetic inconsistently.

## 10. Priority semantics

Official provider `priority` is interpreted as cascade rank: lower numeric value means earlier/higher priority unless the authoritative data/clarification proves otherwise.

Do not directly map this field to the legacy `RankingPolicy` convention where larger configured values are favored. The case mapper/resolver must normalize the semantics explicitly and test it.

## 11. Fallback and timeout semantics

For the authoritative hackathon simulation:

- rejected provider → exclude that provider and route to the next current eligible candidate;
- expired/timeout simulation → exclude that provider and route to the next current eligible candidate;
- hard constraints are reapplied against current mutable state before every next attempt;
- when the external provider pool is exhausted, use configured terminal self-provider `spacepayments`.

This judge rule must not globally weaken the production safety invariant that a raw real transport timeout is not automatically `definitely_not_sent`. Implement the competition timeout semantics in the bounded case simulator/adapter by mapping the authoritative simulated expiry to a safe fallback outcome.

`spacepayments` is a special terminal fallback, not an ordinary zero-share competitor. Configure its identity rather than hardcoding routing behavior around provider brand names.

## 12. Deterministic outcome simulation

Simulation must be reproducible for identical inputs and configuration. Do not use uncontrolled randomness.

A stable operation/provider/seed-derived value may be compared to configured conversion and expiry thresholds. The exact deterministic algorithm and seed must be documented and covered by golden tests.

Simulation must produce organizer-compatible `approved`, `rejected` and `expired` values and feed fallback/state/report logic consistently.

## 13. Explanation contract

Every operation must support a product-readable trace answering:

- why each provider was hard-excluded;
- which eligible providers were considered;
- factor values and contributions for considered providers;
- final composite score/order;
- why the selected provider won;
- which provider attempts failed/expired and why fallback continued;
- when/why `spacepayments` became terminal fallback;
- why a configured traffic target was infeasible or missed.

Internal production audit structures may be reused, but judge output must use concise case-facing reason codes and must not expose irrelevant provider-controlled diagnostics.

## 14. Analytics/report contract

`routing_report*.json` must include the mandatory TZ fields and may extend them with useful evidence.

At minimum report:

- period;
- total operations;
- distribution by provider;
- actual vs target count share and deviation;
- actual/target volume share and deviation where configured;
- approved/rejected/expired and success metrics;
- skip/exclusion reasons;
- provider load/utilization and limits;
- fallback metrics;
- causes of material target deviations/infeasibility;
- projected daily utilization where required;
- actionable recommendations.

Recommendations are deterministic rules backed by measured evidence and must name a concrete parameter/rule/action to change. Neural networks/LLMs are not part of the submission runtime.

## 15. History calibration

`operations_history.csv` may be used for:

- historical count/volume distribution;
- historical success/reject/expired rates;
- latency/tail metrics;
- confidence/trend context;
- explicitly configured derived defaults such as candidate volume targets.

Do not replay historical rows through the current provider hard constraints as if they were current-correct decisions; supplied history predates the current provider snapshot and contains routes incompatible with current bank rules.

Derived values must carry provenance in configuration/reporting and remain overridable.

## 16. Architecture boundary

Add a bounded competition layer (namespace/name may be `RubyRouting::Case` or equivalent):

`DatasetLoader → CaseConfiguration → ProviderCaseState → HardConstraintEvaluator → TrafficLedger → FactorEvaluator → ConflictResolver → Router/Simulator → DecisionSerializer → ReportBuilder/RecommendationEngine → CaseValidator`.

This is not permission to build a second unrelated router. Reuse pure existing primitives where semantics match and keep one authoritative decision path inside the case layer. Do not make HTTP/demo/report code choose providers independently.

The existing production execution kernel remains protected for economic ownership, provider I/O, UNKNOWN and durable recovery. Competition-only simplifications belong at the simulation adapter/use-case boundary.

## 17. Public validator and strict internal validator

Public compatibility is mandatory:

`ruby scripts/validate_10.rb <generated-decisions>` must pass the public dataset.

Because that validator is permissive, create a stricter internal validator that additionally checks:

- exactly one decision per queue operation, no duplicates/missing IDs;
- decision/attempt consistency;
- selected attempts satisfy hard constraints at the actual mutable-state point;
- state limits are never exceeded;
- deterministic fallback ordering and terminal self-provider legality;
- simulated outcomes are valid and consistent;
- report totals/shares/reasons recompute from decisions/state;
- recommendations reference real evidence;
- output file names/location for finalization.

## 18. Public golden acceptance cases

The supplied 10-operation dataset must prove at least:

- `op_103` routes to `quickpay` because amount excludes `vipay`/`payflow`;
- `op_104` routes to `quickpay` because bank constraints exclude alternatives;
- `op_107` routes to `payflow` because it is the only valid external provider for the low amount;
- `op_108` routes to `quickpay` because bank constraints exclude alternatives;
- sequential daily-state logic prevents an illegal payflow approval beyond remaining daily headroom;
- hard-forced quickpay traffic can make target count/volume shares mathematically infeasible and the report explains the deviation.

The current public dataset contains 385,800 RUB of queue volume; the three hard-forced quickpay operations account for 195,000 RUB, making a low quickpay volume target infeasible if configured below that forced share. Use exact values from the loaded data in tests/report, not copied constants in routing code.

## 19. Rubric acceptance

Before `VERSION_CANDIDATE`, demonstrate executable evidence for every scored area:

- correctness/hard constraints/fallback/state mutation;
- count, volume, priority, amount preference, conversion, load/intensity, business obligations;
- combined strategy/conflict resolution and infeasible-goal behavior;
- selected/excluded/fallback explanations;
- analytics and concrete recommendations;
- architecture/configurability/error handling;
- exact required final files and validator compatibility.

Maintain `docs/TZ_REQUIREMENT_MATRIX.md` as the traceability source from requirement → current status → implementation/test/output evidence.

## 20. Finalization command

Before the hidden queue arrives, provide one deterministic command/script that accepts the test queue and produces both root submission files, then executes strict internal validation plus organizer-compatible validation where applicable.

The last-hour workflow must require no code changes and no hand-edited JSON.

## 21. Protected compatible baseline

Preserve unless authoritative case evidence requires a change:

- Ruby-only executable logic;
- exact Integer/Rational financial/allocation arithmetic;
- deterministic provider-independent abstractions;
- hard-gate-before-optimization separation;
- structured reason/evidence traces;
- bounded configuration parsing;
- test/property/model/concurrency/fault discipline;
- production UNKNOWN/economic-ownership safety outside the bounded competition simulator.

## 22. Explicit non-goals for v0.4.0

Do not spend scoring-critical time on:

- more generic recovery/restart hardening absent a TZ blocker;
- Rails/ORM, PostgreSQL, Redis/Sidekiq, queues, leases or microservices;
- real PSP integrations;
- ML/bandits/neural networks;
- general rules DSL or dynamic code plugins;
- large cosmetic Coordinator/Analytics refactors;
- distributed production guarantees not required by the case;
- dashboard polish before exact submission/report correctness.

## 23. Completion contract

Known scope green is only `VERSION_CANDIDATE`.

`VERSION_COMPLETE` for v0.4.0 requires:

1. every mandatory TZ requirement classified and traced;
2. all public golden cases pass;
3. organizer public validator passes generated public decisions;
4. strict internal validator passes;
5. generated decisions/report are internally consistent and deterministic;
6. all rubric factor/reconciliation demonstrations are executable;
7. full inherited test/property/model/concurrency/fault suites remain green or any deliberate case-boundary divergence is explicitly isolated/tested;
8. dry-run finalization from a clean checkout succeeds;
9. blind code-first/data-first skeptical pass finds no material P0/P1;
10. exact pushed-HEAD GitHub Actions is green and documentation matches that tree.
