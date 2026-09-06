# Long-Horizon Development Roadmap

## Project goal

Win Hack.Genesis **«Умный роутинг выплат»** with a deterministic, configurable, explainable Ruby router that satisfies authoritative TZ, hidden/public validation and scoring rubric.

## Current Version Goal

**v0.4.1 — Submission Policy Activation & Contract Closure — VERSION_COMPLETE**.

Opening baseline: `0187bf2558d58a52dfdb27e76694d6323addbcd6`.

## Version map

v0.1 foundation → v0.2 core → v0.3.x safety/product hardening → v0.4.0 authoritative case engine (**completed baseline**) → **v0.4.1 submission policy + contract closure (VERSION_COMPLETE)** → v1.0 submission candidate after organizer test queue/final validation.

## Why v0.4.1 exists

v0.4.0 built the right components, but the opening audit found that the
supported submission command used default priority-only / always-approved
configuration and that distribution accounting/output semantics were partially
ambiguous. v0.4.1 converged capability and actual release path; blind closure
and exact pushed-head verification are complete.

## Execution order

1. reproduce release-path gaps;
2. canonical smart SubmissionProfile;
3. primary-assignment vs attempts vs settlement accounting split;
4. organizer-compatible attempt/selected-provider projection;
5. independent soft amount preference;
6. post-serialization validation/minimal decisions DTO;
7. assignment/settlement analytics and recommendation correction;
8. hidden-like scale/determinism campaigns;
9. exact smart finalization/rubric evidence;
10. VERSION_CANDIDATE;
11. blind code/data/output audit;
12. fresh full exact verification + exact-head CI;
13. VERSION_COMPLETE only after clean closure.

## Freeze

Do not spend scoring-critical time on databases, queues, distributed execution, real PSP integration, ML, generic DSLs, broad production refactors or additional generic recovery hardening.
