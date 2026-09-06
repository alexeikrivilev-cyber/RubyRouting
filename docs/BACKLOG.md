# RubyRouting Backlog

This backlog is subordinate to the current Version Goal, SPEC-004 and `docs/exec-plans/active/product-convergence.md`.

Current development is **v0.3 — Product Convergence & Full Routing Product**.

## Current slice evidence

- Post-cleanup baseline is clean on `main` at `1f3500e...`; local canonical matrix and benchmark pass on CRuby 4.0.6.
- `State::FactStore` now owns append-only fact identity/revision/journal delivery behind the coordinator atomic facade; restart continuation is covered by crash, corruption and long-history campaigns, while closure remains open.
- Policy now has distinct per-payout measure limits and exact provider share bounds; allocation emits typed corridor violations and analytics records their cause.
- Admission now has an explicit time-window throughput budget with atomic consumption facts and live/replay snapshots; the durable path restores its consumed tokens and concurrent reservation races are covered.
- `State::AdmissionLedger` now owns concurrent capacity and throughput counters behind the coordinator atomic facade; capacity release and throughput-window expiry remain separate.
- `State::AllocationLedger` now owns keyed primary allocation snapshots and restore/commit progression behind the coordinator atomic facade.
- Ranking is now a separate constrained optimizer stage operating only within allocation-authority ties.
- Decision facts now preserve an immutable optimization trace with allocation admissibility, quality evidence, lexicographic ranking keys and the selected candidate.
- Allocation windows now have explicit policy-epoch and functional opportunity-cohort keys, with matching live/replay/analytics grouping.
- `FileJournal`/`FactCodec` now restore a working coordinator for covered unresolved-operation boundaries, reject truncated/checksum-corrupt history and semantically inconsistent lifecycle/provider/financial facts; crash and long-history campaigns pass.
- Durable coordinator mutations append one fact batch atomically; post-append error ambiguity is reconciled against the journal, while pre-append failures rebuild working projections from the last accepted fact prefix.
- Allocation deviation facts now preserve explicit `none`/`recoverable`/`unavoidable` classification, while the product still has no historical catch-up mode.
- Working restore validates operation linkage and application resume defers safely when an existing owner has no configured adapter.
- `State::LifecycleLedger` now owns operation phase/outcome reduction behind the coordinator facade, with reducer, model and restart regressions.
- `State::ObservationLedger` now owns shared live/restore observation identity, deduplication, authoritative provider ordering and late-success conflict classification; lifecycle effects and facts remain coordinated atomically.
- Durable observation restore rejects noncanonical observation IDs, non-boolean applied/conflict/safe-release flags, invalid sequence/timestamp values and unsupported outcome/transport values before mutation.
- Durable fact-source and batch append boundaries reject non-enumerable input explicitly across `FactStore`, `FactCodec` and `FileJournal`.
- Durable observation restore delegates outcome-to-status reduction to `LifecycleLedger` instead of maintaining a second mapping.
- Provider-catalog replacement now records explicit removal facts; restart restores the live opportunity set without discarding historical admission usage needed to release an unresolved old operation.
- Removed-provider observations preserve valid historical health/quality evidence across restart, while manual health commands reject unknown current providers and durable restore rejects signals that precede registration.
- Durable restore replays provider registration/removal facts in order and rejects provider-dependent facts that precede an active catalog registration; supplied runtime opportunities cannot bypass that history.
- Ambiguous partial durable appends now poison the journal after explicit corruption classification, preventing unsafe fact-identity reuse; complete visible batches remain reconciled.
- Durable restore and live observation/clock boundaries now reject noncanonical provider identities and non-`Time` timestamps instead of deferring corruption to lookup, TTL or analytics.
- Durable decoding also rejects crafted nested floating-point payloads, so exact financial history cannot bypass the encoder through journal corruption.
- `FileJournal` rejects non-object JSON roots before record-kind inspection, so malformed array/scalar/null journal lines cannot leak incidental Ruby type errors instead of the durable-corruption contract.
- Working restore now preserves causal and multiplicity invariants for decision, observation, capacity/health release, throughput, allocation, settlement and economic-conflict facts; duplicate or post-release durable records are rejected instead of mutating financial/admission projections twice.
- Working restore now validates opportunity-evaluation quality, ranking, health-policy, static-policy and previous-outcome traces against the typed state at the same evaluation boundary (D-094).
- Working restore now recomputes assignment allocation/optimization traces from the preceding evaluation and rejects divergent durable rationale (D-095).
- Working restore now cross-checks allocation policy metadata and capacity-reservation linkage against the pinned policy and operation state (D-096).
- Working restore now recomputes recovery classification for resolution decisions and rejects divergent action/reason/reason-code evidence (D-097).
- Working restore now validates non-operation final/defer/no-route decisions, switch-budget evidence and adapter-availability context instead of returning before trace validation (D-098).
- Live and restore assignment paths now share proposal construction and reject divergent reasons, reason codes, deviation cause or recoverability (D-099).
- Working restore now rejects duplicate intent/policy registration, cross-payout policy-scope redefinition, noncanonical policy and operation identities, reused attempt identities, split static-feasibility, provider policy, health-signal policy, operation-phase, probe-attempt, ownership-release, contract, action, reconciliation-expiry and allocation-key evidence; analytics is idempotent for exact duplicate observations. `PolicyRegistry` and available-provider filtering also share the each-only input boundary, while `FactCodec` rejects duplicate Hash entries and noncanonical envelope identity (D-100–D-120). Live interaction commands now validate caller-supplied commit identity and provider request before recording starts (D-121). Public policy/domain/routing collection boundaries now share the same each-only contract (D-122). The orchestrator now accepts only explicit provider transport uncertainty and surfaces adapter contract/programming errors without losing resumable operation state (D-123). Payout context labels use the same boundary during policy/opportunity evaluation, and `PayoutIntent` materializes accepted nested collections for durable encoding (D-124). `Fact` now materializes nested each-only values before codec/journal boundaries (D-125). Provider-event reconciliation now canonicalizes provider IDs before normalization and preserves the core linkage contract (D-126). HTTP normalizer lookup now uses canonical provider IDs and rejects normalized-key collisions (D-127). Reversal linkage now canonicalizes provider and operation IDs before settlement/conflict matching and idempotent repeat checks (D-128). Public payout lookup, policy/resume lookup and audit filtering now canonicalize payout IDs consistently with `PayoutIntent` (D-129), direct replay capacity/throughput snapshots use the same provider identity rule (D-130), public policy accessors/collection reductions now share canonical IDs and each-only input handling (D-131), provider-keyed policy maps reject canonicalization collisions (D-132), authoritative allocation snapshots canonicalize provider identity and reject canonicalized-key collisions (D-133), provider quality snapshots canonicalize provider identity at construction and batch lookup (D-134), allocation decisions canonicalize provider-keyed evidence and reject canonicalized-key collisions (D-135), runtime feasibility canonicalizes attempted/provider sets so padded IDs cannot re-enter recovery (D-136), the allocation chooser canonicalizes candidate/accounting inputs (D-137), the decision engine canonicalizes availability/attempted inputs for resume and fallback (D-138), and constrained optimization canonicalizes direct quality evidence keys and rejects collisions (D-139); the full local matrix is green.
- Observation-derived health, quality and transport facts now carry source payout/observation identity and are validated against the restored provider observation; manual health events remain explicitly source-free.
- Authoritative allocation snapshots now reject empty provider identities at construction, lookup and commit (D-140).
- Direct quality evidence now requires typed snapshots with key/value provider identity alignment, valid counters and canonical context labels (D-141).
- Admission ledgers and capacity/throughput projections now canonicalize provider identity and validate typed counters, budgets and timestamps (D-142).
- Attempt/payout snapshots and decision proposals now reject malformed typed state, canonicalize operation/provider/policy identities, enforce ownership/history linkage and action/role shape (D-143).
- Replay capacity/throughput/allocation/lifecycle projections now canonicalize provider/operation identities in both fact application and public lookup (D-144); analytics uses the same identity rule across attribution, target and policy-scope maps (D-145); the lifecycle ledger phase-change boundary now canonicalizes and rejects blank identities (D-146).
- Health admission now canonicalizes probe-owner identity, rejects blank health snapshot providers and rejects truthy non-Boolean exposure flags before state mutation (D-147).
- Policy registry fetch and intent resolution now canonicalize non-empty policy id/epoch/scope inputs, preventing padded public lookups from diverging from stored policy identity (D-148).
- HTTP application construction now rejects non-executable provider webhook normalizers before exposing the API surface (D-149).
- Provider health snapshots now reject malformed counters, non-positive/non-integer probe limits and impossible in-flight probe counts before health admission state is exposed (D-150).
- Direct runtime-feasibility construction now accepts the shared each-only reason-code input contract (D-151).
- Policy infeasibility error metadata now accepts the shared each-only reason-code input contract (D-152).
- Analytics opportunity/reason-code reductions now consume the shared each-only collection boundary; scalar fact collections are rejected rather than silently counted as provider identities (D-153).
- Durable health-probe reservation restore now rejects noncanonical `attempt_id` values instead of coercing them with `.to_s` (D-154).
- Normalized provider observations now reject ambiguous transport paired with safe release and definitely-not-sent transport paired with settlement (D-155).
- Recovery now has an end-to-end regression proving safe release cannot bypass an exhausted `max_operations` budget (D-156).
- Opaque journal append failures now fail closed and make `FactStore` unusable when durable visibility cannot be established, preventing fact-identity reuse (D-157).
- Definitely-not-sent transport observations now reject unresolved `pending`/`unknown` normalized outcomes before lifecycle mutation, keeping live recovery and durable restore aligned (D-158).
- Durable `Coordinator` construction now rejects write-only journals that cannot provide a read-back fact history for fresh-process recovery (D-159).
- Journal poison-hook failures no longer mask the primary `DurableCorruptionError`; the `FactStore` remains fail-closed (D-160).
- Provider transport result/error/observation constructors now reject invalid kinds with explicit `ArgumentError` instead of leaking `NoMethodError` (D-161).
- Health state/signal/attribution and quality evidence-scope boundaries now reject non-symbol-like enum inputs with explicit `ArgumentError` (D-162).
- Policy/provider functional eligibility now canonicalizes payout context label whitespace consistently with configured labels (D-163).
- Static policy feasibility now records hard-constraint contradictions, while missing adapters remain operational exclusions from a preserved functional cohort (D-164).
- Resume processes contract expiry before adapter-availability deferral; typed normalized-evidence ingress, closed durable enum/key boundaries, monotonic elapsed anchors, canonical restore identities, diagnostic concurrency traces and replay identity/collection-shape validation are now implemented (D-165–D-173).
- Ledger monotonic anchors now reject Float input at restore and capacity-trace boundaries; `FactCodec` rejects unknown envelope/tagged-value fields; static share feasibility is checked after hard constraints; application reconciliation requires raw provider input plus an executable provider normalizer; and no-route deviations are included in analytics (D-174–D-177).
- Fact-producing assignment, retry/resolve, phase-transition and ownership-release side effects now have an explicit `State::OperationCommitter` seam; coordinator atomicity and provider-I/O boundaries remain unchanged (D-178).
- Fact-free opportunity/admission/eligibility/allocation/constrained-decision assembly now has an explicit `Routing::DecisionEvaluator` seam; it does not publish facts or reserve business resources (D-179).
- Ordered durable-prefix replay, supplied runtime-catalog validation and reducer-error classification now have an explicit `State::WorkingStateRestorer` seam; individual fact reducers remain behind the coordinator atomic facade (D-180).
- Provider-definition/runtime durable fact replay now has an explicit `State::ProviderCatalogRestorer` seam with direct catalog/history contract coverage; remaining routing reducers stayed behind the coordinator atomic facade at that slice (D-181).
- Capacity reservation/release and throughput-consumption durable fact replay now has an explicit `State::AdmissionFactRestorer` seam with exact money/time and operation-linkage contract coverage (D-182).
- Ownership, attempt-start, reconciliation-block and health-exposure durable fact replay now has an explicit `State::OperationFactRestorer` seam with operation/phase/ownership and probe-order contract coverage (D-186).
- Provider-derived transport, health, quality and health-transition durable fact replay now has an explicit `State::ProviderEvidenceFactRestorer` seam with observation-provenance and transition-order coverage (D-187).
- Late-success conflict and settlement-reversal durable fact replay now has an explicit `State::FinancialFactRestorer` seam with source-linkage and reversal-bound coverage (D-188).
- Intent and policy registration durable fact replay now has an explicit `State::PayoutFactRestorer` seam with creation-anchor, policy-identity and static-feasibility coverage (D-189).
- Historical opportunity-evaluation and assignment/retry/resolve decision replay now have explicit `State::OpportunityEvaluationFactRestorer` and `State::DecisionFactRestorer` seams with recomputation and cross-projection validation coverage (D-190–D-191).
- Final restored payout/operation lifecycle, reservation linkage and release-order checks now have an explicit `State::RestoredStateValidator` seam; policy/allocation/admission/operation decision proof now has an explicit `State::DecisionTraceValidator` seam (D-192–D-193).
- Restart-generated resolution/retry decisions now have an explicitly validated `restart_recovery` trace and survive another fresh-process restore before provider I/O (D-194).
- Valid post-settlement partial reversals now survive fresh `FileJournal` working restore with settlement linkage, ordered amount conservation, analytics parity and exact duplicate idempotency (D-195).
- Live payout state now records the same operation-linked throughput reservation anchors as its durable `throughput_consumed` fact; current and restored admission projections are aligned (D-196).
- Application analytics now exposes pending/UNKNOWN/reconciliation age at the coordinator clock by default, with an explicit ISO-8601 HTTP `as_of` override (D-197).
- HTTP method/path/query/body inputs are bounded before parsing and oversized requests return a sanitized 413 response (D-198).
- The seeded high-contention fuzz harness now starts workers through a shared barrier; scheduler-dependent runs retain seed/trace diagnostics and do not claim a fixed interleaving (D-199).
- The baseline benchmark now measures the public `Application::Service` path separately over 2,000 operations; the result is bounded local evidence, not an API capacity claim (D-200).
- The HTTP audit route now serves bounded pages with strict `limit`/`offset` validation and explicit continuation metadata instead of returning the full durable journal in one response (D-201).
- A restart regression now uses an actual separate Ruby process with no runtime opportunity/policy catalog input and continues the durable owner through the public `Application::Service` on the original operation identity (D-202).
- Durable replay now rejects an applied pending/unknown observation whose matching lifecycle phase transition is missing, preventing an inconsistent `dispatching` attempt from suppressing restart recovery (D-203).
- Ownerless non-operation defer decisions now produce the explicit `:deferred` payout status in live state, durable restore and analytics; owner-held UNKNOWN/TTL defers retain ownership and unresolved status (D-204).
- Durable decision-role validation now accepts only `:recovery` for ownerless defer and `:resolution` for owner-held defer; production budget and no-route branches emit that same shape (D-205).
- `DecisionProposal` now rejects invalid non-operation control roles and operation identifiers at construction, keeping the domain value-object shape aligned with durable decision validation (D-206).
- Provider/capability/operation-contract/outcome Boolean inputs now reject truthy non-Boolean values, including crafted durable provider definitions.
- Policy registry activation now follows explicit registration order rather than guessing epoch recency from opaque strings; numeric-looking `"9"`/`"10"` and explicit reactivation are covered.
- `State::ProviderCatalogLedger` now owns the current opportunity map and ordered provider-registration/removal timeline; its monotonic sequence guard prevents a caller from corrupting historical currentness.
- Restore and live provider-catalog entry points now reject non-enumerable opportunity input explicitly instead of leaking an internal `NoMethodError`.
- Shared collection-boundary conversion consumes `#each` directly, covering valid each-only enumerable inputs across durable facts, provider catalog, projections and demo configuration.
- A reproducible 10k coordinator lifecycle harness now runs through the same application/provider path; latest sequential local run: 22.6157 s / 442.2 ops/s / 140,002 facts.
- `Application::Service` now separates commands from queries, and `HttpApp` delegates to it with provider-specific webhook normalization and sanitized errors.
- `Demo::Scenario` now demonstrates primary safe failure followed by recovery success through the canonical application/provider path; the provider is explicitly simulated.
- Current local matrix after D-206: test 455/9,219 (seed 53445), property 4/1,210 (seed 51414), model 3/2,941 (seed 33545), concurrency 12/946 (seed 14725), fault 240/3,352 (seed 56648), all zero failures/errors/skips. Benchmark/load/degradation/demo and fresh closure evidence are recorded in the active ExecPlan; exact-revision CI and final closure decision remain open. Scheduler-dependent fuzz assertion totals may vary while failures retain seed/trace diagnostics. P0-003 coordinator decomposition now includes `OperationCommitter`, `DecisionEvaluator`, `WorkingStateRestorer`, `ProviderCatalogRestorer`, `AdmissionFactRestorer`, `OperationFactRestorer`, `ProviderEvidenceFactRestorer`, `FinancialFactRestorer`, `PayoutFactRestorer`, `OpportunityEvaluationFactRestorer`, `DecisionTraceValidator`, `DecisionFactRestorer` and `RestoredStateValidator`; the coordinator remains the atomic facade. Historical catch-up/debt is explicitly disabled by D-059, not silently omitted.

