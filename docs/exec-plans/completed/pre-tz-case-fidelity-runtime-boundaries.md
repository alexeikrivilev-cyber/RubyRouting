# ExecPlan — v0.3.8 Case Fidelity & Runtime Boundary Finalization

Status: VERSION_COMPLETE — known P1 scope green; independent skeptical closure clean; final exact verification/CI completed for the closure sequence.

Opening HEAD: `b970c31a62c442dd96e52b8dfc6e31598fe2aa6b`.

## Purpose / Big Picture

Finish the last generic pre-TZ runtime-boundary gaps without reopening the proven v0.3.7 routing/economic kernel. The target is a product that is not only correct internally, but also honest at provider, recovery, configuration and judge/demo boundaries.

The version is deliberately narrow. It should end with fewer ambiguous runtime contracts, stronger case-visible proof and no new platform architecture.

## Governing sources

1. `README.md`
2. `AGENTS.md`
3. `specifications/012-pre-tz-case-fidelity-runtime-boundaries.md`
4. this ExecPlan
5. `docs/PRE_TZ_BACKLOG.md`
6. `docs/ROADMAP.md`
7. `docs/COMPLETION_POLICY.md`
8. `docs/PRE_TZ_ARCHITECTURE_V03_8.md`
9. `docs/DECISIONS_V03_8.md`
10. compatible v0.3.7/SPEC-011 guarantees
11. implementation/tests as evidence, never as higher authority than current explicit requirements.

## Starting repository evidence

At opening:

- v0.3.7 is `VERSION_COMPLETE`;
- validated material SHA: `8e10df1a47f5f96e346bd5c0ffb7f7d7dba29a7c`;
- final evidence/docs closure HEAD: `b970c31a62c442dd96e52b8dfc6e31598fe2aa6b`;
- exact-head Actions run `33657465337` is green;
- `RecoveryExecutor` catches only `ProviderExecutionError` and caps mutating batches at 256;
- `Orchestrator#invoke_provider` still wraps a `StandardError` rescue around both the adapter call and subsequent application-side classification;
- `GET /v1/recovery/due-work` does not pass a limit despite `Queries#due_work` supporting one;
- canonical case demo compares different count and volume workloads;
- runtime configuration can be mutated via HTTP, while adapter registration remains bootstrap-time and active configuration durability is not financial-fact durability.

No confirmed new financial P0 is known at opening. Any deterministic P0 immediately preempts the phase order below.

## Candidate-stage independent skeptical discovery — clean

At candidate checkpoint `c481d5706ae62d6d27347afeeb67c159c77fb3f1`, a fresh
code-first review ignored the backlog checklist and challenged the changed
provider, recovery, HTTP, configuration, adapter-availability and demo paths.
It found no material locally solvable P0/P1:

- provider-call exceptions remain distinct from post-return application
  classification/validation failures, while interaction guards release safely;
- due-work inspection is strictly bounded and rejects malformed controls before
  querying;
- configuration and adapter availability remain separate authorities;
- the case demo uses one skewed workload and canonical analytics, without a
  second routing/allocation path;
- UNKNOWN, causal safety, restart/replay, privacy and lock/I/O invariants were
  not weakened, and no new broad production rescue or unbounded operator path
  was introduced.

The candidate still requires fresh exact verification and pushed-HEAD CI before
the status can change to `VERSION_COMPLETE`.

## Protected baseline

Do not reopen without new evidence:

- count/volume allocation authority;
- UNKNOWN and cross-provider safety;
- provider idempotency semantics;
- causal live/restart protections;
- exact financial arithmetic;
- typed RoutingContext/policy/provider compatibility;
- configuration atomic publication;
- recovery scheduling and same-provider resolution;
- attempt history, analytics and public explanation;
- v0.3.7 RecoveryExecutor error/time semantics except where S12-001 proves the provider error boundary itself is too broad.

## Phase 0 — re-orient and reproduce actual boundaries

