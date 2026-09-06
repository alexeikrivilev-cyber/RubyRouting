# ExecPlan — v0.3.5 Pre-TZ Economic Effect Safety & Adapter Readiness

Status: ACTIVE

## Purpose / Big Picture

Advance RubyRouting from the verified v0.3.4 baseline by closing the last generic financial-safety boundary exposed by the new invocation-owned guard model: a callback can change durable lifecycle/ownership while a money-moving provider call is still executing outside the Coordinator lock.

The goal is not to add another routing feature. It is to prove that provider A cannot remain economically live while the system opens a fresh money-moving path to provider B.

## Current Version Goal

**v0.3.5 — Pre-TZ Economic Effect Safety & Adapter Readiness**

Governing source: `specifications/009-pre-tz-economic-effect-safety.md` plus compatible protected guarantees from SPEC-008 and earlier.

## Starting evidence

Exact baseline before this plan: `17d91fb3e30dc7c8a04c8df318668130090a0325`.

Verified inherited facts:

- v0.3.4 exact-HEAD CI is green;
- live provider interaction guards are invocation-owned using an opaque process-local token/generation;
- unrelated callbacks cannot release another invocation's local guard;
- `apply_observation` can still reduce an independent safe-to-release observation while a provider invocation remains live;
- safe route failures default to `safe_to_release=true`;
- after ownership release, normal decision flow may reroute;
- the current token blocks duplicate `resume_operation` for the same operation but does not explicitly fence a fresh assignment for the payout after ownership was released.

This produces the primary v0.3.5 hypothesis below. It is not yet a proven defect until a controlled interleaving reproduces it.

## Protected baseline

Do not churn these areas without new evidence:

- exact count/volume allocation;
- policy/configuration resolution and generation coherence;
- provider route eligibility/admission;
- UNKNOWN ownership safety and restart recovery;
- provider operation payload/idempotency contract;
- invocation-owned duplicate recovery guard;
- quality/health ranking hierarchy;
- dimension-safe distribution/outcome analytics;
- payout history/public audit/explanation;
- revision-keyed read optimizations and bounded performance evidence;
- exact-case campaign.

## Goal

**Prove and enforce that no fresh cross-provider money-moving assignment can be committed while a previous money-moving provider invocation for the payout is still live, even if an independent provider callback has already produced a safe-to-release lifecycle outcome. Then harden adjacent late-completion and adapter timeout semantics without speculative infrastructure.**

## Phase A — Deterministic P0 reproducer

Inspect exact HEAD implementations of:

- `Coordinator#mark_attempt_started`;
- `Coordinator#mark_resolution_started`;
- `Coordinator#apply_observation`;
- `Coordinator#prepare_and_commit_decision`;
- `Coordinator#resume_operation`;
- `OperationCommitter#apply_outcome` / ownership release;
- `ObservationLedger#observation_applies?`;
- Orchestrator `submit/initiate/resolve/apply_provider_invocation`.

Build controlled blocking providers using queues/barriers, never sleeps.

### A1 — initial assignment race

1. commit provider A primary assignment;
2. start A `initiate` and block inside provider after interaction token acquisition;
3. independently apply a same-operation `safe_route_failure` callback with `safe_to_release=true`;
4. while A is still blocked, call canonical `submit`/advance path again;
5. assert whether provider B can start before A finishes.

Pre-fix failure condition: B starts while A's original money-moving call is still live.

### A2 — idempotent retry race

1. obtain UNKNOWN on provider A;
2. start same-provider `retry_same/initiate` and block it;
3. independently apply safe-to-release failure callback for operation A;
4. concurrently attempt normal continuation;
5. assert whether provider B starts before the retry finishes.

### A3 — adjacent outcomes

Repeat with:

- explicit safe-to-release temporary provider failure;
- terminal payout failure;
- late A success;
- late definitely-not-sent A result;
- ambiguous A result;
- adapter exception.

Record exact provider calls and financial facts.

## Phase B — Minimal correctness design

Do not preselect a class shape before the reproducer.

Preferred smallest solution if the hypothesis reproduces:

- extend the existing process-local interaction ownership semantics so the system can distinguish money-moving invocation (`assign`/`retry_same` via `initiate`) from read-only resolution (`resolve`);
- while any live money-moving invocation exists for a payout, fresh provider assignment/fallback for that payout returns a deterministic defer/wait reason rather than acquiring new economic ownership;
- an independent callback may still be recorded/reduced under canonical observation rules, but it cannot indirectly open provider B during the live-A interval;
- the owning invocation's completion/failure releases only its token;
- no process-local fence is persisted across restart.

