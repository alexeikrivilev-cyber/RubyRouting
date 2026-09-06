# RubyRouting Domain Context

Current glossary for the authoritative case, v0.4.2 submission contract and protected production kernel.

## Authoritative case terms

- **Hard constraint** — absolute provider eligibility; never compensated by score.
- **Soft routing factor** — one business preference evaluated only for eligible providers.
- **ConflictResolver** — single deterministic soft-goal authority after hard filtering.
- **SubmissionProfile** — typed release configuration used by exact finalization/CLI; owns target/weight/simulation provenance and terminal identity.
- **Primary routing phase** — provider selection before any outcome for the current operation. Count/volume distribution objectives apply here under the current bounded TZ interpretation.
- **Fallback routing phase** — selection among remaining eligible providers after a rejected/expired primary or prior fallback attempt. It must not create another count/volume counterfactual assignment for the same operation.
- **Primary assignment** — first provider selected for a new payout before simulated outcome. This is the current authority for count/volume distribution targets.
- **Attempt** — a provider actually invoked after selection. Hard-excluded providers are not attempts.
- **Settlement provider** — final provider whose simulated outcome is approved; may differ from primary assignment after fallback.
- **Assignment ledger** — exact count/volume distribution of primary assignments used by routing objectives.
- **Attempt ledger** — exact count/volume/outcome evidence for every invoked provider in cascade order.
- **Settlement ledger** — exact count/volume of approved final providers used for success/settlement analytics, not silently as routing-target authority.
- **ProviderCaseState** — mutable official snapshot for daily approved amount, external + transient in-progress exposure, requisites, RPM and case outcome counters.
- **Terminal provider** — explicitly configured terminal fallback (`spacepayments` in supplied data) after external exhaustion; terminal identity is not defined solely by a zero traffic target.
- **Competition expiry** — synthetic `expired` result that permits fallback inside the case simulator; not a real PSP timeout fact.
- **Current conversion signal** — supplied `conversion_24h`; history is calibration/trends only.
- **Target feasibility evidence** — observed reasons a target is forced over, structurally constrained under, or limited by finite workload granularity. Do not call a target mathematically infeasible without evidence.
- **Organizer decision projection** — conservative external JSON mapping from richer internal assignment/attempt/settlement facts to required fields/enums.
- **TZ report base projection** — compatibility fields/types explicitly shown by the TZ (`period`, base distribution percentages, projected daily utilization, skip reasons, judge-readable recommendations). Rich exact analytics extend this base rather than replace it.
- **Rich report extension** — additive exact assignment/attempt/settlement, profile, factor, explanation and structured recommendation evidence.
- **Independent organizer contract validator** — validator whose required fields/types come from TZ/sample/public authority rather than from the same builder being validated.
- **Non-discriminating factor** — factor whose raw value is equal across all current candidates; it provides no causal decision pressure and should not claim full contribution.
- **Submission finalization** — clean-checkout command that uses canonical SubmissionProfile, writes exact root files, reparses and validates submitted artifacts through both compatibility and internal checks.

## Protected production terms

- **Economic ownership** — at most one unresolved authority for the next safe real-payment economic action.
- **UNKNOWN** — ambiguous real provider outcome that blocks unsafe cross-provider fallback unless safely released/classified.
- **Provider operation identity** — stable provider-local idempotency/status identity.
- **Durable payout history** — production execution/recovery evidence; distinct from organizer history CSV.
- **AdmissionLedger** — production in-flight/throughput authority; not the organizer business snapshot.

## Naming rule

Do not reuse one state/ledger/phase name for assignment, attempt, settlement and production economic state when their accounting/lifecycles differ.