# ExecPlan — v0.3.2 Semantic Control Plane & Recovery Readiness

Status: VERSION_COMPLETE — SPEC-006 fresh closure/red-team passed on the exact pushed pre-TZ revision; no locally solvable P0/P1 remains

## Purpose

Build on the verified v0.3.1 payout-routing kernel and close the next layer of locally solvable product-semantic gaps before the authoritative Hack.Genesis TZ arrives.

This version does not reopen proven economic-safety work. The focus is the semantic control plane around the kernel: typed route identity, provider compatibility, deterministic policy selection, timed recovery, route-aware evidence, configurable product surface and architectural convergence.

## Current Version Goal

Reach a state where a new payout can be described by one canonical route context; one deterministic policy can be selected and explained; only route-compatible providers enter feasibility; unresolved ownership exposes a deterministic next due action; quality/health evidence is comparable to the route being decided; and configuration/analytics are operable through one application model.

The official TZ should then primarily require mapping exact authoritative schemas/formulas/scoring onto existing mechanisms.

### PTZ2-001 closure evidence (2026-08-31)

- `PayoutIntent#routing_context` is the single immutable generic interpretation of method, rail, destination kind and normalized labels; raw context remains available for adapter metadata.
- `ProviderOperationPayload` carries that value, rejects conflicting direct dimensions, and folds legacy direct dimensions into the same canonical value.
- `intent_registered` facts and lifecycle replay preserve the canonical value; persisted mismatches fail closed through the durable corruption boundary.
- Focused evidence: RoutingContext `4 runs, 15 assertions`; provider operation `5 runs, 28 assertions`; payload/restart scenario `2 runs, 17 assertions`; acceptance traceability `1 run, 199 assertions`.
- Exact-head full evidence: `bundle exec rake test` — `490 runs, 9,590 assertions, 0 failures`; broad matrix seeds `property 55125`, `model 58589`, `concurrency 57141`, `fault 17230`, all green (`4/1210`, `3/2941`, `12/944`, `256/3518`).
- Skeptical review fixed two boundary defects before closure: scalar segment normalization and divergent explicit payload dimensions.

### PTZ2-002 closure evidence (2026-08-31)

- `ProviderRouteCapabilities` is the typed provider-side seam for supported payment methods, rails and destination kinds; `nil` remains unconstrained and an explicit empty set fails closed.
- `ProviderOpportunity#functional_eligible_for?` applies route compatibility as a hard functional gate before allocation; `reason_for` emits typed `unsupported_*` exclusions.
- The existing functional cohort/allocation-key path excludes impossible providers from allocation accounting while retaining the full catalog opportunity view for operational explanations.
- Provider definitions round-trip through the durable catalog whitelist and the route exclusion survives replay; explanation exposes the same typed exclusion without recipient/provider raw payloads.
- Focused evidence: capability unit `4 runs, 23 assertions`; capability scenario `1 run, 9 assertions`; acceptance traceability `1 run, 207 assertions`.
- Exact-head full evidence after the final guard: `bundle exec rake test` — seed `23207`, `495 runs, 9,628 assertions, 0 failures, 0 errors, 0 skips`.
- Broad evidence after the skeptical invalid-intent guard: property seed `53191` (`4/1210`), model `40183` (`3/2941`), concurrency `16520` (`12/941`), fault/scenario `2682` (`257/3527`), all green.
- Review finding resolved before closure: the scenario initially asserted a non-public snapshot field; it now verifies the authoritative durable evaluation fact instead of widening the public projection.

### PTZ2-003 closure evidence (2026-08-31)

- `PolicySelector` is a bounded immutable typed selector over currency, canonical route dimensions, normalized labels/segments and explicit non-negative priority; destination aliases are canonicalized and conflicting aliases fail closed.
- `PolicyRegistry#resolve_for_intent` returns a typed `PolicyResolution`, ranks matches lexicographically by `[priority, specificity]`, never uses registration order, and exposes no-match/ambiguity without selecting an arbitrary policy.
- `RoutingPolicy#applies_to?` is the shared policy-route compatibility check for registry resolution and explicit coordinator commands; selector/currency mismatches are rejected before intent or policy facts are registered.
- The orchestrator uses typed resolution for new payouts, preserves the durable pinned policy before consulting changed active configuration on resume, and policy selector definitions/fingerprints round-trip through restart.
- Focused evidence after the final boundary review: resolver/policy `30 runs, 109 assertions` across `policy_resolution_test` and `policy_test`; acceptance traceability `1 run, 218 assertions`; route/context regression remained green.
- Exact-head full evidence after the final selector/applicability boundary changes: `bundle exec rake test` — seed `18369`, `503 runs, 9,679 assertions, 0 failures, 0 errors, 0 skips`.
- Broad evidence: property seed `54416` (`4/1210`), model seed `52220` (`3/2941`), concurrency seed `32305` (`12/947`), fault/scenario seed `63730` (`257/3527`), all green.
- Skeptical review added alias/conflict coverage, explicit selector mismatch fail-closed behavior and durable selector/fingerprint restart coverage; no unbounded rules DSL or alternate routing path was introduced.

