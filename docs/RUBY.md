# Ruby Engineering Guide

This document defines the Ruby engineering baseline for RubyRouting. It is normative for implementation style and runtime choices unless the official hackathon TZ requires a different Ruby version or a later durable decision explicitly supersedes it.

The product specification defines **what** the system must do. `docs/ARCHITECTURE.md` defines **where responsibilities live**. This document defines **how to use Ruby professionally for this project**.

## 1. Runtime baseline

As of 2026-08-27 the current stable Ruby line is Ruby 4.0 and the latest stable release is **Ruby 4.0.6** (released 2026-07-14).

For v0.1:

- development baseline: **CRuby 4.0.6**;
- keep the code portable across ordinary CRuby 4.0.x patch releases;
- do not depend on master/4.1 features;
- avoid unnecessary 4.0-only behavior when an equally clear portable Ruby construct exists, because the judge runtime is still unknown;
- when the official TZ publishes its Ruby runtime, update the runtime decision, CI/setup documentation, and compatibility-sensitive code immediately.

Do not build a second implementation for another language/runtime.

Official references:

- https://www.ruby-lang.org/en/news/2026/07/14/ruby-4-0-6-released/
- https://docs.ruby-lang.org/en/4.0/
- https://www.ruby-lang.org/en/documentation/

## 2. Project shape: plain Ruby first

v0.1 is a plain Ruby modular application/library, not a Rails/Sinatra/Hanami application.

Use conventional Ruby tooling:

- Bundler for dependency resolution;
- a small `Gemfile`;
- Rake for canonical repository tasks;
- Minitest as the default v0.1 test framework;
- standard library whenever it gives a clear solution;
- explicit `require` boundaries instead of adding an autoloading dependency before it is needed.

The intended first canonical command is `bundle exec rake test`. Additional focused/property/concurrency/benchmark tasks may be added under Rake while preserving one obvious full-suite entry point.

Dependencies are not forbidden, but every dependency must solve a current problem better than the standard library and must remain removable if the judge environment is restrictive.

Do not add Rails, ActiveSupport, an ORM, dependency-injection framework, rules DSL, event framework, or concurrency framework merely to organize the domain model.

## 3. Namespace and files

All production constants live under one top-level namespace:

```ruby
module RubyRouting
end
```

Do not create globally named domain classes such as `Payout`, `Money`, `Policy`, or `Router` outside the namespace.

Use `snake_case.rb` file names matching the principal constant. Keep files focused, but do not create one-line wrapper files or a Java-like class-per-interface hierarchy.

The concrete v0.1 directory layout is defined in `docs/ARCHITECTURE.md`.

## 4. Value objects and immutability

Ruby's `Data` class is the default tool for small value-like immutable records when the record itself has little behavior. Ruby 4.0 documents `Data` specifically as storage for immutable atomic values and provides value equality and pattern-matching support.

Example shape:

```ruby
DecisionReason = Data.define(:code, :details)
```

However, `Data` is **shallowly** immutable: a member may still reference a mutable Array, Hash, String, or custom object. Therefore:

- normalize/freeze nested collections and strings when they become durable domain values;
- never expose a mutable collection that can silently change a value object's hash/equality meaning;
- prefer immutable replacement (`with`, new value) over mutating domain values;
- use a regular class when construction must enforce substantial invariants or when behavior is the important part of the type.

Good candidates for `Data.define` include immutable facts, normalized observations, decision reasons, identifiers paired with metadata, and simple command/result objects.

Good candidates for explicit classes include `Money`, policy objects with validation, state machines, allocation state, and coordinator/application objects.

Official reference: https://docs.ruby-lang.org/en/4.0/Data.html

## 5. Money: Integer minor units only

All monetary amounts inside the financial kernel are represented as **Integer minor units plus an explicit currency**.

Examples:

- 10.00 RUB -> `1000` minor units;
- 123.45 USD -> `12345` minor units.

Rules:

- no `Float` in monetary correctness logic;
- no implicit currency;
- no adding/comparing monetary values of different currencies unless an explicit conversion rule exists;
- reject negative/zero values where the domain operation does not allow them;
- parse external decimal strings exactly at the boundary and convert them to minor units before entering the core;
- formatting back to decimal text is a boundary concern.

Ruby `Integer` has arbitrary precision semantics suitable for exact integral amounts. Do not narrow values to machine-sized integers for perceived performance.

`BigDecimal` is not the core representation. It may become useful at an external FX/pricing boundary if the official task introduces decimal calculations that cannot be modeled naturally as integers/rationals, but it must not leak into basic payout allocation without need.

## 6. Ratios, weights, and exact percentages

Use exact integer weights or `Rational` for allocation proportions and discrepancy calculations.

Examples:

