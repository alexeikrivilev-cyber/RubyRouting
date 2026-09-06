# Decisions

This file records durable project decisions. Behavioral requirements remain authoritative in `specifications/`; this file preserves rationale and marks provisional/superseded choices explicitly.

## D-001 — specification-driven repository
Status: accepted.
Decision: `specifications/` is the behavioral source of truth. Semantic code changes trace to requirements; code/spec drift is a defect.

## D-002 — deterministic financial kernel, adaptive optimizer outside it
Status: accepted.
Decision: economic safety, ownership, eligibility, policy accounting, outcome normalization and hard constraints are deterministic. Adaptive/statistical logic may rank only already-safe feasible actions.

## D-003 — effectively-once economic semantics
Status: accepted.
Decision: one payout intent represents one economic intention. Technical calls may repeat, but retries/failover must not intentionally create an additional payout effect. Provider-local idempotency does not coordinate two independent providers.

## D-004 — distinct accounting views
Status: accepted.
Decision: opportunity, assignment, attempt and settlement are distinct logical facts even if future storage shares physical structures.

## D-005 — deterministic discrepancy allocation before weighted randomness
Status: accepted as baseline direction; exact official semantics pending.
Decision: count/volume allocation minimizes feasible post-decision discrepancy and accounts for committed work. Weighted randomness is optional optimization/tie-breaking, not the correctness mechanism.

## D-006 — primary assignment is the provisional allocation accounting point
Status: provisional; revisit under official-TZ reconciliation.
Decision: until the official case defines otherwise, business target shares are interpreted as primary routing assignments. Recovery/attempt/settlement distribution is measured separately.

Consequence added by v0.2: under this decision, fallback/recovery **must not advance the primary allocation projection**. If official semantics later choose attempt/acceptance/settlement accounting, replace the accounting strategy explicitly.

## D-007 — fallback is fresh re-routing, not a static cascade
Status: accepted.
Decision: after a safely resolved failure, select the next provider from a fresh current decision. v0.2 clarifies that fresh cross-provider fallback excludes already money-moving attempted providers by default; same-provider reuse requires an explicit retry/provider policy.

## D-008 — raw payout failure is not provider-health failure
Status: accepted.
Decision: payout business outcome and reliability feedback are separate signals. Recipient/downstream failures do not automatically penalize the provider.

## D-009 — Ruby is mandatory; executable logic is Ruby-only
Status: accepted.
Decision: all product/routing/reference/simulator/property/model/concurrency executable domain logic is Ruby. Minimal declarative CI/shell is allowed; no second router/oracle in another language.

## D-010 — Goal Mode autonomy inside invariants
Status: accepted.
Decision: agents complete version goals without routine confirmation, use reversible defaults for low-risk ambiguity, maintain a lightweight backlog and change tactic instead of repeating failed actions.

## D-011 — advanced adaptive routing remains optional until measured
Status: accepted.
Decision: bandits/contextual models/correlated-failure inference/counterfactual optimization are extension candidates, not correctness core.

## D-012 — development continues before the full TZ
Status: accepted and strengthened by v0.2.
Decision: absence of the full TZ is not a reason to stop coding. Implement every high-value generic/reversible routing mechanism that can be specified and tested without inventing the external contract.

The active plan is now `docs/exec-plans/active/pre-tz-comprehensive-core.md`.

## D-013 — verification uses independent models and multiple test modes
Status: accepted.
Decision: correctness evidence combines deterministic scenarios, independent oracle checks, property/invariant tests, model/state-machine sequences, controlled concurrency/interleavings, provider contract/fault tests and end-to-end scenarios. Line coverage alone is insufficient.

## D-014 — deterministic testability is architectural
Status: accepted.
Decision: wall-clock time, randomness, provider I/O and external mutable state stay at explicit boundaries whenever they affect domain behavior. Core tests require deterministic simulation/replay seams.

## D-015 — long sessions are version-gated, not milestone-gated
Status: accepted.
Decision: Goal Mode continues through slices/phases/commits until the active Version Goal exit gate passes or every remaining required path is truly externally blocked.

