# Completion Policy — no premature "done"

This is the normative completion contract for RubyRouting coding agents.

## 1. Core rule

Completion is an evidence claim about the actual system, never a feeling, checklist result, commit message, assertion count or absence of an obvious next task.

Use precise states:

- `SLICE_IMPLEMENTED`
- `SLICE_VERIFIED`
- `PHASE_VERIFIED`
- `VERSION_CANDIDATE`
- `VERSION_COMPLETE`
- `EXTERNALLY_BLOCKED`

Current active version: **v0.3.4 / SPEC-008 — VERSION_COMPLETE**.

A previous `VERSION_COMPLETE` publication may be reopened when a later material counterexample appears. Reopening preserves history; it does not rewrite the earlier evidence.

## 2. What never proves completion by itself

None of these are sufficient:

- all planned checkboxes are green;
- all currently known backlog items are closed;
- all acceptance IDs have tests;
- unit/property/model/concurrency/fault suites are green;
- CI is green;
- a benchmark or demo passes;
- documentation says the version is complete;
- a previous closure pass succeeded;
- the agent cannot immediately think of another task;
- the official TZ is not yet available.

## 3. Two-stage closure model

### Stage 1 — Known-scope verification

Finish or falsify all mandatory active SPEC-008 hypotheses and preserve compatible inherited guarantees.

Only then set status to `VERSION_CANDIDATE`.

### Stage 2 — Independent skeptical discovery

Review the candidate as if the known backlog did not exist. Actively search changed production code for unplanned counterexamples.

Any new material P0/P1 returns v0.3.4 to ACTIVE and becomes normal backlog work, even if the finding appears after a prior `VERSION_COMPLETE` publication.

Only a fresh no-material-finding pass may proceed to final exact-HEAD verification and `VERSION_COMPLETE`.

## 4. Mandatory v0.3.4 skeptical areas

### A — Outcome analytics semantics

Challenge provider/fallback success numerators and denominators under count/volume, multiple currencies, primary/fallback outcomes, unresolved work, duplicates/late observations and reversals. No rate may divide incompatible populations.

### B — Duplicate recovery consumers and interaction ownership

Challenge multiple workers observing the same due item and racing through resume/start. Then add concurrent observations while the provider invocation itself is blocked.

Must challenge:

- duplicate observation during live status resolution;
- duplicate/stale/non-applying observation during live same-provider retry;
- callback before start token consumption;
- adapter exception cleanup;
- accepted observation/completion cleanup;
- a stale callback trying to clear a newer invocation;
- restart while durable operation is dispatching/resolving.

At most one provider interaction may be live for one committed token inside one process. A process-local guard is owned by the invocation that acquired it. Observation application is not automatically proof that another live invocation completed.

### C — Configuration publication crash/restart

Use abrupt fresh-process boundaries. Restart must reconcile one coherent generation or fail closed before routing. Silent mixed-generation routing is forbidden.

### D — Derived-read/cache correctness

Challenge stale fact revision, append during read, restart rebuild, dynamic `as_of`, multi-policy/multi-currency parity and invalidation after reversal/conflict.

### E — Due-work ordering/scale

Challenge mostly-terminal histories, sparse due sets, exact due boundaries, stale work items, deterministic ordering and restart rebuild of any index.

### F — Exact hackathon case composition

Construct count-share and volume-share batches where skewed amounts differ. Add safe fallback and ambiguous-no-response resolution. Verify history and analytics together.

### G — Financial safety regression

Always challenge second monetary effect, UNKNOWN followed by cross-provider fallback, stale start tokens, fallback to attempted provider, late old-provider success, provider removal while unresolved, TTL/deadline expiry, reversal/conflict and restart operation identity.

### H — Application/API/history parity

Verify HTTP/demo/application paths consume canonical routing, analytics and payout history. No adapter owns a second success formula or selection algorithm.

### I — Measured scale claims

Inspect full-history copies/scans, repeated reads, due-work enumeration, restore and memory. Record exact workload/revision and never turn bounded synthetic evidence into unsupported production-scale claims.

