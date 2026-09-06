# Decisions — v0.3.5 Economic Effect Safety & Adapter Readiness

Status: VERSION_COMPLETE decision supplement for SPEC-009; fresh skeptical discovery and exact-head local CI are green.

This file inherits all compatible accepted decisions from v0.3.4 and earlier. It changes authority only where stated below.

## D-351 — v0.3.4 is a protected completed baseline

Status: accepted.

Decision: SPEC-008/v0.3.4 remains `VERSION_COMPLETE` historical baseline. v0.3.5 may reopen a mechanism only when a new reproducer or measurement demonstrates a material gap.

## D-352 — live invocation and economic ownership are independent safety dimensions

Status: accepted.

Decision: absence of durable economic ownership is not by itself sufficient to permit fresh cross-provider money movement if a previous provider `initiate` invocation is still live and can independently produce an economic effect.

Rationale: an independently delivered callback may release lifecycle ownership while the request that can move money is still executing outside the Coordinator lock.

## D-353 — money-moving live interaction fences fresh cross-provider assignment

Status: accepted after deterministic reproduction and focused/broad verification.

Decision: while a live `assign` or `retry_same` provider `initiate` exists for a payout, a fresh provider assignment must fail closed/defer unless provider semantics explicitly prove the live invocation cannot succeed.

Status lookup/resolution is not itself money-moving and must not be over-serialized merely because it is a provider interaction.

Implementation boundary: the existing process-local invocation token carries the typed money-moving distinction; the Coordinator fences only an owner-free fresh decision for that payout while such a token exists. Existing ownership/dispatch-in-progress classification remains authoritative while the current operation still owns the payout.

## D-354 — `safe_to_release` is lifecycle evidence, not universal causal dominance

Status: accepted.

Decision: `NormalizedOutcome#safe_to_release?` may authorize lifecycle release under normalized provider semantics, but does not automatically prove that every concurrent money-moving invocation for that payout has ceased to be economically live.

Rationale: provider event ordering and request execution are distinct dimensions, especially for independently delivered webhooks and providers without authoritative sequence semantics.

## D-355 — prefer a narrow live-money-moving fence over new provider-specific causal metadata

Status: accepted as implementation preference.

Decision: first attempt the smallest conservative solution using the existing process-local invocation ownership model. Do not add generalized causal tokens, distributed leases or provider-event vector clocks unless a deterministic counterexample proves the narrow fence insufficient.

## D-356 — late contradictory success is reconciliation-grade evidence

Status: accepted.

Decision: if canonical lifecycle state was released/terminated by independent evidence while a protected live money-moving invocation later returns success, the product must not silently overwrite history or route a second provider during the live interval. Contradictory late success is explicit settlement/conflict/reconciliation evidence according to canonical lifecycle rules.

## D-357 — adapter network deadlines belong to adapters

Status: accepted.

Decision: provider adapters own connect/read/request timeouts and transport uncertainty classification. Generic core code must not use unsafe asynchronous thread termination as a substitute for provider-specific timeout semantics.

Operation TTL/deadline remains an economic/recovery contract and is distinct from low-level network timeout configuration.

## D-358 — no pre-TZ distributed exactly-once claim

Status: accepted.

Decision: process-local live interaction ownership/fencing is not a cross-process guarantee. Do not introduce Redis/database/distributed leases before the authoritative process/deployment contract exists. Documentation and demos must not claim distributed exactly-once execution.

## D-359 — architecture/performance work remains evidence-gated

Status: accepted.

Decision: large Coordinator/Analytics files, history growth or aesthetic concerns are not enough to justify pre-TZ refactoring. Extract only a clear invariant owner or optimize only a measured case-relevant bottleneck.

## D-360 — provider observation ordering remains narrow and typed

Status: accepted after deterministic live-initiate adjacency evidence.

Decision: retain the existing observation identity and provider-declared authoritative sequence rules. A duplicate observation is idempotent; an out-of-order authoritative observation is recorded as non-applying; neither may regress lifecycle state or open fresh money movement while a prior `initiate` remains live. No generalized causal/vector-clock metadata is introduced before the authoritative TZ.

Evidence: the live economic-effect matrix exercises sequence 2 → stale 1 → release 3 during a blocked A initiate, plus duplicate callback delivery, terminal/temporary release and existing callback-before-token cases.

## D-361 — raw adapter timeout is not a generic transport classification

Status: accepted after conformance regression evidence.

