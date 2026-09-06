# Testing Strategy

This document defines how RubyRouting proves correctness. It is intentionally stricter than a normal hackathon test plan because payout routing combines money-moving side effects, online allocation, retries/fallback, delayed outcomes, and concurrency.

The governing behavior remains `specifications/001-smart-payout-routing.md`. Tests verify the specification; tests must not silently invent product semantics that the specification leaves provisional.

## 1. Testing objective

The goal is not maximum line coverage. The goal is evidence that the implementation preserves the important properties under normal, boundary, adversarial, concurrent, delayed, duplicated, and reordered execution.

The test system must prove, as applicable:

1. **Economic safety** — one payout intent cannot accidentally produce two independent money-moving effects.
2. **Allocation correctness** — count/volume policies behave according to the configured measure, scope, accounting point, window, constraints, and in-flight commitments.
3. **Recovery correctness** — retry, fallback, resolve, defer, and reconciliation obey normalized outcome semantics.
4. **Concurrency correctness** — ownership and allocation commitments remain valid under races/interleavings.
5. **Provider-boundary correctness** — provider-specific responses normalize into stable domain semantics.
6. **History/analytics correctness** — opportunity, assignment, attempt, outcome, attribution, and settlement remain distinguishable and consistently projected.
7. **Robustness** — duplicates, delayed/out-of-order events, malformed/partial provider behavior, and provider degradation do not corrupt financial state.
8. **Performance fitness** — once the TZ provides limits, the implementation meets them without weakening correctness.

No single test style is sufficient. RubyRouting uses complementary deterministic scenarios, invariant/property tests, model/state-machine tests, controlled concurrency tests, provider contract tests, and fault injection.

## 2. Ruby-only test policy

Product implementation, routing algorithms, reference/oracle models, simulators, property generators, concurrency harnesses, and executable test logic MUST be written in Ruby.

Declarative CI configuration or minimal shell commands may orchestrate tests, but must not contain a second implementation of routing/business logic. Do not build a Python/JavaScript/Go reference router and compare Ruby against it; that creates a second language/runtime dependency and violates the project constraint.

Until the judge runtime is known, keep test code portable across the practical Ruby versions supported by the project and avoid relying on unnecessary Ruby-4-only behavior.

## 3. Test architecture

### 3.1 System under test

The production implementation is the SUT. Tests should exercise public/domain boundaries rather than private methods whenever the observable behavior can be tested directly.

### 3.2 Independent reference model

Maintain a small, pure Ruby reference model for semantics that benefit from an oracle, especially:

- economic ownership state;
- normalized recovery actions;
- policy accounting;
- post-decision discrepancy for count/volume allocation;
- simple derived ledger projections.

The reference model MUST be structurally independent of production code. It may share immutable domain constants/value definitions when unavoidable, but it must not call the production allocator/recovery engine or reuse the same helper that implements the rule being verified.

For small candidate sets, prefer a deliberately simple/brute-force oracle over a clever second algorithm. Example: enumerate every feasible provider for one routing step and calculate the resulting discrepancy independently; assert that the production decision is one of the optimal permitted actions.

### 3.3 Deterministic provider simulator

Build a Ruby provider simulator/fake capable of scripted outcomes. The simulator should eventually support at least:

- immediate success;
- immediate safe/confirmed route failure;
- terminal payout/recipient failure;
- timeout before any possible acceptance, when the provider contract can prove that semantic;
- timeout/lost response after possible acceptance -> `UNKNOWN`;
- accepted `PENDING` followed by success;
- accepted `PENDING` followed by failure;
- long/never-resolved pending;
- delayed success after an initiating error/timeout;
- success followed by return/reversal when that lifecycle is enabled;
- duplicate callbacks;
- callbacks delivered out of order;
- delayed callbacks;
- malformed/unknown provider status/error;
- temporary provider unavailable/rate-limited/capacity constrained;
- safe same-provider idempotent retry returning the original operation;
- status lookup that resolves an unknown operation.

The simulator must be deterministic by default. Time, random choices, IDs, and callback ordering must be controllable from the test.

