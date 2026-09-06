# ExecPlan — v0.3.7 Case Surface & Semantic Convergence

Status: VERSION_COMPLETE.

## Purpose / Big Picture

Turn the completed v0.3.6 safety-heavy reference implementation into the strongest pre-TZ case product without inventing new routing semantics. First fix the operator-semantics defects in the newly added RecoveryExecutor, then prove the causal release/liveness boundary, converge the repeated causal predicates that caused v0.3.6 live/replay defects, and finally expose configuration/recovery/demo/explanation through canonical product surfaces.

The goal is not “more code”. It is a smaller gap between the mature kernel and what a judge/operator can configure, execute and understand.

## Current Version Goal

**v0.3.7 — Pre-TZ Case Surface & Semantic Convergence — VERSION_COMPLETE**.

## Governing sources

1. direct current instruction;
2. `specifications/011-pre-tz-case-surface-and-semantic-convergence.md`;
3. this ExecPlan;
4. `docs/PRE_TZ_BACKLOG.md`;
5. `docs/PRE_TZ_ARCHITECTURE_V03_7.md`;
6. `docs/DECISIONS_V03_7.md`;
7. `docs/COMPLETION_POLICY.md`;
8. compatible SPEC-010 and earlier guarantees.

## Starting repository evidence

Opening HEAD for this execution: `0cf4fb518f1346de36762d8055b990ffd8a83c89`.

At opening:

- v0.3.6 is completed; last material/candidate SHA is `0988a6248e71f2cbc7a859a4813bac029dfdba4d` and final docs closure HEAD is `c1dcd5a1b8bb4adc199670b035ddf8342a1bd956`;
- GitHub Actions run `33639941312` is green on the opening HEAD;
- `RecoveryExecutor#execute` rescues every `StandardError` into a per-item error result;
- `RecoveryExecutor#run(as_of:)` selects due work using `as_of` but `Service#resume` evaluates against Coordinator time;
- strict `RoutingConfiguration.decode` and atomic `Service#apply_configuration` exist;
- HttpApp exposes `GET /v1/configuration` but no configuration mutation;
- `RecoveryExecutor` exists but no direct product recovery-run entrypoint exists;
- the default runnable demo shows one count-policy safe fallback and only a small analytics subset;
- internal causal hold is redacted publicly, so a safe-release observation can appear unapplied without a clear public reason;
- v0.3.6 repeatedly found current-owner/causal-completion/identity discrepancies between live, durable restore and replay.

No confirmed new financial P0 is known at opening.

Opening execution discoveries:

- the opening `RecoveryExecutor` rescue was confirmed to swallow
  `DurableCorruptionError`, `ConfigurationDriftError` and programming failures;
- a provider-boundary `ProviderExecutionError` now preserves resumable raw
  adapter failures while keeping all non-provider failures fail-closed;
- `RecoveryExecutor#as_of` is now an explicitly bounded scan timestamp:
  future scans are rejected, while canonical resume keeps Coordinator time;
- focused RecoveryExecutor, orchestrator, due-worker and economic-effect
  suites are green after both changes;
- current broad evidence is green: `rake test` 691 tests/12,039 assertions,
  property 1,210, model 2,958, concurrency 1,388 and fault 4,349 assertions.

Closure evidence on the validated material HEAD is: `bundle check`,
`rake test` (703 tests/12,301 assertions), `property` (1,210 assertions),
`model` (2,958 assertions), `concurrency` (1,446 assertions) and `fault`
(4,468 assertions) are green. Focused HTTP/demo/explanation/acceptance and
fresh-process case/operator/corruption campaigns are green; independent
code-first skeptical discovery found no material local P0/P1. The validated
code SHA is `8e10df1a47f5f96e346bd5c0ffb7f7d7dba29a7c`; Actions run
`33652116273` passed `Fast Ruby verification` and `Bounded product evidence`.
The final docs-only closure commit is separately exact-head verified.

## Protected baseline

Do not reopen without new evidence:

- count/volume allocator and exact arithmetic;
- UNKNOWN/idempotency/economic ownership;
- v0.3.5/v0.3.6 live interaction fences and causal holds;
- observation/transport identity/order semantics;
- restart/replay/fresh-process safety;
- coherent configuration generations;
- analytics/history/audit correctness;
- bounded performance/read-path improvements.

## Global Goal

Deliver a pre-TZ product where:

1. operator recovery errors/time semantics are honest and fail closed;
2. conservative causal safety does not hide an avoidable provider-authority liveness gap;
3. live/restore/replay share the repeated causal rules that previously drifted;
4. a judge/operator can configure strategies and run bounded recovery through the real product surface;
5. one executable canonical demo makes count/volume/fallback/UNKNOWN/history/analytics obvious;
6. causal deferred fallback is explainable without leaking internals;
7. all inherited financial safety remains green.

