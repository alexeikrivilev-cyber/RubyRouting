# SPEC-013 — Pre-TZ Boundary Honesty & Demo Isolation

Status: VERSION_COMPLETE.

Version Goal: **v0.3.9 — Boundary Honesty & Demo Isolation**.

Opening HEAD: `7cee74a2336b356c4e112b23a848fe5df4051af4`.

Protected baseline: v0.3.8 / SPEC-012 is `VERSION_COMPLETE`; exact-head Actions run `33672087791` is green.

## 1. Purpose

Resolve the final generic pre-TZ mismatches between internal correctness and external/product semantics without reopening the proven financial kernel. v0.3.9 is not a feature expansion.

## 2. Protected invariants

Preserve: one submission = one intent; at most one unresolved owner; ambiguous possible-send remains UNKNOWN; UNKNOWN blocks fresh cross-provider movement; raw timeout/exception is not `definitely_not_sent`; same-provider recovery reuses pinned identity; provider I/O stays outside locks; primary/recovery/settlement accounting stay separate; replay/restart preserves causal safety; HTTP/demo remain adapters over canonical application paths; active configuration, durable payout history and executable adapters remain distinct authorities.

## 3. Mandatory hypotheses

### S13-001 — HTTP error domain follows execution provenance

Opening evidence: `HttpApp` maps generic `ArgumentError` to `400 invalid_request`, while post-provider observation linkage validation also raises `ArgumentError` after operation/provider interaction already exist.

Required:
- reproduce through real HTTP surface;
- distinguish request/input validation from post-provider contract/application failure;
- post-provider failure must not imply the request was rejected before economic work;
- public output remains bounded/privacy-safe;
- exact owner/status/phase/facts/guard release asserted;
- use the smallest typed error/status mapping.

### S13-002 — raw provider execution failure has explicit liveness semantics

Opening evidence: raw adapter-call exceptions become `ProviderExecutionError`; the live guard is released and operation remains pinned. Due-work behavior has not been independently proven as a product liveness contract.

Required:
- reproduce initiate and resolve/recovery raw exception paths;
- inspect immediate/time-advanced `Queries#due_work`;
- prove whether RecoveryExecutor discovers work or manual resume is intentional;
- if safely resumable work is stranded outside advertised recovery, implement smallest deterministic recovery transition;
- never convert raw exception into safe cross-provider release;
- prove restart parity and no duplicate invocation.

### S13-003 — count-vs-volume judge evidence isolates strategy on fresh state

Opening evidence: v0.3.8 uses the same amounts but runs count then volume in one Service with shared stateful providers and accumulated runtime/history.

Required:
- independent fresh Coordinator/Service/provider instances;
- equivalent initial configuration/provider behavior/context/workload, with measure as intended changing variable;
- measured workload with clear defensible difference;
- canonical Queries/Analytics values only;
- no demo allocator;
- separate fallback/UNKNOWN/recovery evidence if necessary;
- deterministic machine-readable output.

### S13-004 — adapter interface matches declared capabilities

Opening evidence: Orchestrator construction requires executable `initiate` and `resolve` for every provider, while `status_lookup` may be false.

Required:
- inventory actual `resolve`/capability uses;
- determine whether `resolve` is universal port method or capability-dependent;
- evidence-close if coherent;
- otherwise smallest capability-aware validation change;
- no dynamic plugin framework/provider-brand core branching.

### S13-005 — traceability and skeptical closure

Map S13 requirements to executable evidence. All mandatory hypotheses green/evidence-closed gives only `VERSION_CANDIDATE`; then perform a fresh code-first skeptical pass. Any new material P0/P1 returns ACTIVE. Exact full verification and exact pushed-HEAD CI are mandatory before `VERSION_COMPLETE`.

## 4. P2 / evidence-gated

Configuration generation/fingerprint if historical revision ambiguity becomes material; runtime adapter warnings on config apply; `scan_as_of` naming cleanup; optimistic config revision; branch protection/static tooling; large architecture extraction.

## 5. Explicit non-goals

No Rails/ORM, DB/Redis/Sidekiq, distributed leases, microservices, dynamic plugin system, ML/bandits, new objectives, generalized rules DSL, PSP-specific core model or large Coordinator/Analytics refactor without new authority.

## 6. Exit criteria

`VERSION_CANDIDATE`: honest HTTP post-provider errors; explicit raw-provider-failure liveness; fresh independent count/volume experiment; coherent adapter capability contract; inherited safety green; traceability current; PTZ9-006 replay/live evidence parity, PTZ9-007 fatal-adapter guard cleanup and PTZ9-008 post-return enrichment provenance fixed, with fresh local matrix green.

`VERSION_COMPLETE`: candidate plus clean independent skeptical pass, full current verification and exact-HEAD CI. Achieved on closure HEAD `543f7b4f00d37e42441245b1e26a74e943f0e525`; GitHub Actions run `33692143385` is green.
