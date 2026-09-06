# TZ Reconciliation Protocol

This is the ready-to-use operating protocol for the moment the authoritative Hack.Genesis case/TZ becomes available.

The purpose is to turn the TZ into a controlled delta against an already mature payout-routing product, not restart implementation from scratch.

## 1. Authority switch

Before TZ publication, repository authority follows `AGENTS.md`, **SPEC-007** and the active v0.3.3 ExecPlan, with compatible SPEC-006/005 and earlier guarantees inherited as protected baseline behavior.

After the full authoritative TZ is obtained:

`direct current instruction > authoritative TZ > explicit judge/runtime contract > reconciled repository specification > prior pre-TZ specs > implementation/tests`.

Do not silently reinterpret existing semantics. Every authoritative difference becomes an explicit reconciliation record.

## 2. First action: ingest the complete source

Before coding:

1. read the entire authoritative TZ, including appendices, examples, schemas, limits, evaluation/scoring rules and environment restrictions;
2. preserve/reference the complete source unchanged;
3. extract atomic requirements rather than summarizing only the headline case;
4. separate normative MUST/SHALL behavior from examples, hints and optional scoring opportunities;
5. identify contradictions/undefined terms before implementing around them;
6. compare exact dates/version/runtime constraints when the supplied package contains multiple revisions.

Do not optimize for one paragraph while unread sections may change its interpretation.

## 3. Requirement classification

For every atomic requirement assign exactly one initial class:

- `CONFIRMED` — current behavior matches the authoritative requirement;
- `CHANGED` — the same concept exists but authoritative semantics differ;
- `REMOVED` — a pre-TZ behavior is explicitly incompatible or unnecessary;
- `NEW` — the TZ introduces a capability/contract absent from the product;
- `AMBIGUOUS` — authoritative text does not permit a safe deterministic interpretation yet.

`AMBIGUOUS` is not permission to guess when the ambiguity affects financial correctness, judge protocol or acceptance.

## 4. Reconciliation matrix

Create one row per atomic requirement:

| Req ID | Authoritative source | Class | Current semantic | Required delta | Domain/code | API/provider contract | Tests/evidence | Status |
|---|---|---|---|---|---|---|---|---|
| TZ-001 | ... | CONFIRMED | ... | none | ... | ... | ... | verified |
| TZ-002 | ... | CHANGED | ... | ... | ... | ... | ... | todo |

Every row must be independently actionable and verifiable. Never use a giant row such as “routing works”.

## 5. Mandatory reconciliation dimensions

At minimum classify the TZ across these areas.

### Input / payout intent

- payout identity;
- amount/currency precision;
- recipient/destination fields;
- routing method/rail/context;
- duplicate submission semantics;
- validation/error contract.

### Routing context / policy resolution

- which payout dimensions select a strategy;
- policy precedence/specificity/priority;
- amount-band behavior;
- no-match/ambiguity behavior;
- active configuration source and mutation semantics;
- configuration revision/snapshot expectations;
- policy pinning/version behavior for in-flight payouts.

### Provider model

- provider configuration schema;
- route capabilities and eligibility;
- availability/status source;
- capacity/rate limits;
- provider idempotency guarantees/TTL;
- status lookup/retry/cancellation/webhook semantics;
- provider-specific error taxonomy.

### Allocation

- count versus volume allocation;
- denominator/opportunity semantics;
- windows/epochs;
- target/tolerance/min/max constraints;
- concurrent assignment accounting;
- outage/debt/catch-up semantics;
- multi-currency/FX rules if any.

### Recovery / fallback

- when fallback is legal;
- same-provider retry versus status resolution versus fresh provider switch;
- maximum attempts/switches/time;
- due/backoff schedule;
- TTL/deadline precedence;
- recovery provider objective/ranking;
- behavior when provider response is unknown/ambiguous.

### Health / quality / smart routing

- health signals;
- route/currency context for quality;
- evidence age/sample requirements;
- cost/latency/reliability objectives;
- any allowed adaptive/statistical optimization;
- scoring function if authoritative.

### Persistence / concurrency / restart

- required process model;
- durability guarantees;
- idempotency/restart expectations;
- concurrency limits;
- time semantics across restart/deployment;
- exact judge persistence constraints.

### Analytics / audit / UI

- required metrics;
- dimensions/grouping;
- target versus actual/settlement reporting;
- attempt history;
- required explanations/audit;
- dashboard/API contract.

### Runtime / judge integration

- Ruby/runtime version;
- start command;
- ports/network/database restrictions;
- input/output schema;
- timeouts/resources;
- test harness protocol;
- scoring/evaluation workload;
- packaging/submission rules.

## 6. Reconciliation rules

- Preserve proven pre-TZ behavior when `CONFIRMED`.
- For `CHANGED`, identify the smallest coherent semantic change rather than layering an incompatible adapter over wrong core behavior.
- For `REMOVED`, delete/demote behavior if keeping it would confuse the authoritative path.
- For `NEW`, integrate through the canonical application/routing flow; do not create a judge-only second algorithm.
- For `AMBIGUOUS`, isolate the uncertainty behind a typed/configurable seam when possible and record the exact question.

Financial safety has priority over convenience.

## 7. Configuration migration

SPEC-007 may have introduced a revisioned active configuration snapshot before TZ. Reconcile this explicitly with the authoritative contract:

- map authoritative policy/provider schema into the existing typed configuration if compatible;
- decide whether authoritative config is startup-only, mutable runtime state or judge request data;
- preserve historical payout policy/operation semantics where required;
- remove provisional fields only if authoritative semantics make them unnecessary/incompatible;
- do not retain two active sources of truth.

## 8. Provider integration migration

Brand/provider-specific facts stay in adapters/normalizers. The generic core should receive typed capabilities, operations and normalized outcomes.

If authoritative providers have different idempotency/status semantics, encode them in provider contracts/capabilities rather than weakening UNKNOWN safety globally.

## 9. Testing conversion

Every authoritative requirement gets executable evidence.

Retain compatible pre-TZ regressions. Add:

- exact judge fixtures;
- API/provider contract tests;
- authoritative numeric boundaries;
- changed allocation/recovery scenarios;
- concurrency/restart tests required by the judge environment;
- scoring/performance campaigns matching the real workload.

Old synthetic benchmarks are background evidence, not proof against the judge workload.

## 10. Goal Mode after TZ

Once the matrix exists, create the official reconciliation Version Goal/ExecPlan and continue autonomously:

`classify delta -> highest-value mandatory slice -> implement -> verify -> skeptical review -> update matrix/plan -> continue`.

Do not stop after ingesting the TZ, writing a plan or closing one requirement.

## 11. Completion after TZ

The pre-TZ `VERSION_COMPLETE`/checkpoint labels no longer define submission completion.

Submission readiness requires:

- every authoritative mandatory row resolved;
- no open P0/P1 compliance defect;
- exact judge/runtime integration working;
- current full tests/CI on candidate revision;
- reproducible setup/run;
- measured evidence against authoritative workload/scoring where applicable;
- final skeptical closure under the reconciled specification.
