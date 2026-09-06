# SPEC-003 — Full Pre-TZ Logic Scope and Completion Contract

**Status:** PRE-TZ ACTIVE / v0.2 NORMATIVE  
**Authority:** supplements SPEC-001 and SPEC-002 until the official hackathon TZ arrives  
**Purpose:** prevent accidental scope shrink and premature completion while driving the core toward full generic payout-routing logic

## 1. Principle

Before the official TZ, RubyRouting is not limited to a minimal demo or the first green deterministic foundation.

The project must implement the **complete high-value generic routing logic** that can be specified, simulated and verified without inventing external API, persistence, deployment or judge-specific contracts.

A locally solvable domain mechanism is not deferred merely because the official TZ could later refine its exact configuration.

## 2. Mandatory pre-TZ capability envelope

The v0.2 core must cover the following capability families as coherent interacting behavior.

### V3-CORE-001 — economic lifecycle safety

Model one economic intent, single unresolved ownership, explicit provider operation identity/phase, dispatch ambiguity, safe release, terminal business failure, unresolved states and economic-conflict detection.

### V3-CORE-002 — complete routing policy dimensions

The policy model must be able to represent, with explicit provisional semantics where needed:

- strategy/measure: count and volume;
- target weights/shares;
- policy identity/epoch/fingerprint;
- scope/segment;
- accounting point;
- allocation window/epoch semantics;
- tolerance/deviation;
- minimum/maximum constraints where generic;
- hard vs soft/relaxable business constraints;
- recovery budgets;
- deterministic ranking inputs.

Do not build a generic rules-language DSL. Implement explicit typed primitives.

### V3-CORE-003 — allocation controller

Allocation must handle:

- exact count and exact monetary volume;
- post-decision discrepancy;
- committed/in-flight primary assignments;
- indivisible large payouts;
- policy epochs;
- opportunity-aware accounting;
- transient runtime infeasibility without erasing history;
- typed deviation attribution;
- bounded recovery/catch-up pressure if debt is supported.

### V3-CORE-004 — provider eligibility and opportunity

Functional opportunity must be derived from payout/provider context using explicit constraints such as currency, amount bounds, administrative state and supported labels/capabilities.

Opportunity is distinct from current availability, capacity and health.

### V3-CORE-005 — live feasibility and capacity

Live routing must enforce hard operational feasibility including at least:

- availability/administrative disablement;
- concurrent operation capacity;
- generic count/amount capacity budgets when configured;
- atomic reservation/release semantics;
- fallback capacity re-evaluation.

### V3-CORE-006 — provider health and exposure

Implement deterministic operational health with attributable signals, minimum evidence, hysteresis, degradation/quarantine/probing and controlled re-exposure.

Provider health cannot be degraded by clearly recipient-caused failure and cannot be overridden by allocation pressure.

### V3-CORE-007 — deterministic ranking

Within the already safe/eligible/live-feasible set, support a replaceable deterministic ordering using configured priority and available health/quality/cost/latency inputs.

Hard constraints remain lexicographic; ranking cannot resurrect an eliminated provider.

### V3-CORE-008 — recovery controller

Recovery must explicitly distinguish:

- same-provider idempotent retry;
- status resolution;
- cross-provider fallback;
- wait/defer;
- reconciliation-blocked;
- terminal stop;
- post-settlement remediation.

Fresh fallback excludes already money-moving attempted providers by default and re-evaluates live candidates.

Separate budgets are required for money-moving operations/provider switches and resolution interactions; time/deadline/TTL must be representable through controlled time.

### V3-CORE-009 — provider contract semantics

A committed operation pins the provider recovery/idempotency/status-resolution semantics needed for its lifetime. New-route provider state cannot erase old-operation reconciliation capability.

Transport semantics distinguish definitely-not-sent from ambiguous-after-possible-send.

### V3-CORE-010 — event/lifecycle reducer

Provider observations are immutable facts. Duplicates are idempotent; conflicting identity reuse is rejected. Event ordering uses authoritative provider ordering only when contractually meaningful, otherwise explicit legal/conservative transitions.

No semantic status-rank chronology is permitted.

### V3-CORE-011 — settlement, reversal and economic conflict