## D-016 — CRuby 4.0.6 development baseline
Status: accepted; reconcile when official judge runtime is published.
Decision: current development targets CRuby 4.0.6, uses `docs/RUBY.md`, exact Integer minor-unit money/Rational ratios, Minitest/Rake, and avoids unnecessary runtime-specific tricks.

## D-017 — plain-Ruby modular monolith with atomic in-memory coordinator
Status: accepted as current architecture baseline.
Decision: deterministic kernel + application orchestrator + narrow ports/adapters + one coarse `Thread::Mutex` coordinator. Correctness state is committed before provider I/O; provider I/O is outside the lock; observations apply later under synchronization.

Internal collaborators/ledgers/reducers may be extracted as v0.2 grows, while retaining one clear atomic coordinator boundary. No service/DB/queue decomposition is implied.

## D-018 — feasible-provider-cohort allocation reset
Status: **SUPERSEDED by D-025 / SPEC-002**.

Historical v0.1 decision: reset the in-memory allocation projection whenever the currently feasible-provider cohort changed.

Why superseded: “feasible” mixed functional opportunity with temporary availability/capacity. Resetting on outage silently erased policy deviation and made current availability redefine historical accounting.

Do not use D-018 for new behavior.

## D-019 — observation identifiers are immutable fact identities
Status: accepted.
Decision: exact replay of one observation ID/payload is idempotent; reuse of the same observation ID with different linkage/normalized payload is an integrity error and cannot rewrite the original fact.

## D-020 — v0.1 is a checkpoint; v0.2 is the current pre-TZ goal
Status: accepted.

Decision: the first green v0.1 implementation is preserved as a checkpoint, not treated as a complete pre-TZ product. Static review found locally solvable correctness/modeling gaps. Current version is **v0.2 — Pre-TZ Comprehensive Routing Core**.

Rationale: waiting for the official TZ while recovery accounting, dispatch ambiguity, replay and operation-contract gaps remain would waste preparation time and force risky changes during the hackathon.

Consequences:

- old v0.1 ExecPlan is archived as completed checkpoint evidence;
- SPEC-002 records amendments/new generic requirements;
- current work follows `docs/exec-plans/active/pre-tz-comprehensive-core.md`;
- official TZ moves to v0.3 rather than blocking v0.2.

## D-021 — primary allocation and recovery traffic are separate under primary-assignment accounting
Status: accepted for the current provisional accounting point.

Decision: a recovery/fallback assignment does not mutate the primary allocation projection when the policy accounting point is `primary_assignment`.

Rationale: business distribution intent and recovery execution answer different questions. Mixing them causes provider failures to distort future primary routing targets.

Consequences: facts/analytics preserve both; future official accounting points may select another ledger explicitly.

## D-022 — provider recovery semantics are operation-scoped
Status: accepted.

Decision: relevant idempotency/status-resolution/TTL/provider-contract semantics are snapshotted with a committed provider operation. Current route eligibility/availability does not erase the ability to resolve an existing operation.

Rationale: disabling a PSP for new traffic must not strand its already unresolved payout operations.

## D-023 — operation dispatch phase is explicit
Status: accepted.

Decision: economic ownership acquisition and provider dispatch are distinct states. An owner that is only committed/being dispatched is not automatically eligible for status resolution or idempotent retry.

Rationale: concurrent duplicate commands otherwise can start a second provider interaction before the first dispatch result is known.

Consequences: transport boundary classifies definitely-not-sent vs ambiguous-after-send; unresolved ambiguity retains ownership.

## D-024 — event chronology is not inferred from semantic status rank
Status: accepted.

Decision: provider observation ordering uses immutable identity, explicit transition legality, and authoritative provider sequence/version only when available. Arbitrary ordering such as `pending < unknown < failure < success` is not a correctness rule.

Rationale: severity is not chronology and cannot safely model out-of-order events or later returns/reversals.

## D-025 — opportunity is separate from live feasibility
Status: accepted pre-TZ; official denominator/window still provisional.

