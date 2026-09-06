# SPEC-021 — Autonomous Product Excellence & Score Maximization

Status: **ACTIVE / ROLLING**

Program: **v0.4.4 — Competition 10/10 Convergence**

Completed implementation baseline: `50b969575f482610460b805d199acc725e8eb37b` (SPEC-020). Exact current `main` is runtime evidence and must be refetched.

## Objective

Continuously maximize expected Hack.Genesis score and product quality under the authoritative TZ without turning development into a rigid pre-written patch sequence.

The coding agent owns skeptical discovery, prioritization, implementation, testing and re-audit. This specification defines product invariants, evidence quality and completion discipline; it deliberately does not prescribe the next patch before current code/data/artifacts are analyzed.

Official TZ/rubric remains immutable authority. This derived engineering SPEC may strengthen implementation/evidence requirements but cannot weaken or rewrite organizer semantics.

## Product architecture target

Canonical product model:

`Input -> Opportunity -> Portfolio Objective -> Selection -> Execution Cascade -> Settlement -> Causal Evidence -> Feasibility/Counterfactual Analytics -> Independent Validation -> Submission`.

The product should be stronger than the minimum TZ by making business semantics stable, provider-independent, deterministic and directly explainable to judges.

## S21-1 — constraint-safe opportunity model

Every choice begins with explicit hard eligibility. Hard violations are absolute, typed and explainable. Fallback re-evaluates current state. Terminal fallback is explicit configuration, never an ordinary positively weighted provider.

No score, tie-break, ordering path or fallback shortcut may resurrect a hard-ineligible provider.

## S21-2 — explicit objectives; no hidden business preference

Only explicitly configured positive business objectives may influence business preference. A disabled/zero-weight/absent factor must not alter a winner through a secondary ordering path.

A deterministic tie-break must be semantically neutral or explicitly configured and visible. Business `priority` must not secretly remain active merely because it is convenient for tie resolution.

## S21-3 — stable multi-objective mathematics

The engine supports count/volume allocation plus priority, amount preference, conversion, load, intensity and turnover obligations with exact deterministic evidence.

The scoring model should satisfy, where applicable:

- provider enumeration invariance;
- common positive weight-scale invariance;
- zero-weight/disabled-factor independence;
- monotonic factor semantics when other evidence is fixed;
- deterministic transparent tie behavior;
- robustness to irrelevant/dominated candidate perturbation;
- explicit target mass/provenance validation;
- stable normalized/contribution meaning across comparable opportunity sets.

Candidate-relative min/max normalization was an audit hypothesis, not a protected design. A current Router counterexample identified unjustified A/B inversion from both dominated and non-dominated candidate additions, so built-in preference factors now use fixed semantic `[0,1]` bounds while count/volume retain fixed `[-2,0]` portfolio-loss bounds. Any future normalization change still requires a current counterexample and stronger invariant.

## S21-4 — opportunity-aware portfolio allocation

Count and volume are portfolio routing objectives. Candidate ordering should correspond to an explicit post-decision portfolio objective for the supported target model, not an unexplained local heuristic.

For small deterministic portfolios, an independent oracle must be able to calculate the candidate ordering from business target semantics without calling the factor implementation.

Impossible targets caused by hard constraints, target mass or finite workload must be diagnosed rather than hidden by soft score.

## S21-5 — lifecycle semantic integrity

Primary assignment, selection rationale, invoked attempts, provider outcome, final selected provider and approved settlement are distinct facts. Each external/report projection declares which population it represents. Organizer ambiguity stays explicit and reversible rather than being hidden by collapsing ledgers.

`why selected` and `what happened at the provider` are different evidence.

## S21-6 — causal explainability

For every operation the evidence model should answer:

- who was hard-excluded and why;
- who was eligible/considered;
- each configured factor's raw value, stable scale/normalization, weight and causal contribution or equivalent;
- why the chosen provider won, including tie semantics;
- what the provider then returned;
- why fallback continued;
- which provider finally settled.

Minimal organizer DTO compatibility may constrain serialization, but rich evidence must retain the causal chain.

## S21-7 — typed configuration and extensibility

Policy semantics live in typed profile/config data, not provider-name branches. Target sources, target mass, weights, amount bands, RPM/intensity and turnover obligations are explicit when used. Missing optional configuration has neutral semantics.

Adding a provider or factor must not create a second router or silently change unrelated preferences. Configuration success means economically coherent semantics, not merely parseable JSON.

## S21-8 — feasibility, recommendations and counterfactual analytics

Analytics cover count/volume target deviation, assignment/attempt/final/settlement populations, success/failure/expiry/fallback, utilization and structural causes. Diagnose forced-over-target, constrained-under-target, workload granularity and terminal fallback.

Recommendations should name a concrete controllable parameter/rule and supporting evidence. Prefer deterministic bounded what-if/counterfactual evidence when it materially improves judge understanding; ML is unnecessary.

## S21-9 — judge-visible rubric evidence

