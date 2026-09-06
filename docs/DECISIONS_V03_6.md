# Decisions — v0.3.6 Causal Recovery Safety & Operator Readiness

Status: VERSION_COMPLETE decision supplement for SPEC-010 at exact pushed HEAD `0988a6248e71f2cbc7a859a4813bac029dfdba4`.

Compatible decisions from v0.3.5 and earlier remain inherited.

## D-385 — Replay causal completion requires current ownership

Status: accepted and implemented.

Finding: the independent candidate pass showed that `Projections::Replay.lifecycle`
validated a causal completion against a held observation but not against the
current payout owner. A reordered or forged completion after `ownership_released`
could therefore diverge from `ObservationFactRestorer` and project the held
outcome after ownership was gone.

Decision: replay must require matching current provider/operation/attempt ownership
before applying `provider_interaction_completed`. This keeps the public replay
projection aligned with durable restore without introducing a second reducer.
Its identity comparisons use the same trimming/canonicalization boundary as
the surrounding replay projection, so valid padded identity payloads remain
replayable without weakening the ownership check.

Regressions: `ReplayTest#test_lifecycle_replay_rejects_causal_completion_after_ownership_release`
and `ReplayTest#test_lifecycle_replay_canonicalizes_padded_causal_completion_identity`.

## D-367 — v0.3.5 remains a protected completed baseline

Status: accepted.

Decision: baseline `e9751d67c3b999d140bacbbc9ac4057c7792b506` remains a valid v0.3.5 closure checkpoint. New v0.3.6 evidence does not rewrite historical status; it opens a new adjacent goal.

## D-368 — read-only and economically irrelevant are different concepts

Status: accepted as v0.3.6 hypothesis boundary.

Decision: provider interactions must not be judged safe for fallback solely by whether they move money themselves. A read-only status lookup can be economically decisive because it can report that the pinned operation already succeeded.

Implementation remains evidence-driven; this decision does not mandate fencing every read-only call forever.

## D-369 — process-local token disappearance is not durable causal proof

Status: accepted.

Decision: after process death, absence of the old interaction token proves only that process-local state was lost. It does not prove that a previously started provider request could no longer produce or reveal a monetary effect.

If the crash reproducer is unsafe, add the smallest durable replayable evidence needed to fail closed. Do not introduce distributed leases.

## D-370 — independent callback and owning-invocation completion are distinct evidence sources

Status: accepted as modeling principle.

Decision: an external webhook/reconcile observation and an observation/result returned by the local invocation may carry identical lifecycle outcomes but different causal meaning relative to an outstanding provider call. The core may persist this distinction if S10 P0 evidence proves it necessary.

Provider event sequence is separate from invocation provenance unless an explicit provider contract links them.

## D-371 — raw adapter exception is not economic completion

Status: accepted.

Decision: a raw timeout/programming/adapter exception can end a local Ruby invocation and release its process-local guard, but cannot by itself prove `definitely_not_sent`. Any cross-provider release must still be justified by canonical provider evidence/transport classification and, after a callback race, by the causal-safety model.

## D-372 — configuration ingress should round-trip canonical typed configuration

Status: accepted and implemented as a P1 transport boundary; broader TZ-specific input remains out of scope.

Decision: expose a strict transport-neutral decode boundary for the existing `RoutingConfiguration#to_h` vocabulary where practical. The compiler and domain constructors remain semantic authorities; Commands remains the only publication path.

Do not invent judge-specific REST/config fields before TZ.

## D-373 — deferred recovery runner is orchestration glue, not a routing engine

Status: accepted and implemented as a P1 application seam.

Decision: a bounded recovery executor may query due work and call canonical resume. It may not select providers, reinterpret errors, own leases or mutate Coordinator state directly.

The current executor requires an explicit non-negative `limit`, performs one deterministic pass, and reports provider/application exceptions per item without classifying them as payout outcomes.

The pass records the effective injected clock value as `as_of` even when the live caller omits it, so operator results remain auditable without introducing a scheduler.

## D-374 — smart objective changes remain TZ/measurement gated

Status: accepted.

Decision: do not pre-TZ change strict allocation authority, recovery objective modes, tolerance-vs-quality ordering, accounting points or quality maturity defaults merely to make routing appear smarter. These are explicit seams to reconcile against official scoring/TZ later.

## D-375 — external safe release is a causal hold without owning completion

Status: accepted and implemented; closure adjacency verified at exact pushed HEAD.

Decision: a safe provider-failure observation received without the owning interaction token must not release an unresolved operation in `committed`, `dispatching`, `resolving`, `pending` or `unknown` phase. It is persisted as an unapplied `causal_hold`. An owning-token observation may close the interaction; if it reports SUCCESS after the hold, the payout settles and an explicit `causal_release_contradiction` fact records the contradiction.

