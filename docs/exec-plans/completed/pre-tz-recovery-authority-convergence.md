# ExecPlan — v0.3.11 Recovery Authority Convergence

Status: **VERSION_COMPLETE**.

Opening HEAD: `74e26a9aa774ecbc8cef2f6bcd9256539a885b29`.

Latest verified code checkpoint: `23403c554d5af2ea17609dfdc305751a1d64cba4`; Actions run `33754861237` is green. Candidate docs checkpoint: `9604a35630551ee1284b9fc56dd4e53fdc7afd81`; Actions `33756341322` green.

Governing spec: `specifications/015-pre-tz-recovery-authority-convergence.md`.

Protected completed baseline: **v0.3.10 / SPEC-014 — VERSION_COMPLETE**. Verified code-bearing tree `ba00d7dc0d77e328d300bfc9418b96ebe89ede70`, Actions `33740328533` green. Docs/evidence closure HEAD `74e26a9aa774ecbc8cef2f6bcd9256539a885b29`, exact-head Actions `33741033247` green.

## Current verified working-tree state

The exact starting `main` was `2226566f8014b9eff972b626d661daab52d0c5ce`, equal to
`origin/main` and clean before this slice. The opening hypotheses were both
reproduced deterministically before production changes:

- a live post-return `ProviderContractError` or `ApplicationProcessingError`
  released the guard and was immediately advertised as `restart_recovery` in
  the same process, while a fresh process correctly rediscovered the pinned
  operation;
- raw repeated resolution failure bypassed the resolution budget and
  configured delay, permitting another same-provider interaction immediately.

The latest verified code checkpoint is `23403c554d5af2ea17609dfdc305751a1d64cba4`.
The first candidate blind pass then reproduced a third provenance gap: a fatal
adapter/programming `ScriptError` released the live guard without any marker,
so the same live process could advertise poison `restart_recovery` work when a
status-lookup capability was present. The fix generalizes the process-local
marker to retain `:post_return` versus `:fatal` provenance; a fresh Coordinator
still has no marker and can rediscover the exact pinned operation from durable
facts. Focused and adjacent suites are green; fresh broad verification is
complete on this code-bearing checkpoint.

## Purpose

Converge recovery execution authority after the fresh post-v0.3.10 audit. Do not broaden the product. The session must determine, with executable evidence, whether raw-provider, restart-derived and post-return failure paths can bypass the same provenance/budget/timing rules that govern normal UNKNOWN recovery.

The target question is deliberately narrow:

> Given one already-pinned provider operation, may another same-provider interaction execute now, and which single authority decides that across normal recovery, raw provider failure and genuine restart?

## Operating loop

`orient -> verify exact main/CI -> reproduce/falsify -> state invariant -> smallest coherent fix/evidence-close -> focused verify -> adjacent recovery/restart/replay/concurrency/fault review -> case regression -> checkpoint -> next highest-value slice`.

Do not stop after one reproducer, one green patch, a ticket, a commit or a passing suite. Do not implement from documentation assumptions alone.

## Phase 0 — exact re-orientation

Before production code:

- fetch exact current `main` and current CI;
- read SPEC-015, this plan, current Coordinator/Orchestrator/Recovery/RecoveryExecutor/Queries paths and relevant tests;
- inspect `restart_recovery_work_for`, `provider_execution_failure_work_for`, `resume_operation`, `Recovery.classify`, `RecoverySchedule`, `provider_interaction_failed`, `provider_interaction_ended` and HTTP error mapping;
- verify v0.3.10 protected tests still describe actual behavior;
- reproduce both opening P1 hypotheses against exact HEAD.

Any financial P0 immediately preempts the plan.

## Phase 1 — false restart work after live post-return failure

Build paired deterministic scenarios without changing production code first.

### 1A Provider contract failure

`initial UNKNOWN -> scheduled/due resolve -> provider returns malformed linkage -> ProviderContractError -> same-process due_work immediately`.

Assert exact phase, ownership, provider/operation/attempt identity, interaction counters, live guard, `provider_execution_failed` absence, due-work reason/action and RecoveryExecutor behavior on a subsequent pass.

### 1B Application processing failure

Inject a valid provider return followed by application-owned processing/classification/duration failure. Assert the same state dimensions and immediate due-work.

### 1C Genuine restart control