## 5. Exact-case acceptance cohesion

Before closure, one deterministic campaign must prove:

`configurable count/volume policy -> routing -> provider attempt -> safe/ambiguous failure handling -> fallback/resolution -> attempt history -> settlement -> target/actual + success analytics -> replay/restart`.

Passing isolated tests is not a substitute.

## 6. Canonical-flow cohesion

Verify every reachable production module belongs to:

`Intent -> RoutingContext -> Active Config -> Provider Compatibility -> Admission -> Allocation -> Recovery -> Optimization -> Atomic Commit -> Provider -> Observation -> Lifecycle -> Durable Facts -> History/Analytics/Explanation`.

Classify dead modules, duplicate algorithms, alternate config/routing interfaces, demo code masquerading as core, divergent live/restore rules and multiple active sources of truth.

## 7. Concurrency evidence rule

Concurrency correctness claims require deterministic interleavings using barriers, queues, latches or equivalent controlled synchronization. Sleeps and probabilistic timing are insufficient for a P0 claim.

Tests must assert exact provider-call and financial-fact counts, not only final payout status. A single-owner invariant alone does not prove single provider interaction.

When using a live interaction token/generation, test stale-token/ABA behavior explicitly.

## 8. Performance change gate

A performance optimization requires exact baseline revision and CRuby version, explicit workload size, before/after metrics, correctness parity against full replay/reference behavior and restart rebuild proof for derived state.

Prefer the narrowest change.

## 9. Repository discovery

Search actual main for TODO/FIXME/XXX, reachable `NotImplementedError`, broad exception swallowing, uncontrolled time/randomness, Float in financial correctness, stale active docs, multiple active plans/specs, repeated full-history query work and randomized tests without reproducible seeds.

Every material finding is classified before closure.

## 10. Exact-HEAD verification

After the final material change and skeptical pass are clean, run risk-appropriate current evidence on the exact candidate revision:

- `bundle check`
- `bundle exec rake test`
- `bundle exec rake property`
- `bundle exec rake model`
- `bundle exec rake concurrency`
- `bundle exec rake fault`
- exact-case campaign
- focused recovery interaction-ownership races
- relevant restart/crash tests
- SPEC-008 acceptance traceability
- current GitHub Actions.

Performance benchmarks are required only when performance code/claims changed or the active plan explicitly requires them.

Do not reuse old results for changed code.

## 11. Documentation consistency gate

`VERSION_COMPLETE` is forbidden unless all active normative sources agree on current version and status, including at minimum:

- README;
- AGENTS;
- active SPEC;
- active ExecPlan;
- PRE_TZ_BACKLOG;
- ROADMAP;
- Completion Policy.

A docs-only closure commit must itself receive exact-HEAD CI if CI is part of the declared completion evidence.

## 12. External blocker test

`EXTERNALLY_BLOCKED` is valid only if the missing capability is required, cannot be resolved from available engineering evidence, requires unavailable authoritative semantics/access/service, no independent required work remains, and the exact blocker is documented.

Missing TZ by itself is not a blocker.

## 13. Completion report

A v0.3.4 `VERSION_COMPLETE` report must include:

- exact revision;
- SPEC-008 + inherited reconciliation;
- acceptance traceability result;
- exact commands/CI actually run;
- recovery interaction-ownership race evidence;
- outcome analytics mixed-dimension evidence;
- configuration crash/restart evidence;
- exact-case campaign result;
- replay/restart parity for changed derived state;
- independent skeptical areas examined and newly discovered issues;
- remaining genuine external blockers;
- documentation consistency result.

## 14. Final anti-premature rule

`VERSION_COMPLETE` is forbidden when any of the following is true:

- a known P0/P1 is open;
- the independent skeptical stage has not happened after known work became green;
- that stage found a material locally solvable issue still unresolved;
- final verification is not from the exact candidate revision;
- active docs disagree on current version/stop rules;
- a performance claim lacks recorded evidence;
- completion is justified primarily by checklist exhaustion or green CI.