This is a narrow replayable causal boundary, not a lease or a second routing state machine. Provider I/O remains outside the Coordinator atomic boundary.

## D-376 — internal causal provenance remains outside public audit payloads

Status: accepted and implemented.

Decision: `causal_hold` is durable recovery/audit evidence for trusted operators and replay validation, but the public audit projection redacts the new internal field by default. The redaction itself is observable in the bounded `redacted_fields` list without exposing an alternate provider-selection or sensitive provider payload.

## D-377 — duplicate observation identity does not erase invocation provenance

Status: accepted and implemented; closure adjacency verified at exact pushed HEAD.

Decision: if an independent safe-release callback is already held and the
owning provider invocation later returns the same exact observation identity,
the duplicate is treated as owning completion, not as a callback-only no-op.
The coordinator appends `provider_interaction_completed`, applies the outcome
through the existing lifecycle reducer and then releases the interaction token.
Replay requires the completion fact to follow the held observation and precede
the existing lifecycle facts. A duplicate without the current owning token
remains inert; a mismatched payload remains durable corruption/identity reuse.

## D-378 — transport release semantics are interaction-scoped

Status: accepted and implemented.

Decision: a transport classification describes the adapter exchange that produced it. `definitely_not_sent` on `initiate` or same-provider `retry` may prove that the money-moving exchange was not sent and can preserve the existing safe-release semantics. The same classification on `resolve` proves only that the status lookup was not sent; it does not prove that the original payout operation was not sent or is no longer economically decisive. Therefore a failed/definitely-not-sent status lookup remains `UNKNOWN` with ownership retained, and cannot open cross-provider fallback.

This keeps raw timeout/adapter exceptions conservative and does not add a second routing state machine or hold provider I/O inside the atomic boundary.

## D-379 — reconciliation blocking does not erase causal ownership

Status: accepted and implemented.

Decision: `reconciliation_blocked` is still an unresolved economic phase, not proof that a previously started provider interaction is closed. An independent safe-release observation received after TTL/deadline therefore remains an unapplied causal hold, retains the original owner and keeps cross-provider fallback closed. Only conclusive provider evidence or an owning completion may advance the existing lifecycle.

## D-381 — direct normalized transport output remains interaction-scoped

Status: accepted and implemented; closure adjacency verified at exact pushed HEAD.

Decision: an adapter-returned `ProviderObservation` is subject to the same
interaction semantics as a `ProviderTransportResult` or
`ProviderTransportError`. A directly returned `definitely_not_sent` observation
from `resolve` is normalized to UNKNOWN with `safe_to_release: false`, because
the classification proves only that the lookup exchange was not sent. The
initiate/retry safe-release contract remains unchanged.

## D-382 — generated transport observations use a durable-derived exchange ordinal

Status: accepted and implemented; closure adjacency verified at exact pushed HEAD.

Decision: transport observations synthesized by the application include the
canonical interaction action and the payout's durable provider-interaction
ordinal in their identity. This prevents an initial ambiguous exchange and a
later same-operation resolution/retry from being silently deduplicated. The
ordinal is carried by the process-local invocation token but derived from the
durable interaction count, so a restart does not reset exchange identity.

## D-383 — causal hold covers live safe-release attribution, with terminal exception

Status: accepted and implemented; closure adjacency verified at exact pushed HEAD.

Decision: while an economically decisive interaction is live, an independent
safe route outcome must not release its unresolved owner merely because the
outcome attribution is `unknown` or `recipient`. Such outcomes are held as
causal evidence until owning completion. Provider-attributed safe outcomes
retain the existing durable unresolved hold after raw exception/restart. A
`terminal_payout_failure` remains authoritative under the inherited terminal
contract, and a removed-provider unknown-attribution callback remains able to
release its reservation when no live interaction exists.

## D-384 — restored causal holds must belong to the current operation

Status: accepted and implemented; closure adjacency verified at exact pushed HEAD.

Decision: durable replay may accept a persisted `causal_hold` only when its
observation operation is the current unresolved owner, in addition to the
existing phase, outcome and unapplied-state checks. An old operation with an
unresolved-looking phase must not import causal ownership into a newer current
operation. Mismatched history is durable corruption and fails closed.

## D-380 — local interaction duration is not observation identity

Status: accepted and implemented; closure adjacency verified at exact pushed HEAD.

Decision: `interaction_duration_seconds` is locally measured provider-exchange
telemetry. It remains durable for health, analytics and operator explanation,
but is excluded from the provider observation duplicate signature. A single
provider event may legitimately be delivered by an independent callback with
no local duration and later returned by the owning invocation with a measured
duration. Provider event identity, outcome, linkage, ordering and transport
classification remain strict; differing local timing must not turn a valid
causal completion into observation-id reuse.
