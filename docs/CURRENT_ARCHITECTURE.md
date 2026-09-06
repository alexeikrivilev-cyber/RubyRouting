# Current Architecture — Product Excellence Direction

Program: **v0.4.4 ACTIVE / SPEC-021**.

Technical direction: `docs/PRODUCT_NORTH_STAR.md`.

## Canonical competition path

`Dataset/Input -> SubmissionProfile -> CaseState/BusinessCalendar -> HardConstraintEvaluator -> Opportunity Set -> Portfolio Factors/Objectives -> ConflictResolver(primary|fallback) -> primary assignment -> provider attempts/simulation -> final provider -> settlement -> causal Decision/Report evidence -> independent validators -> SubmissionManifest`.

## Five architectural layers

### 1. Opportunity

Hard constraints are absolute and re-run on fallback. Soft scoring only sees hard-eligible providers. `spacepayments` is explicit terminal fallback, not a normal scored provider.

### 2. Portfolio objective

One `ConflictResolver` owns soft-goal choice. Count/volume plus priority, amount, conversion, load, intensity and turnover are typed objectives. Only configured positive objectives may influence business preference.

The architectural invariant is stable objective meaning, not any particular normalization formula. Audit zero-weight independence, provider ordering, common weight scaling, factor monotonicity, irrelevant-candidate effects and post-decision portfolio loss.

Tie-break may exist outside the composite score only if it is deterministic and semantically neutral or explicitly configured. Current code uses provider id after score ties; configured priority participates only through its explicit factor weight.

### 3. Execution cascade

Preserve separate typed facts:

- primary assignment;
- selection rationale;
- actual provider attempt;
- provider outcome;
- final selected provider;
- approved settlement.

Fallback must use the same routing authority over the remaining eligible opportunity set. No second chooser. Case expiry semantics do not weaken production UNKNOWN/economic ownership.

### 4. Evidence and analytics

For each operation, retain hard exclusions, eligible set, objective contributions, tie semantics, selection rationale, provider result, fallback continuation and final settlement.

Analytics should explain target deviation and structural opportunity loss, and should distinguish primary/final/settlement populations. Prefer deterministic counterfactual evidence tied to controllable parameters over generic advice. For finite queues, a positive volume gap smaller than the minimum operation amount is separately reported as a whole-operation granularity bound when no hard exclusion or forced assignment already explains it.

The live Case target ledger (`Router#traffic`) records exactly one finalized selection per operation, after an approved external attempt or after terminal selection. A rejected/expired external attempt never mutates that ledger, so the next primary operation observes the same final-selected population that target analytics report. The first provider chosen for the cascade is retained independently in `Router#primary_assignment_ledger` and `assignment_distribution`; it is not used as a counterfactual target assignment for fallback.

### 5. Judge/release evidence

Every rubric capability should be demonstrable through the same Case engine with explicit scenario profiles. Release safety from SPEC-020 remains protected: explicit queue, exact root names, business calendar, post-write validators, manifest hashes/bytes and Git trackability.

## Current code-first audit seams

These are hypotheses for autonomous investigation:

- resolver score ties use provider id only; the zero-weight priority leak is fixed and covered by a Router-level regression;
- Router still passes the live hard-eligible set as an explicit opportunity pool, but built-in preference factors use fixed exact `[0,1]` semantic bounds and allocation factors use fixed `[-2,0]` portfolio-loss bounds; dominated and non-dominated candidate perturbations therefore cannot redefine A/B weight meaning through min/max scaling;
- failed attempts expose rejection/expiry as public `reason`, while the rich explanation uses a separate internal selection-rationale field;
- count/volume factors use an exact global post-decision portfolio L1 loss and shared fixed `[-2,0]` raw scale, covered by an independent hand-calculated regression;
- optional intensity configuration is neutral when absent: missing `rpm_limit` has raw `0` but is non-discriminating in resolution, while configured rolling RPM headroom and the hard RPM gate remain separate; an explicit zero RPM limit remains typed no-headroom evidence;
- optional load configuration is neutral per dimension when absent: absent daily/concurrent limits are omitted from the typed headroom average, while an explicitly configured zero limit remains exact no-headroom evidence; an entirely absent capacity policy is non-discriminating rather than a worst-score candidate, and hard capacity gates remain separate;
- finite-workload volume granularity is report-only evidence: a minimum-operation lower bound plus a bounded exact subset-sum probe for small, causally clean workloads; neither becomes a second allocation rule;
- direct typed configurations cannot assign positive target mass to a non-terminal provider unless it is literal `active`; `traffic_percentage` is a soft target signal, while explicit `terminal_provider_id` alone defines terminal role and provider-derived profiles keep terminal target mass at zero;
- organizer base distribution under fallback is final-selected; primary assignment, attempts and approved settlement remain separate projections, and target analytics share the final-selected authority;
- primary and fallback use the same configured weighted resolver: count/volume remain active against the uncommitted final ledger, so a rejected primary is not a final assignment and is not counted twice;
- judge-visible evidence under-represents implemented factors and conflicts.

A newly discovered higher-value issue supersedes these seams.

## Protected production kernel

Production ownership, UNKNOWN, idempotency, durable replay/recovery and provider I/O remain separate and frozen unless direct case evidence creates a blocker.