A capability existing only in unit tests is insufficient when deterministic evidence can expose it safely. Maintain a compact evidence lab using the same Case engine and typed profiles to demonstrate:

- count routing;
- volume routing with a genuinely independent volume target;
- priority;
- amount preference;
- conversion;
- load;
- intensity/RPM;
- turnover obligation;
- multiple genuine multi-goal conflicts and weight changes;
- infeasible target diagnosis;
- rejection/expiry fallback and terminal route;
- analytics/recommendations.

No demo-only chooser and no operation-id-specific routing logic.

## S21-10 — submission and temporal safety

SPEC-020 guarantees are protected: explicit queue, fixed root artifact names, post-serialization validators, manifest/byte binding, Git trackability, deterministic bytes and snapshot-offset business dates.

Current committed `_test` artifacts may be public-fixture evidence before the hidden queue arrives. Final submission readiness must independently prove artifact freshness/provenance against the actual hidden queue and exact pushed HEAD.

## S21-11 — independent verification

Use independent, metamorphic or hand-calculated oracles where correlated implementation replay could hide a semantic defect. Testing attacks invariants, not assertion count.

Resolver-level evidence is insufficient when Router call-site behavior can change the candidate pool or ordering; include end-to-end metamorphic probes for score-critical invariants.

Especially valuable probes include factor disablement, weight scaling, provider ordering, irrelevant candidates, target conservation, fallback lifecycle, additional-provider configuration and serialized report recomputation.

Independent verification is a means to protect externally meaningful semantics, not an objective to maximize. Prefer representative failure classes over exhaustive malformed-permutation enumeration. Once a boundary has authoritative/bounded semantics, representative independent coverage, recent blind-audit evidence and no material open P0/P1, further same-class guards require a concrete new counterexample, materially different hidden-test exposure or authoritative clarification.

## S21-12 — autonomous prioritization

At each material iteration, create/update findings with:

- TZ/rubric dimension and points at risk/gain;
- severity if wrong;
- confidence and hidden-test/judge exposure;
- independent reproducer plan;
- implementation/regression cost;
- judge visibility/product-story benefit;
- evidence-saturation state and marginal expected score gain.

Select the highest expected-value material hypothesis, not the oldest documented item. The rolling ExecPlan and finding registry may be rewritten when evidence changes priorities.

### Evidence-saturation rule

A STRONG/PROTECTED surface with representative independent coverage and no current material P0/P1 should be treated as saturated for prioritization. Do not continue adding near-duplicate semantic-oracle guards just because a new malformed combination can be imagined.

A new concrete counterexample immediately reopens the surface. Otherwise move effort to the highest-value PARTIAL rubric dimension. In the current score posture, genuine multi-goal conflict semantics, causal explainability and judge-visible proof of all routing strategies generally outrank additional guard accumulation on already protected release/report boundaries.

## S21-13 — better-than-TZ product discipline

Improvements beyond minimum TZ are encouraged only when they increase scored correctness/flexibility/explainability/analytics/extensibility or materially lower release risk. Production-grade safety already present is an advantage; speculative infrastructure is not.

## Current code-first seed hypotheses

These seed discovery but do not override autonomous priority. Before creating another validator/semantic-oracle guard on a protected surface, compare its expected value with the open PARTIAL scorecard areas.

1. composite-score ties currently use provider id only; current Router/tie-break regressions cover zero-weight priority independence, while any alternate-path priority leakage still requires a distinct reproducer;
2. Router supplies the live eligible set as an explicit opportunity pool; built-in fixed scales now prevent irrelevant eligible C from inverting A/B solely through scaling mechanics;
3. failed selected attempts currently expose `provider_rejected/provider_expired` as reason; verify selection-rationale/outcome separation in judge-visible evidence;
4. independently compare count/volume ordering with an explicit post-decision portfolio loss/objective;
5. keep organizer base distribution under fallback reversible across primary/final/settlement interpretations until stronger authority exists;
6. judge-visible evidence currently under-exposes implemented factors, especially independent volume, intensity and turnover;
7. target provenance/mass and additional-provider configuration need hidden-like evidence;
8. any fresh code-first material finding may supersede all of the above.

## Protected boundaries

Do not weaken hard gates, assignment/attempt/settlement separation, exact arithmetic, deterministic simulation, one routing-choice authority, independent validators, SPEC-020 release/calendar guarantees or production UNKNOWN/economic-owner safety without a reproduced higher-authority blocker.

No DB/Redis/queues/microservices/ML/general DSL/real PSP/broad refactor for optics.

## Acceptance / completion

Closing known findings gives only `VERSION_CANDIDATE`. Then perform a fresh blind audit of actual code/data/artifacts without trusting backlog/status, build rubric-by-rubric deterministic judge evidence and run a clean final submission rehearsal.

Any material P0/P1, hidden objective, unproven high-value rubric row or new authoritative mismatch returns ACTIVE. `VERSION_COMPLETE` requires blind-audit closure, score evidence strong enough to defend the result, clean release provenance and exact pushed-head CI after final changes.
