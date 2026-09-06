# AGENTS.md

## Mission

Build the strongest submission-grade Ruby solution for Hack.Genesis **«Умный роутинг выплат»** under the authoritative TZ.

Current Version Goal: **v0.4.1 — Submission Policy Activation & Contract Closure — VERSION_COMPLETE**.

Opening baseline: `0187bf2558d58a52dfdb27e76694d6323addbcd6` (v0.4.0 completed case engine).

## Read before coding

1. `README.md`
2. `AGENTS.md`
3. `docs/AUTHORITY.md`
4. SPEC-017
5. SPEC-016 baseline
6. `docs/TZ_REQUIREMENT_MATRIX.md`
7. active v0.4.1 ExecPlan
8. `docs/POST_TZ_BACKLOG.md`
9. current architecture/decisions/completion/testing docs
10. actual `data/`, `scripts/validate_10.rb`, case code/tests and exact-head CI.

Documentation is intended authority. Code/output evidence proves reality.

## Why v0.4.1 remains active

The opening audit on `0187bf2558d58a52dfdb27e76694d6323addbcd6` confirmed that
finalization used empty targets, priority-only scoring and always-approved
simulation, and that assignment, attempt and settlement meanings were mixed.
Those findings are now closed on the current candidate HEAD: the supported
finalizer and case CLI load `data/submission_profile.json`, run the canonical
multi-factor path, preserve separate ledgers, project a minimal organizer DTO,
and strictly revalidate serialized artifacts. The blind candidate audit and
fresh exact-HEAD verification satisfied `docs/COMPLETION_POLICY.md` on the
pushed completion HEAD.

## Mandatory order

### P0/P1-A — canonical submission policy

Use one typed, repository-controlled submission profile from both
`bin/finalize_submission` and the supported case CLI. No second hidden chooser
and no demo-only intelligence.

The profile must explicitly define/provenance:

- count target source — official `traffic_percentage` for participating external providers unless stronger authority says otherwise;
- volume target source — explicit configured/derived source with report provenance; never silently invented;
- enabled factor weights;
- independently configured amount-preference bands;
- optional RPM/min-turnover values only when explicitly configured;
- deterministic simulation mode/seed;
- terminal provider identity.

Do not overfit weights to the public 10-row queue. Use bounded explainable defaults and prove sensitivity with synthetic conflict campaigns.

### P1-B — separate accounting points

Do not use one ledger for incompatible business meanings.

At minimum distinguish:

1. **primary assignment** — provider initially selected for the new payout; this is the default authority for count/volume distribution objectives under the TZ wording unless stronger organizer evidence contradicts it;
2. **attempts** — every actually invoked provider in fallback order;
3. **final outcome / settlement provider** — approved final provider, if any.

Keep report metrics for assignment and settlement separately. A rejection must not erase the fact that traffic was assigned/attempted there.

### P1-C — output contract

Internal attempt states must distinguish:

- hard excluded / never called;
- selected and attempted → rejected;
- selected and attempted → expired;
- selected and attempted → approved;
- terminal final non-approval.

The organizer DTO is a projection, not the internal model. Preserve `selected`/`skipped` compatibility conservatively, document top-level `selected_provider` semantics, and keep rich score traces out of the external decisions file unless compatibility is proven. Prefer rich evidence in `routing_report*.json`.

After serialization, reopen both generated JSON files and validate their actual JSON types/shape/content. In-memory validation alone is insufficient.

### P1-D — amount preference

Hard min/max and soft preferred amount range are different concepts. Add typed preferred ranges/configuration; do not derive preference midpoint from the same hard limits and call the rubric complete.

### P1-E — analytics/recommendations

Report separately:

- assignment count/volume distribution;
- attempts/outcomes;
- final approved/settlement distribution;
- target deviations and infeasibility causes;
- hard-rule reasons;
- utilization;
- fallback metrics.

Recommendations must recommend a change that would actually address the evidence. An over-target hard-forced provider should normally trigger target adjustment or improvement of alternatives, not expansion of that same provider's capacity by default.

### P1-F — hidden-like robustness

- index decisions/operations in strict validation instead of repeated linear `find` where material;
- run larger synthetic queues/provider sets;
- test non-public queue finalization with the canonical smart profile;
- prove deterministic output after serialization;
- prove no extra public-decision fields are required for internal explainability.

## Protected case architecture

Keep one competition routing path:

`Input → CaseConfiguration/SubmissionProfile → CaseState → HardConstraintEvaluator → TrafficLedger/accounting → Factors → ConflictResolver → Router/Simulator → projections → validators`.

Hard constraints remain absolute and rerun on fallback. A score never revives an ineligible provider.

## Protected production kernel

Never weaken production UNKNOWN/economic ownership merely to satisfy synthetic judge expiry. Judge `expired → next provider` stays inside `RubyRouting::Case`.

## Evidence discipline

For every material fix:

`reproduce → smallest semantic change → focused tests → adjacent case tests → public queue/finalization → organizer validator → strict serialized-output validator → inherited relevant matrix → docs/traceability → commit/push`.

Do not use public-validator permissiveness as a design oracle.

## Candidate gate

Before `VERSION_CANDIDATE`, prove all of the following:

- exact finalization path loads the canonical smart profile;
- finalization is not priority-only and not forced always-approved by accidental defaults;
- count and volume can both affect finalization routing;
- current conversion/load can affect a finalization-equivalent run;
- assignment and settlement accounting are separately recomputable;
- amount preference is independently configurable;
- external decisions JSON is minimal/compatible and post-serialization validated;
- fallback output is semantically consistent internally and conservatively projected;
- public goldens and public validator remain green;
- report/recommendations are recomputable and evidence-correct;
- hidden-like scale/determinism campaigns are green.

The known scope passed the candidate gate, and the blind code/data-first pass
against all entrypoints and generated files is complete on the pushed HEAD.
Any new material local P0/P1 returns ACTIVE.

## Non-goals

No Rails/ORM, DB, Redis/Sidekiq, queues, microservices, real PSP integrations, ML/bandits/neural networks, generic DSL/plugins, broad Coordinator rewrite or new generic recovery machinery. Do not solve activation gaps by building infrastructure.

## Goal Mode

Work continuously while the next scoring/release step is derivable. Do not stop after one green fix or one public-validator run. Stop only at genuine v0.4.1 completion under `docs/COMPLETION_POLICY.md`, an external blocker with no independent work, or new organizer authority requiring reconciliation.
