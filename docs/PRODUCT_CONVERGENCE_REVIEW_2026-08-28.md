# Product Convergence Review — 2026-08-28

Reviewed repository HEAD: `30b4fb3e29ff70b37b38586a4e2d1b063a0dde60`.

Purpose: establish the new development vector after a feature burst expanded the repository beyond the coherent routing core.

## Executive verdict

The project should not be restarted. The deterministic payout-routing foundation is strong and materially useful.

However, the repository is not an industrial v1.0 product. The latest feature burst mixed several speculative/demo branches with the core and then declared completion too early.

The correct direction is **Product Convergence**: keep the strong routing/lifecycle core, remove misleading disconnected branches, converge responsibilities into one canonical routing pipeline, then continue development all the way to a nearly finished product before the official TZ.

## Verified strengths

Current code contains strong mechanisms for:

- exact money and Rational allocation;
- economic ownership;
- dispatch token/phase;
- definitely-not-sent vs ambiguous transport;
- operation-scoped provider contract;
- primary/recovery separation;
- count/volume allocation;
- provider opportunity/eligibility;
- capacity reservations;
- provider health/quarantine/probing;
- recovery/status lookup/fallback/defer;
- late economic conflict and reversal;
- lifecycle/allocation/capacity/health replay;
- policy fingerprint and multi-currency policy registry;
- property/model/concurrency/fault tests.

GitHub Actions for the reviewed HEAD succeeded on CRuby 4.0.6. The green run is useful evidence but does not prove product completeness.

## Main convergence findings

### 1. Completion/documentation drift

README still described v0.2 as active and warned against premature completion while ROADMAP declared both v0.2 and an industrial v1.0 delivered.

This contradiction can direct a fresh agent incorrectly and is itself a product-governance defect.

### 2. Coordinator responsibility concentration

`State::Coordinator` grew to roughly 45 KB and owns too many concerns at once: payout/operation registry, allocation, capacity, health, lifecycle, facts, conflict/reversal and atomic synchronization.

The atomic facade is correct. The internal ownership model is not yet the desired final design.

### 3. Advanced ranking was not a safe policy layer

The added `MultiObjectiveRanker` combined discrepancy, fee, latency, priority and health into a weighted penalty and was described as Pareto optimization.

Problems:

- it was not Pareto optimization;
- if integrated naively it could choose worse allocation discrepancy because of a lower-level objective;
- allocation correctness and business distribution therefore risked becoming a tunable weight rather than an authority.

Decision: remove and redesign later as constrained/staged optimization.

### 4. Rate limiting was semantically detached

The added token bucket used Float and wall-clock time and was not integrated into the canonical admission/reservation state.

More importantly, rate/TPS is a time-based throughput budget while existing capacity is concurrent exposure. They need different conservation semantics.

Decision: remove the standalone implementation and reintroduce rate/throughput through the admission controller.

### 5. Corridor/BIN logic drifted from the case

Hardcoded card/BIN/bank assumptions are not generic payout-routing logic and were unsupported by the case contract.

Decision: remove from core. Generic method/rail/destination context remains a valid future routing dimension.

### 6. “Real-world adapters” were simulators

SBP/MIR/bank-wire classes returned synthetic immediate success and had no real external protocol.

Decision: remove misleading names. Future demo providers must be explicitly simulated; future real adapters require actual provider/TZ contracts.

### 7. Chaos adapter used a different provider interface

The added chaos adapter did not match the canonical `initiate(request) / resolve(request)` port and used uncontrolled wall-clock/random behavior.

Decision: remove it. Build one deterministic scripted/seeded simulator around the canonical provider port.

### 8. Persistence did not provide safe restart continuation

The file journal/recovery prototype could rebuild read projections but created a fresh coordinator that re-registered intents without restoring unresolved ownership/operation/reservations.

Therefore the system could look correctly replayed while the working coordinator had forgotten economic authority.

Malformed JSON lines were silently dropped.

Decision: remove the misleading persistence implementation. Reintroduce durability only after crash/restart contract tests prove safe continuation.

### 9. HTTP/webhook shell bypassed the intended provider boundary

The generic webhook endpoint accepted raw `status`, `attribution` and `safe_to_release` fields and constructed domain outcomes directly.

This lets untrusted external payload shape economic safety semantics.

It also exposed internal backtrace lines for 500 responses.

Decision: remove current server/dashboard shell. Rebuild later over stable application commands and provider-specific normalizers.

### 10. Load/fuzz evidence was overstated

The “large scale battle” test executed hundreds of payouts, not the claimed 100k campaign. The fuzz suite used global randomness without an explicit reproducible seed.

Decision: preserve the core-oriented fuzz concept but make randomness deterministic and separate heavy load campaigns from CI.

## Cleanup classification

### Keep as core

- domain money/intent/policy/operation/outcome/ownership/decision values;
- policy registry;
- eligibility/allocation/recovery/health;
- state coordinator/snapshots;
- provider port;
- orchestrator;
- replay/analytics;
- existing strong reference/property/model/concurrency/fault tests that target the core.

### Remove now; reintroduce only through canonical design

- hardcoded payment corridor/BIN mapping;
- weighted-sum “Pareto” ranker;
- standalone token-bucket provider rate limiter;
- standalone fee optimization branch;
- fake SBP/MIR/bank-wire production adapters;
- incompatible chaos adapter;
- unsafe file-journal/snapshot recovery branch;
- demo HTTP server/dashboard and dedicated tests;
- misleading large-scale battle test.

## New target architecture

The product should converge toward:

1. domain/policy values;
2. policy resolver;
3. provider catalog/opportunity builder;
4. operational admission controller;
5. exact allocation controller;
6. constrained optimizer;
7. lifecycle/recovery/reconciliation;
8. focused internal ledgers/reducers;
9. one atomic coordinator facade;
10. provider normalization adapters;
11. durable state repository;
12. application commands/queries;
13. analytics/audit;
14. API/demo over those stable boundaries.

## Immediate development recommendation

Do not add more broad features immediately.

First:

1. get a clean green post-cleanup baseline;
2. inventory remaining modules and remove dead references;
3. decompose one high-value coordinator responsibility without semantics change;
4. write failing restart-safety tests before choosing new persistence;
5. write failing policy/share/admission tests before adding advanced optimization.

## Product standard

The project should be able to explain for every payout:

- which providers could serve it;
- which providers were currently admissible;
- what the distribution policy required;
- why one provider was selected;
- what happened to each attempt;
- whether fallback was economically safe;
- where the actual settlement occurred;
- why target distribution deviated;
- whether provider health/load influenced the route;
- how the state can be reconstructed and safely continued after restart.

That is the target “11/10” product direction. Everything else is subordinate.