Produce the comparable durable `attempt_started` state, terminate the process, restore fresh, and prove safe same-provider work remains discoverable only from persisted capability.

### Decision

If same-process post-return failures are advertised as `restart_recovery`, treat that as a reproduced provenance divergence unless evidence demonstrates an intentional superior contract. Implement the smallest distinction between a genuine restored in-flight operation and a live-process post-return failure.

Preferred constraints:

- no synthetic provider observation;
- no ownership release;
- no fresh fallback;
- no durable lease/scheduler;
- no broad exception handling;
- process-local provenance is preferable to durable financial state if sufficient.

Status: **VERIFIED in the working tree**. `RecoveryExecutorTest` covers both
post-return failure classes, exact ownership/phase/identity/facts and a real
fresh Ruby process probe. The live marker suppresses same-process false
restart work but is not durable; a fresh Coordinator retains the safe pinned
recovery derived from durable facts.

## Phase 2 — recovery budget/timing convergence

Reproduce repeated raw failure under a deliberately tiny recovery budget.

Minimum campaign:

1. `max_resolution_interactions = 1`;
2. provider initiate becomes UNKNOWN or raw-fails into a pinned recoverable operation;
3. status lookup repeatedly raises raw `Timeout::Error`;
4. run repeated RecoveryExecutor passes;
5. record provider calls, `resolution_interaction_count`, due-work, reason codes, schedules and phase.

Repeat for idempotent-retry capability and for fresh-process restart-derived work where applicable.

Challenge non-zero `initial_delay_seconds`/`backoff_seconds`, TTL/deadline expiry and reconciliation-blocked precedence.

If raw/restart paths bypass budget or timing, converge them under one pure same-provider recovery eligibility authority. Provenance may remain distinct, but execution permission must not diverge.

Do not create a second recovery state machine or scheduler. Reuse/extend the existing Recovery policy semantics or extract one narrow shared gate if needed.

Status: **VERIFIED in the working tree**. Raw initiate with status lookup and
idempotent retry, repeated raw resolve, zero budget, non-zero initial delay
and backoff, restart-derived work, TTL/deadline precedence, reconciliation
precedence and concurrency/restart/replay adjacency are covered. Raw and
restart callers now share `Routing::Recovery.same_provider_action`; due time
for a raw marker is derived from the pinned policy and cannot be bypassed by
`Service#resume`.

## Phase 3 — concurrency and restart adjacency

After any Phase 1/2 material fix:

- duplicate RecoveryExecutor workers;
- money-moving idempotent retry under contention;
- read-only resolve under contention;
- crash between due-work scan and canonical resume;
- crash after `attempt_started` before provider return;
- raw failure marker before/after restart;
- replay/restore malformed marker/provenance evidence;
- configuration/provider-adapter absence on pinned recovery.

Assert no duplicate money-moving execution and no fresh-provider movement while ownership remains unresolved.

Status: **VERIFIED in the working tree** by the recovery, restart, replay,
concurrent-worker and fault-adjacent suites; rerun the complete matrix after
the final documentation/checkpoint changes.

## Phase 4 — synchronous raw-provider HTTP honesty

Only after recovery authority is coherent, reproduce synchronous raw provider failure through real `HttpApp` submit/resume.

Decide whether generic `500 internal_error` is sufficiently honest pre-TZ. If changing, define a stable provider-execution/unresolved 5xx that:

- leaks no adapter text;
- does not imply the payout intent was rejected before commitment;
- keeps provider-contract and application-internal failures distinct;
- directs continuation through same payout id/status/recovery rather than a new economic intent.

Evidence-close as TZ-gated if a new public status would be speculative.

Status: **EVIDENCE-CLOSED / TZ-GATED**. A real HTTP valid submit whose adapter
raises a raw timeout returns the existing non-leaking generic 500 while the
committed unresolved owner and canonical due work remain queryable. No new
public status is invented before an authoritative API contract.

## Phase 5 — `due_work(as_of:)` contract precision

Verify tests/docs describe the intended model: causal cutoff over current unresolved state, not historical time-travel reconstruction. Add a regression demonstrating that a currently resolved payout does not reappear when queried with an older `as_of`, while no current work item may rely on future evidence.

Prefer documentation/test clarification over a historical projection implementation.

Status: **EVIDENCE-CLOSED**. The regression demonstrates that an older
`as_of` is a causal cutoff over current unresolved state, not a historical
time-travel reconstruction, and does not mutate facts.

