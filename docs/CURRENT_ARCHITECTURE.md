# Current Architecture — post-TZ v0.4.3

Status: **ACTIVE audit overlay**. Completed v0.4.2 architecture remains the implementation baseline.

## Competition path

`Dataset/Input -> SubmissionProfile -> CaseState -> HardConstraintEvaluator -> Traffic/Attempt/Settlement ledgers -> Factors -> ConflictResolver(primary|fallback) -> Router/DeterministicSimulator -> Decision/Report projections -> validators`.

## Stable boundaries

- hard constraints are absolute and rerun before fallback attempts;
- count/volume allocation is currently recorded once at primary assignment;
- attempts record each invoked provider outcome;
- settlement records approved final provider only;
- organizer decisions expose final selected provider;
- report preserves the TZ-compatible base projection and richer internal evidence;
- Case judge expiry semantics do not weaken production UNKNOWN/economic ownership.

## v0.4.3 audit seams

### 1. Base report meaning

The architecture intentionally has three ledgers. SPEC-019 must prove which ledger feeds organizer base `distribution`; do not delete ledgers or force them to match.

### 2. Independent semantic validation

Keep three distinct validator roles:

- organizer decisions/public validator: supplied compatibility lower bound;
- organizer report shape validator: required keys/types/ranges;
- **semantic report oracle**: independent recomputation from raw inputs + serialized decisions/profile, without ReportBuilder expected values.

Strict/Serialized validators remain valuable internal consistency checks but are not semantic independence.

### 3. Resolver normalization

One ConflictResolver remains authority. Candidate-set robustness is tested at factor normalization boundary. If normalization changes, factor interfaces and exact trace fields stay stable.

### 4. Temporal state

ProviderCaseState owns mutable per-run business state. Any daily rollover fix belongs here as deterministic date-scoped state; it must not introduce DB/jobs/clock infrastructure.

### 5. Optional soft configuration

Missing optional factor configuration must be explicitly neutral. Absence must never silently equal strongest preference.

## Protected production kernel

Production ownership, UNKNOWN, idempotency, durable replay/recovery and provider I/O remain separate and frozen unless the authoritative case creates a direct blocker.
