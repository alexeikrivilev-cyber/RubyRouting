# Workflow — v0.4.3 evidence-first

Canonical loop:

`inspect exact main -> hypothesis -> independent reproducer -> classify confirmed/falsified -> invariant/authority -> minimal fix OR evidence-close -> focused tests -> adjacent tests -> real finalization/artifacts -> independent oracle -> broad verification -> docs/matrix/plan -> commit/push -> next hypothesis`.

Rules:

- authoritative TZ and organizer contracts outrank implementation convenience;
- never use Router replay or ReportBuilder self-equality as the only proof of semantics;
- do not replace working architecture unless a material counterexample requires it;
- keep Case-specific expiry semantics bounded from production UNKNOWN;
- no manual editing of submission JSON;
- every release claim refers to exact pushed HEAD and exact-head CI.