```ruby
Rational(1, 2)       # 50%
Rational(3, 10)      # 30%
Rational("0.125")   # exact 12.5%
```

Ruby documents `Rational` as an exact number specifically useful for avoiding rounding error.

Never construct an exact policy ratio from a binary Float such as `Rational(0.3)`. Parse strings/integers instead (`Rational("0.3")`).

Prefer calculations that compare exact cross-products or rational values. Convert to a display percentage only at analytics/UI boundaries.

Official reference: https://docs.ruby-lang.org/en/4.0/Rational.html

## 7. IDs and enums

Identifiers such as payout IDs, provider IDs, policy IDs, attempt IDs, and external references should be immutable strings or small validated value objects.

Do not depend on Ruby object identity for business identity.

For closed internal states/outcomes, prefer explicit constants or small value types over arbitrary symbols arriving directly from provider payloads.

Provider/external strings are normalized at the adapter boundary. Do not call `to_sym` indiscriminately on unbounded external input.

State names must carry domain meaning, for example `UNKNOWN` is not an alias for `FAILED`.

## 8. Collections

Use the simplest collection matching semantics:

- `Array` for ordered attempts/facts and deterministic candidate sequences;
- `Hash` for keyed state/projections;
- `Set` for true membership/set operations such as eligible/excluded provider IDs;
- `Enumerable` for transformations without unnecessary intermediate abstractions.

Ruby 4.0's `Set` is implemented in C and uses Hash-like equality/hash semantics. Do not mutate objects while they are being used as Set/Hash keys.

Do not subclass `Array`, `Hash`, or `Set` just to give a collection a domain name. Wrap it in a domain object when invariants/behavior justify the type.

Official reference: https://docs.ruby-lang.org/en/4.0/Set.html

## 9. Determinism

Financial-core behavior must be deterministic for the same inputs and state.

Rules:

- never depend on Hash/Set iteration order as an implicit business tie-breaker;
- when multiple providers are equivalent, apply an explicit stable tie-breaker (normally provider ID or a policy-defined stable order);
- do not call global `rand` from routing code;
- inject/use a `Random` instance only for explicitly optional exploration/test generation;
- log/report the seed for randomized tests;
- avoid reading `Time.now` inside pure domain decisions;
- sort only when ordering is semantically required; avoid hidden nondeterministic ordering caused by concurrent collection construction.

Ruby `Random.new(seed)` provides an independent deterministic PRNG sequence and is the preferred test/generator mechanism.

Official reference: https://docs.ruby-lang.org/en/4.0/Random.html

## 10. Time

Separate two concepts:

1. wall-clock timestamps used for facts/audit (`Time` in UTC at the boundary);
2. elapsed-duration/timeout measurement, which must use a monotonic source.

For the real system clock adapter, elapsed time should use:

```ruby
Process.clock_gettime(Process::CLOCK_MONOTONIC)
```

Core code that depends on time receives a narrow clock/time value through an explicit boundary. Tests use a controlled/fake clock and advance it directly. Do not make deterministic tests wait with real `sleep`.

Keep time-zone formatting out of the core.

## 11. Errors vs domain outcomes

Do not use exceptions as normal payout business flow.

Represent expected domain outcomes explicitly:

- success;
- pending;
- unknown;
- safe route/provider failure;
- terminal payout failure;
- no safe route/defer.

Use exceptions for programming/configuration/invariant failures such as:

- malformed impossible object construction;
- unknown internal enum/code;
- violated precondition that indicates a bug;
- corrupt state that should never be accepted.

At external boundaries, convert provider/network exceptions into normalized observations only when their semantics are known. A transport timeout after a request may have been accepted must normalize to `UNKNOWN`, not generic failure.

Do not rescue `StandardError` broadly in core logic. Rescue the narrow exception classes that the boundary actually understands.

## 12. Pattern matching

Ruby pattern matching is useful for small closed result/state variants and pairs naturally with `Data` values.

Use it when it makes state transitions exhaustive and readable. Do not build a deeply nested pattern-matching DSL that hides ordinary control flow.

Prefer an explicit `case` over chains of boolean flags when each branch is a semantically distinct outcome.

## 13. Methods and APIs

Professional Ruby for this project means explicit, unsurprising APIs:

- keyword arguments for constructors with several domain fields;
- small public method surface;
- predicate methods end in `?`;
- destructive/mutating methods use `!` only when there is a meaningful non-bang counterpart or the danger convention is genuinely useful;
- avoid setters on domain value objects;
- return domain result objects instead of loosely structured Hashes from core services;
- use hashes only at serialization/config/provider boundaries or for genuinely dynamic keyed structures.

