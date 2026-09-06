# Product North Star — Smart Routing Beyond Minimum TZ

Program: **v0.4.4 / SPEC-021 — ACTIVE**.

This document is the technical direction, not a fixed patch queue. The coding agent may discover a better next problem after inspecting current code/data/artifacts, but improvements should move the product toward this architecture and maximize expected TZ/rubric score.

## Product thesis

RubyRouting should be a single coherent smart-routing system that is safer, more explainable and more configurable than the minimum case implementation while staying simple enough for a hackathon submission.

Canonical model:

`Input -> Opportunity -> Portfolio Objective -> Selection -> Execution Cascade -> Settlement -> Causal Evidence -> Analytics/Counterfactuals -> Independent Validation -> Submission`

The system should make every important decision auditable and every scored capability demonstrable.

## Layer 1 — Opportunity / hard eligibility

Provider eligibility is an absolute typed contract. Status, amount bounds, daily/concurrent limits, bank rules, margin agreement, requisites and RPM are evaluated before soft scoring and re-evaluated on fallback. `traffic_percentage` is a soft count/volume target, while explicit terminal identity is handled outside ordinary candidate eligibility.

No soft factor, fallback shortcut or tie-break may resurrect a hard-ineligible provider.

## Layer 2 — Portfolio objective

The smart-routing layer is one explicit configured objective over the hard-eligible opportunity set.

Count and volume are portfolio objectives, not random weights. Priority, amount preference, conversion, load, intensity and turnover are typed business objectives. Disabled/zero-weight/absent objectives are semantically inactive.

The objective model should have stable business meaning under:

- provider enumeration changes;
- common positive weight scaling;
- disabled-factor removal;
- monotonic improvement of one factor;
- irrelevant/dominated candidate perturbation;
- target/config changes.

Tie-break is outside business score only if it is semantically neutral and deterministic. A disabled business priority must not leak through a hidden tie-break.

Do not mandate a normalization formula in advance. Prefer the simplest exact model that satisfies the invariants and can be explained to judges.

## Layer 3 — Execution cascade

Routing choice and provider outcome are different facts.

Preserve:

`primary assignment -> selected attempt rationale -> provider outcome -> fallback decision -> final provider -> approved settlement`.

Fallback reuses the same routing authority over the remaining eligible opportunity set; do not create a second chooser. Case `expired -> next provider` remains bounded competition semantics and never weakens production UNKNOWN/economic-owner safety.

## Layer 4 — Causal evidence and analytics

For every operation the product should be able to answer:

- which providers were hard-excluded and why;
- which providers were eligible;
- which configured factors mattered;
- why the winner won;
- what happened at the provider;
- why fallback continued;
- which provider finally settled.

Analytics should distinguish primary assignment, attempts, final selection and settlement; count and volume target/actual; success/reject/expiry/fallback; utilization; structural infeasibility; finite-workload granularity and terminal fallback.

Recommendations should point to a concrete controllable parameter or rule and cite evidence. Prefer deterministic bounded counterfactuals when they make the product story clearer.

## Layer 5 — Evidence and release

Every scored capability should have compact deterministic judge-visible evidence using the same Case engine: count, independent volume, priority, amount, conversion, load, intensity, turnover, multi-goal conflicts, infeasible targets, fallback and recommendations.

Submission safety is part of product quality: explicit queue, exact required root filenames, post-write validators, manifest/byte binding, Git trackability, business-calendar consistency and final hidden-queue freshness/provenance.

Independent evidence protects these semantics, but evidence infrastructure is not an end in itself. Once a boundary has representative independent coverage, a recent blind pass and no material open P0/P1, spend the next engineering unit on a higher-value product/rubric gap unless a new distinct failure class is reproduced.

## Score-facing development bias

When release correctness and hard constraints are already STRONG/PROTECTED, the default next investment should move the judge-visible product forward: stronger multi-goal semantics, clearer causal explanations, independent count-vs-volume behavior, meaningful conflicts between business objectives, infeasibility diagnosis and compact demonstrations of all scored strategies.

Do not trade away safety for presentation. Do stop polishing already saturated validation boundaries when the marginal guard does not materially change expected score, hidden-test exposure or product defensibility.

## Product-quality invariants

1. Hard constraints are absolute.
2. One routing-choice authority; no hidden second chooser.
3. No hidden business objective outside configured policy.
4. Exact deterministic arithmetic for routing authority.
5. Stable objective semantics, not candidate-order accidents.
6. Lifecycle facts are never collapsed for convenience.
7. Explanations are causal, not merely descriptive.
8. Config is typed/provider-independent with neutral optional defaults.
9. Independent or metamorphic evidence is preferred over correlated replay, with risk-proportionate coverage rather than guard accumulation.
10. Release artifacts must be provably fresh and bound to the actual input.

## Current code-first seeds

These are high-value hypotheses to verify, not mandatory patches:

- `ConflictResolver` uses provider id for exact composite-score ties; `test/case/tie_break_semantics_test.rb` proves zero-weight priority independence. Built-in preference scales are fixed exact `[0,1]`, with Router perturbation evidence for dominated and non-dominated eligible additions.
- Router supplies the live hard-eligible set as an explicit opportunity pool, while built-in preference factors use fixed exact `[0,1]` bounds and count/volume use fixed `[-2,0]` portfolio-loss bounds. Router-level regressions cover dominated and non-dominated candidate stability plus zero-weight priority independence; remaining opportunity changes are distinct from pure scale artifacts.
- Failed selected attempts keep rejection/expiry as the minimal public `reason`; rich explanations expose the original resolver rationale separately and remain under audit for judge-facing clarity.
- Count/volume factor ordering is independently covered by an explicit post-decision portfolio L1 loss/objective; candidate-set scale effects are separated from legitimate opportunity changes.
- Organizer base `distribution` under fallback is the final-selected provider population; preserve primary assignment, attempts and approved settlement as separate named populations and keep their analytics explicit.
- Implementation supports more rubric factors than the current judge-visible evidence demonstrates.

A newly discovered higher-value P0/P1 supersedes these seeds immediately.

## What not to build

No Rails/DB/Redis/queues/microservices, ML/bandits/neural networks, generic routing DSL, real PSP integration or distributed exactly-once work for optics. Add infrastructure only if authoritative TZ or a reproduced score-critical blocker requires it.
