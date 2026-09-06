# Current Architecture — Authoritative TZ / v0.4.2

v0.4.1 established the canonical smart submission policy, distinct assignment/attempt/settlement ledgers and post-serialization validation. v0.4.2 tightens competition contract fidelity and scoring semantics without creating another router.

## Competition flow

`DatasetLoader`
→ `SubmissionProfile / CaseConfiguration`
→ `ProviderCaseState`
→ `HardConstraintEvaluator`
→ `Routing phase context (primary/fallback)`
→ `TrafficLedger + AttemptLedger + SettlementLedger`
→ `RoutingFactors`
→ `ConflictResolver`
→ `CaseRouter`
→ `DeterministicSimulator / fallback`
→ `internal attempt facts`
→ `organizer-compatible DecisionProjection + TZ base ReportProjection + rich report extensions`
→ `independent organizer-contract validators + strict internal validators`
→ required root files.

There is one provider-selection authority: hard filter + one ConflictResolver inside CaseRouter. CLI/finalization/demo/report cannot independently choose providers.

## SubmissionProfile boundary

The exact finalization path loads one typed profile; library defaults are not release policy. Profile carries target/weight/simulation/terminal provenance. Data-derived values are computed from loaded data, not copied provider names.

## Accounting and phase boundary

Keep distinct:

- **primary assignment** — distribution strategy authority;
- **attempts** — every invoked provider in cascade order;
- **settlement** — approved final provider, if any.

Count/volume factors evaluate the primary assignment. Once primary assignment is recorded, fallback must not counterfactually add that operation again. Fallback uses the same resolver under explicit fallback phase and applicable non-allocation business factors.

## Hard vs soft

All official hard constraints remain absolute and stateful. For the bounded Case domain, only literal `status == "active"` is active. Soft factors compare only eligible providers. Amount hard bounds and preferred amount bands are independent.

## Output boundary

External compatibility is layered:

1. minimal decisions DTO compatible with organizer/public validator;
2. TZ-compatible report base schema preserving required field names/types;
3. additive rich exact assignment/attempt/settlement, factor, explanation and recommendation details.

Serialize, reparse and validate actual artifacts. Internal rich self-consistency validation and organizer/TZ contract validation are separate authorities.

## Scoring evidence boundary

A factor that is configured but equal for all candidates is non-discriminating and must not appear causally decisive. Stable deterministic tie-break is separate. Canonical profile factor settings must be demonstrably meaningful in finalization-equivalent evidence.

## Production boundary

Production economic ownership, UNKNOWN, provider operation identity and durable recovery remain protected. Synthetic case expiry/fallback stays bounded inside competition simulation.

## Performance boundary

Case routing/validation remains in-memory. Hidden-like robustness may use maps/indexes to avoid accidental quadratic scans, but no database/distributed infrastructure is warranted.