# ExecPlan — v0.3 Product Convergence & Full Routing Product

Status: VERSION_CANDIDATE

## Purpose / Big Picture

Turn the current RubyRouting repository from a strong but partially fragmented routing checkpoint into one coherent, nearly submission-ready payout-routing product before the official TZ appears.

The project already has valuable financial/lifecycle machinery. This plan does not restart it. It converges responsibilities, removes misleading experimental branches, completes missing generic product mechanics, proves restart safety, and builds application/demo surfaces only on top of stable core contracts.

## Global Goal

Deliver v0.3 Product Convergence & Full Routing Product by bringing the current `main` RubyRouting tree to a practically ready, coherent and deeply verified smart payout-routing product: one canonical routing pipeline, all case-relevant locally solvable mechanisms, and closure evidence for financial safety, allocation/admission correctness, provider recovery, restart-safe durability, analytics, application boundaries and reproducible concurrency/fault behavior.

The official TZ is not a stop condition. It will become v0.4 reconciliation.

## Governing sources

Read and obey:

- `AGENTS.md`
- `docs/ROADMAP.md`
- `docs/COMPLETION_POLICY.md`
- `specifications/004-product-convergence.md`
- inherited applicable SPEC-003/002/001 behavior
- `docs/CURRENT_ARCHITECTURE.md`
- `docs/RUBY.md`
- `docs/TESTING.md`
- `docs/BACKLOG.md`
- `docs/DECISIONS_CURRENT.md`.

## Current repository evidence

Recorded post-cleanup baseline: `1f3500ea1222abffd25224a6919cd8747a8f9064` on `main`, with a clean working tree before convergence edits.

Baseline evidence captured on 2026-08-28 (CRuby 4.0.6, YJIT disabled):

- `bundle check` passed;
- `bundle exec rake test` passed: 133 runs / 4,272 assertions;
- `bundle exec rake property` passed: 2 runs / 550 assertions;
- `bundle exec rake model` passed: 2 runs / 2,184 assertions;
- `bundle exec rake concurrency` passed: 11 runs / 942 assertions;
- `bundle exec rake fault` passed: 81 runs / 411 assertions;
- `bundle exec rake benchmark` passed: 20,000 allocation ops, 2,000 lifecycle ops and 250 replay cases.

This is local current evidence only; it is not a version-completion claim. The GitHub Actions workflow now runs the test/property/model/concurrency/fault tasks plus benchmark, load, degradation and demo smoke checks; it still has no result for the current uncommitted candidate.

## Progress

