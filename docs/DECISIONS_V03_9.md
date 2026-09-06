# Decisions — v0.3.9

## D-501 — v0.3.8 remains protected
Status: accepted.

Fresh audit found no new confirmed financial P0. v0.3.9 does not reopen the economic kernel without deterministic evidence.

## D-502 — HTTP status follows failure domain, not Ruby superclass
Status: accepted as requirement; implementation pending evidence.

A post-provider validation failure is not a client input failure merely because current exception type is `ArgumentError`.

## D-503 — safety and liveness are separate claims
Status: accepted.

Releasing process-local interaction guard while retaining pinned ownership can be financially safe but operationally stranded. Raw provider failure recovery progress must be proved explicitly.

## D-504 — strategy isolation requires fresh mutable state
Status: accepted.

Identical workload alone is insufficient. Count/volume judge runs must not share provider script cursors, quality, health, allocation or durable fact history.

## D-505 — adapter validation follows a proven port contract
Status: accepted.

Do not remove universal `resolve` merely because `status_lookup` can be false. First prove whether method is universal application port or capability-dependent operation.

## D-506 — no speculative platform expansion
Status: accepted.

No DB, queues, distributed locks, dynamic plugins, ML or broad refactor is justified by v0.3.9 findings.

## D-507 — post-return provider contract failures have typed HTTP provenance

Status: accepted and implemented.

The adapter invocation boundary remains responsible for raw `ProviderExecutionError`. Once an adapter returns, classification/linkage/application validation is wrapped only as `ProviderContractError`; `HttpApp` exposes that boundary as bounded `502 provider_contract_error`. The original cause remains available to internal callers, while public output never includes provider payload or exception text. Ordinary pre-provider `ArgumentError` input failures remain `400 invalid_request`, and contract failures are not treated as resumable raw provider execution by `RecoveryExecutor`.

## D-508 — raw provider execution failure is durable due-work evidence

Status: accepted and implemented.

When a raw adapter exception occurs after `attempt_started`, the coordinator releases only the process-local interaction guard and appends a payload-free `provider_execution_failed` fact carrying the pinned provider/operation/attempt/action/phase and interaction index. `Queries#due_work` exposes one immediate same-provider `resolve` or `retry_same` item only when the persisted operation contract proves that path is available. This closes the discovered RecoveryExecutor liveness gap without synthesizing an outcome, releasing economic ownership, enabling cross-provider fallback, persisting adapter exception text, or adding a scheduler. The marker is cleared by the next canonical interaction and is not emitted for post-return application/contract failures.

## D-509 — strategy evidence requires independent canonical runtimes

Status: accepted and implemented.

Count-versus-volume evidence must change only the policy measure. Each variant therefore gets a fresh Service, Coordinator and executable provider instances with the same workload, equivalent configuration and provider behavior. Fallback/UNKNOWN/RecoveryExecutor scenarios run separately so their provider scripts, health/quality state and durable facts cannot influence the strategy experiment. The report remains an evidence assembly layer: target/actual values are read from each run's canonical Analytics and no demo allocation logic is introduced.

## D-510 — universal adapter port with capability-selected recovery

Status: accepted and evidence-closed.

## D-511 — raw provider-failure evidence has one restore/replay validator

Status: accepted and implemented.

Candidate-stage review found that replay accepted malformed `provider_execution_failed` evidence that the durable working-state restorer rejected. Keep live state transitions and projection state separate, but share one pure validator for marker identity, current owner/attempt, action/phase, interaction ordinal, timestamp shape and duplicate-marker rejection. This closes replay/live drift without changing financial recovery semantics or adding another state machine.

The executable application port requires both `initiate` and `resolve` so adapter construction is validated before any payout work and all canonical invocation paths have one stable shape. This does not imply that every provider supports status lookup: `status_lookup` selects `resolve`, `idempotent_retry` selects same-operation `initiate`, and no recovery capability publishes no recovery work. The focused method/capability matrix and existing recovery tests prove the distinction; no production capability branching is justified.

## D-512 — fatal adapter unwinding is release-only, not resumable

Status: accepted and implemented.

A `ScriptError`-derived adapter/programming fault such as `NotImplementedError` is intentionally not caught as a routine `ProviderExecutionError`, because it is not proven resumable provider execution. It must nevertheless release the process-local interaction guard when the invocation unwinds before returning an observation. `invoke_provider_with_guard` therefore performs idempotent release-only cleanup in `ensure` only when no `ProviderInvocation` was returned; ordinary returned observations retain the guard until atomic application, and `StandardError` raw adapter failures continue through the durable provider-failure marker. This preserves both fatal-error taxonomy and guard liveness without catching broad `Exception` or creating a second recovery path.
## D-513 — post-return enrichment follows provider-contract provenance

Status: accepted and implemented.

Once an adapter has returned a `ProviderObservation`, failures in application-owned duration enrichment are not raw provider execution failures and must not create resumable due work. Only the `with_interaction_duration` validation seam is wrapped as `ProviderContractError`; raw adapter invocation remains `ProviderExecutionError`, and later atomic observation application remains release-only cleanup. The regression preserves the committed owner/phase, releases the live guard and rejects both synthetic observation and durable raw-failure marker without catching unrelated programming faults broadly.

## D-514 — v0.3.9 closure evidence is exact and bounded

Status: accepted and closed.

The final independent code-first skeptical pass found no new material locally
solvable P0/P1 after PTZ9-006/007/008. Exact closure HEAD
`543f7b4f00d37e42441245b1e26a74e943f0e525` passed `bundle check`, test
(`719/12601`), property (`4/1210`), model (`3/2958`), concurrency
(`44/1438`) and fault (`387/4662`) with zero failures/errors/skips. Focused
HTTP/provider-liveness/replay/restart/demo/operator/fresh-process and
acceptance evidence also passed. Product measurements remain honestly bounded:
the history profile covers 100/250/500 samples and the separate load evidence
covers 10,000 lifecycle operations. GitHub Actions run `33692143385` is green
on that exact SHA.
