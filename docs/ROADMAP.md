# Long-Horizon Development Roadmap

## Project Goal

Build RubyRouting into a coherent, deeply verified, submission-grade smart payout-routing product in Ruby for Hack.Genesis.

The project does not wait for the official TZ while material generic payout-routing work is locally solvable. When the authoritative TZ arrives, it becomes a controlled reconciliation/integration delta rather than a restart.

Work hierarchy:

`Project Goal -> Version Goal -> Phase Goal -> Slice Goal`

A green slice, phase, commit, CI run or exhausted checklist is a checkpoint, never an automatic stop condition.

## Current Version Goal

**v0.3.4 — Pre-TZ Adversarial Case Fidelity & Edge Hardening — VERSION_COMPLETE**

Normative scope: `specifications/008-pre-tz-adversarial-edge-hardening.md` plus compatible protected guarantees inherited from SPEC-007 and earlier.

The previous v0.3.4 closure publication `799f6977f07310105c30be9df549a536cc9d665d` is retained as historical evidence, but a later audit found and reproduced a new material interaction-guard concurrency counterexample. Its fix, fresh skeptical pass, exact candidate verification/CI and final docs-only CI are verified; v0.3.4 is `VERSION_COMPLETE` at the published exact head.

## Version Map

### v0.1 — Deterministic Foundation — HISTORICAL

Exact money/allocation, economic ownership, recovery basics, facts/analytics and baseline tests.

### v0.2 — Comprehensive Routing Core — HISTORICAL STRONG CHECKPOINT

Dispatch safety, operation-scoped recovery, opportunity/eligibility, capacity/health, policy identity, duplicate/out-of-order handling, reversals/conflicts and deeper property/model/concurrency/fault evidence.

### v0.3 — Product Convergence — HISTORICAL COMPLETE CHECKPOINT

Canonical product pipeline, admission/throughput, constrained optimization, quality layer, provider normalization, restart-safe recovery, application/API shell and deep verification.

### v0.3.1 — Pre-TZ Maximum Hardening — HISTORICAL COMPLETE CHECKPOINT

Provider payload realism, dimensional analytics, tolerance/recovery semantics, bounded quality, richer health, explainability/public audit and performance evidence.

### v0.3.2 — Semantic Control Plane & Recovery Readiness — HISTORICAL VERIFIED CHECKPOINT

Canonical RoutingContext, provider route capabilities, policy resolution, typed active configuration, recovery scheduling/due work, scoped quality/health and indexed control queries.

### v0.3.3 — Pre-TZ Skeptical Hardening & Product Semantics — VERSION_COMPLETE

Coherent configuration generations, fail-closed route input, restart-safe timing, quality cohorts, configuration compiler/source-of-truth, contextual health, product query parity and skeptical closure.

### v0.3.4 — Pre-TZ Adversarial Case Fidelity & Edge Hardening — VERSION_COMPLETE

Already verified checkpoints:

1. dimension-safe provider/fallback outcome analytics;
2. baseline duplicate due-worker race serialization;
3. configuration publication fresh-process crash consistency;
4. measured analytics/explanation read-path hardening;
5. measured sparse due-work hardening;
6. deterministic exact-case campaign;
7. product-facing payout history completeness.

Current mandatory outcome:

8. live provider-interaction guard ownership remains correct when duplicate/stale/non-applying observations race a blocked recovery provider invocation and a second worker. Verified and closed after fresh exact-head CI.

### v0.4 — Official TZ Reconciliation & Judge Integration

Entry condition: authoritative full TZ/judge contract is available.

Use `docs/TZ_RECONCILIATION.md`.

Purpose:

- ingest the entire authoritative source before coding;
- classify every requirement as `CONFIRMED / CHANGED / REMOVED / NEW / AMBIGUOUS` against latest pre-TZ behavior;
- reconcile exact routing/allocation/recovery/provider/API/analytics semantics;
- integrate judge interfaces/runtime restrictions;
- turn official limits/scoring into executable gates;
- preserve proven pre-TZ mechanisms where compatible.

### v0.5 — Judge-Driven Optimization & Demo Hardening

Only after official scoring/workload are known:

- tune quality/cost/latency/recovery objectives to measured judge value;
- add adaptive/statistical exploration only if allowed, safe and measurable;
- optimize actual judge bottlenecks;
- polish dashboard/demo around evaluated flows.

### v1.0 — Submission Candidate

Requires authoritative-TZ compliance, no open P0/P1 acceptance defect, reproducible setup/run, final integration contract, stable demo and current correctness/performance evidence on submitted revision.

## Current v0.3.4 Development Vector

`Reproduce live guard race`
→ `Understand adjacent observation/interactions`
→ `Implement invocation-owned local guard if required`
→ `Focused recovery/concurrency/restart verification`
→ `Full matrix`
→ `Fresh skeptical closure`
→ `VERSION_CANDIDATE`
→ `Exact-HEAD CI`
→ `VERSION_COMPLETE` only if all active docs agree.

No feature expansion precedes this correctness chain.

## Completion discipline

A prior `VERSION_COMPLETE` publication does not prevent reopening when new material evidence appears. This is intentional and is not a regression in governance.

When all known work is green, the version becomes only `VERSION_CANDIDATE`. The agent must perform a fresh adversarial discovery pass from the changed production code. Any material locally solvable finding reopens ACTIVE development.

## Explicit Non-Priorities Before TZ

Microservices, Rails/ORM, Redis/Sidekiq, distributed leases, database-backed control plane, provider-brand core schemas, generalized rules DSL, ML/bandits, speculative dashboards and cosmetic architecture churn remain out of scope without authoritative or measured need.