### 3.4 Virtual time

Core tests MUST NOT depend on real `sleep` calls. Time-sensitive behavior should use an explicit/injectable clock or simulator time where implementation design requires time.

This is necessary for reproducible tests of:

- retry/backoff windows;
- provider timeout and pending age;
- policy windows;
- idempotency TTL;
- health windows;
- recovery/probing timing.

Do not introduce a clock abstraction everywhere prematurely; place it only at boundaries that genuinely depend on time.

### 3.5 Reproducible randomness

Deterministic allocation should not require randomness. If later exploration/random tie-breaking is implemented:

- random source/seed must be controllable;
- failing seeds must be printed/preserved;
- a discovered failing seed becomes a deterministic regression test;
- correctness invariants must hold for every seed, not only statistically on average.

## 4. Verification layers

### Layer A — value/object/unit tests

Use focused tests for exact money, policy validation, outcome normalization, attribution, discrepancy calculations, state predicates, and other locally deterministic logic.

These tests should be small and fast, but they are not sufficient proof of orchestration correctness.

### Layer B — executable acceptance scenarios

Every implemented SPEC-001 acceptance scenario must have at least one deterministic executable test. Test names or metadata must make the relevant requirement/AC traceable.

Important safety requirements need both positive and negative tests: prove the permitted action and prove that a dangerous action is rejected.

### Layer C — property/invariant tests

Generate many valid inputs and assert properties that must always hold. This is especially important because allocation amounts, eligibility subsets, provider ordering, and event sequences form a combinatorial space too large for manual examples.

Property failures must shrink or be reduced to a small reproducible counterexample when tooling permits.

### Layer D — state-machine/model-based tests

Generate sequences of commands against both the reference model and the implementation. Useful commands include:

- create/submit payout intent;
- request primary routing decision;
- commit assignment/economic ownership;
- provider immediate success;
- provider safe failure;
- provider terminal payout failure;
- provider pending;
- provider unknown timeout;
- status resolution;
- same-provider idempotent retry;
- cross-provider reroute after safe release;
- duplicate provider observation;
- delayed/out-of-order observation;
- reconciliation observation;
- provider enable/disable/capacity change;
- policy epoch change.

Generated sequences must respect preconditions, then compare expected state/action/ledger invariants after every step. The point is to test long histories and unusual transitions, not only isolated calls.

### Layer E — concurrency/interleaving tests

Concurrency-sensitive invariants need deliberately coordinated races rather than hoping a race appears under load.

Use barriers/latches/controlled synchronization so tests can force relevant interleavings. The implementation technique can evolve, but the test must be capable of proving the observable invariant.

Critical races:

- two workers try to acquire economic ownership for the same payout;
- duplicate payout submissions arrive concurrently;
- two routing workers see the same allocation deficit;
- assignment commitment races with another routing decision;
- safe failure/release races with a second fallback worker;
- `UNKNOWN` observation races with fallback decision;
- callback/reconciliation race;
- provider disable/capacity exhaustion races with decision commit;
- policy epoch update races with a routing decision.

Where the chosen persistence/concurrency model requires a linearizable operation (for example single economic ownership), tests should verify that concurrent histories are equivalent to a legal sequential history for that invariant rather than merely asserting "no exception".

### Layer F — provider contract/integration tests

For every provider/simulator adapter, verify the mapping from raw provider behavior to normalized domain behavior independently of the routing algorithm.

Contract tests should cover:

- idempotency/reference semantics;
- terminal versus non-terminal states;
- timeout ambiguity;
- status lookup;
- error attribution;
- duplicate/out-of-order callback behavior;
- safe retry conditions;
- unknown/unrecognized status handling.

A new provider must not be considered integrated until this suite passes.

### Layer G — end-to-end fault scenarios

Exercise the whole orchestration path with a deterministic simulator: create intent -> route -> attempt -> provider result -> recovery/reconciliation -> final analytics.

Fault tests should combine failures, not only test one fault at a time. Examples:

