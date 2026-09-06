# Long-Horizon Development Roadmap

## Project Goal

Build RubyRouting into a coherent, deeply verified, submission-grade smart payout-routing product in Ruby for Hack.Genesis.

The project does not wait for the official TZ to begin generic product work. Before TZ arrival we close every material locally solvable payout-routing gap. When the authoritative TZ arrives, it becomes a controlled reconciliation/integration delta.

Work hierarchy:

`Project Goal -> Version Goal -> Phase Goal -> Slice Goal`

A green slice is a checkpoint, never an automatic stop condition.

## Current Version Goal

**v0.3.2 — Semantic Control Plane & Recovery Readiness — VERSION_COMPLETE (pre-TZ)**

Normative scope: `specifications/006-pre-tz-semantic-control-plane.md` plus every compatible protected guarantee inherited from SPEC-005/004/003/002/001.

Current plan/closure record: `docs/exec-plans/active/pre-tz-semantic-control-plane.md`.

Current backlog/optional follow-ups: `docs/PRE_TZ_BACKLOG.md`.

Purpose achieved: the semantic control plane around the already strong financial kernel now makes route identity, provider compatibility, policy selection, recovery timing, evidence segmentation, configuration and operator queries deterministic and product-ready before the official TZ.

## Version Map

### v0.1 — Deterministic Foundation — HISTORICAL

Established exact money/allocation, economic ownership, recovery basics, facts/analytics and baseline tests.

### v0.2 — Comprehensive Routing Core — HISTORICAL STRONG CHECKPOINT

Added dispatch safety, operation-scoped recovery, opportunity/eligibility, capacity/health, policy identity, duplicate/out-of-order handling, reversals/conflicts and deeper property/model/concurrency/fault evidence.

### v0.3 — Product Convergence — HISTORICAL COMPLETE CHECKPOINT

Completed one canonical product pipeline, admission/throughput, constrained optimization, slow quality layer, provider normalization boundary, restart-safe working recovery, application/API shell and deep verification.

### v0.3.1 — Pre-TZ Maximum Hardening — HISTORICAL COMPLETE CHECKPOINT

Completed at baseline revision `01c00f2f258a82fcf6e3b2ee843947a68ba62ed1`.

Closed:

- executable immutable provider payout payload;
- dimensional analytics safety;
- exact tolerance semantics;
- explicit recovery selection boundary;
- confidence-aware bounded deterministic quality;
- richer operational health signals;
- one immutable prepared evaluation in the canonical live path;
- first shared live/restore runtime-opportunity seam;
- typed decision explanation and public audit privacy;
- SPEC-005 executable traceability;
- bounded history/performance evidence.

v0.3.1 remains a protected baseline. SPEC-006 is a new layer, not a claim that the prior closure was invalid.

### v0.3.2 — Semantic Control Plane & Recovery Readiness — VERSION_COMPLETE (pre-TZ)

Mandatory outcomes:

1. one canonical typed routing context;
2. explicit generic provider route-capability matching;
3. deterministic policy resolution independent of registration order;
4. visible no-policy/ambiguous-policy handling;
5. explicit active configuration versus durable historical semantics;
6. typed application configuration model;
7. deterministic recovery scheduling and due-work query semantics;
8. route-aware and time-stale deterministic quality evidence;
9. canonical provider-interaction telemetry feeding fast health safely;
10. explicit recovery-objective extension seam;
11. further convergence of duplicate evaluation/live-restore semantics;
12. unambiguous admission capacity terminology;
13. dimension-safe filtered analytics/application queries;
14. SPEC-006 executable traceability and fresh exact-revision closure.

Closure: the fresh 2026-08-31 exact-head SPEC-006 closure passed. The full
deterministic/property/model/concurrency/fault matrix, restart/replay evidence,
bounded product campaigns and documentation reconciliation are recorded in the
active ExecPlan. Only optional P2 work and authoritative-TZ reconciliation
remain.

### v0.4 — Official TZ Reconciliation & Judge Integration

Entry condition: the authoritative full TZ/judge contract is available.

Use `docs/TZ_RECONCILIATION.md`.

Purpose:

- ingest the entire authoritative source before coding;
- split it into atomic requirements;
- classify each as `CONFIRMED / CHANGED / REMOVED / NEW / AMBIGUOUS` against SPEC-006 and inherited behavior;
- reconcile exact routing/allocation/recovery/provider/API/analytics semantics;
- integrate judge interfaces and runtime restrictions;
- turn official numeric limits/scoring into executable gates;
- preserve proven pre-TZ mechanisms where compatible.

The target is a bounded delta, not a rewrite.

### v0.5 — Judge-Driven Optimization & Demo Hardening

Only after official scoring/workload are known:

- tune quality/cost/latency/recovery objectives to measured judge value;
- add adaptive/statistical exploration only if allowed, safe and measurable;
- optimize actual judge bottlenecks;
- polish dashboard/demo around evaluated flows.

### v1.0 — Submission Candidate

Requires:

- complete authoritative-TZ compliance;
- no open P0/P1 acceptance defect;
- reproducible clean setup/run;
- final API/provider contract;
- stable demo;
- restart-safe behavior where applicable;
- current deterministic/property/model/fault/concurrency/performance evidence on submitted revision.

## v0.3.2 Development Phases

The active ExecPlan is authoritative for execution detail. The stable dependency order is:

`Baseline orientation`
→ `RoutingContext`
→ `Provider capability matching`
→ `PolicyResolver`
→ `Configuration model`
→ `Recovery schedule / due work`
→ `Route-aware quality + time staleness`
→ `Interaction telemetry / health`
→ `Recovery objective seam`
→ `Architecture convergence`
→ `Product query surface`
→ `SPEC-006 closure`.

Independent phases may overlap when dependencies permit. Do not block recovery scheduling on configuration work if the current domain seams are sufficient.

## Post-closure queue

The canonical concise queue is `docs/PRE_TZ_BACKLOG.md`; its required v0.3.2
items are verified. No new speculative version is opened before the official
TZ.

Completed order:

1. PTZ2-001 canonical RoutingContext;
2. PTZ2-002 provider route capabilities;
3. PTZ2-003 deterministic PolicyResolver;
4. PTZ2-004 configuration boundary/DTOs;
5. PTZ2-005 recovery scheduling/due work;
6. PTZ2-101/102 route-aware and time-stale quality;
7. PTZ2-103 canonical interaction telemetry;
8. PTZ2-105/106/107 architecture and admission convergence;
9. PTZ2-108/109 product query/config demo surface;
10. PTZ2-006 fresh closure.

Reopen only when new evidence identifies a material correctness defect, or when
the official TZ reconciliation supplies authoritative changed requirements.

## Explicit Non-Priorities Before TZ

Unless new evidence finds a correctness defect, do not sink major effort into:

- deeper FileJournal corruption taxonomies;
- restoration validators for defensive breadth alone;
- microservices/distributed deployment design;
- real brand-specific PSP integrations without authoritative contracts;
- Rails/ORM/queue infrastructure without demonstrated need;
- cosmetic refactoring;
- unsupported production-scale claims;
- ML/bandits before official scoring demonstrates need.

## Stop Condition

v0.3.2 is complete because every SPEC-006 exit criterion has current
executable evidence and the fresh closure passed on exact HEAD. Optional P2
work is intentionally deferred. When the authoritative TZ arrives, immediately
switch to `docs/TZ_RECONCILIATION.md`; otherwise reopen only for a newly proven
material local defect.