### PTZ2-005 closure evidence (2026-08-31)

- `RecoveryPolicy` now defines a deterministic exact-integer schedule: `initial_delay_seconds + backoff_seconds * interaction_index`, optionally capped by `max_delay_seconds`; default policies preserve v0.3.1 policy fingerprints.
- An unresolved applied provider observation stores an immutable `RecoverySchedule` with operation linkage, wall/monotonic anchors, due time, action (`resolve`/`retry_same`) and typed reason. The existing observation restorer and lifecycle replay reconstruct it; a new decision or ownership release clears it.
- Coordinator `prepare` and restart resume enforce the schedule before evaluation/provider I/O using both wall and exact monotonic time. TTL/deadline expiry is checked first and clears scheduled recovery into reconciliation-blocked ownership.
- `PayoutSnapshot`, HTTP snapshot mapping and `DecisionExplanation` expose `next_action`/`next_action_at`; `Coordinator#due_recovery_work` and application `Queries#due_work` return deterministic, sorted due recovery or explicit reconciliation items as of a supplied wall time. Future TTL expiry is reported as reconciliation even before a mutating command materializes the block.
- Focused evidence: recovery schedule `6 runs, 52 assertions`; replay `14 runs, 46 assertions`; existing recovery, observation/restorer, restart-resolution and public-audit regressions all green; acceptance traceability includes PTZ2-005.
- Exact-head full evidence after replay hardening: `bundle exec rake test` — seed `6330`, `509 runs, 9,745 assertions, 0 failures, 0 errors, 0 skips`.
- Broad evidence: property seed `64472` (`4/1210`), model seed `28530` (`3/2941`), concurrency seed `21521` (`12/941`), fault/scenario seed `7241` (`263/3579`), all green.
- Skeptical findings fixed before closure: restore must clear an obsolete schedule after a resolution decision; public audit must explicitly allow only the safe schedule projection; future due-work must not misclassify an operation whose contract has already expired; replay must reject rather than drop a schedule on an unapplied observation or an unsupported/unlinked operation; frozen journal timestamps must be normalized non-mutatively.

### PTZ2-004 closure evidence (2026-08-31)

- `Application::RoutingConfiguration` is the single immutable active configuration value for typed policies and provider opportunities. It reuses `RoutingPolicy`, `ProviderOpportunity` and `PolicyRegistry` validation and canonicalizes collection order for stable `to_h` serialization.
- `Commands#apply_configuration` validates the full replacement before mutating the provider catalog, atomically swaps the active policy registry after candidate validation, and updates a shared thread-safe configuration holder. Existing policy/provider commands keep the queried configuration synchronized.
- `Queries#configuration` exposes the active value without mixing it into payout facts. Applying a new active policy/provider set does not create a historical policy fact; a payout already pinned to the old policy resumes through its durable policy and operation contract after active replacement.
- Focused evidence: application service `9 runs, 47 assertions`; acceptance traceability `1 run, 249 assertions`; restart-recovery `98 runs, 255 assertions`; policy-resolution regression remained green.
- Exact-head full evidence after the active configuration boundary: `bundle exec rake test` — `514 runs, 9,780 assertions, 0 failures, 0 errors, 0 skips`.
- Broad evidence: property seed `32067` (`4/1210`), model seed `16605` (`3/2941`), concurrency seed `28516` (`12/939`), fault/scenario seed `56106` (`266/3601`), all green.
- Skeptical review confirmed no alternate routing algorithm or PSP schema entered the application layer; invalid configuration is rejected before provider catalog mutation, and active policy replacement cannot rewrite unresolved payout history.

### PTZ2-101/102 closure evidence (2026-08-31)