Settlement is distinct from assignment/attempt. Later return/reversal is a separate economic lifecycle fact. Late evidence that an older operation may also have paid after fallback must raise a visible economic-conflict/reconciliation incident rather than disappear as a stale callback.

### V3-CORE-012 — replayability

Facts must be sufficient to rebuild supported current payout/operation/ownership/settlement/conflict state deterministically. Hidden coordinator-only correctness state is not an acceptable source of truth for a capability claimed replayable.

### V3-CORE-013 — typed explainability and analytics

Decision/analytics semantics must be structured, not inferred from prose strings.

At minimum distinguish:

- opportunity;
- primary allocation;
- recovery decisions/attempts;
- settlement;
- target/deviation and cause;
- first-attempt/eventual success;
- successful fallback recovery;
- unresolved states/age;
- attempt/switch amplification;
- provider-attributable vs recipient/downstream failures;
- capacity/health exclusions;
- reversal/conflict incidents.

### V3-CORE-014 — concurrency correctness

Controlled concurrency evidence must cover all correctness-sensitive shared dimensions, including:

- same-payout owner acquisition;
- duplicate submit during dispatch;
- primary allocation reservation;
- capacity reservation;
- ownership release versus fallback;
- observation/reconciliation versus recovery decision;
- provider live-state changes versus decision commit;
- policy epoch/fingerprint changes where supported.

### V3-CORE-015 — adversarial verification

The core is not complete with isolated feature tests. Property/model/fault scenarios must combine capabilities across long histories and preserve replayable seeds/traces.

## 3. Required versus TZ-blocked

The capability families above are **required v0.2 work**. Their exact external serialization, API, database representation, provider SDK mapping and official thresholds remain TZ-dependent.

The agent may choose simple explicit provisional configuration semantics, but may not omit the capability because an official default/value is unknown.

Examples:

- unknown official allocation window -> implement an explicit replaceable window/epoch strategy, not no window concept;
- unknown provider capacity units -> support generic typed slot/count/amount primitives, not a single opaque boolean forever;
- unknown retry limit -> support separate configurable budgets with conservative defaults, not one overloaded counter;
- unknown health thresholds -> configurable deterministic thresholds, not omission of health mechanics;
- unknown API -> keep application/domain use cases independent from web/API shape.

## 4. No implementation-defined scope reduction

Phrases such as "for the supported scope", "minimal subset", "good enough for pre-TZ", or "judge may not test it" cannot be used to avoid a required capability above.

A required capability can be removed from v0.2 only by:

1. explicit user instruction;
2. authoritative official-TZ evidence making it irrelevant/incompatible; or
3. a durable decision showing that another implemented mechanism fully subsumes it without reducing observable behavior.

## 5. Full-logic interaction requirement

A capability is not considered implemented until its important interactions with earlier capabilities are tested.

Examples:

- allocation + capacity + outage;
- allocation pressure + health quarantine;
- UNKNOWN + duplicate command + idempotency TTL;
- safe failure + fallback + provider becomes unavailable;
- fallback + late old success;
- policy change + concurrent primary decision;
- reversal + replay + analytics;
- capacity reservation + duplicate observation;
- health recovery + bounded exposure + allocation deviation.

## 6. Completion authority

Version completion is governed by `docs/COMPLETION_POLICY.md` and the v0.2 exit gate in `docs/ROADMAP.md`.

A green planned checklist is not sufficient. The agent must enter `VERSION_CANDIDATE`, perform a fresh source/spec/capability/repository/red-team/backlog/documentation sweep, and return to implementation if any important locally solvable gap is found.

## 7. v0.2 acceptance condition

v0.2 can reach `VERSION_COMPLETE` only when all are true:

- SPEC-001/002/003 requirements applicable before the official TZ are reconciled to executable behavior;
- every V3-CORE capability family above is implemented rather than merely represented in a plan;
- P0/P1 current backlog has no locally actionable correctness/full-logic item remaining;
- long-history replay and live state agree for supported generated histories;
- controlled concurrency and deterministic provider faults cover the important interaction matrix;
- canonical current verification is green;
- a red-team closure pass finds no unresolved material generic gap;
- documentation consistently describes the current code/version;
- remaining work is genuinely official-TZ-specific external integration or optional post-core optimization.

If closure review finds a new material generic mechanism or defect, v0.2 is not complete regardless of previous checkboxes.
