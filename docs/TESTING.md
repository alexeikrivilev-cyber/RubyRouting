# Testing — SPEC-021 autonomous product-evidence strategy

Keep inherited Minitest/Rake/property/model/concurrency/fault and full Case suites green. Add tests according to semantic risk and rubric value; do not grow assertion counts for optics.

## Evidence hierarchy

Use the strongest relevant evidence type:

1. authoritative organizer golden/validator for explicitly defined contracts;
2. hand-calculated independent oracle for small semantic questions;
3. metamorphic/property tests for invariants;
4. implementation replay/self-consistency for conservation/regression only;
5. judge-facing deterministic scenarios for rubric visibility;
6. clean-checkout/fresh-process evidence for release behavior.

A resolver-level unit test is insufficient when Router call-site behavior changes candidate pools/order. Score-critical invariants should have both small resolver evidence and at least one end-to-end Router-level probe.

## Evidence saturation rule

Test depth must be proportional to semantic risk and expected score impact. For an externally important boundary, cover the meaningful equivalence/failure classes with at least one independent or metamorphic oracle where correlated replay is unsafe. After representative classes are covered, a recent blind pass is clean and no material P0/P1 remains, treat the boundary as saturated.

Do not keep adding near-duplicate malformed permutations solely to increase defensive coverage. Add a new guard after saturation only when a concrete counterexample, a materially distinct hidden-input class or authoritative clarification justifies it. Otherwise invest test effort in PARTIAL rubric semantics and judge-visible scenarios—especially genuine multi-goal conflicts, explainability and all implemented routing factors.

## Authoritative goldens

Preserve organizer public deterministic cases, required output shape and public validator compatibility. Do not overfit routing policy to the ten public operation ids.

## Scoring metamorphic suite

For `ConflictResolver` and actual Router flow maintain exact scenarios covering:

- provider enumeration order invariance;
- multiplying all positive weights by the same positive factor does not change winner;
- removing or setting one factor weight to zero removes that business preference from the result;
- a zero-weight/disabled priority factor cannot influence a score tie through hidden sort order unless tie semantics explicitly configure it;
- improving one candidate's monotonic factor while holding all else fixed cannot make that factor harm the candidate;
- equal/non-discriminating factor values have zero causal contribution;
- adding/removing a genuinely irrelevant or dominated hard-eligible candidate does not invert A/B solely from normalization mechanics;
- hard exclusion cannot be overcome by any soft score;
- missing optional factor configuration has explicit neutral semantics;
- exact deterministic tie behavior is observable and documented.

### Router-level irrelevant-candidate probe

Do not prove normalization stability by passing a manually frozen reference pool that canonical Router never uses. Construct A/B, route normally, then add hard-eligible non-winning C with A/B facts unchanged and compare actual Router winner/trace. Separate legitimate changes in count/volume opportunity from pure scaling artifacts.

### Allocation objective oracle

Build hand-calculated count and volume portfolios. For every candidate independently compute the intended post-decision distribution objective/loss and compare to resolver ordering. Include all-over-target, under-target, uneven amounts, independent configured volume targets, target-mass edge cases and terminal zero target.

Do not simply recalculate `CountShareFactor#raw`/`VolumeShareFactor#raw`; the retained regression starts from the business objective and catches the former local-deficit/normalization divergence.

## Lifecycle/explainability tests

Verify primary assignment, selection rationale, attempted outcome, final selected provider and settlement independently. For rejection/expiry, prove the original why-selected evidence remains available and is not mislabeled as the failure result.

## Accounting/report oracles

For fallback cases independently recompute primary-assignment, final-provider and approved-settlement populations from raw operation/attempt evidence. Keep organizer projection tests separate from internal ledger conservation and preserve ambiguity reversibly where TZ is silent.

## Temporal/release tests

Preserve SPEC-020 explicit-queue, manifest/trackability/byte-parity and snapshot-offset business-calendar campaigns. Before final submission add freshness/provenance evidence proving root artifact hashes correspond to the actual hidden queue and exact release HEAD.

## Rubric evidence lab

Using the canonical Case engine, provide deterministic judge-readable scenarios for:

- count;
- volume with genuinely independent volume targets;
- priority;
- amount preference;
- conversion;
- load;
- intensity/RPM;
- turnover-min obligation;
- several real multi-goal conflicts where configured weights change the winner;
- infeasible/constrained target diagnosis;
- rejection/expiry fallback and terminal fallback;
- quantitative recommendations/counterfactuals.

Scenario data/profiles may vary. Routing authority may not.

The checked-in runnable evidence surface is `ruby -Ilib bin/ruby_routing_case_evidence`; its output is generated from `RubyRouting::Case::ConflictResolver`, `Router` and `ReportBuilder`, includes typed recommendation provider/evidence/action details, a projection of the canonical `SubmissionProfile`/`CaseConfiguration` provenance and weights plus explicit canonical-versus-synthetic scenario scope, and is covered for determinism and factor/lifecycle coverage. `test/case/normalization_perturbation_test.rb` covers actual Router stability when dominated and non-dominated eligible candidates are added. `bundle exec ruby -Itest test/case/intensity_neutrality_test.rb` covers the Router-level optional-RPM neutral-default regression without sleeps, and `test/case/load_neutrality_test.rb` plus `test/case/factors_test.rb#test_zero_capacity_limit_has_no_load_headroom_without_dividing_by_zero` cover absent, partial and zero-capacity neutral-load contracts. `test/case/volume_recommendation_test.rb` covers both the report-only minimum-operation lower bound and the bounded exact subset-sum evidence for finite workloads. The committed `Gemfile.lock` is part of the clean-checkout reproducibility boundary.

## Extensibility / hidden-like campaigns

Exercise additional providers, missing optional configuration, non-100/invalid target mass, terminal target mistakes, unknown provider config, tight capacities, bank mixes, large/small amounts, fallbacks, terminal route, cross-day/mixed-offset queues and hundreds/thousands of deterministic operations.

Prefer reproducible generators and invariant checks over unrecorded random tests.

## Blind-audit rule

After known findings are green, deliberately ignore the finding registry and inspect the code again for new semantic paths, correlated oracles, disabled-factor leaks, denominator drift, public-data overfit and judge/release gaps. A green test is evidence only for the property its oracle actually proves. The blind audit may reopen a saturated area when it finds a distinct material failure; otherwise its purpose is not to manufacture another guard, but to redirect work toward the highest-value remaining product/rubric gap.