## NOW / P0 — correctness and coherence

### P0-001 — clean post-feature-burst baseline

Remove/demote disconnected or misleading production modules and false v1.0 claims. Run the complete verification matrix afterward and fix any legitimate coupling exposed by cleanup.

Progress: the post-cleanup baseline was recorded before convergence edits; the current root require graph contains the supported product modules only, misleading completion claims were removed or marked historical, and the full local matrix remains green. Exact-revision CI and final closure review remain open.

### P0-002 — canonical routing pipeline

Every production module must have one explicit responsibility in:

`Intent -> Policy -> Opportunity -> Admission -> Allocation -> Optimization -> Atomic Commit -> Provider -> Observation -> Lifecycle/Recovery -> Durable State -> Analytics/API`.

Remove duplicate/unreachable alternate paths.

Progress: the reachable product path follows the canonical intent/policy/opportunity/admission/allocation/optimization/commit/provider/observation/lifecycle/durable/analytics flow; application, demo and projection layers delegate to the same coordinator/provider contracts. The current candidate still requires exact-revision CI/closure evidence.

### P0-003 — coordinator responsibility decomposition

`State::Coordinator` remains the atomic transaction facade but should no longer be the final owner of every policy/allocation/capacity/health/lifecycle concern.

Extract the highest-value internal responsibility incrementally with behavior/replay/concurrency equivalence tests.

