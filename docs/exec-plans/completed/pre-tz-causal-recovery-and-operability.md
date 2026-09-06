# ExecPlan — v0.3.6 Causal Recovery Safety & Operator Readiness

Status: VERSION_COMPLETE

## Purpose / Big Picture

Take the completed v0.3.5 financial kernel and attack the last known generic causal-recovery gaps before TZ. First prove whether technically read-only status resolution and process death can reopen cross-provider double-effect risk. Only after financial P0 closure, improve operator usability through typed configuration ingress and a bounded recovery executor.

## Governing sources

1. direct current instruction;
2. `specifications/010-pre-tz-causal-recovery-and-operability.md`;
3. this ExecPlan;
4. `docs/PRE_TZ_BACKLOG.md`;
5. `docs/PRE_TZ_ARCHITECTURE_V03_6.md`;
6. `docs/DECISIONS_V03_6.md`;
7. compatible inherited SPEC-009 guarantees.

## Starting repository evidence

Baseline revision: `e9751d67c3b999d140bacbbc9ac4057c7792b506`.

At that revision:

- v0.3.5 is `VERSION_COMPLETE`;
- exact-head GitHub Actions run `33555861163` is actually green for both `Fast Ruby verification` and `Bounded product evidence`;
- `Coordinator` marks `initiate` interactions money-moving and `resolve` interactions non-money-moving;
- fresh assignment is fenced only while a live `money_moving` token exists;
- an existing v0.3.5 regression explicitly permits fresh provider B while a blocked `resolve(A)` is live after an independent release callback;
- current blocking resolve test returns UNKNOWN, so the economically decisive late-SUCCESS variant is not proven;
- process-local interaction tokens intentionally disappear on restart;
- typed `RoutingConfiguration`/compiler and Commands publication exist, but no transport-neutral decode boundary exists;
- `due_work` and `resume` exist, but no small canonical application executor owns one bounded recovery pass.

## Current evidence checkpoint — 2026-09-02

The first two P0 hypotheses reproduced deterministically on the current worktree:

- a blocked `resolve(A)` plus an independent safe-release callback previously allowed a fresh `B` assignment before late `SUCCESS(A)`;
- a fresh Ruby process previously treated a persisted independent release plus a missing local completion as sufficient to start `B`.

Raw timeout and adapter exception variants reproduced the same unsafe release shape. A further adversarial reproducer found that `definitely_not_sent` from a live `resolve` was also unsafe when interpreted as payout release: it proves only that the lookup exchange was not sent, not that the original initiate was not sent. Explicit `definitely_not_sent` on initiate/retry and `ambiguous_after_possible_send` retain their distinct semantics.

The minimal implemented correction is a causal hold on an external safe provider-failure observation while the pinned operation is unresolved. The observation is durably marked `causal_hold: true, applied: false`; only an observation returned with the owning interaction token can release that hold. A later owning `SUCCESS` is applied, settles the payout and emits an explicit `causal_release_contradiction` conflict. Fresh-process resume retains the original operation and uses same-provider resolution/retry only.

The adjacent duplicate-identity probe also found that a provider may reuse one
`observation_id` for an independent callback and the owning invocation result.
The owning duplicate now emits a narrow `provider_interaction_completed` fact,
applies the held outcome and reuses the existing lifecycle reducer; replay
restores that fact before the already-published release/settlement facts. A
callback-only duplicate remains a no-op and cannot release the owner.

A further identity probe found that the owning invocation may attach a positive
locally measured `interaction_duration_seconds` while the earlier callback has
no local duration. That metric is now retained for health/analytics telemetry
but excluded from observation identity, so valid owning completion cannot be
misclassified as payload reuse. Provider event identity fields remain checked.

Focused economic, duplicate-identity, fresh-process crash, fresh-process
TTL/reconciliation, observation-ledger, restart/replay and concurrency
verification are green. The adjacent review also found and closed three
interaction-boundary defects: direct normalized resolve observations bypassed
transport scoping, generated transport IDs collided across exchanges, and
non-provider safe-release attribution could release ownership during a live
economically decisive interaction. The later candidate-pass restore-linkage
finding is also fixed and the full local matrix is green. The version had
entered `VERSION_CANDIDATE`, but the first independent candidate pass found a
replay-integrity gap: `Replay.lifecycle` accepted a causal completion after
ownership release. The replay projection now enforces the same current-owner
invariant as durable restore. Fresh focused, broad, acceptance, exact-case,
operator-composition and fresh-process evidence for the correction is green at
pushed revision `ddb7fd453c6c4e14b2b484961425702ef2713189`; the subsequent
independent code-first skeptical discovery and final exact-head
verification are recorded below.

## Protected baseline

Do not reopen count/volume allocator, UNKNOWN semantics, v0.3.5 initiate fence, observation sequence fixes, analytics, configuration generation publication or durability architecture without a new reproducer.

## Phase 1 — economically decisive resolve P0 — IMPLEMENTED

