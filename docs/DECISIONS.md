# Decisions

This file records durable project decisions that future agents should not have to rediscover. Behavioral requirements remain authoritative in `specifications/`; this file preserves rationale and clearly marks provisional choices that must be revisited when the full case specification arrives.

## D-001 — specification-driven repository

Status: accepted.

Decision: `specifications/` is the behavioral source of truth. Semantic code changes trace to requirements; code/spec drift is a defect.

Rationale: the project will be developed heavily by coding agents across separate runs. Durable plain-language intent prevents local implementation patterns from silently becoming business requirements.

Consequences: `AGENTS.md` stays concise and points to structured repository knowledge; substantial implementation work uses living plans; official case changes update the spec before conflicting code.

## D-002 — deterministic financial kernel, adaptive optimizer outside it

Status: accepted.

Decision: economic safety, ownership, eligibility, policy accounting, outcome normalization, and hard constraints are deterministic. Adaptive/statistical logic may rank only already-safe feasible actions.

Rationale: payout correctness must not depend on an ML model, unstable score, or limited historical sample. This also provides a strong baseline that can be demonstrated even if the hackathon data is insufficient for learning algorithms.

Consequences: bandits/ML are optional later work, not foundation work.

## D-003 — effectively-once economic semantics

Status: accepted.

Decision: one payout intent represents one economic intention. The system does not promise literal distributed exactly-once execution; it must prevent retries/duplicates/failover from intentionally creating an additional payout effect.

Rationale: external money-moving operations can succeed while responses are lost. Provider-local idempotency alone does not coordinate two independent providers.

Consequences: explicit economic ownership, `UNKNOWN` handling, and safe release before cross-provider fallback are core requirements.

## D-004 — four logical accounting ledgers

Status: accepted.

Decision: opportunity, assignment, attempt, and settlement are distinct logical facts even if future persistence stores them in fewer physical tables/documents.

Rationale: fallback makes “provider” ambiguous. Correct allocation, reliability analysis, and explainability require knowing who could have been selected, who was selected, who was attempted, and who ultimately settled.

Consequences: no core model should collapse the lifecycle into one mutable `provider_id`.

## D-005 — deterministic discrepancy allocation before weighted randomness

Status: accepted as baseline algorithmic direction; exact official semantics pending.

Decision: count/volume proportional allocation should minimize feasible post-decision discrepancy and account for in-flight commitments. Weighted randomness may be used for tie-breaking/exploration but not as the sole correctness mechanism.

Rationale: random weighted routing converges only probabilistically and performs poorly for short windows or uneven payout amounts. In-flight commitments are necessary to avoid concurrent overshoot.

Consequences: allocation tests must prove local post-decision optimality/bounded discrepancy against an independent reference oracle for the confirmed policy semantics.

## D-006 — primary assignment is the provisional allocation accounting point

Status: provisional; MUST be revisited under B-001/B-002.

Decision: until the full case defines otherwise, business target shares are interpreted as primary routing assignments. Actual settlement distribution is measured separately.

Rationale: this cleanly separates business routing intent from recovery behavior and prevents a provider outage from retrospectively rewriting the router's original allocation decision.

Risk: the official task may define “volume through provider” as attempted, accepted, successful, or settled volume. If so, update the allocation-policy section of SPEC-001, the reference model/tests, and dependent implementation before treating the new semantic as authoritative.

## D-007 — fallback is re-routing, not a static cascade

Status: accepted.

Decision: after a safely resolved failure, the next provider is selected by a fresh routing decision using current eligibility, health, limits, capacity, and recovery context.

Rationale: a precomputed sequence becomes stale and cannot correctly react to the cause of failure or changing provider state.

Consequences: the decision trace must identify each fallback decision separately.

## D-008 — raw payout failure is not provider health failure

Status: accepted.

Decision: business payout outcome and reliability/health feedback are separate signals. Recipient/downstream failures do not automatically penalize the provider.

Rationale: otherwise the optimizer learns selection bias and routes away from providers that correctly reject invalid payouts.

Consequences: provider adapters normalize both outcome semantics and attribution.

## D-009 — Ruby is mandatory; executable logic is Ruby-only

Status: accepted.

