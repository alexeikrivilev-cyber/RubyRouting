# SPEC-004 — Product Convergence & Full Routing Product

Status: current normative pre-TZ specification supplement.

This specification supersedes any earlier repository claim that the product is finished or that pre-TZ development should stop. It inherits compatible behavior from SPEC-003/002/001 and defines the required product-convergence direction.

## 1. Product objective

RubyRouting SHALL become a coherent, nearly submission-ready smart payout-routing product before the official TZ is published.

The official TZ SHALL later be treated as an explicit reconciliation/integration input. Lack of TZ SHALL NOT be used to omit locally implementable case-relevant mechanics.

The product SHALL remain centered on the case: configurable payout distribution across providers, provider constraints/load/reliability, safe failover, attempt history and analytics.

## 2. Canonical product pipeline

All production behavior SHALL integrate through one logical pipeline:

`Payout Intent`
→ `Policy Resolution`
→ `Functional Opportunity`
→ `Operational Admission`
→ `Allocation Authority`
→ `Constrained Optimization`
→ `Atomic Decision / Ownership / Reservations`
→ `Provider Operation`
→ `Normalized Observation`
→ `Lifecycle / Recovery / Reconciliation`
→ `Durable State / Facts`
→ `Analytics / Audit / Application Surface`.

A production module that cannot be placed in this pipeline with a clear responsibility SHALL be removed, demoted to demo/experimental support, or redesigned.

## 3. Economic safety

The inherited economic-safety rules remain mandatory:

- one payout command represents one economic intent;
- at most one unresolved money-moving economic owner exists per intent;
- ambiguous-after-possible-send transport outcome is UNKNOWN unless proven otherwise;
- UNKNOWN retains ownership;
- cross-provider fallback requires safe release/proof of no remaining monetary effect;
- same-provider retry/status resolution is distinct from fresh fallback;
- provider-local idempotency does not provide cross-provider deduplication;
- late evidence of a second monetary effect is an economic conflict, not a stale callback to discard.

## 4. Policy model

The product SHALL support configurable allocation policy as explicit typed concepts.

At minimum:

- policy id/version/epoch/fingerprint;
- scope/segment;
- count and volume strategies;
- provider target weights/shares;
- accounting point;
- allocation window/epoch semantics;
- tolerance/admissible corridor;
- provider target minimum/maximum share obligations where configured;
- hard/soft constraints;
- recovery budgets/policy;
- optimization policy.

Per-payout provider eligibility amount limits SHALL NOT be represented as provider target-share minimum/maximum obligations. These are separate concepts.

Static policy infeasibility and runtime infeasibility SHALL be distinguishable and auditable.

## 5. Functional opportunity

Functional opportunity answers whether a provider could serve the payout in principle under provider/payout/policy context.

Generic factors may include:

- currency;
- amount range;
- method/rail/context labels;
- provider capabilities;
- administrative configuration;
- hard business constraints.

Temporary availability, capacity/rate and provider health SHALL NOT redefine historical functional opportunity.

The product SHALL NOT embed hardcoded provider-brand/BIN/bank trivia in generic core unless required by official TZ or isolated in an explicit provider/demo plugin.

## 6. Operational admission

Operational admission answers whether a new provider operation may start now.

Admission SHALL evaluate current hard runtime conditions, including configured subsets of:

- provider enabled state;
- availability;
- concurrent operation slots/exposure;
- amount exposure;
- throughput/rate budget;
- health/quarantine/probing;
- emergency hard gates.

Concurrent exposure/capacity and time-based throughput rate SHALL be separate state models:

- exposure is reserved/released with operation lifecycle;
- throughput budget is consumed over time and is not restored merely because an operation completes.

Admission is a hard gate. Lower-priority allocation pressure or optimization SHALL NOT resurrect an inadmissible provider.

## 7. Allocation authority

Allocation SHALL be the authoritative business-distribution controller.

For the active policy/accounting semantics it SHALL:

- use exact Integer/Rational arithmetic;
- account for relevant committed/in-flight primary work;
- support count and volume measures;
- handle indivisible large payouts by choosing the least-bad achievable admissible state;
- use the functional opportunity universe/explicit policy scope for accounting;
- preserve policy epochs/windows;
- distinguish primary assignment from recovery attempts and settlement;
- record target deviation and cause;
- distinguish unavoidable/non-recoverable deviation from recoverable debt when debt is enabled;
- bound debt/catch-up so provider recovery cannot cause an uncontrolled traffic burst.

Under the inherited provisional `primary_assignment` accounting point, recovery/fallback SHALL NOT advance the primary allocation ledger.

## 8. Constrained optimization

Optimization SHALL operate only after economic safety, hard eligibility, operational admission and allocation obligations determine the admissible action set.

The product SHALL NOT use one arbitrary undocumented weighted scalar as the correctness policy if that scalar can trade away higher-priority constraints.

Default priority SHALL be equivalent to:

1. economic safety;
2. hard functional/business eligibility;
3. operational admission;
4. allocation admissibility/contract;
5. reliability/quality;
6. cost;
7. latency/configured preference;
8. optional bounded exploration.

A deterministic lexicographic or staged optimizer is acceptable.

## 9. Health and quality feedback

Fast operational health and slow routing quality SHALL be distinct concepts.

