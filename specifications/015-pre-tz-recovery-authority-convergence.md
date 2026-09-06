# SPEC-015 — Pre-TZ Recovery Authority Convergence

Status: **VERSION_COMPLETE**.

Version Goal: **v0.3.11 — Recovery Authority Convergence**.

Opening HEAD: `74e26a9aa774ecbc8cef2f6bcd9256539a885b29`.

Latest verified code checkpoint: `23403c554d5af2ea17609dfdc305751a1d64cba4`; Actions run `33754861237` is green. Candidate docs checkpoint `9604a35630551ee1284b9fc56dd4e53fdc7afd81`; Actions run `33756341322` is green.

Protected completed baseline: **v0.3.10 / SPEC-014 — VERSION_COMPLETE**. Verified code-bearing tree: `ba00d7dc0d77e328d300bfc9418b96ebe89ede70`, Actions run `33740328533` green. Subsequent docs-only closure/evidence HEAD: `74e26a9aa774ecbc8cef2f6bcd9256539a885b29`, exact-head Actions run `33741033247` green.

## Purpose

Close the remaining generic pre-TZ recovery-authority inconsistencies found by a fresh code-first audit after v0.3.10. The economic kernel remains protected. The target is one coherent answer to: **may this already-pinned provider operation execute another same-provider interaction now, and under which policy/provenance constraints?**

The current implementation has mature normal UNKNOWN recovery, raw-provider execution markers and restart-derived recovery. The new audit found plausible divergence between those paths around genuine restart provenance, provider/application failure provenance, resolution budgets and retry timing. SPEC-015 exists to reproduce or falsify those gaps, converge authority minimally where required, and then freeze generic pre-TZ development again.

## Case contract

The case still requires configurable count/volume payout distribution, safe fallback, complete attempt history and analytics. Recovery convergence matters because provider refusal/non-response handling must be safe **and** bounded: no duplicate economic owner, no unsafe cross-provider movement, no poison item that is automatically re-executed forever, and no raw-failure path that silently ignores configured recovery limits.

## Protected invariants

Do not weaken these without a deterministic counterexample or authoritative TZ requirement:

- one payout has at most one unresolved economic owner;
- ambiguous-after-possible-send remains UNKNOWN unless stronger evidence exists;
- UNKNOWN never enables fresh-provider money movement;
- same-provider status lookup/idempotent retry is distinct from fresh fallback;
- provider-local idempotency is not cross-provider idempotency;
- provider I/O remains outside Coordinator/configuration locks;
- count/volume allocation remains exact Integer/Rational and primary-assignment based;
- active configuration, durable payout history and executable adapter registry remain separate authorities;
- public provider-controlled diagnostics stay private by default;
- replay/restore fail closed on malformed durable evidence;
- demo/report code never becomes routing/recovery authority.

Any reproduced financial P0 preempts this specification.

## PTZ11-001 — genuine restart vs live post-return failure provenance

### Finding / hypothesis

`restart_recovery_work_for` currently derives work from durable phase/capability plus absence of a process-local interaction token. The same structural state can exist without a process restart after `ProviderContractError`, `ApplicationProcessingError` or fatal post-return unwinding: ownership remains pinned, phase can remain `dispatching`/`resolving`, and the live guard is deliberately released without a `provider_execution_failed` marker.

This creates a plausible semantic contradiction: application/contract failures are documented as *not* raw-provider resumable work, while ordinary `due_work` may later advertise them as `restart_recovery` merely because no live token exists.

### Required method

Reproduce before production change.

Build deterministic cases for:

1. UNKNOWN -> due `resolve` -> malformed provider observation -> `ProviderContractError` -> immediate `due_work` in the same process;
2. valid provider return -> injected application processing fault -> immediate `due_work` in the same process;
3. the equivalent durable state after an actual fresh-process restart;
4. fatal post-return process-death path already covered by SPEC-014, rechecked for adjacency.

### Required outcome if reproduced

A live-process post-return application/contract fault must not be mislabeled as genuine restart recovery merely because the process-local guard ended. A real process restart must still be able to derive safe same-provider recovery for the exact pinned identity when persisted capability permits it.

Prefer the smallest provenance distinction. Do not synthesize provider outcomes, release ownership, enable fresh fallback, add a queue/lease service, or add durable financial state solely to remember a process-local execution detail. A process-local restored-in-flight provenance marker is admissible only if evidence shows it is the narrowest coherent fix.

### Acceptance

- immediate same-process `due_work` after provider-contract/application processing failure matches the chosen explicit contract;
- genuine fresh-process restart remains discoverable when status lookup/idempotent retry permits safe continuation;
- exact provider/operation/attempt identity preserved;
- no second owner/fresh-provider call;
- provider execution marker remains reserved for raw invocation failure;
- live/restore/replay behavior is intentionally explained and regression-tested;
- poison work cannot indefinitely abort unrelated RecoveryExecutor items merely by being re-advertised as false restart work.

## PTZ11-002 — one recovery policy authority for raw/restart paths

### Finding / hypothesis

Normal recovery uses `Recovery.classify` and `RecoverySchedule`, including `max_resolution_interactions` and delay/backoff. `provider_execution_failure_work_for` and `restart_recovery_work_for` currently derive `resolve`/`retry_same` directly from phase/capability and may bypass the same policy budget/timing authority.

