# Current Architecture — Authoritative TZ / v0.4.1

v0.4.0 established the bounded `RubyRouting::Case` engine. v0.4.1 changes release-path authority and accounting/projection semantics without creating another router.

## Competition flow

`DatasetLoader`
→ `SubmissionProfile / CaseConfiguration`
→ `ProviderCaseState`
→ `HardConstraintEvaluator`
→ `AssignmentTrafficLedger + settlement projections`
→ `RoutingFactors`
→ `ConflictResolver`
→ `CaseRouter`
→ `DeterministicSimulator / fallback`
→ `internal attempt facts`
→ `minimal DecisionProjection + rich ReportBuilder`
→ `post-serialization validators`
→ required root files.

There is one provider-selection authority: hard filter + ConflictResolver inside CaseRouter. CLI/finalization/demo/report cannot independently choose providers.

## SubmissionProfile boundary

The exact finalization path must load a typed default profile; library defaults are not release policy. Profile carries target/weight/simulation provenance. Data-derived values are computed from loaded data, not copied provider names.

## Accounting boundary

Keep distinct:

- primary assignment: distribution strategy authority;
- provider attempts: operational cascade evidence;
- approved settlement: success/financial outcome projection.

Do not use settlement-only totals as the routing target ledger unless organizer authority explicitly says so.

## Hard vs soft

All existing official hard constraints remain absolute and stateful. Soft factors can compare only eligible providers. Amount hard bounds and preferred amount bands are independent.

## Output boundary

Internal attempt facts are richer than organizer DTO. External decisions are a conservative projection; report carries rich factor/config/accounting evidence. Serialize, then reparse and validate actual artifacts.

## Production boundary

Production economic ownership, UNKNOWN, provider operation identity and durable recovery remain protected. Synthetic case expiry/fallback stays bounded inside competition simulation.

## Performance boundary

Case routing/validation remains in-memory. Hidden-like robustness may use maps/indexes to avoid accidental quadratic scans, but no database/distributed infrastructure is warranted.
