# Testing Strategy

RubyRouting testing is organized around financial invariants and adversarial state transitions, not line coverage.

## Core test families

Use a layered matrix:

- deterministic unit and acceptance regressions;
- independent pure-Ruby allocation/recovery/admission oracles;
- property and metamorphic tests;
- model/state-machine histories;
- controlled concurrency/interleaving tests;
- provider contract/normalization tests;
- deterministic fault injection and fresh-process crash tests;
- end-to-end payout/fallback/reconciliation scenarios;
- replay/restart equivalence;
- bounded performance/stress evidence with exact workload metadata.

No flaky retry masking. Randomized failures must emit/reuse reproducible seeds/traces.

## Financial invariants always worth asserting

- active unresolved economic owners per payout <= 1;
- UNKNOWN never causes cross-provider fallback;
- same-provider retry/resolution reuses the pinned economic operation according to contract;
- primary allocation is not advanced by recovery attempts;
- capacity/throughput/health reservations are conserved and released exactly once where specified;
- settlement is unique unless a later distinct effect is represented as conflict/reversal evidence;
- exact duplicate observations are idempotent;
- replay/restart reproduces the same economic state;
- count/volume/currency analytics remain dimension-safe.

## Concurrency tests

P0 concurrency evidence must use controlled synchronization: barriers, queues, latches or equivalent. Do not rely on `sleep` to make a race likely.

Assert exact structural evidence:

- provider call count;
- `attempt_started` count;
- operation/attempt identities;
- ownership acquisitions/releases;
- `allocation_committed` count;
- settlement count;
- recovery interaction counters;
- provider B/fallback calls where forbidden.

Final payout status alone is insufficient because duplicate provider calls can occur while ownership remains single.

## v0.3.4 live provider-interaction ownership matrix

The reopened S8-002/PTZ4-004 session must cover:

1. N workers racing one due status-resolution item with no competing callback;
2. N workers racing one due idempotent retry item with no competing callback;
3. worker A blocked in live `resolve`, exact duplicate old observation applied, worker B resumes before A completes;
4. worker A blocked in live same-provider retry, duplicate/stale/non-applying observation applied, worker B resumes;
5. stale callback cannot clear a newer invocation token/generation;
6. adapter exception releases only its own invocation ownership and permits later safe recovery;
7. accepted observation/completion does not leave a stuck guard;
8. callback-before-start invalidates only the durable start token it legitimately supersedes;
9. fresh restart discards process-local invocation identity and rebuilds recovery from durable operation state;
10. UNKNOWN ownership remains pinned and no cross-provider fallback occurs during any race.

If the implementation introduces invocation generation values, add explicit ABA/stale-generation tests.

## Recovery and observation adversarial matrix

Cover:

- success, safe route failure, temporary provider failure, terminal payout failure, pending, UNKNOWN;
- definitely-not-sent vs ambiguous-after-possible-send transport;
- duplicate observation id with exact same payload;
- duplicate observation id with conflicting payload;
- authoritative sequence ordering and out-of-order callbacks;
- late success from released old operation;
- provider disable/removal while unresolved;
- TTL/deadline expiry and reconciliation blocking;
- restart before dispatch, during dispatching/resolving, after observation, after release and after settlement.

## Exact case campaign

Maintain one deterministic canonical Service/Coordinator/provider campaign demonstrating:

`count policy + volume policy + safe fallback + UNKNOWN resolution + full attempts/history + target/actual analytics + provider/fallback outcome analytics + restart/replay parity`.

This is product-composition evidence, not a replacement for adversarial mechanism tests.

## Performance evidence

Performance changes require recorded exact revision, CRuby version, workload size and before/after result. Prefer median/p95 for repeated reads. Derived caches/indexes must have full replay/restart parity.

Do not claim 100k/production scale unless that exact workload was actually executed and recorded.

## Verification order for a correctness fix

1. deterministic reproducer red/falsification test;
2. focused unit/concurrency regression;
3. adjacent recovery/restart/fault tests;
4. `bundle exec rake concurrency`;
5. `bundle exec rake fault`;
6. `bundle exec rake test`;
7. `bundle exec rake property`;
8. `bundle exec rake model`;
9. acceptance traceability;
10. exact-HEAD CI.

Run performance suites only when the changed path or claim warrants them.