- `QualityController` now records each provider-attributed terminal outcome in the global cohort, a normalized label context cohort and, when at least one typed route dimension exists, a typed-only route cohort. Route cohorts ignore labels, so labels remain a separate broader context dimension with bounded cardinality.
- Routing quality selection is ordered as mature/non-stale route, mature/non-stale label context, mature/non-stale global evidence, then the configured prior. Quality remains downstream of hard eligibility and allocation authority; pending, UNKNOWN and recipient/downstream outcomes remain neutral.
- `QualityPolicy#max_evidence_age_seconds` and injected observation/as-of times make freshness explicit. Age is exact `Rational` wall-time arithmetic, the allowed boundary is fresh, and mature stale or unknown-age evidence cannot be selected when max age is configured.
- Durable quality facts retain observation time, last evidence time, max-age policy and typed route identity. Provider-evidence restore, standalone quality replay, opportunity-evaluation validation, decision-trace validation and public audit use the same fields without exposing raw recipient data.
- Focused evidence: quality unit `14 runs, 71 assertions`; quality hardening `3 runs, 14 assertions`; decision evaluation `1 run, 5 assertions`; provider payload `2 runs, 17 assertions`; acceptance traceability is extended with PTZ2-101/102.
- Skeptical findings fixed before closure: route labels could contaminate typed route identity and hash route keys could leak as pseudo-labels; live quality timestamps initially diverged from replay query views; and filling an absent provider-observation timestamp would break observation-id deduplication after restart. Route state now uses a typed-only key, query comparisons accept a shared as-of, and quality timestamp durability is separate from the immutable observation payload.

## Governing sources

Read and obey, in order:

1. `AGENTS.md`
2. `specifications/006-pre-tz-semantic-control-plane.md`
3. this ExecPlan
4. `docs/PRE_TZ_BACKLOG.md`
5. `docs/ROADMAP.md`
6. `docs/PRE_TZ_ARCHITECTURE.md`
7. `specifications/005-pre-tz-maximum-hardening.md` for inherited guarantees
8. `docs/COMPLETION_POLICY.md`
9. `docs/TZ_RECONCILIATION.md`.

If the authoritative TZ arrives, stop speculative expansion and execute `docs/TZ_RECONCILIATION.md` before continuing implementation.

## Protected baseline

Treat v0.3.1 at `01c00f2f258a82fcf6e3b2ee843947a68ba62ed1` as the completed pre-version baseline.

Preserve:

- exact Integer/Rational financial arithmetic;
- one economic intent and at most one unresolved money-moving owner;
- conservative `UNKNOWN` ownership blocking;
- provider-local idempotency boundary;
- primary/recovery/settlement accounting separation;
- hard eligibility/admission before allocation/optimization;
- provider I/O outside the atomic state lock;
- immutable provider-operation payload and pinned operation contract;
- dimensionally correct analytics;
- deterministic allocation and recovery legality;
- restart-safe unresolved continuation;
- typed explanation/public-audit safety;
- reproducible unit/property/model/concurrency/fault/restart evidence.

## Long-session continuation contract

Operate continuously in Goal Mode:

`orient -> inspect current implementation -> choose highest-value unblocked slice -> establish acceptance -> implement -> focused verify -> broad verify -> skeptical review -> update plan/backlog -> choose next slice -> continue`

A file, test, commit, milestone or phase completion is not a stop condition.

Stop only when:

1. every v0.3.2 exit criterion is satisfied on the exact candidate revision; or
2. every remaining required path is externally blocked and no independent case-relevant work remains; or
3. the authoritative TZ arrives, in which case switch to the reconciliation protocol.

A failing test, difficult local bug, reversible design choice, need for repository/official-doc research, or uncertainty resolvable from current evidence is not an external blocker.

Keep the `Rolling Next Actions` section small and current. Replace completed actions rather than accumulating a diary.

## Phase 0 — Re-orient and prove baseline — VERIFIED

Goal: synchronize the plan with actual `main` before changing behavior.

Required work:

- inspect repository tree and current implementation, not only docs;
- verify current version/HEAD and relevant existing tests;
- map SPEC-006 requirements to existing seams and identify where a proposed mechanism already partially exists;
- record any contradiction between this plan and actual code before implementation.

Exit gate:

- baseline is understood and no current safety regression is ignored;
- the first implementation slice is the smallest high-value dependency for later phases.

### Current factual baseline (2026-08-31)

