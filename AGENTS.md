# AGENTS.md

This file is the operational authority for coding agents working on RubyRouting. The repository `README.md` is intentionally product-facing; agent instructions, competition context, release procedure, score-oriented evidence strategy and autonomous operating rules live here.

## Mission

Autonomously drive RubyRouting to the strongest defensible Hack.Genesis submission: maximize expected TZ/rubric score while building a coherent smart-routing product that is stronger than the minimum case requirements.

Smart payout-routing system for Hack.Genesis case **«Умный роутинг выплат»**.

Ruby baseline: **CRuby 4.0.6**.

Program: **v0.4.4 — Competition 10/10 Convergence — ACTIVE**.

Governing specification: **SPEC-021 — Autonomous Product Excellence & Score Maximization — ACTIVE / ROLLING**.

Current technical direction: `docs/PRODUCT_NORTH_STAR.md`.

Completed implementation baseline: `50b969575f482610460b805d199acc725e8eb37b` — SPEC-020 submission-safety/business-calendar slice. Never trust this or any chat SHA as current; refetch `main` before work.

The project is deliberately not driven by a fixed patch queue. The coding agent owns skeptical code/data/artifact discovery, prioritization, implementation, testing, plan revision and re-audit under the authoritative TZ/rubric.

## Start every session from reality

Fetch exact `main`, exact-head CI, current generated artifacts and actual Case code before trusting documentation or chat context.

Documentation is an intended model. Code, artifacts and independent evidence prove reality.

Recommended operational read order:

1. `AGENTS.md`
2. user-facing `README.md` for the current product overview only
3. `docs/AUTHORITY.md`
4. `specifications/021-autonomous-product-excellence-score-maximization.md`
5. `docs/PRODUCT_NORTH_STAR.md`
6. `docs/COMPETITION_SCORECARD.md`
7. `docs/TZ_REQUIREMENT_MATRIX.md`
8. `docs/exec-plans/active/autonomous-product-excellence-score-maximization.md`
9. `docs/POST_TZ_BACKLOG.md`
10. `docs/DECISIONS_CURRENT.md`
11. `docs/CURRENT_ARCHITECTURE.md`
12. completion/session/plans/workflow/testing/roadmap
13. actual `data/`, organizer scripts, Case code/tests, generated artifacts and exact-head CI

The former README read order placed `README.md` before `AGENTS.md`; after the README cleanup, operational authority begins here instead. All former README directives are retained in this file.

## Current authority

Use this precedence when sources conflict:

`direct current instruction > authoritative TZ/rubric > organizer data/sample/reference/public validator > SPEC-021 > PRODUCT_NORTH_STAR > compatible completed SPEC-020/019/018/017/016 > COMPETITION_SCORECARD > active rolling ExecPlan > TZ_REQUIREMENT_MATRIX/POST_TZ_BACKLOG > current decisions/architecture/completion/testing/workflow > protected production invariants > implementation/tests > historical docs`.

## Product North Star

Canonical product direction:

`official inputs -> absolute hard eligibility -> explicit opportunity set -> stable configured portfolio objective -> selection -> provider attempts/fallback -> final provider -> settlement -> causal explanation -> feasibility/counterfactual analytics -> independent evidence -> fail-safe submission`.

The target is stronger than minimum compliance: deterministic, provider-independent, audit-friendly and operationally safe, with business objectives whose meaning remains stable when providers, configuration or workload change.

Build one five-layer product, not a collection of hacks:

`Opportunity -> Portfolio Objective -> Execution Cascade -> Evidence/Analytics -> Independent Release Evidence`.

### Opportunity

Hard constraints are absolute and typed. Status, amount, daily/concurrent limits, banks, margin, requisites, RPM/participation and fallback eligibility fail closed before soft scoring and are rechecked on fallback.

### Portfolio objective

Only explicitly configured positive objectives may affect business preference. Count/volume plus priority, amount, conversion, load, intensity and turnover must have stable explainable semantics. Disabled, zero-weight or absent factors must not leak through provider order or tie-break.

Actively test provider-order invariance, common weight-scale invariance, zero-weight independence, monotonicity, irrelevant/dominated candidates, exact tie semantics and post-decision portfolio objective correctness. Do not preselect a normalization formula; reproduce the defect first.

### Execution cascade

Primary assignment, selection rationale, provider attempt, provider outcome, final selected provider and approved settlement are different facts. Fallback uses the same routing authority over remaining eligible candidates. No second chooser.

### Evidence / analytics

Explain who was excluded, who was eligible, why the winner won, what the provider returned, why fallback continued and who finally settled. Diagnose infeasible targets and prefer quantitative/counterfactual recommendations over generic advice.

The runnable judge evidence surface is `bin/ruby_routing_case_evidence`; it must use the canonical Case resolver/router/report paths and remain additive to, never a replacement for, production routing semantics.

### Release / judge evidence

Every scored capability should have compact deterministic judge-visible evidence using the same Case engine. SPEC-020 explicit queue, root artifacts, validators, manifest bytes, trackability and snapshot-offset business calendar are protected.

