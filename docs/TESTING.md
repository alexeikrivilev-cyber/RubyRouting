# Testing — current v0.4.3 requirements

Keep inherited Minitest/Rake/property/model/concurrency/fault and Case suites green. SPEC-019 adds adversarial evidence that must be independent of the implementation path it checks.

## Required campaigns

1. **Accounting-point campaign**: deterministic primary A -> rejected/expired -> final B and compare independently computed primary/final/settlement distributions.
2. **Semantic report oracle**: parse serialized decisions/report plus raw queue/providers/profile; recompute operation count, provider set, distribution counts/shares/targets, projected utilization and period.
3. **Normalization perturbation**: keep A/B facts fixed, add/remove hard-eligible non-winning C across real factors and canonical mixed weights; classify legitimate allocation opportunity changes separately from normalization-only inversions.
4. **Temporal campaign**: queue crossing midnight around a nearly exhausted daily limit; either prove correct day rollover or prove/fail-closed single-day contract.
5. **Missing-band campaign**: add provider without preferred amount range and prove absence is neutral, not maximally preferred.
6. **Finalization convergence**: canonical CLI/finalization, public validator, report shape validator, semantic validator, strict serialized validator and byte/deterministic checks.

A regression that copies production control flow is not an independent oracle. Small hand-calculated expected values are preferred for semantic probes.
