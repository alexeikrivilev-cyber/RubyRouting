# Completion Policy — no premature "done"

This is the normative completion contract for RubyRouting coding agents.

## 1. Core rule

Completion is an evidence claim, never a feeling, checklist result, commit message or test count.

Use precise states:

- `SLICE_IMPLEMENTED`
- `SLICE_VERIFIED`
- `PHASE_VERIFIED`
- `VERSION_CANDIDATE`
- `VERSION_COMPLETE`
- `EXTERNALLY_BLOCKED`

Do not jump from a local status to `VERSION_COMPLETE`.

## 2. What never proves completion by itself

None of these are sufficient:

- all planned checkboxes green;
- all currently known issues fixed;
- CI/test/property/model/concurrency/fault suites green;
- benchmark/load run passes;
- demo/API works;
- a large assertion count;
- the agent cannot immediately think of another task;
- a previous closure pass succeeded on an earlier revision/version;
- v0.3 or v0.3.1 was historically complete;
- official TZ is not available.

All are evidence only.

## 3. Active-version closure protocol

Before `VERSION_COMPLETE`, set status to `VERSION_CANDIDATE` and perform a fresh closure attempt from current repository state.

For v0.3.2, SPEC-006 is the top pre-TZ specification and compatible requirements from SPEC-005/004/003/002/001 remain inherited.

### Pass A — source/spec reconciliation

Read current production code and reconcile every governing requirement through SPEC-006 plus applicable inherited behavior.

Classify each requirement:

- implemented and evidenced;
- intentionally superseded with durable rationale;
- genuinely external;
- missing.

Any important missing locally solvable requirement reopens development.

SPEC-006 mandatory acceptance behavior must have executable traceability; inherited SPEC-005/AC evidence alone is not enough.

### Pass B — canonical-flow cohesion

Verify every reachable production module belongs to the current canonical product flow:

`Intent -> RoutingContext -> Policy Resolution -> Provider Compatibility/Opportunity -> Admission -> Allocation -> Recovery Legality/Due Schedule -> Optimization -> Atomic Commit -> Provider -> Telemetry/Observation -> Lifecycle/Recovery -> Durable State -> Analytics/Explanation/Configuration/Queries`.

Find and classify:

- dead production modules;
- unintegrated optional hooks;
- duplicate algorithms;
- alternate provider/configuration interfaces;
- demo code masquerading as core;
- hardcoded case-irrelevant business trivia;
- live/restore implementations that encode the same business transition differently;
- transport/API code that owns routing semantics.

Material findings reopen development or are removed/demoted.

### Pass C — financial safety red-team

Actively attempt counterexamples for:

- duplicate economic effects;
- UNKNOWN followed by cross-provider fallback;
- duplicate submit during dispatch;
- stale commit/provider call race;
- fallback to an already money-moving provider;
- late old-provider success after newer settlement;
- provider disablement while unresolved;
- idempotency TTL expiry;
- policy/config changes while work is in flight;
- return/reversal/conflict histories;
- retry/restart reconstructing a materially different provider operation payload;
- recovery schedule changes accidentally releasing ownership or permitting early fallback.

### Pass D — route-context and provider compatibility review

Prove routing-critical dimensions have one canonical interpretation.

Check:

- payment method/rail/destination kind/normalized generic labels where modeled;
- semantically equivalent input canonicalization;
- provider capability matching uses the same route semantics;
- a provider unsupported for a route does not enter functional opportunity/allocation debt;
- provider-operation payload can remain richer without becoming a second routing-context authority;
- no PSP-specific request schema leaks into generic core.

### Pass E — policy resolution and active configuration review

Challenge:

- registration-order permutations;
- multiple same-scope/currency policies;
- explicit/pinned policy identity;
- selector specificity/priority;
- no-policy and ambiguous-policy behavior;
- active config changes after payout policy pinning;
- restart of unresolved payouts under changed active configuration;
- configuration DTO validation versus duplicated domain rules.

A valid resolver must be deterministic and explainable. “Latest registered wins” is not an acceptable hidden business tie-break unless an authoritative source requires it.

### Pass F — allocation/recovery legality and scheduling review

