# Authoritative TZ Requirement Matrix

Status: **v0.4.3 VERSION_COMPLETE traceability source**.

Opening baseline: `277d6b68d568eceb88ece3b3e466987535ff75bd` (completed v0.4.2).

Legend: `SUPPORTED` = end-to-end release path proven; `PARTIAL` = implementation exists but the active audit has not independently closed semantics/evidence; `MISSING`; `CONFLICT`; `OVERENGINEERED`.

| ID | Requirement | Current status | v0.4.3 action |
|---|---|---|---|
| IO-01..06 | official inputs and generated root artifacts | SUPPORTED | preserve |
| OUT-01..06 | decisions fields/attempts/outcomes/latency | SUPPORTED | preserve public validator compatibility |
| OUT-07 | rich explanations | SUPPORTED | preserve additive evidence |
| HC-01..10 | authoritative hard constraints | SUPPORTED | preserve literal active and fallback recheck |
| SG-01 | count-share routing | SUPPORTED for primary assignment; base fallback meaning authority-ambiguous | TZ19-101 evidence-closed; primary base projection is explicit and reversible |
| SG-02 | volume-share routing | SUPPORTED for primary assignment | preserve explicit source/provenance |
| SG-03 | lower-is-higher priority | SUPPORTED | preserve |
| SG-04 | amount preference distinct from hard gate | SUPPORTED with neutral absence | TZ19-105 closes missing-band strongest-preference bias |
| SG-05 | conversion preference | SUPPORTED | preserve |
| SG-06 | load/intensity preference | SUPPORTED capability | preserve |
| SG-07 | turnover-min obligation | SUPPORTED optional capability | preserve absent organizer values |
| SG-08 | simultaneous multi-goal resolution | SUPPORTED with explicit normalization pool | TZ19-103 closes candidate-set scale drift; preserve one resolver |
| SG-09 | explicit one ConflictResolver | SUPPORTED | preserve one chooser/phase model |
| SG-10 | infeasible target explanation | SUPPORTED including terminal fallback causality | TZ19-202 closes direct terminal deviation explanation |
| FB-01..04 | reject/expired fallback, recheck, terminal | SUPPORTED | preserve phase-correct fallback |
| STATE-01..03 | sequential provider state | SUPPORTED for sequential multi-day workload | preserve |
| STATE-04 | daily-limit temporal semantics | SUPPORTED with deterministic UTC date scope | TZ19-104 closes stale cross-midnight baseline; no persistence/scheduler |
| EXP-01..03 | reasons/exclusions/fallback sequence | SUPPORTED | preserve |
| AN-01 | distribution count/share/target | SUPPORTED for explicit primary-assignment base; fallback population authority-ambiguous | TZ19-101 independent fallback probe; keep rich final/settlement ledgers |
| AN-02 | target deviation | SUPPORTED rich evidence; base fallback meaning authority-ambiguous | primary assignment remains target authority pending organizer clarification |
| AN-03 | outcomes / assignment-attempt-settlement | SUPPORTED rich | preserve separate ledgers |
| AN-04 | projected utilization/limits | SUPPORTED | TZ19-102 recomputes raw snapshot + approved settlements; canonical serialized finalization |
| AN-05..07 | skip reasons, deviation causes, recommendations | SUPPORTED including terminal causes | TZ19-202 adds quantitative terminal fallback evidence |
| AN-08 | semantic report oracle fails closed on malformed raw boundary inputs | SUPPORTED | TZ19-106 regression prevents validator crashes |
| AN-09 | semantic report oracle handles a permitted empty queue | SUPPORTED | TZ19-107 zero-denominator regression |
| FLEX-01 | provider independent | SUPPORTED for optional amount configuration | TZ19-105 additional-provider missing-band regression |
| FLEX-02 | config-driven rules/weights | SUPPORTED | preserve canonical profile |
| FLEX-03 | add provider/factor without redesign | PARTIAL | TZ19-103/105 additional-provider campaigns |
| RULE-01..04 | deterministic/Ruby/no neural/proprietary | SUPPORTED | preserve |

## Release-critical interpretation

v0.4.2 solved the organizer report **shape** problem. v0.4.3 does not reopen that shape; it verifies semantic meaning independently. A library self-replay or ReportBuilder self-equality cannot by itself move an active PARTIAL row back to SUPPORTED.

Primary assignment remains the current internal allocation authority unless stronger evidence changes the organizer-facing projection. Decisions continue to expose final cascade provider; settlement remains approved-only. These three facts must remain distinguishable.

## Traceability rule

A row becomes SUPPORTED only when authoritative wording and/or an independent oracle plus finalization-equivalent evidence agree. If a fresh hypothesis is falsified, record the reproducer and why no change is justified rather than manufacturing a feature.
