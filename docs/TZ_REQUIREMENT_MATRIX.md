# Authoritative TZ Requirement Matrix

Status: **v0.4.1 VERSION_COMPLETE traceability source**.

Opening v0.4.1 baseline: `0187bf2558d58a52dfdb27e76694d6323addbcd6`.

Legend: `SUPPORTED` = authoritative end-to-end release path proven; `PARTIAL` = primitive exists but finalization/output semantics incomplete; `MISSING`; `CONFLICT`; `OVERENGINEERED`.

A library feature is not `SUPPORTED` for submission if the supported finalization path does not activate it.

| ID | Requirement | v0.4.1 status | Completion evidence |
|---|---|---|---|
| IO-01..04 | official inputs / one decision per op | SUPPORTED | retain strict loader/coverage |
| IO-05..06 | root decisions/report generation | SUPPORTED | retain clean finalization |
| OUT-01 | operation id | SUPPORTED | serialized validation |
| OUT-02 | selected provider semantics | SUPPORTED / conservative organizer assumption | primary/final identities are preserved internally; compatibility projection is covered by `test/case/finalization_test.rb` and `SerializedArtifactValidator` |
| OUT-03 | ordered attempts | SUPPORTED | internal attempt classification and ordered fallback are replayed by `test/case/runner_test.rb`; serialized coverage is strict-validated |
| OUT-04 | organizer provider/decision/reason | SUPPORTED / conservative organizer projection | invoked failures project as `selected`, hard exclusions as `skipped`; public validator and post-write validator pass on finalization artifacts |
| OUT-05 | approved/rejected/expired | SUPPORTED | canonical profile selects deterministic conversion simulation; controlled fallback and terminal non-approval are covered by case finalization/edge campaigns |
| OUT-06 | latency | SUPPORTED | keep typed non-negative output |
| OUT-07 | rich explanations | SUPPORTED in report / active minimal DTO | rich selection traces remain in report/in-memory; default decisions omit them |
| HC-01..10 | official hard constraints | SUPPORTED | preserve fallback/terminal/state regressions |
| SG-01 | count-share routing | SUPPORTED | finalization profile derives count targets from `provider.traffic_percentage`; assignment distribution and target deviation are serialized and strict-recomputed |
| SG-02 | volume-share routing | SUPPORTED | finalization profile derives volume targets from the same explicit source with provenance; exact volume ledger/report evidence passes |
| SG-03 | lower-is-higher priority | SUPPORTED | preserve inversion test |
| SG-04 | amount preference distinct from hard gate | SUPPORTED slice | typed preferred bands are independent from hard limits; hard-eligible ranking and malformed-band campaign pass |
| SG-05 | conversion preference | SUPPORTED | profile enables `conversion_24h`; finalization traces and controlled conversion fallback are covered in `test/case/finalization_test.rb` |
| SG-06 | load/intensity preference | SUPPORTED | profile enables load and simultaneous factor traces; factor campaign and finalization regression pass |
| SG-07 | turnover-min obligation | SUPPORTED / explicit optional input | typed profile activates it only when configured; no silent default is claimed |
| SG-08 | multiple goals simultaneously | SUPPORTED | canonical finalization passes count, volume and business factors to one resolver; factor sensitivity campaign proves policy activation |
| SG-09 | explicit ConflictResolver | SUPPORTED | finalization is configured through the single typed profile and canonical resolver; duplicate policy identities fail closed |
| SG-10 | infeasible target explanation | SUPPORTED | report exposes target deviations, hard exclusion causes and actionable under/over-target recommendations from canonical ledgers |
| FB-01 | reject -> next | SUPPORTED | canonical profile reaches deterministic fallback under controlled rejection; assignment and attempts remain distinct |
| FB-02 | expired -> next | SUPPORTED / isolated case semantics | canonical profile reaches deterministic judge-expiry fallback; production timeout semantics remain isolated |
| FB-03 | reapply hard constraints | SUPPORTED | retain strict replay |
| FB-04 | terminal self-provider | SUPPORTED | retain terminal hard/non-approval tests |
| STATE-01..04 | sequential provider state | SUPPORTED | preserve |
| EXP-01 | concrete selection reason | SUPPORTED report | minimal external DTO + rich report |
| EXP-02 | exclusion reason | SUPPORTED | preserve stable codes |
| EXP-03 | actual fallback sequence | SUPPORTED | ordered invoked attempts, classifications and conservative DTO projection are covered by fallback and serialized artifact tests |
| AN-01 | count/share | SUPPORTED | report exposes primary-assignment distribution and strict serialized recomputation from canonical ledgers |
| AN-02 | target deviation | SUPPORTED | deviations use primary assignment and are recomputed from canonical ledgers in strict validation |
| AN-03 | outcomes | SUPPORTED / separate ledgers | attempt, final outcome and settlement distributions are distinct |
| AN-04..05 | utilization/skip reasons | SUPPORTED | preserve |
| AN-06 | deviation causes | SUPPORTED | report exposes per-provider hard-exclusion and assignment causes from observed evidence |
| AN-07 | actionable recommendations | SUPPORTED | recommendations name provider, evidence and concrete target/alternative or hard-rule action; causal regression passes |
| FLEX-01 | provider independent | SUPPORTED | preserve |
| FLEX-02 | config-driven rules/weights | SUPPORTED | canonical `SubmissionProfile` drives finalization without code edits; strict policy/simulation ingress and profile-only weight sensitivity pass |
| FLEX-03 | add provider/factor without redesign | SUPPORTED | typed configuration seam and five-provider scale campaign pass without a second chooser |
| RULE-01..04 | deterministic/Ruby/no neural/proprietary | SUPPORTED | preserve |

## Protected scoring-low capabilities

Production economic ownership/UNKNOWN, durable restart/replay, RecoveryExecutor and HTTP control plane remain protected but frozen unless SPEC-017 exposes a blocker.

## Traceability rule

Every row moved to `SUPPORTED` must cite actual finalization-equivalent code/test/generated-artifact evidence. Do not close a row from a demo-only configuration or unit factor test.