Challenge:

- count and volume distribution;
- large indivisible amounts;
- opportunity-aware denominator;
- policy epochs/windows;
- exact tolerance semantics;
- min/max share semantics;
- temporary outage and debt/catch-up behavior;
- concurrent committed primary work;
- concurrency exposure versus time-based throughput limits;
- impossible/static/runtime infeasibility;
- explicit recovery-provider selection semantics;
- primary/recovery accounting separation;
- configured delay/backoff boundaries;
- repeated early `resume` attempts;
- TTL/deadline versus next scheduled action;
- due-work reconstruction after restart.

Recovery behavior must deliberately answer both **what is legal** and **when the next interaction is due**.

### Pass G — smart optimization integrity

Prove optimization cannot violate higher-priority constraints and that quality evidence remains defensible.

Specifically verify reliability/cost/latency/priority logic cannot:

- resurrect hard-excluded or route-incompatible providers;
- exceed operational admission;
- bypass allocation authority;
- bypass recovery legality or due schedule;
- treat pending/UNKNOWN as arbitrary provider failure;
- let recipient/downstream failure poison provider quality;
- let sparse route cohorts dominate mature broader evidence without an explicit confidence rule;
- use old evidence indefinitely solely because the sample-count window has not rolled;
- use one undocumented weighted score as the complete correctness policy.

Time staleness and sample maturity must be independently testable.

### Pass H — operational health and telemetry review

Prove fast health and slow quality remain distinct.

Challenge canonical interaction evidence:

- definitely-not-sent transport failures;
- ambiguous timeout pressure;
- overload/rate rejection;
- normalized provider service errors;
- measured latency/deadline pressure;
- probe/recovery results.

Fast health may protect future traffic but must not change the economic state of an already ambiguous operation.

Recipient/business/downstream outcomes must not degrade provider health without explicit provider attribution.

All timing-sensitive correctness evidence should use injected/fake clocks rather than sleeps.

### Pass I — analytics dimensional correctness and query review

Treat analytics as typed/dimensioned data.

Prove:

- count is never added to volume;
- different monetary currencies are never added into one amount total;
- target/actual/deviation/settlement retain policy/scope/epoch/window/measure/currency identity;
- convenience rollups are only across compatible units;
- filtered/grouped queries preserve the same dimensional identity;
- invalid aggregation cannot be reintroduced in HTTP/UI;
- mixed-policy/mixed-currency histories replay correctly.

### Pass J — durability/restart safety

If durable behavior is touched, crash/restart at adversarial boundaries and prove the new process safely continues unresolved work.

Required checks include, as relevant:

- ownership restored;
- operation phase/contract/idempotency restored;
- provider operation payload restored;
- policy binding restored;
- recovery due-time semantics restored or deterministically reconstructed;
- dedup/order state restored;
- required allocation/admission reservations restored;
- quality evidence timestamps/staleness semantics restored where durable;
- settlement/reconciliation state restored;
- no second provider operation becomes legal solely because the process restarted.

Existing v0.3.1 durability remains a protected baseline; do not demand unrelated persistence complexity during every SPEC-006 slice.

### Pass K — provider/application/configuration/audit boundary review

Prove:

- raw external input cannot directly assert trusted `safe_to_release` semantics;
- provider-specific normalization owns raw status mapping;
- provider interaction telemetry does not reinterpret economic outcome;
- API/configuration/dashboard do not implement alternate routing logic;
- application configuration DTOs map into domain semantics rather than copy them;
- public audit does not expose recipient-sensitive/provider-message fields by default;
- internal backtraces are not exposed as ordinary API errors.

### Pass L — architecture/source-of-truth review

Challenge decomposition rather than counting classes.

Verify:

- one atomic correctness facade remains;
- canonical proposal construction uses one prepared evaluation source;
- the standalone `DecisionEngine` compatibility path does not own a second independently evolving eligibility/runtime-feasibility algorithm;
- live and restore paths share reducers/invariants where practical;
- new restorers/validators reduce semantic duplication rather than move it;
- `Coordinator` responsibilities are explicit and any extraction reduces real reasons-to-change;
- `max_slots` and `max_count` have distinct verified meanings or redundant semantics have been removed;
- no second state machine exists accidentally in durability validation.

