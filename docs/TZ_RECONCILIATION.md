# TZ Reconciliation Protocol

This document is the ready-to-use operating protocol for the moment the authoritative Hack.Genesis case/TZ becomes available.

The purpose is to turn the TZ into a controlled delta against an already mature product, not restart implementation from scratch.

## 1. Authority switch

Before TZ publication, repository authority follows `AGENTS.md` and SPEC-006, with compatible SPEC-005 and earlier guarantees inherited as protected baseline behavior.

After the full authoritative TZ is obtained:

`direct current instruction > authoritative TZ > explicit judge/runtime contract > reconciled repository specification > prior pre-TZ specs > implementation/tests`.

Do not silently reinterpret existing semantics. Every authoritative difference becomes an explicit reconciliation record.

## 2. First action: ingest the complete source

Before coding:

1. read the entire authoritative TZ, including appendices, examples, schemas, limits, evaluation/scoring rules and environment restrictions;
2. preserve the original source/reference unchanged;
3. extract atomic requirements rather than summarizing only the headline case;
4. separate normative MUST/SHALL requirements from examples, hints and optional scoring opportunities;
5. identify contradictions or undefined terms before implementing around them.

Do not optimize for one paragraph while unread sections may change the interpretation.

## 3. Requirement classification

For every atomic requirement assign exactly one initial class:

- `CONFIRMED` — current behavior matches the authoritative requirement;
- `CHANGED` — the same concept exists but authoritative semantics differ;
- `REMOVED` — a pre-TZ behavior is explicitly incompatible or unnecessary;
- `NEW` — the TZ introduces a capability/contract absent from the product;
- `AMBIGUOUS` — authoritative text does not yet permit a safe deterministic interpretation.

`AMBIGUOUS` is not a license to guess if the ambiguity affects financial correctness, judge protocol or acceptance.

## 4. Reconciliation matrix

Create a current working matrix with one row per atomic requirement:

| Req ID | Authoritative text / source | Class | Current semantic | Required delta | Domain/code | API/provider contract | Tests/evidence | Status |
|---|---|---|---|---|---|---|---|---|
| TZ-001 | ... | CONFIRMED | ... | none | ... | ... | ... | verified |
| TZ-002 | ... | CHANGED | ... | ... | ... | ... | ... | todo |

Each row must be independently actionable and verifiable.

Never use one giant row such as "routing works".

## 5. Mandatory reconciliation dimensions

At minimum classify the TZ across these areas.

### Input / payout intent

- payout identity;
- amount/currency precision;
- recipient/destination fields;
- method/rail/context;
- duplicate submission semantics;
- validation/error contract.

### Routing context / policy resolution

- which payout dimensions select a routing strategy;
- policy selector precedence/specificity/priority;
- no-match behavior;
- ambiguity behavior;
- active configuration source and mutation semantics;
- policy pinning/version behavior for in-flight payouts.

### Provider model

- provider configuration schema;
- route capability/eligibility constraints;
- availability/status source;
- capacity/rate/load definitions;
- provider request/response contracts;
- idempotency semantics;
- timeout and ambiguous-send behavior;
- callback/webhook/status lookup semantics;
- ordering/sequence guarantees.

### Allocation

- count strategy exact formula;
- volume strategy exact formula;
- denominator/opportunity rules;
- accounting point;
- window/period/reset semantics;
- target shares/weights;
- tolerance/corridor;
- min/max obligations;
- large indivisible payout behavior;
- outage debt/catch-up semantics.

### Recovery

- what constitutes refusal/failure/nonresponse;
- same-provider retry rules;
- fallback eligibility;
- fallback order/selection policy;
- recovery schedule/backoff/due-time semantics;
- budgets/timeouts/deadlines;
- terminal/deferred states;
- reconciliation expectations.

### Smart optimization

- success/reliability objective;
- cost/latency objective;
- required/forbidden adaptation;
- scoring weights if authoritative;
- exploration allowance;
- route/context segmentation;
- sample maturity and stale-evidence rules.

### Analytics/history

- required history fields;
- distribution metrics;
- success/failure metrics;
- count/volume dimensions;
- reporting windows;
- filtering/grouping expectations;
- required API/output schemas;
- explainability/audit expectations.

