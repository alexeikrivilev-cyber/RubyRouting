# Goal Mode + SpecOps Workflow

Current Version Goal: **v0.3.4 — Pre-TZ Adversarial Case Fidelity & Edge Hardening — ACTIVE (REOPENED)**.

## Operating loop

`Discover -> Hypothesize -> Specify -> Plan -> Reproduce/Falsify -> Implement/Prove -> Verify -> Skeptical Review -> Reconcile -> Discover next gap`

The final discovery step is mandatory and is not the same as checking that the plan is finished. A previously closed version may be reopened by new material evidence.

## Discover

Read SPEC-008/active ExecPlan/backlog/architecture/completion rules first, then inspect exact HEAD, production code, tests and current CI.

Do not infer implementation state from a historical closure label. The v0.3.4 closure at `799f6977f07310105c30be9df549a536cc9d665d` is evidence from that checkpoint; the current status is ACTIVE because a later audit found a new P0 hypothesis.

## Hypothesize

Every slice begins with a falsifiable statement or measured bottleneck. Current highest-priority hypothesis:

> a duplicate/stale/non-applying observation can clear a process-local interaction marker owned by a still-running recovery invocation and allow a second worker to start the same provider interaction concurrently.

Do not start with a desired refactor.

## Specify

Behavior changes map to SPEC-008 or compatible inherited guarantees. Safety ambiguity is conservative.

For the current recovery slice distinguish:

- durable economic ownership;
- durable operation/recovery legality;
- process-local provider invocation ownership;
- provider observation evidence.

Do not collapse them into one boolean state.

## Plan

Use `docs/exec-plans/active/pre-tz-adversarial-edge-hardening.md` for substantial work. Plans are living, outcome-based and falsifiable.

## Reproduce / Falsify

For a P0 concurrency hypothesis, build deterministic barriers/queues/latches before changing production code. Record the exact interleaving and assert provider call counts/facts, not only final payout status.

If the hypothesis is falsified by the existing code, add the regression that proves it and close the slice without code churn.

## Implement / Prove

Work in coherent vertical slices.

Rules:

- preserve financial/economic invariants first;
- keep provider I/O outside atomic/configuration locks;
- keep one coherent configuration snapshot per decision;
- keep provider semantics at adapters/normalizers;
- keep exact Ruby arithmetic for money/allocation/rates;
- treat outcome counts separately from allocation measures;
- derived performance caches/indexes are rebuildable and never economic truth;
- a process-local interaction token is not durable recovery state;
- only the live invocation that owns a guard/token may release it;
- an unrelated callback is lifecycle evidence, not implicit completion of another invocation;
- do not add speculative platform components while a simpler case-relevant proof exists.

## Verify

Use risk-appropriate layers from `docs/TESTING.md`.

For the current P0 run focused interaction races first, then recovery/restart/fault adjacency, then full test/property/model/concurrency/fault matrix and exact-HEAD CI.

Every randomized material failure preserves a reproducible seed/trace. Every P0 concurrency claim uses controlled synchronization rather than sleep.

## Skeptical Review

Try to falsify the changed slice:

- Can duplicate/stale callback release a newer live invocation?
- Can two workers both invoke provider for the same committed recovery token?
- Can an exception leak or over-release a token?
- Can success leave a stuck token?
- Can restart depend on process-local token state?
- Can UNKNOWN release/switch accidentally?
- Can a stale start commit become executable?
- Can config crash/restart produce a mixed generation?
- Can analytics mix incompatible populations?
- Did API/demo gain a second routing or success formula?

Fix material findings before moving on.

## Reconcile

After a verified slice:

1. update active ExecPlan with exact evidence;
2. update backlog status or add a newly discovered item;
3. update decisions/architecture for material semantic changes;
4. run broader verification proportional to blast radius;
5. select the next highest-value unblocked slice.

Do not ask for permission to continue when the next step follows from active sources and code.

## Candidate / closure workflow

When every known P0/P1 appears green:

1. set `VERSION_CANDIDATE` only;
2. execute the independent skeptical stage in `docs/COMPLETION_POLICY.md` against the changed code;
3. ignore prior closure publications as proof;
4. any material finding returns the version to ACTIVE;
5. run final exact-HEAD verification/CI only after a clean skeptical pass;
6. synchronize README, AGENTS, SPEC, ExecPlan, backlog, ROADMAP and Completion Policy;
7. only then may `VERSION_COMPLETE` be published.

## If blocked

A path is not externally blocked because it is difficult or because a test is red. Change tactic after repeated failures. Missing official TZ is not a blocker while independent case-relevant work remains.

When authoritative TZ arrives, immediately switch to `docs/TZ_RECONCILIATION.md`.
