# SPEC-014 — Pre-TZ Public Boundary & Recovery Temporal Integrity

Status: **VERSION_COMPLETE**.

Version Goal: **v0.3.10 — Public Boundary & Recovery Temporal Integrity**.

Opening HEAD: `7ab9bd6884146a64fefe47ae0e05baef623a757d`.

Protected completed baseline: **v0.3.9 / SPEC-013 — VERSION_COMPLETE**. Last material code closure: `543f7b4f00d37e42441245b1e26a74e943f0e525`, Actions run `33692143385` green. The subsequent docs-only closure/index HEAD `7ab9bd6884146a64fefe47ae0e05baef623a757d` has exact-head Actions run `33693537201` green.

Closure evidence is recorded in the completed ExecPlan. Verified code-bearing tree
is `ba00d7dc0d77e328d300bfc9418b96ebe89ede70`; Actions run `33740328533` is green.

## Purpose

Close the remaining generic pre-TZ gaps discovered by a fresh code-first audit after v0.3.9 without reopening the mature economic kernel or inventing infrastructure. The focus is the correctness of public data boundaries, historical recovery queries, process-death liveness and post-provider error provenance.

## Case contract

The case still requires configurable count/volume routing, safe provider fallback, complete attempt history and analytics. v0.3.10 strengthens the operator/judge surface around that kernel: public responses must not leak provider-controlled internals, `due_work(as_of:)` must respect its scan time, restart after an in-flight process death must not strand safely recoverable same-provider work, and provider-contract failures must remain distinct from application programming faults.

## Protected invariants

Do not weaken these without a new deterministic counterexample or authoritative TZ requirement:

- one payout intent has at most one unresolved economic owner;
- ambiguous-after-possible-send remains UNKNOWN unless stronger evidence exists;
- UNKNOWN never enables fresh-provider movement;
- same-provider status lookup/idempotent retry is distinct from fresh fallback;
- provider-local idempotency is not cross-provider idempotency;
- provider I/O remains outside Coordinator/configuration locks;
- count/volume allocation remains exact Integer/Rational and allocation-first;
- recovery attempts do not silently rewrite primary-assignment accounting;
- active configuration, durable payout history and executable adapter registry remain separate authorities;
- replay/restore must fail closed on malformed durable evidence;
- demo/report code may compose canonical results but may not choose providers or recompute allocation.

Any reproduced financial P0 preempts this specification.

## PTZ10-001 — public payout projection privacy

### Finding

The public audit projection is default-deny for provider payload details, but the HTTP payout snapshot currently serializes `NormalizedOutcome#message` and `provider_reference` directly. These values are provider/adapter controlled and can contain diagnostics or identifiers that the public audit boundary deliberately withholds.

### Required outcome

Define one explicit public payout/outcome DTO boundary. Provider-controlled diagnostic text must not leave the HTTP surface by default. Preserve the richer internal/durable outcome where needed for recovery/audit internals.

### Acceptance

- deterministic HTTP reproducer proves the current exposure before changing behavior;
- public payout/submit/resume responses expose only allowlisted outcome fields;
- arbitrary provider message text is absent from public JSON;
- provider reference is either deliberately excluded or explicitly justified by a typed public contract;
- public audit remains default-deny;
- no loss of internal recovery/replay evidence;
- regression checks both direct payout GET and route-result responses.

## PTZ10-002 — historical `due_work(as_of:)` integrity

### Finding

`provider_execution_failed` carries `failed_at`, while the derived raw-failure due-work path currently ignores the caller's `as_of`. A historical scan can therefore expose a failure marker that did not yet exist at the requested scan time.

### Required outcome

Every due-work source must be causally visible at the requested scan timestamp. A raw provider failure occurring after `as_of` must not appear in that scan.

### Acceptance

- controlled-clock regression reproduces `as_of < failed_at`;
- raw-failure work is absent before `failed_at` and present at/after its causal visibility point;
- current-time behavior remains unchanged;
- restart/fresh-process query semantics match live semantics;
- no real sleeps and no wall-clock races;
- no mutation is performed merely by historical query.

## PTZ10-003 — process-death liveness before failure marker