Progress: append-only fact identity/revision/journal delivery extracted to `State::FactStore`, current provider catalog and ordered registration timeline extracted to `State::ProviderCatalogLedger`, capacity/throughput exposure state extracted to `State::AdmissionLedger`, keyed primary allocation state extracted to `State::AllocationLedger`, operation phase/outcome reduction extracted to `State::LifecycleLedger`, fact-producing operation assignment/retry/resolve/release side effects extracted to `State::OperationCommitter`, shared observation identity/order extracted to `State::ObservationLedger`, fact-free routing evaluation extracted to `Routing::DecisionEvaluator`, ordered durable replay orchestration extracted to `State::WorkingStateRestorer`, provider definition/runtime fact replay extracted to `State::ProviderCatalogRestorer`, capacity/throughput fact replay extracted to `State::AdmissionFactRestorer`, ownership/dispatch/reconciliation/probe fact replay extracted to `State::OperationFactRestorer`, provider evidence fact replay extracted to `State::ProviderEvidenceFactRestorer`, conflict/reversal fact replay extracted to `State::FinancialFactRestorer`, intent/policy replay extracted to `State::PayoutFactRestorer`, historical opportunity evaluation replay extracted to `State::OpportunityEvaluationFactRestorer`, assignment/recovery decision application extracted to `State::DecisionFactRestorer`, cross-fact decision proof extracted to `State::DecisionTraceValidator`, and final restored-state/release-order checks extracted to `State::RestoredStateValidator`. `Routing::HealthController` is already the focused health state seam; D-060 records why no redundant wrapper is added. The coordinator remains the single atomic facade and still owns low-level identity/order/corruption helpers that are shared by multiple fact families; this is now a narrower, evidence-driven follow-up rather than a broad reducer concentration claim.