- A timeout/unknown while B is healthy;
- A safe-fails, B becomes unavailable before fallback, C succeeds;
- A safe-fails while policy is temporarily infeasible;
- duplicate callback arrives after fallback completion;
- pending A resolves success after repeated status checks;
- provider recovers while carrying historical allocation deviation;
- large payout arrives during partial provider outage;
- many concurrent payouts while one provider crosses a capacity boundary.

### Layer H — stress/performance/soak

Before the TZ, record baselines without turning guessed numbers into requirements. After the TZ, add explicit gates for judged constraints.

Measure at least when relevant:

- routing decisions/sec;
- latency distribution for pure decision logic;
- memory growth over long histories;
- allocation discrepancy under long streams;
- attempts per payout during degraded conditions;
- behavior under high concurrency;
- recovery from provider outage without retry amplification/stampede.

Performance tests must fail for correctness violations even if throughput is excellent.

### Layer I — mutation testing / fault seeding (optional but valuable)

When the test suite becomes mature, deliberately mutate or fault-seed critical rules to audit whether tests detect them. High-value injected defects include:

- release ownership on `UNKNOWN`;
- count only completed assignments instead of in-flight commitments;
- treat recipient failure as provider failure;
- use request count in volume mode;
- ignore provider eligibility in allocation denominator;
- allow duplicate callback to double-count settlement;
- reuse stale fallback list;
- use floating-point money.

Do not chase a universal mutation-score target during the hackathon. Use mutation/fault seeding to prove that safety-critical tests are capable of failing for the intended reason.

## 5. Core invariant catalog

The following properties should become reusable assertions/reference-model invariants.

### SAFETY-P1 — single unresolved owner

For every payout history:

`active_unresolved_economic_owners <= 1`

### SAFETY-P2 — unknown retains ownership

After an attempt becomes `UNKNOWN`, no independent cross-provider money-moving attempt may be committed until the prior operation is resolved/released under the provider contract.

### SAFETY-P3 — duplicate intent/effect

Replaying the same economic intent does not create an additional logical payout/economic ownership.

### SAFETY-P4 — duplicate observations are idempotent

Reprocessing the same provider observation cannot double-count an attempt, settlement, provider-quality signal, or state transition.

### SAFETY-P5 — history is not erased

Later facts may refine derived state but cannot delete/rewrite the historical decision/attempt/observation facts needed to explain the lifecycle.

### ALLOC-P1 — selected provider is feasible

Every committed assignment is a member of the feasible provider set at its decision/commit point.

### ALLOC-P2 — local post-decision optimality

For the configured deterministic allocation rule, the selected provider's resulting required discrepancy is no worse than any other feasible provider under the same state, except where an explicit higher-priority constraint/reliability rule permits a tie/band choice.

### ALLOC-P3 — committed work is visible

Allocation state includes already committed/in-flight assignments according to the policy accounting semantics; concurrent decisions cannot all act on a stale identical deficit.

### ALLOC-P4 — opportunity correctness

A provider that is not an opportunity under the policy/context does not accrue ordinary router-choice debt merely because it was absent from a payout it could never receive.

### ALLOC-P5 — exact money

For volume allocation, all equality/ordering/discrepancy decisions use exact monetary representation. No binary floating-point rounding may change routing behavior.

### ALLOC-P6 — accounting conservation

For any chosen policy view, the sum of provider accounting contributions plus explicitly unattributed/unassigned contributions equals the total measure that the policy defines as accountable. No payout is silently double-counted.

### REC-P1 — terminal payout failure stops provider hopping

A failure classified as recipient/payout-terminal cannot trigger a cross-provider attempt solely because another provider exists.

### REC-P2 — safe failure may release and reroute

A confirmed safe route/provider failure may release ownership and permits a new decision from fresh current candidates.

### REC-P3 — fallback is fresh

A fallback decision uses current eligibility/availability/capacity/recovery context rather than blindly consuming a stale precomputed list.

### REC-P4 — bounded recovery

No payout creates an unbounded number of provider attempts. Once the configured budget/deadline semantics are reached, the result is defer/terminal/unresolved according to policy.