Decision:

- opportunity = functional eligibility for the payout/policy context;
- live feasibility = opportunity plus current availability/capacity/health/hard operational constraints.

Transient live feasibility changes do not automatically reset the allocation window/history.

Rationale: an ineligible PSP could never receive the payout; an eligible-but-down PSP represents a runtime inability to satisfy policy. Those cases require different attribution.

Consequences: D-018 is superseded. Runtime outage/capacity deviations are explicit. Any catch-up/debt must be bounded rather than achieved by silent reset or unlimited burst.

## D-026 — policy definitions are immutable and fingerprinted
Status: accepted.

Decision: one policy identity/epoch/scope maps to one material definition/fingerprint. Conflicting reuse is an integrity error. Decision history records the governing fingerprint.

Rationale: allocation state and replay cannot be correct if the same policy key silently changes meaning.

Consequences: business policy identity is pinned per decision/payout history; live emergency availability/health remains separate.

## D-035 — allocation and policy indexes are fact-backed projections
Status: accepted for the current pre-TZ coordinator.

Decision: primary allocation state and policy-identity validation are derived
from append-preserved typed facts; in-memory indexes may remain as synchronized
performance projections. `Replay.allocation` rebuilds primary allocation measures
and its local commit revision from primary allocation facts.

Rationale: allocation and policy integrity must survive projection rebuilding and
must not depend on an unrecorded coordinator-only cache.

## D-027 — late contradictory economic effects are incidents
Status: accepted.

Decision: a late old-operation observation that indicates a possible monetary effect after fallback/new settlement is not silently ignored. Preserve facts and emit an explicit economic-conflict/reconciliation signal.

Rationale: suppressing stale state mutation is correct, but possible double payout is economically significant even when it belongs to an old operation.

## D-028 — deterministic provider health precedes adaptive ML
Status: accepted for v0.2.

Decision: before any bandit/ML layer, implement attributable operational health with minimum evidence/hysteresis/quarantine/probing and a replaceable deterministic ranker inside the feasible set.

Rationale: this covers the production-relevant “smart routing” mechanics while keeping financial correctness deterministic and testable before the official scoring/data model is known.

## D-029 — facts must support lifecycle replay, not analytics only
Status: accepted for v0.2.

Decision: append-preserved facts must carry enough immutable domain material to rebuild the supported payout/operation/ownership/settlement projection deterministically. `Replay` is not considered complete if it can reconstruct only aggregate analytics.

Rationale: replay is the strongest check that hidden mutable coordinator state has not become the real source of truth and is essential for reconciliation/out-of-order event testing.

## D-030 — version completion is an evidence claim, not a checklist result
Status: accepted.

Decision: a version is not complete merely because all originally planned phases/checklists are green or the canonical test suite passes. Before `VERSION_COMPLETE`, the project enters `VERSION_CANDIDATE` and executes the closure protocol in `docs/COMPLETION_POLICY.md`.

Rationale: v0.1 had a strong green suite but a later source-level review still found material locally solvable interaction defects. Completion therefore requires active attempts to discover missing behavior, not only confirmation of known tests.

Consequences:

- closure performs fresh source/spec/capability/backlog/red-team/documentation passes;
- closure may reopen earlier phases;
- test counts/coverage are evidence, not a completion definition;
- agents report narrower `SLICE_VERIFIED`/`PHASE_VERIFIED` status when version evidence is incomplete.

## D-031 — v0.2 scope cannot be narrowed by implementation convenience
Status: accepted.

Decision: SPEC-003 defines the mandatory generic pre-TZ capability envelope. An agent may not move an unfinished required capability/P0/P1 item to `LATER`, call it “unsupported scope”, or redefine the version around existing code solely to obtain closure.

Rationale: unknown official defaults do not imply that generic policy/capacity/health/recovery/replay concepts should be missing. Most can be represented through explicit replaceable configuration without guessing external contracts.

Consequences: scope reduction requires direct user instruction, authoritative TZ evidence or a durable decision proving equivalent behavior through a simpler mechanism.

