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
- a previous closure pass succeeded on an earlier revision;
- official TZ is not available.

All are evidence only.

## 3. Active-version closure protocol

Before `VERSION_COMPLETE`, set status to `VERSION_CANDIDATE` and perform a fresh closure attempt from current repository state.

### Pass A — source/spec reconciliation

Read current production code and reconcile every governing requirement through SPEC-004 plus applicable inherited SPEC-003/002/001 behavior.

Classify each requirement:

- implemented and evidenced;
- intentionally superseded with durable rationale;
- genuinely external;
- missing.

Any important missing locally solvable requirement reopens development.

### Pass B — canonical-flow cohesion

Verify every reachable production module belongs to the canonical product flow:

`Intent -> Policy -> Opportunity -> Admission -> Allocation -> Optimization -> Atomic Commit -> Provider -> Observation -> Lifecycle/Recovery -> Durable State -> Analytics/API`.

Find and classify:

- dead production modules;
- unintegrated optional hooks;
- duplicate algorithms;
- alternate provider interfaces;
- demo code masquerading as core;
- hardcoded case-irrelevant business trivia.

Material findings reopen development or are removed/demoted.

### Pass C — financial safety red-team

Actively attempt counterexamples for:

- duplicate economic effects;
- UNKNOWN followed by cross-provider fallback;
- duplicate submit during dispatch;
- stale commit/provider call race;
- fallback to an already attempted provider;
- late old-provider success after newer settlement;
- provider disablement while unresolved;
- idempotency TTL expiry;
- policy changes while work is in flight;
- return/reversal/conflict histories.

### Pass D — policy/allocation/admission review

Challenge:

- count and volume distribution;
- large indivisible amounts;
- opportunity-aware denominator;
- policy epochs/windows;
- target tolerance/min/max share semantics;
- temporary outage and debt/catch-up behavior;
- concurrent committed primary work;
- concurrency exposure versus time-based throughput limits;
- health/quarantine/probing;
- impossible/static/runtime infeasibility.

### Pass E — optimization integrity

Prove optimization cannot violate higher-priority constraints.

Specifically verify that reliability/cost/latency/priority logic cannot:

- resurrect hard-excluded providers;
- exceed operational admission;
- bypass allocation obligations/tolerance;
- treat pending/UNKNOWN as arbitrary provider failure;
- use one undocumented weighted score as the complete correctness policy.

### Pass F — durability/restart safety

If durable mode exists, crash/restart the system at adversarial boundaries and prove the new process safely continues unresolved work.

Required checks include:

- ownership restored;
- operation phase/contract/idempotency restored;
- policy binding restored;
- dedup/order state restored;
- required allocation/admission reservations restored;
- settlement/reconciliation state restored;
- no second provider operation becomes legal solely because the process restarted.

Also test truncated/corrupted durable history. Silent fact loss is a closure defect.

A replay projection that looks correct while the working coordinator forgets ownership fails this pass.

### Pass G — provider/application boundary review

If API/webhooks/provider integrations exist, prove:

- raw external input cannot directly assert trusted `safe_to_release` semantics;
- provider-specific normalization owns raw status mapping;
- internal backtraces are not exposed as normal API errors;
- API/dashboard do not implement alternate routing logic;
- demo providers are clearly labeled and satisfy the canonical provider port.

### Pass H — repository discovery

Search for:

- TODO/FIXME/XXX;
- `NotImplementedError` in reachable paths;
- dead public methods;
- broad exception swallowing;
- real `Time.now`/`sleep`/global randomness in correctness-sensitive tests/code without explicit reason;
- Float in money/allocation correctness;
- ignored warnings;
- misleading names/claims;
- stale docs/active plans;
- generated/random tests without reproducible seeds.

Every finding is classified before closure.

### Pass I — current verification

Run current canonical checks on the exact candidate revision:

- `bundle check`
- `bundle exec rake test`
- `bundle exec rake property`
- `bundle exec rake model`
- `bundle exec rake concurrency`
- `bundle exec rake fault`
- `bundle exec rake benchmark`
- CI on current revision
- additional crash/load checks required by the active plan.

Do not reuse old results for changed code.

### Pass J — product load/evidence review

Any performance or scale claim must match an actual reproducible benchmark/test.

If docs say 100k payouts, evidence must actually execute the stated scale in an appropriate non-default load campaign. Do not turn marketing numbers into fake tests.

### Pass K — backlog/blocker audit

Review all NOW/P0/P1 items and active-plan discoveries.

Remaining work is only:

- required and locally actionable -> continue;
- genuinely external -> record blocker;
- optional and non-blocking -> later.

Unknown TZ is not a blanket blocker.

### Pass L — documentation consistency

README, AGENTS, ROADMAP, SPEC-004/003/002/001, CURRENT_ARCHITECTURE, TESTING, WORKFLOW, PLANS, SESSION_POLICY, BACKLOG, DECISIONS_CURRENT and active ExecPlan must describe the same current goal and stop rules.

## 4. No scope shrinking

Do not make closure easier by redefining the version around existing code.

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
- requirement reconciliation;
- canonical-flow/module inventory result;
- commands/CI actually run;
- seeds/traces for generated evidence;
- concurrency/fault/crash/restart evidence;
- scale/benchmark evidence for any scale claims;
- closure findings/regressions;
- remaining genuine external blockers;
- documentation consistency result.

If this evidence does not exist, report the narrower status and continue.