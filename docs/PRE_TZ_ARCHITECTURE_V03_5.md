# Pre-TZ Architecture Delta — v0.3.5

Status: ACTIVE

This delta governs SPEC-009 and inherits the verified v0.3.4/SPEC-008 architecture. Nothing changes by default; every new mechanism requires a reproduced case-relevant defect or measured need.

## 1. Architectural thesis

Keep one canonical financial state machine and separate three concepts that must not be conflated:

1. durable economic ownership;
2. durable operation/recovery legality;
3. process-local live provider invocation state.

The v0.3.4 invocation token solved duplicate live execution for one operation. v0.3.5 challenges the next boundary: durable ownership can be released by an independently delivered provider observation while a money-moving invocation for that payout is still physically executing.

## 2. Live money-moving fence

A live `initiate` invocation can still create an economic effect even if another callback has already produced a lifecycle outcome for the operation.

Therefore cross-provider routing requires two conditions:

- durable lifecycle/ownership semantics permit release/fallback; and
- there is no still-live money-moving invocation for the payout that can independently create an economic effect.

The implementation may enforce this with an extension of the existing process-local interaction token/guard or an equivalent narrow mechanism.

Preferred semantic distinction:

- `assign` / `retry_same` provider `initiate` => money-moving interaction;
- `resolve` status lookup => non-money-moving interaction;
- provider callback/webhook => observation evidence, not automatically invocation completion.

Do not globally serialize all provider reads and callbacks. The fence exists only to prevent a concurrent second economic effect.

## 3. Conservative release rule

`safe_to_release=true` means the normalized observation is safe for lifecycle release under its provider semantics. It does not automatically prove that a different currently executing money-moving invocation cannot still succeed.

When an independent callback races a live money-moving invocation, the product must fail closed with respect to fresh cross-provider assignment.

A minimal acceptable shape is:

- allow the callback to be recorded/reduced as canonical provider evidence if existing ordering rules permit it;
- retain the process-local live money-moving fence until the owning invocation finishes/fails;
- refuse/defer any fresh money-moving provider assignment for that payout while the fence exists;
- after the live invocation completes, let canonical lifecycle/conflict/reconciliation semantics determine whether fallback is legal.

This shape is preferred over inventing provider-specific causal metadata unless a reproducer proves it insufficient.

## 4. Late completion semantics

If an independent observation released durable ownership while a money-moving invocation remained live, its eventual completion may contradict the earlier observation.

Required architectural outcome:

- no provider B call was started during the live-A interval;
- late A success is explicit settlement or economic conflict/reconciliation evidence, never silent overwrite;
- late definitely-not-sent failure can permit fallback after the live fence is gone;
- ambiguity remains UNKNOWN/reconciliation-safe;
- invocation-token release remains owner-only and process-local.

The system may conservatively enter reconciliation rather than guess provider chronology.

## 5. Observation ordering

Provider event ordering remains owned by `ObservationLedger` and provider contract semantics.

`authoritative_sequence=true` is a provider capability for event ordering; it is not a generic distributed transaction proof. Non-authoritative providers remain conservative under contradictory late evidence.

Do not modify global observation ordering merely to solve the live-money-moving fence unless a deterministic counterexample requires it.

## 6. Adapter execution boundary

The core does not safely preempt arbitrary provider network I/O.

Production provider adapters own:

- connect/read/request timeouts;
- mapping timeout/connection results into the explicit transport taxonomy;
- provider-specific status lookup and idempotent retry semantics;
- webhook normalization and authenticity outside the generic lifecycle reducer.

Operation TTL/deadline remains an economic/recovery contract, not a replacement for socket/request timeout configuration.

Do not use `Thread#kill`, broad asynchronous interruption or a generic timeout wrapper as a financial correctness primitive.

## 7. Single-process scope

The live interaction fence is intentionally process-local. It does not create a cross-process exactly-once guarantee.

Before the authoritative deployment contract exists, do not introduce Redis/database/distributed leases solely to extend the fence across processes. Document the scope precisely and reconcile it when the TZ defines the process model.

Durable restart safety continues to rely on operation identity, idempotency/status capabilities, attempt phase, ownership and reconciliation.

## 8. Coordinator ownership

`State::Coordinator` remains the atomic transaction facade.

A small extraction is justified only if it makes the live interaction/money-moving fence invariant easier to own and test. File size alone is not a reason to refactor.

Do not create parallel routing/recovery state machines in helper services.

## 9. Verification architecture

Use deterministic controlled concurrency for live-invocation races. Assert exact structural evidence:

- provider A/B call counts;
- operation count;
- ownership acquisitions/releases;
- allocation commits;
- attempt-start facts;
- settlement/conflict facts;
- final payout status;
- replay/restart parity when durable state changes.

A final status assertion alone is insufficient.

## 10. Non-goals

No microservices, distributed lease system, database migration, brand-specific PSP model, generalized rules DSL, ML/bandits, dashboard work or cosmetic decomposition before authoritative TZ/measurement requires it.