### Runtime/judge contract

- Ruby/runtime version;
- allowed dependencies;
- process model;
- storage restrictions;
- required ports/commands;
- input/output protocol;
- startup/shutdown behavior;
- time/memory/CPU limits;
- concurrency/load profile;
- deterministic requirements;
- hidden-test assumptions where inferable from the contract.

### Scoring

- mandatory correctness gates;
- weighted scoring dimensions;
- performance thresholds;
- success-rate objective;
- distribution accuracy objective;
- demo/presentation requirements.

## 6. Order of implementation after reconciliation

Unless the authoritative TZ requires otherwise, resolve deltas in this priority:

1. judge/runtime/input-output contract blockers;
2. economic safety semantics;
3. routing-context/policy/provider compatibility semantics;
4. provider execution contract;
5. hard eligibility/admission rules;
6. exact allocation semantics;
7. timeout/retry/fallback/recovery-schedule semantics;
8. required analytics/history;
9. scoring-sensitive quality/cost/latency optimization;
10. measured performance against official limits;
11. demo/UI polish.

Do not tune scoring on top of a semantically wrong contract.

## 7. Preserve reusable pre-TZ strengths

Do not replace a mature mechanism merely because the TZ describes the problem more simply.

Prefer adapting configuration/contracts around existing proven components when they already satisfy the requirement:

- exact money arithmetic;
- economic ownership;
- UNKNOWN safety;
- atomic commit before provider I/O;
- immutable provider-operation payload;
- primary/recovery/settlement separation;
- functional opportunity vs operational admission;
- deterministic allocation/constrained optimization envelope;
- typed observations;
- restart/replay evidence;
- dimensionally correct analytics;
- typed explanation/public audit boundary;
- deterministic property/model/concurrency harnesses.

Delete or simplify only when the authoritative requirement contradicts the current behavior or the current abstraction adds no value.

## 8. Acceptance conversion

Every authoritative requirement that affects behavior must become executable evidence.

For each reconciliation row add one or more of:

- deterministic unit test;
- scenario/acceptance test;
- property/oracle test;
- metamorphic test;
- fake-clock schedule/deadline test;
- concurrency interleaving;
- fault/timeout simulation;
- restart/reconciliation test;
- API contract test;
- benchmark/load gate.

A requirement is not considered reconciled because the code "looks compatible".

## 9. Performance/scoring conversion

Convert official numeric limits into exact reproducible gates.

Examples of acceptable gate shapes:

- N payouts completed under the specified runtime/memory bound;
- allocation deviation below the authoritative threshold;
- success/fallback metric computed from the official scenario distribution;
- API response schema exactly matching judge expectations.

Do not infer or advertise performance beyond the actual official workload and measured evidence.

## 10. Ambiguity handling

For every `AMBIGUOUS` requirement record:

- exact ambiguous text;
- why interpretations differ;
- financial/correctness consequence of each interpretation;
- safest reversible provisional interpretation if implementation cannot wait;
- where the assumption is isolated in code/config;
- tests that make later replacement cheap.

Prefer configuration and explicit strategy objects over hardcoding uncertain constants.

## 11. Documentation update after TZ

Once reconciliation begins:

- create the official reconciled specification as the new top authority;
- update `AGENTS.md` read order and precedence;
- update `docs/ROADMAP.md` to the official-TZ integration version;
- create an active official-TZ ExecPlan;
- replace `docs/PRE_TZ_BACKLOG.md` as the active backlog or clearly mark it historical;
- keep SPEC-006/SPEC-005 and older pre-TZ specs as historical rationale, not current authority.

## 12. Final official closure

Before submission, perform a fresh closure against the authoritative TZ, not merely a pre-TZ specification.

Required evidence:

- every authoritative atomic requirement classified and resolved;
- no unresolved P0/P1 compliance defect;
- exact judge/runtime/API contract exercised;
- required routing-context/policy/allocation/fallback/analytics scenarios pass;
- current deterministic/property/model/concurrency/fault evidence green;
- official-scale performance evidence current;
- setup/run instructions reproduced from a clean environment;
- documentation and product claims match the exact submitted revision.

The desired end state is: the TZ changes or confirms a bounded set of semantics and interfaces; it does not expose a missing generic routing product underneath.