Decision: all product implementation is Ruby. Routing algorithms, reference/oracle models, provider simulators, property/model/concurrency test harnesses, and other executable domain verification logic are also Ruby. Minimal declarative CI configuration and shell orchestration are permitted, but no second routing implementation may be written in another language.

Rationale: Ruby is a hard case constraint. Keeping both production and test/reference semantics in Ruby reduces runtime/tooling uncertainty and prevents a parallel implementation from becoming an accidental dependency.

Consequences: no Python/JS/Go/Java/Rust domain implementation. No framework, persistence engine, background-job system, queue, cache, deployment topology, or ML stack is selected before the official case or an implementation goal makes the need concrete.

## D-010 — Goal Mode is autonomous inside explicit invariants

Status: accepted.

Decision: coding agents should complete requested goals without routine confirmation, use reversible defaults for non-critical ambiguity, keep a lightweight backlog, and change approach instead of repeating failed actions. Escalation is reserved for irreducible financial/product ambiguity or external blockers.

Rationale: high agent throughput requires clear boundaries and feedback loops, not pervasive permission gates.

Consequences: `AGENTS.md`, `docs/WORKFLOW.md`, `docs/PLANS.md`, and `docs/SESSION_POLICY.md` encode anti-loop, scope, planning, continuation, and completion rules.

## D-011 — advanced adaptive routing stays optional until measured

Status: accepted.

Decision: multi-armed bandits, contextual models, correlated failure inference, and counterfactual policy evaluation are research-backed extension candidates, not mandatory core features.

Rationale: a hackathon solution gains more from demonstrable correctness and explainability than from an unvalidated ML layer. Advanced optimization is valuable only if the full case provides the traffic/data/criteria to measure an uplift.

Consequences: implement and benchmark a deterministic baseline first; promote advanced work only with concrete evidence.

## D-012 — development starts before the full TZ

Status: accepted.

Decision: the repository is no longer “pre-implementation until TZ”. Pre-TZ work begins immediately on stable, reversible foundations described in `docs/exec-plans/active/pre-tz-foundation.md`.

Rationale: waiting would waste the highest-value preparation period. Core economic ownership, deterministic allocation machinery, simulation, executable acceptance tests, state-machine/property tests, and concurrency harnesses can be built without guessing the final API/persistence/UI contract.

Consequences:

- build the deterministic Ruby kernel and test harness now;
- isolate provisional semantics such as allocation accounting point/window;
- do not freeze external architecture merely to make visible progress;
- when the TZ arrives, reconcile spec/reference tests first, then adapt dependent code.

## D-013 — verification uses independent models and multiple test modes

Status: accepted.

Decision: correctness evidence cannot rely only on handwritten happy paths or line coverage. RubyRouting uses complementary deterministic scenarios, independent reference/oracle checks, property/invariant tests, model/state-machine sequences, controlled concurrency/interleaving tests, provider contract tests, and fault-injected end-to-end scenarios as detailed in `docs/TESTING.md`.

Rationale: the state space is combinatorial and includes delayed/duplicate/reordered events and races. A finite scenario list alone cannot cover important interaction space.

Consequences:

- production helpers must not be reused as the sole oracle for the rule they implement;
- randomized failures must be reproducible by seed/trace;
- material bugs gain deterministic regression tests;
- flaky test retries are not an acceptable substitute for diagnosis.

## D-014 — deterministic testability is an architectural requirement

Status: accepted.

Decision: wall-clock time, randomness, provider I/O, and external mutable state must remain at explicit boundaries whenever they influence domain behavior. Core tests must be able to control these inputs without real sleeps/live money-moving services.

Rationale: timeout, pending, idempotency, allocation windows, reconciliation, and concurrency behavior cannot be tested deeply or reliably if hidden global time/random/network calls are embedded in the financial kernel.

Consequences: architecture must preserve deterministic simulation/replay seams, but should not introduce generic abstractions where no real time/random/I/O dependency exists.

## D-015 — long sessions are version-gated, not milestone-gated

Status: accepted.

Decision: a long-running Goal Mode session continues through verified slices, milestones, phases, and commits until the active Version Goal's exit criteria are satisfied or every remaining required path is genuinely blocked by an external dependency outside the agent's control.