### ATTR-P1 — business outcome and health signal are distinct

Recipient-caused terminal failure may fail the payout while producing a neutral provider-quality signal.

### LEDGER-P1 — lifecycle linkage

Every assignment belongs to a payout/policy epoch; every attempt belongs to a decision; every provider observation belongs to a known or explicitly unresolved provider operation; settlement/reversal facts link to the corresponding economic intent without overwriting earlier facts.

### ANALYTICS-P1 — replay stability

Rebuilding projections from the same ordered fact set yields the same analytics/derived state.

## 6. Metamorphic properties

Metamorphic tests help verify behavior even when a full expected output is difficult to enumerate.

Use only when their preconditions are satisfied.

1. **Provider renaming:** consistently renaming provider IDs in policy/state/input should produce the correspondingly renamed decision, not a different economic result.
2. **Add irrelevant ineligible provider:** adding a provider that is definitely ineligible must not change the selected feasible action.
3. **Equal-amount equivalence:** when all payout amounts are equal and count/volume policies have equivalent semantics, count and volume allocation should produce equivalent proportional behavior.
4. **Volume scaling:** multiplying every amount and volume threshold/initial accounting state by the same positive factor should not change provider ordering when there are no amount-dependent eligibility/cost rules.
5. **Duplicate observation:** adding an exact duplicate provider event should not change derived state/analytics after the first application.
6. **Replay:** applying the same immutable fact history to a fresh projection should reproduce the same derived state.

Metamorphic properties must state their preconditions explicitly; do not encode false invariants for policies where amount, time, health, or provider priority legitimately changes the decision.

## 7. Scenario-space matrix

Manual scenario coverage should systematically vary these axes. Not every Cartesian combination must be handwritten; property/model tests cover the large product space. Known dangerous combinations MUST have explicit regression scenarios.

| Axis | Values to cover |
|---|---|
| Provider count | 0, 1, 2, 3+, many |
| Allocation measure | count, volume |
| Target shape | equal, skewed, tiny share, dominant share, min/max if supported |
| Amount | minimum valid, ordinary, boundary, very large/indivisible |
| Eligibility | all eligible, subset, one, none |
| Availability | healthy, degraded if implemented, unavailable, capacity-limited |
| Primary outcome | success, safe failure, terminal payout failure, pending, unknown |
| Delayed outcome | pending->success, pending->failure, unknown->success, reversal if enabled |
| Event delivery | once/in order, duplicate, delayed, out of order |
| Recovery position | primary, second attempt, later attempt/budget edge |
| Policy state | feasible, statically invalid, runtime-infeasible, epoch change |
| Allocation history | balanced, provider under target, over target, outage-created deviation |
| Concurrency | single, two-way race, high fan-out |
| Provider contract | idempotent retry supported/not supported/TTL boundary if modeled |
| Currency/context | one scope, segmented eligibility; multi-currency only after explicit semantics |

At minimum, explicit tests must cover pairwise interactions across these axes plus targeted higher-order combinations for known hazards such as `UNKNOWN + concurrency + fallback`, `large volume + outage + committed allocations`, and `duplicate/out-of-order callback + reconciliation + prior fallback`.

## 8. Concrete adversarial scenario catalog

The suite should grow toward the following catalog. IDs are test-plan IDs, not new product requirements.

### Economic intent / ownership

- `T-SAF-001` duplicate sequential submission -> one economic intent.
- `T-SAF-002` duplicate concurrent submission -> one economic intent/owner.
- `T-SAF-003` two workers route same payout -> at most one ownership commit.
- `T-SAF-004` A returns `UNKNOWN`; B must not start.
- `T-SAF-005` A `UNKNOWN` later resolves success; no B attempt ever exists.
- `T-SAF-006` A `UNKNOWN` later resolves confirmed failure; ownership releases, fresh reroute allowed.
- `T-SAF-007` same-provider idempotent retry returns original provider operation.
- `T-SAF-008` idempotent retry unsupported/expired -> do not pretend retry is safe.
- `T-SAF-009` no admissible provider -> safe no-route/defer.

### Allocation