## Non-negotiable quality properties

- hard constraints can never be compensated by soft score;
- one routing-choice authority; no hidden second chooser;
- only explicitly configured business objectives may influence preference;
- disabled/zero-weight factors cannot leak through provider ordering or tie-breaks;
- tie-break behavior is deterministic, semantically neutral or explicitly configured and explainable;
- scoring should be stable under provider enumeration, weight scaling and irrelevant-candidate perturbations unless the real business opportunity changed;
- count/volume routing should correspond to an explicit post-decision portfolio objective;
- primary assignment, selection rationale, attempt, provider outcome, final provider and settlement stay separate facts, with the canonical Case report retaining separate aggregate populations;
- the Case target ledger records each operation once for its final selected provider after the cascade; `primary_assignment_ledger` preserves the first assignment separately for causal evidence;
- explanations are causal: why-selected and what-happened are distinct;
- every scored capability should have compact deterministic judge-visible evidence using the same Case engine;
- SPEC-020 explicit-queue, business-calendar, artifact-byte and release protections stay intact.

## Autonomous operating model

You are not a patch executor. Own discovery, prioritization, implementation, testing, skeptical re-audit and plan revision.

At session start and after every material checkpoint:

1. inspect actual code/data/artifacts and rubric evidence;
2. run a short code-first skeptical sweep before trusting documented findings;
3. formulate concrete hypotheses, including new ones absent from docs;
4. estimate rubric points at risk/gain, correctness severity, hidden-test/judge exposure, confidence, judge visibility, regression cost and diminishing-return risk;
5. choose the highest expected-value material issue or tightly coupled cluster;
6. independently reproduce/falsify before changing semantics;
7. state the authoritative invariant or bounded interpretation;
8. implement the smallest coherent correction, or evidence-close unchanged behavior;
9. run focused + independent/metamorphic + adjacent tests and real artifact validation;
10. update scorecard/matrix/finding registry/rolling plan with exact evidence;
11. commit/push a coherent checkpoint, re-audit, and continue.

If fresh evidence changes priority, rewrite the active plan. Do not preserve an old ordering because it was written earlier.

A newly discovered higher-value material issue immediately takes priority.

## Evidence saturation / diminishing returns

Independent validation is a means to protect score and semantics, not the product goal itself.

Treat a surface as **evidence-saturated** when all of the following are true:

- the authoritative contract for the surface is documented or the bounded interpretation is explicit and reversible;
- representative independent/metamorphic coverage exists for the meaningful failure classes, not only implementation replay;
- a recent blind audit and real finalization/artifact path found no material P0/P1 on that surface;
- the scorecard already marks the area STRONG/PROTECTED or equivalent.

Once saturated, do **not** keep enumerating near-duplicate malformed-input permutations or add another semantic-oracle guard merely because one can be invented. Reopen the surface immediately if a new concrete counterexample, authoritative clarification or materially different hidden-test class appears.

Absent such evidence, prefer the highest-value PARTIAL scorecard area. In the current program this usually means strengthening genuine multi-goal conflict semantics, causal explainability and judge-visible proof of the implemented routing strategies before adding more guards to already strong release/report boundaries.

A useful test is: “Will this next change materially improve expected rubric score, catch a distinct high-severity failure class, or make the product story more defensible?” If not, move on.

## Current code-first audit seeds

These are hypotheses for autonomous verification, not instructions to patch blindly. Absent a fresh material P0/P1, bias discovery toward scorecard rows that remain PARTIAL rather than further hardening a saturated STRONG/PROTECTED boundary.

Current high-value seams:

- resolver score ties use provider id only; a Router-level regression proves that disabled priority cannot change an exact tie; continue attacking adjacent score invariants;
- Router normalization uses fixed exact semantic domains for built-in preference factors and a separate fixed portfolio-loss domain for count/volume; dominated/non-dominated candidate perturbations and zero-weight priority leakage are covered end-to-end, while broader business-objective semantics remain an audit surface;
- Router passes the live hard-eligible set as an explicit opportunity pool; broader non-dominated opportunity/objective effects remain under audit;
- failed selected attempts keep rejection/expiry as their minimal public reason, while rich explanations expose the original selection rationale separately; continue auditing judge-facing semantics;
- count/volume factor ordering uses an independent exact post-decision portfolio L1 objective with exact shared dimensional scaling; continue auditing target provenance and non-dominated opportunity effects;
- absent optional capacity dimensions are neutral/no-headroom load evidence rather than silently renormalized maximum headroom or a zero denominator, matching the explicit neutral-RPM contract;
- optional intensity inputs are neutral when absent; an explicit zero RPM limit remains typed no-headroom evidence and hard admission remains separate;
- organizer base distribution under fallback is final-selected, while primary assignment, attempts and approved settlement remain separate named populations;
- primary and fallback use the same configured weighted resolver: count/volume remain active against the uncommitted final ledger, so a rejected primary is not a final assignment and is not counted twice;
- the judge-visible evidence surface covers all typed factors, Router-level objective conflicts and zero-weight independence across factor keys, while canonical-profile provenance and broader hidden-like evidence remain audit surfaces;
- finite-workload volume granularity is report-only evidence: a minimum-operation lower bound plus a bounded exact subset-sum probe for small, causally clean workloads; neither becomes a second allocation rule;
- direct typed configurations cannot assign positive target mass to a non-terminal provider unless it is literal `active`; `traffic_percentage` is a soft target signal, while explicit `terminal_provider_id` alone defines terminal role and provider-derived profiles keep terminal target mass at zero.