Avoid `method_missing`, runtime constant generation, monkey patches, refinements, and metaprogramming unless there is measured/repeated complexity that they clearly remove. There is currently no such need.

## 14. Modules and objects

Use modules for namespace/grouping or stateless cohesive functions where an object has no meaningful state.

Use objects when they own:

- validated state;
- lifecycle/state transition behavior;
- an external boundary dependency;
- concurrency coordination;
- a coherent algorithm configuration.

Avoid generic names such as `Manager`, `Helper`, `Processor`, or `Service` when a precise domain name exists.

Do not create interface classes solely to imitate Java. Ruby ports are documented behavioral contracts backed by tests; a small abstract module/class is acceptable only when it materially improves clarity.

## 15. Mutation discipline

The pure kernel prefers immutable inputs/results. Mutable state is isolated inside the coordinator/state adapter.

Rules:

- no global mutable hashes/arrays;
- no class variables for routing state;
- no mutable singleton holding allocation counters;
- facts are append-oriented and not edited after creation;
- projection/state replacement must happen through coordinator-owned mutation;
- do not return internal mutable collections directly; return frozen copies/immutable snapshots as appropriate.

This discipline exists to make concurrency and replay reasoning tractable, not as functional-programming ideology.

## 16. Concurrency on CRuby

v0.1 uses `Thread` plus `Thread::Mutex` for the in-memory concurrency harness and coordinator.

Important rules:

- never rely on CRuby's GVL as a correctness lock;
- every shared mutable routing state transition has an explicit synchronization boundary;
- keep critical sections small and deterministic;
- never hold the coordinator mutex while calling provider/network I/O;
- atomically commit the routing decision, allocation reservation, decision fact, and economic ownership before releasing the critical section;
- normalize/apply provider observations in a later synchronized state transition;
- use deterministic barriers/hooks in concurrency tests rather than timing races with `sleep`.

`Thread::Mutex` explicitly exists to coordinate access to shared data. `Thread::Queue` is appropriate only where a real producer/consumer queue is useful in tests/simulation; do not turn it into an internal event bus by default.

Official references:

- https://docs.ruby-lang.org/en/4.0/Thread/Mutex.html
- https://docs.ruby-lang.org/en/4.0/Thread/Queue.html

## 17. Ractor and Fiber policy

Do **not** use Ractor in the v0.1 financial kernel or coordinator.

Ruby 4.0 significantly improves Ractor and introduces `Ractor::Port`, but the Ruby 4.0 release notes still describe Ractor as moving *toward* leaving experimental status. Adding shareability constraints now would complicate the domain model without a demonstrated judge benefit.

Ractor may be benchmarked/reconsidered later if the official workload demonstrates CPU-parallel routing pressure that Threads/processes cannot satisfy cleanly.

Do not introduce Fiber/Fiber Scheduler abstractions until an actual async I/O framework or provider concurrency model requires them. Core routing is synchronous/pure; I/O scheduling belongs outside it.

Official references:

- https://www.ruby-lang.org/en/news/2025/12/25/ruby-4-0-0-released/
- https://docs.ruby-lang.org/en/4.0/language/ractor_md.html

## 18. Frozen string literals

Ruby 4.0 still documents frozen string literals as disabled by default unless enabled. Use:

```ruby
# frozen_string_literal: true
```

at the top of project Ruby source files unless a file intentionally requires mutable literals.

This reduces accidental mutation/allocation and makes immutability expectations explicit across unknown judge configurations.

Official reference: https://docs.ruby-lang.org/en/4.0/language/options_md.html

## 19. Requires and load order

Until a framework/autoloader is justified:

- `lib/ruby_routing.rb` is the production entry point;
- it explicitly requires public production components in dependency-safe order;
- tests require `ruby_routing` and their own test support;
- test/reference/simulator helpers that are not production behavior stay under `test/support` and must never be required by `lib/`;
- avoid circular requires by keeping dependency direction consistent with architecture.

Do not rely on incidental current-working-directory `$LOAD_PATH` behavior. Canonical tasks must set load paths deliberately.

## 20. Testing Ruby code

v0.1 defaults to **Minitest + Rake**.

Why:

- small dependency/tooling surface;
- idiomatic Ruby;
- easy focused tests;
- suitable for custom property/state-machine/concurrency harnesses;
- no need for a DSL-heavy test framework to express the domain.

Test names should describe behavior/invariant, not implementation method names alone.

Prefer explicit assertions over overly clever custom assertion DSLs. Extract reusable invariant assertions when repetition is semantic and substantial.

The independent oracle stays in test support and must not call the production algorithm being checked.

`docs/TESTING.md` remains authoritative for test depth and scenario coverage.

## 21. Code style

Optimize for reviewability by humans and coding agents:

- 2-space indentation;
- UTF-8 source;
- small methods when separation improves reasoning, not arbitrary line-count rules;
- early returns are fine when they simplify guard conditions;
- avoid dense chained expressions for financial state transitions;
- use parentheses when precedence could be misread;
- use `_` digit separators for large integer literals (`10_000_000`);
- prefer explicit names (`allocation_snapshot`) over compressed names (`alloc_st`);
- comments explain *why/invariant*, not what obvious code does;
- public/non-obvious domain behavior gets concise documentation where the type name is insufficient.

Do not perform repo-wide style churn while correctness work remains.

## 22. Static checks and linting

Do not let linting tool selection block v0.1 Phase 1.

Required baseline:

- tests;
- `ruby -c`/loadability through the canonical suite;
- warnings investigated where practical;
- deterministic behavior checks.

A Ruby linter/static/type tool may be added as a development-only dependency after the harness exists if it catches real defects at acceptable noise/cost. Do not add Sorbet/RBS/RuboCop/Standard merely to appear sophisticated.

If a tool is adopted, document one canonical command and avoid conflicting formatters.

## 23. Performance

Correctness first, measurement second, optimization third.

For v0.1:

- benchmark decision/allocation/replay paths with representative synthetic states;
- record Ruby version and whether JIT is enabled;
- baseline without relying on JIT-specific semantics;
- avoid allocation-heavy temporary structures in hot loops only when benchmarks show material impact;
- do not mutate the domain model into opaque arrays/integers solely for microbenchmarks;
- do not cache correctness-sensitive decisions without a clear invalidation model.

Ruby 4.0 includes YJIT and introduces experimental ZJIT. The Ruby 4.0 release guidance says ZJIT is not yet as fast as YJIT and recommends holding off production deployment. Therefore neither JIT is an architectural dependency. Later we may benchmark interpreter vs YJIT if the official environment permits it.

## 24. Security and boundary hygiene

Even in a hackathon:

- never use `eval`/`instance_eval` on external policy/provider input;
- do not deserialize untrusted Ruby Marshal data;
- validate provider IDs, amount/currency fields, and policy configuration before constructing core objects;
- do not log secrets/provider credentials;
- keep credentials/configuration outside source code if real integrations appear;
- bound externally controlled collection/string sizes where the official input format makes resource abuse possible.

## 25. Serialization

Core objects are not required to be JSON-shaped.

If/when an external API/storage contract appears:

- create explicit serializers/mappers at the boundary;
- preserve integer minor-unit money or a clearly defined decimal string representation;
- serialize normalized state codes intentionally;
- version externally durable schema if compatibility matters;
- never couple the financial kernel directly to framework serializer callbacks.

## 26. Review checklist for Ruby changes

Before accepting a non-trivial Ruby change, ask:

1. Is all executable domain logic still Ruby?
2. Is monetary arithmetic exact and currency explicit?
3. Is mutable state isolated and synchronized where shared?
4. Is provider/time/random behavior behind the right boundary?
5. Is the core deterministic for deterministic inputs?
6. Did a Data/Hash/Set key accidentally contain mutable nested state?
7. Is an expected domain outcome modeled as a value rather than an exception?
8. Is provider I/O outside the coordinator critical section?
9. Does the code depend on a Ruby 4.0-specific feature without meaningful benefit?
10. Is a new gem/framework actually needed now?
11. Can tests reproduce randomized/concurrent failures?
12. Is the implementation simpler than the abstraction it replaces?

If several answers are unfavorable, revise before building more code on top.

## 27. Official Ruby sources used for this guide

- Ruby 4.0.6 release: https://www.ruby-lang.org/en/news/2026/07/14/ruby-4-0-6-released/
- Ruby documentation index: https://www.ruby-lang.org/en/documentation/
- Ruby 4.0 docs: https://docs.ruby-lang.org/en/4.0/
- Ruby 4.0 release notes: https://www.ruby-lang.org/en/news/2025/12/25/ruby-4-0-0-released/
- `Data`: https://docs.ruby-lang.org/en/4.0/Data.html
- `Rational`: https://docs.ruby-lang.org/en/4.0/Rational.html
- `Set`: https://docs.ruby-lang.org/en/4.0/Set.html
- `Random`: https://docs.ruby-lang.org/en/4.0/Random.html
- `Thread::Mutex`: https://docs.ruby-lang.org/en/4.0/Thread/Mutex.html
- `Thread::Queue`: https://docs.ruby-lang.org/en/4.0/Thread/Queue.html
- Ractor language docs: https://docs.ruby-lang.org/en/4.0/language/ractor_md.html
- command-line/language options: https://docs.ruby-lang.org/en/4.0/language/options_md.html

Re-check these sources when upgrading Ruby or when the official judge runtime becomes known.
