# SPEC-002 — Pre-TZ Comprehensive Routing Core Amendments

**Status:** PRE-TZ ACTIVE / v0.2  
**Authority:** supplements and overrides explicitly listed provisional choices in SPEC-001 until the official hackathon TZ is available  
**Language:** all executable product/reference/simulator/test domain logic remains Ruby-only

## 1. Purpose

SPEC-001 remains the baseline product specification. This amendment fixes implementation lessons discovered after the first v0.1 executable foundation and defines the additional high-value mechanics that can be built safely before the official TZ.

Where SPEC-002 explicitly changes a provisional SPEC-001 rule, SPEC-002 wins. All official-TZ requirements will later supersede both through explicit reconciliation.

## 2. Accounting semantics correction

### V2-ALLOC-001 — primary accounting is isolated from recovery

Under the current provisional accounting point (`primary_assignment`), only the first primary assignment for a payout contributes to the business allocation controller.

A fallback/recovery assignment:

- is preserved as a routing decision and attempt;
- may contribute to attempt/settlement analytics;
- does **not** mutate the primary allocation projection.

If the official TZ later defines attempted/accepted/settled volume as the normative accounting point, the accounting strategy must be replaced explicitly rather than implicitly mixing recovery into primary allocation.

### V2-ALLOC-002 — opportunity and live feasibility are distinct

**Opportunity** means a provider is functionally eligible for this payout under stable provider/policy/context constraints.

**Live feasibility** means an opportunity is currently admissible after availability, capacity, health/quarantine and other hard operational checks.

A temporary availability/capacity change must not silently reset the allocation history/window merely because the feasible-provider set changed.

This supersedes the v0.1 feasible-provider-cohort reset in D-018 / SPEC-001 section 5.

### V2-ALLOC-003 — explicit deviation attribution

If a target cannot be met because an opportunity is unavailable, capacity-constrained, safety-blocked or otherwise temporarily infeasible, preserve the deviation and its cause. Do not hide it by silently changing the denominator/window.

Any allocation debt/catch-up policy must be bounded. No outage may create an unlimited recovery traffic burst.

### V2-ALLOC-004 — recovery candidates exclude previously failed providers by default

After a confirmed safe failure, a fresh cross-provider routing decision excludes providers already used by a money-moving operation for the same payout, unless an explicit recovery policy/provider contract permits a new same-provider operation.

Same-provider idempotent retry is a separate `retry_same` action and reuses the provider operation/idempotency domain when its contract permits it.

## 3. Policy identity and configuration

### V2-POL-001 — immutable policy definition

A policy identity/epoch/scope must uniquely identify one immutable policy definition. Reusing the same identity with different targets, accounting semantics or material constraints is an integrity error.

Persist or derive a deterministic policy fingerprint suitable for decision trace/replay.

### V2-POL-002 — payout decisions pin policy identity

A payout history records which policy definition governed each decision. A caller cannot silently swap a different policy definition into an unresolved payout while keeping the same policy identity.

Emergency operational disablement/health remains live and can supersede the pinned business policy for safety.

### V2-POL-003 — policy concerns are separated

Keep at least these conceptual concerns separate:

- allocation policy: scope/measure/target/min/max/tolerance/accounting/window;
- eligibility constraints: provider/payout compatibility;
- recovery policy: retry/fallback/resolve/defer budgets and deadlines;
- optional ranking policy: reliability/cost/latency inside the safe feasible set.

Do not collapse them into one weighted scalar score or one giant rules DSL.

### V2-POL-004 — feasibility is explicit

Detect static contradictory policy definitions where possible and represent runtime infeasibility separately. Hard safety and eligibility are never relaxed to make a business target feasible.

## 4. Provider profile, capability and capacity

### V2-PRV-001 — context-aware provider eligibility

Provider eligibility must be evaluable against payout context rather than stored only as a global boolean. The pre-TZ baseline should support a small explicit profile/constraint model for likely constraints such as:

- supported currency;
- amount minimum/maximum;
- enabled/disabled state;
- required capability/context labels when present.

Do not build a generic DSL until official requirements justify one.

### V2-PRV-002 — operation recovery contract is snapshotted

When a provider operation is committed, preserve the operation-scoped recovery semantics needed later:

- provider identity;
- idempotent retry support and relevant identity;
- status lookup support;
- any known TTL/deadline semantics;
- adapter/contract version when useful.

Current route availability or provider disablement cannot erase the ability to resolve an existing unresolved operation.

### V2-CAP-001 — capacity is reservable state