1. verify exact HEAD and exact current CI before coding;
2. inspect `Orchestrator#invoke_provider`, `classify_transport`, `validate_observation!`, interaction-guard release and `RecoveryExecutor#execute` together;
3. write a deterministic regression where provider call returns successfully but classification/validation fails afterward;
4. inspect due-work query/HTTP cardinality and demo output from actual code;
5. inspect configuration bootstrap/store/provider adapter ownership and existing restart tests.

Do not infer implementation from SPEC text.

## Phase 1 — provider execution provenance — VERIFIED

Goal: close S12-001.

Acceptance:

- only exceptions originating from executable provider invocation inherit resumable provider-execution semantics;
- application-side classifier/validation bugs fail closed under their own deliberate taxonomy;
- malformed adapter return behavior is explicit;
- interaction guard is released exactly once and economic owner remains safe;
- recovery batch continuation occurs only for the deliberately resumable typed class;
- public recovery error remains bounded/private.

Preferred minimal change: narrow the rescue around the adapter method call. Introduce a new contract-error class only if tests show that plain fail-closed validation errors are insufficiently clear.

Verification: focused Orchestrator/RecoveryExecutor tests are green. The
adjacent 199-run / 1,096-assertion matrix covering guard/concurrency,
duplicate workers, economic safety, restart and replay is green. The narrow
rescue preserves raw adapter-call `ProviderExecutionError`, while
post-return validation retains `ArgumentError` and aborts RecoveryExecutor.

## Phase 2 — bounded due-work inspection — VERIFIED

Goal: close S12-002.

Acceptance:

- HTTP due-work accepts a bounded limit or otherwise uses a bounded default;
- hard cap is explicit and tested;
- unknown/duplicate/malformed/out-of-range query parameters fail before query execution;
- ordering and `as_of` semantics remain unchanged;
- no second pagination/indexing system unless evidence requires it.

Prefer sharing the existing recovery batch cap if that keeps the product contract simple.

Implemented: `HttpApp` exposes an explicit default/cap of 256, validates
`limit` before querying, rejects duplicate/unknown/malformed/out-of-range
parameters, and calls `Queries#due_work(as_of:, limit:)` for both implicit and
explicit `as_of` requests. Focused HTTP verification is 37 runs / 258
assertions; the adjacent recovery/configuration/restart/case matrix is green
at 174 runs / 980 assertions.

## Phase 3 — strategy-isolated judge proof — VERIFIED

Goal: close S12-003.

1. measure allocator behavior on a same-workload skewed fixture;
2. choose a deterministic fixture where count and volume visibly diverge;
3. run equivalent provider behavior/configuration except for policy measure;
4. report input workload, target shares, primary assignment counts and primary assigned volume;
5. assert report values against canonical analytics/queries;
6. retain fallback + UNKNOWN + deferred recovery evidence in the same case report or a clearly adjacent canonical section.

No demo-only routing or arithmetic.

Implemented: `Demo::Scenario.case_run` uses one deterministic skewed
`[900, 100, 100, 100]` sequence for both policies, with the same provider
set/behavior and only the policy measure materially changing the routing
objective. Canonical analytics/report evidence shows count target/actual
`2/2` and `2/2`, versus volume target/actual `600/600` and `300/900`.
Fallback, UNKNOWN resolution, attempt history and success analytics remain
covered by `DemoScenarioTest` and `CaseFidelityCampaignTest`; the runnable
case command was also executed successfully.

## Phase 4 — active configuration restart contract — VERIFIED

Goal: close S12-004.

Evidence-closed without production redesign: canonical configuration export
is re-supplied through strict `RoutingConfiguration.decode` to a fresh
`ConfigurationStore`/`Service`. The fresh process-local generation starts at
revision 0 and never derives active configuration from payout facts. The new
`ConfigurationIngressTest` regression proves typed/JSON equivalence and
runtime provider catalog publication; existing configuration crash and
restart suites cover coherent publication and unresolved payout safety.

Determine actual current contract before changing production code.

Preferred outcome if sufficient:

`GET/export canonical configuration -> RoutingConfiguration.decode -> fresh ConfigurationStore/Service bootstrap`

