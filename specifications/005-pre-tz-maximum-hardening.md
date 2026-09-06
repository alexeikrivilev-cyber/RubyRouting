# SPEC-005 — Pre-TZ Maximum Hardening

Status: ACTIVE pre-TZ specification supplement.

This specification starts after the completed v0.3 Product Convergence checkpoint. It does not revoke v0.3 evidence. It defines the next locally solvable work required to make RubyRouting as close as possible to a submission-grade payout-routing product before the authoritative TZ arrives.

SPEC-005 inherits all compatible safety and product requirements from SPEC-004/003/002/001. Where this document is more specific, it is authoritative before the official TZ.

## 1. Objective

RubyRouting SHALL maximize useful pre-TZ readiness, not merely preserve a green checkpoint.

The product SHALL enter TZ reconciliation with:

- a complete generic payout execution contract;
- dimensionally correct allocation and settlement analytics;
- explicit allocation/recovery semantics instead of accidental behavior;
- statistically defensible deterministic smart-routing quality;
- operational health that can react to provider degradation before terminal failure dominates;
- one fact-free routing evaluation and one atomic commit path;
- reduced state/replay complexity where duplication exists;
- measured scalability with no unsupported capacity claims;
- executable requirement traceability for the active specification;
- a prepared TZ reconciliation protocol.

The target is not speculative feature count. The target is minimum semantic distance from plausible official payout-routing requirements while preserving economic safety.

## 2. Scope discipline

Work is in scope when it materially improves one or more of:

- configurable payout distribution;
- payout/provider eligibility;
- operational admission/load protection;
- provider selection quality;
- safe retry, resolution, fallback or reconciliation;
- provider execution realism;
- decision explainability;
- distribution/success analytics;
- deterministic correctness under concurrency/restart;
- measurable performance of the canonical path;
- speed and safety of later TZ reconciliation.

Until a new correctness defect is discovered, additional durability work SHALL NOT outrank unresolved smart-routing/product-semantic P0/P1 work. Existing restart safety is a protected invariant, not the default area for further expansion.

Adaptive ML, bandits or exploration SHALL NOT be introduced merely to make the system appear intelligent. They are allowed only after the deterministic quality baseline is statistically defensible, measurable and safely bounded.

## 3. Provider execution contract

The provider port SHALL be capable of executing a real payout without an undocumented out-of-band lookup.

`PayoutIntent` already contains economic amount, recipient/destination information and routing context. The committed provider operation payload SHALL preserve and expose the provider-relevant immutable payout data required to initiate the payout.

At minimum the design SHALL support:

- payout/economic intent identity;
- operation/attempt identity;
- amount and currency;
- stable idempotency identity;
- payout destination/recipient data required by an adapter;
- explicit payout method/rail/context when relevant;
- immutable operation-time provider contract/capabilities;
- safe restart reconstruction of the same operation payload.

The core SHALL NOT hardcode one PSP's recipient schema. Prefer a typed generic destination/payload boundary plus provider-specific mapping.

A retry or restart SHALL reuse the same economic and provider-operation identity and SHALL NOT silently reconstruct a materially different payout payload.

Acceptance direction:

- a provider adapter can initiate from the canonical request alone;
- the request carries destination/context evidence needed for an executable simulated real-world adapter contract;
- restart/resume reconstructs byte/semantic-equivalent economic fields and the same idempotency identity;
- provider-specific normalization remains outside the core.

## 4. Dimensionally correct analytics

Analytics SHALL never add incompatible measures into one number.

The primary analytical allocation dimension SHALL distinguish at least:

- policy id;
- policy epoch/version;
- policy scope;
- allocation window/cohort identity where applicable;
- measure kind (`count` or `volume`);
- currency for monetary volume;
- provider id.

Consequences:

- count SHALL never be summed with volume;
- RUB minor units SHALL never be summed with USD minor units;
- target, actual, deviation and settlement views SHALL expose their dimension identity;
- cross-policy rollups are allowed only when units are compatible and the aggregation is explicit;
- reversals/returns remain currency-safe;
- public/API analytics SHALL expose safe grouped views rather than ambiguous provider-only totals.

The system SHOULD preserve convenience provider summaries where mathematically valid, but dimensional correctness outranks a flat API shape.

## 5. Allocation semantics

