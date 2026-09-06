# TZ Reconciliation

The authoritative TZ superseded pre-TZ guesses and produced v0.4.0 / SPEC-016, which built the bounded official case engine while preserving compatible production safety.

A subsequent independent audit of exact `main` `0187bf2558d58a52dfdb27e76694d6323addbcd6` found that capability and release path were not fully converged: finalization used default priority-only/always-approved configuration; traffic distribution was success-only; fallback attempt semantics and output compatibility remained partially ambiguous; amount preference reused hard ranges; serialized artifacts were not strict-revalidated.

At that reconciliation point the current authority became v0.4.1 / SPEC-017 ACTIVE. The submission/release contract was subsequently closed on the v0.4.1 completion tree; this historical record explains why that work was opened and does not itself reopen the completed version. A new authoritative clarification or material counterexample still reopens ACTIVE under the current completion policy.

Current reconciliation rules:

- authoritative TZ remains highest product authority;
- count target source comes from official traffic percentage unless superseded;
- volume target source must be explicit/provenanced;
- distribution routing uses primary assignment by default, with settlement reported separately, pending stronger organizer clarification;
- synthetic expired fallback remains case-only and never weakens production UNKNOWN;
- organizer output ambiguities use conservative reversible projections and explicit tests.