- `SLICE_VERIFIED` — clean post-cleanup baseline established on `main` at `1f3500e...` before current edits.
- `SLICE_VERIFIED` — `State::FactStore` extracted behind the coordinator mutex; focused and full local verification remain green.
- `SLICE_VERIFIED` — policy/allocation now separates per-payout `minimum_measures`/`maximum_measures` from exact `minimum_shares`/`maximum_shares`; allocation and analytics preserve typed corridor violations.
- `SLICE_VERIFIED` — operational admission now has an explicit time-window `ThroughputBudget`, atomic consumption facts and live/replay snapshots; throughput is not released with concurrent capacity.
- `SLICE_VERIFIED` — correctness-sensitive contention fuzz uses a fixed explicit seed and deterministic provider/gate rolls; failures report the seed and trace context.
- `SLICE_VERIFIED` — `ConstrainedOptimizer` is a separate deterministic stage that ranks only allocation-authority ties; allocation obligations cannot be traded for ranking metrics.
- `SLICE_VERIFIED` — policy windows now create explicit policy-epoch or functional opportunity-cohort allocation keys; allocation, analytics and replay preserve the same nested key.
- `SLICE_VERIFIED` — `FileJournal`/`FactCodec` and coordinator restoration preserve unresolved ownership, operation contracts, dedup/order, policy definitions, capacity/throughput/health state and safe post-restart dispatch/resolution paths; truncation/checksum corruption fails explicitly.
- `SLICE_VERIFIED` — `Application::Service` exposes separate commands and queries; the Rack-compatible `HttpApp` is a transport-only adapter with provider-specific webhook normalization and sanitized errors.
- `SLICE_VERIFIED` — explicit `Demo::ScriptedProvider`/`Demo::Scenario` exercises safe fallback through the same provider port and application service; it is clearly simulated.
- `SLICE_VERIFIED` — slow `QualityController` is separate from fast health, ignores pending/UNKNOWN and non-provider outcomes, and feeds confidence-aware ranking only inside allocation ties; live/replay/API query evidence exists.
- `SLICE_VERIFIED` — an independent seeded share-corridor property campaign now checks exact maximum/minimum violation precedence and post-decision choice across 300 generated states.
- `SLICE_VERIFIED` — static/runtime feasibility is typed and persisted, with static contradictions rejected at policy construction and runtime no-route causes exposed in decisions and analytics.
- `SLICE_VERIFIED` — quality evidence is partitioned by normalized context cohort with mature-global fallback; the constrained optimizer persists a per-candidate stage trace without widening the allocation authority.
- `SLICE_VERIFIED` — durable mutations append one journal batch; failure before durable visibility rebuilds working projections from accepted facts, while a complete post-append batch is reconciled instead of replaying fact identities.
- `SLICE_VERIFIED` — ambiguous partial/non-prefix journal append is now classified as durable corruption and poisons the journal; unchanged-prefix I/O failures remain retryable and complete visible batches remain reconciled.
- `SLICE_VERIFIED` — durable provider identities and timestamp fields are validated at restore, while live observations and coordinator clocks enforce canonical provider/time types before lifecycle facts are created.
- `SLICE_VERIFIED` — `PolicyRegistry` uses explicit registration order for active policy selection; opaque epochs are no longer compared lexicographically, and reactivation is deterministic.
- `SLICE_VERIFIED` — `FactCodec` rejects floating-point values on both encode and decode paths, including nested crafted durable payloads; exact Integer/Rational history cannot be bypassed through a damaged journal.
- `SLICE_VERIFIED` — `State::ProviderCatalogLedger` owns current opportunity identity and ordered registration/removal history, with a monotonic sequence guard; the coordinator remains the atomic fact-publishing facade.
- `SLICE_VERIFIED` — provider-catalog construction and restore now reject non-enumerable opportunity input with the same explicit `ArgumentError` contract as live replacement.
- `SLICE_VERIFIED` — `State::AdmissionLedger` now owns concurrent capacity and time-window throughput state behind the coordinator facade; live and restored projections use the same seam.
- `SLICE_VERIFIED` — `State::AllocationLedger` now owns keyed committed allocation snapshots and exact revision progression behind the same atomic facade.
- `SLICE_VERIFIED` — allocation deviations now carry explicit `none`/`recoverable`/`unavoidable` classification and analytics preserve it separately from causal reason; no catch-up behavior is enabled by this classification.
- `SLICE_VERIFIED` — working durable restore rejects mismatched ownership/operation/attempt/observation links, and application resume defers safely when the existing operation adapter is unavailable.
- `SLICE_VERIFIED` — durable restore now rejects unsupported lifecycle facts, semantically inconsistent final payout states, invalid provider-system facts, non-boolean runtime claims, unrelated economic conflicts and reversals without settled/conflicted linkage.
- `SLICE_VERIFIED` — provider-catalog replacement now records explicit removals, so a removed opportunity does not reappear after restart while historical admission reservations remain releasable.
- `SLICE_VERIFIED` — manual health signals now reject unknown current providers, while health/quality evidence emitted by a valid old operation remains restorable after catalog removal; durable validation requires registration before the signal fact.
- `SLICE_VERIFIED` — working restore replays provider catalog facts in sequence instead of preloading future registrations; provider-dependent durable facts now require the provider to be active before that fact, preventing order-forging through supplied runtime configuration.
- `SLICE_VERIFIED` — opportunity-evaluation facts now apply the same ordered provider-registration invariant as decisions, reservations and provider-system evidence; an evaluation cannot introduce an unregistered or already-removed provider into durable history.
- `SLICE_VERIFIED` — `State::LifecycleLedger` owns operation phase transitions and outcome reduction behind the coordinator atomic facade; focused reducer tests, restart tests and model histories preserve live/replay behavior.
- `SLICE_VERIFIED` — health recovery promotes `probing` to `healthy` only after the configured success evidence and all probe reservations are released; concurrent probes cannot trigger premature full exposure.
- `SLICE_VERIFIED` — a seeded six-scenario crash-boundary campaign proves fresh-process continuation or conservative preservation at assignment, possible provider acceptance, UNKNOWN, safe release, settlement and reconciliation-blocked boundaries.
- `SLICE_VERIFIED` — the deterministic scripted simulator now supports queued delayed callbacks, exact duplicate delivery, provider-sequence out-of-order delivery, status/idempotency paths and settlement reversal construction without adding a second provider contract.
- `SLICE_VERIFIED` — a fixed 1,000-payout history with periodic safe failures preserves settlement/allocation conservation, live-vs-replay analytics, lifecycle replay and fresh working restore equivalence.
- `SLICE_VERIFIED` — a deterministic 2,000-payout degradation harness measures bounded attempt amplification and ObjectSpace growth: 2,247 attempts (`2247/2000` per payout), 228 fallback payouts, 228 successful fallback recoveries, maximum 3 attempts/payout, 77,780,232-byte ObjectSpace delta and 801,976 live-slot delta on CRuby 4.0.6 in the latest sequential run (lifecycle 3.1300 s).
- `SLICE_VERIFIED` — a fixed-seed 96-history fault campaign exercises definitely-not-sent/ambiguous transport, pending, UNKNOWN, safe and temporary failures, terminal failure and success; unresolved paths resolve safely and final states remain owner-free.
- `SLICE_VERIFIED` — a fixed-seed long state-machine campaign drives 64 payout histories through repeated UNKNOWN/pending resolution, safe fallback, terminal failure and immediate success, then checks lifecycle/replay/fresh-restore parity.
- `SLICE_VERIFIED` — `State::ObservationLedger` now owns the shared live/restore observation identity, deduplication, provider-sequence ordering and late-success conflict classification; lifecycle transitions and fact publication remain behind the atomic coordinator facade.
- `SLICE_VERIFIED` — durable observation restore now rejects noncanonical IDs, non-boolean flags, invalid provider sequence/timestamp values and unsupported outcome/transport symbols before mutating working state.
- `SLICE_VERIFIED` — durable fact-source and batch append boundaries now reject non-enumerable inputs explicitly instead of leaking internal `NoMethodError` failures.
- `SLICE_VERIFIED` — durable observation restoration now obtains payout status from `LifecycleLedger.status_for`, so live and restore outcome reduction share one implementation.
- `SLICE_VERIFIED` — provider, capability, operation-contract and normalized-outcome Boolean inputs now reject truthy non-Boolean values; durable provider-definition corruption is covered by restore regression.
- `SLICE_VERIFIED` — the shared collection boundary consumes `#each` directly, so FactStore/codec/journal/catalog, demo and projection APIs accept valid each-only enumerables without leaking `.to_a` `NoMethodError` failures.
- `SLICE_VERIFIED` — analytics now distinguish distinct payouts receiving a fallback, successful fallback recovery and total recovery assignment operations (D-071), while preserving the economic role across idempotent resolution retries (D-072); failed-fallback and UNKNOWN→retry_same→success regressions pass live/replay equivalence.
- `SLICE_VERIFIED` — `FileJournal` validates JSON object roots before inspecting record kind, so array/scalar/null journal lines use the explicit durable-corruption contract (D-073).
- `SLICE_VERIFIED` — durable health-state transitions are linked to the preceding restored health signal; forged predecessor states, missing transition facts and interleaved transition records are rejected before a working coordinator is exposed (D-074).
- `SLICE_VERIFIED` — durable health probe reservations now reject duplicate or post-release reservation facts and require the restored operation to be committed and owner-free at reservation time (D-075).
- `SLICE_VERIFIED` — durable decision restore now validates policy binding, economic role/phase, assignment uniqueness, operation capability contract and control-plane decision uniqueness; forged resolution actions and duplicate assignment decisions are rejected (D-076).
- `SLICE_VERIFIED` — durable observation restore now recomputes `applied` and `conflict` from the restored operation state instead of trusting those persisted decision flags, preserving late-success conflict evidence (D-077).
- `SLICE_VERIFIED` — durable capacity and health release facts now require a terminal operation outcome, while capacity reservations remain valid only in their actual pre-decision or committed-assignment positions (D-078).
- `SLICE_VERIFIED` — durable throughput consumption now requires one committed, owner-free assignment with a pending dispatch; duplicate or post-release consumption cannot recreate rate exposure (D-079).
- `SLICE_VERIFIED` — durable allocation facts are unique per operation and causally ordered before dispatch; replay cannot increment the primary allocation ledger twice or recreate an allocation after release (D-080).
- `SLICE_VERIFIED` — settlement and economic-conflict facts are unique in working restore; duplicate settlement cannot rewrite a reversed payout and duplicate conflict evidence cannot inflate incident analytics (D-081/D-082).
- `SLICE_VERIFIED` — observation-derived health, quality and transport facts now carry canonical source payout/observation identity, validate the source observation and reject duplicate or pre-source derived records (D-083).
- `SLICE_VERIFIED` — a conflicting late observation now requires its matching `economic_conflict` fact in causal order; removing that fact while keeping `conflict:true` is rejected instead of silently losing the incident (D-084).
- `SLICE_VERIFIED` — assignment restore now requires the selected provider to belong to the preceding feasible cohort and checks the evaluation's durable provider, health and throughput traces (D-085).
- `SLICE_VERIFIED` — the atomic assignment bundle is complete on restore: allocation, ownership, required throughput and probing-health reservations cannot be silently omitted from an otherwise plausible pending payout (D-086).
- `SLICE_VERIFIED` — opportunity-evaluation restore now compares its allocation key, revision and measures with the exact allocation ledger snapshot at that fact boundary (D-087).
- `SLICE_VERIFIED` — opportunity-evaluation restore now requires each persisted admission capacity trace to match the exact `AdmissionLedger` snapshot at that fact boundary (D-088).
- `SLICE_VERIFIED` — durable health signals now carry explicit manual/observation provenance; erasing an observation source cannot be reinterpreted as a legal manual health event (D-089).
- `SLICE_VERIFIED` — allocation restore now requires every allocation fact to use the exact key from its preceding opportunity evaluation, preventing ledger writes under a forged cohort/window (D-090).
- `SLICE_VERIFIED` — provider registration restore now cross-checks duplicated capacity/throughput fields against the canonical provider definition, preventing replay/working admission divergence (D-091).
- `SLICE_VERIFIED` — explicit provider throughput gates now remain hard before optional rate-window logic, including providers without a configured budget (D-092).
- `SLICE_VERIFIED` — opportunity-evaluation restore now recomputes functional/operational eligibility and runtime feasibility from the restored intent, policy, catalog and admission/health projections at the historical evaluation timestamp (D-093).
- `SLICE_VERIFIED` — opportunity-evaluation restore now compares quality, ranking, health-policy, static-policy and previous-outcome traces with the typed state at the evaluation boundary (D-094).
- `SLICE_VERIFIED` — assignment-decision restore now recomputes the allocation and constrained-optimization trace from the preceding evaluation and rejects divergent selected-provider, discrepancy, candidate, runtime and soft-constraint evidence (D-095).
- `SLICE_VERIFIED` — allocation restore now cross-checks duplicated policy identity/epoch/scope/fingerprint and the capacity-reservation flag against the pinned policy and operation state (D-096).
- `SLICE_VERIFIED` — resolution-decision restore now recomputes recovery classification and rejects forged action, reason or reason-code evidence (D-097).
- `SLICE_VERIFIED` — non-operation decision restore now validates final/defer/no-route traces, switch-budget decisions and adapter-availability context instead of accepting an early no-operation return (D-098).
- `SLICE_VERIFIED` — assignment proposal construction is shared by live routing and restore validation, which now also rejects forged assignment reasons, reason codes, deviation cause and recoverability (D-099).
- `SLICE_VERIFIED` — durable restore now rejects duplicate intent/policy registrations and split policy static-feasibility evidence (D-100–D-102).
- `SLICE_VERIFIED` — provider registration and health-signal policy snapshots must match canonical controllers; provider interaction starts, probing reservations and ownership releases preserve exact causal operation evidence (D-103–D-107).
- `SLICE_VERIFIED` — durable operation contracts now match provider capabilities and pinned recovery overrides; provider interaction starts preserve the committed action; analytics is idempotent for exact duplicate observations (D-108–D-110).
- `SLICE_VERIFIED` — reconciliation-block restore now validates canonical expiry reason, exact elapsed time and actual TTL/deadline expiry evidence (D-111).
- `SLICE_VERIFIED` — durable policy restore now preserves global scope identity and rejects cross-payout redefinition of a policy scope (D-112).
- `SLICE_VERIFIED` — `PolicyRegistry` now uses the shared each-based collection boundary for initial policy sources, with an each-only regression (D-113).
- `SLICE_VERIFIED` — durable policy identity fields are now strict canonical Strings across registration, evaluation and allocation facts (D-114).
- `SLICE_VERIFIED` — durable operation, attempt, observation and reversal identities now remain strict canonical Strings across lifecycle, admission, settlement, conflict and derived facts (D-115).
- `SLICE_VERIFIED` — durable restore now rejects reuse of a money-moving `attempt_id` across assignments within one payout while preserving retry/resolution reuse of the existing attempt (D-116).
- `SLICE_VERIFIED` — available-provider filtering now consumes the shared each-based collection contract before routing and durable decision context (D-117).
- `SLICE_VERIFIED` — durable codec Hash decoding now rejects duplicate tagged entries instead of silently overwriting earlier values (D-118).
- `SLICE_VERIFIED` — durable allocation keys now require exact structural equality in both opportunity snapshots and committed allocation facts; restore no longer normalizes key segments with `.to_s` (D-119).
- `SLICE_VERIFIED` — durable fact decoding now requires canonical envelope type/fact/payout identity Strings and positive Integer sequence before constructing a `Fact` (D-120).
- `SLICE_VERIFIED` — live dispatch/resolution start commands now validate the commit's payout, operation/attempt/provider identity, action/role, phase/token, policy epoch and provider request before recording interaction facts; ordinary resolution and restart-resume paths also keep the live action index synchronized (D-121).
- `SLICE_VERIFIED` — public policy, provider-opportunity, eligibility, allocation, feasibility and quality collection inputs now consume the shared `#each` boundary instead of requiring `.map`, with direct each-only regressions (D-122).
- `SLICE_VERIFIED` — the orchestrator now handles only explicit `ProviderTransportError` values at the provider boundary; malformed observations and unclassified adapter/programming errors surface instead of becoming synthetic `UNKNOWN`, while a committed operation remains resumable (D-123).
- `SLICE_VERIFIED` — payout context labels now use the shared each-only collection boundary in policy and provider opportunity evaluation, while `PayoutIntent` materializes nested accepted collections for durable encoding; direct eligibility and journal-restore regressions pass (D-124).
- `SLICE_VERIFIED` — `Fact` now materializes nested each-only values before durable encoding, so accepted enumerable inputs cannot remain unencodable inside an in-memory fact; direct codec round-trip regression passes (D-125).
- `SLICE_VERIFIED` — provider-event reconciliation now canonicalizes the application-supplied provider identity before invoking the provider normalizer, preserving core linkage for whitespace-padded route identifiers; end-to-end regression passes (D-126).
- `SLICE_VERIFIED` — HTTP normalizer configuration and webhook lookup now use canonical provider IDs, reject empty/colliding normalized keys and preserve the provider-specific normalization boundary for padded route segments; HTTP regressions pass (D-127).
- `SLICE_VERIFIED` — reversal linkage now canonicalizes provider and operation identities before matching settlement/conflict state or checking idempotent repeats; padded-identity reversal and duplicate regressions pass (D-128).
- `SLICE_VERIFIED` — public live/replay payout lookup, policy/resume lookup and audit filtering now canonicalize payout identity consistently with `PayoutIntent`; padded payout query/history regressions pass (D-129).
- `SLICE_VERIFIED` — direct replay capacity and throughput provider snapshots now canonicalize provider identity consistently with application/provider queries; padded projection lookup regressions pass (D-130).
- `SLICE_VERIFIED` — public policy provider accessors now canonicalize provider IDs, and policy `weights_for`/`measure_exclusions` consume the shared each-only collection boundary; padded and each-only policy regressions pass (D-131).
- `SLICE_VERIFIED` — provider-keyed ranking, measure-limit and share-limit policy maps now reject collisions after ID canonicalization instead of silently overwriting configuration; collision regressions pass (D-132).
- `SLICE_VERIFIED` — authoritative allocation snapshots now canonicalize provider IDs for lookup/update and reject canonicalized-key collisions, preventing padded IDs from creating a second allocation bucket (D-133).
- `SLICE_VERIFIED` — provider quality snapshots now canonicalize provider IDs at construction and in batch lookup, preventing padded each-only inputs from creating divergent quality evidence keys (D-134).
- `SLICE_VERIFIED` — allocation decisions now canonicalize chosen/candidate provider identities across discrepancy, post-measure, share-violation and optimization-trace maps, reject canonicalized-key collisions and use canonical lookup for corridor checks (D-135).
- `SLICE_VERIFIED` — runtime feasibility now canonicalizes policy/eligibility/attempted provider IDs and measure-exclusion keys, preventing padded attempted IDs from re-entering recovery cohorts (D-136).
- `SLICE_VERIFIED` — the exact allocation chooser now canonicalizes padded each-only candidate and accounting provider IDs before intersecting them with policy weights, preventing a valid padded input from becoming a false no-route (D-137).
- `SLICE_VERIFIED` — the public decision engine now canonicalizes available and attempted provider IDs before adapter-availability and recovery-candidate checks, preserving safe resume/fallback behavior for padded each-only inputs (D-138).
- `SLICE_VERIFIED` — constrained optimization now canonicalizes provider keys in direct quality evidence maps and rejects canonicalized collisions before ranking, keeping quality selection aligned with the allocation candidates (D-139).
- `SLICE_VERIFIED` — authoritative allocation snapshots now reject empty provider identities at construction, lookup and commit boundaries, so blank keys cannot enter or address allocation state (D-140).
- `SLICE_VERIFIED` — direct quality evidence now requires typed `ProviderQualitySnapshot` values whose canonical provider identity matches the map key; sample counters and context labels are validated/canonicalized before optimization (D-141).
- `SLICE_VERIFIED` — admission ledgers and capacity/throughput projections now canonicalize provider identity, validate typed counters/budgets, and accept only `Time`-valued each-only throughput timestamps (D-142).
- `SLICE_VERIFIED` — attempt and payout snapshots now enforce canonical operation identity, typed outcomes/contracts/history, ownership linkage, projection counters/timestamps and unique operation history; decision proposals enforce canonical IDs, typed allocation evidence and action/role shape (D-143).
- `SLICE_VERIFIED` — replay capacity, throughput, allocation and lifecycle projections now canonicalize provider/operation identities in both fact application and public snapshot lookup, so equivalent padded identities cannot split replay state (D-144).
- `SLICE_VERIFIED` — analytics canonicalizes provider/operation identities across opportunity, allocation, attempts, observations, settlement, exclusions, targets and policy scopes, preserving one attribution bucket for equivalent fact identities (D-145).
- `SLICE_VERIFIED` — the extracted lifecycle ledger now canonicalizes operation/attempt/provider identities in phase-change values and operation lookup, rejecting blank IDs at that internal boundary (D-146).
- `SLICE_VERIFIED` — health admission now canonicalizes probe-owner identities, rejects blank health provider IDs and rejects truthy non-Boolean exposure flags before mutating probe state (D-147).
- `SLICE_VERIFIED` — policy registry fetch and intent resolution now canonicalize non-empty policy id/epoch/scope inputs, preventing padded public lookups from diverging from stored policy identity (D-148).
- `SLICE_VERIFIED` — HTTP application construction now rejects provider normalizers without an executable `#normalize` implementation, so a configured webhook boundary cannot remain unusable until its first event (D-149).
- `SLICE_VERIFIED` — `ProviderHealthSnapshot` now validates non-negative counter values, a positive probe limit and the `probe_in_flight <= probe_limit` invariant before exposing health admission state (D-150).
- `SLICE_VERIFIED` — direct `RuntimeFeasibility` construction now consumes the shared each-only reason-code boundary, keeping public construction consistent with `assess` and the other routing inputs (D-151).
- `SLICE_VERIFIED` — `StaticPolicyInfeasibilityError` now consumes the shared each-only reason-code boundary, keeping policy error metadata consistent with the public domain collection contract (D-152).
- `SLICE_VERIFIED` — analytics opportunity/reason-code reductions now consume the shared each-only collection boundary instead of `Array(...)`; scalar fact collections are rejected rather than converted into misleading provider metrics (D-153).
- `SLICE_VERIFIED` — durable health-probe reservation restore now validates `attempt_id` as a canonical identity instead of coercing arbitrary values with `.to_s` (D-154).
- `SLICE_VERIFIED` — normalized observations now enforce the safety relation between transport classification and lifecycle outcome: ambiguous transport cannot claim safe release, and definitely-not-sent transport cannot settle (D-155).
- `SLICE_VERIFIED` — recovery operation budgets now have an explicit end-to-end regression proving that safe release cannot create a new money-moving assignment after `max_operations` is exhausted (D-156).
- `SLICE_VERIFIED` — an unobservable journal append failure now fails closed and poisons the `FactStore`, preventing later fact-identity reuse when durable visibility cannot be established (D-157).
- `SLICE_VERIFIED` — definitely-not-sent transport observations now accept only lifecycle-terminal/releasable normalized statuses, rejecting unresolved `pending`/`unknown` claims that would otherwise diverge from live recovery and durable restore (D-158).
- `SLICE_VERIFIED` — the durable `Coordinator` now rejects write-only journals, requiring a read-back fact view before it exposes restart-safe persistence (D-159).
- `SLICE_VERIFIED` — journal poison-hook failures no longer mask the primary durable-corruption error; the `FactStore` remains unusable and exposes the explicit fail-closed contract (D-160).
- `SLICE_VERIFIED` — invalid provider transport kinds now fail as explicit `ArgumentError` values across transport results, transport errors and normalized observations, rather than leaking `NoMethodError` (D-161).
- `SLICE_VERIFIED` — health state/signal/attribution and quality evidence-scope enums now reject non-symbol-like values with explicit `ArgumentError` at their public typed boundaries (D-162).
- `SLICE_VERIFIED` — policy and provider functional eligibility now trim payout context labels before comparing them with canonical configured labels, with a direct eligibility regression for padded input (D-163).
- `SLICE_VERIFIED` — static policy feasibility now intersects target providers with hard allow/exclude constraints and persists typed feasibility evidence; adapter availability remains an operational admission fact, so unavailable providers stay in the functional cohort while being excluded from the current decision (D-164).
- `SLICE_VERIFIED` — application resume expires unresolved operations before rebuilding a dispatch proposal or deferring for a missing adapter, so restart/resume cannot bypass TTL or deadline evidence (D-165).
- `SLICE_VERIFIED` — closed enum and Hash-key boundaries replace arbitrary durable/external symbolization, recursively reject nested floating-point values, and preserve nested fact immutability without interning attacker-controlled names (D-166).
- `SLICE_VERIFIED` — elapsed-time decisions use exact monotonic values, the default system clock supplies a restore translation for legacy wall timestamps, and monotonic anchors are persisted with relevant lifecycle/admission facts (D-167).
- `SLICE_VERIFIED` — the direct reconciliation command is explicitly typed as normalized-evidence ingress; raw provider payloads must cross the provider-specific normalizer before entering the core reducer (D-168).
- `SLICE_VERIFIED` — durable restore identity paths reject noncanonical provider/operation values instead of coercing them, keeping replay and working-state identity boundaries aligned (D-169).
- `SLICE_VERIFIED` — the high-contention concurrency harness now captures a per-payout execution trace and includes it with the fixed seed for invariant assertions and worker exceptions, making scheduler-dependent failures diagnosable without retries (D-170).
- `SLICE_VERIFIED` — legacy replay allocation facts without an explicit key now consume `policy_scope` through the shared each-only collection boundary and reject scalar wrapping, preserving replay/live key shape (D-171).
- `SLICE_VERIFIED` — replay and analytics identity normalization now rejects numeric/arbitrary payload values before coercion while retaining padded String/Symbol lookup compatibility, keeping durable projections aligned with working restore (D-172).
- `SLICE_VERIFIED` — replay lifecycle, health and quality fact ingress now applies the same strict identity boundary to provider/operation/attempt/observation/reversal/contract IDs and quality context labels, including projection lookup through policy-like objects (D-173).
- `SLICE_VERIFIED` — admission restore and supplied evaluation anchors now reject inexact Float monotonic values, including direct `capacity_trace` input; exact Integer/Rational elapsed-time semantics are enforced at the ledger boundary (D-174).
- `SLICE_VERIFIED` — `FactCodec` now rejects unknown or missing fields in fact/batch envelopes and every tagged nested value, preventing a checksummed durable record from silently dropping unsupported data (D-175).
- `SLICE_VERIFIED` — static policy feasibility now checks share obligations after hard allow/exclude constraints, including minimum shares on ineligible targets and effective maximum capacity (D-176).
- `SLICE_VERIFIED` — stable application reconciliation requires an executable provider-specific normalizer and no longer accepts a generic caller-constructed observation; deferred no-route decisions now persist causal deviation/recoverability and analytics records them (D-177).
- `SLICE_VERIFIED` — fact-producing assignment, retry/resolve, phase-transition and ownership-release side effects now live in `State::OperationCommitter`, with explicit ledger/controller dependencies and unchanged atomic coordinator/provider boundaries (D-178).
- `SLICE_VERIFIED` — fact-free opportunity, admission, eligibility, allocation and constrained-decision assembly now lives in `Routing::DecisionEvaluator`; durable restore and fact publication remain outside that seam (D-179).
- `SLICE_VERIFIED` — ordered durable-prefix replay, supplied runtime-catalog validation and the reducer corruption boundary now live in `State::WorkingStateRestorer`; fact reducers remain behind the coordinator atomic facade (D-180).
- `SLICE_VERIFIED` — provider-definition/runtime durable facts now replay through `State::ProviderCatalogRestorer`, with catalog, admission and quality dependencies supplied by the coordinator and direct contract coverage (D-181).
- `SLICE_VERIFIED` — capacity reservation/release and throughput-consumption durable facts now replay through `State::AdmissionFactRestorer`, preserving exact money/time and operation-linkage checks through coordinator callbacks (D-182).
- `SLICE_VERIFIED` — ownership, attempt-start, reconciliation-block and health-exposure durable facts now replay through `State::OperationFactRestorer`, preserving operation/phase/ownership and probe-order checks through coordinator callbacks (D-186).
- `SLICE_VERIFIED` — provider-derived transport, health, quality and health-transition facts now replay through `State::ProviderEvidenceFactRestorer`, preserving observation provenance and transition ordering through coordinator callbacks (D-187).
- `SLICE_VERIFIED` — late-success conflict and settlement-reversal facts now replay through `State::FinancialFactRestorer`, preserving source linkage and reversal bounds behind the coordinator facade (D-188).
- `SLICE_VERIFIED` — intent and policy durable registration facts now replay through `State::PayoutFactRestorer`, preserving exact creation anchors, policy fingerprints and static-feasibility bindings (D-189).
- `SLICE_VERIFIED` — historical opportunity-evaluation facts now replay through `State::OpportunityEvaluationFactRestorer`, recomputing catalog/admission/allocation/health/quality eligibility before recording the validated trace (D-190).
- `SLICE_VERIFIED` — assignment/retry/resolve durable decisions now replay through `State::DecisionFactRestorer`, with cross-projection decision validators injected from the atomic coordinator facade (D-191).
- `SLICE_VERIFIED` — final restored-state ownership/phase/outcome/reservation and release-order invariants now live in `State::RestoredStateValidator`, behind dynamic working-state references (D-192).
- `SLICE_VERIFIED` — policy/allocation/admission/operation cross-fact decision trace validation now lives in `State::DecisionTraceValidator`; `DecisionFactRestorer` remains an application seam (D-193).
- `SLICE_VERIFIED` — restart-generated resolution/retry decisions now carry an explicitly validated `restart_recovery` trace and can themselves be restored before the next provider call, closing a repeated-restart durability gap (D-194).
- `SLICE_VERIFIED` — valid partial settlement reversals now survive a fresh `FileJournal` working restore with settlement linkage, reversal order/amount conservation, analytics parity and exact duplicate idempotency (D-195).
- `SLICE_VERIFIED` — committed throughput reservations now remain in live payout state with the same provider and exact time anchors as the durable consumption fact; live and restored admission working projections are aligned (D-196).
- `SLICE_VERIFIED` — application analytics now uses the coordinator clock for unresolved age by default and HTTP supports an explicit ISO-8601 `as_of` boundary (D-197).
- `SLICE_VERIFIED` — HTTP method/path/query/body inputs are bounded before parsing, with sanitized 413 responses for oversized input (D-198).
- `SLICE_VERIFIED` — the seeded high-contention fuzz harness now starts workers through a shared barrier, preserving seed/trace diagnostics while making concurrent pressure explicit (D-199).
- `SLICE_VERIFIED` — the baseline benchmark now measures the public `Application::Service` path separately over 2,000 operations, closing the application-throughput evidence gap without changing routing semantics (D-200).
- `SLICE_VERIFIED` — the HTTP audit route now returns bounded pages with strict `limit`/`offset` validation and an explicit continuation marker, preventing silent truncation or an unbounded journal response (D-201).
- `SLICE_VERIFIED` — a restart regression now crosses an actual separate Ruby process: the child restores durable provider/policy state without runtime catalog input and safely continues the committed owner through the public `Application::Service` on the same operation (D-202).
- `SLICE_VERIFIED` — durable replay now rejects an applied pending/unknown observation without its matching lifecycle phase transition, both for initial dispatch and for a response arriving after a resolution decision, preventing a damaged in-flight attempt from suppressing restart recovery (D-203).
- `SLICE_VERIFIED` — non-operation defer decisions with no economic owner now expose `:deferred` in live state, durable restore and analytics, while owner-held defer remains unresolved (D-204).
- `SLICE_VERIFIED` — durable decision-role validation now distinguishes ownerless recovery defer from owner-held resolution defer, and all production defer branches emit the matching role (D-205).
- `SLICE_VERIFIED` — `DecisionProposal` now enforces the non-operation identifier and action/role shape for defer, terminal and already-final control decisions, with direct domain regressions (D-206).