### Pass M — repository discovery

Search for:

- TODO/FIXME/XXX;
- `NotImplementedError` in reachable paths;
- dead public methods;
- broad exception swallowing;
- real `Time.now`/`sleep`/global randomness in correctness-sensitive code/tests without explicit reason;
- Float in money/allocation correctness;
- ignored warnings;
- misleading names/claims;
- stale docs/active plans;
- generated/random tests without reproducible seeds;
- historical files still presented as active authority;
- multiple active ExecPlans for different current versions.

Every finding is classified before closure.

### Pass N — current verification

Run current canonical checks on the exact candidate revision:

- `bundle check`
- `bundle exec rake test`
- `bundle exec rake property`
- `bundle exec rake model`
- `bundle exec rake concurrency`
- `bundle exec rake fault`
- `bundle exec rake benchmark`
- relevant load/history campaigns affected by the version
- CI on current revision
- additional fake-clock/restart/configuration checks required by the active ExecPlan.

Do not reuse old results for changed code.

### Pass O — product load/evidence review

Any performance or scale claim must match an actual reproducible benchmark/test.

Measure the bottleneck that exists rather than optimizing the most flattering benchmark. For any claimed scale, record workload shape, payout/fact count, throughput, query/analytics cost, memory, restore cost and Ruby/runtime configuration.

### Pass P — backlog/blocker audit

Review `docs/PRE_TZ_BACKLOG.md`, active-plan discoveries and every remaining P0/P1 item.

Remaining work is only:

- required and locally actionable -> continue;
- genuinely external -> record exact blocker;
- optional/non-blocking -> later.

Unknown TZ is not a blanket blocker.

### Pass Q — TZ readiness

Before v0.3.2 completion prove `docs/TZ_RECONCILIATION.md` is current and usable.

It must define full-source ingestion before coding, atomic requirement extraction, `CONFIRMED / CHANGED / REMOVED / NEW / AMBIGUOUS` classification, mapping to domain/code/API/tests, judge/runtime/scoring conversion and authority switch after TZ arrival.

### Pass R — documentation consistency

README, AGENTS, ROADMAP, SPEC-006, inherited SPEC-005, PRE_TZ_ARCHITECTURE/CURRENT_ARCHITECTURE, COMPLETION_POLICY, PRE_TZ_BACKLOG, TZ_RECONCILIATION and the active v0.3.2 ExecPlan must describe the same current goal and stop rules.

Historical backlog/decision/review/spec files may retain historical detail but must be clearly non-active.

## 4. No scope shrinking

Do not make closure easier by redefining v0.3.2 around existing code.

A required capability may be removed only by direct user instruction, authoritative TZ evidence, or a durable decision proving equivalent behavior through a simpler case-relevant design.

## 5. Discovery may reopen any phase

Phases are organizational, not sealed. A closure finding may reopen an earlier phase or create a new one.

## 6. External blocker test

`EXTERNALLY_BLOCKED` is valid only if all are true:

1. the missing capability is required;
2. it cannot be resolved from current repository/runtime/research/ordinary engineering judgment;
3. proceeding requires unavailable authoritative semantics/access/service;
4. no independent required work remains;
5. the exact blocker and affected exit criterion are recorded.

## 7. Completion report

A `VERSION_COMPLETE` report includes:

- exact revision;
- SPEC-006 and inherited requirement reconciliation;
- active acceptance-traceability result;
- canonical-flow/module inventory result;
- route-context/provider-capability evidence;
- policy resolution/configuration evidence;
- recovery legality/scheduling/due-work evidence;
- quality/health/telemetry evidence;
- analytics dimensional/query evidence;
- architecture/admission semantic review result;
- commands/CI actually run;
- seeds/traces for generated evidence;
- concurrency/fault/crash/restart evidence relevant to changed semantics;
- bounded scale/benchmark evidence for any scale claims;
- closure findings/regressions;
- remaining genuine external blockers;
- TZ readiness result;
- documentation consistency result.

If this evidence does not exist, report the narrower status and continue.