- Exact `main` revision at orientation: `337da3e88aee21b83555b3e34fd4aefd6b7b707f`.
- Working tree was clean before implementation.
- `bundle check` passed on the configured CRuby 4.0.6 environment.
- Baseline verification passed: full suite `484 runs, 9,550 assertions`; property `4 runs, 1,210 assertions`; model `3 runs, 2,941 assertions`; concurrency `12 runs, 941 assertions`; fault matrix `256 runs, 3,515 assertions`.
- The active queue is materially unimplemented in code: no canonical `RoutingContext`, no explicit method/rail/destination capability fields on `ProviderOpportunity`, registration-order-independent resolver, recovery due schedule, typed active configuration model, filtered analytics query, or SPEC-006 acceptance mapping.
- Existing seams are usable: `PayoutIntent` owns the raw provider context, `ProviderOperationPayload` is the existing immutable adapter payload, `ProviderOpportunity#functional_eligible_for?` owns functional matching, `PolicyRegistry#find_for_intent` owns automatic policy lookup, `QualityController` owns context evidence, and `DecisionEvaluator` is the canonical live evaluation seam.
- The first dependency slice is PTZ2-001. It can be implemented without changing allocation, ownership, provider I/O, durable fact meaning, or the existing raw adapter payload. Provider capability matching and policy resolution must consume the new value before their own semantics are changed.

### Session Goal

Advance the whole v0.3.2 Version Goal toward exact-head closure by replacing the identified semantic-control-plane gaps with one canonical, deterministic and executable product path, preserving the proven financial kernel and continuously following each newly unblocked case-relevant slice through focused and broad verification. The session stops only at a fresh SPEC-006 closure, an exact external blocker with no independent work remaining, or the official TZ authority switch.

## Phase 1 — Canonical RoutingContext — P0 — VERIFIED

Goal: create one immutable generic representation of route-relevant payout dimensions.

Required outcomes:

- canonical typed access to payment method, rail, destination kind and normalized generic labels where applicable;
- economic currency/amount remain sourced from `Money`/intent rather than duplicated inconsistently;
- provider-operation raw context may remain richer, but routing-critical values have one normalized interpretation;
- context is deterministic, immutable and explanation-safe.

Verification:

- canonicalization unit tests;
- semantic-equivalence/metamorphic tests for string/symbol/input ordering where relevant;
- provider-operation payload remains semantically stable across retry/restart.

Freedom:

- exact class/module/file names are implementation choices;
- do not create a general rules engine.

## Phase 2 — Provider route capability matching — P0 — VERIFIED

Goal: provider functional eligibility understands the same route dimensions as payout execution.

Required outcomes:

- explicit generic support matching for configured methods/rails/destination kinds as needed;
- currency/amount/context constraints remain compatible with existing behavior;
- unsupported route dimension produces a typed functional exclusion;
- opportunity accounting does not create debt for providers that could never legally handle the route.

Verification:

- table/property coverage across method/rail/currency combinations;
- no regression in opportunity-cohort allocation invariants;
- explanation exposes route-compatibility exclusion without PSP-specific fields.

## Phase 3 — Deterministic PolicyResolver — P0 — VERIFIED

Goal: remove registration-order business semantics from automatic policy selection.

Required outcomes:

- typed policy selectors tied to route context;
- explicit deterministic precedence/specificity/priority rule;
- explicit no-match result;
- explicit ambiguity result for equal-precedence competing matches;
- explicit/pinned policy input still works and is validated;
- selected policy identity/fingerprint remains pinned to payout history.

Verification:

- registration order permutation does not change the winner;
- ambiguous configuration remains ambiguous under permutation;
- restart/history preserves previously pinned policy even if current active config changes;
- property/metamorphic tests for resolver determinism.

Do not implement an unbounded DSL before TZ.

## Phase 4 — Active configuration model — P0/P1 — VERIFIED

Goal: make “configurable routing strategies” a product capability, not only a Ruby constructor capability.

Required outcomes:

- typed application DTO/model for policy definitions/selectors and provider definitions;
- validation of target shares/measure/recovery/provider route capabilities/admission settings through existing domain types;
- explicit bootstrap/control-plane boundary for active configuration;
- historical payout semantics remain pinned and immutable;
- thin application commands for applying current config.

Optional after the model is stable:

- minimal HTTP endpoints that map directly to the application configuration model.

Do not let HTTP invent routing semantics.

## Phase 5 — Recovery schedule and due work — P0 — VERIFIED

Goal: recovery knows not only the next legal action but also when it is due.

Required outcomes:

- deterministic schedule/backoff model using injected time;
- `next_action_at` or equivalent evidence for unresolved operations;
- TTL/deadline precedence is explicit;
- repeated early resume cannot bypass configured scheduling;
- query/projection can identify due unresolved work as of a supplied time;
- restart/replay preserves equivalent schedule semantics.

Verification:

- fake-clock deterministic tests, no real sleeping;
- unknown owner remains blocked across early resume calls;
- exact due boundary tests;
- TTL/deadline versus backoff tests;
- restart due-work equivalence.

No queue/background framework is required.

## Phase 6 — Route-aware quality and time staleness — P1 — VERIFIED