## Phase 6 — case fidelity regression

Run the canonical case evidence after recovery changes:

- count strategy target/actual;
- volume strategy target/actual;
- safe fallback after releasable provider failure;
- UNKNOWN blocks unsafe cross-provider movement;
- RecoveryExecutor resolves the pinned operation;
- complete attempt history;
- success/fallback analytics;
- deterministic demo output and independent strategy runtimes.

No demo-only routing math or new strategy is allowed.

## Phase 7 — traceability and candidate

Map SPEC-015 claims to executable evidence. Update acceptance traceability only after behavior exists.

Run focused + broad verification. Known required scope green => **VERSION_CANDIDATE**, not complete.

## Phase 8 — blind skeptical discovery

Ignore ticket status and re-audit actual code for:

- another path that decides same-provider recoverability independently;
- budget/backoff/TTL/deadline bypass;
- poison work that repeatedly aborts bounded executor passes;
- wrong fresh-provider movement;
- provider/application/client provenance confusion;
- live vs fresh-process vs replay divergence;
- incorrect `as_of` claims;
- case/demo regression;
- stale evidence/docs.

Any material locally solvable P0/P1 returns ACTIVE.

The first candidate pass found and reproduced the fatal adapter/programming
provenance gap described above. It is now covered by same-process suppression,
fresh-process discoverability and fatal-apply adjacency regressions. A second
post-fix blind pass searched the same neighboring paths and found no additional
material P0/P1.

## Phase 9 — closure

Only after clean blind discovery:

- fresh `bundle check`;
- full `bundle exec rake test`;
- property;
- model;
- concurrency;
- fault;
- focused recovery/provenance/fresh-process campaigns;
- case/demo/acceptance evidence;
- push exact final HEAD;
- verify GitHub Actions on that exact SHA;
- synchronize README/AGENTS/spec/plan/backlog/roadmap/completion/session/workflow/index/TZ docs;
- archive this plan to `completed/` only when the evidence contract is satisfied.

Closure evidence: fresh candidate `9604a35630551ee1284b9fc56dd4e53fdc7afd81`
passed Actions run `33756341322`; local exact matrix passed with test
`740/12963`, property `4/1210`, model `3/2958`, concurrency `45/1448`, fault
`407/4900`, acceptance traceability `1/1313`, case `2/163` and operator
`1/18`, all with zero failures/errors/skips. Focused provenance, restart,
replay, due-worker and HTTP suites were also green.

## Rolling next actions

1. no mandatory implementation work remains after the clean post-candidate blind pass;
2. fresh exact matrix and case/operator/traceability evidence are green;
3. archive this completed plan and preserve the evidence references above.

## Candidate blind skeptical pass

The initial candidate checklist pass was clean on the earlier code-bearing tree
at `a39728ed407a30fc5b44af88542ffa6eb9a3a1e1`; it was not the final blind
closure pass. It ignored backlog labels and searched the reachable
implementation for:

- independent same-provider action authorities and direct capability-only
  execution paths;
- raw/restart budget, delay/backoff, TTL/deadline, reconciliation and live
  interaction bypasses;
- poison due work after provider-contract/application failure;
- callback marker clearing on malformed linkage or rejected duplicate payload;
- provider/client/application provenance leakage at RecoveryExecutor and HTTP;
- live/fresh-process/replay identity drift and case/demo regressions.

That initial pass was followed by a blind extension that reproduced the fatal
adapter/programming provenance gap described in Phase 8. The latest material
fix is on `23403c554d5af2ea17609dfdc305751a1d64cba4`; its focused, adjacent and
fresh broad verification is green. A second post-fix blind pass then searched
the same neighboring paths and found no additional material P0/P1. The version
passed the candidate gate, final fresh evidence and exact pushed-head Actions.
No material locally solvable P0/P1 remained, so v0.3.11 is VERSION_COMPLETE on
the published closure HEAD.

## Stop policy

v0.3.11 is closed on the published closure HEAD. If authoritative TZ arrives,
switch immediately to `docs/TZ_RECONCILIATION.md`; otherwise freeze generic
pre-TZ kernel work until new deterministic evidence or authority appears.

Red tests, difficult bugs, uncertain implementation shape, a passing focused suite or missing TZ are not blockers.
