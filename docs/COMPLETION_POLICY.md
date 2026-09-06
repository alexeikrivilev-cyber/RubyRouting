# Completion Policy — no premature "done"

This document is a normative operating contract for coding agents working on RubyRouting. It exists because a green implementation checkpoint was previously described as the end of useful pre-TZ work before a second technical review found important locally solvable gaps.

## 1. Core rule

Completion is an **evidence claim**, not an agent feeling and not a consequence of finishing a checklist.

The words `complete`, `done`, `finished`, `all implemented`, `nothing left`, `wait for TZ`, or equivalent may be used for the active Version Goal only after the **Version Closure Protocol** below passes.

A file, class, test, commit, slice, milestone, phase, benchmark or green suite proves only that local scope. It never proves the whole version by itself.

## 2. Allowed status vocabulary

Use precise status language:

- `SLICE_IMPLEMENTED` — code for a slice exists, verification may still be incomplete.
- `SLICE_VERIFIED` — slice acceptance and relevant broader checks pass.
- `PHASE_VERIFIED` — every required phase outcome is implemented and cross-checked.
- `VERSION_CANDIDATE` — planned phases appear complete; closure audit has started.
- `VERSION_COMPLETE` — closure protocol passed with evidence.
- `EXTERNALLY_BLOCKED` — every remaining required path depends on an external dependency and the blocker test passed.

Do not jump from `SLICE_VERIFIED` or `PHASE_VERIFIED` to `VERSION_COMPLETE`.

## 3. Green tests are necessary but not sufficient

A green test suite demonstrates only behavior represented by that suite. It does not prove:

- that the specification is complete;
- that all important interactions are represented;
- that no hidden state bypasses replay;
- that documentation matches implementation;
- that no locally solvable generic mechanism is missing;
- that the current architecture has no correctness gap outside existing tests.

Test counts, assertion counts, line coverage and benchmark throughput are evidence, not a definition of completeness.

## 4. Mandatory Version Closure Protocol

Before declaring a version complete, enter `VERSION_CANDIDATE` and perform all passes below from current repository state.

### Pass A — source/spec reconciliation

Read the current code and compare it against every governing specification and durable decision, not only acceptance tests.

For v0.2 this means at least SPEC-001, SPEC-002 and SPEC-003.

For every normative requirement classify it:

- implemented and evidenced;
- intentionally not applicable with a governing reason;
- externally blocked;
- missing.

Any missing locally actionable requirement reopens implementation.

### Pass B — capability matrix sweep

Inspect the complete current-version capability matrix, including interactions:

- economic intent / ownership;
- dispatch / transport ambiguity;
- provider-operation contract and idempotency;
- allocation by count and volume;
- policy identity, constraints, feasibility and deviation;
- functional eligibility / opportunity;
- live availability;
- capacity reservations;
- provider health / quarantine / probing;
- deterministic ranking;
- retry / resolve / fallback / defer / reconciliation;
- time, budgets, deadlines and TTL;
- duplicate / delayed / out-of-order observations;
- settlement / return / reversal / economic conflict;
- facts / lifecycle replay;
- decision trace / analytics;
- concurrency and stale-decision behavior.

A capability is not complete if only its isolated happy path works while a required interaction is still unmodeled.

### Pass C — repository discovery sweep

Search the repository for evidence of unfinished behavior:

- TODO/FIXME/XXX and temporary comments;
- `NotImplementedError` and placeholder branches in reachable current-version paths;
- public/domain methods with no meaningful tests;
- duplicated recovery/allocation semantics that can drift;
- human-readable strings parsed as machine semantics;
- hidden mutable state not represented in facts/replay;
- stale active-plan or backlog references;
- assumptions that were accidentally hardened into code.

Not every TODO is a blocker, but every discovered item must be classified before closure.

### Pass D — adversarial/red-team review

Assume the implementation is incomplete and deliberately try to break it.

Construct counterexamples around:

- skewed allocation plus fallback;
- large indivisible volume;
- provider outage/recovery and capacity pressure;
- duplicate submit during dispatch;
- UNKNOWN plus concurrent fallback attempts;
- provider disablement while an old operation is unresolved;
- late old-provider success after newer settlement;
- policy update during concurrent decisions;
- health quarantine versus allocation pressure;
- callback/reconciliation races;
- replay after complex multi-provider histories.

A newly found material defect becomes a regression and returns the version to active implementation.

### Pass E — verification gate

Run the canonical full suite plus the relevant focused suites from current code. For v0.2 normally:

- `bundle check`
- `bundle exec rake test`
- `bundle exec rake property`
- `bundle exec rake model`
- `bundle exec rake concurrency`
- `bundle exec rake fault`
- benchmark/static/loadability checks required by the active plan
- CI evidence when CI exists.

Never reuse an old run as proof for changed code. Never claim an unavailable check passed.

### Pass F — backlog and blocker audit

Review every `NOW`, P0 and P1 item and every unresolved discovery in the active ExecPlan.

For anything remaining, classify it as:

- required and locally actionable -> continue development;
- genuinely external-TZ dependent -> blocker/next-version input;
- optional optimization with no correctness/completeness gap -> later.

The absence of the official TZ is not itself a blocker while generic routing logic can still be improved without inventing the external contract.

### Pass G — documentation consistency

Verify that README, AGENTS, ROADMAP, active ExecPlan, specifications, completion/session/workflow rules, backlog, decisions, architecture guidance and testing guidance all describe the same current version and stop conditions.

A stale document that can direct a fresh agent incorrectly is a version-closure defect.

## 5. No scope shrinking at closure

An agent may not make completion easier by silently redefining the active version to match what is already implemented.

The current Version Goal and mandatory capability scope are defined by `docs/ROADMAP.md` and governing specifications. Narrowing them requires an explicit durable decision justified by authoritative TZ evidence or a deliberate user instruction.

Do not change `required` to `optional`, move an unfinished P0/P1 item to `LATER`, or rename a missing mechanism as "out of scope" merely to close the version.

## 6. Discovery can reopen a phase

Phases are dependency/organization aids, not sealed boxes.

If Phase K/closure discovers that Phase B, D, G or another earlier capability is incomplete, reopen that phase or create a new slice. There is no requirement to preserve a monotonic checklist.

Correct project state is more important than a neat progress table.

## 7. External blocker test

`EXTERNALLY_BLOCKED` is valid only if all are true:

1. the missing requirement is necessary for the current version;
2. it cannot be resolved from repository/runtime/research/ordinary engineering judgment;
3. proceeding would require inventing authoritative external semantics or unavailable access/service;
4. no independent required current-version work remains;
5. the exact blocker and affected exit criterion are recorded.

"We do not have the TZ yet" fails this test for generic policy, lifecycle, safety, capacity, health, replay, analytics and verification work already specified for v0.2.

## 8. Completion report requirements

A `VERSION_COMPLETE` report must include:

- exact commit/revision reviewed;
- version exit criteria result;
- specifications/requirements reconciled;
- full commands actually run and their results;
- important property/model seeds/traces;
- concurrency/fault evidence;
- closure/red-team findings and regressions created;
- remaining TZ-blocked items;
- remaining optional later work;
- documentation reconciliation result.

If this evidence is unavailable, report the narrower verified status instead of saying the project is complete.