Goal: quality evidence is both statistically and temporally comparable to the route being optimized.

Required outcomes:

- use canonical routing context for bounded route cohorts where meaningful;
- mature route cohort -> mature broader provider evidence -> prior/default fallback;
- add deterministic time staleness/max-evidence-age or equivalent;
- sample maturity and time staleness remain separate concepts;
- pending/UNKNOWN/non-provider failures remain neutral;
- quality still cannot bypass allocation authority.

Verification:

- sparse cohort versus mature global;
- mature route cohort selection;
- old evidence losing authority without requiring N newer samples;
- replay equivalence with injected time/evidence timestamps;
- optimizer trace names evidence scope and staleness.

Do not introduce ML/bandits.

## Phase 7 — Canonical provider interaction telemetry — P1 — VERIFIED

Goal: fast health can be driven by evidence observed in the normal provider interaction path.

Required outcomes:

- measure provider interaction duration through injected monotonic time where practical;
- normalize transport/timeout/service/overload/latency evidence into existing health vocabulary;
- economic `UNKNOWN` meaning remains unchanged;
- recipient/downstream outcomes remain neutral for provider health;
- telemetry is durable only to the extent needed for replay/explanation/correctness.

Verification:

- fake-clock latency threshold scenarios;
- ambiguous transport affects future health/admission but retains owner;
- provider service evidence degrades health;
- recipient failure does not.

Context-scoped health is optional and should be added only if a bounded clear use case is proven.

### PTZ2-103 closure evidence (2026-08-31)

- The canonical `Application::Orchestrator` measures start/end using the
  coordinator's injected exact monotonic clock for both initiate and resolve.
- `ProviderObservation#interaction_duration_seconds` is immutable, accepts only
  exact non-negative Integer/Rational values and is included in observation
  identity, durable facts, explanation/public-audit projection and restore.
- A configured positive `latency_threshold_ms` emits `latency_pressure` only
  for provider-attributable slow normal observations. Transport classifications
  and provider-service failures keep their more specific signal; economic
  UNKNOWN, ownership and fallback legality are unchanged; recipient/downstream
  outcomes remain health-neutral.
- Focused evidence: normalizer `10 runs, 24 assertions`; health scenarios `26
  runs, 155 assertions`; observation ledger `5 runs, 28 assertions`; provider
  evidence restorer `3 runs, 11 assertions`; restart recovery `98 runs, 255
  assertions`; acceptance traceability `1 run, 279 assertions`. Full exact-head
  evidence: `bundle exec rake test` — `523 runs, 9867 assertions, 0 failures,
  0 errors, 0 skips`. Broad exact-candidate evidence: property seed `49042`
  (`4/1210`), model seed `21298` (`3/2941`), concurrency seed `55654`
  (`12/943`), fault/scenario seed `27881` (`271/3633`), all green.

### PTZ2-105 closure evidence (2026-08-31)

- `DecisionEvaluator.prepare` is the shared pure preparation contract for
  eligibility, policy-measure exclusions and runtime feasibility. The live
  evaluator and standalone `DecisionEngine` compatibility path both consume
  it; only the live path owns dynamic catalog/admission materialization and
  immutable atomic evaluation construction.
- Focused evidence: decision evaluation `2 runs, 11 assertions`; acceptance
  traceability `1 run, 287 assertions`; deterministic scenario `1 run, 40
  assertions`. Full exact-head evidence: `bundle exec rake test` — `524 runs,
  9887 assertions, 0 failures, 0 errors, 0 skips`. Broad evidence: property
  seed `33712` (`4/1210`), model seed `8040` (`3/2941`), concurrency seed
  `28709` (`12/943`), fault/scenario seed `55086` (`271/3633`), all green.

### PTZ2-106 closure evidence (2026-08-31)

- `LifecycleLedger::OutcomeReduction` is the pure canonical reducer for
  outcome phase, public lifecycle status and ownership-release classification.
  Live `OperationCommitter` uses it through `LifecycleLedger#apply_outcome`,
  observation restore uses the same reducer through `status_for`, and replay
  plus Analytics use its status adapter. Provider I/O, ownership mutation and
  durable fact ordering remain outside the pure reducer.
- The reducer preserves the safety matrix: success settles and releases,
  terminal payout failure terminates and releases, safe provider failures
  release, unresolved or unsafe provider failures remain UNKNOWN and retain
  ownership.
- Focused evidence: lifecycle `7 runs, 63 assertions`; replay `14 runs, 46
  assertions`; projection replay `18 runs, 99 assertions`; analytics
  dimensions `1 run, 15 assertions`; observation restore `3 runs, 15
  assertions`. Acceptance traceability now includes PTZ2-106.
