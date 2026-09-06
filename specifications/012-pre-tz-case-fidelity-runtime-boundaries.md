# SPEC-012 — Pre-TZ Case Fidelity & Runtime Boundary Finalization

Status: VERSION_COMPLETE.

Version Goal: **v0.3.8 — Case Fidelity & Runtime Boundary Finalization**.

Opening HEAD: `b970c31a62c442dd96e52b8dfc6e31598fe2aa6b`.

Candidate implementation checkpoint: `aab25d1756a7028638b88f9c188674617535136a`.

Candidate closure checkpoint: `9377dc156b2117c82be2bb92261957451fe32bad`; exact-head Actions run `33670750287` is green. Final status/docs closure is verified on the current pushed HEAD.

Protected baseline: v0.3.7 / SPEC-011 is `VERSION_COMPLETE`. Its validated material SHA is `8e10df1a47f5f96e346bd5c0ffb7f7d7dba29a7c`; final documentation/evidence closure HEAD is `b970c31a62c442dd96e52b8dfc6e31598fe2aa6b`; exact-head Actions run `33657465337` is green.

## 1. Purpose

Close the last high-value generic pre-TZ gaps that remain after v0.3.7 without reopening the proven routing/economic kernel or inventing official-provider semantics.

v0.3.8 is intentionally narrow. It must improve case fidelity, runtime boundary honesty and operator safety. It is not a reason to add more routing strategies, distributed infrastructure or speculative optimization.

## 2. Public-case objective

The solution must remain visibly strong against the public case:

- configurable distribution by payout count and payout volume;
- fallback to the next suitable provider when it is economically safe;
- conservative handling when a previous provider may still have moved money;
- complete attempt history;
- target/actual and success/fallback analytics;
- an operator/judge surface that demonstrates those capabilities through the same canonical application path.

## 3. Protected invariants

Preserve unless a new deterministic counterexample proves a defect:

1. one submission is one economic intent;
2. at most one unresolved economic owner exists per payout;
3. ambiguous-after-possible-send remains UNKNOWN without stronger semantics;
4. UNKNOWN does not permit fresh cross-provider money movement;
5. provider-local idempotency is not cross-provider idempotency;
6. provider I/O stays outside Coordinator/configuration locks;
7. primary assignment, recovery attempts and settlement are separate accounting views;
8. money/allocation arithmetic stays exact Integer/Rational;
9. routing/admission/allocation authority precedes optimization;
10. restart/replay preserves durable economic/causal state;
11. HTTP/demo/recovery/configuration surfaces remain adapters over Service/Commands/Queries/RecoveryExecutor;
12. active configuration and durable payout history remain distinct authorities;
13. v0.3.7 causal-release behavior remains conservative until an authoritative provider contract proves stronger semantics.

## 4. Mandatory P1 hypotheses

### S12-001 — Provider execution boundary is narrower than application classification

Opening evidence: `Orchestrator#invoke_provider` wrapped `StandardError` from a block containing both `provider.public_send` and subsequent transport/result classification. Therefore an application-side classifier/validation failure after the adapter returned could be mislabeled as `ProviderExecutionError`, which `RecoveryExecutor` intentionally treats as a resumable per-item provider failure. Candidate evidence is the narrowed rescue plus the exact regressions listed below.

Required behavior:

- raw exceptions raised by the executable adapter call may be wrapped as typed provider execution failures;
- once the adapter has returned, application classification/validation/programming failures must not silently become routine resumable provider errors;
- malformed provider return values may use an explicit provider-contract failure type if useful, but that class must have deliberate fail/continue semantics rather than inheriting them accidentally;
- interaction guards still release safely on all exceptions;
- no provider exception text leaks through the public recovery surface;
- exact payout owner/status/facts remain safe after each failure class.

Candidate evidence: `OrchestratorSimulatorTest#test_malformed_provider_observation_surfaces_without_synthetic_unknown`, `RecoveryExecutorTest#test_post_return_provider_validation_failure_aborts_instead_of_becoming_an_item_error` and `OrchestratorSimulatorTest#test_raw_adapter_timeout_is_not_guessed_as_definitely_not_sent`.

### S12-002 — Due-work read surface is bounded

Opening evidence: `Queries#due_work` supported `limit`, `POST /v1/recovery/run` was capped at 256, but `GET /v1/recovery/due-work` accepted only `as_of` and serialized the entire due set. Candidate evidence is the bounded HTTP projection and exact limit/parser regressions listed below.

Required behavior:

- product-facing due-work inspection is bounded by default and by a hard maximum;
- malformed, negative, duplicate or over-limit controls fail before expensive work;
- read bounding must not change recovery ordering or legality;
- do not add pagination/cursors unless the current simple limit contract is insufficient.

Candidate evidence: `HttpAppTest#test_http_due_work_is_bounded_by_default_and_explicit_limit` and `HttpAppTest#test_http_due_work_rejects_invalid_bounds_before_querying`.

### S12-003 — Count-versus-volume demo proves strategy causality

Opening evidence: the v0.3.7 demo used different workloads for count and volume. Candidate evidence is the same-workload case demo using `[900, 100, 100, 100]` and reporting canonical target/actual dimensions.

Required behavior:

- run the same deterministic skewed amount sequence through count and volume policies;
- keep provider set, route context and provider success behavior equivalent;
- report target and primary actual distribution for both;
- choose a workload where count and volume visibly produce different primary assignment patterns while both obey the same target shares;
- all routing still flows through decoded configuration and canonical Service/Queries;
- no demo-specific allocation formula.

Candidate evidence: `DemoScenarioTest#test_case_demo_isolates_count_vs_volume_on_the_same_skewed_workload` and `CaseFidelityCampaignTest#test_case_campaign_preserves_count_volume_fallback_unknown_and_restart`.

Preferred evidence workload: one large payout plus several small payouts, e.g. `900` followed by nine `100` values, if the real allocator deterministically demonstrates the intended contrast. Measure actual behavior before locking the fixture.

### S12-004 — Active configuration restart contract is explicit and tested

Opening evidence: runtime `PUT /v1/configuration` changed the active in-process generation; durable payout facts safely pinned history, but the active configuration for new payouts was not itself financial journal truth. Candidate evidence is the explicit export/decode/fresh-bootstrap test and configuration crash-consistency campaign.

Required behavior:

- explicitly define whether runtime configuration is process-local and must be supplied again at bootstrap, or provide a minimal canonical export/import/bootstrap path;
- restart must never infer a new active configuration from payout facts;
- unresolved payouts remain safe across active configuration changes/restart;
- GET/export -> canonical decode -> fresh Service/bootstrap equivalence should be executable evidence if configuration is restart-supplied;
- do not add a database or mix control-plane state into economic facts merely for persistence.

Candidate evidence: `ConfigurationIngressTest#test_configuration_export_is_the_explicit_fresh_bootstrap_input` and `ConfigurationCrashConsistencyTest#test_fresh_process_crash_after_provider_publication_restarts_only_with_a_coherent_generation`.

### S12-005 — Configured providers versus executable adapters is operator-visible

Opening evidence: provider opportunities were runtime-configurable while the executable adapter map was fixed at Service/Orchestrator construction. Routing safely intersected available adapter IDs, but an operator could otherwise believe a configured provider was callable when no adapter existed. Candidate evidence is the explicit application projection below.

Required behavior:

- make the distinction explicit at the application/operator boundary;
- choose the smallest coherent behavior: reject impossible active configuration, emit a typed warning/status, or expose adapter availability in provider/config inspection;
- disabled/future providers must not be accidentally prohibited if the chosen semantics intentionally support them;
- do not move adapter instances into the domain/provider-opportunity schema;
- no dynamic plugin loader is required.

Candidate evidence: `HttpAppTest#test_http_provider_projection_exposes_configured_but_uncallable_adapters` and `AllocationOpportunityTest#test_missing_adapter_is_operational_exclusion_not_functional_cohort_loss`.

### S12-006 — Fresh traceability and skeptical closure

- map SPEC-012 requirements to executable evidence;
- remove stale statements that describe already-fixed v0.3.7 code as current behavior;
- candidate status requires all mandatory P1 implemented or evidence-closed;
- candidate is followed by a new code-first skeptical discovery against actual changed code;
- exact full verification and exact pushed-HEAD CI are mandatory before `VERSION_COMPLETE`.

Candidate traceability is executable in `test/support/acceptance_evidence.rb` under
`S12-001` through `S12-006`; `AcceptanceTraceabilityTest` validates every
referenced file and method.

## 5. P2 / evidence-gated follow-ups

Do not let these displace mandatory P1:

- expose `scan_as_of` as the primary external field instead of legacy `as_of`;
- optimistic configuration revision / stale-write rejection;
- richer canonical recovery/explanation dispositions;
- branch protection/static tooling;
- architecture extraction based only on measured repeated semantic changes;
- performance changes beyond the confirmed unbounded due-work read.

## 6. Explicit non-goals before TZ

Do not add without new authoritative/measured need:

- Rails/ORM, database migration, Redis/Sidekiq, queues, distributed leases;
- microservices or distributed exactly-once claims;
- real PSP-specific adapters before providers/contracts are known;
- generalized rules DSL;
- ML/bandits;
- new allocation/recovery objective modes;
- tolerance-vs-quality redesign;
- alternate accounting points/windows;
- large Coordinator/Analytics refactor;
- dynamic provider plugin loading;
- UI/dashboard work that does not materially improve judged evidence.

## 7. Version exit criteria

v0.3.8 may become `VERSION_CANDIDATE` only when:

1. provider-call exception ownership is proven and application classifier failures cannot masquerade as routine provider execution errors;
2. due-work product reads are bounded;
3. judge demo compares count and volume on the same skewed workload and visibly proves strategy-dependent distribution;
4. active configuration restart semantics are explicit and executable;
5. provider configuration versus adapter availability is explicit and operator-safe;
6. all inherited economic/causal tests remain green;
7. SPEC-012 traceability and docs match actual behavior.

Then perform an independent skeptical pass. Challenge especially: provider-call versus classifier exception provenance, guard release, unbounded reads, stale config writes, restart/config source confusion, configured-but-uncallable providers, demo-only behavior, UNKNOWN weakening and privacy leaks.

Only after that pass is clean, full test/property/model/concurrency/fault/acceptance/case evidence is current, docs agree and GitHub Actions is green on the exact final pushed SHA may v0.3.8 become `VERSION_COMPLETE`.