- `T-ALL-001` 50/50 count stream stays at minimal achievable prefix discrepancy.
- `T-ALL-002` skewed count targets (for example 70/20/10).
- `T-ALL-003` volume uses amount, not payout count.
- `T-ALL-004` one huge indivisible payout chooses the least-bad feasible next state.
- `T-ALL-005` zero providers / one provider edge.
- `T-ALL-006` ineligible provider does not create artificial opportunity/debt.
- `T-ALL-007` provider at capacity is excluded before allocation ranking.
- `T-ALL-008` many concurrent assignments do not stampede an under-target provider.
- `T-ALL-009` assignment ledger and settlement ledger diverge correctly after fallback.
- `T-ALL-010` static contradictory constraints are rejected if/when such constraints exist.
- `T-ALL-011` runtime outage makes policy infeasible without violating safety.
- `T-ALL-012` policy epoch change does not reinterpret old history.
- `T-ALL-013` recovered provider does not receive unbounded catch-up solely from old outage deviation.
- `T-ALL-014` exact-money boundary values cannot change route due to float rounding.

### Outcome/attribution

- `T-OUT-001` recipient invalid -> payout terminal; provider health neutral.
- `T-OUT-002` provider transport failure -> provider operational signal negative; safe-failure behavior per contract.
- `T-OUT-003` downstream bank failure -> correct attribution and recovery action.
- `T-OUT-004` unknown raw provider code -> safe conservative normalization, never fabricated success.
- `T-OUT-005` same event twice -> no double health/settlement count.

### Recovery

- `T-REC-001` A safe-fails, B succeeds.
- `T-REC-002` A safe-fails; B becomes unavailable before fallback; fresh decision chooses C/no-route.
- `T-REC-003` terminal payout failure -> no fallback.
- `T-REC-004` pending -> no premature fallback.
- `T-REC-005` attempt budget exhausted -> stop/defer according to policy.
- `T-REC-006` same-provider retry vs cross-provider fallback remain distinguishable in history.
- `T-REC-007` stale candidate list cannot force an invalid fallback.

### Event/reconciliation

- `T-EVT-001` duplicate callback is idempotent.
- `T-EVT-002` out-of-order callbacks derive a valid final state.
- `T-EVT-003` live callback races with reconciliation observation.
- `T-EVT-004` success later reversed/returned when lifecycle supports it; history preserved.
- `T-EVT-005` long pending ages correctly under virtual time.
- `T-EVT-006` reconciliation resolves unknown without creating a new independent attempt.

### Analytics/trace

- `T-AN-001` every decision records policy epoch and chosen role (primary/recovery).
- `T-AN-002` excluded candidates retain material reason when explainability is implemented.
- `T-AN-003` primary share and settlement share are separately correct after recovery.
- `T-AN-004` deviation attribution distinguishes ineligibility/outage/capacity/router choice where implemented.
- `T-AN-005` replaying immutable facts recreates the same projection.
- `T-AN-006` first-attempt and eventual-success metrics differ correctly on recovered payouts.

### Concurrency

- `T-CON-001` ownership acquire/acquire race.
- `T-CON-002` ownership release/fallback race.
- `T-CON-003` allocation reservation/reservation race.
- `T-CON-004` provider disable/decision-commit race.
- `T-CON-005` policy-epoch-change/decision race produces a decision attributable to one coherent epoch.
- `T-CON-006` duplicate callback/reconciliation race produces one logical fact effect.

## 9. Oracle and assertion rules

A test oracle must assert domain results, not implementation trivia.

Good assertions:

- chosen action/provider and rationale category;
- ownership state;
- normalized outcome;
- allocation counters/measure and discrepancy;
- durable fact count/identity;
- no additional provider attempt;
- derived settlement/analytics values.

Avoid assertions tied to private class names, arbitrary method-call ordering, JSON field order, or storage layout unless those are actual contracts.

For allocation, whenever practical calculate expected values independently in the test/reference model. Avoid writing `expected = production_helper(...)`.

## 10. Failure diagnostics