Fast health MAY react to provider-attributable transport failures, timeouts, 5xx, rejection/overload and latency signals. It SHALL use hysteresis and controlled recovery/probing.

Recipient/business/downstream-attributable failures SHALL NOT automatically degrade provider health.

Slow quality/reliability estimates SHOULD account for:

- route/context cohort;
- outcome attribution;
- feedback maturity/delay;
- sample confidence;
- stale evidence.

Pending/UNKNOWN SHALL NOT be blindly counted as provider failure in slow quality.

## 10. Provider operation contract

Each money-moving operation SHALL retain the provider semantics required to resolve it safely even if the provider later becomes disabled for new traffic.

The contract SHALL support applicable concepts:

- stable operation/idempotency identity;
- status lookup;
- same-operation idempotent retry;
- idempotency/status TTL;
- deadline;
- provider ordering/sequence semantics;
- cancellation semantics when supported.

## 11. Provider normalization boundary

Raw provider HTTP/API/webhook status data SHALL be normalized at a provider-specific boundary before it enters the core lifecycle reducer.

A generic external caller SHALL NOT be trusted to directly assert:

- `safe_to_release`;
- provider/business attribution;
- terminal economic state;
- provider sequencing guarantees.

These are derived from an adapter/provider contract.

## 12. Recovery and reconciliation

After an operation the product SHALL choose only legal actions:

- stop on success/terminal payout failure;
- wait on pending/UNKNOWN where required;
- resolve/status-check same provider when safe;
- same-operation retry when idempotently safe;
- safely release and fresh-route after confirmed safe failure;
- defer when no safe action exists;
- enter reconciliation-blocked when automatic resolution becomes unsafe/expired;
- process returns/reversals as post-settlement lifecycle;
- surface/remediate economic conflicts.

Recovery SHALL respect separate configurable operation, provider-switch and resolution-interaction budgets plus deadline/TTL constraints.

## 13. State architecture

One atomic correctness boundary SHALL remain responsible for state changes that must commit together before provider I/O.

The coordinator MAY and SHOULD delegate to focused internal ledgers/reducers as the product grows.

The final architecture SHOULD avoid a single class owning all of allocation, admission, health, lifecycle, fact storage and policy algorithms while preserving one atomic transaction facade.

Provider I/O SHALL remain outside the atomic lock/transaction.

## 14. Durable continuation

If the product claims durability/restart recovery, a fresh process SHALL be able to safely continue unresolved payouts.

Durable/recoverable state SHALL include enough information to reconstruct, as applicable:

- payout intent;
- policy binding/fingerprint;
- operation/attempt identity and phase;
- economic ownership;
- provider operation/idempotency contract;
- observation dedup/order state;
- allocation state/reservations needed for correctness;
- operational admission/capacity reservations needed for correctness;
- health state used by routing;
- settlement/reversal/conflict/reconciliation state.

A system that only rebuilds read-only projections while the new working coordinator forgets unresolved ownership SHALL NOT be described as recovered.

Malformed/truncated durable history SHALL NOT be silently skipped as if the financial history were complete.

## 15. Analytics and audit

The product SHALL preserve enough evidence to report separately:

- functional opportunity;
- primary assignment;
- provider attempts/interactions;
- settlement;
- target vs actual count/volume;
- deviation and cause;
- first-attempt success;
- eventual success;
- fallback recovery;
- attempt amplification;
- provider-attributable failures;
- pending/UNKNOWN/reconciliation age;
- availability/capacity/rate/health exclusions;
- conflicts/reversals;
- exact typed decision rationale.

Analytics SHALL NOT infer causality by collapsing unrelated business failures into provider failure rates.

## 16. Application/API/demo

The product SHOULD expose stable application commands/queries before final external API design.

An HTTP/API/dashboard MAY be built over the application layer, but SHALL NOT own alternate routing semantics.

Provider callbacks SHALL pass through provider-specific normalization.

Normal API error responses SHALL NOT leak Ruby backtraces/internal implementation details.

Demo/simulator providers SHALL be clearly labeled as such.

## 17. Testing and evidence

The product SHALL use deep multi-layer verification:

- deterministic unit/acceptance/regressions;
- independent allocation/recovery/reference models;
- property/invariant tests;
- state-machine histories;
- controlled concurrency/interleavings;
- seeded deterministic provider/fault simulation;
- duplicate/delayed/out-of-order event tests;
- replay equivalence;
- crash/restart tests for durable mode;
- durable corruption tests;
- end-to-end multi-provider scenarios;
- performance/load campaigns after correctness.

Correctness-sensitive randomized tests SHALL expose a reproducible seed/trace.

Any documented scale claim SHALL correspond to an actual test/benchmark at that scale.

## 18. Repository coherence

Before v0.3 completion:

- no disconnected misleading production feature branch remains;
- no fake real-world adapter is described as production integration;
- no known unsafe durability path is described as crash recovery;
- no optimizer name claims semantics it does not implement;
- no stale roadmap says to wait for TZ;
- active documentation agrees on v0.3 and current execution plan.

## 19. Completion

SPEC-004 completion is governed by `docs/COMPLETION_POLICY.md`.

Green tests/checklists do not self-authorize completion. A fresh product-wide closure/red-team pass is mandatory and may reopen any phase.