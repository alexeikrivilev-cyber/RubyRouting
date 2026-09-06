# Pre-TZ Architecture v0.3.9

v0.3.9 preserves the v0.3.8 economic architecture and tightens boundary semantics.

## Canonical flow

`HTTP/CLI/demo input` -> `Service/Commands` -> `RoutingContext + ActiveConfiguration` -> `Coordinator decision` -> `committed operation/ownership` -> `provider interaction` -> `transport/provider-contract interpretation` -> `NormalizedObservation` -> `Coordinator lifecycle/recovery/facts` -> `Queries/Analytics/Explanation`.

## Boundary rules

### Request boundary
Client parsing/validation happens before economic work and may produce 4xx.

### Provider execution boundary
Raw exception from executable adapter call may become `ProviderExecutionError`. This never proves safe fallback.

### Post-provider interpretation boundary
Once adapter returns, classification/linkage/application validation is no longer client-input validation. Failures need deliberate provider-contract/application semantics and must not masquerade as `invalid_request`.

### Recovery liveness boundary
Process-local guard release is not equivalent to durable recovery scheduling. v0.3.9 proves the exact bridge from provider-call failure to later canonical progress, and the same raw-failure evidence validation is shared by live restore and replay so malformed history cannot be accepted by one path only.

### Demo experiment boundary
A strategy comparison is valid only when mutable runtime state is independent between variants. Shared provider scripts, quality, health or history are confounders.

### Adapter capability boundary
Provider capabilities describe semantics; executable adapter methods are application dependencies. Their required method set must be coherent with declared capabilities without embedding adapters in domain configuration.

## Unchanged authorities

Coordinator owns economic transitions; Service/Commands mutation entry; Queries/Analytics projections; ConfigurationStore current process-local active config; adapters provider/network specifics; demo/HTTP never own allocation/fallback semantics.