A newly discovered higher-value P0/P1 outranks all of these.

## Judge evidence path

The deterministic judge-facing factor and lifecycle evidence is generated by the canonical Case engine:

`ruby -Ilib bin/ruby_routing_case_evidence`

For the shortest judge-facing multi-goal proof — one payout, identical inputs, two weight sets and exact factor contributions:

`bundle exec ruby -Ilib bin/judge_demo`

The evidence surface exposes all typed factors, exact traces, count/volume and multi-goal conflicts, deterministic controlled pairwise changed-operation deltas with paired left/right weights and resolver traces for canonical weight scenarios, rejection/expiry-to-terminal fallback, the canonical ordered hard-gate/resolver/fallback/terminal causal chain with independently checked resolver winner/reason semantics, per-pass fallback selection traces, final outcomes, explicit primary/final/settlement populations, report analytics, typed recommendation evidence and the canonical submission policy's identity/source/revision/target provenance/weights, with explicit scope labels for synthetic factor cases versus canonical-profile fallback evidence.

It is a runnable evidence surface, not a second routing implementation.

The official-queue case demo compares two fresh canonical runs on the same workload with separate count and volume target maps, then shows the deterministic conversion/fallback report:

`ruby -Ilib bin/ruby_routing_case_demo`

## Submission rehearsal and release procedure

Submission finalization is always explicit about its input queue. The public fixture is a deterministic smoke run only:

`bundle exec rake finalize_public_submission`

For the actual submission queue, the one-command release path is deliberately bound to the supplied `operations_queue_test.json` and verifies the exact committed `HEAD` bytes:

`bundle exec rake finalize_submission`

Equivalent direct command:

`bundle exec ruby -Ilib bin/finalize_submission --queue operations_queue_test.json --verify-committed`

The task also accepts an explicit `SUBMISSION_QUEUE` path when the supplied file is staged elsewhere, but it never falls back to the public `operations_queue_10.json`.

The finalizer writes only the required repository-root files:

- `routing_decisions_test.json`
- `routing_report_test.json`

It then runs strict serialized, organizer contract and independent semantic validation. The public queue is only an explicit smoke path.

After validated root files are committed, rerun with `--verify-committed` to prove the validated bytes equal the exact `HEAD` bytes that will be pushed:

`bundle exec ruby -Ilib bin/finalize_submission --queue operations_queue_test.json --verify-committed`

The command prints the absolute queue path, SHA-256, operation count, first/last operation IDs and artifact digests. A hidden/actual queue must never be inferred from the public fixture or from the fixed artifact filenames.

### Important release sequencing note

`rake finalize_submission` invokes the finalizer with `--verify-committed`. When processing a newly supplied queue for the first time, generate and validate the artifacts before the commit with the direct command without `--verify-committed`, inspect them, commit the exact root files, then rerun the direct command with `--verify-committed` against the committed bytes. Do not confuse first-generation failure of committed-byte verification with a routing failure.

## Protected boundaries

Keep one Case path and one routing-choice authority. Hard constraints remain absolute; exact arithmetic/determinism remain mandatory; Case expiry never weakens production `UNKNOWN != failure`, economic-owner safety, idempotency or durable recovery.

The following production invariants remain protected unless direct evidence creates a real blocker:

- economic ownership safety;
- production UNKNOWN semantics;
- idempotency;
- durable replay/recovery;
- provider I/O separation from the deterministic kernel.

## Non-goals

No Rails/DB/Redis/queues/microservices, real PSP, ML/bandits/neural networks, generic DSL, distributed exactly-once or broad production refactor unless direct TZ evidence or a reproduced material blocker justifies it.

## Completion discipline

Green tests, all planned tasks done, backlog exhaustion, test count or a high estimated score are not completion.

Known scope green gives `VERSION_CANDIDATE` only. Then perform a blind code/data/artifact audit that ignores backlog/status claims, build rubric-by-rubric deterministic evidence and run a clean final submission rehearsal.

Any material P0/P1 or meaningful high-value rubric gap returns ACTIVE.

`VERSION_COMPLETE` is allowed only after:

- an autonomous blind code/data/artifact audit;
- rubric-by-rubric deterministic evidence;
- a clean final submission rehearsal;
- clean release provenance;
- exact pushed-head CI after final changes.

No backlog exhaustion, test count or estimated score means done. A newly discovered material P0/P1 immediately reopens ACTIVE.

Continue autonomously while the next useful step is derivable. Do not ask “continue?” after a green slice.
