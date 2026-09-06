# Current Context — RubyRouting post-TZ

Current goal: **v0.4.3 / SPEC-019 — ACTIVE**.

Opening baseline: `277d6b68d568eceb88ece3b3e466987535ff75bd` (v0.4.2 VERSION_COMPLETE baseline).

## Product model

`official provider snapshot + queue + history + SubmissionProfile -> hard eligibility -> primary smart routing -> primary assignment -> deterministic provider attempts/fallback -> final selected provider -> settlement -> decisions + report`.

Keep these concepts separate:

- **primary assignment**: first routing allocation authority currently used by count/volume ledger;
- **attempt**: a provider actually invoked in the bounded simulator;
- **final selected provider**: last selected attempt exposed in organizer decisions;
- **settlement**: approved final monetary outcome used for success/utilization state;
- **report base projection**: organizer-facing compatibility surface;
- **rich report**: additive exact evidence and explanations.

v0.4.3 specifically audits whether the organizer base `distribution` should project primary assignment, final selection or settlement. Do not collapse the three ledgers before that is proven.

## Current adversarial seams

1. semantic report correctness must be independently recomputed from raw inputs/artifacts, not from ReportBuilder;
2. candidate-relative normalization must survive adding/removing irrelevant eligible candidates without unjustified A/B inversion;
3. daily limits must have an explicit temporal contract for hidden queues;
4. missing preferred amount configuration must be neutral rather than silently favorable.

## Protected production semantics

The competition Case simulator is bounded. Production `UNKNOWN != failure`, economic owner safety, durable recovery and provider-I/O contracts remain protected and are not part of this narrow cycle unless a direct TZ blocker appears.
