# Post-TZ Backlog — v0.4.3 Adversarial Evidence & Contract Semantics Closure

Status: **VERSION_COMPLETE**

Spec: `specifications/019-adversarial-evidence-contract-semantics.md`

Opening baseline: `277d6b68d568eceb88ece3b3e466987535ff75bd`.

v0.4.2 / SPEC-018 is the completed compatible baseline. This backlog contains only fresh code-first findings and evidence-gated follow-ups.

## P1 — release semantics and independent evidence

### TZ19-101 — organizer distribution accounting point — EVIDENCE CLOSED (2026-09-04; authority ambiguous)
Current rich accounting cleanly separates primary assignment, attempts and settlement, but organizer base `distribution` projects primary assignment while decisions expose the final cascade provider. A deterministic independent probe proves the three populations diverge for `A rejected -> B approved`; literal TZ `distribution by provider` and the public sample/validator do not specify the fallback population. Keep primary assignment as the conservative reversible base projection and retain final/settlement/attempt distributions richly. Regression: `test/case/accounting_semantics_test.rb`.

### TZ19-102 — independent semantic report oracle — CLOSED (2026-09-04)
`RubyRouting::Case::OrganizerReportSemanticValidator` parses raw providers/queue/profile and serialized decisions/report without using `ReportBuilder` expected values. It recomputes queue coverage, primary-assignment population/count denominator, `share_pct`, declared `target_pct`, approved-settlement projected daily `used/limit/utilization_pct` and UTC period. Finalization and the case CLI execute it after serialization. `test/case/report_semantic_test.rb` covers canonical/fallback outputs plus shape-valid mutations for each semantic field; public and strict validators remain separate layers.

### TZ19-103 — candidate-set normalization robustness — CLOSED (2026-09-04)
The deterministic canonical-weight A/B/C campaign confirmed a material
candidate-relative min/max artifact: hard-eligible non-winning C changed A/B's
winner while their raw count/volume/priority/amount/conversion/load evidence
stayed fixed. `ConflictResolver` now requires an explicit normalization pool and
fails closed if it omits a scored candidate; Router and strict replay pass the
complete current eligible pool. `test/case/normalization_perturbation_test.rb`
proves stable A/B selection and raw/normalized perturbation invariants, while
the public finalization output remains unchanged.

### TZ19-104 — multi-day daily-state semantics — CLOSED (2026-09-04)
The deterministic cross-midnight reproducer confirmed that cumulative daily
usage incorrectly carried a snapshot-day baseline into the next UTC date. The
ordered TZ queue is not declared single-day, so `ProviderCaseState` now anchors
the supplied baseline to `snapshot_at`'s UTC date and resets only
`daily_approved_amount` when the operation date advances. RPM, in-progress,
attempt, route and settlement state remain continuous. The regression also
checks latest-day report utilization and strict replay conservation:
`test/case/daily_temporal_test.rb`.

### TZ19-105 — missing preferred amount range neutrality — CLOSED (2026-09-04)
The additional-provider reproducer confirmed that absent optional configuration
returned strongest raw preference `1` and could beat a configured non-matching
band. Missing bands now return exact raw `0`; equal missing/non-matching values
are non-discriminating and contribute zero, with a stable explanation. Existing
configured canonical bands remain active. Regression:
`test/case/amount_band_neutrality_test.rb` plus the inherited factor/profile
campaigns.

### TZ19-106 — semantic-oracle malformed raw boundary — CLOSED (2026-09-04)
An independent blind probe passed a raw provider with non-exact
`traffic_percentage` to the semantic report oracle and reproduced an uncaught
`NoMethodError`. The oracle now rejects malformed provider/queue/profile/report
shapes, identities and non-exact target values with ordinary validation errors,
without weakening the canonical input loader. Regressions:
`test/case/report_semantic_test.rb`.

### TZ19-107 — semantic-oracle empty-queue denominator — CLOSED (2026-09-04)
The blind pass used an empty queue, which the canonical Case loader permits,
and reproduced an uncaught `ZeroDivisionError` while recomputing zero-count
distribution shares. The independent oracle now emits exact zero shares for a
zero operation denominator and validates the empty serialized artifact. The
regression lives in `test/case/report_semantic_test.rb`.

## P2 — evidence gated

### TZ19-201 — terminal identity vs zero participation — EVIDENCE CLOSED (2026-09-04; no defect)
An explicit-terminal probe with two zero-traffic providers showed that the
configured active zero-participation identity is selected as terminal while the
other zero-traffic provider is correctly excluded as an external candidate.
The coupling is a typed case convention supported by the supplied data and TZ;
no production change is justified. Regression:
`test/case/terminal_causality_test.rb`.

### TZ19-202 — direct terminal fallback deviation causality — CLOSED (2026-09-04)
The generated all-hard-excluded artifact confirmed that direct terminal routing
could leave a zero-target/100%-actual deviation unexplained at report level.
Rich deviation causes and deterministic recommendations now identify configured
terminal fallback, its quantitative deviation and hard-excluded alternatives.
Regression: `test/case/terminal_causality_test.rb`.

## Protected completed baseline

Do not reopen without a new counterexample: TZ-compatible report shape, literal Case active status, primary/fallback phase split, assignment/attempt/settlement ledgers, concrete reason codes, canonical amount bands for current providers, neutral equal-factor contributions, deterministic recommendations and public finalization.

## Completion gate

All P1 items confirmed-fixed or explicitly evidence-closed -> VERSION_CANDIDATE only. Then run an independent code/data/artifact blind pass. Any new material P0/P1 returns ACTIVE. VERSION_COMPLETE requires fresh full inherited suites, case/adversarial campaigns, public decisions validator, independent report shape + semantic validators, strict serialized validation, clean finalization, docs consistency and exact pushed-head Actions success.

Candidate evidence (2026-09-04, exact code checkpoint
`f1fc24f1637101e41c3d94b8140105a1917f60dd`): post-fix full inherited and Case
matrices are green (`test` 855/13,603; `property` 4/1,210; `model` 3/2,958;
`concurrency` 45/1,441; `fault` 407/4,900; `case` 115/637). Finalization
produced fresh root artifacts; public validation is 29 passed, 0 errors,
0 warnings; independent shape+semantic validation and strict serialized
validation pass. The alternate Case CLI produces byte-identical artifacts.
The 1,000-operation hidden-like campaign now also runs independent semantic
validation and remains deterministic. The post-fix blind pass found no new
material P0/P1. This candidate gate was followed by clean final docs sync and
exact-head CI.

Final closure (2026-09-04, exact pushed HEAD
`13efbeba48f1726b91b71b1677d3541dd4f9f433`): all SPEC-019 P1/P2 evidence,
fresh full inherited/Case/adversarial matrix, clean-checkout finalization,
public decisions validation, independent shape+semantic report validation,
strict serialized validation and exact-head Actions run `33852436704` passed.
No material local P0/P1 remains; v0.4.3 is VERSION_COMPLETE.

## Frozen

No generic recovery/restart hardening, HTTP polish, DB/Redis/queues/microservices, real PSP adapters, ML/neural networks, generic DSL or broad production refactor without a direct SPEC-019 blocker.
