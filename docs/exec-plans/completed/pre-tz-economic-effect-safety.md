# ExecPlan — v0.3.5 Pre-TZ Economic Effect Safety & Adapter Readiness

Status: VERSION_COMPLETE — fresh skeptical discovery and exact-head local CI are green; no official TZ has arrived

## Purpose / Big Picture

Advance RubyRouting from the verified v0.3.4 baseline by closing the last generic financial-safety boundary exposed by the new invocation-owned guard model: a callback can change durable lifecycle/ownership while a money-moving provider call is still executing outside the Coordinator lock.

The goal is not to add another routing feature. It is to prove that provider A cannot remain economically live while the system opens a fresh money-moving path to provider B.

## Current Version Goal

**v0.3.5 — Pre-TZ Economic Effect Safety & Adapter Readiness**

Governing source: `specifications/009-pre-tz-economic-effect-safety.md` plus compatible protected guarantees from SPEC-008 and earlier.

## Starting evidence

Exact baseline before this plan: `1cd84a345845fb9f94104b9d4e833368ab149c17` (`origin/main`).

Verified inherited facts:

- v0.3.4 exact-HEAD CI is green;
- live provider interaction guards are invocation-owned using an opaque process-local token/generation;
- unrelated callbacks cannot release another invocation's local guard;
- `apply_observation` can still reduce an independent safe-to-release observation while a provider invocation remains live;
- safe route failures default to `safe_to_release=true`;
- after ownership release, normal decision flow may reroute;
- the current token blocks duplicate `resume_operation` for the same operation but does not explicitly fence a fresh assignment for the payout after ownership was released.

This produced the primary v0.3.5 hypothesis. A controlled interleaving reproduced it before the production change: an independent safe-release callback could free durable ownership while A's `initiate` remained live, allowing a canonical continuation to open B.

## Slice checkpoint — local exact worktree

PTZ5-001/002 and the PTZ5-003 outcome matrix are now implemented and verified with deterministic queue barriers. The narrow fix extends the existing process-local invocation token with an explicit `money_moving` bit and fences only owner-free fresh decisions while a same-payout money-moving token remains live. Read-only resolution tokens are explicitly non-money-moving. Late success/ambiguous observations become explicit conflict evidence and keep automatic continuation deferred; definitely-not-sent completion can unblock fallback only after the owning invocation releases its token.

Focused evidence: `test/concurrency/economic_effect_safety_test.rb` — 9 runs, 113 assertions, 0 failures/errors. The matrix now includes temporary safe release, terminal release, duplicate callback, authoritative sequence 2→1→3 while A is live, late success/definitely-not-sent/ambiguous/adapter exception, and a real blocking read-only resolution. Adjacent coordinator safety, observation ledger, projection/replay, due-worker, model, allocation, recovery-budget, recovery-schedule, cross-feature, outcome-analytics and restart suites are green. The latest exact-head local matrix is `655 runs` with zero failures/errors/skips; required Rake groups are property `4`, model `3`, concurrency `30` and fault `344` runs, all with zero failures/errors/skips. Assertion totals vary with reproducible test seeds.

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

### A1 — initial assignment race — VERIFIED

1. commit provider A primary assignment;
2. start A `initiate` and block inside provider after interaction token acquisition;
3. independently apply a same-operation `safe_route_failure` callback with `safe_to_release=true`;
4. while A is still blocked, call canonical `submit`/advance path again;
5. assert whether provider B can start before A finishes.

Pre-fix failure condition: B starts while A's original money-moving call is still live.

### A2 — idempotent retry race — VERIFIED

1. obtain UNKNOWN on provider A;
2. start same-provider `retry_same/initiate` and block it;
3. independently apply safe-to-release failure callback for operation A;
4. concurrently attempt normal continuation;
5. assert whether provider B starts before the retry finishes.

### A3 — adjacent outcomes — VERIFIED

Repeat with:

- explicit safe-to-release temporary provider failure;
- terminal payout failure;
- late A success;
- late definitely-not-sent A result;
- ambiguous A result;
- adapter exception.

Record exact provider calls and financial facts.

## Phase B — Minimal correctness design

The reproducer selected the smallest compatible extension; no separate guard class was required.

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

Current evidence: the deterministic economic-effect matrix exercises an authoritative-sequence provider with applied sequence 2, stale sequence 1 and release sequence 3 while the initial A `initiate` remains blocked. The stale observation is recorded as non-applying, does not regress `pending`/ownership, and does not open B. A duplicate safe-release callback is idempotent. Existing callback-before-dispatch/resolution tests cover invalidation before token consumption; the real blocking-resolution test confirms read-only calls are not over-fenced.

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

Current evidence: `test/scenario/orchestrator_simulator_test.rb` covers explicit ambiguous and definitely-not-sent result/error classifications plus an unclassified raw `Timeout::Error` (22 runs, 96 assertions). The raw timeout surfaces without synthetic transport facts or unsafe release, while the committed operation remains recoverable through its existing status-lookup contract. Provider-port comments make adapter-owned connect/read/request bounds explicit and keep them distinct from economic TTL/deadline; no asynchronous thread termination is used.

## Phase F — Restart/configuration adjacency

Run deterministic/fresh-process scenarios for:

- crash while money-moving dispatch was started;
- restart after callback but before local provider return/process death;
- provider opportunity removal/config revision change while unresolved operation remains pinned;
- stale decision commit after callback/restart;
- stale due-work item.

Expected: local interaction identity disappears on process death; durable recovery remains governed by operation phase/contract/ownership and existing status lookup/idempotent retry rules.

