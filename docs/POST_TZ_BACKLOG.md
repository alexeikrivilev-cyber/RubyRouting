# Post-TZ Finding Registry — v0.4.4 Competition 10/10 Convergence

Status: **ACTIVE under SPEC-021**.

This is a live hypothesis registry, not a mandatory FIFO backlog. The agent may insert, reorder, split or evidence-close findings when fresh code/data/artifact analysis changes expected value.

## Protected completed baseline

SPEC-020 release safety/business calendar is closed and protected: explicit queue finalization, fixed/trackable root artifacts, manifest byte binding, post-write validators, snapshot-offset business date, local-midnight reset and release byte parity.

Hard constraints, deterministic fallback, separate assignment/attempt/settlement ledgers, exact arithmetic, typed profiles and production UNKNOWN/economic-owner safety are also protected unless a fresh reproducer proves a material issue.

## Current high-value hypotheses

### S21-H1 — live opportunity-set normalization stability — CLOSED / STABLE BUILT-IN SCALES

Confirmed at the canonical Router call site: adding a hard-eligible `C` dominated by existing `A/B` on every active raw factor changed the winner solely through live min/max scaling. A second actual Router reproducer found the same unjustified inversion with a non-dominated `C` under `priority + conversion_24h + load`: `A` won the two-provider run and `B` won after `C` entered, despite unchanged A/B raw facts. The minimal correction gives all built-in preference factors a fixed exact `[0,1]` semantic scale; count/volume retain their separate fixed `[-2,0]` portfolio-loss scale. Evidence: `test/case/normalization_perturbation_test.rb` covers dominated and non-dominated Router perturbations, factor campaigns, the full Case matrix and public finalization. Candidate-set scale drift is closed for built-in factors; broader business-objective semantics remain audit surfaces.

### S21-H2 — hidden business objective in tie-break / disabled normalization — CLOSED

Confirmed on the pre-fix Router path: with only `conversion_24h` enabled and equal raw values, swapping provider priority changed the winner despite equal zero scores. A second Router reproducer showed that `priority: 0` could change a non-tied conversion/load winner indirectly by entering the Pareto frontier. The minimal fix uses provider id as the neutral exact-tie key and excludes zero-weight factors from positive-objective frontier construction; configured priority remains active only through a positive explicit contribution. Evidence: `test/case/tie_break_semantics_test.rb` (9 assertions), plus adjacent Case scoring suites. Broader alternate-path evidence remains part of the blind audit.

### S21-H3 — allocation objective semantics — CLOSED / GLOBAL L1

The independent hand-calculated portfolio probe confirmed a real gap: candidate-local count/volume deficits plus per-factor live min/max could choose `B` when the exact combined post-decision portfolio L1 loss chose `C` (`count=[0,0,2]`, `volume=[0,0,2]`, targets `A=0,B=20%,C=80%`, incoming amount `2`). The minimal correction evaluates every configured provider after each hypothetical assignment and uses `-L1` for both allocation factors on a shared exact `[-2,0]` scale, so configured count/volume weights have stable dimensional meaning. Evidence: `test/case/portfolio_objective_test.rb` (8 assertions), full Case matrix, public finalization and serialized validators. Target provenance/mass and non-dominated opportunity semantics remain separate audits.

### S21-H4 — selection rationale vs provider outcome — CLOSED / BOUNDARY FIX

The reproducer on public `op_105`/`op_109` confirmed that a rejected primary attempt had `provider_rejected` both as its outcome and as the rich primary-assignment reason. The minimal fix keeps the organizer-compatible attempt `reason` as the provider outcome, stores the resolver rationale separately on the internal attempt, and makes rich `primary_assignment_reason` use that rationale. `failed_attempts[].reason` remains the provider outcome. Evidence: `test/case/runner_test.rb`, `routing_report_test.json`, Case matrix and public finalization. Continue blind auditing for alternate explanation paths.

### S21-H5 — organizer base distribution under fallback — SUPERSEDED BY S21-H100

The original A-rejected->B-approved reproducer correctly established the three distinct populations, but its provisional primary-based organizer interpretation left target analytics inconsistent after H97 moved compact `distribution` to final-selected providers. S21-H100 closes that drift: compact `distribution` and all target analytics are final-selected, while `assignment_distribution`, attempt and approved settlement remain explicit and independently conserved.

### S21-H6 — rubric evidence lab — CLOSED / RUNNABLE CASE SURFACE

`bin/ruby_routing_case_evidence` now generates compact deterministic judge-facing evidence using the canonical Case resolver/router/report paths. It exposes count, genuinely independent volume targets, priority, amount, conversion, load, intensity, turnover, conversion-vs-load weight conflicts, count-vs-volume portfolio conflicts, hard-forced infeasibility, rejection/expiry-to-terminal fallback and report recommendations/settlement analytics. `test/case/evidence_cli_test.rb` verifies all typed traces, target provenance visibility, fresh deterministic output and lifecycle evidence. No second chooser or operation-specific routing rule was added.

### S21-H7 — volume/intensity/turnover product policy and provenance — PARTIAL / INTENSITY GAP CLOSED

Canonical profile currently derives volume targets from `traffic_percentage` and intentionally does not enable intensity/turnover. A fresh policy/evidence recheck confirms that absence is visible rather than hidden: the loaded profile weights contain neither optional factor, while the same canonical evidence CLI separately runs configured intensity and turnover scenarios with exact traces. No policy activation is justified without a stronger TZ/business requirement. A Router-level two-operation reproducer confirmed that a provider without optional `rpm_limit` was previously assigned raw intensity `1`, silently claiming maximum preference. The minimal fix uses raw `0` plus an explicit neutral explanation for absent RPM configuration; configured RPM headroom remains scored and hard RPM eligibility is unchanged. A fresh typed-boundary reproducer then found that valid `rpm_limit=0` divided by zero inside direct intensity resolution; it now also yields exact raw/normalized/contribution `0` while the hard gate remains authoritative. A shape-valid artifact probe then confirmed that the independent report oracle accepted forged rich volume targets/deviations and a configured target mass above one; it now recomputes assignment count/volume, count/volume targets and deviations from raw queue/decisions/profile, and rejects negative or over-mass targets. Follow-up identity and outcome probes found that `selected_provider` and top-level `simulated_result` could be forged to known-but-unbacked values while compensating projected utilization; the oracle now requires both to follow the last selected attempt. A final chain-integrity probe found that removing both the selected-attempt and top-level outcome could still pass; every selected attempt now requires a valid typed outcome. These guards preserve fallback chains without collapsing ledgers. Evidence: `test/case/intensity_neutrality_test.rb`, `test/case/factors_test.rb#test_zero_rpm_limit_has_no_intensity_headroom_without_dividing_by_zero`, `test/case/report_semantic_test.rb`, `test/case/evidence_cli_test.rb`, adjacent factor/evidence suites and full Case matrix. Canonical target provenance and explicit intensity/turnover policy remain open.

### S21-H8 — analytics/feasibility/counterfactual depth — PARTIAL / STRUCTURAL + GRANULARITY EVIDENCE

Attack recommendations and infeasibility diagnostics with constrained-under-target, forced-over-target, near-daily-limit, fallback, terminal and finite-workload cases. Avoid duplicate/generic advice when a structural cause is already known. Prefer quantitative parameter/coverage changes and bounded what-if evidence.

A one-operation `100`-unit reproducer with a `50/50` volume target confirmed that a positive `50`-unit gap is unattainable by whole operations, but was previously reported only as a generic `volume_target_unmet`. The Case report now adds an independent `volume_workload_granularity` detail when the positive gap is smaller than the queue's minimum operation amount and the observed deficit is not explained by hard exclusion or hard-forced assignment. Allocation is unchanged; broader subset-sum/what-if recommendations remain open.

The canonical public `payflow` report then confirmed a second recommendation defect: the same hard-exclusion evidence was emitted alongside generic `count_target_unmet` and `volume_target_unmet` entries. The report now emits the structural recommendation as the causal detail and suppresses those duplicate generic entries when a provider has observed hard exclusions and a positive count or volume deficit. The independent regression checks both the structural evidence and absence of the contradictory generic advice; allocation, target values and hard-gate semantics are unchanged.

An independent serialized-report probe then confirmed that shape-valid `skip_reasons`, attempt/final outcome totals, fallback count and assignment totals could be forged without being checked by the semantic oracle. The oracle now recomputes these population metrics, including settlement totals and success rate, from serialized decision attempts and the raw queue. It also rejects outcomes attached to hard-skipped attempts, while counting fallback only from earlier selected attempts. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_shape_valid_population_accounting_tampering`; no routing or ledger implementation changed.

The judge-surface audit then found that the runnable evidence CLI exposed only recommendation strings and infeasibility, omitting the canonical report's provider/evidence/action detail. `fallback_and_analytics` now includes the full typed `recommendation_details` projection alongside those strings, with evidence-cli assertions for one-to-one coverage and required causal fields; the existing ReportBuilder remains the sole recommendation authority.

A blind artifact probe then forged a known-shape recommendation provider/evidence pair and the independent semantic oracle accepted it because recommendations were not checked at all. The oracle now validates one-to-one recommendation/detail cardinality, known provider and kind, non-empty action, text/provider linkage, and exact target/actual/gap/utilization/workload fields against independently recomputed report populations. It deliberately does not reimplement the full recommendation policy or replace ReportBuilder. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_recommendation_provenance_tampering`, semantic/contract/serialized suites and the full Case matrix.

### S21-H9 — hidden submission artifact freshness — DISCOVERY / RELEASE

Current committed `_test` artifacts may intentionally be generated from the public fixture before the hidden queue arrives. Ensure final submission rehearsal has an explicit freshness/provenance gate tying the committed bytes to the actual hidden queue digest and exact pushed HEAD; filenames alone are not evidence.

