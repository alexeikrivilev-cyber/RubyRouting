# Execution Plan Protocol

Current active plan: none. `docs/exec-plans/completed/submission-policy-activation-contract-closure.md` is the **v0.4.1 / SPEC-017 — VERSION_COMPLETE** closure plan.

v0.4.0 / SPEC-016 is completed baseline evidence.

## Planning rule

Plan behavior/invariant before class shape. Reproduce current code/output first. Keep one routing authority and one active plan. Prefer end-to-end release-path slices over new abstractions.

## v0.4.1 priority

1. canonical finalization policy activation;
2. assignment/attempt/settlement accounting;
3. fallback/output projection contract;
4. independent amount preference;
5. serialized artifact validation/minimal DTO;
6. analytics/recommendation correctness;
7. hidden-like robustness;
8. blind candidate closure.

Every slice states TZ/rubric relevance, current matrix status, exact entrypoint affected, focused reproducer, artifact effect, validator effect and adjacent case/production boundary risk.

Known scope green → candidate only → blind audit → fresh exact verification → exact-head CI → completion. v0.4.1 has passed this sequence.
