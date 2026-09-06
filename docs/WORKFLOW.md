# Workflow — autonomous evidence-first score maximization

Canonical loop:

`exact main/CI -> inspect TZ/data/code/artifacts -> update score/risk map -> choose highest-value hypothesis -> independent reproducer -> invariant/authority -> minimal coherent fix OR evidence-close -> focused + metamorphic/independent + adjacent tests -> real artifacts/validators -> scorecard/matrix/plan -> commit/push -> skeptical re-audit -> repeat`.

Rules:

- authoritative TZ/rubric outrank implementation convenience;
- hard constraints never become soft penalties;
- do not use implementation replay as the only semantic oracle;
- before adding another guard to the same boundary, ask whether that surface is already evidence-saturated and whether the new test represents a genuinely distinct material failure class;
- once a surface is STRONG/PROTECTED with representative independent coverage and no current material P0/P1, prefer a higher-value PARTIAL rubric gap over near-duplicate validation hardening;
- do not preserve a planned ordering after evidence makes another issue more valuable;
- no manual editing of submission JSON;
- avoid broad refactors unless they remove a reproduced semantic divergence or materially improve scored extensibility/clarity;
- every release/completion claim names exact pushed HEAD and exact-head CI;
- continue autonomously while the next useful step is derivable.