A failed high-level test must make the trace understandable. Capture a compact timeline:

- payout/economic-intent ID;
- policy epoch and relevant allocation state;
- opportunity/feasible provider set;
- routing decisions;
- ownership transitions;
- provider scripted observations;
- normalized outcomes/attribution;
- final ledger/projection state;
- random seed and virtual timestamps when applicable.

Do not dump huge logs by default. The failure should contain the minimal evidence required to reproduce and reason about the bug.

## 11. Regression discipline

Every material bug found during development/demo/chaos/property testing must produce a regression test before or with the fix.

For randomized/model tests:

1. preserve the failing seed/command sequence;
2. shrink/reduce to a minimal deterministic sequence when possible;
3. add that sequence as a named regression if it represents a meaningful class of defect;
4. keep the broader randomized property test as well.

Do not "fix" flaky tests by automatic retries. A flaky test is a defect in test determinism or in the product and must be diagnosed.

## 12. Quality gates

### Per small change

- focused tests for the changed behavior pass;
- relevant invariant/property tests pass;
- no known regression is ignored/skipped without an explicit reason.

### Per substantial Goal/ExecPlan milestone

- all mapped acceptance tests pass;
- full deterministic suite passes;
- relevant property/model tests pass with recorded/reproducible seed policy;
- concurrency/fault scenarios relevant to the change pass;
- lint/static/build checks that exist pass;
- final diff is reviewed against `AGENTS.md`, SPEC-001, architecture, and this testing strategy.

### Before demo/submission

- complete requirement-to-test traceability for the implemented judged scope;
- all safety invariants have direct negative/positive regression coverage;
- full end-to-end fault suite passes repeatedly without flaky reruns;
- high-concurrency/stress suite passes at expected limits;
- performance baseline/gates pass once TZ limits exist;
- fresh-environment execution succeeds from documented commands;
- no hidden dependency on network time/random state/external services for deterministic core tests;
- known limitations/provisional assumptions are explicit.

Code coverage percentage is diagnostic only. A high line percentage does not substitute for invariant/state/concurrency coverage.

## 13. Requirement traceability

Every implemented normative requirement/acceptance scenario should be traceable to executable evidence. Use the least noisy mechanism supported by the test framework/repository, for example test names containing `AC-007` or a small Ruby mapping/manifest.

Do not scatter requirement IDs through production code merely for traceability.

A requirement is not `DONE` in an ExecPlan until its intended verification layer exists and has passed.

## 14. Pre-TZ testing work that starts now

Do not wait for the full TZ to build the verification foundation. Safe pre-TZ work includes:

1. Ruby test project/harness with one documented full-suite command.
2. Pure Ruby reference model for current stable invariants.
3. Deterministic provider simulator/fault scripting.
4. Executable versions of SPEC-001 safety/allocation/recovery acceptance scenarios that are not dependent on unknown external API details.
5. Property generators for payout amounts, policies, provider opportunities, and outcome sequences.
6. Controlled concurrency test utilities for ownership/allocation races.
7. Projection/trace helpers that make failures diagnosable.
8. Baseline performance measurements without declaring guessed limits as requirements.

When the full TZ arrives, reconcile semantics first, then adjust the oracle/tests before changing production behavior that depends on a changed requirement.

## 15. Research basis

The methodology is informed by:

- Juspay payout UAT cases, which explicitly simulate pending states, same-reference retries, random gateway timeouts, delayed failure, reversal, and status re-checks: https://www.juspay.io/in/docs/payout/docs/resources/sample-uat-test-cases
- Stripe webhook guidance on duplicate delivery: https://docs.stripe.com/webhooks
- John Hughes, *Software Testing with QuickCheck* — property-based and state-machine testing of stateful systems: https://research.chalmers.se/en/publication/154999
- Herlihy & Wing, *Linearizability: A Correctness Condition for Concurrent Objects* — reasoning about concurrent histories as legal sequential behavior: https://www.cs.columbia.edu/~wing/publications/HerlihyWing90.pdf

These references motivate test technique. SPEC-001 and the official TZ remain the authority for project behavior.