### S21-H10 — extensibility and target/config invariants — PARTIAL / TERMINAL TARGET GUARD

An adversarial configuration probe confirmed that a positive target for the explicit terminal provider was accepted even though the Router never offers terminal to the ordinary resolver. Case configuration now fails closed on positive terminal count/volume targets, with `test/case/configuration_test.rb` regression coverage. Partial non-terminal target maps remain supported for bounded constrained/infeasible scenarios, the public derived provider target mass is exactly `1`, and no target map is silently renormalized. Fresh order/additional-provider probes now cover both a non-routable `enabled` provider (zero target, never selected) and an active provider with positive traffic: the latter derives an exact `1/10` target and preserves decisions/report under provider-order permutation. A follow-up profile-boundary probe supplied positive optional `intensity` and `turnover_min` weights while omitting their optional RPM/minimum-turnover inputs: the profile remains valid by the documented neutral-input contract, and every selected trace exposes exact zero raw/contribution plus a neutral or non-discriminating reason. A boundary campaign now confirms that every provider-keyed configuration map rejects an unknown provider on both direct typed configuration and JSON profile loading; broader target provenance remains under audit.

### S21-H11 — product/evidence polish — PARTIAL / CASE VERSION AUTHORITY

The report, runnable demo and judge evidence previously emitted stale `0.4.2` product metadata while the active program was `v0.4.4`. A single `RubyRouting::Case::VERSION` now drives all three surfaces, with regression coverage in `test/case/version_metadata_test.rb`. The submission profile's `official-smart-v0.4.2` id and seed remain explicit input provenance and are intentionally not rewritten without a policy/data change. README judge-path clarity, dependency-lock reproducibility and final hidden-artifact freshness remain open release audits.

The follow-up judge-surface audit confirmed that the factor/lifecycle evidence did not expose the canonical submission policy or distinguish it from synthetic factor scenarios. The evidence CLI now adds a deterministic typed projection of the real `SubmissionProfile`: profile identity, source/revision, count/volume target provenance, compiled configuration (including weights) and an explicit scope map showing that factor/conflict cases are synthetic while `fallback_and_analytics` uses the canonical profile. The projection is loaded through the existing profile/configuration authority and is covered against the checked-in profile plus byte-deterministic CLI output; it does not select providers or add a second policy. Hidden-artifact freshness and exact-head CI remain release-time obligations.

### S21-H12 — serialized population-accounting oracle — CLOSED / INDEPENDENT EVIDENCE

The semantic report oracle previously checked selected-attempt linkage and rich assignment targets but did not independently recompute several judge-visible population metrics. A shape-valid artifact probe confirmed that `skip_reasons`, attempt/final outcomes, fallback count and assignment totals could be forged without detection. The oracle now recomputes those values plus traffic/settlement totals and success rate from serialized decisions and raw queue amounts, rejects outcomes on hard-skipped attempts and derives fallback only from earlier selected attempts. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_shape_valid_population_accounting_tampering`; no routing or ledger implementation changed.

### S21-H13 — per-provider attempt/settlement report oracle — CLOSED / INDEPENDENT EVIDENCE

The adjacent artifact probe confirmed that shape-valid per-provider `attempt_distribution` and `settlement_distribution` could be forged while the prior oracle still passed. The oracle now recomputes their exact count/volume totals, shares and per-provider attempt outcomes from serialized selected attempts, final approved decisions and raw operation amounts. The attempt and settlement ledgers remain separate; this is only report validation. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_shape_valid_attempt_and_settlement_tampering` and the canonical fallback semantic test.

### S21-H14 — primary demo independent volume policy — CLOSED / JUDGE EVIDENCE

The main `bin/ruby_routing_case_demo` reproduced a judge-facing evidence gap: its count and volume strategy configurations used the same target map, so the observed allocation difference could not demonstrate an independent volume objective. The demo now keeps the count map at `1/5, 1/5, 3/5` and uses a separately configured exact volume map of `1/10, 1/5, 7/10`, while both strategy outputs continue to come from fresh canonical Router/TrafficLedger runs. `test/case/demo_test.rb` asserts target-map independence and verifies that serialized distribution targets match each strategy configuration. The canonical submission profile remains intentionally unchanged and continues to derive its volume target from `provider.traffic_percentage`.

### S21-H15 — aggregate attempt-ledger report oracle — CLOSED / INDEPENDENT EVIDENCE

The adjacent serialized-report probe confirmed that `attempt_totals` could be changed while the independent per-provider attempt distribution and all other checked population metrics remained coherent. The oracle now recomputes aggregate attempt count and volume from serialized selected attempts and links both fields to the per-provider ledger. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_shape_valid_attempt_and_settlement_tampering`; routing and ledger implementations are unchanged.

### S21-H16 — serialized decision-chain terminality — CLOSED / INDEPENDENT EVIDENCE

The blind serialized-decision probe confirmed that the independent report oracle accepted a shape-valid `skipped` attempt appended after the final selected attempt when its skip-reason population was adjusted coherently. Canonical Router output always terminates each decision at its final selected attempt; allowing a later attempt makes the serialized lifecycle ambiguous and can hide data after the reported final outcome. The oracle now requires the last serialized attempt to be selected whenever selected attempts exist. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_attempt_after_the_final_selected_attempt`; no routing, accounting or terminal-fallback semantics changed.

### S21-H17 — serialized attempt typing and decision vocabulary — CLOSED / INDEPENDENT EVIDENCE

The adjacent malformed-input probes confirmed that shape-valid decisions could replace an attempt object with `null`, or use an unknown `decision` value, while compensating `skip_reasons`; the independent oracle previously ignored both cases during population derivation. The oracle now rejects non-object attempts and requires the lifecycle vocabulary `skipped`/`selected` before interpreting populations. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_non_object_attempt` and `#test_independent_oracle_rejects_unknown_attempt_decision`; no routing, accounting or fallback semantics changed.

### S21-H18 — selected-attempt rationale typing — CLOSED / INDEPENDENT EVIDENCE

The next serialized boundary probe confirmed that deleting `reason` from a selected attempt left provider, outcome and all checked populations coherent, so the independent oracle accepted an incomplete lifecycle record. The oracle now requires every selected attempt to carry a non-empty string reason, matching the typed serialized contract while leaving the separate rich selection trace unchanged. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_selected_attempt_without_reason`; no routing or accounting semantics changed.

### S21-H19 — serialized attempt-provider uniqueness — CLOSED / INDEPENDENT EVIDENCE

The next chain probe confirmed that a duplicate hard-skipped provider could be inserted while compensating `skip_reasons`, and the independent oracle still accepted the artifact. Canonical Case routing removes a provider after its single hard skip or selected attempt; the oracle now rejects repeated known providers in one decision chain. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_duplicate_attempt_provider`; no routing or accounting semantics changed.

### S21-H20 — serialized attempt reason vocabulary — CLOSED / INDEPENDENT EVIDENCE

The next semantic boundary probes confirmed that a shape-valid selected or skipped attempt could carry an arbitrary reason while all provider, outcome and population values remained coherent. The independent oracle now accepts only the bounded Case reason vocabulary, while keeping type/empty diagnostics and the rich resolver trace separate. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_unsupported_attempt_reason` and `#test_independent_oracle_rejects_unsupported_skipped_reason`; no routing or accounting semantics changed.

### S21-H21 — structural recommendation causality — CLOSED / COUNTERFACTUAL EVIDENCE

The blind recommendation probe found that any observed hard exclusion suppressed generic under-target advice, even when all remaining hard-eligible operations were sufficient to attain both configured count and volume targets and the allocation was unchanged after removing the exclusion. The report now labels a deficit structurally constrained only when hard exclusions make at least one deficient target mathematically unattainable under an all-hard-eligible upper bound; otherwise generic count/volume advice remains visible. Rich evidence includes hard-eligible operation/volume capacity and the unattainable measures. Evidence: the deterministic regression `test/case/recommendation_test.rb#test_observed_hard_exclusion_does_not_claim_structural_deficit_when_target_remains_attainable`, adjacent public `payflow` recommendation coverage, and exact Case/fault matrices. Existing structural advice remains for payflow because its hard-eligible volume is below its configured target.

### S21-H22 — dimension-specific recommendation causality — CLOSED / ADJACENT EVIDENCE

The adjacent public-case probe found that a hard exclusion making only the volume target unattainable also suppressed the independent count-target recommendation. The report now applies the hard-capacity counterfactual per dimension: structural volume evidence does not hide count advice when count remains attainable, and vice versa. Evidence: `test/case/recommendation_test.rb#test_structural_under_target_exposes_observed_hard_exclusion_causes`, public finalization and the full Case matrix; no allocation, ledger or hard-gate semantics changed.

### S21-H23 — canonical traffic target mass — CLOSED / SOURCE INVARIANT

The target-provenance audit changed one raw public provider `traffic_percentage` from `25` to `15`. Before the fix, `SubmissionProfile.load` accepted the provider source and published a target mass of `9/10`, silently describing an incomplete canonical distribution. The minimal boundary fix now requires the exact sum of active non-terminal provider targets to be `1`; it rejects both under- and over-mass provider-derived maps with exact `Rational` arithmetic. The independent serialized report oracle applies the same source-specific invariant from raw providers, while explicitly configured partial maps remain available for bounded diagnostic scenarios. Evidence: `test/case/submission_profile_test.rb#test_provider_traffic_target_source_requires_full_target_mass`, `test/case/report_semantic_test.rb#test_independent_oracle_rejects_incomplete_provider_traffic_target_mass`; routing, allocation and configured-map semantics are unchanged.

### S21-H24 — supplied profile provenance — CLOSED / ALTERNATE PATH GUARD