## D-033 — authoritative provider sequences require sequenced provider events
Status: accepted for the current pre-TZ reducer.

Decision: when an operation contract declares provider sequence ordering authoritative, an unsequenced provider event cannot establish or replace lifecycle state. A transport classification may still apply without a sequence because it describes the initiating exchange rather than a provider event.

Rationale: accepting an unsequenced first `SUCCESS` would allow an event with unknown chronology to settle an operation before the provider's ordered evidence is available. The conservative rule preserves ownership until a sequenced observation arrives.

## D-032 — current architecture inherits v0.1 baseline through an explicit v0.2 supplement
Status: accepted.

Decision: `docs/ARCHITECTURE.md` remains the detailed historical/currently inherited v0.1 starting architecture. `docs/CURRENT_ARCHITECTURE.md` is the current v0.2 supplement and supersedes the baseline where it adds operation phase, policy, capacity, health, replay and conflict responsibilities.

Rationale: rewriting useful detailed architecture history solely to replace every “v0.1” label would add churn and risk losing rationale. Explicit inheritance provides clearer provenance and current authority.

## D-034 — health attribution and read paths are explicit
Status: accepted for the current pre-TZ health projection.

Decision: provider health transitions require provider-attributed operational
signals; unknown, recipient and downstream attribution are neutral. Health
snapshot reads do not materialize hidden state. Provider registration/configuration
facts are the explicit projection initialization path.

Rationale: allocation pressure must not turn unclassified business/transport
evidence into provider quarantine, and a read-only health inspection must not
create state that lifecycle/replay facts cannot reproduce.

## D-036 — soft constraints are advisory before the official TZ
Status: accepted for the current pre-TZ core.

Decision: hard constraints remain route-eliminating. Soft constraints are
evaluated as typed advisory violations; they do not eliminate an otherwise safe
provider or override allocation/safety ordering. The violations are preserved
in opportunity and assignment decision facts with the
`soft_constraint_relaxed` reason code.

Rationale: SPEC-003 requires an explicit hard/soft policy distinction, while
the official TZ does not yet define a relaxable-objective ordering. Advisory
trace semantics preserve explainability without inventing an irreversible
ranking contract.

## D-037 — unresolved age requires an explicit analytics reference time
Status: accepted for the current pre-TZ core.

Decision: `Analytics` may receive a caller-supplied controlled `as_of` time and
derive age for still-unresolved `pending`/`unknown` payouts from fact timestamps.
Without `as_of`, it reports only age explicitly recorded by a
`reconciliation_blocked` fact. It never reads wall-clock time implicitly.

Rationale: age is a point-in-time metric, while the append-only fact set has no
implicit observation time at which a projection is queried. An explicit
reference preserves deterministic replay and testability.

## D-038 — probing exposure is operation-owned
Status: accepted for the current pre-TZ health projection.

Decision: health evidence emitted for a payout operation changes provider
health state but does not implicitly release a probe exposure. Operation-owned
reservations are keyed by operation and the coordinator releases that specific
reservation once, recording the release as a fact. Standalone reservations and
signals use a separate direct exposure count, so an unrelated standalone
signal cannot release an in-flight payout probe.

Rationale: a health signal is not enough to identify which of multiple in-flight
probe operations completed. Releasing both in the signal reducer and the
operation lifecycle can undercount exposure and violate `probe_limit`; explicit
operation ownership preserves the bound and replay parity. Separating direct
and operation-owned counts also prevents an unrelated external signal from
undercounting an active operation reservation.

## D-039 — stale dispatch commits are non-actions
Status: accepted for the current pre-TZ application boundary.

Decision: a committed assignment whose ownership or dispatch token was
invalidated before provider I/O is treated as a stale non-action. The
coordinator returns a false start claim, and the orchestrator must not call the
provider; it re-enters decision making instead.

Rationale: committing ownership before I/O is required for economic safety, but
the commit can race with a callback or release. Calling the provider after the
token is gone could create a second monetary effect outside the current owner.