### Hypothesis

A process can die after durable `attempt_started` but before an observation or `provider_execution_failed` fact is appended. After restart the pinned operation is manually resumable, but the bounded RecoveryExecutor may not discover it automatically until TTL/deadline handling.

### Required method

Do not implement from the hypothesis alone. Build a real fresh-process/barrier reproducer that terminates the first process after durable attempt start and before any completion/failure marker. Inspect facts, restored phase, due-work, manual resume and RecoveryExecutor.

### If reproduced

Add the smallest derived same-provider recovery visibility for the restored in-flight phase when the persisted operation contract proves `status_lookup` or `idempotent_retry`. Do not synthesize a provider outcome, do not release ownership, do not enable cross-provider fallback and do not require a queue/lease service.

### Acceptance

- real process death, not an in-process exception simulation;
- exact provider/operation/attempt identity preserved across restart;
- no second economic owner or fresh-provider movement;
- recovery action derives only from persisted contract capability;
- unsupported providers remain safely pinned without advertised executable work;
- concurrent workers cannot duplicate money-moving execution;
- replay/restore parity remains green;
- if current behavior is already coherent, evidence-close without production abstraction.

## PTZ10-004 — narrow post-provider error provenance

### Finding

The v0.3.9 post-return boundary correctly prevents malformed provider data from becoming `400 invalid_request`, but broad `rescue StandardError` around application-owned classification/enrichment can also label an internal programming defect as `ProviderContractError` / HTTP 502.

### Required outcome

Provider-return validation failures and internal application bugs must remain distinct. HTTP/error taxonomy follows execution provenance, not broad Ruby superclass convenience.

### Acceptance

- malformed provider return/linkage still yields bounded provider-contract semantics and never client 400;
- a deterministic application-side programming fault after a valid provider return is not mislabeled as provider contract failure;
- raw adapter invocation failures remain `ProviderExecutionError` and retain their recovery semantics;
- no provider payload/error detail leak;
- guard/owner/phase/facts are asserted for every branch;
- no broad `rescue Exception` and no exception taxonomy explosion.

## PTZ10-005 — adjacent fatal apply-path evidence

After PTZ10-004, challenge the remaining post-return apply path for `ScriptError`-derived fatal unwinding. Determine whether the intended contract is process-fatal restart recovery or in-process guard cleanup. Prefer evidence/explicit contract to catching `Exception`. Production change is required only for a reproduced locally meaningful liveness defect.

## PTZ10-006 — judge evidence clarity

After P1 integrity work is green:

- measure alternative count-vs-volume workloads through the canonical allocator and choose a fixture that makes the strategy difference legible without demo-only math;
- keep count and volume on fresh independent runtimes;
- report configuration/runtime identity honestly when multiple runtimes are used;
- do not hardcode expected provider assignments or target/actual metrics outside Analytics;
- retain the current skewed fixture if alternatives are less honest.

## Explicit non-goals

No Rails/ORM, PostgreSQL, Redis/Sidekiq, queues, distributed leases, microservices, generalized routing DSL, dynamic plugin framework, ML/bandits, real PSP integration, new recovery objective, alternate accounting point, tolerance/quality redesign, large Coordinator/Analytics refactor, persistent control-plane database or unmeasured performance work.

## Verification contract

Every material bug starts with a deterministic reproducer. Use controlled clocks, process barriers and deterministic seeds; never sleep for correctness evidence.

After a material slice: focused regression -> causal/restart/replay/concurrency/fault adjacency -> relevant case evidence -> broad matrix. Before `VERSION_COMPLETE`: fresh `bundle check`, `bundle exec rake test`, property, model, concurrency, fault, acceptance/case campaigns, exact pushed-HEAD GitHub Actions and a new independent code-first skeptical pass that ignores backlog status.

## Completion

Known PTZ10 work green means **VERSION_CANDIDATE only**. `VERSION_COMPLETE` requires a fresh skeptical pass over public DTO privacy, temporal query semantics, restart/process-death liveness, provider/application error provenance, inherited economic safety, demo authority and live/restore/replay parity. Any new material locally solvable P0/P1 returns the version to ACTIVE.
