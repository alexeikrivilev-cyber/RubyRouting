# ExecPlan — v0.3.4 Pre-TZ Adversarial Case Fidelity & Edge Hardening

Status: VERSION_COMPLETE

Archived after v0.3.4 closure. Historical execution evidence is preserved here; it is not active authority for v0.3.5.

## Purpose / Big Picture

Advance RubyRouting from its strong pre-TZ case-complete checkpoint by resolving a newly discovered recovery-concurrency risk before adding any new feature. The session goal was correctness of the live provider-interaction interval under concurrent workers and concurrent observations.

The closure publication at `799f6977f07310105c30be9df549a536cc9d665d` is historical evidence only. A later audit found and reproduced a new material counterexample; its fix was verified below.

## Current Version Goal

**v0.3.4 — Pre-TZ Adversarial Case Fidelity & Edge Hardening**

Normative scope: `specifications/008-pre-tz-adversarial-edge-hardening.md` plus compatible protected guarantees inherited from SPEC-007 and earlier.

## Protected completed work inside v0.3.4

- typed provider/fallback outcome analytics;
- read-path analytics/explanation optimization with replay parity;
- sparse due-work scan optimization;
- fresh-process configuration crash consistency;
- exact-case count/volume/fallback/UNKNOWN/restart campaign;
- public multi-attempt history completeness;
- baseline N-worker duplicate recovery consumer race.

## New finding and verified resolution

The baseline worker fix used `@provider_interaction_in_flight[[payout_id, operation_id]] = true` as a process-local marker. `resume_operation` refused recovery while it existed. Before the final v0.3.4 fix, `apply_observation` cleared the same marker when a duplicate observation was detected and also cleared it before returning for other non-applying observations.

The interleaving was deterministically reproduced before the fix: worker B entered a second provider `resolve` before worker A was released, so provider calls reached 2 for one operation.

Root cause: the process-local marker was keyed by payout/operation and `apply_observation` deleted it for duplicate/non-applying observations. The callback did not prove that worker A's live provider call had completed.

Implemented resolution: `Coordinator` returns an immutable process-local `(payout_id, operation_id, generation)` token when consuming a start token. `Orchestrator` carries that token through provider invocation and observation application; completion and adapter-failure paths release only the exact token object that is still current. Independent reconciliation has no token and cannot release the guard. Tokens are not persisted, and provider I/O remains outside Coordinator synchronization.

## Coding session Goal

**Prove and enforce single-live-provider-interaction ownership for one committed recovery operation across concurrent workers, duplicate/stale observations, adapter failures and restart, without weakening durable UNKNOWN/fallback safety or adding distributed infrastructure.**

## Deterministic counterexample

The primary race was:

- worker A blocked in status lookup;
- exact duplicate prior observation applied concurrently;
- worker B called `resume` before A completed.

The pre-fix behavior allowed two provider interactions. Controlled synchronization reproduced it deterministically.

## Adjacent counterexamples — VERIFIED

The matrix covered:

- idempotent same-provider retry;
- stale/out-of-order/non-applying observation;
- accepted observation while provider call returns later;
- adapter exception then retry;
- callback-before-resolution/start token invalidation;
- restart of dispatching/resolving operation;
- stale/ABA interaction token behavior.

## Minimal implementation — COMPLETE

Verified properties:

- interaction guard has explicit invocation identity/token/generation;
- acquire happens atomically with start-token consumption and `attempt_started` publication;
- Orchestrator retains invocation identity through provider I/O;
- completion/failure releases only a matching token;
- unrelated observation application cannot release another live invocation;
- token state is not durable;
- fresh restart reconstructs recovery from operation phase/contract;
- provider I/O stays outside Coordinator mutex;
- no distributed lock/queue/database was introduced.

## Regression matrix — VERIFIED

Focused evidence proved:

1. baseline four-worker resolve race → one provider call;
2. baseline four-worker retry race → one provider call;
3. blocked resolve + duplicate callback + second resume → one provider call;
4. blocked retry + duplicate/stale callback + second resume → one provider call;
5. adapter exception releases only its own token and later retry proceeds;
6. unrelated/stale callback cannot release a newer invocation token;
7. normal completion does not leave a stuck token;
8. UNKNOWN retains ownership and provider B is not called;
9. restart discards local guard identity and safely resumes pinned operation;
10. no unintended extra allocation/ownership/operation/provider-interaction facts.

Evidence: `bundle exec ruby -Itest test/concurrency/due_recovery_workers_test.rb` — 7 runs, 97 assertions, 0 failures; `bundle exec ruby -Itest test/acceptance_traceability_test.rb` — 1 run, 793 assertions, 0 failures.

## Broader verification — VERIFIED

Evidence on the closure worktree: safety 15/68, replay 18/99, orchestrator 21/89, payload 2/17, restart/recovery 103/264; property 4/1210; model 3/2941; concurrency 21/1050; scenario/fault matrix 341/4182; full `bundle exec rake test` 639/11274. All passed with 0 failures/errors.

No performance claim changed, so no new benchmark was required.

## Skeptical closure pass — VERIFIED

The closure review challenged token ABA/generation reuse, callback clearing wrong token, exception/success leaks, adapter availability, token lifetime across configuration changes, restart dependence, stale decision commits, duplicate observation facts, lock ordering and provider-I/O boundaries.

No material P0/P1 remained in the v0.3.4 scope. The code/test checkpoint is `6510893ac2c7c12e70acba5882d0829b11f898a2`; candidate CI run `33510733290` passed for `27005276661488f852bdfdfe3d2a71bb0d8dbb38`; final published v0.3.4 exact HEAD became `17d91fb3e30dc7c8a04c8df318668130090a0325` with green CI.

## Historical completion sequence

1. PTZ4-004 reproduced and resolved;
2. focused tests green;
3. broad verification green;
4. active docs updated;
5. fresh skeptical pass found no material v0.3.4 issue;
6. candidate gate passed;
7. exact candidate CI passed;
8. active v0.3.4 sources were synchronized;
9. `VERSION_COMPLETE` was published and exact-head CI passed.

## Non-goals

No new analytics metrics, dashboard work, PSP-brand adapters, persistence subsystem, database, queue, distributed lease, ML/bandit logic, new allocation strategy, generalized rules DSL or cosmetic refactor belonged to v0.3.4.