- Exact-head full evidence after the shared reducer: `bundle exec ruby -Ilib
  -Itest -e "Dir['test/**/*_test.rb'].sort.each { |path| require
  File.expand_path(path) }"` — seed `25964`, `528 runs, 9960 assertions, 0
  failures, 0 errors, 0 skips`. Broad exact-head evidence: property seed
  `59193` (`4/1210`), model seed `36087` (`3/2941`), concurrency seed `46069`
  (`12/938`), fault/scenario seed `39221` (`271/3633`), all green.

## Phase 8 — Recovery objective seam — P1

Goal: recovery-provider optimization is explicit enough to accommodate likely TZ differences without rewriting safety logic.

Status: VERIFIED on the exact current working tree.

Required outcomes:

- current allocation-constrained recovery behavior remains a named/default semantic;
- selection legality is separate from optimization objective;
- if additional mode(s) are implemented, use lexicographic priorities and typed configuration;
- primary allocation ledger remains uncontaminated under current accounting semantics.

Prefer the minimum extension seam over feature-count-driven modes.

Closure evidence:

- `RoutingPolicy#recovery_objective` is an immutable typed `RecoveryObjective`; the only current mode is `allocation_constrained`.
- `RecoverySelection` dispatches on the objective after normalizing and excluding already-attempted providers, while recovery legality remains owned by `Recovery` and the primary ledger remains untouched for recovery roles.
- The default objective is intentionally omitted from `RoutingPolicy#to_h` and fingerprint material so historical durable policy definitions retain their identity; non-default modes, when authorized later, are structurally ready to become explicit policy identity.
- Focused evidence: policy `23 runs, 84 assertions`; allocation `31 runs, 108 assertions`; acceptance traceability `1 run, 295 assertions` includes PTZ2-104.
- Skeptical review confirmed unsupported modes fail closed at typed construction and no speculative reliability-first/hybrid scoring was introduced.

## Phase 9 — Architecture convergence — P1 — VERIFIED

Goal: reduce semantic sources of truth before official-TZ edits make them expensive.

Current status: PTZ2-106, PTZ2-107, PTZ2-108, PTZ2-109 and PTZ2-110 implemented/verified; fresh SPEC-006 closure passed in Phase 11.

Required outcomes:

- remove or redirect `DecisionEngine` standalone compatibility computation through the canonical prepared-evaluation builder;
- identify the highest-value remaining live/restore duplicated business rule and converge it through shared transition/invariant logic;
- keep `Coordinator` as atomic facade but reduce one or more coherent reasons-to-change where evidence supports extraction;
- resolve `max_slots` / `max_count` semantic ambiguity or document/test why both are independently meaningful.

Rules:

- no cosmetic decomposition;
- no new restorer merely to move lines;
- every refactor must preserve current full verification evidence.

PTZ2-107 closure evidence:

- Actual admission paths had no independent slot/count behavior: each payout incremented and released both counters together, while throughput already owned time-window counts.
- `CapacityBudget#concurrent_limit` now makes the stricter `max_slots`/legacy `max_count` cap explicit; live and replay use one `in_flight` counter, while durable/public aliases remain compatible and snapshot mismatch fails closed.
- Focused evidence: admission ledger `7 runs, 29 assertions`; capacity `3 runs, 15 assertions`; replay `14 runs, 46 assertions`; admission property `1 run, 360 assertions`; coordinator races `11 runs, 43 assertions`.
- Acceptance traceability includes PTZ2-107. Broad semantic review confirms amount exposure and throughput windows remain independent.

PTZ2-106 closure evidence:

- The actual duplicated outcome `case` in replay and Analytics now delegates to
  `LifecycleLedger.reduce_status`; live commit and observation restoration
  delegate to `LifecycleLedger.reduce_outcome`. No new restorer or parallel
  lifecycle state machine was introduced.
- The pure reducer's focused matrix covers success, pending, UNKNOWN, safe and
  unsafe provider failures, and terminal payout failure. Existing replay,
  restart, fault and ownership evidence exercises the shared status semantics
  through real fact histories.

## Phase 10 — Product query surface — P1/P2 — VERIFIED for required scope

Goal: make the strong underlying model easy to operate and demonstrate.

Required outcomes:

- filtered/grouped dimension-safe analytics query surface;
- policy/configuration query surface matching the typed configuration model;
- due-recovery query exposed through application queries;
- audit querying should have a bounded/indexable abstraction if profiling shows full-history scanning materially matters.