Support deterministic capacity constraints beyond one boolean where useful before TZ: concurrent slots and count/amount budgets are sufficient generic primitives.

Capacity required by a new money-moving operation is checked/reserved atomically with routing ownership where the capacity model requires it, and released/settled according to explicit lifecycle rules.

Fallback is subject to the same current capacity constraints as a primary route.

## 5. Operation dispatch and transport ambiguity

### V2-OP-001 — explicit operation phase

A provider operation must distinguish at least the states necessary to reason about dispatch safety:

- committed / not yet dispatched;
- dispatch in progress or dispatched;
- provider observation received;
- unresolved pending/unknown;
- terminal/released.

Exact enum names are implementation details.

### V2-OP-002 — ownership alone does not authorize resolution/retry

A concurrent duplicate command that sees a newly committed owner while the original dispatch is still in progress must not immediately start status lookup or same-provider retry merely because ownership exists.

Resolution/retry actions require an operation phase/outcome that makes them meaningful and safe.

### V2-OP-003 — transport result classes

The provider boundary must distinguish at least:

- **definitely not sent / no provider side effect possible** — may normalize to a safe local/route failure and release ownership;
- **ambiguous after possible send** — normalize to `UNKNOWN`; keep ownership;
- **provider observation** — apply normalized provider semantics.

Generic exceptions must not be allowed to silently bypass this economic classification.

### V2-OP-004 — adapter availability is pre-commit admissibility

The application cannot commit a money-moving assignment to a provider for which no executable adapter/transport is available in the current application configuration.

## 6. Observation ordering, lifecycle reduction and conflicts

### V2-EVT-001 — no arbitrary status-rank chronology

Do not determine event chronology by ranking statuses such as `pending < unknown < failure < success`.

Use:

- immutable observation identity;
- provider sequence/version when the contract guarantees its meaning;
- explicit lifecycle transition rules;
- conservative handling when ordering is unknown.

All observations remain historical facts even when they cannot change current derived state.

### V2-EVT-002 — duplicate and conflicting observations

Exact duplicate delivery is idempotent. Reuse of the same immutable observation identity with different payload/linkage is an integrity error, preserving D-019.

### V2-EVT-003 — late old-operation success is an economic conflict

If a previously released provider operation later reports evidence that it may have produced a monetary effect after another provider operation has been started or settled, do not silently ignore it.

Preserve current facts and emit an explicit economic-conflict/reconciliation incident. Such an incident is a P0 correctness signal even if the main payout projection cannot safely choose a single economic truth automatically.

### V2-EVT-004 — post-settlement return/reversal is separate recovery

The simulator/domain may represent a later returned/reversed settlement. It must not be treated as ordinary continuation of the original provider cascade. Preserve the initial settlement and the later economic reversal/remediation state separately.

## 7. Replay and source facts

### V2-REP-001 — lifecycle replay is real

The append-preserved fact set must contain enough information to rebuild the supported v0.2 payout lifecycle projection deterministically, including:

- economic intent material needed by the domain;
- policy identity/fingerprint;
- decisions and roles;
- operation/attempt identities and provider contract snapshot;
- observations;
- ownership acquisition/release;
- settlement/reversal/conflict facts.

`Replay` must rebuild more than analytics; current lifecycle/ownership/operation projections must be derivable without consulting hidden coordinator state.

### V2-REP-002 — facts are typed, analytics do not parse prose

Machine decisions/exclusions/deviation/failure reasons used by projections are structured codes/data. Human-readable explanations may accompany them but analytics must not depend on substring parsing.

## 8. Recovery policy and time

### V2-REC-001 — separate recovery budgets

Do not overload one `max_attempts` integer for every kind of provider interaction. The baseline model should permit separate limits for:

- money-moving operations;
- provider switches/fallback depth;
- same-provider resolution/retry interactions;
- optional elapsed/deadline budget.

Defaults may be simple and conservative before the TZ.

### V2-REC-002 — explicit resume/reconcile path

Initial submission and continuation of an unresolved payout are conceptually distinct commands/use cases. An implementation may share internals, but the public application layer must be able to express “advance/resume/reconcile this known payout” without pretending it is a fresh economic intent.

### V2-REC-003 — provider contract expiry

If idempotency/status-resolution safety has a TTL, an expired unresolved operation cannot be retried blindly. It becomes a reconciliation/manual/blocked state until safe evidence exists.

## 9. Deterministic operational health

### V2-HLT-001 — fast operational health is implemented before ML

Build a deterministic provider-health controller capable of consuming attributable operational signals such as transport failures/timeouts/provider internal failures/latency or explicitly supplied health signals.