The follow-up code-first audit constructed a typed `SubmissionProfile` directly with source `provider.traffic_percentage` and a `1/2` target mass. The profile constructor and `Runner` previously accepted this programmatic object, allowing a caller to claim provider-derived provenance without the loader's dataset derivation. The constructor now enforces exact mass for each provider-derived dimension; `configured` profiles retain their explicit partial-map semantics. Evidence: `test/case/submission_profile_test.rb#test_programmatic_provider_source_profile_cannot_lie_about_target_mass`, plus the H23 loader/oracle regressions and full Case matrix; no routing or accounting path changed.

### S21-H25 — target-source vocabulary — CLOSED / ALTERNATE PATH GUARD

The adjacent constructor audit supplied `count_target_source: "configured"`, which the file loader rejects but the direct typed constructor previously accepted. The constructor now enforces the same bounded source vocabulary as `SubmissionProfile.load`: count is provider-derived, while volume is provider-derived or explicitly configured. Evidence: `test/case/submission_profile_test.rb#test_programmatic_profile_cannot_claim_an_unsupported_target_source`, existing loader/configured-volume coverage and fresh Case verification; no allocation semantics changed.

### S21-H26 — committed artifact byte parity — CLOSED / RELEASE GUARD

The release audit ran the valid finalizer against a deterministic one-operation alternate queue. The existing manifest validated and printed those root artifacts, but `git diff` proved they differed from the bytes in `HEAD`; exact-head CI could therefore regenerate a passing worktree without proving the pushed artifacts were the validated ones. `SubmissionManifest#verify_committed!` now compares each validated artifact digest with `git show HEAD:path`. The release-level Rake/CI path enables this check while the ordinary finalizer remains available for generating a new explicit submission artifact before commit. Evidence: `test/case/finalization_test.rb#test_submission_manifest_rejects_validated_artifacts_not_present_in_head`, positive committed-byte verification, public finalization and exact root artifact parity.

### S21-H27 — provider-derived typed-profile provenance — CLOSED / DATASET-BOUND GUARD

The alternate-path audit supplied a typed `SubmissionProfile` whose count and volume maps both assigned `1` to `vipay`; the maps had valid total mass, so the H24 guard passed, and both `Runner(profile:)` and direct `Router(profile:)` previously accepted the false `provider.traffic_percentage` claim. `SubmissionProfile#validate_against!` now recomputes the exact provider-derived map from the loaded dataset, and the canonical Router boundary applies it before state construction; explicitly configured volume remains independent. Evidence: `test/case/submission_profile_test.rb#test_programmatic_provider_source_profile_cannot_lie_about_provider_targets`, covering both alternate entrypoints, plus the fresh Case matrix and public finalization.

### S21-H28 — typed profile/configuration provenance split — CLOSED / CONSTRUCTOR GUARD

The adjacent typed-boundary probe supplied a profile claiming `trusted-source` revision `99` around a configuration sourced from `data/submission_profile.json` revision `2`; `Runner(profile:)` previously accepted the contradictory top-level and nested provenance. `SubmissionProfile#initialize` now requires source and revision equality before the profile can be used by either Runner or Router. Evidence: `test/case/submission_profile_test.rb#test_programmatic_profile_cannot_split_provenance_from_configuration`, with the existing alternate source/target guards and fresh Case verification; no routing or target semantics changed.

### S21-H29 — typed profile identity/provenance emptiness — CLOSED / ALTERNATE PATH GUARD

The blind constructor probe supplied an empty `profile_id` and empty `source`, plus a matching empty-source configuration. The file loader already rejected empty values, but direct `SubmissionProfile.new` accepted them and the canonical Router emitted a run with blank profile provenance. The constructor now applies the same non-empty identity/provenance contract as the loader. Evidence: `test/case/submission_profile_test.rb#test_programmatic_profile_rejects_empty_identity_and_provenance`, fresh Case matrix (`155/953`), full inherited matrix (`895/13,915`), clean public finalization and benchmark campaigns; no routing, target or release semantics changed.

### S21-H30 — profile report DTO versus file-ingress schema — EVIDENCE-CLOSED / AUTHORITY AMBIGUOUS