Historical working evidence after D-163 (2026-08-30, local CRuby 4.0.6, YJIT disabled):

- `bundle check` passed;
- `bundle exec rake test` passed: 385 runs / 8,920 assertions (Minitest seed `5479`); `property` passed: 4 runs / 1,210 assertions (seed `37129`); `model` passed: 3 runs / 2,941 assertions (seed `46360`); `concurrency` passed: 12 runs / 944 assertions (seed `481`); `fault` passed: 225 runs / 3,252 assertions (seed `36248`); all had zero failures/errors;
- `bundle exec rake benchmark` passed: 20,000 allocation ops in 1.4938 s / 13,388.7 ops/s, 2,000 lifecycle ops in 2.9553 s / 676.8 ops/s, 250 replay cases in 20.6899 s / 12.1 ops/s and 28,003 replayed facts;
- `bundle exec rake load_10k` passed: 10,000 coordinator lifecycle ops, 18.1539 s / 550.8 ops/s, 140,002 facts;
- `bundle exec rake degradation_metrics` passed: seed `20260829`, 2,000 payouts with 2,247 attempts, 228 fallback payouts, 228 successful fallback recoveries, 3-attempt maximum, 73,903,544-byte ObjectSpace delta and 720,284 live-slot delta (lifecycle 3.1008 s).
- `ruby -Ilib bin/ruby_routing_demo` passed with simulated-primary safe failure and simulated-recovery settlement.
- Additional closure checks passed: Ruby syntax for 95 files, `git diff --check`, and reachable production scans for stale TODO/FIXME/XXX, Float financial arithmetic, unsafe wall-clock/randomness and unclassified exception swallowing.
- Generated-run reproduction metadata: Minitest seeds `test=5479`, `property=37129`, `model=46360`, `concurrency=481`, `fault=36248`; degradation seed `20260829`.

These are current local working-tree results, not CI or version-completion evidence.

Historical working evidence after D-169 (2026-08-30, local CRuby 4.0.6, YJIT disabled):

- `bundle check` passed;
- `bundle exec rake test` passed: 392 runs / 8,946 assertions (Minitest seed `35139`);
- `bundle exec rake property` passed: 4 runs / 1,210 assertions (seed `39447`);
- `bundle exec rake model` passed: 3 runs / 2,941 assertions (seed `9312`);
- `bundle exec rake concurrency` passed: 12 runs / 944 assertions (seed `27844`);
- `bundle exec rake fault` passed: 229 runs / 3,273 assertions (seed `14573`);
- `bundle exec rake benchmark` passed: 20,000 allocation ops in 1.3456 s / 14,862.9 ops/s, 2,000 lifecycle ops in 3.0721 s / 651.0 ops/s, 250 replay cases in 18.2894 s / 13.7 ops/s and 28,003 replayed facts;
- `bundle exec rake load_10k` passed: 10,000 coordinator lifecycle ops in 15.9610 s / 626.5 ops/s and 140,002 facts;
- `bundle exec rake degradation_metrics` passed: seed `20260829`, 2,000 payouts, 2,247 attempts, 228 fallback payouts, 228 successful fallback recoveries, maximum 3 attempts/payout, 77,777,424-byte ObjectSpace delta and 801,946 live-slot delta;
- `ruby -Ilib bin/ruby_routing_demo` passed through simulated-primary safe failure and simulated-recovery settlement;
- syntax passed for 96 Ruby files and `git diff --check` passed;
- all commands above completed with zero failures, errors and skips. These measurements are bounded local evidence and do not constitute a 100k benchmark or version-completion claim.

These are historical local working-tree results before D-170, not CI or version-completion evidence.

Current working evidence after D-206 (2026-08-30, local CRuby 4.0.6, YJIT disabled):

- `bundle check` passed;
- `bundle exec rake test` passed: 455 runs / 9,219 assertions (Minitest seed `53445`);
- `bundle exec rake property` passed: 4 runs / 1,210 assertions (seed `51414`);
- `bundle exec rake model` passed: 3 runs / 2,941 assertions (seed `33545`);
- `bundle exec rake concurrency` passed: 12 runs / 946 assertions (seed `14725`);
- `bundle exec rake fault` passed: 240 runs / 3,352 assertions (seed `56648`);
- A later test-only rerun on 2026-08-31 also passed: 455 runs / 9,214
  assertions (Minitest seed `31797`); the assertion total may vary with the
  scheduler-sensitive contention scenarios, while failures/errors/skips remain
  zero;