Goal: deterministically prove/falsify S10-001.

Immediate actions:

1. create blocking status-lookup provider where `resolve` can later return SUCCESS;
2. drive UNKNOWN -> blocked resolve -> independent safe release -> canonical continuation;
3. assert whether B starts before resolve completes;
4. release resolve and assert exact monetary/conflict facts;
5. repeat with UNKNOWN/ambiguous resolve completion and authoritative-sequence variant.

If current behavior permits B before a late SUCCESS(A), preserve the red reproducer.

Do not fix by putting provider I/O under Coordinator mutex.

Evidence: `test/concurrency/economic_effect_safety_test.rb` covers live resolve, retry, late success/ambiguous/definitely-not-sent, raw timeout/adapter exception, direct normalized transport observations, duplicate provider observation identity, interaction-specific transport IDs and authoritative ordering; provider B call count remains zero until the causal window is closed. The new transport-variant campaign also proves that a definitely-not-sent `resolve` retains UNKNOWN/ownership and keeps B at zero.

## Phase 2 — crash/durable causality P0 — IMPLEMENTED

Goal: prove/falsify S10-002/S10-003.

Use a real fresh-process or crash/journal harness:

1. persist intent/decision/attempt_started for A;
2. persist an independent release observation while local invocation has no durable completion evidence;
3. terminate process before owning invocation can publish its completion/classification;
4. restore in a new Ruby process;
5. attempt canonical continuation and observe whether B can start;
6. repeat with raw timeout/adapter exception and explicit ambiguous/definitely-not-sent transport classification.

If unsafe, design the smallest replayable causal-completion state. Candidate questions, not mandated implementation:

- should a fact distinguish local invocation completion from independent callback delivery?
- should a release become pending/reconciliation-blocked while a started dispatch lacks conclusive completion evidence?
- can existing `attempt_started` plus new completion provenance express the invariant without a second state machine?

Any durable addition must be fail-closed and replay/restorer validated.

Evidence: `test/scenario/durable_crash_campaign_test.rb` drives child processes, persists independent callbacks, terminates owning processes with `Process.exit!`, and resumes in fresh Ruby processes. The fresh process records same-operation A resolution, no B call, no ownership release and replayable causal facts; a second campaign crosses a persisted causal hold and deterministic TTL transition into `reconciliation_blocked` before process death.

## Phase 3 — adjacent recovery/order verification — VERIFIED

Challenge the chosen safety model against:

- v0.3.5 blocked initial/retry initiate races;
- invocation token ABA/wrong owner release;
- authoritative/non-authoritative provider sequence;
- stale/duplicate callbacks;
- status lookup returning success/failure/unknown;
- provider removed/disabled/config revision changes;
- operation TTL/deadline;
- stale DecisionCommit and due-work item;
- restart at each new durable boundary;
- late settlement/conflict/reversal projections.

The interaction-scoped transport correction is now implemented for both typed
transport results and directly returned normalized observations: `resolve`
transport `definitely_not_sent` maps to conservative UNKNOWN rather than safe
route failure, while initiate/retry behavior is unchanged. Generated transport
observations now carry a durable-derived interaction ordinal, preventing
cross-exchange identity collisions. A TTL-boundary reproducer also found and
fixed that an independent safe release in `reconciliation_blocked` could
otherwise erase the unresolved owner; it is now a causal hold. The broader
adjacency and fresh closure evidence are recorded in the completed verification
below.

## Phase 4 — configuration ingress P1 — IMPLEMENTED

Enter only after P0 is stable.

Goal: expose existing typed configuration as a strict transport-neutral product input without inventing official judge schema.

Preferred acceptance:

- `RoutingConfiguration.decode(config.to_h).to_h == config.to_h` or equivalent named boundary;
- representative count/volume/recovery/constraints/ranking/provider-capability round-trips;
- strict unknown-field and malformed nested-value rejection;
- compile diagnostics preserved;
- application publication only through Commands;
- optional JSON helper using Ruby stdlib; YAML/HTTP write endpoint not required.

Evidence: `RoutingConfiguration.decode` accepts the closed canonical Hash/JSON vocabulary, rejects unknown/duplicate/malformed values and Float/coercion, round-trips representative count/volume configurations, and leaves publication to `Commands#apply_configuration`. Focused ingress and full local test verification are green.

If future TZ fields require a broader schema, reconcile them explicitly rather than widening this boundary implicitly.

## Phase 5 — bounded recovery executor P1 — IMPLEMENTED

Goal: remove operator boilerplate without introducing infrastructure.

Implement/prove a small application component that performs one deterministic bounded pass:

`queries.due_work -> for each work item -> service.resume`.

Requirements:

- explicit `limit`/one-pass bound;
- deterministic result records;
- no provider selection logic;
- no queue/background thread/lease;
- duplicate callers remain safe through existing Coordinator invariants;
- API exposure optional unless it clearly reuses the same component.