Decision: the generic core handles only explicit `ProviderTransportResult`/`ProviderTransportError` classifications. A raw adapter timeout or programming/contract exception must surface, must not be guessed as `definitely_not_sent`, and must leave the committed operation recoverable under its durable status-lookup/idempotent-retry contract. Connect/read/request bounds remain adapter-owned and distinct from operation TTL/deadline.

Evidence: `OrchestratorSimulatorTest` exercises explicit ambiguous/definitely-not-sent paths and a raw `Timeout::Error`; the latter emits no synthetic transport classification and is recovered via the pinned operation's status lookup.

## D-362 — process-local fence does not become durable cross-process ownership

Status: accepted after restart/configuration adjacency evidence.

Decision: the live money-moving fence is intentionally process-local. A fresh process must not inherit an invocation token; after restart, durable attempt phase, operation contract, ownership and provider availability remain the source of recovery truth. The product makes no distributed exactly-once claim before the authoritative deployment contract exists.

Evidence: durable crash, restart/recovery, configuration crash-consistency, coordinator-race and due-worker suites pass, including safe-release restart fallback, UNKNOWN pinned ownership, provider removal and stale-work cases.

## D-363 — bounded performance evidence closes without speculative optimization

Status: accepted after fresh exact-case and benchmark evidence.

Decision: retain the current canonical read paths, full durable facts and rebuildable derived projections. The fresh 10k lifecycle, degradation, bounded history and 1,000/5,000/12,500 read-path profiles are evidence for current behavior only; they do not establish a 100k production claim. No cache/index/refactor is justified without a reproducible case-relevant regression and before/after parity evidence.

Evidence: fresh exact-candidate measurements on CRuby 4.0.6 measured 10k lifecycle at 40.3602 s / 247.8 ops/s / 140,002 facts; 2,000-payout degradation at 2,247 attempts and 228 fallback recoveries; 500×4 history throughput at 315.3 ops/s. The 12,500-sample read-path profile measured analytics median/p95 0.000384/0.000539 s, typed analytics 0.000489/0.000519 s, explanation 0.000443/0.000618 s and due-work-empty 0.004463/0.005035 s. Fact-snapshot p95 variability (0.114104 s) was recorded rather than hidden by reruns. These are bounded measurements, not a 100k production claim.

## D-364 — authoritative ordering governs provider-health evidence

Status: accepted after deterministic skeptical reproduction and broad verification.

Decision: an observation rejected by an authoritative provider's ordering
contract must not alter provider health merely because it is a new durable
observation. A strictly newer sequenced observation may still provide health
evidence even when lifecycle cannot apply it because the operation was already
released. Transport classification remains admissible without a provider
sequence because it describes the initiating exchange rather than an ordered
provider event.

Rationale: lifecycle, quality and health are separate projections, but they
must not disagree about whether an explicitly stale provider event is current
operational evidence. Before this decision, a stale failure could degrade a
provider while leaving payout lifecycle unchanged, suppressing future traffic
through an ordering-invalid health side effect.

Implementation boundary: `ObservationLedger::Decision` owns the derived
`health_evidence?` classification and the observation ledger advances the
authoritative sequence cursor for every new sequenced observation, including a
late non-applying observation. The coordinator records health only when the
decision permits it, and durable restore/replay preserves and validates the
cursor. No generalized causal metadata or health-specific sequence store is
introduced.

The follow-up counterexample showed why the cursor cannot mean only the last
lifecycle-applying event: after late sequence 4 was accepted as health
evidence, sequence 3 was still treated as fresh because the payout had already
released ownership. The shared ordering cursor now tracks the greatest new
authoritative observation independent of lifecycle applicability.

For non-authoritative providers, the existing last-applied sequence remains a
compatibility projection. Restore therefore keeps that assignment for applied
observations while authoritative restore relies on the shared max-observed
cursor.

## D-365 — restore preserves provider-specific observation cursor semantics

Status: accepted after deterministic restore/replay and broad verification.

Decision: restoring a non-authoritative provider observation preserves the
existing last-applied sequence projection. Restoring an authoritative
observation preserves the greatest new sequence observed, including late
non-applying evidence. These are one ordering boundary with provider-specific
semantics, not an invented second health state.

## D-366 — exact observation duplicates retain their original decision

Status: accepted after deterministic skeptical reproduction and broad verification.

Decision: observation identity deduplication is checked before recomputing a
current authoritative lifecycle decision. The dedup record retains the
original applied/conflict/health-evidence result, so an exact durable duplicate
remains idempotent after later sequence advancement while a duplicate carrying
forged derived flags is rejected. This preserves one ordering boundary and
does not grant a duplicate new lifecycle or health effects.