The highest-value reproducer is a provider whose status lookup repeatedly raises a raw `Timeout::Error` with `max_resolution_interactions = 1`. Repeated RecoveryExecutor passes must not create an unbounded immediate same-provider loop if the configured policy says the resolution budget is exhausted.

### Required method

Test separately:

- raw initiate failure with status lookup;
- raw initiate failure with idempotent retry;
- raw resolve failure repeated beyond `max_resolution_interactions`;
- crash-before-marker restart recovery repeated beyond the same budget;
- zero-delay policy versus non-zero initial/backoff delay;
- TTL/deadline expiry and reconciliation-blocked precedence;
- concurrent workers and exact interaction counts;
- fresh-process/replay parity.

### Required outcome if reproduced

There must be one semantic authority for whether another same-provider recovery interaction is executable **now**. Raw provider failure and restart recovery may have distinct provenance/reason codes, but they may not silently bypass configured resolution budget, timing/backoff, TTL/deadline or ownership safety.

Do not create a second scheduler or second recovery state machine. Prefer a shared pure recovery eligibility/gating decision used by normal, raw-failure and restart-derived paths where semantics overlap.

### Acceptance

- `max_resolution_interactions` is respected consistently across normal, raw-failure and restart recovery;
- configured delay/backoff is either consistently honored or an explicit evidence-backed exception is documented/tested;
- no infinite immediate due-work loop from repeated raw resolve failure;
- TTL/deadline/reconciliation-blocked remain higher-priority safety boundaries;
- provider-local idempotent retry reuses the exact operation identity;
- no fresh-provider fallback from unresolved ownership;
- concurrent executor workers cannot duplicate a money-moving retry;
- reason codes preserve provenance without creating divergent authority.

## PTZ11-003 — synchronous raw-provider HTTP honesty

Priority: **P1-low / evidence-first after PTZ11-001/002**.

A synchronous `ProviderExecutionError` currently falls through the generic HTTP `500 internal_error`, even though an economic operation may already be durably committed and unresolved. Evaluate whether the case/operator surface needs a stable, non-leaking provider-execution 5xx contract that communicates unresolved committed work without implying request rejection.

Acceptance if changed:

- no adapter/provider exception text leak;
- response cannot reasonably imply that a committed payout intent was never accepted;
- same payout id/status endpoint/recovery path remains canonical continuation;
- provider contract failure and application internal failure stay distinct;
- no new transport-specific economic inference.

If authoritative TZ is likely to define this surface and current behavior is safe enough, evidence-close as TZ-gated rather than inventing public API semantics.

## PTZ11-004 — `due_work(as_of:)` contract precision

The current implementation is a causal cutoff over **current unresolved state**, not a full historical reconstruction of what due-work existed at the supplied timestamp. For example, a payout resolved after `T1` will not reappear merely because the caller asks `due_work(as_of: T1)`.

Do not build time-travel state reconstruction pre-TZ. Align names/documentation/tests with the actual intended contract: no current work item may depend on evidence created after `as_of`; the query is not an event-sourced historical snapshot unless authoritative TZ explicitly requires that.

Production code changes are required only for an actual contract inconsistency.

## Blind closure extension — fatal live interaction provenance

The first post-candidate code-first audit found one adjacent inconsistency:
a fatal adapter/programming `ScriptError` released the live interaction guard
without a raw provider-failure fact, allowing the same live process to expose
`restart_recovery` work when the pinned provider supported status lookup.

The minimal correction is process-local provenance only. Fatal and post-return
unwinds retain distinct local markers, the guard is released, no synthetic
outcome or `provider_execution_failed` fact is created, and a fresh process
still discovers the exact pinned operation from durable attempt facts. This is
an extension of PTZ11-001's provenance invariant, not a second recovery state
machine or a durable restart flag.

## PTZ11-005 — case/regression traceability and closure

After material recovery work:

- map every SPEC-015 acceptance claim to executable evidence;
- rerun the exact case count/volume/fallback/UNKNOWN/history/analytics demo to prove no regression;
- run focused recovery/provenance/fresh-process tests, then property/model/concurrency/fault/full suite;
- enter `VERSION_CANDIDATE`, then perform a new independent code-first skeptical pass that ignores this backlog;
- any new locally solvable material P0/P1 returns ACTIVE;
- only after clean skeptical discovery, fresh exact verification and exact pushed-HEAD GitHub Actions may v0.3.11 become `VERSION_COMPLETE`.

## Explicit non-goals

No Rails/ORM, PostgreSQL, Redis/Sidekiq, queues, distributed leases, microservices, generalized routing DSL, dynamic plugin framework, ML/bandits, real PSP integration, new allocation/recovery objective, alternate accounting point, tolerance/quality redesign, persistent control-plane DB, large Coordinator/Analytics refactor or unmeasured performance work.

Do not reopen mature count/volume allocation, UNKNOWN semantics, health/quality architecture, configuration architecture or demo routing without a new deterministic material counterexample or authoritative requirement.

## Verification contract

Every material bug starts with a deterministic reproducer. Use controlled clocks, actual fresh processes where restart matters, deterministic barriers and exact call/fact assertions. Never use sleep as correctness evidence.

After a material slice: focused regression -> recovery-policy/provenance adjacency -> restart/replay/concurrency/fault -> case evidence -> broad matrix. Known SPEC-015 tickets green means **VERSION_CANDIDATE only**, never automatic completion.