Current evidence: durable crash campaign (6/24), restart/recovery (103/264), configuration crash consistency (1/28), coordinator races (13/55) and due-worker concurrency (7/97) all pass. They cover crash during dispatch/reconciliation, restart after safe release or settlement, pinned provider removal, stale committed decisions and stale due work. The new fence remains process-local and is intentionally absent after fresh Coordinator construction; no cross-process exactly-once claim is made.

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

Current evidence: exact-case composition is green (`case_fidelity_campaign_test` 2/163, deterministic matrix 1/40, demo 2/12, bounded history evidence 2/15 and long-history replay 1/2010). The required Rake matrices are green: `property` 4/1,210, `model` 3/2,613, `concurrency` 30/1,163 and `fault` 344/4,203, all with zero failures/errors/skips. Fresh exact-candidate bounded measurements on CRuby 4.0.6: 10k lifecycle 40.3602 s / 247.8 ops/s / 140,002 facts; 2,000-payout degradation 2,247 attempts with 228 fallback recoveries; history profile 500 payouts 7,002 facts and 315.3 concurrent ops/s. The 12,500-sample read-path profile reports median/p95 analytics 0.000384/0.000539 s, typed analytics 0.000489/0.000519 s, explanation 0.000443/0.000618 s and due-work-empty 0.004463/0.005035 s; fact-snapshot p95 0.114104 s is recorded as variability. These are bounded evidence, not 100k or production-scale claims, and no new performance change is justified.

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

## Fresh skeptical discovery finding — stale authoritative health evidence

The candidate pass produced a deterministic counterexample outside the original
economic-effect cases. With `authoritative_sequence=true`, an applied
`sequence=2` success followed by a new stale `sequence=1` provider failure did
not change payout lifecycle, but `Coordinator#apply_observation` still emitted
health evidence and degraded the provider. That could suppress healthy future
traffic even though the observation was explicitly rejected by the provider
ordering contract.

The focused fix gives `ObservationLedger::Decision` an explicit
`health_evidence?` result: transport classification remains admissible,
authoritative observations require a new sequence, and non-authoritative late
observations retain their existing operational-health semantics. The durable
observation records this derived decision and restore validates any emitted
health signal against it. The follow-up pass then found that a late accepted
sequence did not advance the durable ordering cursor, allowing an older late
event to be treated as fresh. The minimal fix advances that cursor through
live observation, restore and replay. Focused ledger, restorer,
projection/replay and health suites are green. A second follow-up pass found
and fixed exact duplicate replay after cursor advancement; the fresh skeptical
discovery is now clean and the revision remains a `VERSION_CANDIDATE` until
the final exact-HEAD closure evidence is recorded.

## Fresh follow-up counterexample — late authoritative sequence did not advance the cursor

The second skeptical pass constructed a released operation with applied
sequence 2, then delivered late sequence 4 followed by late sequence 3. The
sequence-4 event was correctly lifecycle-non-applying but eligible for health;
because the cursor only advanced for lifecycle-applying events, sequence 3 was
also classified as fresh and could degrade the provider. This violated the
ordering contract at the health projection boundary.

The fix keeps one shared authoritative cursor: every new sequenced observation
advances it to the greatest observed sequence, whether or not lifecycle
applies. Live decisions, durable restore and replay use the same rule. The
regression asserts exact health facts, cursor value and restart parity. A
second skeptical reproducer found that an exact duplicate replayed after a
newer sequence was incorrectly judged against the current cursor; the ledger
now preserves the original derived decision with the dedup identity so replay
remains idempotent without weakening contradictory-payload validation.

## Fresh follow-up counterexample — exact duplicate replay after cursor advance

The skeptical pass then replayed an exact durable observation after a newer
authoritative observation had advanced the cursor. Restore incorrectly
recomputed the old observation against the current cursor and rejected its
original `applied` decision as stale. The fix stores the original derived
decision with the observation identity signature, checks exact identity before
current ordering, and still rejects forged duplicate decision flags. The
deterministic unit regression and the full local matrix are green.

## Final closure evidence

The independent skeptical pass on the actual production paths found no new
material locally solvable P0/P1. The final exact-head local workflow is green:
`bundle check`, `test` 655 runs, `property` 4 runs, `model` 3 runs,
`concurrency` 30 runs and `fault` 344 runs, all with zero failures, errors or
skips. The property/model/fault assertion totals are 1,210/2,613/4,203;
concurrency and full-test assertion totals vary with their reproducible seeds.
Focused SPEC-009 races, acceptance traceability, exact-case campaign,
restart/crash, replay, history, analytics, API and demo evidence are green.

Fresh bounded CRuby 4.0.6 product evidence measured 10k lifecycle at
40.3602 s / 247.8 ops/s / 140,002 facts; 2,000-payout degradation at 2,247
attempts with 228/228 fallback recoveries; 500-payout history at 7,002 facts
and 315.3 concurrent ops/s; and a 12,500-sample read-path profile with
analytics p95 0.000539 s, typed analytics p95 0.000519 s, explanation p95
0.000618 s and due-work-empty p95 0.005035 s. Fact-snapshot p95 variability
of 0.114104 s is recorded; no 100k production claim is made.

The hosted GitHub Actions endpoint returned HTTP 404 and is not claimed green.
The checked-in workflow was executed locally on the exact closure revision;
the hosted visibility limitation is recorded rather than hidden.

## Explicit non-goals

No new allocation strategy, dashboard, PSP-brand adapter, database, queue, distributed lease, microservices, generalized rules DSL, ML/bandits or cosmetic Coordinator split.

## Stop policy

The v0.3.5 closure is complete after SPEC-009 P0/P1 was verified/falsified,
the fresh skeptical pass was clean, exact-head local CI was green and all
normative documents agreed. Authoritative TZ arrival still triggers immediate
reconciliation mode.
