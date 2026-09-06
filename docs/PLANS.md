# Execution Plan Protocol

Current active plan: none. The completed v0.4.2 closure plan is archived at
`docs/exec-plans/completed/submission-contract-fidelity-scoring-semantics.md`.

v0.4.1 / SPEC-017 and v0.4.0 / SPEC-016 are completed baseline evidence.

## Planning rule

Plan behavior/invariant and external contract before class shape. Reproduce current code/output first. Keep one routing authority and one active plan. Prefer end-to-end submission slices over new abstractions.

## v0.4.2 priority

1. TZ report base contract fidelity;
2. independent report contract validator;
3. exact active-status semantics;
4. primary-vs-fallback scoring phase;
5. selection reason clarity;
6. amount strategy activation and factor honesty;
7. recommendation/feasibility quality;
8. evidence-gated volume/normalization/terminal cleanup;
9. hidden-like rubric campaign;
10. candidate -> blind audit -> exact closure.

Every slice states:

- authoritative TZ/rubric relevance;
- exact opening behavior/reproducer;
- semantic authority/invariant;
- entrypoint/artifact affected;
- independent oracle/validator where possible;
- focused and adjacent tests;
- compatibility risk;
- matrix/backlog update.

Known scope green -> candidate -> blind audit -> fresh exact verification -> exact-head CI -> completion. v0.4.2 has completed this sequence.
