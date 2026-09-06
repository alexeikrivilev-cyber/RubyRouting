# Session Policy — v0.4.3

Status: **VERSION_COMPLETE under SPEC-019**.

Every coding session starts by fetching exact `main`, exact-head CI, SPEC-019, the one active ExecPlan, matrix/backlog and actual Case/data/artifacts. Do not trust a prior chat SHA.

Work continuously while the next step is derivable. The default unit of work is one adversarial hypothesis, not one arbitrary file.

For each hypothesis:

1. reproduce/falsify on exact HEAD;
2. state the semantic contract;
3. make the smallest justified code change or explicitly evidence-close without code change;
4. run focused and adjacent tests;
5. generate real artifacts and run independent validators where relevant;
6. update matrix/plan/docs;
7. commit/push coherent checkpoint;
8. continue to the next highest-value open item.

Do not ask to continue when the active plan determines the next step. Do not mark VERSION_COMPLETE from backlog exhaustion alone.
