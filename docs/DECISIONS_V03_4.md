# Decisions — v0.3.4 Adversarial Case Fidelity & Edge Hardening

Status: VERSION_COMPLETE decision supplement for SPEC-008.

This file inherits all compatible accepted decisions from v0.3.3 and earlier. It changes authority only where stated below.

## D-340 — v0.3.3 remains closed baseline

Status: accepted.

Decision: SPEC-007/v0.3.3 remains `VERSION_COMPLETE` unless a new reproducible defect falsifies one of its protected guarantees. v0.3.4 is not permission to redesign completed mechanisms.

## D-341 — v0.3.4 is case-fidelity first

Status: accepted.

Decision: new pre-TZ work is prioritized by direct relevance to configurable count/volume distribution, safe fallback/recovery, complete attempt history and final distribution/success analytics.

## D-342 — outcome counts are distinct from allocation measures

Status: accepted.

Decision: provider/fallback success analytics must not derive payout-count success rates from allocation/settlement volume. Outcome populations have explicit typed semantics; exact Rational rates are allowed only for a well-defined compatible population.

## D-343 — due-work discovery is not a lease

Status: accepted, refined by D-348.

Decision: multiple workers may observe the same due recovery item. Distributed exactly-once work leasing is not required. The local atomic resume/start protocol must make duplicate consumers economically and operationally harmless.

## D-344 — config crash safety may fail closed

Status: accepted.

Decision: before the official deployment/control-plane contract exists, abrupt configuration-publication restart may reconcile one externally supplied coherent generation or fail closed. It may not silently route with a mixed generation.

## D-345 — performance state is derived state

Status: accepted.

Decision: caches/indexes/incremental analytics are reconstructible derived state and cannot become a source of money-moving truth.

## D-346 — optimize the narrowest proven bottleneck

Status: accepted.

Decision: use existing FactStore indexes before new indexes, revision-keyed derived projection before persistent caches, and sort only actionable due work before adding a due queue/index.

## D-347 — case campaign is executable acceptance evidence

Status: accepted.

Decision: v0.3.4 maintains a deterministic end-to-end campaign demonstrating count-vs-volume distribution, safe fallback, UNKNOWN resolution, attempt history and outcome analytics through canonical product surfaces.

## D-348 — live provider interaction guard is invocation-owned

Status: accepted, implemented and verified by the code/test checkpoint and exact-head CI recorded in the active ExecPlan.

Decision: a process-local guard used to serialize live provider interactions represents ownership by one specific invocation, not merely membership of a payout/operation key. An unrelated duplicate, stale, out-of-order or non-applying observation must not release another still-executing invocation's guard.

The owning invocation's success/completion or adapter-failure path may release its token. If a canonical observation arrives independently, it may update durable/lifecycle state but must not impersonate completion of a different live call unless the implementation can prove identity equivalence.

Rationale: operation identity can legitimately be reused for status lookup/idempotent same-provider recovery. Therefore `operation_id` alone is insufficient to identify which concurrent invocation owns a process-local execution interval.

## D-349 — process-local interaction identity is not durable recovery state

Status: accepted.

Decision: invocation tokens/generations used for live serialization are intentionally process-local. They are discarded on process death. Fresh restart continues to rely on durable attempt phase, operation contract, ownership and recovery legality to rebuild the pinned operation.

Rationale: persisting a local mutex/lease concept would complicate restart and create false distributed-exactly-once semantics. Durable economic safety and live single-process execution ownership solve different problems.

## D-350 — closure is reopenable by new evidence

Status: accepted.

Decision: a prior `VERSION_COMPLETE` publication is a claim about evidence known at that revision, not an irrevocable project state. A later reproducible material counterexample or high-confidence untested P0 hypothesis reopens the current version to ACTIVE work while preserving the old commit as historical evidence.

Rationale: this is the intended consequence of the project's evidence-first completion policy and prevents documentation status from outranking actual code risk.
