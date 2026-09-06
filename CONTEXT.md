# RubyRouting Domain Context

Current glossary for the authoritative case and protected production kernel.

## Authoritative case terms

- **Hard constraint** — absolute provider eligibility; never compensated by score.
- **Soft routing factor** — one business preference evaluated only for eligible providers.
- **ConflictResolver** — single deterministic soft-goal authority after hard filtering.
- **SubmissionProfile** — typed release configuration used by the exact finalization/CLI path; owns target/weight/simulation provenance and terminal identity.
- **Primary assignment** — first provider selected for a new payout before simulated outcome. Under current bounded TZ interpretation this is the authority for count/volume distribution targets.
- **Attempt** — a provider actually invoked after selection. Hard-excluded providers are not attempts.
- **Settlement provider** — final provider whose simulated outcome is approved; may differ from primary assignment after fallback.
- **Assignment ledger** — exact count/volume distribution of primary assignments used by routing objectives.
- **Settlement ledger** — exact count/volume of approved final providers used for success/settlement analytics, not silently as routing-target authority.
- **ProviderCaseState** — mutable official snapshot for daily approved amount, external + transient in-progress exposure, requisites, RPM and case outcome counters.
- **Terminal self-provider** — configured `spacepayments` fallback after external exhaustion; not an ordinary scoring candidate.
- **Competition expiry** — synthetic `expired` result that permits fallback inside the case simulator; not a real PSP timeout fact.
- **Current conversion signal** — supplied `conversion_24h`; history is calibration/trends only.
- **Infeasible target** — target unreachable under current hard constraints/state/finite workload; reported rather than forced.
- **Organizer decision projection** — conservative external JSON mapping from richer internal assignment/attempt/settlement facts to required fields/enums.
- **Submission finalization** — clean-checkout command that uses canonical SubmissionProfile, writes exact root files, reparses and validates submitted artifacts.

## Protected production terms

- **Economic ownership** — at most one unresolved authority for the next safe real-payment economic action.
- **UNKNOWN** — ambiguous real provider outcome that blocks unsafe cross-provider fallback unless safely released/classified.
- **Provider operation identity** — stable provider-local idempotency/status identity.
- **Durable payout history** — production execution/recovery evidence; distinct from organizer history CSV.
- **AdmissionLedger** — production in-flight/throughput authority; not the organizer business snapshot.

## Naming rule

Do not reuse one state/ledger name for assignment, attempt, settlement and production economic state when their accounting/lifecycles differ.