with deterministic equivalence tests and explicit documentation that runtime HTTP mutation is an active-process control-plane generation unless the caller persists/re-supplies it.

Do not infer active configuration from payout facts. Do not add a DB merely for this phase.

If current bootstrap API cannot express the contract cleanly, add the smallest typed application bootstrap seam.

## Phase 5 — configured provider / adapter consistency — VERIFIED

Goal: close S12-005.

Implemented as a runtime projection: `Service` exposes the normalized adapter
IDs owned by its canonical `Orchestrator`; `GET /v1/providers` adds only the
application-level `adapter_available` flag to each provider row. The domain
opportunity/configuration values remain unchanged, and no dynamic plugin or
adapter object enters the configuration schema. The focused regression proves
configured A/callable and configured B/uncallable are distinguishable while
the HTTP/application/concurrency suites remain green.

Inventory actual use cases first. Then choose minimal behavior:

- fail apply for enabled/usable providers with no executable adapter; or
- compile/application warning; or
- explicit operator status such as adapter availability.

The result must make silent uncallability impossible to miss while preserving any intentional disabled/future-provider semantics.

Adapters remain application/runtime objects, never ProviderOpportunity domain fields.

## Phase 6 — docs/traceability and final closure — VERIFIED

Goal: close S12-006.

- remove stale statements describing fixed v0.3.7 behavior as current;
- record each implemented/evidence-closed finding with exact tests/evidence;
- keep Rolling Next Actions to 2–5 items;
- synchronize README/AGENTS/backlog/roadmap/architecture/decisions/completion/workflow.

SPEC-012 traceability is executable: `S12-001` through `S12-006` are mapped in
`test/support/acceptance_evidence.rb` and validated by
`AcceptanceTraceabilityTest`.

## Candidate gate and final closure

When all known mandatory P1 is green, set only `VERSION_CANDIDATE`; after a clean independent review and exact final verification, the version may become `VERSION_COMPLETE`.

Then ignore the backlog and perform a fresh code-first review of all changed production paths. Required questions:

- Can a classifier/programming failure still be mislabeled as resumable provider failure?
- Can any exception path leak or fail to release the interaction guard safely?
- Can any operator read still return unbounded state?
- Can runtime config disappear/reappear across restart in a way docs/API misrepresent?
- Can configured providers silently be impossible to execute?
- Can stale/lost config updates produce a material correctness problem?
- Does the demo prove strategy causality or merely show two independent scenarios?
- Did any fix weaken UNKNOWN or causal safety?
- Did any new adapter/demo code become a second business authority?

Any material local P0/P1 returns ACTIVE.

## Verification matrix

After each slice: focused deterministic tests.

After material semantic changes: adjacent property/model/concurrency/fault/restart tests as relevant.

Before candidate/complete:

- `bundle check`
- `bundle exec rake test`
- `bundle exec rake property`
- `bundle exec rake model`
- `bundle exec rake concurrency`
- `bundle exec rake fault`
- focused provider-boundary tests
- focused HTTP due-work bounds tests
- configuration restart/bootstrap equivalence
- judge/demo deterministic output and analytics equivalence
- inherited causal/fresh-process campaign
- exact case/operator acceptance traceability
- GitHub Actions on exact pushed HEAD.

Do not use stale evidence from an earlier SHA.

## Rolling Next Actions

1. preserve the exact candidate and final closure evidence in the completed plan;
2. reconcile with `docs/TZ_RECONCILIATION.md` immediately when authoritative TZ arrives.

## Stop policy

Do not stop after one fix, commit, green suite, endpoint or demo improvement.

Stop the active version only when:

1. v0.3.8 exit criteria pass, independent skeptical closure is clean and exact pushed-HEAD CI is green; or
2. all remaining mandatory work is genuinely externally blocked and no independent mandatory slice remains; or
3. authoritative TZ arrives, at which point switch immediately to `docs/TZ_RECONCILIATION.md`.

A difficult bug, failing test, reversible design choice, repository research or missing TZ is not an external blocker.
