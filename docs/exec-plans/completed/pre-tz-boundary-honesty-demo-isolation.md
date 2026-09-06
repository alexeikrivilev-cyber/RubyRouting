# ExecPlan — v0.3.9 Boundary Honesty & Demo Isolation

Status: VERSION_COMPLETE.

Opening HEAD: `7cee74a2336b356c4e112b23a848fe5df4051af4`.

Closure HEAD: `543f7b4f00d37e42441245b1e26a74e943f0e525`.

Exact GitHub Actions: run `33692143385`, green.

## Purpose

Close freshly discovered generic pre-TZ gaps between the strong financial kernel and semantics exposed to operators/judges.

## Governing sources

`AGENTS.md` -> SPEC-013 -> this plan -> PRE_TZ_BACKLOG -> Completion Policy -> v0.3.9 architecture/decisions.

## Protected baseline

v0.3.8 is complete. Do not reopen allocation, UNKNOWN, causal fences, configuration architecture or recovery objectives without a new deterministic counterexample.

## Phase 0 — re-orient

Verify exact `main`/CI; inspect `HttpApp`, Orchestrator, RecoveryExecutor, Coordinator due-work/restart paths, demo scenario and provider port; reproduce every opening hypothesis before production changes.

## Phase 1 — HTTP post-provider error honesty — VERIFIED

Build real HTTP reproducer: valid request, operation/provider interaction begins, provider returns malformed linked data, application validation fails after return.

Evidence: the deterministic real-HTTP repro returned `400 invalid_request` on opening HEAD after one provider call, with a committed owner and no completion fact. The focused regression now returns `502 provider_contract_error`; it asserts 13 conditions including exact operation/attempt identity, `pending`/`dispatching` state, guard release, absence of completion/observation/failure-marker facts and privacy-safe body. Full HTTP (`39/275`), Orchestrator (`22/105`) and RecoveryExecutor (`14/139`) suites are green.

Decision: introduce `ProviderContractError` only around post-return classification/linkage validation. Raw adapter exceptions remain `ProviderExecutionError`; pre-provider input errors remain 400.

## Phase 2 — raw ProviderExecutionError liveness — VERIFIED

Evidence: opening probes showed guard release plus safe manual same-provider resume, but no immediate or time-advanced due-work after raw initiate/resolve exceptions. The implementation adds durable payload-free `provider_execution_failed` provenance, releases the local guard, and exposes one bounded immediate work item only for the persisted operation contract's `status_lookup`/`idempotent_retry` capability. A provider without either capability remains safely pinned and has no advertised work. The next canonical attempt clears the marker; post-return `ProviderContractError` uses release-only cleanup and does not become raw-provider recovery work.

Focused evidence: `test/scenario/recovery_executor_test.rb` (`14/142`), `test/scenario/restart_recovery_test.rb` (`104/290`), `test/scenario/durable_crash_campaign_test.rb` (`8/62`), plus restore/replay/HTTP/orchestrator and due-worker/economic-safety/coordinator-race suites. The fresh-process regression asserts exact same operation/attempt resolution and live/replay parity.

## Phase 3 — fresh-runtime strategy experiment — VERIFIED

Evidence: the opening case demo shared provider outcome cursors and state, and its volume result was `A=300/B=900`; an isolated measurement with the same `[900, 100, 100, 100]` workload and fresh all-success providers produced count `A=2/B=2` and volume `A=900/B=300`. `Demo::Scenario.case_run` now uses separate fresh Service/Coordinator/provider runs for count and volume, while fallback plus UNKNOWN/RecoveryExecutor use a third runtime. Target/actual values remain sourced from each canonical `Queries#analytics`; no demo allocator was added.

Focused evidence: `test/scenario/demo_scenario_test.rb` (`6/54`), `test/scenario/case_fidelity_campaign_test.rb` (`2/163`) and `test/scenario/operator_composition_campaign_test.rb` (`1/18`) are green. The demo report exposes fresh-runtime strategy metadata and separate provider call traces.

## Phase 4 — adapter capability contract — VERIFIED / EVIDENCE-CLOSED

Code-first inventory confirms the universal executable adapter port is `initiate` plus `resolve`, while persisted capabilities choose recovery behavior rather than adapter shape: `status_lookup` invokes `resolve`, `idempotent_retry` invokes same-operation `initiate`, and `false/false` exposes no recovery action. The focused matrix (`test/scenario/provider_adapter_contract_test.rb`, `2/13`) plus existing status-lookup/idempotent-retry/no-capability tests prove this contract. No production change was required.

## Phase 5 — traceability and candidate — VERIFIED / VERSION_CANDIDATE

SPEC-013 traceability maps PTZ9-001 through PTZ9-008 to executable regressions, including HTTP provenance, raw-failure liveness/fresh process, isolated demo runtimes, adapter capability matrix, replay/live evidence parity, fatal-adapter guard cleanup, post-return enrichment provenance and this traceability test. Candidate-stage code-first review found PTZ9-006: replay accepted malformed `provider_execution_failed` evidence that restore rejected. The shared validator fix and fresh post-fix full matrix were green. The subsequent candidate skeptical pass found PTZ9-007: fatal adapter unwinding stranded the process-local guard; its release-only fix and focused regression are green. A further candidate pass found PTZ9-008: post-return duration enrichment was mislabeled as raw provider failure; its release-only typed-boundary fix and focused regression are green. The final exact local matrix on closure HEAD is green: test `719/12601`, property `4/1210`, model `3/2958`, concurrency `44/1438`, fault `387/4662`, all with zero failures/errors/skips.

## Phase 6 — independent skeptical discovery

Ignore checklist. Search wrong 4xx/5xx after economic effects, hidden error taxonomy, stranded phases, duplicate movement, demo state leakage/demo-only math, capability contradictions, UNKNOWN weakening, privacy leaks and second authorities. Any material finding returns ACTIVE.

The final candidate code-first pass checked the changed provider, recovery,
replay, HTTP and demo paths and found no new material production P0/P1. It did
find stale secondary documentation indexes still declaring v0.3.7 current;
those indexes were synchronized before final exact verification. A second
closure review of the synchronized tree found no new production or authority
drift gap.

## Phase 7 — closure

Full matrix, exact-HEAD CI, synchronized docs, then `VERSION_COMPLETE` on
`543f7b4f00d37e42441245b1e26a74e943f0e525`. Exact GitHub Actions run
`33692143385` is green. Product evidence is bounded and honest: the history
profile covers 100/250/500 samples, while the separate load evidence covers
10,000 lifecycle operations; no unsupported 100k claim is made.

## Rolling next actions

1. preserve the exact closure SHA and evidence in the completed-plan archive;
2. switch to `docs/TZ_RECONCILIATION.md` if authoritative TZ arrives;
3. reopen v0.3.9 only for a new material counterexample or authority conflict.

## Stop policy

Do not stop after one fix/test/commit/phase/green CI. Stop only at full v0.3.9 closure, genuine external blockage with no independent mandatory work, or authoritative TZ arrival.
