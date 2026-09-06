# TZ Reconciliation

The authoritative TZ superseded pre-TZ guesses and produced v0.4.0 / SPEC-016, which built the bounded official case engine while preserving compatible production safety.

An independent audit then opened v0.4.1 / SPEC-017 because the exact finalization path did not activate the richer smart policy and accounting/output semantics were incomplete. v0.4.1 closed that release-path gap through a typed `SubmissionProfile`, separate assignment/attempt/settlement ledgers, independent preferred amount ranges, conservative decision projection and post-serialization validation.

A subsequent code-first audit of exact `main` `e9a24923aebfdb1b01223a360b3f3f2b4e84ee45` found a new class of competition-boundary issues and opened v0.4.2 / SPEC-018:

- the rich report does not preserve the TZ base report field/type shape;
- the report validator is correlated with the same builder and therefore does not independently prove TZ compatibility;
- fallback ranking can apply count/volume counterfactuals after primary assignment is already recorded;
- Case active status is broader than organizer semantics;
- selected reasons, canonical amount policy and recommendation/feasibility evidence can be made materially stronger for the rubric.

Current reconciliation rules:

- authoritative TZ remains highest product authority;
- base artifact schemas shown by the TZ are compatibility requirements; rich fields are additive;
- public decisions validator remains lower-bound evidence;
- count/volume distribution uses primary assignment by default, with attempts and settlement reported separately;
- fallback cannot create a second counterfactual assignment for the same operation under that interpretation;
- only literal `active` is active inside the bounded Case domain;
- synthetic expired fallback remains case-only and never weakens production UNKNOWN;
- organizer ambiguities use conservative reversible projections and explicit tests;
- history may inform calibration/provenance but never becomes current hard eligibility truth;
- any stronger organizer clarification supersedes the bounded assumptions above and must be reconciled before implementation changes.