### 5.1 Tolerance

`tolerance` SHALL have one explicit mathematical meaning.

The implementation and documentation SHALL state whether it is:

- absolute discrepancy in allocation measure units;
- normalized share error;
- per-provider corridor;
- another exact metric.

A single tolerance value SHALL NOT silently mean materially different business concepts for count and monetary volume.

If the generic product needs both absolute and proportional tolerance, model them as distinct typed concepts rather than overloading one field.

### 5.2 Provider share obligations

Provider target weights, minimum shares, maximum shares, per-payout amount limits and functional eligibility SHALL remain distinct concepts.

For indivisible payouts, the router SHALL choose the least-bad feasible post-decision state and preserve exact violation evidence.

### 5.3 Recovery selection policy

Primary distribution and recovery selection SHALL have explicit semantics.

The product SHALL decide and encode whether a recovery/fallback provider is selected by:

- the same allocation authority as a primary assignment;
- a distinct recovery objective constrained by safety/business rules;
- a staged hybrid.

This SHALL NOT remain an accidental consequence of reusing `Allocation.choose`.

A preferred generic default is:

1. economic safety and hard constraints;
2. recovery legality and operation/switch budgets;
3. avoid already money-moving providers;
4. explicit business allocation obligations that apply to recovery;
5. provider reliability/quality;
6. cost/latency/priority.

Under `primary_assignment` accounting, recovery attempts SHALL NOT advance the primary allocation ledger unless a later authoritative TZ explicitly changes that rule.

### 5.4 Debt/catch-up

Deviation classification SHALL NOT imply historical catch-up automatically.

If debt repayment is enabled, it SHALL be explicit, bounded and rate-limited. A provider returning from outage/ineligibility SHALL NOT receive an uncontrolled traffic burst to repay historical debt.

## 6. Deterministic smart-routing quality

The slow quality estimator SHALL become statistically defensible without requiring adaptive ML.

The current raw success ratio is insufficient as the final routing quality rule because very small samples can dominate large mature samples.

The quality model SHALL address:

- small-sample uncertainty;
- confidence/maturity;
- provider-attributable success/failure only;
- pending/UNKNOWN neutrality until resolved;
- route/context comparability;
- stale evidence;
- recency or bounded observation window/decay;
- deterministic behavior and exact/reproducible calculations.

Acceptable designs include a conservative Bayesian/Beta estimate, Wilson-style lower confidence score, deterministic shrinkage toward a prior, or another justified estimator.

Required behavioral property:

A provider with `1/1` success SHALL NOT automatically outrank a provider with `99/100` mature success solely because `1.0 > 0.99`.

Context quality SHOULD use hierarchical fallback:

`mature context evidence -> broader mature evidence -> conservative prior/default`.

The optimizer SHALL continue to use quality only inside candidates admitted by higher-priority safety, eligibility, admission and allocation authority.

## 7. Operational health

Fast operational health SHALL remain separate from slow settlement quality.

Health SHOULD be able to consume provider-attributable operational evidence such as:

- definitely-not-sent transport failures;
- ambiguous timeouts where appropriate for fast availability protection without declaring economic failure;
- overload/rate rejection;
- provider 5xx/service errors after provider-specific normalization;
- latency or deadline pressure;
- controlled probe/recovery results.

The health model SHALL preserve hysteresis and slow re-exposure after recovery.

Recipient/business/downstream failures SHALL NOT degrade provider health unless the provider contract explicitly attributes them to provider operation failure.

Latency/timeout health signals SHALL protect future admission without changing the economic outcome of an already ambiguous operation.

## 8. One routing evaluation

The canonical decision path SHOULD compute eligibility, admission, allocation feasibility, runtime feasibility and quality evidence once per decision boundary and pass one immutable evaluation into proposal construction.

`DecisionEvaluator` and `DecisionEngine` SHALL NOT maintain duplicate independently evolving computations of the same eligibility/feasibility concepts.

Goals:

- one source of routing evidence;
- less CPU work;
- lower live/restore drift risk;
- simpler decision-trace validation;
- clearer unit and property oracles.

Atomic revalidation immediately before commit SHALL still preserve concurrency correctness.

## 9. State/replay architecture

The coordinator remains one atomic correctness facade.

Further decomposition SHALL reduce semantic duplication, not merely move methods into more classes.

