# ExecPlan — v0.3.10 Public Boundary & Recovery Temporal Integrity

Status: **VERSION_COMPLETE**.

Opening HEAD: `7ab9bd6884146a64fefe47ae0e05baef623a757d`.

Governing spec: `specifications/014-pre-tz-public-boundary-recovery-temporal-integrity.md`.

Protected completed baseline: v0.3.9 / SPEC-013. Last material code closure `543f7b4f00d37e42441245b1e26a74e943f0e525`; docs-only closure/index HEAD `7ab9bd6884146a64fefe47ae0e05baef623a757d`; exact-head Actions run `33693537201` green.

Material code closure: `e7c9540ba68f63e99426aebc4d0ac3b3d2b61238`.

Verified code-bearing closure tree: `ba00d7dc0d77e328d300bfc9418b96ebe89ede70`.
Exact-head Actions for that tree: run `33740328533`, green.

## Purpose

Resolve the fresh post-v0.3.9 findings at the public/recovery boundary while preserving the mature economic kernel. This is not a generic refactor cycle.

## Operating loop

`orient -> inspect exact code/CI -> reproduce or falsify -> state invariant -> implement smallest coherent slice -> focused verify -> adjacent skeptical review -> broad verify -> update plan/backlog/decisions -> coherent checkpoint -> next highest-value unblocked slice`.

Do not stop at a file, class, endpoint, regression, commit, green suite or completed phase.

## Phase 0 — exact re-orientation

Before production edits:

- verify exact `main` and current CI;
- inspect actual `HttpApp` payout DTO, `NormalizedOutcome`, public audit projection, Orchestrator provider boundary, Coordinator due-work/restart paths, RecoveryExecutor, restore/replay and current tests;
- rerun or rebuild each opening reproducer against current HEAD;
- reconcile any divergence between SPEC-014 assumptions and code before implementing.

Any financial P0 preempts all phases.

## Phase 1 — public payout privacy — VERIFIED

Reproduce provider-controlled `message` / reference exposure through real HTTP. Define an allowlisted public outcome projection and remove accidental diagnostic leakage without deleting internal durable evidence.

The real HTTP reproducer confirmed `message`, observation/provider reference and outcome reference were exposed in a successful submit response. `HttpApp#outcome_payload` now exposes only the allowlisted `status`, `attribution` and `safe_to_release` fields. Submit, direct GET and resume responses are covered by a deterministic regression; internal current outcome and both durable `provider_observed` payloads still retain the richer evidence. Focused HTTP/audit/orchestrator/replay adjacency is green (`40/292`), and the original reproducer now reports no public secret values.

Acceptance: submit/GET/resume public responses, audit redaction, internal snapshots and durable evidence agree.

## Phase 2 — raw-failure historical scan time — VERIFIED

The controlled-clock reproducers confirmed two future-visibility mismatches: a raw provider failure marker at `T2` and a `reconciliation_blocked` marker at `T3` were both exposed by `due_work(as_of: T1)`. `Coordinator#provider_execution_failure_work_for` now validates `failed_at`, and both reconciliation due-work branches now require the persisted `blocked_at <= as_of` boundary. Current-time behavior remains immediate; historical reads remain non-mutating and restart-compatible. Focused regressions cover both before/at boundaries.

## Phase 3 — crash-before-marker liveness — VERIFIED

The real barrier process was killed after durable `attempt_started` and before any observation/failure marker. A fresh process originally returned no due work even though manual same-provider recovery was safe, confirming the liveness gap. `Coordinator#restart_recovery_work_for` now derives only `resolve` for persisted `status_lookup` or `retry_same` for persisted `idempotent_retry`, with the exact pinned provider/operation/attempt identity; no capability means no derived work and the owner remains pinned. Fresh-process due-work and RecoveryExecutor regressions cover both capabilities, historical future-failure suppression, no-capability defer, and four-way concurrent deduplication.

Acceptance: actual separate-process kill/barrier; durable facts and restored phase inspected; fresh bounded due-work discovers only safe same-provider work; manual/RecoveryExecutor resume preserves owner and identity; no fresh-provider fallback, synthetic outcome, or unsafe release.

## Phase 4 — post-provider error provenance — VERIFIED

Reproduce both sides separately:

1. malformed provider-return data -> provider-contract/public 502 semantics;
2. valid provider return followed by an injected application programming fault -> internal/fail-closed semantics, not provider blame.

`ProviderContractError` is now raised explicitly for malformed provider return/linkage data. Raw adapter exceptions remain `ProviderExecutionError` and resumable. A valid return followed by application classification/duration failure is represented as `ApplicationProcessingError`, ends the process-local interaction guard, leaves the durable attempt unresolved and is not marked as provider execution failure. Real HTTP and exact fact/phase regressions cover both branches; no broad `Exception` rescue was added.