### P0-004 — durability must preserve economic safety across restart

`FileJournal` is now a minimal crash-recovery path with contract tests for unresolved ownership, operation contract/idempotency, policy binding, dedup/order, capacity/throughput reservations and semantic lifecycle/provider/financial linkage. Working restore rejects unsupported facts and inconsistent final states. Deterministic crash, corruption, long-history and long state-machine campaigns now pass; keep the item open for CI/closure review.

Corrupted/truncated history must be explicit, not silently ignored.

### P0-005 — provider normalization boundary

Raw provider/webhook input must never directly assert trusted `safe_to_release`, provider attribution or final financial semantics. Provider-specific adapters/normalizers own this mapping.

Progress: provider adapters return normalized observations or explicit transport uncertainty, while HTTP/application webhook input crosses a provider-specific normalizer before entering the core. D-123, D-126, D-127, D-149, D-168 and D-177 cover contract failures, canonical provider identity, normalized lookup collisions, fail-fast executable normalizer configuration and stable raw-plus-normalizer application ingress; exact-revision CI/closure review remains open.

### P0-006 — optimization cannot override allocation contract

Replace any arbitrary weighted-sum provider choice with constrained/lexicographic optimization operating only inside the allocation-admissible safe set.

Progress: `Routing::ConstrainedOptimizer` now ranks only candidates tied on share-obligation violations and exact allocation discrepancy; allocation and optimization are separate stages. Quality confidence/maturity, recovery probing guardrails and the complete per-candidate optimization trace are now persisted; current optimizer, benchmark and dedicated load evidence is recorded without making an unexecuted 100k-scale claim.