Prefer:

- shared pure reducers;
- shared typed transition functions;
- shared invariant validators;
- focused ledgers with explicit ownership;
- live and restore paths consuming the same transition semantics where practical.

Avoid a second parallel state machine implemented only through increasingly numerous fact restorers/validators.

No refactor may weaken:

- single-owner economic safety;
- committed allocation visibility;
- capacity/throughput correctness;
- UNKNOWN blocking;
- restart continuation;
- fact/audit traceability.

## 10. Explainability and attribution

For every routing decision the product SHOULD be able to explain, in typed machine-readable form:

- applicable policy/version/scope;
- functional opportunities;
- hard exclusions and reasons;
- operational admission state;
- allocation state before the decision;
- candidate post-decision discrepancies/corridor violations;
- quality/health evidence used by optimization;
- selected provider and exact lexicographic rationale;
- recovery role and previous provider outcome;
- settlement or unresolved result.

Do not claim strict causal attribution when the system only observed a correlated exclusion.

If a metric is named `deviation_cause`, either establish a defensible counterfactual/causal rule or document it as deterministic routing-reason attribution rather than scientific causality.

Public audit views SHOULD redact or omit recipient-sensitive fields while preserving routing evidence.

## 11. Performance and history growth

Performance work SHALL follow semantic correctness.

Current evidence already shows routing math is cheap relative to fact/replay work. Future work SHOULD measure and, when justified, improve:

- facts generated per payout;
- application/coordinator throughput;
- analytics query cost versus history size;
- working restore cost versus history size;
- memory growth;
- concurrent canonical-path throughput.

Before claiming higher scale, run reproducible campaigns at that scale.

Likely optimization directions after measurement:

- incremental analytics projections;
- indexes by payout/policy/provider/dimension;
- projection checkpoints/snapshots;
- reduction of redundant fact payloads;
- bounded audit retrieval.

Do not optimize by removing correctness evidence required for reconciliation or audit.

## 12. Verification and traceability

SPEC-005 SHALL have executable acceptance traceability, not only inherited AC-001..AC-017 mapping.

At minimum add acceptance evidence for:

- provider request contains executable payout destination/context data;
- restart preserves provider operation payload identity;
- count and volume analytics cannot mix;
- currencies cannot mix in volume analytics;
- tolerance semantics are exact and tested;
- recovery selection semantics are explicit and tested;
- small-sample quality cannot dominate mature evidence incorrectly;
- stale/recency quality behavior is deterministic;
- operational health reacts to provider operational signals without misclassifying recipient outcomes;
- one evaluation path preserves routing decisions under concurrency;
- public audit does not expose sensitive recipient payload by default;
- performance claims match actual campaigns.

Use unit/property/model/scenario/concurrency/fault/restart evidence according to the risk of the change.

## 13. TZ readiness contract

The repository SHALL maintain `docs/TZ_RECONCILIATION.md` as the operational protocol for authoritative TZ arrival.

When the TZ arrives:

1. ingest the full authoritative text before coding;
2. split it into atomic requirements;
3. classify each as `CONFIRMED / CHANGED / REMOVED / NEW / AMBIGUOUS` against SPEC-005 and inherited behavior;
4. map each requirement to domain semantics, provider/API contract, code, tests and docs;
5. resolve every ambiguity that blocks correctness;
6. convert judge/scoring/load/interface requirements into executable acceptance gates;
7. implement the smallest compliant delta rather than restarting the product;
8. run a fresh full closure on the official contract.

The official TZ becomes authoritative over every provisional pre-TZ rule.

## 14. Completion criteria for v0.3.1

v0.3.1 SHALL NOT be called complete while a locally solvable material gap remains in the following areas:

- provider execution payload realism;
- dimensional analytics correctness;
- explicit tolerance/recovery-selection semantics;
- statistically robust deterministic quality routing;
- operational health signal completeness appropriate to the generic case;
- duplicate routing-evaluation semantics;
- material live/restore architecture duplication;
- active-spec traceability;
- unsupported scale/performance claims;
- TZ reconciliation readiness.

Existing durability may be considered sufficient unless new evidence finds a correctness defect.

Completion still requires `docs/COMPLETION_POLICY.md` and a fresh skeptical closure pass on the exact candidate revision.