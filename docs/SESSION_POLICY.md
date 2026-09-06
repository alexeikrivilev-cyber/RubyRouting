# Session Policy — autonomous score convergence

Program: **v0.4.4 / SPEC-021 — ACTIVE**.

Every coding session begins with exact `main`, exact-head CI, current TZ/rubric, data/scripts, generated artifacts, scorecard and actual Case code. Do not start by blindly implementing the first backlog line.

The agent must:

1. perform a short skeptical audit;
2. update/rank findings by expected score/correctness value;
3. mark already STRONG/PROTECTED surfaces as evidence-saturated when representative independent coverage and a recent blind pass exist;
4. choose the best next hypothesis, applying a diminishing-return penalty to another same-class guard on a saturated surface;
5. reproduce or falsify it independently;
6. implement the smallest coherent correction or evidence-close it;
7. run relevant focused, metamorphic/independent and adjacent tests;
8. exercise serialized artifacts when the boundary is affected;
9. update scorecard/matrix/backlog/ExecPlan;
10. commit/push coherent evidence;
11. continue while useful work is derivable.

Independent evidence remains mandatory where semantic correlation could hide a material defect, but do not turn sessions into exhaustive malformed-input enumeration. If no distinct material failure class is reproduced on a saturated boundary, move to the highest-value PARTIAL rubric area—typically multi-goal semantics, causal explainability or judge-visible strategy evidence.

The agent may reorder or rewrite the active plan when evidence changes priorities. Do not ask for confirmation for ordinary reversible work inside SPEC-021. Do not declare completion because a session reached its initial checklist.