It may expose states such as:

`HEALTHY -> DEGRADED -> QUARANTINED -> PROBING -> HEALTHY`

Exact names/threshold configuration are implementation details.

### V2-HLT-002 — hysteresis and minimum evidence

Do not flap provider exposure on one ordinary business failure. Health transition rules use minimum evidence and different degrade/recovery conditions where appropriate.

Recipient/payout-attributable failure does not degrade provider health.

### V2-HLT-003 — fast down, controlled recovery

Strong operational evidence may reduce new traffic quickly. Recovery/probing increases allowed exposure gradually and cannot be overridden by historical allocation debt.

### V2-HLT-004 — quality estimate remains separate

Longer-horizon success/quality estimate is separate from operational availability. If implemented before TZ, keep it deterministic/confidence-aware and segment primary vs fallback cohorts where practical. ML/bandits remain optional.

## 10. Ranking inside the feasible envelope

### V2-RNK-001 — safety/constraints remain lexicographic

Ranking never reintroduces a provider eliminated by safety, eligibility, capacity, policy-hard constraint or quarantine.

### V2-RNK-002 — deterministic baseline ranking

Implement a replaceable deterministic ranking layer for feasible candidates. It may use configured priority, operational health/quality, cost/latency metadata where present, and deterministic tie-breaking.

Allocation requirements define admissible/pressured choices; ranking optimizes inside the permitted envelope. Do not require ML.

## 11. Decision trace and analytics

### V2-TRC-001 — typed decision trace

A committed routing decision records enough structured context to explain:

- policy identity/fingerprint;
- primary vs recovery role;
- opportunity candidates;
- live feasibility/exclusions with typed reasons;
- current allocation state/revision;
- relevant capacity/health/ranking state;
- selected action/provider and reason codes;
- triggering previous outcome for recovery.

### V2-AN-001 — primary, recovery and settlement metrics are distinct

At minimum expose typed projections for:

- target vs actual primary allocation by measure;
- recovery/fallback attempts separately;
- effective settlement distribution;
- first-attempt and eventual success;
- successful fallback recovery (not merely “a fallback was attempted”);
- attempts/provider switches per payout;
- pending/unknown/unresolved counts and age where time exists;
- provider-attributable vs recipient/downstream failures;
- economic-conflict incidents.

### V2-AN-002 — deviation is causal

Represent avoidable/unavoidable or typed deviation causes such as functional ineligibility, outage/quarantine, capacity, safety block, hard policy conflict and optimizer choice. Do not infer this by parsing human-readable strings.

## 12. Verification expansion

v0.2 must add deterministic regression/property/model/concurrency evidence for the new requirements. Minimum adversarial cases:

1. fallback does not mutate primary allocation state;
2. failed provider is not selected as a fresh fallback;
3. operation resolution survives route disable/removal;
4. duplicate submit while dispatch is in-flight does not resolve/retry prematurely;
5. missing adapter prevents assignment commit;
6. definitely-not-sent vs ambiguous transport failure;
7. policy definition collision and mid-payout policy mismatch;
8. availability changes do not erase allocation accounting;
9. capacity reservation races;
10. owner release/fallback racing with callback/reconciliation;
11. ordered and unordered provider observations;
12. late old-provider success emits economic conflict;
13. lifecycle replay equals live projection;
14. return/reversal after settlement;
15. provider-health hysteresis/probing and attribution correctness;
16. recovery budget/time boundaries;
17. analytics conservation across primary/recovery/settlement.

Generated state-machine tests should increasingly operate end-to-end through operation phases, policy, capacity, observations, recovery and replay rather than testing only isolated ownership transitions.

## 13. Acceptance gate for v0.2

The pre-TZ comprehensive core is complete only when:

- P0 findings in `docs/TECH_REVIEW_2026-08-27.md` are closed with regression evidence;
- SPEC-002 requirements implemented for the supported generic pre-TZ scope have executable evidence;
- primary allocation and recovery accounting are not conflated;
- operation dispatch/transport ambiguity and operation-scoped recovery contracts are explicit;
- opportunity/live feasibility/capacity/health are separate inputs;
- lifecycle facts can replay current supported state;
- economic conflicts are surfaced, never silently ignored;
- policy identity/feasibility and recovery budgets are explicit and replaceable;
- deterministic health/ranking baseline works without ML;
- analytics are typed and causal enough to explain routing/fallback outcomes;
- full scenario/property/model/concurrency/fault suites are green in an executable environment;
- remaining unknowns genuinely require the official TZ or are optional judged optimizations.