### P0-007 — deterministic fault verification

Remove unseeded/global-random correctness tests. Generated/fuzz/chaos failures must be reproducible by seed/trace.

Progress: all current generated property/model/concurrency/fault campaigns use explicit fixed seeds or deterministic scenario tables, with seed/history context in assertions; keep the item open for future-campaign discipline and closure review.

## NOW / P1 — full product mechanics

### P1-001 — universal policy model

Complete policy semantics for:

- count/volume strategy;
- target shares/weights;
- scope/segment;
- policy identity/epoch/fingerprint;
- accounting point;
- explicit window;
- tolerance/admissible corridor;
- provider share min/max obligations;
- hard/soft constraints;
- static/runtime infeasibility;
- recovery policy;
- optimization policy.

Explicitly separate provider share obligations from per-payout amount eligibility limits.

Progress: separation, exact share-bound/corridor mechanics, explicit windows, static/runtime infeasibility and explicit deviation recoverability evidence are implemented; D-059 explicitly keeps historical debt/catch-up disabled in v0.3. D-196 closes the live-versus-restored throughput-reservation projection gap.

### P1-002 — allocation ledger and deviation/debt semantics

Implement exact opportunity-aware allocation accounting with committed/in-flight work, large indivisible payouts, runtime deviation attribution and bounded recoverable debt/catch-up where enabled.

Progress: committed/in-flight accounting, opportunity cohorts, typed recoverability and an extracted `State::AllocationLedger` are present; no historical debt/catch-up policy is enabled by D-059, so recovery cannot trigger a catch-up burst.

### P1-003 — operational admission controller

Unify hard live admission using:

- enabled/availability;
- concurrent slots/exposure;
- amount exposure;
- throughput/rate limits;
- health/quarantine/probing.

Do not conflate concurrent exposure with time-based throughput quota.

Progress: `AdmissionLedger` owns concurrent capacity and throughput exposure while health remains a separate hard gate; `ThroughputBudget` consumes immutable time-window tokens on operation commit, exposes live/replay projections, and intentionally does not release tokens on safe failure. Fresh-process restoration is implemented for the covered FileJournal path; crash campaigns remain P0-004/P1-007 work.

### P1-004 — provider health and slow quality separation

Keep fast operational health separate from slow quality/reliability estimation. Add context/cohort, maturity and confidence semantics before adaptive routing.

Progress: `QualityController` now records only provider-attributed success/failure terminal evidence, exposes exact score/confidence/maturity, and uses context-cohort evidence with mature-global fallback while remaining independent of fast health.

### P1-005 — constrained smart optimizer

Within the safe allocation-admissible set, rank deterministically using reliability/quality, then cost/latency/priority according to explicit policy. Add bounded traffic-ramp/stability guardrails where useful.

Progress: deterministic staged optimizer seam includes optional quality score/confidence before cost/latency/priority, still only within allocation ties; context/cohort semantics and the immutable per-candidate stage trace are implemented. Health recovery uses bounded concurrent probing and waits for all probe reservations before full exposure.

### P1-006 — provider lifecycle/reconciliation completeness

Consolidate dispatch, UNKNOWN/pending, status resolution, idempotent retry, fallback, budgets, deadline/TTL, late success, return/reversal, conflict/remediation and manual reconciliation semantics.

