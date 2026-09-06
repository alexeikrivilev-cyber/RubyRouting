# RubyRouting Domain Context

This glossary records the product terms that must remain distinct in the
canonical payout-routing flow.

- **Economic ownership** — the single unresolved right to determine the next
  safe action for a payout. It is held by one provider operation or by none.
- **Functional opportunity** — a provider can serve the payout in principle
  under provider, payout and policy context, independent of temporary health,
  availability or capacity.
- **Allocation deviation** — the exact difference between committed primary
  distribution and the policy target/corridor for the relevant opportunity
  cohort or policy epoch.
- **Recoverable deviation** — a deviation caused by a temporary or admissible
  routing condition that a later primary assignment may improve. It is an
  explanation, not a queued obligation.
- **Historical catch-up/debt** — an explicit future-routing obligation to
  compensate a prior deviation. This mechanism is not enabled by v0.3; no
  payout may be burst-routed merely to repair historical allocation.