HTTP/UI remain adapters over these queries.

### PTZ2-108 closure evidence (2026-08-31)

- `Analytics#query` is a typed read-only query over the canonical additive
  dimension maps for assignment, primary assignment/target/deviation and
  settlement. `Application::Queries#analytics_query` only rebuilds the
  canonical replay projection and delegates to that query seam.
- Filters and group fields are restricted to canonical policy id/epoch/scope,
  window/cohort, measure, currency and provider dimensions. Query selection
  canonicalizes those values and rejects any varying ungrouped dimension before
  summation, preserving policy identity and preventing count/volume/currency
  aggregation across incompatible rows.
- Focused evidence: analytics dimensions `2 runs, 24 assertions`; projection
  replay `18 runs, 99 assertions`; application service `9 runs, 47 assertions`;
  acceptance traceability `1 run, 313 assertions`.
- Exact-head full evidence after the query seam: `bundle exec ruby -Ilib -Itest
  -e "Dir['test/**/*_test.rb'].sort.each { |path| require
  File.expand_path(path) }"` — seed `42706`, `529 runs, 9980 assertions, 0
  failures, 0 errors, 0 skips`. Broad exact-head evidence: property seed
  `44131` (`4/1210`), model seed `19007` (`3/2941`), concurrency seed `13270`
  (`12/941`), fault/scenario seed `26399` (`272/3642`), all green.

### PTZ2-109 closure evidence (2026-08-31)

- `Demo::Scenario.run` now applies a typed `RoutingConfiguration` through the
  application service before submitting the payout. A custom run can supply
  its own typed policy/provider opportunity set, adapter map and intent;
  policy shares, generic route capabilities, capacity and recovery timing are
  exercised by the existing canonical coordinator path.
- The default demo retains its explicit simulated-provider label and existing
  safe-fallback storyline. No CLI/HTTP layer gained alternate selection logic,
  PSP-specific fields or production-scale claims.
- Focused evidence: demo scenario `2 runs, 12 assertions`; application service
  `9 runs, 47 assertions`; HTTP regression `9 runs, 61 assertions`; acceptance
  traceability `1 run, 318 assertions`.
- Exact-head full evidence after the configured demo path: `bundle exec ruby
  -Ilib -Itest -e "Dir['test/**/*_test.rb'].sort.each { |path| require
  File.expand_path(path) }"` — seed `34425`, `530 runs, 9985 assertions, 0
  failures, 0 errors, 0 skips`. Broad exact-head evidence: property seed
  `42680` (`4/1210`), model seed `19457` (`3/2941`), concurrency seed `36138`
  (`12/946`), fault/scenario seed `50764` (`273/3648`), all green.

### PTZ2-110 closure evidence (2026-08-31)

- `State::FactStore` builds payout-id and fact-type indexes from the validated
  durable prefix and updates them only when facts publish after the existing
  durable append boundary. Queries with both filters choose the smaller index
  and retain sequence order; staged facts remain visible to reads made inside
  the current transaction. `FactPage` is immutable and carries only the
  requested page, total and deterministic continuation offset.
- `Application::Queries#audit_facts` now delegates to the indexed store query;
  `audit_facts_page` delegates to the bounded page seam. The public HTTP audit
  path maps only `page.facts`, preserving the existing privacy projection and
  pagination contract without changing replay or durable fact shape.
- Focused evidence: FactStore `16 runs, 69 assertions`; HTTP audit regression
  `9 runs, 61 assertions`; bounded history evidence `2 runs, 15 assertions`;
  acceptance traceability `1 run, 323 assertions`.
- Exact-head bounded profile: `bundle exec rake history_profile` on CRuby 4.0.6
  without YJIT measured 500 payouts/7,002 facts, 0.0003 seconds for 100
  unfiltered page reads, 0.0007 seconds for 100 payout/type-filtered page
  reads, 0.6982 seconds restore and 696.9 concurrent ops/s (four workers).
  This remains bounded evidence, not a 100k or production-scale claim.

## Phase 11 — Verification and closure — P0 — VERIFIED

Goal: make SPEC-006 claims executable and close the exact candidate skeptically.

Required outcomes:

- stable SPEC-006 acceptance IDs added to traceability;
- focused unit/scenario/property/model/concurrency/fault/restart coverage proportional to each change;
- material randomized failures expose seed/trace;
- all full canonical commands pass on the exact revision;
- performance campaigns are rerun only where affected and claims remain bounded;
- docs/roadmap/backlog reflect actual code, not intended code;
- no locally solvable P0/P1 SPEC-006 defect remains.