Progress: the canonical provider port, normalized transport outcomes, operation-scoped contracts, guarded dispatch/resolution/fallback, TTL reconciliation blocking, late conflicts, reversals and application reconciliation command are integrated and covered. D-195 verifies ordered partial reversal continuation through a fresh durable working process and exact duplicate idempotency. The deterministic scripted simulator now covers queued delayed callbacks, exact duplicates, provider-sequence reordering and reversal construction; the scenario matrix and seeded fault campaign cover the complete current lifecycle envelope.

### P1-007 — restart-safe durable store

Choose the smallest hackathon-compatible durable mechanism that can provide the required atomic/recovery contract. Build contract tests first; implementation choice is secondary.

Progress: tagged `FactCodec` plus `FileJournal` restore a working coordinator for covered unresolved-operation boundaries, with batch append and failure reconciliation; D-195 adds valid fresh-process continuation for ordered partial settlement reversals and exact duplicate idempotency; D-196 keeps the live operation-linked throughput reservation aligned with the restored state. A seeded six-scenario crash-boundary campaign verifies fresh-process continuation or conservative preservation at required lifecycle boundaries, a 14-mutation corruption matrix verifies explicit rejection of malformed history, a fixed 1,000-payout campaign verifies long-history replay/restore equivalence and a 64-history state-machine campaign verifies repeated lifecycle/restart parity. CI/closure review remains open.

The durable restore now links each health-state transition to the immediately preceding health signal (D-074), rejecting forged predecessor, missing and interleaved transition facts. Probe-reservation restore rejects duplicate or post-release reservation facts and requires a committed owner-free operation (D-075).

### P1-008 — causal analytics and decision audit

Provide target vs actual count/volume, opportunity/assignment/attempt/settlement, first/eventual success, fallback recovery, provider-attributable failure, unresolved age, amplification, exclusion/deviation causes including recoverability, conflict/reversal and full decision trace.

Progress: live/replay analytics expose these dimensions, including runtime infeasibility and recoverable/unavoidable deviation, with distinct fallback-payout, successful-fallback-recovery and recovery-operation metrics; economic roles remain stable across idempotent resolution retries; decision facts retain allocation and optimization traces; D-197 exposes current unresolved age through the application query/API surface; the fixed 1,000-payout campaign verifies long-history conservation and replay equivalence.

### P1-009 — application command/query surface

Create stable use cases for submit/get/resume/reconcile/config/query. `Application::Service` now provides this command/query boundary; external API remains an adapter over it.

Progress: `Application::Commands`, `Application::Queries` and `Application::Service` expose the stable mutation/read surface, with HTTP delegating to it and scenario coverage for submit, resume, provider-normalized reconcile, configuration and audit/query behavior. D-129 keeps padded public payout lookup/history identities aligned with stored `PayoutIntent` identity; D-177 prevents callers from injecting a hand-built `ProviderObservation` through the stable command surface; D-197 exposes current unresolved age, D-198 bounds transport input and D-201 bounds audit responses with explicit pagination. The external shape remains provisional pending the official TZ.

### P1-010 — safe API/webhook/demo surface

The generic pre-TZ minimum is implemented and tested: `Application::HttpApp`
delegates to the service, provider callbacks pass through provider-specific
normalization, internal errors/backtraces are not exposed, and `Demo::Scenario`
is a tested simulated fallback path. Audit facts are exposed through bounded
pages with explicit continuation metadata. The final external API shape remains
provisional until the official TZ rather than becoming a second routing model.

### P1-011 — deterministic simulator

Provide scriptable providers supporting success, safe failure, terminal recipient failure, UNKNOWN, pending, delayed/duplicate/out-of-order callbacks, status lookup, idempotent retry, availability/capacity changes, reversal and late conflict.

Progress: `TestSupport::Simulator::ScriptedProvider` now queues deterministic delayed callbacks, can drain them FIFO/LIFO, re-deliver the exact observation identity, and construct a settlement reversal linked to its own settled operation. Existing scripted steps cover status lookup, idempotent retry and normalized failure classes; the deterministic scenario matrix and seeded fault trace exercise the supported lifecycle envelope.

### P1-012 — deep restart/concurrency/fault campaign

Add controlled races and crash-at-boundary scenarios covering ownership, reservations, policy change, provider state, reconciliation and durable continuation.

