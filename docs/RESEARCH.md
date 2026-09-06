# Research References

This file preserves external sources that materially informed the current repository model. Specifications and decisions contain project conclusions; this file is evidence and further-reading context, not a second source of truth.

When external behavior matters to implementation, re-check current official documentation rather than relying indefinitely on this summary.

## 1. OpenAI coding-agent guidance

### How OpenAI uses Codex

https://openai.com/business/guides-and-resources/how-openai-uses-codex/

Key lessons adopted here:

- give Codex persistent repository context with `AGENTS.md`;
- structure work around concrete issue-like goals and acceptance context;
- use task queue/backlog for tangential work instead of expanding current task;
- for larger changes, plan before implementation and validate result.

### Harness engineering: leveraging Codex in an agent-first world

https://openai.com/index/harness-engineering/

Key lessons adopted here:

- repository-local knowledge is the system of record for an agent-first codebase;
- a short `AGENTS.md` should be a map while deeper knowledge lives in structured docs;
- plans, design decisions, active/completed work, technical debt, and verification should be legible in-repo;
- enforce important invariants and architectural boundaries while allowing local implementation autonomy;
- work depth-first by decomposing ambitious goals into verifiable building blocks that unlock later work;
- single Codex runs can sustain multi-hour tasks when the repository harness and feedback loops are strong;
- when agents repeatedly fail, improve context, abstractions, tools, tests, or feedback loops instead of telling them to “try harder”;
- avoid unchecked entropy by turning recurring review lessons into durable repository rules/tests.

### Codex-maxxing for long-running work

https://openai.com/index/codex-maxxing-long-running-work/

Relevant lessons adopted in `docs/ROADMAP.md` and `docs/SESSION_POLICY.md`:

- long-horizon work benefits from explicit continuity across workstreams rather than one isolated prompt;
- ambitious goals should be decomposed into verifiable steps while preserving the larger objective;
- durable project context and checkpoints allow work to continue without repeated human re-orientation;
- human oversight is most valuable at real judgment/external gates, not routine milestone transitions.

RubyRouting translates this into version-gated continuous Goal Mode: complete a verified slice, update living state, choose the next slice, and continue until the active version exit gate or a true external blocker.

### Using PLANS.md for multi-hour problem solving

https://developers.openai.com/cookbook/articles/codex_exec_plans

Key lessons adopted in `docs/PLANS.md`:

- substantial plans are self-contained living documents;
- progress, discoveries, decisions, and outcomes remain current as work proceeds;
- plans focus on demonstrably working behavior and exact validation, not edit checklists alone;
- an autonomous agent should continue through milestones rather than repeatedly requesting next-step confirmation;
- prototypes are appropriate when they reduce major uncertainty and have explicit promotion/discard criteria.

### Model guidance

https://developers.openai.com/api/docs/guides/latest-model

Relevant prompting lesson: leaner instruction sets can outperform repetitive, oversized prompts. The repository therefore states important guidance once and uses progressive disclosure through `AGENTS.md` -> roadmap/current plan -> specification/architecture/testing rather than duplicating a giant instruction manual.

## 2. SpecOps methodology

### SpecOps agent instructions

https://github.com/spec-ops-method/spec-ops-agents-file

Core principle adopted: specifications are source of truth, code implements verified specifications, behavior changes are traceable to requirements, and ambiguity/spec drift is explicit rather than silently encoded in implementation.

### SpecOps methodology

https://github.com/spec-ops-method/spec-ops/blob/main/public/METHODOLOGY.md

The original methodology is heavily oriented toward legacy modernization. RubyRouting adapts useful specification-first and verification principles to a greenfield hackathon instead of copying ceremony that does not serve this project.

## 3. Production payment-routing references

### Hyperswitch intelligent routing

https://docs.hyperswitch.io/explore-hyperswitch/payments-modules/intelligent-routing

Relevant observations:

- production routing separates strategy families such as success/auth-rate, least-cost, elimination, contracts, and volume-based routing;
- success-based routing deals with non-stationary performance and exploration/exploitation rather than assuming fixed provider quality;
- static fallback and intelligent routing are distinct concerns.

### Hyperswitch volume-based routing

https://docs.hyperswitch.io/explore-hyperswitch/workflows/intelligent-routing/volume-based-routing

Supports the case interpretation that percentage-based provider distribution is a first-class business policy independent of provider fallback.

### Juspay payout overview / advantages

https://juspay.io/in/docs/payout/docs/overview/introduction
https://juspay.io/in/docs/payout/docs/overview/payout-advantages

Relevant observations:

- payout orchestration spans multiple banks/providers;
- routing, scheduling, and retry are separate decisions;
- retry/fallback depends on current route health and available alternatives rather than a single universal HTTP retry rule.

### Juspay dynamic routing / orchestrator research

https://juspay.io/blog/juspay-orchestrator-and-merchant-controlled-routing-engine
https://arxiv.org/abs/2510.16735

Relevant observations:

- rule-based routing remains a production-grade foundation; adaptive ordering is an additional layer;
- dynamic routing behaves as a feedback/control system where rapid traffic shifts and delayed outcomes can bias measurement and create instability;
- stability, probing, and bounded traffic movement matter alongside instantaneous success estimates.

