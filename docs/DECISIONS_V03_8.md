# Decisions — v0.3.8

Status: VERSION_COMPLETE decision log for SPEC-012. Decisions are closed for the pre-TZ scope and remain subject to authoritative TZ reconciliation.

## D-421 — v0.3.7 is protected; v0.3.8 is a narrow runtime-boundary pass

Status: accepted.

Decision: do not reopen allocation, UNKNOWN, causal safety, configuration publication, RecoveryExecutor time semantics or optimization without new deterministic evidence. v0.3.8 targets only the newly identified runtime/product-boundary gaps.

Rationale: the project is already strong against the public case. Speculative redesign now has lower value and higher regression risk than closing known boundary ambiguity.

## D-422 — exception provenance precedes exception taxonomy

Status: accepted and implemented.

Decision: a failure receives resumable provider-execution semantics because it originated from the executable provider invocation boundary, not merely because it happened inside a method named `invoke_provider` or was caught by `rescue StandardError`.

Once the adapter has returned, application classification/validation is application authority. Failures there must have explicit semantics and may not accidentally inherit RecoveryExecutor continuation behavior.

Rationale: `ProviderExecutionError` is now operationally significant. A broad rescue can convert application bugs into routine item failures and hide defects. The focused post-return malformed-observation regression and the adjacent 199-run matrix prove the narrowed boundary and guard release.

## D-423 — malformed provider return is not automatically a raw provider execution error

Status: accepted and implemented as fail-closed application validation.

Decision: invalid return type/linkage/transport-outcome combinations must be handled deliberately after adapter return. They may remain fail-closed validation errors or receive a distinct provider-contract classification if useful. Do not automatically reuse raw invocation failure semantics.

Rationale: provider contract violation and provider transport execution failure have different provenance even if both are ultimately caused by an adapter/integration. The current minimal contract retains `ArgumentError` after a successful adapter return; no new error class was needed.

## D-424 — due-work inspection is a bounded product read

Status: accepted and implemented.

Decision: `GET /v1/recovery/due-work` bounds response/work cardinality with a
256 default and hard maximum through canonical `Queries#due_work(...,
limit:)`. Invalid, duplicate, unknown and out-of-range query parameters fail
before the query is executed. No pagination infrastructure is introduced.

Rationale: the number of due payouts grows with workload. The mutating
recovery runner was already bounded; leaving the read unbounded was
inconsistent and avoidable. HTTP regressions cover the default, explicit
limit, ordering/as_of preservation and rejection paths.

## D-425 — strategy demo should isolate strategy

Status: accepted and implemented.

Decision: count and volume judge evidence uses the same skewed amount
sequence `[900, 100, 100, 100]` and equivalent provider behavior, changing
the routing measure/strategy rather than changing both strategy and workload.

Rationale: this is a stronger causal demonstration of the public case
requirement and avoids presentation ambiguity. The canonical report measures
count and volume targets/actuals from Queries analytics; no demo allocation
formula was introduced.

## D-426 — active configuration is control-plane state, not financial fact truth

Status: accepted and evidence-closed.

Decision: runtime configuration for new decisions remains separate from durable payout/economic facts. Restart behavior must explicitly re-supply/import active configuration unless an authoritative persistence mechanism is introduced later.

Do not reconstruct the desired current configuration from payout facts. The
existing canonical `to_h`/`decode` and `ConfigurationStore` constructor are
the pre-TZ bootstrap contract; a fresh generation intentionally begins at
revision 0.

Rationale: historical payout semantics and desired control-plane state have
different lifecycles and retention requirements. The fresh-bootstrap
regression and configuration crash/restart suites provide executable evidence
without adding persistent control-plane infrastructure.

## D-427 — executable adapter availability is application runtime state

Status: accepted and implemented.

Decision: provider opportunities remain domain/config values; executable
provider adapters remain application runtime dependencies. `GET
/v1/providers` makes configured-but-uncallable state visible through an
application-only `adapter_available` projection, without embedding adapter
objects or runtime fields into domain configuration.

Rationale: runtime configuration can change independently of the adapter map.
Silent mismatch is safe from accidental calls but confusing for operators.
The projection is sourced from the canonical Orchestrator adapter map and is
covered by an A=true/B=false HTTP regression.

## D-428 — no persistent control-plane or plugin infrastructure pre-TZ without authority

Status: accepted.

Decision: do not add a database, Redis/Sidekiq, distributed lease, dynamic plugin loader or generic provider registry framework to solve v0.3.8. Prefer explicit bootstrap/export/import/status semantics.

Rationale: these are platform features not required by the public case and would expand correctness scope substantially.

## D-429 — candidate is not complete

Status: accepted.

Decision: closing PTZ8-001..005 permits only `VERSION_CANDIDATE`. A fresh code-first skeptical pass after candidate is mandatory. Only clean discovery plus current exact verification/docs and exact pushed-HEAD CI may produce `VERSION_COMPLETE`.

Rationale: v0.3.7 itself found material fixes during skeptical closure; known backlog exhaustion is demonstrably insufficient evidence of completeness.

## D-430 — candidate-stage skeptical discovery is clean, but not completion evidence

Status: accepted.

Decision: the fresh code-first review at candidate checkpoint `c481d5706ae62d6d27347afeeb67c159c77fb3f1` found no material locally solvable P0/P1 in provider-error provenance, interaction-guard release, bounded due-work reads, configuration/bootstrap authority, configured-versus-executable provider visibility, demo causality, UNKNOWN safety, privacy or second routing authorities. The subsequent exact candidate matrix and pushed-HEAD Actions run `33670750287` at `9377dc156b2117c82be2bb92261957451fe32bad` are green; final status/docs closure is verified on its own pushed HEAD.

Rationale: a clean skeptical discovery removes the currently observed closure findings, but the completion policy requires evidence on the exact final pushed SHA, including a docs-only closure commit if that commit is cited.