The blind round-trip probe showed that `SubmissionProfile#to_h` is a nested report metadata projection and is not accepted as the flat `SubmissionProfile.load` file schema (a configured-volume profile also lacks the loader's top-level `volume_share`). Current code and authority define round-trip for the typed `CaseConfiguration#to_h`, while `SubmissionProfile#to_h` is consumed by the rich report; no current contract requires the two external shapes to be identical. This is therefore evidence-closed without changing report shape or creating a second serializer authority. Evidence: deterministic configured-volume probe, `test/case/submission_profile_test.rb#test_profile_round_trip_keeps_exact_values_and_preferred_bands_are_independent`, and canonical finalization; revisit only if TZ or an operator contract requires profile-level file round-trip.

### S21-H31 — independent raw provider snapshot contract — CLOSED / FAIL-CLOSED ORACLE

The blind artifact audit supplied a provider snapshot with `daily_amount_limit` removed and a compensated report; the independent semantic oracle previously accepted it because it only checked provider identities. A second probe changed that field to a string and made the oracle raise `ArgumentError` while validating utilization. The oracle now independently checks the required provider shape, exact numeric/type bounds and cross-field capacity invariants before semantic recomputation, returning validation errors instead of raising. Canonical exact-ratio strings emitted by the Case serializer are normalized back to `Rational` for the oracle's raw provider view, so hidden-like serialized provider inputs remain valid. Evidence: `test/case/report_semantic_test.rb#test_malformed_raw_provider_returns_validation_errors_instead_of_raising`, `test/case/scale_campaign_test.rb`, and the fresh Case matrix; no routing or accounting path changed.

### S21-H32 — independent raw queue contract and chronology — CLOSED / FAIL-CLOSED ORACLE

The blind artifact audit then supplied the canonical decisions/report with a raw queue operation missing `bank`, and with the first operation moved after its successor in absolute time. The semantic oracle previously accepted both because it checked only operation identities. It now validates the exact queue operation shape, scalar types, positive amount, non-empty requisite, ISO-8601 timestamp and non-decreasing absolute timestamp order before semantic recomputation. Evidence: `test/case/report_semantic_test.rb#test_malformed_raw_queue_returns_validation_errors_instead_of_raising`, fresh Case matrix and public finalization; no routing or accounting path changed.

### S21-H33 — independent provider snapshot root contract — CLOSED / FAIL-CLOSED ORACLE

The next blind artifact probe supplied canonical decisions/report with `gateway` removed from the raw provider document and then with `merchant` changed to a non-string. The semantic oracle previously accepted both because it consumed only `snapshot_at` and provider identities. It now validates the provider root's required metadata and timestamp/type contract before provider recomputation, returning validation errors instead of accepting an incomplete or malformed snapshot. Evidence: `test/case/report_semantic_test.rb#test_malformed_raw_provider_root_returns_validation_errors_instead_of_raising`, fresh Case matrix and public finalization; no routing or accounting path changed.

### S21-H34 — direct typed configuration provenance — CLOSED / ALTERNATE PATH GUARD

The alternate-entrypoint audit supplied a valid `CaseConfiguration` with an empty `source` directly to `Runner(configuration:)`; the canonical Router accepted it and emitted decisions with blank configuration provenance, bypassing the non-empty `SubmissionProfile` contract. `CaseConfiguration` now rejects empty source values while retaining its existing default `case-defaults` source and all routing semantics. Evidence: `test/case/configuration_test.rb#test_configuration_source_must_be_non_empty_for_direct_typed_entrypoint`, focused profile/runner suites and the canonical Case matrix.

### S21-H35 — provider bank identifier shape — CLOSED / FAIL-CLOSED ORACLE

The raw provider audit found that the independent oracle accepted a provider snapshot with a blank bank identifier or duplicated bank entries, although the typed loader rejects both. Provider snapshot validation now applies the same trimmed non-empty identifier and uniqueness contract, alongside the existing type checks. Evidence: `test/case/report_semantic_test.rb#test_provider_identifier_and_bank_values_follow_typed_input_contract`, fresh Case matrix and public finalization; no routing or accounting path changed.

### S21-H36 — null artifact roots — CLOSED / FAIL-CLOSED ORACLE

The malformed-artifact campaign found that literal JSON `null` at the root of any raw provider, queue, profile, decisions or report input produced no error and was treated as an absent parse result. The independent oracle now distinguishes parse failures from valid JSON null and rejects every root whose type is not the required Object/Array contract. Evidence: `test/case/report_semantic_test.rb#test_null_raw_artifact_roots_return_validation_errors`, deterministic 42-case malformed-artifact campaign, fresh Case matrix and public finalization.

### S21-H37 — README explicit submission rehearsal — CLOSED / OPERATOR EVIDENCE

The blind release audit found that the README exposed the evidence/demo commands but not the explicit queue → validate → commit → `--verify-committed` rehearsal. It now documents the public smoke command, the actual-queue command, fixed root artifact names, printed queue/artifact digests and the exact-HEAD verification order. No runtime or artifact behavior changed.

### S21-H38 — hard-forced recommendation causality — CLOSED / COUNTEREXAMPLE

An independent recommendation reproducer used one operation, two hard-eligible providers and `weights: { priority: 1 }`. The better-priority provider was selected, but `hard_forced?` previously treated the single active factor as proof that the assignment was forced by hard constraints, producing false `target_infeasible_hard_forced` evidence for the other target provider. Hard-forced classification now requires the selected resolution to report `only_eligible_provider` and the decision chain to contain a hard-skipped attempt. Evidence: `test/case/recommendation_test.rb#test_single_factor_selection_between_eligible_providers_is_not_hard_forced`, focused factor/evidence/semantic/finalization suites and the fresh Case matrix; routing and target semantics are unchanged.

### S21-H39 — finite-workload volume subset-sum evidence — CLOSED / BOUNDED COUNTEREXAMPLE

The follow-up H8 probe used two fully eligible operations of amounts `70` and `30`, a provider target of `50` volume units and no fallback/exclusion cause. The existing minimum-operation lower bound did not apply because the gap was `50`, while the exact attainable whole-operation volumes were only `0/30/70/100`. The report now emits bounded `volume_subset_sum_granularity` evidence with nearest attainable volumes and suppresses generic volume advice for this case. The report-only bitset is gated at `64` operations and `250000` total volume units, so hidden-like larger workloads remain bounded and unchanged. Evidence: `test/case/volume_recommendation_test.rb#test_unreachable_volume_target_reports_bounded_subset_sum_evidence`, adjacent recommendation/runner/validator/semantic/finalization suites; routing and accounting remain unchanged.

### S21-H40 — dependency-lock release reproducibility — CLOSED / RELEASE BOUNDARY

The blind release audit found `Gemfile.lock` present in the workspace but ignored and untracked, so a clean GitHub checkout could resolve dependency versions afresh despite `bundler-cache: true`. The lockfile is now tracked, includes both the local `x64-mingw-ucrt` and CI `x86_64-linux` platforms, and is no longer ignored. Evidence: `bundle check`, current full Case/inherited matrices and the tracked lockfile on the pushed checkpoint; runtime behavior is unchanged.

### S21-H41 — direct configuration targets for non-routable providers — CLOSED / ALTERNATE PATH GUARD

An alternate-path probe supplied a direct typed `CaseConfiguration` with a positive count/volume target for an `enabled` provider. The profile loader already maps non-`active` providers to zero targets, but the direct Router path previously accepted the positive target and could only fail it later as `inactive_provider`. The canonical Router boundary now rejects positive targets for any non-terminal provider that is not literal `active`, before routing starts. The historical positive-participation clause is superseded by S21-H104; active zero-target providers are valid soft-goal candidates. Evidence: `test/case/terminal_identity_test.rb#test_router_rejects_positive_targets_for_a_non_routable_provider`, configuration tests and fresh Case/finalization verification.

### S21-H42 — whitespace provenance identity — CLOSED / ALTERNATE PATH GUARD

The adjacent provenance audit supplied whitespace-only `source` and `profile_id` values. Empty-string guards previously accepted them in direct typed constructors and the profile loader, producing non-blank-looking but semantically empty provenance. Configuration/profile boundaries now reject `strip.empty?` values while preserving the original non-blank string. Evidence: `test/case/configuration_test.rb#test_configuration_source_must_not_be_whitespace_only`, `test/case/submission_profile_test.rb#test_programmatic_profile_rejects_whitespace_identity_and_provenance` and `#test_profile_loader_rejects_whitespace_identity_and_provenance`, plus fresh Case verification; routing semantics are unchanged.

### S21-H43 — absent optional capacity must be neutral — CLOSED / ROUTER COUNTEREXAMPLE

The fresh Router probe used equal conversion and a `load`-only policy with provider `A` carrying no daily or concurrent capacity limits and provider `B` carrying configured headroom. Before the fix, `LoadHeadroomFactor` returned raw `1` for `A`, so missing data silently gave it maximum preference and selected it over `B` (`24/25`). The factor now returns exact neutral raw `0` when all optional capacity dimensions are absent; configured dimensions retain their exact average headroom, and the trace says `neutral/no load preference`. Evidence: `test/case/load_neutrality_test.rb#test_missing_capacity_limits_are_neutral_instead_of_maximum_headroom`, factor/normalization/portfolio suites, full Case matrix and public finalization. Hard eligibility and configured capacity semantics are unchanged.

### S21-H44 — partial optional capacity must not be renormalized — CLOSED / ROUTER COUNTEREXAMPLE

The adjacent Router probe supplied provider `A` with only a daily limit and provider `B` with all three capacity dimensions. Before the fix, the two missing dimensions disappeared from `A`'s average, giving it raw `99/100` versus `B`'s `24/25` and selecting `A` under a load-only policy. Each absent dimension now contributes exact neutral `0`, so `A` is `33/100`, the configured dimensions remain exact, and `B` wins. The factor campaign fixture now makes every dimension explicit when testing a configured load conflict. Evidence: `test/case/load_neutrality_test.rb#test_missing_capacity_dimensions_are_neutral_in_partial_configuration`, updated `test/case/factor_campaign_test.rb`, factor/normalization suites and the full Case/finalization matrix. Hard capacity gates and configured dimension arithmetic remain unchanged.

### S21-H45 — zero optional capacity must not crash direct scoring — CLOSED / TYPED BOUNDARY COUNTEREXAMPLE

The adjacent direct-resolver probe supplied a valid provider with `daily_amount_limit=0` and invoked `ConflictResolver` directly, before Router hard eligibility. The load factor divided by the zero denominator even though Router correctly excludes a positive payout against zero daily capacity. A zero configured capacity dimension now contributes exact raw `0` (no headroom) while the other configured dimensions retain the fixed three-dimension average; direct scoring is total and hard eligibility remains a separate authority. Evidence: `test/case/factors_test.rb#test_zero_capacity_limit_has_no_load_headroom_without_dividing_by_zero`, adjacent state/load/normalization suites and full Case verification. No Router eligibility or production recovery semantics changed.

### S21-H46 — serialized explanation provenance — CLOSED / INDEPENDENT EVIDENCE

The blind artifact audit mutated `explanations.op_101.selected_provider` while leaving decisions, populations and utilization coherent; the independent semantic oracle previously accepted the forged judge-facing explanation. It now recomputes the independently available lifecycle identity from serialized attempts: decision coverage, selected/primary/final provider and supported reasons, hard exclusions, failed attempts, fallback continuation, terminal identity and considered-provider coverage. Score maps remain shape/provider checked only because compact decisions do not carry an independent score source. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_explanation_identity_tampering`, focused semantic/serialized/finalization verification; routing, ledger and outcome semantics are unchanged.

### S21-H47 — rich report projection provenance — CLOSED / RAW-DERIVED EVIDENCE

The next blind artifact campaign forged `dataset.queue_volume`, `provider_state.vipay.daily_approved_amount` and `deviation_causes.vipay.hard_exclusions`; the independent oracle previously accepted all three while lifecycle populations remained coherent. It now recomputes dataset snapshot/gateway/merchant/count/volume, post-run provider state (including snapshot-offset daily reset and profile RPM-window events) and derivable deviation fields from raw providers/queue/profile plus serialized attempts. History rows/trends remain explicitly outside this closure until the oracle receives and validates raw history input. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_rich_projection_tampering`, focused semantic/serialized/finalization verification and public 29/29 finalization.

### S21-H48 — history analytics provenance — CLOSED / EXPLICIT RAW SOURCE

The next blind probe mutated `history.rows` and `history.by_provider.vipay.approved`; without the raw CSV at the validator boundary both shape-valid changes were accepted. `OrganizerReportSemanticValidator` now accepts an explicit `history_path`, independently parses the strict CSV and recomputes source, rows, volume, provider populations, exact count/volume/approval shares, averages and p95 latency. `bin/finalize_submission` always passes its selected history path; compatibility callers that omit it do not get an implicit provenance claim. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_history_analytics_tampering`, semantic 30/136 and public 29/29 finalization.

### S21-H49 — remaining rich report projections — CLOSED / RAW-DERIVED EVIDENCE

The next blind artifact probes forged `period_window.from`, `configuration.weights.count` and the `infeasibility` array. The independent oracle now recomputes the UTC queue period window, binds serialized configuration to raw providers/profile and exact targets/controls, and recomputes infeasibility entries from public hard-forced decision evidence plus independently validated assignment deviations. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_period_window_tampering`, `#test_independent_oracle_rejects_configuration_and_infeasibility_tampering`, semantic 33/145, scale 2/12 and finalization 10/66.

### S21-H50 — serialized submission-profile provenance — CLOSED / RAW-BOUND EVIDENCE

The blind artifact probe mutated `report.submission_profile.profile_id` while leaving all other report values valid; the independent oracle previously accepted the forged identity. It now requires the exact profile projection shape, raw profile identity/source/revision/target-source values and equality between nested profile configuration and the independently validated report configuration. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_submission_profile_identity_tampering`, semantic 34/147; adjacent serialized/finalization evidence remains required after this checkpoint.

### S21-H51 — recommendation presentation provenance — CLOSED / TYPED-EVIDENCE BOUND

The blind artifact probe replaced a valid base recommendation string and rich action with arbitrary non-empty text; the independent oracle previously accepted both. It now recomputes the stable presentation text/action from each supported recommendation kind and typed evidence, while retaining the existing provider/evidence checks. Evidence: `test/case/report_semantic_test.rb#test_independent_oracle_rejects_recommendation_text_tampering`, expanded action mutation coverage, semantic 35/150; full and finalization verification remain required after this checkpoint.

### S21-H52 — canonical Router multi-goal conflict evidence — CLOSED / ROUTER-BOUND

The existing multi-goal evidence changed winners only through a direct synthetic `ConflictResolver` call. An independent probe reproduced a stronger judge-facing case on the same authoritative 10-operation queue/provider snapshot: conversion/load weights `{4, 1}` selected `payflow` for `op_101`, while `{1, 4}` selected `quickpay`. The evidence CLI now adds `router_multi_goal_conflict` using the canonical `Router`, preserving the input binding, exact configuration, first-selection score/factor trace and full assignment distribution. `test/case/evidence_cli_test.rb` covers the reversal and determinism; routing semantics are unchanged.

### S21-H53 — fallback causal explanation evidence — CLOSED / REPORT-BOUND

The fallback evidence surface exposed attempts, outcomes and settlement distribution but omitted the canonical explanation that links the primary selection rationale to failed attempts and the terminal final selection. An independent CLI probe confirmed the omission. The evidence CLI now projects the existing `ReportBuilder#explanations` entry for `op_101`; focused assertions cover provider linkage, failed-attempt coverage, fallback continuation and terminal identity without changing routing or outcome semantics.

### S21-H54 — second Router-bound objective conflict — CLOSED / MULTI-PAIR EVIDENCE

The first Router-bound conflict covered conversion versus load. A fresh authoritative-data probe found a distinct priority versus load reversal on the same queue: `{ priority: 4, load: 1 }` selects `vipay`, while `{ priority: 1, load: 4 }` selects `quickpay` for `op_101`. The evidence CLI now exposes both pairs with exact configurations, first-selection traces and full assignment maps; no routing semantics changed.

### S21-H55 — independent volume target campaign — CLOSED / ROUTER-BOUND

The existing `portfolio_conflict` reused one target map for count and volume, so its strategy difference did not prove independent volume target provenance. A fresh Router probe used count targets `{payflow: 1/5, quickpay: 3/5, vipay: 1/5}` and volume targets `{payflow: 3/5, quickpay: 1/5, vipay: 1/5}` on the same authoritative queue/provider state; both masses are exactly one and the assignment maps differ. The evidence output now labels both synthetic target sources and serializes the independent volume map.

### S21-H56 — Router conflict target provenance — CLOSED / PROFILE-BOUND

The Router-bound multi-goal evidence reused canonical profile targets while varying synthetic weights, but did not label that boundary inside each scenario. It now emits the typed profile count/volume target-source values (`provider.traffic_percentage`) alongside the synthetic weight configuration; selection, accounting and target values are unchanged.

### S21-H57 — Fallback accounting populations — CLOSED / EVIDENCE SURFACE

The fallback evidence exposed attempts, rationale and approved settlement but left primary assignment versus final selected-provider accounting implicit. It now emits an explicit `accounting_populations` block with exact primary, final and settlement distributions/totals plus canonical final outcome counts, reusing the canonical report ledgers and shared provider-ledger primitive without changing production routing semantics.

### S21-H58 — Canonical final-selection report population — CLOSED / REPORT-BOUND

The CLI-only final-selection projection duplicated a small accounting rule because `ReportBuilder` exposed assignment, attempts and settlement but not the aggregate final-selected population. The report now owns `final_selection_distribution` and `final_selection_totals`; the independent semantic validator recomputes them, and the evidence CLI consumes those fields without a second projection. Terminal non-approved cases remain final-selected but never become settlement.

### S21-H59 — Zero-weight Router independence — CLOSED / EVIDENCE-CLOSED

The existing tie-break suite covered disabled priority only. A fresh canonical Router regression now adds each other implemented factor at weight zero beside active conversion scoring and proves winner, positive scores and zero-weight contributions remain unchanged. No allocation or normalization code changed.

### S21-H60 — Fallback selection-factor traces — CLOSED / EVIDENCE SURFACE

The fallback evidence exposed attempts and aggregate rationale but dropped the canonical resolver factors for each primary/fallback pass. It now projects exact per-pass phase, resolver winner, scores and factor contributions from `Attempt#selection`; public decisions and routing semantics remain minimal and unchanged.

### S21-H61 — Amount/conversion Router conflict — CLOSED / JUDGE EVIDENCE

The canonical Router evidence covered conversion/load and priority/load but did not show amount-band preference changing a real Router winner. A deterministic authoritative-data probe found a hard-eligible `op_106` reversal: amount-heavy weights select `quickpay`, while conversion-heavy weights select `vipay`. The evidence CLI now exposes both scenarios with the same queue/providers/profile bands and only the two exact weight maps changed.

### S21-H62 — Bind amount conflict to hard eligibility — CLOSED / JUDGE EVIDENCE

The H61 reversal did not expose the attempted-provider facts needed to distinguish score preference from hard eligibility. The same canonical conflict block now includes `op_106` attempts: `payflow` is skipped for `amount_exceeds_limit`, while `vipay` and `quickpay` remain the exact score candidates in both weight scenarios.

### S21-H63 — Common positive weight-scale invariance — CLOSED / ROUTER REGRESSION

The scoring audit contract required common positive weight scaling to be exercised at the actual Router call site, but the existing evidence covered only weight conflicts and zero-weight independence. A deterministic regression now proves that scaling conversion/load weights from `{1, 1}` to `{3, 3}` preserves the winner, raw/normalized/reason evidence and exact score/contribution scaling.

### S21-H64 — Optional intensity/turnover Router evidence — CLOSED / JUDGE EVIDENCE

Direct factor probes showed optional inputs but not stateful canonical Router behavior. `router_optional_factor_conflicts` now runs four fresh synthetic Case Router scenarios: intensity-vs-conversion and turnover-vs-conversion, with a warmup operation proving canonical state mutation and hard amount exclusion before `a`/`b` are both score candidates on the conflict operation. Synthetic scope remains explicit; canonical submission profile policy is unchanged.

### S21-H65 — Fallback causal attempt chain — CLOSED / EVIDENCE SURFACE

The fallback evidence exposed attempts, selection traces and report explanation as parallel structures, forcing a judge/operator to infer the causal sequence. `fallback_and_analytics.causal_chain` now joins the existing canonical attempts and traces in order, explicitly distinguishing resolver selection from terminal policy, provider outcome reason and approved settlement. No public decision DTO, routing authority or ledger changed.

### S21-H66 — Additional-provider target/status boundary — CLOSED / JUDGE EVIDENCE

The repository had hidden-like additional-provider and status tests, but the runnable judge surface did not show them. `router_provider_boundary` now runs the official queue through fresh canonical Router instances with an executable active `newpay` provider and an `enabled` zero-participation shadow, exposing exact provider-derived targets, selection, hard exclusion and provider-order invariance. No production policy was changed.

### S21-H67 — Router conflict evidence operation identity — CLOSED / EVIDENCE HONESTY

A blind output audit found that `router_multi_goal_conflict.selected_provider` described the first queue operation (`op_101`) while the adjacent conflict block described `op_106`; the two values diverged in amount/conversion scenarios and the unlabeled field could misstate the claimed winner. The evidence now labels `first_operation` and the conflict `scenario` separately, with a focused assertion that the scenario provider matches the canonical conflict decision. Routing semantics and production DTOs are unchanged.

### S21-H68 — hidden-like Case scale probe — EVIDENCE-CLOSED / NO REGRESSION

A fresh performance probe extended the existing strict 1,000-operation campaign to 3,000 operations across five providers, including an additional active provider, and rebuilt the Router/report path from fresh inputs. It completed in `2.56s`, produced 3,000 decisions and passed `StrictValidator`; the existing serialized semantic campaign remains covered at 1,000 operations. No material quadratic or determinism defect was reproduced, so no cache/index or production refactor is justified.

### S21-H69 — canonical report factor trace — CLOSED / CAUSAL EXPLANATION

A blind report audit found that serialized `explanations[*].considered` exposed aggregate resolver scores but omitted the canonical raw/normalized/weight/contribution/reason factors already present on `Attempt#selection`; operators and judges could see who won without seeing which configured objectives mattered. Report explanations now carry those canonical factor traces without changing the minimal decision DTO or selection authority. The independent semantic validator checks supported unique factors, exact arithmetic, `contribution = normalized * weight`, provider coverage and score-contribution sums; a serialized contribution mutation is rejected. Finalization regenerates and tracks the report artifact through the existing manifest guard.

### S21-H70 — empty canonical factor evidence — CLOSED / FAIL-CLOSED ORACLE

A shape-valid boundary probe found that a provider with an aggregate score of exact `0/1` could carry an empty serialized factor array and still pass the independent semantic oracle: the empty contribution sum coincided with the score. The oracle now requires non-empty factor evidence for every considered provider before checking contribution arithmetic. A deterministic `op_103` mutation regression rejects the forged empty trace; canonical report generation and routing semantics remain unchanged.

### S21-H71 — canonical causal-chain projection — CLOSED / SINGLE REPORT AUTHORITY

A code-first surface audit found that the runnable evidence CLI reconstructed the ordered hard-gate/resolver/fallback/terminal chain separately, while the canonical report exposed only parallel explanation fragments. `ReportBuilder` now emits one typed `causal_chain` per operation, including phase, authority, resolver identity, outcome and settlement facts; the evidence CLI projects that chain instead of rebuilding it. The independent semantic oracle checks chain coverage, provider/decision identity, lifecycle phase, authority, outcome linkage and terminal/hard-gate semantics. Focused fallback, serialized and evidence regressions preserve the existing primary/final/settlement separation.

### S21-H72 — canonical weight-effect comparison — CLOSED / JUDGE DELTA EVIDENCE

A blind judge-surface probe confirmed that the Router's conversion/load, priority/load and amount/conversion scenarios changed real selected providers, but the full selected-provider maps hid the causal deltas and one focus operation stayed unchanged in the conversion/load pair. The evidence CLI now adds deterministic pairwise `comparisons.changed_operations` derived only from the already-run canonical scenario outputs, with left/right scenario and provider identities. It does not select providers or alter routing; the evidence regression binds the three deltas to the real Router outputs.

### S21-H73 — resolver reason/winner auditability — CLOSED / INDEPENDENT ORACLE HARDENING

A shape-valid artifact probe changed a resolver `causal_chain[*].selection_reason` from `highest_composite_score` to the supported `fallback_highest_composite_score`; the semantic oracle accepted it because vocabulary and lifecycle linkage were checked but score winner/reason semantics were not. The oracle now independently recomputes the selected winner from exact serialized score traces, applies the deterministic provider-id tie-break, derives primary/fallback/only-candidate reason semantics and rejects mismatches. Router/DTO/report allocation semantics are unchanged; the regression covers the forged resolver reason.

### S21-H74 — per-delta multi-goal traces — CLOSED / JUDGE CAUSAL EVIDENCE

A judge-surface probe found that H72's changed-operation deltas proved provider movement but required manual lookup of unrelated first/focus traces to inspect why each operation moved. Each deterministic comparison now carries both scenario weights and the exact canonical resolver selection trace for every changed operation, linked to its left/right selected provider. The evidence CLI still projects existing Router runs and does not choose providers or add a second scoring path.

### S21-H76 — controlled multi-goal comparison invariant — CLOSED / EXPERIMENT FIDELITY

A fresh audit found that H74 showed paired traces but the regression did not explicitly assert that each comparison held dataset, targets, provider capabilities, amount bands and simulation controls constant. The evidence test now independently compares every Router scenario configuration after removing only `weights` and per-scenario provenance `source`; any accidental policy/input drift fails the judge evidence. No runtime routing behavior changed.

### S21-H77 — clean-checkout public release rehearsal — CLOSED / RELEASE EVIDENCE

A detached clean worktree at exact `f45ce34` passed `bundle check`, explicit public-queue finalization and `--verify-committed`: all `29/29` organizer checks passed, the manifest hashes matched the committed root bytes, the worktree was clean and its SHA matched the pushed `main`. This strengthens reproducibility without closing S21-H9's separate hidden-queue freshness obligation.

### S21-H78 — factor raw/normalized trace integrity — CLOSED / INDEPENDENT ORACLE

A blind artifact probe changed one serialized `conversion_24h.raw` value from `87/100` to `0/1` while leaving `normalized` and `contribution` untouched; the independent semantic oracle previously accepted the shape-valid report. The oracle now checks each supported factor against its fixed exact normalization domain (`[-2,0]` for count/volume and `[0,1]` for other built-ins), requires the canonical scaled value when raw values discriminate, and requires neutral `0` when all raw values are equal. A focused regression rejects the forged trace. This validates internal factor evidence consistency only; it does not claim to independently reimplement raw provider-factor semantics. The pushed implementation checkpoint is `bec04d6`; exact public finalization on the later docs-synchronized head `fc5b2f7` passed `29/29` with committed-byte parity and clean status.

### S21-H79 — factor weight provenance — CLOSED / INDEPENDENT ORACLE

A second blind artifact probe redistributed serialized factor weights and contributions (`count 2→0`, `volume 2→4`) while preserving the aggregate score, raw/normalized values and report shape; the independent oracle previously accepted the forged causal story. It now binds factor keys and exact weights to the canonical configuration, using the canonical causal phase to allow count/volume omission only in fallback traces. A focused regression rejects the compensated mutation. The pushed implementation checkpoint is `e51d151`; exact public finalization on docs-synchronized `fc5b2f7` passed `29/29`; this closes trace-to-configuration provenance only and does not turn the report oracle into a second routing chooser.

### S21-H80 — factor reason provenance — CLOSED / INDEPENDENT ORACLE

A blind artifact probe replaced a canonical `conversion_24h` factor explanation with unrelated non-empty text while leaving raw, normalized, weight, contribution and aggregate score unchanged; the independent oracle previously accepted the forged causal narrative. It now derives the expected reason from the exact serialized raw value, provider snapshot and configuration context for every built-in factor, including the explicit non-discriminating suffix, and rejects reason mismatches. `test/case/report_semantic_test.rb#test_independent_oracle_rejects_factor_reason_tampering` is the deterministic regression. The implementation checkpoint is `ed7b14e`; this binds rich reason text to existing canonical factor semantics without adding a chooser or changing routing behavior. Exact public finalization rerun on docs-synchronized `44767af` passed `29/29`, with committed-byte parity and a clean worktree; exact-head Actions remains externally unresolved because GitHub's check-runs endpoint returns HTTP 404.

### S21-H81 — recommendation cause provenance — CLOSED / INDEPENDENT ORACLE

A blind artifact probe changed the nested `hard_exclusions` count inside a valid `count_target_unmet` recommendation from the independently derived value to `999`; the oracle previously accepted the shape-valid recommendation because it checked target/actual/gap but not the richer `causes` block. The validator now binds count/volume recommendation causes to the independently validated provider `deviation_causes` projection, and `test/case/report_semantic_test.rb#test_independent_oracle_rejects_recommendation_cause_tampering` rejects the forged evidence. The implementation checkpoint is `85497b1`; routing and recommendation policy remain unchanged. Exact public finalization, docs synchronization and exact-head CI remain required after this checkpoint.

### S21-H82 — recommendation kind eligibility — CLOSED / INDEPENDENT ORACLE

A blind artifact probe re-labeled a valid recommendation as `count_target_unmet` for `quickpay`, whose actual count was not below target, and set the resulting zero gap while preserving typed fields and canonical presentation. The independent oracle previously accepted the semantically impossible recommendation because it compared values but did not require the kind's positive-deficit predicate. It now requires strictly positive recomputed count/volume deficits for `count_target_unmet` and `volume_target_unmet`; `test/case/report_semantic_test.rb#test_independent_oracle_rejects_recommendation_kind_eligibility_tampering` is the deterministic regression. The implementation checkpoint is `039b4bf`; routing and recommendation generation remain unchanged. Exact public finalization, docs synchronization and exact-head CI remain required after this checkpoint.

### S21-H83 — hard-forced recommendation semantics — CLOSED / INDEPENDENT ORACLE

A blind artifact probe re-labeled a below-target `payflow` recommendation as `target_infeasible_hard_forced` while preserving typed targets and exact presentation; the independent oracle previously accepted it because it did not require positive hard-forced evidence plus an over-target deviation. It now binds `hard_forced_assignments` to independently validated deviation causes and requires a positive hard-forced count with a positive count or volume deviation. `test/case/report_semantic_test.rb#test_independent_oracle_rejects_hard_forced_kind_without_over_target_condition` is the deterministic regression. The implementation checkpoint is `5afce90`; routing and recommendation generation remain unchanged. Exact public finalization, docs synchronization and exact-head CI remain required after this checkpoint.

### S21-H84 — structural recommendation evidence — CLOSED / INDEPENDENT ORACLE

A blind artifact probe changed only `structurally_constrained_under_target.evidence.hard_excluded_operations` to `999`; the independent oracle previously accepted the rich recommendation because it checked target/gap fields but not hard-rule counts, reason maps or capacity counterfactuals. It now recomputes excluded operations, hard-exclusion reasons, hard-eligible count/volume and count/volume unattainable dimensions from raw queue plus serialized decisions and validated distributions. `test/case/report_semantic_test.rb#test_independent_oracle_rejects_structural_recommendation_evidence_tampering` is the deterministic regression. The implementation checkpoint is `6438619`; malformed decision shapes remain fail-closed. Exact public finalization, docs synchronization and exact-head CI remain required after this checkpoint.

### S21-H85 — terminal recommendation semantics — CLOSED / INDEPENDENT ORACLE

A blind artifact probe relabeled a valid recommendation as `terminal_fallback_deviation` for `spacepayments` while keeping terminal assignments at zero, the provider distribution non-positive and the hard-exclusion evidence empty; the independent oracle previously accepted the shape-valid forged advice. The validator now binds terminal assignment counts to independently validated deviation causes, recomputes hard-excluded alternatives from serialized terminal decision attempts, requires the configured terminal provider and requires a positive terminal fallback count plus an over-target count or volume deviation. `test/case/report_semantic_test.rb#test_independent_oracle_rejects_terminal_kind_without_terminal_fallback` is the deterministic regression; canonical terminal fallback recommendations still pass the Case matrix. The implementation checkpoint is `de941c2`; exact public finalization, docs synchronization, fresh full verification and exact-head CI remain required.

### S21-H86 — daily recommendation threshold semantics — CLOSED / INDEPENDENT ORACLE

A blind artifact probe relabeled a provider at `65.34%` daily utilization as `daily_utilization_near_limit` and forged a `0/1` utilization ratio; the independent oracle previously checked used/limit/remaining but accepted the impossible kind predicate. It now recomputes the exact ratio from projected used/limit, binds the evidence ratio and requires the same `>= 9/10` threshold as recommendation generation. `test/case/report_semantic_test.rb#test_independent_oracle_rejects_daily_limit_kind_without_near_limit_utilization` is the deterministic regression; the real `payflow` near-limit recommendation remains valid. The implementation checkpoint is `fa8e321`; fresh full verification, finalization, docs synchronization and exact-head CI remain required.

### S21-H87 — count workload recommendation semantics — CLOSED / INDEPENDENT ORACLE

A blind artifact probe relabeled `payflow` as `workload_granularity` with a fractional target count of `3.5`, actual count `1` and hard exclusions; the independent oracle previously checked only queue size, target and actual fields, so it accepted a non-granularity explanation. It now binds attainable floor/ceil counts and requires a fractional target, actual count at one of those bounds, zero hard exclusions and zero hard-forced assignments. `test/case/report_semantic_test.rb#test_independent_oracle_rejects_workload_kind_without_count_granularity_condition` is the deterministic regression; canonical workload recommendations remain valid. The implementation checkpoint is `68cc416`; fresh full verification, finalization, docs synchronization and exact-head CI remain required.

### S21-H88 — volume workload recommendation semantics — CLOSED / INDEPENDENT ORACLE

A blind artifact probe relabeled `payflow` as `volume_workload_granularity` with a large target gap and hard exclusions; the independent oracle previously checked only queue totals and target/actual volume, so it accepted an explanation that could not be caused by whole-operation granularity. It now binds the absolute target volume, exact gap, minimum operation amount and requires a positive gap smaller than that minimum with zero hard exclusions and zero hard-forced assignments. `test/case/report_semantic_test.rb#test_independent_oracle_rejects_volume_workload_kind_without_small_gap_condition` is the deterministic regression; canonical custom-queue finite-workload reports remain valid. The implementation checkpoint is `b782c9f`; fresh full verification, finalization, docs synchronization and exact-head CI remain required.

### S21-H89 — subset-sum recommendation semantics — CLOSED / INDEPENDENT ORACLE

A blind artifact probe relabeled an already-over-target `quickpay` distribution as `volume_subset_sum_granularity`, forging nearest attainable values and a search bound; the independent oracle previously checked only queue totals and target/actual volume. It now runs an independent bounded exact subset-sum reachability calculation, binds the configured operation/volume bound and nearest below/above values, and requires a positive unreachable integer target gap with no hard exclusions, hard forcing or fallback assignments. `test/case/report_semantic_test.rb#test_independent_oracle_rejects_subset_sum_kind_without_unreachable_target` is the deterministic regression; the authoritative bounded subset-sum Case fixture remains valid. The implementation checkpoint is `71725d2`; fresh full verification, finalization, docs synchronization and exact-head CI remain required.

### S21-H90 — recommendation set completeness — CLOSED / INDEPENDENT ORACLE

A blind artifact probe removed one valid recommendation/detail pair while preserving equal array cardinality and leaving all remaining typed entries valid; the independent oracle previously accepted the incomplete report. It now independently recomputes the expected `(provider, kind)` recommendation set from raw operations, serialized decisions, distributions, deviation causes and utilization, rejects duplicates and rejects omissions/additions. The scale campaign exposed and corrected one oracle denominator mistake (`target_share * operation_count` versus the share itself), proving the completeness check against five-provider/1,000-operation artifacts. `test/case/report_semantic_test.rb#test_independent_oracle_rejects_omitted_recommendation_detail` is the deterministic regression; implementation checkpoint `d8b0d4b`.

### S21-VER-2026-09-05 — fresh exact-head closure verification

The docs-synchronized exact HEAD `dff7ac8` passed full `rake test` (`943/14435`), property (`4/1210`), model (`3/2958`), concurrency (`45/1444`), fault (`407/4900`) and Case (`203/1474`) matrices with zero failures/errors/skips. `bundle check`, explicit public finalization plus `scripts/validate_10.rb` passed `29/29`; manifest hashes matched tracked root artifacts, the clean-checkout rehearsal was clean, and the evidence CLI and demo were byte-deterministic. Exact-head GitHub Actions remains unresolved because the check-runs API returns HTTP 404 for this repository/SHA.

### S21-H91 — Router preference monotonicity — EVIDENCE-CLOSED / METAMORPHIC

A code-first scoring audit found that the current Router path covered zero-weight independence, provider-order/scale perturbations and factor winner examples, but did not directly prove monotonicity when one hard-eligible provider's preference input improves. A fresh Router campaign now compares paired runs for priority, amount band, conversion, load, turnover-min and stateful rolling intensity. Each improved scenario changes only provider `a`'s relevant input, proves its exact raw trace increases where observable, and proves the winner cannot worsen (`b → a`); intensity uses three ordered operations to preserve the real RPM state mutation and hard gate. `test/case/monotonicity_test.rb#test_router_preference_factors_do_not_make_an_improved_provider_worse` passes with `1/17`; adjacent factor, normalization, tie-break, strategy and evidence CLI suites remain green. Count/volume are intentionally covered by their separate post-decision portfolio-loss oracle because ledger mutation changes both candidates' objective context; no production routing change is justified. On exact pushed HEAD `dff7ac8`, the fresh matrix also passes: full `rake test` `943/14435`, property `4/1210`, model `3/2958`, concurrency `45/1444`, fault `407/4900`, Case `203/1474`, all with zero failures/errors/skips; finalization and organizer validation remain green `29/29` with unchanged manifest hashes.

### S21-VER-2026-09-05 — product-evidence workflow revalidation

The current CI product-evidence commands were rerun locally on CRuby 4.0.6: `benchmark` completed the pure allocation, lifecycle, service and fact-replay probes; `load_10k` completed 10,000 coordinator lifecycles in `24.6461s`; `degradation_metrics` completed the seeded 2,000-payout campaign with `2,247` attempts and `228` successful fallbacks; `history_profile` completed the documented bounded 100/250/500 samples and concurrent 500-payout probe; and `ruby -Ilib bin/ruby_routing_demo` passed. These are bounded measurements, not a 100k benchmark claim. No material performance or determinism defect was reproduced, so no cache/index or production refactor is justified.

### S21-H92 — fallback zero-weight independence — EVIDENCE-CLOSED / ALTERNATE PATH (superseded for positive allocation weights)

A blind scoring audit identified an uncovered call-site class: primary-path zero-weight tests did not prove that disabled factors stayed inert after a rejected primary entered the canonical fallback phase. A fresh Router metamorphic campaign now compares the same `a rejected → c approved` cascade with each of `count`, `volume`, `amount`, `conversion_24h`, `load`, `intensity` and `turnover_min` added at weight zero. The fallback provider, attempt/reason sequence and phase scores remain identical (`1/62`); zero-weight factors retain zero contribution. The positive-weight allocation-factor clause in this historical finding is superseded by S21-H102, which reuses count/volume in fallback against the uncommitted final ledger. Focused fallback, tie-break, factor, normalization and evidence suites remain green.

### S21-H93 — fallback provider-enumeration invariance — EVIDENCE-CLOSED / CASCADE REGRESSION

A blind execution-path audit found that provider-order evidence covered approved and additional-provider campaigns but did not directly cover a rejected-primary fallback cascade with its lifecycle facts. A fresh Router regression now runs the same `a rejected → c approved` case from canonical and reversed provider enumerations and compares ordered attempted-provider identities, public reasons, exact primary/fallback resolver traces, final provider, assignment population, attempt ledger and settlement ledger. The runs are identical; no production change is justified. Evidence: `test/case/fallback_order_invariance_test.rb`, focused `1/6`, adjacent fallback `2/13` and evidence CLI `2/322`.

### S21-VER-2026-09-05-9ab75a3 — exact pushed-head revalidation

On pushed checkpoint `9ab75a3`, fresh full `bundle exec rake test` passed `945 runs / 14504 assertions` with zero failures/errors/skips. The explicit public finalizer regenerated byte-identical root artifacts, `scripts/validate_10.rb` passed `29/29`, manifest hashes remained `0611eecd…` for the queue, `88715ccf…` for decisions and `d3acf588…` for the report, and `git diff` confirmed no generated drift. The clean-checkout rehearsal on the same checkpoint passed `bundle check`, finalization, public validation and clean worktree. The exact check-runs endpoint remains external/unavailable (`404`); no GitHub Actions success is claimed.

### S21-VER-2026-09-05-87308eb — exact pushed-head closure revalidation

The exact pushed code/docs tree `87308eb` passed fresh local closure verification: full `bundle exec rake test` `945/14505`, property `4/1210`, model `3/2958`, concurrency `45/1445`, fault `407/4900` and Case `205/1542`, all with zero failures/errors/skips. `bundle check`, explicit public finalization with `--verify-committed`, `scripts/validate_10.rb` `29/29`, manifest/byte parity, tracked root artifacts and a detached clean-checkout rehearsal all passed. Exact-head GitHub check-runs still return `404` after the Actions plan/infrastructure became unavailable; no green Actions result is claimed.

### S21-H94 — Case routing-weight insertion-order determinism — CLOSED / CANONICAL ARTIFACT EVIDENCE

A code-first boundary probe constructed two semantically identical exact weight maps with reversed Hash insertion order. Provider selections remained equal, but the pre-fix Case configuration key order, resolver factor traces and serialized report bytes differed; this made equivalent transport/configuration inputs produce different judge artifacts. `RoutingWeights` now re-emits validated factors in the explicit `FactorRegistry::DEFINITIONS` order while preserving duplicate-key and exact Integer/Rational validation. `test/case/weight_order_determinism_test.rb` proves equal canonical configuration, decisions, report values and serializer bytes across both inputs. Full `bundle exec rake test` passed `946/14510`; property `4/1210`, model `3/2958`, concurrency `45/1453`, fault `407/4900` and Case `206/1548` also passed with zero failures/errors/skips. On pushed `7580067`, explicit public finalization and `scripts/validate_10.rb` passed `29/29`, `--verify-committed` confirmed manifest hashes, generated root artifacts stayed byte-identical and the worktree remained clean. This is a Case artifact determinism correction only; no production routing/economic semantics changed.

### S21-VER-2026-09-05-7580067 — exact pushed-head release revalidation

The exact code checkpoint `7580067` is pushed and equals `origin/main`. Local release verification passed `bundle check`, explicit public-queue finalization, public validation (`29/29`), committed-byte parity and clean status. The queue/decision/report SHA-256 values remain `0611eecd…`, `88715ccf…` and `d3acf588…`. GitHub Actions/check-runs remain an external unavailable gate: the repository/commit API returns HTTP `404` under the current account/plan, so this record makes no claim of green Actions.

### S21-H95 — provider-keyed Case configuration map determinism — CLOSED / CANONICAL ARTIFACT EVIDENCE

A follow-up code-first probe reversed equivalent provider-keyed maps for `preferred_amount_ranges`, `min_turnovers` and `rpm_limits`. Before the fix, selection and report values were equal but report bytes differed because `CaseConfiguration` preserved caller insertion order. The typed configuration boundary now emits these maps in sorted canonical `provider_ids` order; exact values, unknown-provider rejection, duplicate canonical identities and hard/soft routing semantics are unchanged. The second regression in `test/case/weight_order_determinism_test.rb` proves equal canonical configuration, decisions, report values and serializer bytes. The public report was regenerated by `bin/finalize_submission`, not edited manually. Pushed checkpoint `a5a61f6` passes full `bundle exec rake test` `947/14518`, property `4/1210`, model `3/2958`, concurrency `45/1448`, fault `407/4900` and Case `207/1555`, all with zero failures/errors/skips. Exact finalization/public validation passed `29/29`; manifest hashes are queue `0611eecd…`, decisions `88715ccf…`, report `5e466e754b83f043…` and committed-byte parity is clean.

### S21-VER-2026-09-05-a5a61f6 — exact pushed-head release revalidation

The exact pushed `main` checkpoint `a5a61f6` equals `origin/main`. `bundle check`, explicit public-queue finalization with `--verify-committed`, `scripts/validate_10.rb` (`29/29`), tracked root artifact parity and the full inherited matrix passed. GitHub Actions/check-runs remain unavailable with HTTP `404` under the current account/plan; this is not reported as green CI.

### S21-H96 — direct resolver policy provenance — CONFIRMED / MINIMAL CANONICAL FIX

A blind alternate-entrypoint probe constructed `Router.new(..., resolver:)` with exact amount bands and turnover minima. The resolver used those policies for selection, but the Router-created `CaseConfiguration` discarded them and serialized only the resolver weights. This allowed a real routing decision to depend on policy data absent from the canonical configuration/report surface. `ConflictResolver` now exposes its validated typed policy maps, and the direct Router path carries them into `CaseConfiguration`, preserving canonical provider ordering and unknown/duplicate/exact validation. The existing profile/configuration authorities and production kernel are unchanged. Evidence: `test/case/router_resolver_authority_test.rb` proves weights, preferred amount ranges, minimum turnovers and configuration serialization agree on the direct path; adjacent configuration, factor, fallback, profile, validator and determinism suites pass. Public finalization does not change because it uses the canonical profile path. Pushed checkpoint `398d2b1` passed full test (`949/14522`), property (`4/1210`), model (`3/2958`), concurrency (`45/1452`), fault (`407/4900`) and Case (`209/1563`) matrices; clean-checkout finalization and `29/29` public validation reproduced byte-identical root artifacts. The exact-head Actions check remains an external HTTP `404` after the account plan/infrastructure ended.

### S21-H97 — final distribution and human-readable decision evidence — CONFIRMED / MINIMAL REPORT FIX

The fallback reproducer showed that organizer-facing `distribution` was still primary-assignment data even though `final_selection_distribution` and `settlement_distribution` already preserved the later populations. The base `distribution` now projects the final selected provider for every operation; `assignment_distribution` remains the primary population and approved-only settlement remains explicit. The same report explanation now carries a short deterministic `decision_summary` derived only from its existing causal chain, and the independent semantic validator recomputes/rejects summary tampering. Evidence: accounting, runner and semantic suites pass; public finalization regenerates the report through the canonical path.

### S21-H98 — compact multi-goal judge demo — EVIDENCE-CLOSED / ROUTER PRIMITIVE

`bin/judge_demo` is a deliberately bounded one-operation demonstration of the existing `ConflictResolver`: identical providers/input, conversion-heavy weights select PayFlow, load-heavy weights select QuickPay, and the output shows exact conversion/load contributions plus the reason for the change. It adds no routing authority, strategy or test-only semantics.

### S21-H99 — actual submission release command — CONFIRMED / FAIL-CLOSED PATH

The public queue was still the default of the `rake finalize_submission` task. The task now targets literal `operations_queue_test.json`, requires that basename even when staged via `SUBMISSION_QUEUE`, passes `--verify-committed`, and fails non-zero when the actual queue is absent or any generated/validated/HEAD byte check fails. Public `operations_queue_10.json` remains available only through the explicit `finalize_public_submission` smoke task; CI uses that explicit public task and cannot silently masquerade as actual submission.

### S21-H100 — fallback analytics population drift — CONFIRMED / MINIMAL REPORT FIX

A deterministic rejected-primary → approved-fallback reproducer showed that compact `distribution` had already moved to final-selected providers, while `deviation_causes`, `infeasibility` and `recommendation_details` still used primary assignments. The public artifact therefore reported final QuickPay `70%` / target `25%` but explained a primary QuickPay `50%`, and treated final VipPay `20%` as if its primary `40%` were on target. The report now derives exact final target/deviation fields once and uses that population for all target analytics; primary assignment remains explicitly available in `assignment_distribution`. The semantic validator follows the same contract and independently checks final target/deviation fields. Evidence: `test/case/accounting_semantics_test.rb#test_target_causes_and_recommendations_use_the_final_population`, report semantic suite, public finalization and `scripts/validate_10.rb` `29/29`.

The actual `operations_queue_test.json` is still not present in this checkout. This is a submission-input availability gap, not permission to substitute the public fixture: `rake finalize_submission` remains fail-closed and the tracked root `_test` artifacts remain explicitly public-smoke output until the real queue is supplied.

### S21-H101 — online target ledger population drift — CONFIRMED / MINIMAL ROUTER FIX

A code-first fallback reproducer confirmed a second, deeper population split after H100: `ReportBuilder#distribution` and final analytics were final-selected, but the live `Router#traffic` ledger still recorded the first primary provider before simulation. Thus a rejected `VipPay -> QuickPay` cascade influenced later count/volume decisions as if VipPay had received the operation, while final report analytics described QuickPay. This was not a harmless presentation distinction because the next primary resolver consumed the mutated ledger.

The Router now keeps `primary_assignment_ledger` for the first selected attempt and commits `traffic` only once for the final selected provider: after an approved external attempt or after terminal selection. Rejected/expired external attempts do not mutate the target ledger. Primary and fallback reuse the same weighted resolver, so count/volume evaluate the current operation against the uncommitted final ledger without double-counting the rejected primary. Stateful replay, strict conservation and report projection use the same two explicit populations. `test/case/accounting_semantics_test.rb#test_next_primary_resolution_observes_final_target_ledger_after_fallback` independently compares the next count-factor raw value against final-ledger and legacy-primary calculations; fallback phase/order, runner and traffic tests cover the adjacent boundaries. This is a Case routing/accounting correction only; production UNKNOWN/economic ownership and settlement semantics are unchanged.

The actual `operations_queue_test.json` remains unavailable, so no public fixture is promoted to the actual submission path. Public artifacts must be regenerated only through the explicit public smoke task until the authoritative queue arrives.

Fresh local evidence for H101 is green: full `rake test` `952/14557`, property `4/1210`, model `3/2958`, concurrency `45/1451`, fault `407/4900` and Case `212/1595`, all with zero failures/errors/skips. Public finalization regenerated the report through the canonical Router and organizer validation passed `29/29`; evidence and demo outputs were byte-deterministic. Committed-byte parity is intentionally rerun after this checkpoint is committed.

### S21-H102 — fallback reuses final-ledger count/volume objectives — CONFIRMED / MINIMAL ROUTER FIX

A deterministic three-provider reproducer confirmed that fallback previously removed positive `count` and `volume` weights, allowing a priority-favored provider to beat the portfolio objective. Primary and fallback now reuse the same weighted resolver against the uncommitted final ledger; the rejected primary remains only in the primary-assignment ledger. Focused fallback/accounting/zero-weight regressions and the full local matrix are green.

### S21-H103 — optional load/RPM absence is non-discriminating — CONFIRMED / MINIMAL FACTOR FIX

A focused boundary campaign confirmed that absent capacity/RPM policy could look like a disadvantage or a sole configured preference. Missing dimensions are now non-discriminating; partial load averages only supplied dimensions, and explicit zero remains typed no-headroom evidence. Focused load/intensity/semantic validation regressions and the full local matrix are green.

### S21-H104 — zero traffic target is soft, terminal identity is explicit — CONFIRMED / MINIMAL BOUNDARY FIX

The TZ-aligned reproducer showed that an active external `traffic_percentage == 0` provider was hard-skipped as `zero_participation`, despite traffic percentage being a soft target. The fix removes the hard gate and the hidden `Provider#self_provider?` terminal inference. The explicit `terminal_provider_id` now solely defines terminal role; count/volume prefer positive-target providers when available, while the active zero-target provider remains a safe fallback after hard exclusions. Non-active providers remain hard-excluded and positive direct targets for them remain rejected.

Evidence: `test/case/state_test.rb#test_zero_target_active_provider_is_not_a_hard_exclusion`, `test/case/terminal_identity_test.rb#test_zero_target_active_provider_is_counted_as_a_soft_goal_and_can_be_fallback`, terminal-causality/profile/evidence regressions and focused serialized validation. Public artifacts are expected to remain unchanged because the canonical terminal already has explicit identity and zero target.

The H101 wording above predates the fallback-objective correction now recorded in the active plan: current behavior and current tests use the same weighted resolver in both phases; the rejected primary remains only in the primary-assignment ledger.

### S21-VER-2026-09-06-b5daa0a — exact pushed-head H101 verification

Checkpoint `b5daa0a117499f08f49efd5a073566a5c5bb440e` is pushed on `main`; local `HEAD` equals `origin/main`. Post-push `finalize_public_submission` passed `29/29` with `committed_head_verified=true`; queue, decisions and report manifest digests were `0611eecd…`, `88715ccf…` and `18ef6f7f…`. The actual `operations_queue_test.json` is still absent, and the exact GitHub check-runs endpoint returns HTTP `404`, so no Actions success is claimed.

## Rule

A newly discovered higher-impact P0/P1 immediately outranks these hypotheses. A hypothesis is CLOSED only with current code/artifact evidence or an explicit falsification record, not because a plan says it is done.
