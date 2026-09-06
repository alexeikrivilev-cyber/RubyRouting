# Current Context — RubyRouting post-TZ

Program: **v0.4.4 — Competition 10/10 Convergence — ACTIVE**.

Governing spec: **SPEC-021 — Autonomous Product Excellence & Score Maximization**.

Completed implementation baseline: `50b969575f482610460b805d199acc725e8eb37b`; exact current `main` must be refetched.

## Product model

`provider snapshot + history + explicit queue + typed policy -> hard opportunity -> configured multi-objective objective -> primary assignment -> attempts/fallback -> final provider -> settlement -> causal decisions/report -> independent validation -> release guard`.

Keep separate: primary assignment; invoked attempt; selection rationale; provider outcome; final selected provider; approved settlement; organizer base projection; rich analytics.

## Current maturity

SPEC-020 closed explicit-queue release safety and snapshot-offset business-calendar risks. Hard gates, deterministic fallback, exact ledgers, typed factors, rich report, independent report validation and submission byte/trackability guard are strong baseline capabilities.

Fresh code-first review shows the remaining path to 10/10 is mostly objective semantics and evidence quality rather than missing infrastructure:

- live eligible-set min/max normalization now ignores dominated providers when building the scale; a Router-level regression closes that perturbation, while non-dominated opportunity effects remain open;
- exact score ties now use provider id only; a Router-level regression proves disabled priority cannot influence a tie, while broader factor-disablement and normalization audits remain;
- failed selected attempts preserve outcome in public `reason` while rich explanations retain their original resolver rationale separately;
- organizer base distribution under fallback remains an explicit interpretation question;
- count/volume ordering now follows an exact global post-decision portfolio L1 objective on a shared fixed scale, with an independent counterexample regression;
- current judge demo exposes much less than the eight implemented scoring factors;
- volume target provenance, recommendation/counterfactual depth and artifact freshness before the hidden submission remain high-value audit surfaces.

These are hypotheses/priorities, not a predetermined patch sequence. The agent must independently reproduce/falsify and may discover something more important.

## Protected production semantics

Competition Case remains bounded from production `UNKNOWN != failure`, economic ownership, durable recovery and provider-I/O contracts.