## Phase 5 — adjacent fatal apply-path evidence — VERIFIED

The injected `NotImplementedError` reproducer showed that fatal unwinding after provider return could strand the process-local interaction guard. `apply_provider_invocation` now performs unconditional idempotent guard cleanup in `ensure` without catching or reclassifying the fatal exception. A fresh-process regression proves process death leaves durable `dispatching` state discoverable as the same-provider restart item; subsequent recovery resolves A and never calls B.

## Phase 6 — judge evidence clarity — EVIDENCE-CLOSED

Measured the existing `[900, 100, 100, 100]` fixture and alternatives `[800, 200, 100, 100]`, `[700, 200, 100, 100]`, `[600, 300, 200, 100]` and `[500, 300, 200, 100]` using independent fresh Service/Coordinator/provider instances and the canonical analytics projection. The current fixture is the clearest: count remains `A=2/B=2`, while volume is `A=900/B=300`; the suggested `[600,300,200,100]` makes both aggregate shares `1/2`, so it is less legible despite a different assignment sequence. Existing deterministic demo tests already assert canonical target/actual values, same-workload strategy divergence, independent runtimes, fallback/UNKNOWN/recovery/history and configuration source/revision. No production change is justified.

## Phase 7 — traceability and candidate — VERIFIED

Every SPEC-014 acceptance maps to executable evidence in `test/support/acceptance_evidence.rb`. The verified code-bearing tree passed `bundle check`, full test (`731/12,798`), property (`4/1,210`), model (`3/2,958`), concurrency (`45/1,444`), fault (`398/4,779`), focused public/recovery/provenance/case evidence (`105/2,218`), and bounded case/operator campaigns. Candidate documentation/index HEAD `180489cf1edaf0e5c4cfbda35143e1e7e1535294` had green Actions run `33739498787`; verified tree `ba00d7dc0d77e328d300bfc9418b96ebe89ede70` has green run `33740328533`.

## Phase 8 — blind skeptical discovery — VERIFIED

Ignore backlog status and search changed/adjacent code for:

- public data leakage through any route-result/snapshot/explanation/audit path;
- historical query events visible before causal time;
- restart states that manual resume can progress but RecoveryExecutor cannot discover;
- wrong fresh-provider movement after ambiguous execution;
- provider/application/client error-domain confusion;
- stranded guards/phases;
- live/restore/replay disagreement;
- demo-only routing math or shared-state confounders;
- stale exact-HEAD evidence.

Any material locally solvable P0/P1 returns ACTIVE.

The independent candidate-stage code-first pass inspected public payout,
route-result, audit and explanation projections; all due-work sources and
causal timestamps; restart/fresh-process paths; raw provider, contract and
application error boundaries; process-local guard cleanup; live/restore/replay
parity; and demo authority/isolation. It found no new material production
P0/P1. It did find stale candidate labels in documentation indexes; those
indexes were synchronized in a docs-only checkpoint, then the candidate
Actions run passed.

## Phase 9 — closure — VERSION_COMPLETE

After the final material change and clean skeptical pass:

- fresh `bundle check`;
- full test suite;
- property/model/concurrency/fault suites;
- relevant fresh-process/crash/recovery/privacy/case campaigns;
- traceability;
- push exact final HEAD;
- verify GitHub Actions on that exact SHA;
- synchronize README/AGENTS/spec/plan/backlog/roadmap/completion/session/index docs.

The verified code-bearing tree passed the required local matrix above and the focused
fresh-process/case/traceability set (`105/2,218`). Bounded CRuby 4.0.6
measurements were also recorded: 10k lifecycle `20.1243 s / 496.9 ops/s /
140,002 facts`; 2,000-payout degradation `2,247 attempts`, `228` fallback
payouts, `228` successful fallback recoveries, maximum `3` attempts/payout;
history profile `100/250/500` payouts with `1,402/3,502/7,002` facts and
`738.0` ops/s at 500 concurrent; read-path profile through 12,500 payouts and
175,013 facts remained bounded, with due-work-empty p95 `0.002849 s` and
analytics p95 `0.000413 s`. These are bounded measurements, not a 100k claim.
Exact pushed-head Actions run `33740328533` is green, and all authority/index
docs agree with the closure state.

## Rolling next actions

1. preserve the exact closure tree and evidence; do not resume generic pre-TZ hardening without new material evidence;
2. switch to `docs/TZ_RECONCILIATION.md` immediately if authoritative TZ arrives;
3. reopen this version only for a new deterministic material counterexample or authority conflict.

## Stop policy

Stop only when v0.3.10 satisfies its full completion contract, every remaining mandatory path is genuinely externally blocked with no independent work left, or authoritative TZ arrives and immediately switches authority to `docs/TZ_RECONCILIATION.md`.

A red test, difficult local bug, reversible design choice, repository research task, failing candidate pass or missing TZ is not an external blocker.