Evidence: `Application::RecoveryExecutor#run(limit:, as_of:)` performs one sorted, query-bounded pass and returns immutable per-item results. It records the injected/effective `as_of`, exposes a bounded summary, and calls only `Service#resume`; provider exception details are structured without changing payout classification. Zero-limit and duplicate-worker tests are green.

## Phase 6 — composition and skeptical closure — VERSION_COMPLETE

The operator composition campaign covers decoded configuration, Commands publication, count routing, UNKNOWN plus safe recovery fallback through the executor, volume routing, analytics and fresh journal restore/replay parity. Known scope is green and the independent skeptical discovery and final exact-head closure are recorded below.

The candidate gate was entered after known work became green. Fresh code-first skeptical discovery found no new material locally solvable P0/P1, and the final exact-head closure below is green.

## Candidate skeptical discovery — 2026-09-02

The pass ignored backlog completion labels and challenged the changed replay
boundary plus adjacent product paths. The current-owner and padded-identity
completion cases were run against the projection; live causal races, durable
restore, fresh-process crash/TTL recovery, duplicate/stale callbacks,
authoritative ordering, v0.3.5 initiate/retry fences, provider/config changes,
stale due work, strict configuration ingress, executor duplicate callers and
count/volume/analytics composition were re-run through focused suites. Static
inspection found only expected abstract provider methods, test synchronization
and bounded exception boundaries; no provider I/O under correctness/config
locks, no new financial Float path, no unseeded randomness and one active
ExecPlan.

Fresh evidence at pushed `ddb7fd4` is green: full test 685/12015, property
4/1210, model 3/2958, concurrency 43/1379, fault 355/4326, acceptance
traceability 1/1001, exact case 2/163, operator composition 1/18,
fresh-process crash 8/62, history profile 2/15. The workflow's local product
evidence also passed benchmark, 10k load, degradation, history profile and
demo commands on CRuby 4.0.6; these remain bounded measurements rather than
production-scale claims. No material counterexample was found in this pass.

## Verification matrix

Minimum after material safety changes:

- focused new concurrency tests;
- fresh-process restart/crash tests;
- `bundle exec rake test`;
- `bundle exec rake property`;
- `bundle exec rake model`;
- `bundle exec rake concurrency`;
- `bundle exec rake fault`;
- acceptance traceability;
- exact-case campaign;
- current GitHub Actions on exact pushed HEAD.

Run benchmarks only if changed paths/claims can materially affect them.

## Final closure — 2026-09-02

The independent skeptical discovery above was clean. The final documentation
closure is at exact pushed HEAD `0988a6248e71f2cbc7a859a4813bac029dfdba4d`.
GitHub Actions run `33629453611` completed successfully; both
`Fast Ruby verification` and `Bounded product evidence` check-runs are green.

Exact-head local verification on CRuby 4.0.6 is green:

- `bundle check`;
- `bundle exec rake test`: 685 runs / 12007 assertions;
- `property`: 4 / 1210;
- `model`: 3 / 2958;
- `concurrency`: 43 / 1380;
- `fault`: 355 / 4326;
- acceptance traceability: 1 / 1001;
- exact-case: 2 / 163;
- operator composition: 1 / 18;
- fresh-process crash/recovery: 8 / 62;
- history profile: 2 / 15.

The bounded product evidence commands also passed benchmark, 10k load,
degradation, history-profile and demo checks. These are bounded measurements,
not unsupported production-scale claims. All required P0/P1 evidence is
current, active documentation agrees, and no material locally solvable finding
remains.

Latest discovery: local interaction duration was proven non-identity telemetry
by a deterministic callback/owning-invocation barrier test and removed from the
duplicate signature without changing safety or provider-event checks.

Latest P0 review: direct normalized transport output, generated transport event
identity and safe-release attribution are now interaction-scoped; the fresh
process TTL campaign proves the extended causal hold survives restart.

Candidate gate reopened by independent review: durable observation restore could
accept a persisted causal hold for a non-current operation when that old
operation still carried an unresolved phase. The reducer now requires the held
observation operation to equal the current owner; a deterministic regression is
green; final exact-head verification is recorded above.

Candidate gate reopened again by replay review: `Replay.lifecycle` accepted a
`provider_interaction_completed` fact after `ownership_released`. The replay
projection now requires matching current ownership before applying a held
observation; `ReplayTest#test_lifecycle_replay_rejects_causal_completion_after_ownership_release`
is the deterministic regression. The same boundary now canonicalizes padded
source/completion identities, covered by
`ReplayTest#test_lifecycle_replay_canonicalizes_padded_causal_completion_identity`.

Those candidate findings were corrected and included in the exact-head closure
above.

## Stop policy

A red reproducer is work, not a blocker. A green focused fix is not completion. Missing official TZ is not a blocker.

Stop v0.3.6 only under `docs/COMPLETION_POLICY.md` or on the authority switch to `docs/TZ_RECONCILIATION.md`.
