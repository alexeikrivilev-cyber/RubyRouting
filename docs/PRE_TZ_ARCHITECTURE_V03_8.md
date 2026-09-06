# Pre-TZ Architecture Delta — v0.3.8

Status: VERSION_COMPLETE design record for SPEC-012.

This is a narrow delta over the completed v0.3.7 architecture. It does not replace historical architecture records.

## 1. Architectural objective

Finalize runtime boundaries without changing the proven routing/economic model.

Target flow remains:

`transport/demo -> Application::Service -> Commands/Queries/RecoveryExecutor -> Orchestrator/Coordinator/typed domain -> durable facts -> projections`.

v0.3.8 focuses on where runtime/application responsibilities begin and end.

## 2. Provider execution provenance

The provider adapter call and application-side interpretation are separate boundaries.

Preferred behavioral structure:

`invoke executable adapter`
→ raw invocation exception may become a typed provider execution failure
→ successful return crosses back into application authority
→ classify/validate returned value
→ application/contract/invariant failures use deliberate fail-closed semantics.

A single broad `rescue StandardError` spanning both regions is unsafe taxonomy because downstream RecoveryExecutor uses the typed provider execution class to decide pass continuation.

The exact implementation may remain compact. The architecture requirement is provenance-preserving failure semantics, not a mandatory new class hierarchy.

Interaction-token/guard cleanup remains owned by Orchestrator/Coordinator around the entire invocation lifecycle.

## 3. Recovery read versus mutation surfaces

Mutating recovery remains:

`POST recovery/run -> RecoveryExecutor -> bounded due_work -> Service#resume`.

Read-only inspection remains:

`GET recovery/due-work -> Queries#due_work`.

Both product surfaces must be intentionally bounded. Bounding the read is an application/API concern and must not change domain recovery ordering, due-time legality or provider selection.

## 4. Judge/demo fidelity

The case demo is a controlled composition over production primitives.

For strategy comparison, use an identical input sequence and equivalent provider conditions for count and volume policies. The policy measure is the intended independent variable.

The report may summarize:

- canonical input workload;
- policy measure/target;
- primary assignment count/volume;
- fallback/UNKNOWN/recovery history;
- settlement/success analytics;
- configuration revision/source.

All numeric routing claims come from canonical queries/analytics, not a second demo formula.

## 5. Three runtime lifecycles

Keep distinct:

### Durable economic history

Payout intents, ownership, operations, attempts, observations, settlement/conflict/reversal and other facts needed for economic/restart correctness.

### Active routing configuration

Policies/provider opportunity definitions used for **new/current decisions** in the active application generation. Runtime mutation changes this control-plane state.

### Executable provider adapters

Runtime objects supplied when constructing the application. They own actual provider calls and transport integration.

Do not infer one lifecycle from another implicitly.

In particular:

- payout facts do not reconstruct the desired active configuration for new payouts;
- provider opportunity presence does not prove an executable adapter exists;
- adapter objects do not belong in durable/domain configuration serialization.

## 6. Configuration restart contract

Preferred minimal pre-TZ model:

`canonical config export/read`
→ external/startup persistence if desired
→ `RoutingConfiguration.decode`
→ fresh ConfigurationStore/Service bootstrap.

If the existing application constructors already express this cleanly, tests/documentation are sufficient. Add a bootstrap seam only if current API makes the contract ambiguous or unsafe.

Do not introduce a database or put active control-plane generations into the financial FactStore merely to persist HTTP PUT.

Historical unresolved payouts continue to rely on pinned durable policy/operation facts for safety.

## 7. Adapter availability visibility

ProviderOpportunity remains a domain/config value. Adapter availability is application runtime state.

The operator boundary must expose or enforce the relationship without merging models. Acceptable shapes include:

- rejecting an enabled active provider with no adapter;
- typed configuration/runtime warning;
- provider status projection containing adapter availability.

The choice must preserve intentional disabled/future provider use cases if they are currently meaningful.

No dynamic plugin loader is part of v0.3.8.

## 8. Performance/state discipline

The confirmed performance issue was unbounded due-work response cardinality; it is now bounded through the existing query limit/cap without indexes or pagination.

Coordinator/Analytics size alone remains insufficient reason for refactor. No new durable state is expected for v0.3.8 unless a reproduced correctness issue requires it.

## 9. Multi-process boundary

v0.3.8 remains a single-process correctness reference with restart durability. It does not claim distributed exactly-once, cross-process live invocation serialization or persistent dynamic control-plane ownership.

Do not add Redis/DB leases without authoritative requirement.