## Phase 0 — re-orient and prove baseline

1. inspect exact `main` and current CI;
2. run focused existing RecoveryExecutor/config ingress/operator composition/causal tests;
3. inspect actual exception hierarchy from `Service#resume` and due-work/recovery timing flow;
4. inspect ObservationLedger/Coordinator/restorers/Replay duplicated causal predicates;
5. record any discovery that changes the plan before modifying production code.

If any financial P0 reproduces, stop this phase order and fix P0 first.

## Phase 1 — RecoveryExecutor fail-closed error taxonomy

Goal: close S11-001.

Status: IMPLEMENTED; focused, adjacent and broad verification green in the
current working tree.

Actions:

1. DONE — deterministic public-boundary tests cover provider failure,
   `DurableCorruptionError`, `ConfigurationDriftError` and `NoMethodError`;
2. DONE — only the typed provider boundary is item-level;
3. DONE — corruption/impossible-state failures abort/re-raise;
4. DONE — one safe item error does not hide independent due work;
5. DONE — executor still delegates every continuation to `Service#resume`.

Do not hide defects behind broad rescue.

## Phase 2 — RecoveryExecutor time contract

Goal: close S11-002.

Status: IMPLEMENTED; focused, adjacent and broad verification green in the
current working tree.

Actions:

1. DONE — controlled clock reproduces `as_of != Coordinator current time`;
2. DONE — selected the smallest coherent scan-only contract;
3. DONE — result exposes `scan_as_of` and documentation matches execution;
4. DONE — deterministic query/execute clock advance is covered;
5. DONE — inherited restart/recovery scheduling remains unchanged.

No sleeps or second clock authority.

## Phase 3 — causal release authority and liveness

Goal: close S11-003 without weakening safety.

Required deterministic scenarios:

- provider A returns UNKNOWN, has no status lookup or idempotent retry, then later emits safe provider-failure evidence;
- same with authoritative sequence and a newer terminal/rejection event;
- non-authoritative/unsequenced callback;
- active economically-decisive interaction versus no live interaction;
- later contradictory SUCCESS where contract allows it.

Questions to answer from evidence:

- Is `safe_to_release` alone intentionally insufficient forever?
- Can authoritative sequence/event semantics establish causal dominance for the old operation?
- Is a new typed release-proof field/capability needed, or is explicit reconciliation the correct generic behavior?

Prefer no new field if existing provider contract safely expresses the distinction. Never turn any `safe_to_release=true` callback into universal release authority.

## Phase 4 — causal semantic convergence

Goal: close S11-004.

Status: EVIDENCE-CLOSED; no safe shared extraction justified by the actual
authority boundaries.

Actions:

1. inventory duplicate canonical-identity/current-owner/hold/completion logic in Coordinator/ObservationLedger/restorers/Replay;
2. choose only the highest-value duplicated rule(s);
3. extract a pure/stateless shared authority or otherwise mechanically enforce parity;
4. remove old duplicate implementations where safe;
5. run all causal live/replay/fresh-process corruption regressions;
6. verify no new state owner, lock or scan appears.

This phase may close by “no safe extraction justified” if inspection and parity evidence support that conclusion.

Inventory result: live Coordinator `causal_release_hold?` includes the
process-local provider-interaction token, while ObservationLedger owns pure
durable observation hold/completion predicates. Restorers and Replay must also
validate fact order, current ownership and schedule linkage. These are
different evidence layers, not duplicate algorithms that can safely be merged.
Existing identity/causal-hold/completion/replay/fresh-process tests enforce
parity at the durable boundary; no new state machine or cosmetic split was
added.

## Phase 5 — configuration mutation product surface

Goal: close S11-101.

Status: IMPLEMENTED; canonical HTTP adapter and focused/adjacent verification
green.

`PUT /v1/configuration` performs strict JSON parsing, typed
`RoutingConfiguration.decode`, compiler validation and only then delegates to
`Service#apply_configuration`. Successful responses expose the resulting
revision/status/diagnostics; decoder and compiler failures do not publish a
partial generation. HTTP tests assert canonical round-trip, malformed input,
Float rejection, exact Rational round-trip, bounded compiler diagnostics and
unchanged active state. HTTP Rational serialization uses the decoder's
canonical `"numerator/denominator"` representation.

Preferred implementation:

`PUT /v1/configuration` with existing request-size/body bounds.

Flow:

`HttpApp JSON -> RoutingConfiguration.decode -> compile -> Service#apply_configuration`.

Acceptance:

- canonical count/volume configuration succeeds;
- malformed/unknown/Float/duplicate fields fail closed;
- invalid compiler diagnostics return a stable bounded error response with no partial publication;
- response exposes current revision/status/config identity safely;
- concurrent submit/config publication retains whole-generation semantics;
- no alternate configuration source.

## Phase 6 — bounded recovery-run product surface

Goal: close S11-102.

Status: IMPLEMENTED; bounded canonical HTTP adapter and focused/adjacent
verification green.

Preferred implementation:

`POST /v1/recovery/run` with strict small JSON `{limit}` and current-time execution.

Acceptance:

- delegates only to `Service#recovery_executor.run`;
- bounded result size and strict input validation;
- duplicate calls remain safe;
- expected per-item errors remain structured;
- S11-001 fail-closed classes propagate to the proper HTTP/system-level error;
- no background scheduler/queue/lease.

`RecoveryExecutor::MAX_BATCH_SIZE` is the single bound (256) shared by the
Ruby executor and `POST /v1/recovery/run`, which accepts only `{ "limit":
Integer }` and delegates to `Service#recovery_executor.run`. A real UNKNOWN to
same-provider resolution test checks the structured result and exact operation
identity; malformed/out-of-bound controls are rejected before execution. The
endpoint does not accept a scan timestamp and does not introduce a second
execution clock. Provider item errors retain their typed class but expose a
stable operator-safe message; adapter-controlled exception text cannot cross
the HTTP boundary.

## Phase 7 — canonical case demo and explainability

Goal: close S11-103/S11-104.

Status: PTZ7-103 and PTZ7-104 IMPLEMENTED; known P1 scope is green and the
version is complete after skeptical and exact-head closure.

Promote existing operator composition into a runnable scenario rather than writing demo-only logic.

Demo must visibly prove:

- decoded count and volume configurations;
- skewed amounts causing different provider distribution;
- target vs actual;
- safe fallback;
- ambiguous/no-response -> UNKNOWN;
- bounded due recovery -> executor -> same-provider resolution/fallback as canonical rules permit;
- complete ordered attempts;
- provider/fallback success analytics;
- configuration revision;
- public reason for intentional causal defer/reconciliation.

`RubyRouting::Demo::Scenario.case_run` now provides the S11-103 case report
through decoded configuration, canonical Service, bounded RecoveryExecutor and
Queries. The report is timestamp-free and byte-stable: count/volume target and
primary-actual measures, skewed 900/100 inputs, safe fallback, UNKNOWN before
same-provider recovery, ordered attempts, dimensioned settlement analytics,
configuration revision/source and exact provider calls are visible. Remaining
explainability now derives a privacy-safe causal disposition from canonical
replayed state.

Output is deterministic machine-readable JSON. Keep it small enough to inspect in a hackathon demo.

## Phase 8 — full verification and skeptical closure

Known work green -> `VERSION_CANDIDATE`; clean skeptical and exact-head
verification -> `VERSION_COMPLETE`.

Run:

- focused new tests;
- inherited causal/concurrency/fresh-process tests;
- configuration and HTTP tests;
- RecoveryExecutor/operator composition tests;
- `bundle check`;
- `bundle exec rake test`;
- `bundle exec rake property`;
- `bundle exec rake model`;
- `bundle exec rake concurrency`;
- `bundle exec rake fault`;
- acceptance traceability;
- exact-case/runnable demo evidence;
- exact pushed HEAD GitHub Actions.

Then perform an independent code-first skeptical pass ignoring backlog completion labels.

Challenge:

- corruption swallowed as operator error;
- time-of-scan/time-of-execution mismatch;
- conservative release dead-end;
- release-authority change weakening UNKNOWN safety;
- live/restore/replay drift after convergence;
- endpoint partial mutation or alternate business logic;
- demo-only behavior;
- privacy leaks;
- unsupported distributed/production claims.

The pass found no material P0/P1; any future material P0/P1 returns ACTIVE.

## Closure record

1. validated code SHA: `8e10df1a47f5f96e346bd5c0ffb7f7d7dba29a7c`;
2. validated Actions run: `33652116273`, both required jobs successful;
3. plan location is `docs/exec-plans/completed/` after the docs-only closure move;
4. keep `docs/TZ_RECONCILIATION.md` as the authority-switch path when TZ arrives.

Keep this list small and update it after every verified slice.

## Stop policy

Do not stop after one endpoint, test, commit, phase, green suite or demo.

Stop v0.3.7 only when:

1. all mandatory SPEC-011 P1 is verified/falsified;
2. fresh skeptical discovery is clean;
3. exact final pushed HEAD and CI are green;
4. active docs agree and the plan is moved to completed;
5. or authoritative TZ arrives and authority switches to `docs/TZ_RECONCILIATION.md`.

Missing TZ, difficult local bugs, reversible choices and repository research are not blockers.
