# SPEC-011 — Pre-TZ Case Surface & Semantic Convergence

Status: VERSION_COMPLETE.

## Purpose

Take the completed v0.3.6 financial/recovery baseline and close the remaining case-relevant operability, liveness and semantic-maintainability gaps before the authoritative TZ. This version is intentionally not a new routing-algorithm wave.

At opening, no confirmed new financial P0 was known. The mandatory v0.3.7 P1 scope is implemented or evidence-closed and has reached `VERSION_COMPLETE` after fresh skeptical discovery, exact verification and pushed Actions evidence. The validated code SHA is `8e10df1a47f5f96e346bd5c0ffb7f7d7dba29a7c` and Actions run `33652116273` is green for both required jobs; the final docs-only closure commit is separately exact-head verified. Any newly reproduced financial P0/P1 immediately returns the version to ACTIVE.

## Protected inherited guarantees

All compatible SPEC-010 and earlier guarantees remain mandatory, especially exact arithmetic, count/volume allocation, one economic intent, one unresolved owner, conservative UNKNOWN, provider-local idempotency, hard admission/allocation authority, process-local invocation ownership, economically-decisive live fences, durable causal holds/completion, interaction-scoped transport classification, coherent configuration generations, restart/replay parity, complete attempt history and dimension-safe analytics.

Do not redesign a protected mechanism without a new reproducer, measured case-relevant bottleneck or authoritative requirement.

## P1 requirements

### S11-001 — RecoveryExecutor has a fail-closed error taxonomy

Current `RecoveryExecutor#execute` rescues `StandardError` and converts every exception into a per-item operator result.

Required outcome:

- expected provider/application execution failures may be represented as structured item errors only when canonical Service has left payout state safe/resumable;
- `RubyRouting::State::DurableCorruptionError` must not be downgraded to an ordinary item result;
- impossible-state/invariant/programming failures must not be silently converted into expected operational errors;
- one item-level provider failure may not hide independent due work when continuation is safe;
- exact behavior is deterministic and tested by exception class, pass continuation/abort and payout facts/state;
- no retry/reclassification logic is added to the executor itself.

Do not merely replace `StandardError` with an arbitrary allowlist without checking actual exception contracts on `Service#resume`.

### S11-002 — RecoveryExecutor time semantics are coherent and honest

Current `run(limit:, as_of:)` selects `due_work` using `as_of`, then invokes canonical `Service#resume`, whose recovery legality uses Coordinator time.

Required outcome: choose and document one coherent contract.

Acceptable minimal designs include:

1. `as_of` is explicitly scan-only, cannot be advertised as deterministic execution time, and unsafe/misleading future-time usage is rejected or clearly represented; or
2. one canonical evaluation timestamp is safely threaded through both due-work selection and resume without creating a second time authority or bypassing domain scheduling.

Acceptance:

- controlled-clock tests cover past/current/future boundaries and schedule changes between scan and execution;
- selected work cannot be silently represented as executed at a timestamp the domain did not use;
- no real sleeps;
- restart/recovery schedule semantics remain unchanged unless evidence requires otherwise.

### S11-003 — Safe release and causal release authority are explicit

`NormalizedOutcome#safe_to_release?` is an outcome property. v0.3.6 correctly proved that an independent callback carrying that property does not automatically causally dominate an unfinished or unresolved provider interaction.

The generic safe behavior can nevertheless become non-progressing when a provider later supplies stronger authoritative rejection evidence and has no status lookup/idempotent retry path.

Required work:

- build deterministic liveness/safety scenarios for a provider with an UNKNOWN operation and later release evidence, including authoritative-sequence and non-authoritative variants;
- explicitly distinguish outcome safety from causal authority in code/docs/tests;
- preserve conservative UNKNOWN by default;
- if current generic contract cannot express a genuinely authoritative release, add the smallest typed/provider-semantic seam necessary; do not overload a generic boolean;
- if evidence proves the existing conservative behavior is the only safe generic choice, keep it and expose a clear reconciliation/operator reason rather than inventing unsafe liveness;
- prove no fresh provider starts while contradictory monetary evidence can still legally emerge under the chosen contract.

### S11-004 — Repeated causal rules converge to one semantic authority

v0.3.6 candidate review repeatedly found live/restore/replay divergence around current-owner linkage, causal hold/completion legality and identity canonicalization.

Required outcome:

- inspect live Coordinator/ObservationLedger, durable restorers and `Replay` for duplicated causal predicates;
- extract/share only rules with demonstrated semantic duplication, preferably pure predicates/value normalization;
- target one authority for canonical identity/current-owner/hold/completion legality where feasible;
- no new state owner, workflow engine or cosmetic Coordinator split;
- all existing causal concurrency/fresh-process/replay corruption regressions remain green;
- a new test should prove that changing the shared rule affects all intended consumers or that their parity is otherwise mechanically enforced.

If inspection shows no safe extraction can reduce authority duplication, document the evidence and do not refactor for aesthetics.

### S11-101 — Configuration mutation is visible through the canonical product surface

The typed decoder/compiler/atomic application path exists, but the runnable HTTP product currently exposes configuration read only.

Required outcome:

- expose one bounded, strict operator-facing mutation path, preferably `PUT /v1/configuration` if it fits existing `HttpApp` cleanly;
- request JSON goes only through `RoutingConfiguration.decode -> compile -> Service/Commands#apply_configuration`;
- unknown/malformed fields fail closed;
- invalid compilation returns stable typed diagnostics without partial publication;
- successful response includes enough canonical evidence to identify resulting configuration/revision/status;
- no second configuration store/registry/source of truth;
- no judge- or PSP-specific schema.

