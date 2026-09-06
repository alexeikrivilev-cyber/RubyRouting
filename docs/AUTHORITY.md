# Documentation Authority

Program: **v0.4.4 — Competition 10/10 Convergence — ACTIVE**.

Governing spec: **SPEC-021 — Autonomous Product Excellence & Score Maximization — ACTIVE / ROLLING**.

Technical product direction: `docs/PRODUCT_NORTH_STAR.md`.

Opening baseline: `50b969575f482610460b805d199acc725e8eb37b`.

## Normative order

1. direct current user/instructor requirement;
2. authoritative Hack.Genesis TZ and scoring rubric;
3. organizer data/sample/reference/public validator for contracts they explicitly define;
4. `specifications/021-autonomous-product-excellence-score-maximization.md`;
5. `docs/PRODUCT_NORTH_STAR.md`;
6. compatible completed SPEC-020/019/018/017/016;
7. `docs/COMPETITION_SCORECARD.md`;
8. `docs/exec-plans/active/autonomous-product-excellence-score-maximization.md`;
9. `docs/TZ_REQUIREMENT_MATRIX.md` and `docs/POST_TZ_BACKLOG.md`;
10. current decisions/architecture/completion/session/planning/workflow/testing/roadmap;
11. protected production invariants;
12. implementation/tests/artifacts;
13. historical docs.

Lower sources cannot silently override higher authority. Official TZ wording is immutable; internal SPEC/docs may only derive stricter engineering/evidence requirements.

## Autonomous planning rule

The active plan is rolling evidence, not command authority. The agent must inspect current code/data/artifacts, discover new hypotheses, estimate score/correctness value and may reorder/rewrite the plan whenever evidence changes priority.

A newly discovered material P0/P1 supersedes documented ordering immediately.

## Evidence rules

- Documentation status is a claim, not proof.
- Green tests prove only their oracle.
- Router replay proves consistency, not intended business meaning.
- Builder/serializer equality proves fidelity, not organizer semantics.
- Resolver-level tests do not prove Router-level invariants if call-site candidate pools/order differ.
- Score improvements require authoritative evidence, an independent/metamorphic counterexample/oracle, deterministic rubric evidence or explicit falsification/evidence-closure.
- A finding closes only against current code/artifacts, not because a previous plan marked it done.

## Product rule

The goal is not minimal compliance. Prefer one coherent five-layer product:

`Opportunity -> Portfolio Objective -> Execution Cascade -> Evidence/Analytics -> Independent Release Evidence`.

Beyond-TZ improvements are justified when they strengthen scored correctness, flexibility, explainability, analytics, extensibility or release safety without speculative infrastructure.

## Completion rule

No fixed task list can authorize `VERSION_COMPLETE`. Candidate requires no known material P0/P1 and no obvious high-value rubric gap. Completion additionally requires a blind code/data/artifact audit that ignores backlog/status, rubric-by-rubric deterministic evidence, clean final submission provenance/rehearsal and exact-head CI.