### Fresh closure discovery — 2026-08-31

- Pass R initially found stale active-plan/version references in
  `docs/exec-plans/README.md`, `docs/PLANS.md`, `docs/WORKFLOW.md` and the
  testing guide. These were locally corrected to point at the v0.3.2 active
  plan; the corrected exact HEAD was then re-verified.

### Fresh SPEC-006 closure result — 2026-08-31

- Passes A–L reconciled the governing SPEC-006 and inherited protected
  behavior against the reachable production modules. The canonical flow has
  one routing/evaluation path, provider I/O remains outside the atomic state
  boundary, and the UNKNOWN/ownership, payload, allocation, recovery,
  settlement and public-audit safety invariants remained intact under the
  targeted red-team scenarios.
- Pass M found no production `TODO`, `FIXME` or `XXX`; `NotImplementedError`
  is limited to the intentionally abstract provider and normalizer ports.
  Real clocks are limited to the injectable clock fallback and tests use
  controlled clocks for timing-sensitive semantics. Production Float use is
  limited to rejecting unsafe durable values; no financial or allocation path
  uses Float. Historical documents remain explicitly historical rather than
  active authority, and there is one current ExecPlan.
- Passes N–O on the exact candidate: `bundle check`; full `bundle exec rake
  test` seed `12996` (`533 runs, 10,006 assertions, 0 failures, 0 errors, 0
  skips`); property seed `58740` (`4/1,210`); model seed `32193`
  (`3/2,941`); concurrency seed `9551` (`12/939`); fault/scenario seed
  `10357` (`273/3,650`). Product evidence also passed `benchmark`, the
  10,000-payout load campaign (140,002 facts), degradation metrics (2,000
  payouts, seed `20260829`), bounded history profile and the configured demo.
- The bounded history run measured 500 payouts/7,002 facts on CRuby 4.0.6
  without YJIT: 0.0407 seconds analytics replay, 0.6982 seconds restore,
  0.0003 seconds for 100 unfiltered page reads, 0.0007 seconds for 100
  payout/type-filtered page reads and 696.9 concurrent operations/second
  across four workers. These are reproducible bounded observations, not a
  production-scale or 100k claim.
- Pass P leaves only optional P2 work (context-scoped health, UI polish and
  adaptive exploration) plus the official-TZ reconciliation. Pass Q confirms
  `docs/TZ_RECONCILIATION.md` is ready; no authoritative TZ is present. Pass R
  confirms active documentation now describes the same completed v0.3.2
  pre-TZ goal and authority switch.
- Closure result: all 16 v0.3.2 exit criteria are evidenced on the exact
  candidate revision; PTZ2-006 is verified and the plan is `VERSION_COMPLETE`.

## v0.3.2 exit criteria

All must hold:

1. one typed routing context is canonical for route-relevant dimensions;
2. provider eligibility can explicitly match the supported generic route dimensions;
3. policy auto-resolution is deterministic, registration-order independent and ambiguity-safe;
4. active configuration versus durable historical semantics is explicit and tested;
5. unresolved recovery exposes deterministic due-time semantics and cannot be spam-resumed around the schedule;
6. due unresolved work is queryable without requiring a queue framework;
7. quality handles route cohorts and time staleness without weakening existing confidence/attribution rules;
8. canonical provider interactions can generate fast-health operational evidence from controlled timing/transport observations;
9. configuration is represented by a typed application model suitable for later HTTP/judge mapping;
10. analytics can be queried by compatible dimensions without invalid aggregation;
11. duplicate evaluation/live-restore semantics identified by SPEC-006 are materially reduced;
12. admission `max_slots/max_count` semantics are unambiguous and verified;
13. SPEC-006 executable traceability is live;
14. full test/property/model/concurrency/fault/restart verification is green on exact HEAD;
15. documentation matches actual behavior;
16. remaining required work is authoritative-TZ/judge-specific or deliberately optional P2.

## Rolling Next Actions

1. Preserve this exact closure record until the authoritative TZ arrives.
2. When the TZ arrives, freeze speculative work and execute
   `docs/TZ_RECONCILIATION.md` before TZ-specific coding.
3. If new local evidence exposes a material P0/P1 regression, reopen the
   affected phase and run a fresh closure on the new exact revision.

## Stop report

When v0.3.2 closes, report:

- exact HEAD;
- exit criteria and evidence;
- full verification results;
- measured behavior changed by the version;
- residual optional/TZ-blocked work;
- docs moved to the next current version.

Do not reopen speculative pre-TZ scope solely because optional P2 ideas remain;
the next normative change is the authoritative-TZ reconciliation.