- D-140 adds regression coverage for empty allocation provider identities; the exact-revision CI/final closure decision remains open.
- D-141 adds regression coverage for typed/misaligned quality evidence and invalid counters/context labels; the exact-revision CI/final closure decision remains open.
- D-142 adds direct admission-ledger and projection regressions for canonical provider buckets and malformed snapshot values; the exact-revision CI/final closure decision remains open.
- D-144 adds replay identity regressions; D-145 adds analytics attribution/target identity regressions; D-146 adds lifecycle-ledger phase-change identity regressions. The exact-revision CI/final closure decision remains open.
- D-147 adds health probe-owner, snapshot-provider and Boolean exposure-flag regressions. The exact-revision CI/final closure decision remains open.
- D-148 adds policy-registry canonical lookup and blank-identity regressions. The exact-revision CI/final closure decision remains open.
- D-149 adds fail-fast HTTP normalizer configuration validation and a regression for non-executable provider webhook adapters. The exact-revision CI/final closure decision remains open.
- D-150 adds typed health-snapshot counter/limit validation and an impossible probe-exposure regression. The exact-revision CI/final closure decision remains open.
- D-151 adds a direct each-only runtime-feasibility reason-code regression. The exact-revision CI/final closure decision remains open.
- D-152 adds a direct each-only policy-infeasibility reason-code regression. The exact-revision CI/final closure decision remains open.
- D-154 adds canonical durable `attempt_id` validation for health-probe reservation restore. The exact-revision CI/final closure decision remains open.
- D-155 adds normalized transport/outcome safety validation and durable mismatch regression coverage. The exact-revision CI/final closure decision remains open.
- D-156 adds an end-to-end hard recovery-operation-budget regression after safe release. The exact-revision CI/final closure decision remains open.
- D-157 adds fail-closed handling for unobservable durable append outcomes so the store cannot reuse fact identities without a verified durable prefix. The exact-revision CI/final closure decision remains open.
- D-158 adds unresolved definitely-not-sent transport/outcome rejection plus live and durable-restore regressions. The exact-revision CI/final closure decision remains open.
- D-159 adds a durable-journal contract regression preventing restart-safe `Coordinator` construction without a read-back fact view. The exact-revision CI/final closure decision remains open.
- D-160 adds a poison-hook failure regression preserving explicit durable corruption and unusable-store behavior. The exact-revision CI/final closure decision remains open.
- D-161 adds provider transport-kind input-boundary regressions across result, error and observation values. The exact-revision CI/final closure decision remains open.
- D-162 adds health/quality enum input-boundary regressions with explicit `ArgumentError` behavior. The exact-revision CI/final closure decision remains open.
- D-163 adds a padded context-label eligibility regression across policy and provider functional checks. The exact-revision CI/final closure decision remains open.
- D-164 adds static-feasibility and functional-cohort/operational-availability regressions; D-165 adds resume-expiry-before-missing-adapter coverage; D-166–D-169 add closed enum/Hash-key, recursive durable-value, monotonic elapsed-time and canonical restore-identity regressions; D-171 adds replay allocation collection-shape validation; D-172 rejects non-symbol-like replay/analytics identity payloads; D-173 extends that strict boundary across replay lifecycle/health/quality ingress; D-174–D-177 add exact monotonic ledger boundaries, closed durable schemas, post-hard-constraint share feasibility, normalized application reconcile ingress and no-route deviation analytics; D-178–D-182 extract operation-commit side effects, fact-free decision evaluation, ordered durable-restore orchestration, provider catalog fact replay and admission fact replay from the coordinator. The exact-revision CI/final closure decision remains open.
- D-170 adds per-payout execution traces to high-contention invariant failures, preserving seed/trace evidence without masking scheduler-dependent failures. D-171 applies the shared each-only collection boundary to legacy replay allocation keys and rejects scalar wrapping. The exact-revision CI/final closure decision remains open.
- D-187–D-193 extract provider-evidence, financial, payout-registration, opportunity-evaluation, decision application, decision-trace validation and final restored-state validation seams, preserving the coordinator's atomic facade. D-194 adds a repeated-restart regression for the control-plane decision emitted while resuming a dispatching operation; D-195 adds valid fresh-process partial-reversal continuation and duplicate-idempotency coverage; D-196–D-198 add live/restored throughput parity, current unresolved-age analytics and bounded HTTP input; D-199 adds a controlled worker start barrier to the seeded contention harness; D-200 adds public application-service throughput evidence; D-201 adds bounded, explicitly paginated audit responses; D-202 adds actual separate-process restart continuation through the public application facade; D-203 closes the missing lifecycle phase/outcome replay invariant. The exact-revision CI/final closure decision remains open.