## 4. Payout idempotency and delayed outcomes

### PayPal Payouts idempotency

https://developer.paypal.com/docs/payouts/standard/integrate-api/customize/

Relevant observation: after network/5xx uncertainty, repeating with the same provider idempotency identifier can recover original payout state instead of intentionally creating a second payout. This supports distinction between `UNKNOWN`, same-provider recovery, and cross-provider fallback.

### Stripe payouts

https://docs.stripe.com/api/payouts/object

Relevant observation: payout lifecycle can have later failure information after an apparently successful/paid state. A single simplistic boolean success field is not always a safe representation of economic finality.

### Stripe webhooks

https://docs.stripe.com/webhooks

Relevant testing observation: webhook/event delivery can include duplicates, so consumers must be able to process repeated observations idempotently. RubyRouting tests should explicitly inject duplicate provider facts rather than assuming exactly-once callback delivery.

### Adyen payout lifecycle/webhooks

https://docs.adyen.com/payouts/payout-service/payout-lifecycle/
https://docs.adyen.com/payouts/payout-service/getting-paid/payout-webhooks

Relevant observations:

- payout processing includes intermediate, failure, return, and delayed states;
- error reasons distinguish recipient, amount/route, destination-bank, timeout, and other causes that imply different recovery actions;
- payout failure reason and provider reliability are not the same signal.

### AWS idempotent APIs and retry safety

https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/
https://docs.aws.amazon.com/wellarchitected/latest/framework/rel_prevent_interaction_failure_idempotent.html

Relevant observations:

- retries after lost responses are a distributed-systems ambiguity problem, not merely HTTP error handling;
- idempotency semantics are required to make repeat requests safe;
- retry amplification and repeated side effects must be explicitly controlled.

## 5. Scientific/algorithmic references

### Maximizing Success Rate of Payment Routing using Non-stationary Bandits

https://arxiv.org/abs/2308.01028

Production payment-routing study from Dream11. Relevant to future optional adaptive ranking: provider success is non-stationary; TPS/traffic constraints exist; sliding-window UCB performed strongly against a rule-based baseline in their setting. The paper justifies research direction, not mandatory use of that exact algorithm.

### Efficient Fair Queuing Using Deficit Round-Robin

https://web.stanford.edu/class/ee384x/EE384X/papers/DRR.pdf

Relevant analogy for monetary-volume allocation: indivisible work items can have unequal sizes, so simple round-robin by count does not produce fair weighted volume. RubyRouting currently uses broader idea of deficit/discrepancy-aware allocation rather than committing to DRR itself.

### Bandits with Knapsacks

https://arxiv.org/abs/1305.2545

Relevant to optional future optimization under provider capacity/quota budgets. It supports viewing routing as constrained online decision-making, but deterministic constraint model should be built before any bandit layer.

### Cascading Bandits

https://proceedings.mlr.press/v37/kveton15.html

Relevant conceptual analogy for ordered sequential alternatives. RubyRouting does not adopt a static cascading-bandit core because payout fallback has stronger economic-safety requirements and is modeled as a fresh decision after a safely resolved attempt.

## 6. Verification and testing references

### Juspay payout UAT test cases

https://www.juspay.io/in/docs/payout/docs/resources/sample-uat-test-cases

This is particularly relevant to project test harness. The payout sandbox deliberately exercises:

- immediate and delayed success/failure;
- always-pending/manual-review behavior;
- same-reference retry after an initiation failure;
- random gateway timeout followed by status re-check;
- timeout-to-valid/invalid/error validation flows;
- success followed by failure/reversal.

Conclusion adopted: a serious payout simulator must script delayed/ambiguous lifecycle behavior; happy-path response mocks are insufficient.

### Software Testing with QuickCheck — John Hughes

https://research.chalmers.se/en/publication/154999

Relevant techniques:

- property-based testing over generated inputs;
- abstract-data-type properties;
- state-machine modeling for stateful systems;
- finding errors across operation sequences rather than only isolated examples.

RubyRouting adopts methodology, not a Haskell/Erlang runtime dependency. Property/model executable logic remains Ruby.

### Coverage-guided property-based testing

https://doi.org/10.1145/3360607

Relevant lesson: naive random generation can spend most cases outside interesting semantic regions. Generators should create valid policy/provider/state combinations and deliberately cover rare states such as `UNKNOWN`, runtime infeasibility, and near-boundary allocations.

### Linearizability — Herlihy & Wing

https://www.cs.columbia.edu/~wing/publications/HerlihyWing90.pdf

Relevant to concurrency-sensitive operations such as acquiring single economic ownership or committing allocation reservations. Important idea is to check whether a concurrent history can be understood as a legal sequential execution of specified object semantics rather than treating “did not crash” as concurrency correctness.

## 7. Research interpretation rule

Do not cargo-cult a paper, testing technique, or production vendor feature into the project because it is sophisticated.

Use research to answer one of four questions:

1. Does it reveal a correctness hazard or missing invariant?
2. Does it provide a simpler/better algorithm for a verified requirement?
3. Does it provide a testing method that can falsify bugs our examples would miss?
4. Can it produce a measurable improvement under actual hackathon workload and scoring criteria?

If none applies, keep it as background rather than implementation scope.
