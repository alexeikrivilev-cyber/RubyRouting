# Authoritative TZ Requirement Matrix

Status: **v0.4.2 VERSION_COMPLETE traceability source**.

Opening v0.4.2 baseline: `e9a24923aebfdb1b01223a360b3f3f2b4e84ee45`.

Legend: `SUPPORTED` = authoritative end-to-end release path proven; `PARTIAL` = primitive exists but release/output/scoring semantics incomplete; `MISSING`; `CONFLICT`; `OVERENGINEERED`.

A library feature is not `SUPPORTED` if the supported finalization path or submitted artifact does not demonstrate the authoritative contract.

| ID | Requirement | v0.4.2 opening status | Current action |
|---|---|---|---|
| IO-01..04 | official inputs / one decision per op | SUPPORTED | preserve strict loader/coverage |
| IO-05 | root decisions generation | SUPPORTED | keep exact finalization |
| IO-06 | root report generation | **SUPPORTED** | `ReportBuilder` + `Serializer` emit TZ base fields additively; `test/case/report_contract_test.rb`; fresh `bin/finalize_submission` |
| OUT-01 | operation id | SUPPORTED | preserve |
| OUT-02 | final selected provider | SUPPORTED | final cascade provider remains external `selected_provider`; primary assignment reported separately |
| OUT-03 | ordered attempts | SUPPORTED | preserve internal classification/order |
| OUT-04 | organizer provider/decision/reason | **SUPPORTED** | minimal projection uses stable concrete selection/outcome reasons; rich traces remain additive |
| OUT-05 | approved/rejected/expired | SUPPORTED | preserve bounded deterministic simulation |
| OUT-06 | latency | SUPPORTED | preserve typed non-negative value |
| OUT-07 | rich explanations | SUPPORTED in rich report/internal evidence | preserve as additive extension |
| HC-01 | exact active status | **SUPPORTED** | Case `Provider#active?` is literal-only; `test/case/state_test.rb`; public queue remains green |
| HC-02..10 | remaining official hard constraints | SUPPORTED | preserve fallback/state regressions |
| SG-01 | count-share routing | SUPPORTED for primary routing | preserve assignment authority; remove fallback double-counterfactual |
| SG-02 | volume-share routing | SUPPORTED for primary routing / explicit provenance | canonical profile declares its source; configured independent override is supported and tested |
| SG-03 | lower-is-higher priority | SUPPORTED | preserve |
| SG-04 | amount preference distinct from hard gate | **SUPPORTED** | canonical transparent bands; loaded hard-eligible conflict regression in `test/case/submission_profile_test.rb` |
| SG-05 | conversion preference | SUPPORTED | preserve |
| SG-06 | load/intensity preference | SUPPORTED capability | release profile enables load; intensity remains explicit optional input |
| SG-07 | turnover-min obligation | SUPPORTED / explicit optional input | preserve; do not invent absent organizer values |
| SG-08 | multiple goals simultaneously | **SUPPORTED** | one resolver with explicit primary/fallback phase; fallback oracle and case matrix |
| SG-09 | explicit ConflictResolver | SUPPORTED | one resolver remains authority; add phase semantics rather than second chooser |
| SG-10 | infeasible target explanation | **SUPPORTED** | hard-forced over-target, structural under-target and bounded workload-granularity evidence; `test/case/recommendation_test.rb` |
| FB-01 | reject -> next | **SUPPORTED** | explicit fallback phase; A→reject→C regression and assignment/attempt/settlement accounting |
| FB-02 | expired -> next | **SUPPORTED** | same canonical fallback phase; existing expiry cascade plus strict replay |
| FB-03 | reapply hard constraints | SUPPORTED | preserve |
| FB-04 | terminal self-provider | **SUPPORTED** | terminal identity is explicit configuration/profile; arbitrary zero-participation providers are not inferred |
| STATE-01..04 | sequential provider state | SUPPORTED | preserve |
| EXP-01 | concrete selection reason | **SUPPORTED** | stable only-eligible/highest-composite/fallback/tie-break reason codes; public validator remains green |
| EXP-02 | exclusion reason | SUPPORTED | preserve stable codes |
| EXP-03 | actual fallback sequence | SUPPORTED internally / projection compatible | preserve |
| AN-01 | count/share | **SUPPORTED** | serialized `distribution.*.count/share_pct/target_pct`, exact rich shares retained; independent report contract test |
| AN-02 | target deviation | SUPPORTED rich / P0 projection | preserve rich exact fields, add base-compatible projection |
| AN-03 | outcomes | SUPPORTED | separate assignment/attempt/settlement ledgers |
| AN-04 | utilization/limits | **SUPPORTED** | serialized `projected_daily_utilization.*.used/limit/utilization_pct`; independent report contract test |
| AN-05 | skip reasons | SUPPORTED | preserve |
| AN-06 | deviation causes | **SUPPORTED** | hard exclusions, hard-forced, fallback and workload-granularity causes from canonical run |
| AN-07 | actionable recommendations | **SUPPORTED** | base strings + rich provider/evidence/action details; near-limit/structural/granularity regressions |
| FLEX-01 | provider independent | SUPPORTED | preserve |
| FLEX-02 | config-driven rules/weights | SUPPORTED | preserve canonical profile |
| FLEX-03 | add provider/factor without redesign | SUPPORTED | preserve one factor registry/resolver |
| RULE-01..04 | deterministic/Ruby/no neural/proprietary | SUPPORTED | preserve |

## Release-critical interpretation

The TZ base `routing_report` schema is authoritative even without a public report validator. Additional rich fields are allowed, so the safe strategy is base compatibility plus additive extensions.

Current evidence: the finalization path writes and reparses a report with the required
base shape, and `OrganizerReportContractValidator` checks that shape independently;
percentage numbers are rounded to two decimal places only by `Serializer` at the JSON
boundary while internal values remain exact `Rational`.

Primary assignment remains the bounded authority for count/volume distribution unless stronger organizer clarification says otherwise. Therefore rejected/expired fallback must not counterfactually assign the same operation a second time when ranking fallback providers.

## Protected scoring-low capabilities

Production economic ownership/UNKNOWN, durable restart/replay, RecoveryExecutor and HTTP control plane remain protected but frozen unless SPEC-018 exposes a blocker.

## Traceability rule

A row moves to `SUPPORTED` only after finalization-equivalent code, generated artifact and independent contract/rubric evidence agree. Public-validator permissiveness and self-derived validators do not independently close a row.