- Progress: controlled race, deterministic contention, failure-injection, semantic corruption/linkage tests, a seeded six-scenario crash-boundary matrix, a 14-mutation corruption campaign, a fixed 1,000-payout replay/restore conservation campaign, a fixed-seed 96-history fault matrix, a fixed-seed 64-history long state-machine campaign and ordered provider-catalog/operation-fact restore checks are present; D-084–D-153 add causal conflict, feasibility-cohort, atomic assignment-bundle, exact allocation-snapshot, exact admission-capacity-trace, health-source, allocation-key, provider-definition, throughput-gate, recomputed historical-feasibility, exact decision-context, recomputed assignment-rationale, allocation policy/reservation linkage, recovery-classification, non-operation decision, shared assignment-proposal, durable multiplicity, policy-context, operation-causal, operation-contract, action-causal, duplicate-observation, reconciliation-expiry, cross-payout policy-identity, shared-collection-boundary, canonical-policy-identity, canonical-operation-identity, per-payout-attempt-uniqueness, available-provider-collection, duplicate-Hash-entry, exact-key, durable-envelope, explicit provider-error-boundary, context-label-collection, fact-nested-collection, provider-event-identity, HTTP-normalizer-identity, reversal-linkage-identity, payout-query-identity, replay-provider-snapshot-identity, policy-provider-boundary, policy-map-collision, allocation-snapshot-identity, quality-snapshot-identity, allocation-decision-identity, runtime-feasibility-identity, allocation-chooser-identity, decision-engine-provider-identity, optimizer-quality-identity, typed admission projection, typed payout/attempt snapshot and decision-shape checks, replay-identity, analytics-identity, lifecycle-ledger identity, health-admission identity, policy-registry identity, fail-fast HTTP normalizer configuration and typed health-snapshot counter/limit checks, direct each-only runtime-feasibility construction, direct each-only policy-infeasibility error construction and analytics fact-collection reductions; D-154–D-163 add canonical health-reservation identity, transport/outcome safety, hard recovery budget, fail-closed durable append, unresolved definitely-not-sent, restart-safe journal-contract, poison-hook containment, provider transport-kind, health/quality enum and context-label eligibility checks; D-164–D-172 add static-feasibility/cohort, resume-expiry, closed durable-input, monotonic-clock, canonical-identity, reproducible concurrency-trace, replay collection-shape and projection-identity checks; D-174–D-186 add exact monotonic ledger boundaries, closed durable schemas, post-hard-constraint share feasibility, normalized application reconcile ingress, no-route deviation analytics, and operation-commit, decision-evaluation, ordered restore, provider-catalog, admission and operation fact-replay seams; D-194 adds repeated-restart control-plane decision continuation; D-195–D-201 add fresh-process reversal continuation, live/restored throughput parity, coordinator-clock analytics age, bounded HTTP inputs, synchronized contention starts, public application-service throughput evidence and bounded paginated audit responses; D-202–D-206 add actual separate-process public-facade continuation, in-flight phase/outcome chronology validation, explicit ownerless deferred state, state-dependent defer roles and fail-fast decision-proposal shape checks. The fresh A–L closure attempt found no material locally-solvable gap; exact-revision CI and the final VERSION_COMPLETE decision remain open.

### P1-013 — truthful performance/load campaign

Measure realistic allocation/lifecycle/replay/application throughput and memory. Run 10k/100k campaigns only in a dedicated load harness when the documentation claims those scales.

Progress: baseline benchmark and dedicated 10k coordinator lifecycle harness are reproducible; the latest sequential 2,000-payout degradation run measured 2,247 attempts, 228 fallback payouts, 228 successful fallback recoveries, maximum 3 attempts/payout, 78,420,392-byte ObjectSpace delta and 805,980 live-slot delta on CRuby 4.0.6. The latest 10k run measured 22.6157 s / 442.2 ops/s / 140,002 facts; the benchmark measured 20,000 allocation ops at 10,227.4 ops/s, 2,000 lifecycle ops at 510.4 ops/s, 2,000 application-service ops at 534.1 ops/s and 250 replay cases at 10.6 ops/s. No 100k scale claim is made. Current D-206 evidence is recorded in the active ExecPlan.
- D-206 follow-up: the current matrix is test 455/9,219 (seed 53445), property 4/1,210 (seed 51414), model 3/2,941 (seed 33545), concurrency 12/946 (seed 14725) and fault 240/3,352 (seed 56648), all with zero failures/errors/skips. Degradation completed in 4.4953 s; benchmark/load/replay metrics are the bounded figures above, and the fresh A–L closure review is recorded in the active ExecPlan. Exact-revision CI remains unavailable for the uncommitted candidate, so this is not a VERSION_COMPLETE decision.

## P2 — only after core product is coherent

### P2-001 — statistical quality/adaptive routing

Consider contextual/non-stationary bandits only after deterministic quality/confidence and safety envelopes are proven and measurable benefit is plausible.

### P2-002 — correlated failure-domain inference

Optional route/rail/downstream correlation after explicit provider/route context exists.

### P2-003 — advanced counterfactual analytics

Off-policy evaluation only with logged overlap/exploration and explicit uncertainty.

## BLOCKED — official TZ specifics only

The following await authoritative TZ but do not block v0.3 product construction:

- exact official allocation denominator/accounting/window/tolerance defaults;
- exact input/output/API/judge contract;
- official provider/status/idempotency simulator semantics;
- runtime/dependency limits;
- official performance/scoring gates;
- exact required analytics/UI fields;
- official currencies/FX behavior.

## Official-TZ reconciliation questions

1. What does each percentage measure: primary assignment, attempt, acceptance or settlement?
2. What is the denominator/scope/window?
3. Are both count and volume strategies required simultaneously/configurably?
4. What constraints/limits exist per provider?
5. Which payout fields determine eligibility?
6. What are the exact timeout/idempotency/status-resolution semantics?
7. Which failures are terminal/retryable/provider/recipient/downstream?
8. Can callbacks be duplicate/delayed/out-of-order?
9. Can success later return/reverse?
10. What exact analytics are judged?
11. Is concurrency/restart tested?
12. What interface/runtime/dependency constraints apply?
13. What scoring rewards success-rate/cost/latency adaptation?

## Maintenance rules

- NOW/P0/P1 items cannot be moved to LATER merely to close the version.
- Remove duplicate backlog entries rather than accumulating variants.
- A feature removed during cleanup can be reintroduced only through a current product requirement and canonical architecture boundary.
- Every material bug gets a deterministic regression.
