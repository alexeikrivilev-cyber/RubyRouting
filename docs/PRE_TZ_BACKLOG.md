# Pre-TZ Backlog — v0.3.4 Adversarial Case Fidelity & Edge Hardening

Status: VERSION_COMPLETE

v0.3.3/SPEC-007 remains a protected completed baseline. v0.3.4 reached `VERSION_COMPLETE` publication at `799f6977f07310105c30be9df549a536cc9d665d`; a later independent audit found and reproduced a new material recovery-concurrency counterexample, so v0.3.4 was reopened under the completion policy. The counterexample, adjacent risks, fresh skeptical discovery, exact candidate verification/CI and final docs-only CI are verified; v0.3.4 is `VERSION_COMPLETE` at the published exact head.

Priority: P0 before P1. Existing verified checkpoints remain protected unless a new reproducer falsifies them.

## P0 — VERIFIED; VERSION COMPLETE PUBLICATION

### PTZ4-004 — Live provider-interaction guard ownership under concurrent observations

Finding confirmed: the process-local in-flight guard introduced for duplicate due-work consumers was keyed only by payout/operation and could be cleared by observation application that did not originate from the currently executing provider invocation. A duplicate/stale/non-applying callback arriving while `resolve` or same-provider retry was blocked therefore allowed another worker to start the same provider interaction concurrently.

Why this matters:

- S8-002 requires at most one provider interaction for one committed token;
- one unresolved economic owner can still remain intact while duplicate provider I/O occurs, so ownership-only tests are insufficient;
- provider status/retry calls can have side effects or load/cost even when economically idempotent;
- a process-local guard must represent invocation ownership, not merely operation identity.

Required reproducer before implementation:

1. create an unresolved owned payout with status lookup;
2. start worker A recovery and block provider `resolve` after the local guard is acquired;
3. concurrently apply an exact duplicate prior observation for the same operation;
4. start worker B `resume` while A is still blocked;
5. assert whether provider call count can become 2 before A completes.

Repeat for:

- idempotent same-provider retry;
- stale/out-of-order/non-applying observation where the canonical observation ledger permits it;
- adapter exception cleanup;
- accepted live observation/completion cleanup;
- fresh restart semantics.

Done when:

- counterexample is deterministically reproduced or falsified with controlled synchronization;
- if reproduced, live interaction guard uses explicit invocation ownership/token/generation semantics;
- only the owning invocation may release its live guard through completion/failure;
- unrelated callbacks cannot clear another invocation's guard;
- exactly one provider interaction starts for the committed token in all focused races;
- no second owner/operation/allocation/fallback is created;
- UNKNOWN ownership remains pinned;
- fresh Coordinator restart does not depend on process-local guard state;
- focused recovery/concurrency/restart/fault tests pass;
- broad matrix and exact-HEAD CI pass before closure.

Status: VERIFIED — 7 focused tests / 97 assertions, broad matrix, fresh skeptical discovery, exact candidate verification/CI and final docs-only CI green.

## P0 — VERIFIED CHECKPOINTS

### PTZ4-001 — Dimension-safe provider/fallback success analytics

Verified. Canonical outcome dimensions/populations separate payout counts from allocation measures and prevent incompatible aggregation. HTTP/application use the same projection.

### PTZ4-002 — Baseline duplicate due-work consumer race

Verified only for the original N-worker race without a competing observation. Four workers on one due resolution/retry start one provider interaction. This checkpoint remains valuable but does NOT close PTZ4-004.

### PTZ4-003 — Configuration publication crash consistency

Verified by fresh-process crash campaign. Restart reconciles one coherent generation or fails closed; unresolved payout ownership is preserved.

## P1 — VERIFIED CHECKPOINTS

### PTZ4-101 — Repeated analytics/explanation performance evidence

Verified. Revision-keyed discardable analytics base plus dynamic `as_of` projection and indexed payout explanation materially reduce repeated read cost while preserving full replay/restart parity.

### PTZ4-102 — Sparse due-work scaling

Verified. Full-population sort was removed; only emitted work is sorted. A durable due index is not justified by current evidence.

### PTZ4-103 — End-to-end case-fidelity campaign

Verified. Deterministic canonical campaign covers count/volume distribution, safe fallback, UNKNOWN resolution, history, typed outcome analytics and restart/replay parity.

### PTZ4-104 — Product-facing payout history completeness

Verified. Public payout/explanation/audit surfaces preserve all multi-attempt identities, providers, roles and outcomes after restart without exposing raw/recipient data.

## Next coding session order

1. Read exact HEAD and the current guard lifecycle in `Coordinator#resume_operation`, `mark_attempt_started`, `mark_resolution_started`, `apply_observation`, `provider_interaction_failed` and Orchestrator invocation paths. DONE.
2. Write and run the blocked-live-interaction + duplicate-observation reproducer first. DONE; two calls reproduced before the fix.
3. Implement the smallest ownership-aware local interaction token abstraction. DONE.
4. Add retry/stale-observation/adapter-failure/completion/restart regressions. DONE.
5. Run focused suites, then concurrency + fault + restart adjacency. DONE; green.
6. Run full test/property/model/concurrency/fault matrix and acceptance traceability. DONE; green.
7. Perform independent skeptical review of changed guard semantics and candidate-stage discovery. DONE; no new material P0/P1 found.
8. Update decisions/backlog/ExecPlan with exact evidence. DONE for the implementation slice.
9. Set `VERSION_CANDIDATE` only after the fresh pass finds no material P0/P1. DONE; candidate gate passed.

## Explicit non-priorities

Do not spend this session on microservices, Rails/ORM, queues, distributed locks/leases, databases, provider-brand schemas, ML/bandits, dashboards, new ranking logic, analytics expansion, performance optimization or cosmetic Coordinator splitting.

## Closure

The previous `VERSION_COMPLETE` publication is superseded as current status by this new finding. It remains historical evidence that the then-known matrix and CI were green.

Current closure condition: satisfied at the published exact head; no known locally solvable P0/P1 remains.
