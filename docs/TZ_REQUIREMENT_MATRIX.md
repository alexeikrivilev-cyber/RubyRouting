# Authoritative TZ Requirement Matrix

Program: **v0.4.4 ACTIVE / SPEC-021**.

Completed implementation baseline: `50b969575f482610460b805d199acc725e8eb37b`. Current status must be recomputed from exact `main`.

Legend: `SUPPORTED` = current end-to-end evidence is strong; `PARTIAL` = capability exists but semantics/judge evidence still warrants work; `AMBIGUOUS` = organizer authority does not fully define projection; `MISSING`; `CONFLICT`.

| Requirement group | Status | Current evidence / risk |
|---|---|---|
| Official inputs / operation coverage | SUPPORTED | strict loaders, exact boundaries and deterministic ordered queue |
| Required root decisions/report artifacts | SUPPORTED / PROTECTED | explicit queue, fixed root paths, post-write validators, manifest, Git trackability and release-level validated-byte parity against committed `HEAD`; hidden-queue freshness is a final-rehearsal obligation |
| Hard constraints | SUPPORTED / PROTECTED | status, amount, daily/concurrent, banks, margin, requisites and RPM; explicit `terminal_provider_id` is separate from ordinary eligibility, while `traffic_percentage` remains a soft count/volume target; all hard gates rerun on fallback |
| Count-share routing | SUPPORTED / OBJECTIVE EVIDENCE | final-selected TrafficLedger records each operation once after fallback; primary assignment is a separate ledger; global post-decision count L1 objective has independent two-operation regression |
| Volume-share routing | SUPPORTED / IMPROVED evidence | final-selected exact volume L1 objective exists without rejected-primary phantom accounting; main demo and evidence CLI use explicit independent volume targets, while the canonical submission profile intentionally derives volume from `provider.traffic_percentage` |
| Priority / amount / conversion / load | SUPPORTED capability | typed factors and weighted resolver; exact ties use provider-id determinism and configured priority is explicit; each absent or zero optional capacity dimension is neutral/no-headroom evidence rather than silently renormalized or divided by zero |
| Intensity / turnover-min | SUPPORTED optional capability / IMPROVED PARTIAL judge evidence | absent optional RPM configuration is neutral, typed zero RPM has exact no-headroom evidence and hard RPM gating remains separate; canonical profile still does not enable intensity/turnover, while four fresh synthetic Router scenarios show stateful intensity-vs-conversion and turnover-vs-conversion reversals with explicit warmup hard exclusion |
| Explicit factor disablement / zero-weight semantics | SUPPORTED CORE / IMPROVED ALTERNATE-PATH EVIDENCE | positive-weight frontier excludes zero-weight factors; Router regressions cover exact ties, a non-tied conversion/load winner, monotonic improvement of priority/amount/conversion/load/intensity/turnover preference inputs and a rejected-primary fallback cascade with every other zero-weight factor; count/volume remain active in fallback against the uncommitted final-selected ledger, while zero-weight traces remain inert |
| Simultaneous multi-goal resolution | SUPPORTED / PARTIAL final evidence | one formal resolver; canonical Router evidence now includes conversion/load, priority/load and amount/conversion reversals on the authoritative queue, alongside fixed built-in factor bounds, exact-tie priority, dominated/non-dominated candidate scale stability and count/volume portfolio-loss semantics; broader factor-weight semantics remain audit surfaces |
| Fallback reject/expired/recheck/terminal | SUPPORTED / PROTECTED | deterministic Case cascade and explicit terminal |
| Sequential state / business day | SUPPORTED / PROTECTED | absolute ordering/RPM plus snapshot-offset daily calendar |
| Attempt/exclusion/fallback explanations | SUPPORTED / IMPROVED PARTIAL AUDIT | hard reasons strong; minimal public outcome reason remains compatible while canonical serialized explanations now preserve exact per-provider factor traces plus independently checked resolver winner/reason semantics and one ordered hard-gate/resolver/fallback/terminal causal chain with independent lifecycle identity/outcome checks, and the runnable fallback evidence projects that same chain alongside primary rationale, failed provider outcomes, terminal final selection and explicit primary/final/settlement populations |
| Assignment/attempt/final-selection/settlement analytics | SUPPORTED rich | distinct ledgers and report projections; independent oracle fail-closes null/malformed raw roots and checks raw provider root/provider identifiers/queue contracts before validating typed attempt objects, provider uniqueness, bounded attempt-reason vocabulary, selected-attempt rationale and typed outcome presence, terminal decision-chain shape, final-provider/final-outcome linkage to the last selected attempt, recomputed per-provider and aggregate attempt/final-selection/settlement distributions plus skip/attempt/final/fallback/assignment/traffic/settlement population metrics, lifecycle explanation identity/coverage against serialized attempts, raw-derived dataset/provider-state/deviation projections, explicit raw-history source/row/volume/provider/rate/latency recomputation, UTC queue period-window provenance, configuration/profile/target provenance, submission-profile identity provenance and infeasibility evidence; history remains calibration/trends-only |
| Organizer base distribution | SUPPORTED final-selected projection | compact `distribution` and its target/deviation analytics use final selected providers; `assignment_distribution` remains primary assignment and `settlement_distribution` remains approved-only, with an independent A-rejected→B-approved population check |
| Target provenance / target mass | PARTIAL / SOURCE-MASS GUARDED | provider-derived count/volume targets now fail closed unless active non-terminal `traffic_percentage` has exact mass `1`, including supplied typed profiles, and source vocabulary is bounded on both typed/file paths; direct typed configuration provenance is non-empty; configured partial maps remain explicit for bounded diagnostics, positive terminal targets fail closed, and the independent semantic oracle recomputes rich count/volume targets/deviations while rejecting negative, under-mass or over-mass provider-source maps; broader business provenance remains open |
| Target deviation / infeasibility / recommendations | SUPPORTED / IMPROVED evidence | rich cause data plus finite-workload volume-granularity evidence exists; structural count/volume advice now requires a dimension-specific hard-eligibility capacity counterfactual, while generic advice remains for attainable deficient dimensions; independent serialized validation binds recommendation provider/action/detail and deterministic presentation text to recomputed target/utilization/workload facts; broader quantitative/counterfactual audit remains |
| Provider/config extensibility | SUPPORTED architecture / IMPROVED JUDGE EVIDENCE | typed profile/factor registry; provider-derived targets are exact and dataset-bound on loader, Runner and direct Router paths, profile/configuration source+revision cannot diverge, direct typed profiles reject empty identity/provenance just like the loader, and the independent report oracle rejects malformed raw provider snapshots; runnable Router evidence now shows an executable active additional provider with exact `1/10` target, an `enabled` zero-participation shadow with `inactive_provider`, and provider-order invariance; positive optional weights without optional inputs are explicit exact-zero neutral/non-discriminating traces, every provider-keyed map rejects unknown providers on direct and JSON profile paths, and broader target provenance remains |
| Deterministic Ruby / no neural/proprietary | SUPPORTED / PROTECTED | Ruby-only, exact arithmetic, deterministic simulation |
| Submission input/trackability/manifest/calendar | SUPPORTED / PROTECTED | SPEC-020 explicit queue, trackability, manifest, committed-byte release guard and snapshot-offset calendar closure |
| Judge-visible rubric coverage | SUPPORTED / IMPROVED PARTIAL | runnable Case demo/evidence CLI exposes all eight factors, a canonical Router count-vs-independent-volume target campaign, three canonical Router-level weight-conflict pairs with changed-operation deltas and paired left/right resolver traces, optional-factor reversals and an additional-provider/status boundary with explicit profile target-source provenance and zero-weight independence evidence, fallback causal chain, analytics, typed recommendation provider/evidence/action details and canonical typed submission-policy identity/source/revision/target provenance/weights, with explicit canonical-versus-synthetic scenario scope; hidden-like breadth and richer presentation can still improve |

## Derived engineering invariants

These do not replace TZ; they make scored behavior defensible:

- hard gates precede all soft objectives;
- disabled/zero-weight factor independence;
- deterministic neutral or explicit tie-break;
- stable factor scale/weight meaning;
- provider-order invariance;
- irrelevant/dominated-candidate robustness;
- explicit target provenance/mass;
- lifecycle population separation;
- selection rationale distinct from provider outcome;
- final artifacts proven fresh against actual submission input.

## Traceability rule

Do not move a row to SUPPORTED from documentation or self-replay alone. Use authoritative wording, independent/metamorphic evidence and finalization-equivalent artifacts where applicable. Agent-discovered material rows should be added instead of forced into an unrelated old category.