- `bundle exec rake benchmark` passed: 20,000 allocation ops in 1.9555 s / 10,227.4 ops/s, 2,000 lifecycle ops in 3.9184 s / 510.4 ops/s, 2,000 application-service ops in 3.7448 s / 534.1 ops/s, 250 replay cases in 23.6881 s / 10.6 ops/s and 28,003 replayed facts;
- `bundle exec rake load_10k` passed: 10,000 coordinator lifecycle ops in 22.6157 s / 442.2 ops/s and 140,002 facts;
- `bundle exec rake degradation_metrics` passed: seed `20260829`, 2,000 payouts with 2,247 attempts, 228 fallback payouts, 228 successful fallback recoveries, maximum 3 attempts/payout, 78,420,392-byte ObjectSpace delta and 805,980 live-slot delta (lifecycle 4.4953 s);
- `ruby -Ilib bin/ruby_routing_demo` passed through simulated-primary safe failure and simulated-recovery settlement;
- current syntax scan passed for 126 Ruby files, the root require graph reaches all 55 production Ruby files, and `git diff --check` passed (only Git's LF/CRLF conversion warnings). `State::Coordinator` is 1,929 lines after the durable-reducer and validator extractions.

All current commands above completed with zero failures, errors and skips. D-170
changes only test diagnostics, D-171 changes only replay collection handling,
D-172/D-173 harden projection identity boundaries, D-174/D-175 close exact
monotonic and closed durable-schema boundaries, D-176/D-177 align static
share feasibility, application normalization and no-route analytics with the
canonical contracts, D-178 extracts operation-commit side effects, D-179
extracts fact-free decision evaluation, D-180 extracts ordered durable-restore
orchestration, D-181 extracts provider catalog fact replay, D-182 extracts
admission fact replay, D-186 extracts operation-fact replay, D-187 extracts
provider-evidence replay, D-188 extracts financial replay, D-189 extracts
payout registration replay, D-190 extracts opportunity-evaluation replay and
D-191 extracts decision replay, D-192 extracts final restored-state validation,
D-193 extracts decision-trace validation, and D-194 validates restart-generated
resolution/retry decisions across a further fresh-process boundary. D-195 adds
fresh-process partial-reversal continuation; D-196–D-198 add live/restored
throughput parity, current unresolved-age analytics and bounded HTTP input;
D-199 adds a controlled worker start barrier to the seeded contention harness;
D-200 adds the public application-service throughput measurement.
D-201 bounds HTTP audit responses with explicit pagination and strict query
validation. D-202 adds an actual separate-process durable continuation
regression through the public application facade, beyond same-process
coordinator reconstruction. D-203 adds durable replay invariants that reject
an applied pending/unknown outcome when its corresponding lifecycle phase
transition is missing, both for initial dispatch and for a response arriving
after a resolution decision. Without the checks, replay could preserve an
incorrect dispatching/resolving phase and suppress restart recovery. D-204
gives ownerless defer a durable `:deferred` state while preserving owner-held
unresolved states; D-205 aligns its state-dependent decision role; D-206 makes
the same action/role/identifier shape fail fast in `DecisionProposal`.
The per-payout trace remains attached to assertion failures and worker exceptions,
and scheduler-dependent execution remains
observable rather than retried or declared deterministic. These are current
local working-tree results, not CI or version-completion evidence.

## Fresh closure/red-team attempt — 2026-08-30 (after D-206)

Status: `VERSION_CANDIDATE`.

The closure protocol was rerun from the current working tree after D-206. It
found no material locally-solvable product or correctness gap:

- Pass A — current production code was reconciled against SPEC-004 and the
  applicable inherited SPEC-003/002/001 requirements. Allocation, admission,
  optimization, recovery, normalization, durability, analytics and application
  boundary mechanisms are implemented or explicitly provisional/configurable;
  no required local behavior was found missing.
- Pass B — the canonical flow has one reachable production path. The root
  require graph reaches all 55 production Ruby files; focused ledgers/restorers
  are behind the coordinator's one atomic facade, and demo/provider code is
  explicitly simulated and outside generic provider semantics. No dead
  reachable experimental route or alternate routing algorithm was found.
- Pass C — red-team scenarios cover duplicate submit, UNKNOWN ownership,
  stale commit, attempted-provider exclusion, late success/conflict,
  disablement, TTL expiry, policy changes, settlement, reversal and durable
  crash boundaries. D-203 closes the missing in-flight phase/outcome invariant;
  D-204–D-206 close deferred-state, role and control-proposal shape gaps.
- Pass D — exact money/allocation, indivisible amounts, opportunity-aware
  denominator, policy epochs/windows, deviation attribution, concurrent
  reservations, rate versus exposure, health/probing and static/runtime
  infeasibility are covered by scenarios and independent property/oracle/model
  evidence. Historical catch-up remains explicitly disabled by D-059.
- Pass E — optimization runs only after safety, hard eligibility, operational
  admission and allocation admissibility; pending/UNKNOWN is not collapsed into
  arbitrary failure and no weighted score owns correctness.
- Pass F — fresh-process continuation, operation identity/phase/contract,
  policy binding, dedup/order state, reservations, settlement/reconciliation,
  truncation and semantic corruption are covered. Replay projections are not
  used as a substitute for working restart recovery.
- Pass G — provider normalizers own raw status/economic mapping; raw callbacks
  cannot forge safe release; HTTP input/errors are bounded and sanitized; the
  application surface delegates to commands/queries and the demo identifies
  its provider as simulated.
- Pass H — repository scans found no TODO/FIXME/XXX in production or benchmark
  paths, no unapproved wall-clock/randomness/sleep in correctness paths, no
  financial Float use, no silent broad exception path and no unsupported scale
  claim. All generated/fault cases retain seeds and traces.
- Pass I — the current local matrix is green on CRuby 4.0.6 with exact seeds
  recorded above; syntax, dependency, root-load and diff checks also pass. The
  workflow in `.github/workflows/ruby.yml` was inspected, but GitHub Actions
  has not run this uncommitted candidate revision.
- Pass J — benchmark, 10k load, degradation/memory and demo evidence are
  reproducible bounded measurements. No 100k claim is made.
- Pass K — NOW/P0/P1 mechanics are implemented and audited. Remaining exact
  revision CI is an external execution gate; missing official-TZ values are
  documented as provisional reconciliation questions, not used to hide local
  work.
- Pass L — README, governing specs, roadmap, completion policy, architecture,
  Ruby/testing/workflow/plans/session policy, backlog, decisions and this
  ExecPlan now describe the same v0.3 goal and stop rules.

Result: the local candidate has no newly discovered material gap, but it is not
`VERSION_COMPLETE`. Exact-revision CI evidence is still unavailable because
the candidate remains an uncommitted working tree and this session has no
authorization to create a commit or push it. The plan therefore remains at
`VERSION_CANDIDATE`; the next required action is to run CI on the exact
candidate revision after commit authorization, then repeat only the affected
closure evidence before deciding completion.

## Superseded closure attempt — 2026-08-30 (after D-202)

This closure attempt is superseded by the D-203 durable replay finding and is
retained only as historical evidence of the pre-D-203 checks.

The fresh A–L closure protocol was rerun against the exact current working tree
after D-202:

- Pass A — source/spec reconciliation through SPEC-004 and applicable
  SPEC-003/002/001 behavior found no unresolved material behavioral
  requirement. The skeptical review's material gaps are closed for static share
  feasibility after hard constraints, strict monotonic ledger boundaries,
  closed durable schemas, provider-normalized application reconciliation and
  no-route deviation analytics and bounded audit pagination. D-178 through
  D-201 materially advance P0-003
  by extracting operation side effects, fact-free decision evaluation, ordered
  durable-restore orchestration, provider catalog fact replay, admission fact
  replay, operation-fact replay, provider-evidence replay, financial replay,
  payout registration replay, opportunity-evaluation replay, decision replay,
  final restored-state validation and decision-trace validation. D-194 closes
  the repeated-restart control-plane decision gap; D-195 closes fresh-process
  partial-reversal continuation; D-196–D-198 close live/restored throughput
  parity, current unresolved-age analytics and bounded HTTP input; D-199
  strengthens the seeded contention harness with a controlled worker start; D-200
  adds direct public application-service throughput evidence; D-201 bounds the
  HTTP audit response path with explicit pagination and strict query validation;
  D-202 adds actual separate-process restart evidence for durable continuation
  through the public application facade and a parent-side journal reopen.
  The pre-D-203 conclusion that no material source/spec gap remained is
  superseded by the reopened finding below.
- Pass B — the root require graph reaches all 54 required production modules
  plus the `lib/ruby_routing.rb` entrypoint (55 `lib` Ruby files total). The
  canonical coordinator remains the one atomic facade; catalog, admission,
  allocation, lifecycle, operation-commit, observation, fact-store, clock and
  projection seams are integrated into the flow. `RestoredStateValidator` owns
  the final durable-state boundary and `DecisionTraceValidator` owns the
  cross-fact decision proof; the coordinator remains the single atomic facade.
  No deleted experimental
  production path was restored; the simulator/demo remains explicitly named
  and bounded.
- Pass C — financial red-team coverage includes duplicate submit/observation,
  stale commit races, UNKNOWN and ambiguous transport, safe fallback,
  already-attempted-provider exclusion, late success/conflict, disablement with
  unresolved ownership, TTL/idempotency boundaries, in-flight policy binding,
  settlement and reversal histories. D-195 adds a valid fresh-process chain
  with two partial reversals and a repeated reversal command after restore. D-196
  also verifies that live throughput reservations have the same operation-linked
  provider/time anchors as restored state. D-202 additionally exercises an
  actual child Ruby process with no runtime opportunity/policy catalog input,
  continuing through the public application facade; the parent reopens the
  journal and verifies the persisted terminal attempt;
  full, model, race, fault and restart suites remain green.
- Pass D — exact money and allocation obligations remain separate from
  availability, capacity, throughput, health/quarantine/probing and static or
  runtime infeasibility. Functional denominators preserve unavailable adapters;
  current decisions exclude them operationally. D-196 keeps the live throughput
  reservation projection equal to the durable admission fact. No catch-up/debt
  semantics were invented beyond the accepted current decision.
- Pass E — constrained optimization is a later deterministic stage over the
  allocation-admitted candidate/tie set. It cannot resurrect hard exclusions,
  exceed admission, bypass allocation corridors or treat pending/UNKNOWN as a
  safe failure; no arbitrary weighted score is the correctness policy.
- Pass F — FileJournal/FactCodec/FactStore and working restore preserve
  ownership, operation phase/contract/idempotency, policy binding,
  allocation/admission reservations, dedup/order, settlement and reconciliation
  state. Settlement remains distinct from post-settlement reversal: D-195
  verifies two partial reversal facts restore in order and an exact repeated
  reversal does not append a third fact. Truncation, checksum, semantic, identity, enum/key and nested Float
  corruption fail explicitly; D-175 also rejects unknown envelope and tagged
  value fields instead of silently dropping them. Monotonic anchors drive
  elapsed correctness and ledger boundaries reject Float anchors; wall
  timestamps are audit/legacy-restore evidence only. `WorkingStateRestorer`
  owns ordered replay, supplied-catalog validation and reducer error
  classification; `ProviderCatalogRestorer` owns provider definition/runtime
  fact replay; `AdmissionFactRestorer` owns capacity and throughput fact replay;
  `OperationFactRestorer` owns operation continuation replay;
  `ProviderEvidenceFactRestorer` owns provider evidence replay;
  `FinancialFactRestorer` owns conflict/reversal replay;
  `PayoutFactRestorer` owns intent/policy replay;
  `OpportunityEvaluationFactRestorer` owns evaluation replay;
  `DecisionFactRestorer` owns decision replay; `RestoredStateValidator` owns
  final restored-state checks; `DecisionTraceValidator` owns cross-fact decision
  validation. Restart-generated `restart_recovery` resolution/retry decisions
  are validated and restored across a further fresh-process boundary, without
  creating a new money-moving attempt. D-195 verifies ordered partial reversal
  continuation after a fresh restore; D-196 verifies live/restored throughput
  reservation parity. D-202 adds an actual separate-process owner continuation
  regression with durable provider/policy restoration through the public
  application facade. The coordinator remains
  the atomic facade and supplies
  dynamic state references.
- Pass G — raw provider events cross provider-specific normalizers; the direct
  application reconciliation command requires provider identity, raw event
  data and an executable provider-specific normalizer, so callers cannot hand
  the core a forged `ProviderObservation`. HTTP remains transport-only with
  sanitized errors, bounded method/path/query/body inputs, bounded audit pages
  and explicit pagination metadata, and the demo provider is explicitly
  simulated while satisfying the canonical provider port. D-197 exposes the
  coordinator-clock age boundary and explicit HTTP `as_of` override; D-201
  prevents an unbounded journal response.
- Pass H — reachable-source scans found no production `to_sym`,
  `transform_keys` or permissive `Array(...)` collection coercion, stale
  TODO/FIXME/XXX, unsafe correctness wall-clock/randomness use or Float
  financial arithmetic. Projection identity boundaries reject numeric/arbitrary
  payload values before coercion. Remaining broad rescues are classified durable append
  ambiguity/rollback and HTTP sanitization; HTTP input bounds are covered by
  D-198; abstract provider
  `NotImplementedError` guards are intentional.
- Pass I — the current local verification and performance matrix is recorded
  above on this tree. Exact-revision CI is not available for the uncommitted
  candidate, so local results are not promoted to CI evidence.
- Pass J — executed scales are 2,000 degradation payouts, 10,000 lifecycle
  operations, 20,000 allocation operations, 2,000 application-service
  operations and 250 replay cases. Measurements
  are reproducible bounded evidence; no 100k-scale claim is made.
- Pass K — case-relevant NOW/P0/P1 mechanisms are implemented or evidenced,
  with the main cross-fact validation seams extracted into focused validators.
  Exact-revision CI and final version decision are required closure gates, not
  a reason to label the candidate complete; the absent official TZ remains
  future reconciliation, not a blocker. D-196–D-200 are covered by focused
  admission, analytics, HTTP and concurrency regressions plus the application
  benchmark path. D-201 also bounds the HTTP audit response path with explicit
  pagination rather than silently truncating durable facts. D-202 adds a
  separate-process continuation regression through the public application
  facade, followed by a parent-side journal reopen.
- Pass L — README/ROADMAP, active ExecPlan, BACKLOG, CURRENT_ARCHITECTURE,
  TESTING, WORKFLOW, current decisions and the governing specs retain the same
  v0.3 goal, candidate state and no-premature-completion rules. Historical
  evidence is labeled as historical/superseded, and current D-196–D-203 evidence
  is recorded above.

The candidate remains `VERSION_CANDIDATE`. D-174–D-203 closed material local
correctness/boundary gaps and extracted the durable-state and decision-trace
cross-fact seams. Exact-revision CI evidence plus the final completion decision
are still absent because the working tree is uncommitted. The D-203 finding
reopens the full A–L closure protocol; no commit or push was performed.

## Reopened closure state — 2026-08-30 (after D-203)

The prior D-202 closure attempt is superseded by a fresh durable-state
red-team finding. Removing the durable `dispatching -> unknown` phase fact
while retaining the applied `provider_observed` fact was accepted by replay,
leaving an `unknown` payout with a `dispatching` attempt. A restarted
coordinator would therefore classify the operation as dispatch-in-progress and
defer instead of reaching the provider-resolution path.

D-203 makes `RestoredStateValidator` cross-check in-flight attempt phase,
latest operation action and outcome. It preserves valid initial/restarted
dispatch, resolution and idempotent-retry states, while rejecting the damaged
history with `DurableCorruptionError`. The focused restart suite and the broad
test/property/model/concurrency/fault matrix pass on the corrected tree. The
full A–L closure protocol must be rerun after this finding, and exact-revision
CI remains unavailable while the working tree is uncommitted.

## Reopened implementation state — 2026-08-30 (after D-203)

The D-203 closure rerun found a separate state-contract gap. `PayoutSnapshot`
already admitted `:deferred`, but a safe no-route or exhausted-budget decision
left live and replayed payouts at `:new` or the previous releasable failure
status. This made the application state less informative and left a valid
no-route history unable to pass working restore: no-route decisions used role
`:recovery`, while the durable validator treated every non-operation defer as
`:resolution`.

D-204 now sets `:deferred` only for a non-operation defer with no ownership and
projects a current `deferred_count`; D-205 makes the role contract explicit
(`:recovery` without an owner, `:resolution` while an owner is retained) and
normalizes budget-defer branches accordingly. Focused and full regression
tests pass on the corrected tree. The candidate is active again until a fresh
A–L closure pass, current evidence run and skeptical review are complete.

## Superseded closure attempt — 2026-08-30 (after D-169)

The previous closure was invalidated by the D-164–D-169 implementation findings.
The fresh protocol currently records:

- Pass A — the current code was checked against SPEC-004 and inherited
  SPEC-003/002/001 requirements; the new checks close static-feasibility,
  functional-cohort/operational-availability, resume-expiry, typed evidence,
  monotonic elapsed-time and durable-identity gaps.
- Pass B — the root require graph contains 38 production Ruby files. The
  coordinator remains the atomic facade while catalog, admission, allocation,
  lifecycle, observation, fact-store and projection responsibilities stay on
  focused seams; no deleted experimental production path was restored.
- Passes C–E — exact-money/allocation, admission ordering and constrained
  optimization remain protected by the full suite, independent property/model
  oracles, controlled races and seeded fault histories. Adapter availability is
  not allowed to change the functional allocation denominator, and optimization
  still ranks only actions admitted by higher-priority layers.
- Pass F — durable decoding and working restore now use closed enum/key and
  canonical identity boundaries, reject nested floating-point or malformed
  values, and preserve monotonic elapsed-time evidence without trusting wall
  clock differences for correctness decisions.
- Pass G — raw provider events still enter through provider-specific
  normalization; the typed reconciliation command rejects raw hashes, HTTP
  remains transport-only, and resume defers safely when its existing adapter is
  unavailable after expiry processing.
- Pass H — the targeted source audit found no production `to_sym` or
  `transform_keys` coercion path remaining; broader TODO/exception/clock and
  public-reachability scans were rerun after implementation and found no stale
  product TODO/FIXME/XXX, unsafe correctness wall-clock/randomness or Float
  financial arithmetic. Remaining `StandardError` rescues are limited to
  durable append ambiguity/rollback and HTTP sanitization; abstract provider
  `NotImplementedError` guards and deliberate test doubles remain intentional.
- Passes I–J — the current functional matrix, benchmark, 10k load,
  degradation harness, demo, syntax and diff checks are green as recorded
  above. Executed scales remain 2,000 degradation payouts, 10,000 lifecycle
  operations, 20,000 allocation operations and 250 replay cases; no 100k-scale
  claim is made.
- Pass K — exact-revision CI evidence is still unavailable because the candidate
  remains uncommitted; the final closure decision is open.
- Pass L — this ExecPlan, backlog and current decisions are being synchronized
  with the D-164–D-169 implementation facts; the candidate cannot be declared
  `VERSION_COMPLETE` from local green tests alone.

The candidate remains open pending the remaining fresh A–L checks, current
performance evidence, exact-revision CI and skeptical final closure review.
No commit or push was performed.

## Fresh closure attempt — 2026-08-30 (after D-163)

The candidate closure was rerun after D-121, D-122, D-123, D-124, D-125, D-126, D-127, D-128, D-129, D-130, D-131, D-132, D-133, D-134, D-135, D-136, D-137, D-138, D-139, D-140, D-141, D-142, D-143, D-144, D-145, D-146, D-147, D-148, D-149, D-150, D-151, D-152, D-153, D-154, D-155, D-156, D-157, D-158, D-159, D-160, D-161, D-162 and D-163 from the
current working tree:

- Pass A — current production behavior was reconciled against SPEC-004 and
  inherited SPEC-003/002/001 requirements; no important locally solvable
  missing requirement was found.
- Pass B — the reachable production inventory remains 38 Ruby files in the
  root require graph. Catalog, admission, allocation, lifecycle, observation,
  fact-store and projection seams remain behind one coordinator atomic facade;
  no disconnected experimental production path was found.
- Passes C–E — the financial safety, policy/allocation/admission ordering and
  constrained optimization red-team remains covered by deterministic
  scenarios, independent property/model oracles, controlled races and seeded
  fault histories. D-121 closes forged live interaction commits; D-122 closes
  public each-only collection boundaries; D-123 prevents unclassified adapter
  or observation contract errors from being silently reclassified as
  financial `UNKNOWN` evidence; D-124 applies the same collection contract to
  payout context labels used by policy and opportunity evaluation; D-126
  canonicalizes provider identity before application webhook normalization;
  D-127 applies the same identity rule to HTTP normalizer configuration and
  route lookup, rejecting normalized-key collisions; D-128 applies the same
  rule to reversal settlement/conflict linkage and idempotent replay; D-129
  applies it to public live/replay payout lookup, resume/policy lookup and audit history. D-130
  extends the same identity rule to direct replay capacity/throughput snapshots; D-131
  closes policy provider identity and each-only collection boundaries; D-132
   rejects canonical collisions in provider-keyed policy configuration maps; D-133
   closes canonical allocation-snapshot lookup/update and collision handling; D-134
   closes canonical provider identity for quality snapshot construction and batch
   lookup; D-135 closes canonical allocation-decision maps and lookup; D-136
   closes canonical runtime-feasibility provider sets and attempted-provider
   exclusion; D-137 closes canonical allocation chooser inputs; D-138 closes
   canonical decision-engine availability and attempted-provider inputs; D-139
   closes canonical quality evidence keys at the constrained optimizer boundary;
   D-140 closes empty provider identity at the authoritative allocation
   snapshot boundary; D-141 closes typed quality evidence, key/value provider
   identity alignment, valid sample counters and canonical context labels;
   D-142 closes canonical admission buckets and typed capacity/throughput
   projection values; D-143 closes typed/canonical attempt and payout
   snapshots, ownership/history linkage and decision action/role shape; D-144
   closes raw provider/operation identity splits in replay projections; D-145
   closes the same split across analytics attribution and policy-target maps;
    D-146 closes the extracted lifecycle ledger identity boundary; D-147
    closes health probe-owner identity, blank snapshot-provider identity and
    exposure-flag type handling at the health admission boundary; D-148
    closes padded policy-registry lookup identity at policy resolution; D-149
    closes the remaining HTTP configuration gap by rejecting a non-executable
    webhook normalizer before the application is exposed; D-150 closes the
    health-snapshot counter/limit boundary so malformed admission state cannot
     be exposed through the typed health projection; D-151 keeps direct
     runtime-feasibility construction on the shared each-only boundary; D-152
     applies the same boundary to policy infeasibility error metadata; D-153
     applies the same collection rule to analytics fact reductions and keeps
     malformed scalar collections from changing replay metrics silently; D-154
     rejects noncanonical attempt identities in health-probe reservations; D-156
     pins the recovery operation budget with an end-to-end safe-release regression;
      D-157 fails closed when an append outcome cannot be observed; D-158
      rejects unresolved definitely-not-sent transport combinations; D-159
      requires journal read-back for restart-safe coordinator construction;
      D-160 preserves explicit durable corruption when poison containment fails;
      D-161 rejects invalid provider transport kinds at the input boundary; and
      D-162 applies the same explicit enum contract to health and quality
      projections; D-163 applies canonical whitespace handling to payout
      context labels at both hard-policy and provider-opportunity eligibility.
- Pass F — FileJournal/FactCodec and working restore preserve unresolved
  ownership, operation contract, policy binding, dedup/order, reservations,
  settlement and reconciliation state; exact allocation/fact-envelope
  identity, live-operation resume, D-124 canonical nested-context checks,
  D-125 fact nested-collection checks, D-128 canonical reversal linkage, D-129
  canonical replay payout lookup, D-130 canonical replay provider snapshots and
   D-131 policy boundary checks, D-132 policy-collision checks, D-133
   allocation-snapshot checks, D-134 quality-snapshot identity checks, D-135
   allocation-decision identity checks, D-136 feasibility identity checks,
   D-137 allocation chooser identity checks, D-138 decision-engine identity
   checks, D-139 optimizer-quality identity checks, D-140 empty-key checks,
    D-141 quality-evidence checks, D-142 admission-projection checks, D-143
    snapshot/decision-value checks, D-144 replay-identity checks, D-145
     analytics-identity checks, D-146 lifecycle-ledger checks, D-147
      health-boundary checks, D-148 policy-registry checks, D-149 HTTP
       normalizer-configuration checks, D-150 health-snapshot validation checks,
       D-151 each-only feasibility checks, D-152 policy-error collection,
        D-153 analytics collection, D-154 health-reservation identity,
         D-155 transport-outcome safety, D-157 fail-closed append checks and
         D-158 unresolved-transport safety, D-159 journal-contract, D-160
         poison-hook, D-161 transport-kind, D-162 health/quality enum and
         D-163 context-label eligibility checks remain green.
    Truncation,
   checksum and semantic
  corruption fail explicitly.
- Pass G — HTTP/application routing remains transport-only, provider-specific
  normalization remains explicit, normal transport uncertainty is represented
  by `ProviderTransportResult`/`ProviderTransportError`, and adapter contract
  violations do not enter the lifecycle reducer as synthetic outcomes. The
  typed observation boundary also rejects transport classifications that
  contradict the safe lifecycle outcome (D-155, D-158). The
  application boundary trims provider IDs before handing them to normalizers
  and rejects non-executable normalizer configuration at construction;
  reversal commands trim provider/operation IDs before financial linkage and
  payout query/history IDs use the same canonical form; the demo remains
  explicitly simulated.
- Pass H — reachable-code scans found no stale product TODO/FIXME/XXX,
  correctness-sensitive wall-clock/randomness or Float financial arithmetic.
  The remaining `NotImplementedError` sites are abstract provider guards and
  deliberate test doubles. Remaining `StandardError` rescues are limited to
  durable append ambiguity/rollback and HTTP error sanitization; the
  orchestrator no longer has an unclassified provider catch-all.
- Passes I–J — the current local matrix, crash/fault/replay checks and load
   measurements are recorded above. Executed scales remain 1,000 replay
  payouts, 2,000 degradation payouts, 10,000 lifecycle operations and 20,000
  allocation operations; no 100k claim is made. The D-126–D-163 rerun changed
   only observed runtime, not the measured conservation or recovery invariants;
  D-154 changes malformed durable-identity rejection and D-155 rejects an
   unsafe normalized transport/outcome combination before lifecycle mutation;
  D-158 rejects unresolved definitely-not-sent combinations before lifecycle
  mutation; D-159 rejects write-only durable journals before coordinator state
  can be created; D-160 preserves the durable-corruption error when journal
  poisoning itself fails;
  D-156 preserves the hard money-moving operation budget after safe release;
   D-157 fails closed when an append outcome cannot be observed; D-158 rejects
   unresolved definitely-not-sent transport combinations; D-159 prevents a
   write-only journal from being presented as restart-safe coordinator state;
   D-160 keeps poison-hook faults from masking durable corruption; D-161 keeps
   invalid provider transport kinds on the explicit input-error boundary; D-162
   keeps invalid health and quality enum inputs on that same explicit boundary;
   D-163 keeps equivalent padded context labels in one eligibility bucket.
- Pass K — NOW/P0/P1 work is locally implemented and rechecked; the remaining
  completion gate is CI on the exact candidate revision followed by the final
  completion decision. The official TZ remains a future reconciliation input,
  not a blocker for this product.
- Pass L — README, roadmap, current architecture, specifications, testing and
  workflow-facing docs, backlog, decisions and this ExecPlan describe the same
  v0.3 goal and stop rules.

The candidate remains `VERSION_CANDIDATE`: no material local gap was found in
this fresh pass after D-163, but the exact current working tree is uncommitted
and has no corresponding CI result. No commit or push was performed.

## Superseded closure attempt — 2026-08-30 (before D-121)

The candidate closure was rerun after D-119 and D-120 from the current
working tree:

- Pass A — current production behavior was reconciled against SPEC-004 and
  inherited SPEC-003/002/001 requirements; no important locally solvable
  missing requirement was found.
- Pass B — the reachable production inventory contains 38 Ruby files in the
  root require graph. Focused catalog, admission, allocation, lifecycle,
  observation, fact-store and projection seams remain under one coordinator
  atomic facade; no disconnected experimental production path was found.
- Passes C–E — financial safety, policy/allocation/admission and staged
  optimization are covered by the deterministic scenarios, independent
  property/model oracles, controlled races and seeded fault histories listed
  above. No arbitrary weighted score or UNKNOWN cross-provider fallback path
  was found.
- Pass F — FileJournal/FactCodec and working restore preserve unresolved
  ownership, operation contract, policy binding, dedup/order, reservations,
  settlement and reconciliation state; D-119/D-120 now close exact allocation
  and fact-envelope identity aliases. Truncation, checksum and semantic
  corruption remain explicit failures.
- Pass G — HTTP/application/provider review found transport-only API routing,
  provider-specific normalization and sanitized normal errors; the demo is
  explicitly simulated.
- Pass H — reachable-code scans found no TODO/FIXME/XXX, unsafe wall-clock or
  unseeded correctness randomness, Float financial arithmetic or unclassified
  production `NotImplementedError`; the remaining abstract provider guards and
  test doubles are deliberate.
- Passes I–J — the current local matrix, crash/fault/replay checks and load
  measurements are recorded above. Executed scales remain 1,000 replay
  payouts, 2,000 degradation payouts, 10,000 lifecycle operations and 20,000
  allocation operations; no 100k claim is made.
- Pass K — NOW/P0/P1 work is locally implemented and rechecked; remaining
  completion gates are CI on the exact candidate revision and the final
  completion decision. The official TZ remains a future reconciliation input,
  not a blocker for this product.
- Pass L — README, roadmap, current architecture, specifications, testing and
  workflow-facing docs, backlog, decisions and this ExecPlan are synchronized
  to v0.3 and the current candidate evidence.

This closure was valid before the D-121 live command-boundary finding below;
that material finding reopened implementation. The candidate must not return
to `VERSION_CANDIDATE` until D-121 is verified and the closure is rerun.

## Fresh closure attempt — 2026-08-29

The repository-wide closure protocol was rerun against the current working tree
after the latest catalog, policy, lifecycle, codec, semantic-restore, analytics,
journal-boundary and decision-context changes:

- Pass A — current production code was reconciled against SPEC-004 and inherited
  SPEC-003/002/001 behavior; the canonical product flow remains covered, while
  the fresh restore red-team continued to identify locally-solvable durable
  decision-boundary gaps.
- Pass B — the reachable production inventory is the plain-Ruby domain/routing,
  state, projection, application and explicitly simulated demo surface; the
  coordinator remains the atomic facade and the extracted fact, provider-catalog,
  admission, allocation, lifecycle and observation ledgers are integrated.
- Passes C–E — financial safety, policy/allocation/admission ordering and
  constrained optimization are covered by the scenario matrix, independent
  oracles, model histories and concurrency races; the latest restore red-team
  also closed catalog-removal, ordered provider-registration for provider-system,
  opportunity-evaluation and decision facts, final-state,
  conflict, reversal, unsupported-fact, ordered health-transition and
  duplicate/post-release probe-reservation, admission-consumption, allocation,
  settlement and economic-conflict multiplicity/order gaps.
- Passes F–G — crash-boundary, corruption, long-history and provider/application
  boundary campaigns pass; restore also rejects noncanonical provider identities
  and non-`Time` timestamps, durable observations reject noncanonical identity,
  flags, sequence, timestamp and enum values, the durable codec rejects nested
  floating-point payloads, `FileJournal` rejects non-object JSON roots, while
  replay remains distinct from working restart recovery and health transition
  facts are causally ordered and probe reservations, throughput consumption,
  allocation, settlement and conflict records cannot be duplicated or recreated
  after operation release; opportunity-evaluation quality, ranking, health-policy,
  static-policy and previous-outcome traces are checked against their typed
  state at the same evaluation boundary; assignment and non-operation decision
  traces are also recomputed rather than accepted as audit-only payloads.
- Pass H — no TODO/FIXME/XXX remains in reachable product code; the remaining
  `NotImplementedError` sites are abstract provider-port guards or deliberate
  test/benchmark doubles. No Float-based money/allocation arithmetic, wall-clock
  correctness dependency or unseeded randomized campaign was found.
- Passes I–J — the exact local verification and benchmark/load results are the
  evidence block above; executed scales are 1,000 replay payouts, 2,000
  degradation payouts, 10,000 lifecycle operations and 20,000 allocation ops.
  No 100k claim is made.
- Passes K–L — backlog and governing current documents are synchronized; the
  current candidate has no CI execution result because it is uncommitted; CI on
  the current revision and the final closure decision remain completion-policy
  gates.
  The health cohesion review concluded that `Routing::HealthController` is
  already the focused state seam, recorded as D-060, so no redundant wrapper is
  required.
- Follow-up red-team — the audit then found and closed additional local boundary gaps:
  opportunity facts could mention an unregistered provider, durable/live
  boundaries accepted noncanonical provider IDs or non-`Time` timestamps, opaque
  policy epochs were selected lexicographically, durable decoding could admit
  crafted floating-point values, restore could leak a non-enumerable opportunity
  input as an internal `NoMethodError`, live and restore observation identity/order
  logic could diverge, malformed durable observation fields could bypass the live
  input contract, and restore/batch fact inputs could leak another internal
  `NoMethodError` contract. A duplicated durable outcome-to-status mapping was
  also removed. The ordered-provider regression, D-062 identity/time rules,
  D-063 explicit activation order, D-064 codec rules, D-065 catalog seam,
  D-066 observation seam, D-067 durable observation validation, D-068 durable
  enumerable-input contracts, D-069 lifecycle reduction reuse, D-070 strict
  Boolean construction, D-071 fallback analytics semantics, D-072 retry-role
  preservation, D-073 journal-root validation and the each-only collection
  boundary are now included in the current matrix. The latest catalog-restore,
  Boolean-corruption, collection-contract, analytics-role, journal-root and
  health-transition and probe-reservation findings were implemented, regressed
  and rechecked in this candidate closure pass.

The latest restart/type red-team findings were material but locally solvable and
are now implemented with regressions. A follow-up analytics red-team found that
fallback-attempt and successful-recovery metrics were aliases; D-071 and a
deterministic failed-fallback regression now separate those meanings. A second
analytics audit found that `retry_same` could overwrite the original recovery
role; D-072 and an UNKNOWN→retry_same→success regression now preserve the
economic attribution. A durable journal-shape audit then found that a non-object
JSON root could leak an incidental Ruby type error; D-073 validates the root
before record-kind inspection and adds a corruption regression. Focused and full
verification passed on the resulting candidate. A subsequent health-transition
red-team found that `health_state_changed` validated only its destination state,
so a forged predecessor or omitted transition could survive restore. D-074 adds
ordered predecessor tracking and regressions. The full matrix and a fresh
closure attempt were rerun before the subsequent probe-reservation finding;
D-075 was implemented and focused-verified. The subsequent decision-restore
  red-team found that duplicate assignment facts and capability-illegal resolution
  facts could reopen a provider interaction after restart. D-076 closed those
  control-plane gaps with focused regressions. A follow-up observation red-team
  then found that forged durable `applied/conflict` flags could hide a late
  economic conflict; D-077 recomputes them from lifecycle state. A subsequent
  reservation/replay audit found that throughput, allocation, settlement and
  economic-conflict facts could be duplicated or recreated outside their causal
  operation phases. D-078 through D-082 add ordered restore checks and
  multiplicity regressions. A follow-up derived-fact audit then found that
  health, quality and transport records could be replayed without their source
  observation; D-083 adds source identity, projection agreement and duplicate
  guards. A final conflict-evidence audit then found that a valid
  `conflict:true` late observation could lose its separate economic-conflict
  fact while leaving lifecycle status plausible; D-084 makes that conflict fact
  mandatory and ordered. A subsequent assignment-bundle audit found that a
  feasible decision could outlive its opportunity trace, or restore without
  allocation/ownership/rate/probe side facts; D-085 and D-086 link the decision
  to its evaluated cohort and require the complete atomic bundle. A follow-up
  trace audit then found that the persisted allocation snapshot was only shape
  checked; D-087 now compares its exact key, revision and measures with the
  allocation ledger at the evaluation boundary. The candidate remains reopened
  until a fresh closure pass and current-revision CI evidence are available.

The subsequent admission-trace audit found that opportunity evaluations carried
capacity usage evidence but restore only checked its shape. D-088 now compares
every persisted capacity trace with the exact admission ledger at that fact
boundary and adds a forged-usage restart regression. The candidate remains open
for the next fresh closure pass and current-revision CI evidence.

The follow-up integrity audit found three more durable ambiguities: observation
health provenance could be erased into a manual event, allocation facts could
write under a different evaluated cohort key, and duplicated provider admission
fields could diverge from the canonical definition. D-089–D-091 add explicit
provenance, key-linkage and cross-field checks with restart regressions. The
candidate remains open for the next fresh closure pass and current-revision CI
evidence.

The next restore audit found that an evaluation could retain a valid eligibility
cohort while replacing its quality, ranking, health-policy, static-policy or
previous-outcome context. D-094 validates those exact typed traces at the
evaluation boundary; focused and full local verification now pass, while the
candidate remains open for another fresh closure/red-team pass and CI evidence.

The following decision-trace audit found that a feasible assignment could retain
economic safety while replacing its allocation or optimization explanation.
D-095 recomputes the assignment trace from the preceding evaluation and rejects
divergent durable rationale; focused and full local verification now pass, while
the candidate remains open for another fresh closure/red-team pass and CI
evidence.

The subsequent allocation-fact audit found that a valid operation could retain
its linkage while carrying split policy metadata or a forged capacity-reservation
flag. D-096 now cross-checks those fields against the pinned policy and restored
operation bundle; focused verification passes and the candidate remains open for
the next broad closure pass and CI evidence.

The next recovery-decision audit found that a durable resolution action could
retain a valid operation and contract while bypassing the current recovery
classification. D-097 recomputes classification from restored lifecycle,
ownership, contract, attempt and policy state and requires matching action,
reason and reason-code evidence. Focused and full local verification now pass;
the candidate remains open for another fresh closure/red-team pass and
current-revision CI evidence.

The follow-up no-operation decision audit found that `restore_decision!` could
return before validating durable `defer`, `terminate` or `already_final` audit
payloads. D-098 now recomputes final/defer classification, no-route reasons and
runtime feasibility from the preceding evaluation, checks switch-budget
decisions, and requires explicit adapter-availability context for that external
branch. Focused and full local verification now pass; the candidate remains
open for another fresh closure/red-team pass and current-revision CI evidence.

The assignment-rationale audit then found that restore could recompute the
selected allocation while accepting a forged assignment explanation or
deviation classification. D-099 makes assignment proposal construction shared
between live routing and restore validation and checks reasons, reason codes,
deviation cause and recoverability. Focused and full local verification now
pass; the candidate remains open for another fresh closure/red-team pass and
current-revision CI evidence.

The next durable multiplicity/context audit found duplicate intent and policy
registration facts, plus a split static-feasibility field, could survive or
alter working restore; D-100–D-102 reject those histories with focused
regressions. A provider configuration audit then found registration and health
signal policy snapshots were not cross-checked, while operation-causal review
found `attempt_started`, probe reservation and ownership-release facts could
carry divergent phase/identity/reason evidence. D-103–D-107 now enforce those
links. Focused verification passes; the candidate remains open for the fresh
broad matrix, closure red-team and current-revision CI evidence.

A contract/action/analytics audit then found that durable operation contracts
could diverge from provider capabilities, interaction starts could change the
committed action, and duplicate observations could inflate analytics.
D-108–D-110 close those gaps with focused regressions. The candidate remains
open for the fresh broad matrix, closure red-team and current-revision CI
evidence.

The next recovery-boundary audit found that a `reconciliation_blocked` fact
could retain valid operation linkage while carrying forged expiry reason or
timing evidence. D-111 now checks canonical reason, exact elapsed time and
actual contract expiry at restore, with focused corruption regressions. The
candidate remains open for the next broad matrix, fresh closure/red-team pass
and current-revision CI evidence.

A policy-registry audit then found that live registration rejected conflicting
reuse of a policy scope globally, while restore only rejected duplicates within
one payout. D-112 now enforces the same cross-payout identity invariant during
restore, with a focused corruption regression. The candidate remains open for
the next broad matrix, fresh closure/red-team pass and current-revision CI
evidence.

A collection-boundary audit then found `PolicyRegistry` still used `Array()` for
initial policies while the rest of the product accepted each-only sources.
D-113 routes construction through the shared helper and adds a focused
regression. The candidate remains open for the next broad matrix, fresh
closure/red-team pass and current-revision CI evidence.

A durable identity audit then found policy IDs, epochs, scopes and fingerprints
were normalized with `.to_s` in restore, allowing noncanonical representations
to pass identity checks. D-114 applies strict String validation across policy
registration, evaluation and allocation facts, with focused corruption
regressions. The candidate remains open for the next broad matrix, fresh
closure/red-team pass and current-revision CI evidence.

The following identity audit found several lifecycle and settlement restore
branches still normalized operation, attempt, observation or reversal IDs with
`.to_s`. D-115 applies one strict canonical identity boundary across those
facts and adds focused corruption regressions. The candidate remains open for
the next broad matrix, fresh closure/red-team pass and current-revision CI
evidence.

An operation-bundle audit then found restore checked duplicate operation IDs but
not duplicate attempt identities across primary and recovery assignments.
D-116 adds the per-payout attempt uniqueness guard and a primary-failure to
recovery corruption regression. The candidate remains open for the next broad
matrix, fresh closure/red-team pass and current-revision CI evidence.

An application-input audit then found available-provider filtering required
`.map` despite the shared each-based collection contract. D-117 routes that
input through the common boundary and adds an each-only regression. The
candidate remains open for the next broad matrix, fresh closure/red-team pass
and current-revision CI evidence.

A codec red-team then found tagged Hash payloads could contain duplicate keys
and silently change their decoded value. D-118 classifies duplicate entries as
durable corruption and adds a direct codec regression. The candidate remains
open for the next broad matrix, fresh closure/red-team pass and current-revision
CI evidence. A follow-up allocation trace audit found both the evaluation
snapshot and committed allocation fact could normalize a noncanonical key
segment with `.to_s`; D-119 now requires exact structural key equality at both
durable boundaries and adds focused regressions. The candidate remains open for
the next fresh closure/red-team pass and current-revision CI evidence.

Known strengths:

- economic ownership/dispatch/UNKNOWN core;
- exact allocation;
- policy fingerprinting;
- eligibility/capacity/health;
- recovery/reconciliation;
- replay/conflict/reversal;
- multi-currency registry;
- strong property/model/concurrency suites;
- GitHub Actions on Ruby 4.0.6.

Known convergence findings:

- documentation prematurely claimed v0.2/v1.0 completion;
- `State::Coordinator` grew to a broad responsibility hub;
- fee/ranking/rate/corridor/product-server/persistence additions were not coherently integrated;
- weighted-sum “Pareto” ranking could trade allocation correctness for lower-level objectives;
- hardcoded BIN/bank heuristics were case-irrelevant generic-core leakage;
- fake rail adapters were simulators, not real integrations;
- demo webhook trusted raw `safe_to_release` semantics;
- persistence replay did not reconstruct a working coordinator with unresolved ownership; current `FileJournal` restoration now does so for the covered operation boundaries, with deterministic crash/corruption, long-history and state-machine campaigns passing;
- randomized fuzz previously used non-reproducible global randomness; all current generated property/model/concurrency/fault harnesses now use explicit seeds or deterministic scenario tables and report seed/history/step context on failure;
- claimed battle-test scale did not match actual executed payout count.

The cleanup commit removes the clearly misleading branches; useful concepts are reintroduced only through SPEC-004 architecture.

## Phase A — Clean coherent baseline

Goal: establish a small, truthful production surface containing only the integrated routing core.

Required outcomes:

- [x] experimental/disconnected feature-burst production files removed/demoted;
- [x] root require graph contains only supported integrated core;
- [x] dedicated tests for removed experiments removed;
- [x] complete canonical Ruby verification passes after cleanup;
- [ ] CI passes on the cleanup revision;
- [x] no warning from removed demo/server dependencies;
- [x] module inventory records remaining production responsibilities.

First rolling actions:

1. run `bundle check` and all Rake suites after cleanup;
2. fix only real regressions caused by accidental coupling;
3. scan `lib/` for dead public modules/requires;
4. record clean baseline and update this plan.

### Baseline result

The cleanup result is coherent enough to begin Phase B: `lib/` contains the canonical domain/routing/application/state/projection paths only, and the current verification matrix is green. Remaining product gaps were real at this baseline: there was no restart-safe working durable coordinator, no explicit throughput admission state, and the coordinator concentrated fact storage, lifecycle, allocation, capacity and health coordination.

The baseline statement above is historical pre-slice evidence. Current work has since added restart-safe journal/restore, explicit throughput state and focused lifecycle-state validation; this does not retroactively change the clean baseline.

## Phase B — Architecture convergence inside atomic facade

Goal: reduce semantic coupling in `State::Coordinator` without changing financial behavior.

Do not rewrite it wholesale.

Suggested extraction order, subject to actual dependency analysis:

1. fact/state repository responsibility — `State::FactStore` extracted;
2. provider catalog/history responsibility — `State::ProviderCatalogLedger` extracted;
3. admission/capacity ledger responsibility — `State::AdmissionLedger` extracted;
4. allocation ledger responsibility — `State::AllocationLedger` extracted;
5. lifecycle reducer / operation state transition responsibility;
6. observation identity/order responsibility;
7. provider health state integration.

For each extraction:

- write/retain behavior tests first;
- keep atomic transaction under coordinator facade;
- prove no provider I/O enters lock;
- compare replay/live state;
- run concurrency regressions;
- remove old duplicate path after equivalence.

### Rolling architecture slices

`State::FactStore` owns append-only fact identity, sequence/revision and optional journal delivery; `State::ProviderCatalogLedger` owns the current opportunity map and ordered registration/removal timeline; `State::AdmissionLedger` owns concurrent capacity and time-window throughput; `State::AllocationLedger` owns keyed primary allocation snapshots; `State::LifecycleLedger` owns operation phase/outcome reduction; `State::ObservationLedger` owns shared observation identity, deduplication and provider-event ordering. `State::Coordinator` remains the sole synchronization/atomic facade and calls these seams only under its mutex. Durable restore validates lifecycle, provider-system and financial linkage and rejects semantic corruption instead of ignoring it.

Acceptance for the slice:

- facts retain the same immutable payloads and ordering;
- sequence and revision advance exactly once per appended fact;
- journal receives each fact after it is constructed in the same order;
- coordinator snapshots and replay projections retain their current revisions/results;
- no provider method is invoked by the fact store or while the coordinator lock is held.

Result: accepted as `SLICE_VERIFIED` after focused tests and the full local matrix. These extractions preserve one atomic correctness boundary; the focused `Routing::HealthController` seam is intentionally retained per D-060, with only closure evidence and any newly discovered invariant gap still open.

Phase exit: the coordinator coordinates atomic changes; it no longer contains duplicated domain algorithms merely because it owns the mutex.

## Rolling Next Actions

1. Preserve the explicit no-catch-up semantics from D-059; add a debt ledger only if the official TZ or a new accepted product decision requires it.
2. Keep deterministic trace/seed evidence attached to every generated and fault campaign as new scenarios are added.
3. Continue coordinator decomposition only where the next seam improves one of the above invariant boundaries.
4. Keep recovery probing guardrails aligned with admission evidence; a multi-step traffic ramp remains optional unless the case requires it.
5. Repeat crash-boundary/replay equivalence checks after any further durable-state mutation; replay projections alone remain insufficient.

## Phase C — Policy and allocation completeness

Goal: make business distribution semantics universal and explicit.

Required slices:

- [x] split per-payout amount eligibility constraints from provider target-share min/max obligations;
- [x] add exact typed share-corridor violations and staged allocation precedence;
- [x] define explicit target/tolerance/admissible-corridor semantics;
- [x] implement/clarify window semantics beyond a name-only enum;
- [x] define static policy infeasibility versus runtime infeasibility;
- [x] define opportunity-aware denominator/scoping;
- [x] model deviation attribution;
- [x] model recoverable vs unavoidable deviation;
- [x] explicitly keep historical debt/catch-up disabled and prevent recovery burst semantics (D-059);
- [x] prove count and volume under concurrent committed work;
- [x] prove policy epoch changes without silent historical reset.

Acceptance must include large indivisible payouts, dominant weights, provider outage/recovery and variable eligibility.

## Phase D — Operational admission controller

Goal: create one explicit hard runtime admission layer.

Required slices:

- [x] administrative enablement/availability;
- [x] concurrent slots/exposure;
- [x] amount exposure;
- [x] time-based throughput/rate budget;
- [x] health/quarantine/probing;
- [x] atomic revalidation/reservation before operation commit;
- [x] fallback re-evaluates current admission.

Important invariant: throughput tokens/windows are consumed over time; they are not released when a payout operation finishes. Concurrent exposure is separately reserved/released.

Phase exit: allocation/optimizer cannot route through an inadmissible provider.

## Phase E — Constrained smart optimization

Goal: add genuinely useful “smart routing” without compromising deterministic financial policy.

Required architecture:

`safe/eligible/admitted -> allocation admissible set -> reliability/quality -> cost -> latency/priority`.

Required slices:

- [x] deterministic lexicographic/staged optimizer;
- [x] allocation tolerance/corridor defines admissible provider set;
- [x] fast operational health remains separate from slow quality;
- [x] slow quality estimate has explicit attribution and sample confidence;
- [x] delayed/maturity behavior does not score pending as immediate failure;
- [x] context/cohort fallback hierarchy for sparse evidence;
- [x] recovery ramp/probing prevents abrupt full traffic restoration;
- [x] trace explains every optimization stage.

Do not add ML/bandits until this deterministic layer is correct and measurable.

## Phase F — Provider lifecycle and reconciliation hardening

Goal: make the payout workflow exhaustive across ambiguous provider behavior.

Required slices:

- [x] one canonical provider port;
- [x] provider-specific normalization contract;
- [x] operation-scoped idempotency/status/deadline/TTL;
- [x] explicit dispatch/resolve/retry/fallback/defer transitions;
- [x] idempotency TTL expiry -> reconciliation-blocked/manual path rather than unsafe retry;
- [x] late success/conflict and remediation;
- [x] partial/full reversal semantics;
- [x] manual/operator reconciliation command model where useful;
- [x] no raw caller can forge safe-release semantics.

## Phase G — Durable state and restart safety

Goal: implement real restart continuation, not read-only replay mislabeled recovery.

Current slice result: `State::FileJournal` plus tagged `FactCodec` is integrated with `FactStore`, and a fresh coordinator restores the working state needed for the covered unresolved-operation boundaries. Coordinator mutations are committed as one durable batch; failure injection covers both pre-append rollback/rebuild and complete post-append visibility. A deterministic six-scenario crash campaign verifies fresh-process continuation or conservative preservation across the required lifecycle boundaries, a 14-mutation corruption matrix verifies explicit rejection of malformed durable history, a fixed 1,000-payout campaign verifies long-history replay/restore equivalence, and a fixed-seed 64-history state-machine campaign verifies repeated lifecycle/restart parity. The implementation is not yet a phase exit: CI and final closure review remain open.

Start with failing contract tests before choosing/implementing storage.

Required crash scenarios:

1. crash after atomic assignment/ownership but before provider call;
2. crash after provider may have accepted but before observation persisted;
3. crash with UNKNOWN owner;
4. crash after safe release before fallback;
5. crash after settlement before response to caller;
6. crash while reconciliation-blocked.

Fresh process must restore enough working state to continue safely.

Required durability properties:

- transactionally consistent state/facts;
- ownership/operation contract restored;
- policy binding restored;
- dedup/order state restored;
- correctness reservations restored;
- replay and live resumed state agree;
- malformed/truncated persistent data is explicit failure or controlled repair state.

Choose the smallest hackathon-compatible implementation. An embedded transactional store is acceptable if justified; do not build distributed infrastructure.

## Phase H — Analytics and audit productization

Goal: make routing behavior explainable to judges/operators.

Current slice result: analytics and replay preserve target/actual, opportunity,
assignment, attempt, settlement, distinct fallback-payout and successful-
fallback-recovery metrics, provider-attributed failures, unresolved age,
exclusion, runtime infeasibility, typed deviation recoverability,
conflict/reversal and decision-trace evidence. Long-history conservation
is exercised in Phase J; additional scale is optional and no unexecuted 100k
claim is made.

Required outputs:

- target vs actual count/volume;
- opportunity -> assignment -> attempt -> settlement;
- first-attempt/eventual success;
- fallback recovery;
- provider-attributable failure;
- unknown/pending/reconciliation age;
- attempt amplification;
- availability/admission/health exclusion reasons;
- allocation deviation/debt attribution;
- economic conflicts/reversals;
- typed complete decision trace.

Analytics definitions need invariant/conservation tests and replay equivalence.

## Phase I — Application/API/demo product surface

Goal: expose the mature engine without creating alternate domain semantics. The
command/query surface, minimal transport adapter and explicit simulated fallback
scenario now exist and are covered by application/HTTP tests. The final external
API shape remains deliberately provisional until the official TZ, as required by
the pre-TZ specifications; no alternate routing semantics are deferred behind
that boundary.

First create stable application use cases:

- submit payout;
- get payout;
- resume/advance;
- reconcile provider event;
- manage/query policy/provider state;
- query analytics/audit.

Then build minimal API/demo adapters.

Rules:

- raw webhook -> provider-specific normalizer -> domain observation;
- no request field directly grants safe-release authority;
- no Ruby backtrace in user-facing error response;
- demo providers are explicitly simulated;
- dashboard reads projections and invokes application commands only.

## Phase J — Deep verification / load / maintainability

Required campaign:

- [x] deterministic scenario matrix;
- [x] independent oracle/property expansion for new policy/admission semantics;
- [x] long state-machine histories;
- [x] controlled interleavings for new ledgers/restart boundaries;
- [x] seeded chaos/fault runs with stored seeds;
- [x] deterministic crash-at-boundary campaign;
- [x] durable corruption campaign;
- [x] replay equivalence over long histories;
- [x] 10k load baseline;
- [x] 100k campaign not required because the repository makes no 100k-scale claim;
- [x] memory and attempt-amplification measurements;
- [x] measured refactors/performance improvements only (current post-extraction benchmark recorded above; no scale claim beyond executed harnesses).

Heavy scale tests may live outside default CI; their commands/environment/results must be reproducible.

## Phase K — Product closure / red-team

When phases appear complete, set `VERSION_CANDIDATE` and execute every pass in `docs/COMPLETION_POLICY.md`.

Closure must deliberately try to find new gaps. It is not a documentation ceremony.

Any material locally solvable finding:

- gets a backlog item/regression;
- reopens the relevant phase;
- returns status to active development.

`VERSION_COMPLETE` is permitted only after a fresh closure pass finds no unresolved required local gap.

## Verification commands

Canonical:

```text
bundle check
bundle exec rake test
bundle exec rake property
bundle exec rake model
bundle exec rake concurrency
bundle exec rake fault
bundle exec rake benchmark
bundle exec rake load_10k
bundle exec rake degradation_metrics
```

Record exact CI revision and any additional load/crash commands in Progress.

## Surprises & Discoveries

- 2026-08-28: current `main` is clean at `1f3500e...`; the complete local matrix is green, but the former CI workflow omitted benchmark/load/degradation/demo checks and the green suite did not establish restart-safe durability.
- 2026-08-29: CI was extended to run the same benchmark/load/degradation/demo checks as the local product evidence; no current-revision CI result exists until the candidate is executed by GitHub Actions.
- 2026-08-28: `State::Coordinator` is 1,186 lines and directly owns fact sequence/revision/journal in addition to lifecycle and operational ledgers. The first architecture slice extracts that fact repository boundary without changing routing semantics.
- 2026-08-28: green CI on `30b4fb3...` proved the current suites run, but documentation/product claims exceeded what the code actually integrated.
- 2026-08-28: the feature burst reintroduced premature completion despite an existing completion policy; current instructions therefore treat completion as a fresh product-wide falsification exercise.
- 2026-08-28: projection replay and working restart recovery are explicitly separated.
- 2026-08-28: allocation authority and optimization are explicitly separated; lower-level cost/health/latency cannot trade away the distribution contract silently.
- 2026-08-28: full-state Marshal checkpoints made the 2,000-operation benchmark non-scalable; the durable path now rebuilds from accepted facts only on exceptional rollback, restoring the no-journal hot path to a measured 770.7 lifecycle ops/s.
- 2026-08-28: a journal can report an error after a complete batch is visible; FactStore compares the durable prefix/suffix before deciding whether to roll back, preventing identity reuse on retry.
- 2026-08-29: the deterministic simulator gained queued callback/reversal controls; crash and corruption campaigns now cover the required durable boundaries, while a 1,000-payout replay campaign and 2,000-payout degradation/memory harness provide bounded long-history evidence without claiming 100k scale.
- 2026-08-29: lifecycle extraction initially exposed a missing `pending -> unknown` transition in the independent ownership model; the fixed transition table and 64-history long state-machine campaign now cover that path and fresh working restore parity.
- 2026-08-29: semantic restore red-team found and closed silent unsupported-fact handling plus provider-runtime, conflict, reversal and final-state linkage gaps; current evidence is recorded above and the candidate remains open pending closure.
- 2026-08-29: a catalog-removal health/quality restore audit found that valid observations from removed providers need historical-but-ordered registration validation, while manual unknown-provider health commands must be rejected; both paths are now covered. A second audit removed future-registration preload and enforced catalog timeline order, and the candidate remains open pending closure.
- 2026-08-29: failure-injection red-team found that an ambiguous partial append could otherwise permit later writes after in-memory rollback; FactStore now distinguishes unchanged/complete/corrupt outcomes and poisons a journal left non-prefix, recorded as D-061. A follow-up restore audit closed noncanonical provider IDs and arbitrary timestamp payloads at the live/durable boundary, recorded as D-062.
- 2026-08-29: policy-resolution audit found lexical epoch selection (`"9"` versus `"10"`) was an implicit and unsafe recency rule; `PolicyRegistry` now uses explicit registration/activation order, recorded as D-063.
- 2026-08-29: durable-boundary red-team found the codec rejected floats only while encoding; decode now rejects crafted nested floating-point values as corruption, recorded as D-064.
- 2026-08-29: coordinator responsibility review extracted current provider identity and ordered registration/removal history into `State::ProviderCatalogLedger`; a monotonic sequence guard makes the timeline invariant local, recorded as D-065.
- 2026-08-29: restore-input review found non-enumerable supplied opportunities bypassed the live validation contract; `ProviderCatalogLedger` now owns that validation and the coordinator restore path is covered by a regression.
- 2026-08-29: observation-boundary review found live and durable restore had separate identity/order implementations; `ObservationLedger` now centralizes duplicate identity, authoritative sequence handling and late-success conflict classification, recorded as D-066.
- 2026-08-29: the observation-boundary red-team then found durable flags, IDs, sequence and timestamp values were not validated like live observations; `ObservationLedger` now rejects those malformed values before dedup/state mutation, recorded as D-067.
- 2026-08-29: durable input review found fact-source and batch append APIs leaked `NoMethodError` for non-enumerable input; explicit enumerable contracts and focused regressions now cover `FactStore`, `FactCodec` and `FileJournal`, recorded as D-068.
- 2026-08-29: live/restore cohesion review found a duplicated outcome-to-status mapping; durable observation restore now delegates to `LifecycleLedger.status_for`, recorded as D-069.
- 2026-08-29: candidate Pass L found two historical discovery lines still used `ACTIVE` after entering `VERSION_CANDIDATE`; the status language was synchronized and the stale-claim search is now clean.
- 2026-08-29: restart red-team found that restore preloaded supplied runtime opportunities before replay, allowing a provider without durable registration history to receive a new decision; restore now replays the catalog from an empty ledger and rejects supplied IDs that are not current in durable history. The candidate is reopened for verification.
- 2026-08-29: collection-boundary red-team found that explicit `#each` checks still relied on incidental `.to_a`; a shared `RubyRouting::Collection` helper now consumes each-only enumerables across durable, catalog, demo and projection inputs, with focused regressions. The candidate is reopened for verification.
- 2026-08-29: analytics red-team found `fallback_recovery_count` was aliased to successful recovery and therefore hid failed fallback attempts; D-071 separates fallback-payout, successful-recovery and recovery-operation metrics with a live/replay regression. The candidate remains open pending closure and CI.
- 2026-08-29: analytics retry audit found a reused operation's `retry_same` decision could overwrite its original recovery role; analytics now preserve the economic role across control-plane resolution decisions, recorded as D-072, with an UNKNOWN→retry_same→success live/replay regression. The candidate is reopened for verification.
- 2026-08-29: durable journal-shape audit found a non-object JSON root could leak `TypeError`/`NoMethodError` from `FileJournal#facts`; object-root validation now reports `DurableCorruptionError`, recorded as D-073, with a direct journal regression. The candidate is reopened for verification.
- 2026-08-29: health-transition restore red-team found `health_state_changed` checked only the destination state; restore now requires the immediately preceding health signal to produce the exact `from -> to` transition and rejects missing/interleaved transition facts, recorded as D-074. The candidate is reopened for verification.
- 2026-08-29: probe-reservation restore red-team found duplicate and post-release `health_exposure_reserved` facts could be accepted through owner-idempotent reservation behavior; restore now requires a single committed owner-free operation reservation and rejects recreation after release, recorded as D-075. The candidate is reopened for verification.
- 2026-08-29: durable reservation/replay red-team found that capacity/health release facts did not require a terminal operation outcome, and a capacity reservation had to remain valid before the decision fact because that is the actual live append order; D-078 preserves the valid pre-decision order while rejecting premature release/recreation.
- 2026-08-29: throughput, allocation, settlement and economic-conflict restore audits found duplicate or post-release facts could recreate admission exposure, inflate allocation/incident ledgers or rewrite final settlement status; D-079 through D-082 add committed-phase ordering and explicit restore multiplicity guards.
- 2026-08-29: observation-derived health, quality and transport facts could be replayed independently of their provider observation; D-083 adds source payout/observation identity, projection agreement and duplicate guards while preserving source-free manual health events.
- 2026-08-29: conflict-evidence review found a valid late observation could retain `conflict:true` while its separate `economic_conflict` fact was omitted, leaving lifecycle status plausible but losing the incident; D-084 now requires the ordered conflict fact and checks for unconsumed conflict evidence at restore completion.
- 2026-08-29: assignment restore could accept a provider outside the preceding feasible cohort, or a pending assignment missing allocation/ownership/rate/probe side facts; D-085 and D-086 now validate the durable evaluation trace and the complete atomic assignment bundle.
- 2026-08-29: opportunity-evaluation restore validated allocation snapshot shape but not its exact ledger state; D-087 now rejects forged key/revision/measures at the evaluation boundary.
- 2026-08-29: opportunity-evaluation restore validated capacity trace shape but not its exact admission state; D-088 now rejects forged used slots/count/amount traces at the evaluation boundary.
- 2026-08-29: durable health provenance, allocation-key linkage and duplicated provider admission configuration were under-specified; D-089–D-091 now reject source erasure, alternate evaluated keys and split capacity/throughput definitions.
- 2026-08-29: explicit throughput availability was bypassed before rate-window admission, and durable evaluations trusted nested feasible IDs; D-092–D-093 now enforce the hard gate and recompute eligibility/runtime feasibility at the historical evaluation boundary.
- 2026-08-29: the restore red-team found that an evaluation could retain a valid eligibility cohort while replacing its quality/ranking/policy/outcome context; D-094 now validates those typed traces at the evaluation boundary and reopens the candidate for broad verification.
- 2026-08-29: the decision-trace red-team found that a feasible assignment could retain safety while replacing its allocation/optimization rationale; D-095 now recomputes that trace from the preceding evaluation and reopens the candidate for broad verification.
- 2026-08-29: the allocation-fact red-team found split policy metadata and a forged capacity-reservation flag could survive valid operation linkage; D-096 now cross-checks the policy and reservation bundle and reopens the candidate for broad verification.
- 2026-08-29: the recovery-decision red-team found a durable resolution action could bypass the current classification while retaining valid operation linkage; D-097 now recomputes action/reason/reason-code evidence from restored recovery state and reopens the candidate for broad verification.
- 2026-08-29: the no-operation decision red-team found `restore_decision!` could accept forged final/defer/no-route rationale after an early return; D-098 now recomputes the non-operation trace and reopens the candidate for broad verification.
- 2026-08-29: the assignment-rationale red-team found restore could accept forged reasons or deviation classification after recomputing the selected allocation; D-099 now shares assignment proposal construction with live routing and reopens the candidate for broad verification.
- 2026-08-29: durable multiplicity and policy-context audits found duplicate intent/policy registrations and split static-feasibility/provider health-quality policy snapshots; D-100–D-104 now reject those divergent histories with focused regressions.
- 2026-08-29: operation-causal restore audit found interaction starts, probing reservations and ownership releases could carry divergent phase, attempt identity or terminal reason evidence; D-105–D-107 now require exact links and reopen the candidate for broad verification.
- 2026-08-30: recovery-boundary audit found reconciliation blocks could carry forged expiry reason or timing evidence; D-111 now validates exact contract expiry at restore, with focused corruption regressions and the candidate reopened for broad verification.
- 2026-08-30: policy-registry audit found restore could replace a shared policy scope from another payout; D-112 now rejects cross-payout scope redefinition and reopens the candidate for broad verification.
- 2026-08-30: collection audit found `PolicyRegistry` used a different initial-input coercion path; D-113 now applies the shared each-only contract and reopens the candidate for broad verification.
- 2026-08-30: durable identity audit found policy fields could be normalized from noncanonical values; D-114 now requires canonical policy identity Strings across durable facts and reopens the candidate for broad verification.
- 2026-08-30: lifecycle identity audit found operation/attempt/observation/reversal IDs could be normalized from noncanonical values; D-115 now requires canonical durable identities and reopens the candidate for broad verification.
- 2026-08-30: operation-bundle audit found recovery assignments could reuse an earlier attempt identity; D-116 now enforces per-payout attempt uniqueness and reopens the candidate for broad verification.
- 2026-08-30: application-input audit found available-provider filtering used a map-only path; D-117 now applies the shared each-only contract and reopens the candidate for broad verification.
- 2026-08-30: codec red-team found duplicate tagged Hash entries could overwrite earlier values during decode; D-118 now rejects that durable corruption and reopens the candidate for broad verification.
- 2026-08-30: allocation-trace red-team found evaluation and committed allocation keys could normalize noncanonical segments with `.to_s`; D-119 now requires exact structural equality at both durable boundaries and reopens the candidate for broad verification.
- 2026-08-30: durable envelope red-team found `FactCodec` could normalize numeric top-level fact/payout identities through `Fact.new`; D-120 now validates canonical envelope identity fields before construction and reopens the candidate for broad verification.
- 2026-08-30: live command-boundary red-team found a caller-supplied `DecisionCommit` could carry a mismatched provider/attempt identity or provider request; D-121 now validates the commit against the current operation before recording `attempt_started`, and synchronizes live action state for resolution/restart paths.
- 2026-08-30: collection-boundary red-team found public routing/domain APIs that documented enumerable inputs but required `.map`; D-122 now consumes `#each` consistently across policy, provider opportunity, eligibility, allocation, feasibility and quality boundaries.
- 2026-08-30: provider-boundary red-team found the orchestrator converted arbitrary `StandardError` and `NotImplementedError` failures into synthetic `UNKNOWN` observations, hiding adapter contract violations; D-123 now handles only explicit `ProviderTransportError`, while committed operations remain resumable after surfaced adapter errors.
- 2026-08-30: context-input red-team found policy/opportunity evaluation used `Array(raw)` for payout labels, silently rejecting valid each-only collections; D-124 now consumes the shared collection boundary and preserves scalar String/Symbol labels.
- 2026-08-30: durable fact-boundary red-team found `Fact` could retain a nested each-only object that was accepted in memory but rejected later by `FactCodec`; D-125 now materializes nested enumerables during fact construction, with a direct codec round-trip regression.
- 2026-08-30: application provider-event audit found `Commands#reconcile_provider_event` compared a normalized observation with the raw whitespace-padded provider ID; D-126 now canonicalizes the ID before invoking the provider normalizer, with an end-to-end reconciliation regression.
- 2026-08-30: financial command-boundary audit found reversal settlement/conflict comparisons used raw provider and operation IDs even though the reversal value normalized them; D-128 canonicalizes both identities before linkage, aggregation and idempotent repeat checks, with a focused regression.
- 2026-08-30: application/query audit found payout lookup, resume/policy lookup and audit filtering used raw payout IDs although `PayoutIntent` stores trimmed identity; D-129 canonicalizes public payout identity across those paths, with query/history regression coverage.
- 2026-08-30: replay projection audit found direct capacity/throughput/allocation/lifecycle reads could address equivalent padded provider or operation identities differently from fact application; D-144 canonicalizes both replay application and lookup keys, with focused projection regressions.
- 2026-08-30: analytics identity audit found provider/operation attribution, target and policy-scope maps could be split by raw fact payload identity; D-145 canonicalizes those maps and rejects duplicate canonicalized targets, with live/replay analytics regressions.
- 2026-08-30: lifecycle seam audit found `LifecycleLedger` phase changes still used a raw `to_s` identity boundary; D-146 canonicalizes operation lookup and phase-change IDs and rejects blank identities, with focused reducer regressions.
- 2026-08-30: health admission audit found probe owners could be stored with surrounding whitespace and exposure flags accepted truthy non-Booleans; D-147 canonicalizes probe-owner identity, rejects blank health snapshot providers and validates exposure flags before state mutation.
- 2026-08-30: policy-resolution audit found `PolicyRegistry` lookup and scope matching used raw string coercion; D-148 canonicalizes non-empty id/epoch/scope inputs so public policy fetch and intent resolution share stored policy identity.
- 2026-08-30: HTTP provider-boundary audit found `HttpApp` accepted a normalizer object without an executable `#normalize` method and deferred the failure to the first webhook; D-149 validates the configured normalizer at construction and adds a fail-fast regression.
- 2026-08-30: health-admission audit found `ProviderHealthSnapshot` accepted malformed counters, zero/non-integer probe limits and impossible in-flight probe counts; D-150 validates the typed counter/limit boundary and rejects impossible exposure state before projection use.
- 2026-08-30: collection-boundary audit found direct `RuntimeFeasibility.new` still called `.map` on reason codes despite the shared each-only contract; D-151 routes that construction through `Collection.to_array` and adds a direct each-only regression.
- 2026-08-30: the same collection audit found public `StaticPolicyInfeasibilityError` metadata still called `.map` directly; D-152 routes policy error reason codes through `Collection.to_array` and adds a direct each-only regression.
- 2026-08-30: analytics replay reductions still used `Array(...)` for provider/reason collections; D-153 routes those lists and allocation-key identity through the shared collection boundary, preserving optional nil-as-empty semantics and rejecting scalar lists, with a fact-view each-only regression.
- 2026-08-30: durable health-probe reservation restore still coerced `attempt_id` with `.to_s`; D-154 routes it through the canonical durable identity validator and adds a noncanonical numeric-identity corruption regression.
- 2026-08-30: recovery-budget red-team checked safe release at the `max_operations` boundary; D-156 adds an end-to-end regression proving no fresh money-moving assignment is created after the hard operation budget is exhausted.
- 2026-08-30: durable append red-team found an opaque journal failure could leave fact visibility unknown while allowing future identity reuse; D-157 marks the store unusable and raises explicit durable corruption instead of continuing without a durable prefix check.
- 2026-08-30: transport/lifecycle red-team found `definitely_not_sent` could be paired with unresolved `pending`/`unknown` plus `safe_to_release`, producing a released operation that could not reroute coherently or restore; D-158 restricts that transport class to lifecycle-terminal/releasable statuses and adds live/restore regressions.
- 2026-08-30: restart-safety red-team found `Coordinator` accepted a write-only journal and therefore could not reconstruct history in a fresh process; D-159 requires a durable journal read-back view before coordinator construction.
- 2026-08-30: durable fault red-team found an optional journal `poison!` hook could mask the explicit corruption error; D-160 keeps the `FactStore` unusable and preserves `DurableCorruptionError` when containment itself fails.
- 2026-08-30: provider-boundary red-team found invalid transport kinds leaked `NoMethodError`; D-161 normalizes result/error/observation kinds to explicit `ArgumentError` input failures.
- 2026-08-30: typed projection red-team found health state/signal/attribution and quality evidence-scope enums leaked `NoMethodError` for non-symbol-like input; D-162 adds explicit enum validators and focused boundary regressions.
- 2026-08-30: eligibility red-team found padded payout context labels were compared without canonical whitespace handling in policy/provider functional checks; D-163 aligns both checks with configured canonical labels and adds an end-to-end eligibility regression.
- 2026-08-30: policy/cohort red-team found static hard-constraint feasibility was not auditable and adapter filtering could silently change the functional denominator; D-164 persists static feasibility and keeps runtime adapter availability in operational admission only.
- 2026-08-30: resume red-team found a missing adapter could be checked before an expired unresolved operation was processed; D-165 expires before resume proposal/deferral and adds the missing-adapter regression.
- 2026-08-30: durable-input red-team found remaining open enum/Hash-key coercion and nested-value paths; D-166 adds closed validators, recursive Float rejection and non-interning durable decode behavior.
- 2026-08-30: clock red-team found elapsed-time decisions needed an explicit monotonic boundary; D-167 persists exact monotonic anchors and translates only legacy wall timestamps at restore.
- 2026-08-30: application-boundary red-team found direct reconciliation could be mistaken for raw provider ingress; D-168 requires typed normalized evidence and keeps raw events behind provider-specific normalizers.
- 2026-08-30: restore identity audit found remaining provider/operation paths still relied on coercive `.to_s`; D-169 hardens canonical durable identity validation and reopens closure until the current tree is fully reverified.
- 2026-08-30: concurrency verification audit found a seed without scheduler-visible per-payout evidence was insufficient for diagnosing interleaving failures; D-170 records the execution trace for assertion and worker failures without retrying or suppressing scheduler-dependent behavior.
- 2026-08-30: projection collection audit found legacy allocation replay still used permissive `Array(...)` conversion for `policy_scope`; D-171 routes that fallback through the shared each-only boundary and rejects scalar wrapping, with focused replay regressions.
- 2026-08-30: replay/analytics identity audit found projection payloads still coerced numeric or arbitrary provider identities with `.to_s`; D-172 adds a String/Symbol boundary before canonicalization and covers capacity, allocation and analytics regressions.
- 2026-08-30: stateful replay audit found lifecycle/health/quality fact paths still passed crafted IDs and context labels into permissive domain normalizers; D-173 applies strict identity ingress across those reducers and policy-like allocation lookups, with focused malformed-fact regressions.
- 2026-08-30: exactness audit found admission restore and supplied capacity traces still accepted Float monotonic anchors; D-174 rejects inexact anchors at the ledger boundary.
- 2026-08-30: durable-schema audit found unknown FactCodec fields could be silently ignored; D-175 makes fact envelopes and tagged values closed schemas.
- 2026-08-30: policy-feasibility audit found share obligations were checked before hard allow/exclude constraints; D-176 evaluates obligations over the hard-eligible target set and records contradictions.
- 2026-08-30: application/provider audit found reconciliation could accept caller-constructed observations; D-177 requires raw input plus an executable provider normalizer and persists no-route deviation causes.
- 2026-08-30: coordinator concentration audit extracted fact-producing operation side effects into `State::OperationCommitter`; D-178 preserves one atomic facade and provider-I/O boundary.
- 2026-08-30: coordinator concentration audit extracted fact-free routing assembly into `Routing::DecisionEvaluator`; D-179 preserves safety/allocation/optimization ordering without a second state owner.
- 2026-08-30: durable-restore audit extracted ordered replay, supplied-catalog validation and reducer error classification into `State::WorkingStateRestorer`; D-180 leaves individual reducers behind the coordinator facade and keeps P0-003 open.
- 2026-08-30: provider-history audit extracted registration/removal/runtime durable fact replay into `State::ProviderCatalogRestorer`; D-181 keeps identity/order checks and transaction ownership in the coordinator.
- 2026-08-30: admission-durability audit extracted capacity reservation/release and throughput-consumption fact replay into `State::AdmissionFactRestorer`; D-182 preserves separate exact money/time resources and keeps payout/lifecycle reducers as the next P0-003 target.
- 2026-08-30: operation-durability audit extracted ownership, attempt-start, reconciliation-block and health-exposure fact replay into `State::OperationFactRestorer`; D-186 preserves operation/phase/probe ordering and leaves the next durable reducer block for P0-003.
- 2026-08-30: provider-evidence audit extracted transport, health, quality and health-transition fact replay into `State::ProviderEvidenceFactRestorer`; D-187 preserves source provenance and transition ordering through coordinator callbacks.
- 2026-08-30: financial-history audit extracted late-success conflict and settlement-reversal replay into `State::FinancialFactRestorer`; D-188 preserves source linkage and reversal bounds without moving ownership into the restorer.
- 2026-08-30: payout-registration audit extracted intent and policy replay into `State::PayoutFactRestorer`; D-189 preserves exact creation anchors, policy identity and static-feasibility binding.
- 2026-08-30: evaluation-replay audit extracted historical opportunity validation into `State::OpportunityEvaluationFactRestorer`; D-190 retains recomputation against current restored catalog/admission/allocation/health/quality state.
- 2026-08-30: decision-replay audit extracted assignment/retry/resolve fact application into `State::DecisionFactRestorer`; D-191 keeps cross-projection trace validators injected from the single atomic coordinator facade.
- 2026-08-30: durable-state audit extracted final restored payout/operation invariant checks and shared release-order validation into `State::RestoredStateValidator`; D-192 keeps dynamic references because restore rebuilds working projections.
- 2026-08-30: decision-replay audit extracted policy/allocation/admission/operation cross-fact proof into `State::DecisionTraceValidator`; D-193 leaves `DecisionFactRestorer` responsible only for validated decision application.
- 2026-08-30: repeated-restart audit found that a persisted `restart_recovery` resolution/retry decision was rejected by fresh-process trace validation; D-194 adds an exact control-plane trace and regression coverage for both status lookup and idempotent retry continuation.
- 2026-08-30: valid post-settlement reversal continuation was only covered through live/replay and corruption paths; D-195 adds a fresh `FileJournal` regression for ordered partial reversals, settlement preservation and exact duplicate idempotency.
- 2026-08-30: admission red-team found live `throughput_reservations` was not populated on commit even though restore rebuilt it from facts; D-196 records operation-linked provider/time anchors in live state and adds live/restored parity coverage.
- 2026-08-30: analytics/API red-team found the application default could omit current pending age; D-197 anchors default analytics to the coordinator clock and adds an explicit HTTP ISO-8601 `as_of` override.
- 2026-08-30: HTTP boundary red-team found unbounded method/path/query/body input; D-198 adds pre-parse limits and sanitized 413 responses with regression coverage.
- 2026-08-30: concurrency review found the high-contention fuzz workers had no common start gate; D-199 adds a shared barrier while retaining scheduler-dependent seed/trace diagnostics instead of claiming a fixed interleaving.
- 2026-08-30: P1-013 audit found the benchmark measured direct orchestration but not the public application facade; D-200 adds a fresh 2,000-operation `Application::Service` throughput run and records it as bounded local evidence.
- 2026-08-30: API red-team found that the audit endpoint returned the complete durable fact history in one response; D-201 adds strict bounded pagination with continuation metadata and rejects invalid/absurd page parameters.
- 2026-08-30: restart evidence audit found that the existing durable tests rebuilt a coordinator in-process but did not cross an actual Ruby process; D-202 adds a child-process continuation regression with durable catalog/policy restoration, the public `Application::Service` surface and original operation identity.
- 2026-08-30: durable replay red-team found that removing an applied pending/unknown observation's matching lifecycle phase could leave a plausible but misleading dispatching/resolving attempt and suppress restart recovery; D-203 binds restored in-flight phase to the latest action and observation chronology for both initial dispatch and post-resolution responses.
- 2026-08-30: lifecycle-state red-team found ownerless defer was visible only as an action while the payout remained `:new` or a stale releasable failure; D-204 makes it a durable `:deferred` state and adds reconsideration/analytics parity coverage.
- 2026-08-30: decision-role red-team found no-route defer used `:recovery` while shared budget-defer branches used `:resolution`; D-205 makes defer role state-dependent and validates it during restore.
- 2026-08-30: domain-boundary review found `DecisionProposal` still accepted non-operation control decisions carrying operation identifiers or invalid roles; D-206 makes those shapes fail fast with direct value-object regressions.
- 2026-08-31: candidate revalidation reran the full test task after the closure documentation update; it remained green at 455 runs with seed `31797`. The varying assertion total is retained as scheduler-sensitive evidence, not hidden by retries.
- 2026-08-31: a fresh current-tree standards/spec review rechecked stale pre-D-196 findings against the present implementation and tests; AC-011, static feasibility, provider normalization, no-route deviation, live throughput parity, unresolved age and bounded-input findings are closed. With no independent local gap remaining, exact CI on a committed/published candidate is the sole external exit gate.

## Decision Log

See `docs/DECISIONS_CURRENT.md`.

## Stop condition

Do not stop because the official TZ is missing.

Stop only when v0.3 earns `VERSION_COMPLETE` or all remaining required product work is genuinely externally blocked under the completion/session policies.