A smaller CLI/config-file entrypoint is acceptable only if code inspection shows it is materially safer/simpler than HTTP and remains obvious to a judge/operator.

### S11-102 — One bounded recovery pass is visible through the canonical product surface

`RecoveryExecutor` exists but still requires Ruby-level invocation.

Required outcome:

- expose one bounded operator entrypoint, preferably `POST /v1/recovery/run` with a strict small body such as `limit`;
- it delegates only to `Service#recovery_executor.run`;
- it owns no provider selection, routing, scheduling, leases or background lifecycle;
- structured per-item results remain bounded and privacy-safe;
- duplicate callers remain safe through existing Coordinator authority;
- corruption/invariant failures follow S11-001 and are not returned as routine item failures.

Do not build a background scheduler, queue or worker framework before TZ.

### S11-103 — The canonical runnable demo proves the public case

The default demo currently shows only one count-policy fallback even though the product already supports much more.

Required outcome: a deterministic executable scenario, using canonical application paths, visibly demonstrates:

- decoded/configured count strategy;
- decoded/configured volume strategy with skewed payout amounts so the difference is obvious;
- target vs actual distribution;
- safe provider rejection -> next suitable provider;
- ambiguous/no-response -> UNKNOWN with no unsafe cross-provider fallback;
- deferred/same-provider recovery through the bounded RecoveryExecutor where applicable;
- complete ordered attempt history;
- provider/fallback success analytics;
- configuration identity/revision;
- restart/replay parity where practical for the demo evidence.

Output should be machine-readable and concise enough for judge inspection. Do not create demo-only routing logic or separate simulator semantics.

### S11-104 — Causal safety is explainable without leaking internal state

Current public audit may show `safe_to_release=true` and `applied=false` while the internal `causal_hold` field is intentionally redacted.

Required outcome:

- provide a privacy-safe public explanation/reason code for intentionally deferred release, e.g. an equivalent of `awaiting_causal_completion`;
- do not expose recipient/provider-secret/raw transport payloads;
- explanation must derive from canonical facts/state, not implement alternate lifecycle logic;
- operator/judge can understand why fallback did not occur despite a superficially safe failure observation.

### S11-105 — Exact-head evidence and documentation authority stay truthful

v0.3.6 distinguishes last material/candidate revision `0988a624...` from final docs closure HEAD `c1dcd5a1...`. v0.3.7 documentation must preserve that distinction and never call a historical material SHA the current branch HEAD.

Required closure evidence:

- exact final pushed SHA;
- exact GitHub Actions run on that SHA;
- current active/completed ExecPlan layout;
- README/AGENTS/SPEC/backlog/ROADMAP/Completion Policy/docs index status agreement.

## P2 / TZ-gated

Do not implement without new evidence/authority:

- reliability-first or other recovery objective modes;
- tolerance corridor where quality outranks discrepancy;
- alternate allocation accounting points/windows;
- new statistical/ML/bandit routing;
- real PSP-specific adapters before provider contracts are known;
- distributed exactly-once/multi-process leasing;
- DB/Redis/Sidekiq/microservices;
- large Coordinator/Analytics decomposition;
- throughput partitioning/fact compaction without measured need;
- dashboard work that does not materially improve evaluated case evidence;
- branch protection/static tooling as a substitute for product work.

## Verification requirements

For S11-001/002:

- controlled clocks and explicit exception classes;
- assert whether a pass continues or aborts;
- assert exact payout facts/status/ownership after an error;
- no sleep-based timing evidence.

For S11-003/004:

- deterministic safety/liveness counterexamples;
- exact provider A/B call counts;
- current-owner/operation/observation identities;
- live/replay/restart parity;
- fresh-process evidence when durable semantics change.

For S11-101/102:

- strict HTTP/transport bounds;
- prove the endpoint delegates to canonical domain/application authority;
- invalid requests cannot partially mutate state;
- no hidden second routing/config/recovery path.

For S11-103/104:

- deterministic machine-readable demo/explanation evidence;
- compare output with canonical Service/Queries state;
- retain privacy redaction.

After material work run focused suites plus full test/property/model/concurrency/fault, acceptance traceability, exact-case/operator composition and exact-HEAD CI. Benchmarks are required only if changed paths/claims can materially affect measured performance.

## Closure evidence

Known scope reaching green created only `VERSION_CANDIDATE`.

Independent discovery must challenge at least:

- corruption/invariant failures swallowed by operator runners;
- scan time versus execution time mismatch;
- a release path that is safe but can never make progress;
- a liveness fix that weakens UNKNOWN/double-effect safety;
- shared causal predicates that diverge between live/restore/replay;
- HTTP configuration/recovery endpoints bypassing canonical application authority;
- partial configuration publication on decode/compile failure;
- demo-only behavior not present in the real product;
- public explanation leaking internal/sensitive data;
- unsupported distributed/production claims.

The fresh code-first pass found no material local P0/P1. Any material locally solvable P0/P1 returns v0.3.7 to ACTIVE.

## Stop conditions

v0.3.7 is `VERSION_COMPLETE`: every S11 P1 is implemented or falsified with evidence, fresh skeptical discovery found no material local gap, exact verification and exact-head Actions are green, and all authority documents agree.

If authoritative TZ arrives first, immediately switch to `docs/TZ_RECONCILIATION.md`.