A dedicated `ProviderInteractionGuard` is acceptable only if it centralizes this invariant. A Coordinator-local extension is equally acceptable. No distributed lock/lease.

## Phase C — Late completion semantics

Prove exact outcomes after the live invocation finally returns.

Required cases:

1. independent safe failure released ownership, live A later returns safe failure -> no B before A completion; subsequent fallback can occur once;
2. independent safe failure released ownership, live A later returns success -> no B was started; contradiction becomes explicit settlement/conflict/reconciliation evidence, never silent overwrite;
3. live A returns ambiguous transport -> UNKNOWN/reconciliation-safe behavior remains;
4. adapter exception releases only its local token and does not fabricate provider failure;
5. no stuck live fence after normal completion or error.

If current conflict/lifecycle behavior is insufficient, change only the smallest canonical reducer path required by a deterministic failing case.

## Phase D — Observation authority adjacency

Challenge but do not overengineer:

- provider with `authoritative_sequence=true`;
- provider without authoritative sequence;
- duplicate/stale/out-of-order callback while money-moving call is live;
- callback before start-token consumption;
- callback while status lookup is live.

Important distinction: status lookup is not itself money-moving. Do not block safe economic progress merely because a read-only `resolve` call is running unless a reproduced ordering defect requires it.

Do not invent generalized causal/vector-clock provider metadata unless the narrow money-moving fence fails.

## Phase E — Adapter bounded-execution contract

Review provider port, operation TTL/deadline and Orchestrator transport classification.

Required outcome:

- document/test that production adapters own connect/read/request timeouts;
- timeouts are classified through explicit transport semantics, not broad rescue;
- `definitely_not_sent` is used only when justified;
- ambiguous timeout remains UNKNOWN-safe;
- operation TTL/deadline remains economic/recovery policy, not socket timeout;
- do not use `Thread#kill` or generic asynchronous interruption.

Implement a small adapter conformance test/helper only if it materially improves this contract without provider-brand assumptions.

## Phase F — Restart/configuration adjacency

Run deterministic/fresh-process scenarios for:

- crash while money-moving dispatch was started;
- restart after callback but before local provider return/process death;
- provider opportunity removal/config revision change while unresolved operation remains pinned;
- stale decision commit after callback/restart;
- stale due-work item.

Expected: local interaction identity disappears on process death; durable recovery remains governed by operation phase/contract/ownership and existing status lookup/idempotent retry rules.

## Phase G — Broad verification

After focused green:

- focused new concurrency tests;
- existing `due_recovery_workers_test`;
- orchestrator/provider operation tests;
- coordinator safety and restart recovery suites;
- property/model/concurrency/fault tasks;
- full `bundle exec rake test`;
- acceptance traceability;
- exact case campaign;
- demo smoke if application behavior changed.

Run benchmarks only if hot-path code or performance claims changed materially.

## Phase H — Independent skeptical closure

Ignore the completed checklist and review changed production code as untrusted.

Search for:

- fresh provider assignment while any money-moving invocation remains live;
- token ABA or wrong-token release;
- external callback changing lifecycle under a live call;
- late success after release;
- overblocking read-only status lookup;
- adapter timeout being misclassified as definitely-not-sent;
- UNKNOWN cross-provider fallback;
- restart dependence on process-local state;
- provider/config removal while pinned;
- duplicate allocation/ownership/attempt facts;
- API/demo bypass of the canonical fence;
- unsupported distributed exactly-once claims;
- new full-history/performance regressions.

Any material locally solvable P0/P1 keeps v0.3.5 ACTIVE.

## Verification evidence requirements

For P0 races assert at least:

- exact provider A/B call sequence;
- no B call before A live invocation completion;
- `active_unresolved_owners <= 1`;
- exact `allocation_committed` count;
- exact ownership acquire/release count;
- exact operation/attempt identity count;
- settlement/conflict/reconciliation facts as applicable;
- final payout state;
- restart/replay parity if durable semantics changed.

## Rolling next actions

1. Reproduce A1 on current code before production changes.
2. Reproduce/falsify A2 and adjacent late-success case.
3. Choose the smallest money-moving fence design from evidence.
4. Implement focused tests + fix and run adjacency.
5. Continue through adapter/restart phases without routine confirmation.

## Explicit non-goals

No new allocation strategy, dashboard, PSP-brand adapter, database, queue, distributed lease, microservices, generalized rules DSL, ML/bandits or cosmetic Coordinator split.

## Stop policy

Do not stop after a reproducer, fix, green focused test, commit or CI. Continue until SPEC-009 P0/P1 is verified/falsified, a fresh skeptical pass is clean, exact candidate CI is green and active documents agree — or authoritative TZ arrives and triggers immediate reconciliation mode.
