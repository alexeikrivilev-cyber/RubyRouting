# Pre-TZ Architecture Delta — v0.3.4

Status: VERSION_COMPLETE

This delta governs SPEC-008. It inherits the verified v0.3.3 architecture and changes nothing by default. Every new structure must be justified by a new v0.3.4 counterexample or measurement.

## 1. Architectural thesis

Keep the existing canonical flow and atomic financial kernel. v0.3.4 improves case fidelity and derived-read efficiency without adding a second economic state owner.

`Intent -> Config Snapshot -> Eligibility/Admission -> Allocation -> Recovery -> Atomic Commit -> Provider -> Observation -> Durable Facts -> Payout/Analytics/Explanation`

Durable facts remain historical truth. Process-local live-interaction serialization is operational state, not durable economic truth.

## 2. Outcome analytics is not allocation arithmetic

Allocation metrics remain keyed by policy/window/cohort/measure/currency/provider and may contain count or exact volume.

Outcome analytics uses a separate bounded typed identity including policy/currency/provider/role/outcome/attribution as appropriate. Never manufacture a payout success rate from incompatible allocation measures.

The current typed outcome projection is a verified v0.3.4 checkpoint and should not be redesigned without a new counterexample.

## 3. Query-performance rule

Current revision-keyed analytics reuse and indexed payout explanation are verified derived-state optimizations. They are discardable and reconstructible from facts.

Further performance work is evidence-gated. Dynamic `as_of` values such as unresolved age remain explicitly reprojected rather than frozen into cached truth.

## 4. Due-work and live interaction architecture

`due_work` is a query over canonical payout/recovery state, not a queue and not a lease. Multiple workers may read the same item.

Safety has two distinct layers:

1. **durable recovery legality** — ownership, attempt phase, operation contract, dispatch/resolution token, TTL/deadline and recovery schedule determine whether an operation may be rebuilt after restart;
2. **process-local live invocation ownership** — after a start token is consumed and before provider I/O completes, at most one invocation may own the live execution interval for that payout/operation.

The post-closure audit showed that an operation-keyed boolean marker is conceptually weaker than invocation ownership because the same operation identity can be reused across resolution/idempotent recovery interactions. A callback for the operation is lifecycle evidence; it is not automatically proof that a different currently executing invocation finished.

Preferred invariant:

`live interaction token = (payout_id, operation_id, invocation_generation)`

or an equivalent opaque token. Only a matching owner may release it through its completion/failure path.

The exact representation is not mandated. It must remain:

- process-local;
- acquired/released under Coordinator synchronization;
- absent after process restart;
- independent from provider I/O execution, which stays outside the Coordinator mutex;
- incapable of unlocking cross-provider fallback while UNKNOWN ownership remains.

Do not persist the token or introduce Redis/Sidekiq/distributed leases for this pre-TZ single-process correctness problem.

## 5. Observation boundary

Observation application owns lifecycle/evidence reduction: duplicate detection, ordering, normalized outcomes, health/quality evidence, settlement/conflict and next action.

Observation application must not implicitly own another provider invocation's process-local execution guard. If observation identity is independently delivered by webhook/reconciliation, it can change canonical payout state while a live adapter call is still in progress.

Therefore live invocation completion and observation application are separate concepts unless the implementation passes an explicit matching invocation token proving identity equivalence.

## 6. Configuration crash boundary

Active configuration is a control-plane generation; payout/operation facts are durable economic history.

Fresh-process tests already prove restart can reconcile a coherent supplied generation or fail closed before routing. No durable active-config subsystem is required without a new counterexample.

## 7. Case-fidelity evidence

The deterministic canonical campaign remains required evidence for count distribution, volume distribution under skew, safe fallback, UNKNOWN ownership/resolution, attempt/audit history, outcome analytics and restart parity.

It is product-composition evidence, not a substitute for interaction-level concurrency tests.

## 8. Coordinator rule

`State::Coordinator` remains the atomic transaction facade. Do not split it for size.

A v0.3.4 extraction is justified only if it centralizes the live interaction ownership invariant or removes measured repeated-read cost without becoming a new source of truth.

A small dedicated `ProviderInteractionGuard`/token owner is acceptable if it makes acquire/release identity explicit and reduces accidental release-by-operation-key coupling. Cosmetic decomposition is not.

## 9. Non-goals

No microservices, ORM/database migration, queue framework, distributed locking, durable live leases, PSP-brand schema, generalized rules engine, ML/bandits or dashboard architecture before authoritative TZ/measurement requires it.
