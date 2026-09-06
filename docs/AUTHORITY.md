# Documentation Authority

Current Version Goal: **v0.4.3 — Adversarial Evidence & Contract Semantics Closure — VERSION_COMPLETE**.

Opening baseline: `277d6b68d568eceb88ece3b3e466987535ff75bd`.

v0.4.2 / SPEC-018 remains a completed compatible implementation baseline. A fresh code-first audit found unresolved evidence gaps in accounting-point semantics, report semantic validation, normalization robustness, temporal daily state and missing amount-preference configuration. SPEC-019 governs the active cycle.

## Normative order

1. direct current user/instructor requirement;
2. authoritative Hack.Genesis TZ and scoring rubric;
3. organizer data/sample/reference/public validator for contracts they actually define;
4. `specifications/019-adversarial-evidence-contract-semantics.md`;
5. compatible completed SPEC-018, SPEC-017 and SPEC-016;
6. `docs/exec-plans/completed/adversarial-evidence-contract-semantics.md`;
7. `docs/POST_TZ_BACKLOG.md`;
8. `docs/TZ_REQUIREMENT_MATRIX.md`;
9. current architecture/decisions/completion/session/planning/workflow/testing;
10. protected compatible production invariants;
11. implementation/tests;
12. historical documents.

A lower source cannot silently override a higher source.

## Evidence authority

Green tests prove only what their oracle is independent enough to prove. A replay of Router validates consistency, not necessarily intended semantics. A serializer equality test validates fidelity to the same builder, not organizer meaning.

Every v0.4.3 material claim requires one of:

- direct authoritative TZ/sample/rubric evidence;
- an independent oracle derived from raw inputs and explicitly documented semantics;
- an adversarial counterexample showing current behavior is materially wrong;
- explicit evidence-closure when a hypothesis is falsified.

## Report rule

The TZ-compatible base schema from v0.4.2 is protected. v0.4.3 audits the business meaning of base fields, especially `distribution` and `period`, and adds semantic validation without deleting rich assignment/attempt/settlement evidence.

## Organizer ambiguity

When TZ/sample/public validator do not define a detail, do not invent an organizer fact. Preserve reversible internal semantics, document the assumption, and choose a conservative base projection. An ambiguity that can be safely represented does not justify broad architecture.

## Completion

v0.4.3 is VERSION_COMPLETE at exact pushed HEAD `13efbeba48f1726b91b71b1677d3541dd4f9f433`. v0.4.2's completed code/evidence remains compatible baseline evidence; the five v0.4.3 hypotheses, post-candidate blind findings, fresh verification and exact-head Actions run `33852436704` are recorded in the completed ExecPlan.