Rationale: stopping after each milestone wastes autonomous agent capacity and forces unnecessary human coordination. At the same time, an explicit version exit gate prevents “work forever” behavior and gives the agent a concrete definition of done.

Consequences:

- `docs/ROADMAP.md` defines project/version sequencing and authoritative version exit criteria;
- the active ExecPlan maintains actual progress and only a small rolling set of next actions;
- finishing a phase is not a stop condition;
- if one path is blocked but independent version work remains, the agent switches paths and continues;
- a failing test, hard bug, reversible design ambiguity, or desire for confirmation is not an external blocker;
- `docs/SESSION_POLICY.md` defines the blocker/stop test.

## D-016 — Ruby 4.0.6 is the v0.1 development baseline

Status: accepted; runtime must be reconciled when the official TZ publishes judge constraints.

Decision: v0.1 development targets CRuby 4.0.6. All executable project/domain/test logic remains Ruby. The core avoids unnecessary master/4.1 or gratuitous 4.0-specific dependencies when a clear portable Ruby construct exists.

Rationale: Ruby 4.0.6 is the current stable Ruby release as of 2026-08-27, while the judge runtime is still unknown. A current baseline lets development use modern Ruby deliberately without creating accidental dependence on unreleased behavior.

Consequences:

- create/update `.ruby-version` to 4.0.6 during Phase 1;
- use `docs/RUBY.md` as the Ruby engineering source of truth;
- money is Integer minor units plus explicit currency;
- exact policy ratios use integer weights/Rational, never Float;
- Minitest + Rake is the v0.1 harness baseline;
- Ractor is not a financial-kernel dependency in v0.1;
- when official runtime information arrives, explicitly test/reconcile compatibility rather than assuming it.

## D-017 — v0.1 uses a plain-Ruby modular monolith with an atomic in-memory coordinator

Status: accepted for v0.1; the external shell/coordination implementation may change after official TZ evidence or measured limits.

Decision: v0.1 implementation architecture is a plain-Ruby modular monolith with a deterministic kernel, application orchestrator, narrow ports/adapters, and one in-memory coordinator protected initially by a coarse `Thread::Mutex`. Routing decision fact, allocation commitment, and economic ownership are committed atomically before provider I/O. Provider I/O never occurs while the coordinator lock is held; provider observations are applied in a later synchronized transition.

Rationale: this is the smallest architecture that directly proves the two known hard concurrency invariants — single unresolved economic ownership and committed allocation visibility — while preserving replaceable provider/API/persistence boundaries. A coarse lock provides a simple linearizable baseline before any lock striping/database/distributed coordination complexity is justified.

Consequences:

- `docs/ARCHITECTURE.md` is now a concrete implementation contract rather than only a conceptual boundary map;
- root namespace is `RubyRouting`;
- reference/oracle code stays under test support and is independent from production algorithms;
- facts + current projections are used without requiring full event sourcing;
- provider simulator is the v0.1 provider adapter/test boundary;
- Threads/controlled interleavings verify concurrency; no Ractor/queue/microservice architecture is introduced by default;
- changing the coordinator atomicity model, money representation, test framework, full event-sourcing posture, or core concurrency model requires durable evidence/decision update.

## D-018 — provisional allocation windows are opportunity-cohort scoped

Status: accepted for v0.1; provisional until full-TZ reconciliation.

Decision: the in-memory allocation projection is keyed by policy epoch and the
current feasible-provider cohort. A changed cohort starts a fresh accounting
projection; append-preserved facts still expose the prior opportunity and
assignment history.

Rationale: a provider that was unavailable or ineligible could not receive the
payout, so carrying its historical absence as ordinary router debt would create
unbounded catch-up pressure on recovery. The cohort boundary is simple,
deterministic, and replaceable when the official window/denominator semantics are
known.

Consequences: allocation tests must cover cohort changes and policy epochs, and
the rule must be reconciled together with the accounting point/window under
`B-001`/`B-002`.

## D-019 — observation identifiers are immutable fact identities

Status: accepted for v0.1.

Decision: an exact replay of a provider observation is idempotent, but reusing
the same `observation_id` with different operation linkage or normalized outcome
is rejected. The original observation remains preserved as a fact.

Rationale: duplicate delivery must be harmless without allowing a corrupted or
ambiguous identifier to rewrite lifecycle meaning or attribution.
