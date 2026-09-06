# Ruby Guide

Ruby baseline: **CRuby 4.0.6**. Keep the submission Ruby-only and dependency-light.

Use exact `Integer`/`Rational` arithmetic for routing authority. Float/decimal presentation belongs only at explicit organizer-facing boundaries with deterministic rounding.

Prefer small typed value objects, pure factor/evaluation functions and deterministic transformations. Avoid hidden global state, process timezone dependence, uncontrolled randomness and sleep-based correctness tests.

Use Minitest and repository Rake tasks. Add independent/metamorphic tests where self-replay would merely confirm the same bug twice.

Current business authority is `TZ/organizer contract -> SPEC-021 -> completed compatible SPEC-020/019/018/017/016 -> scorecard/active plan/matrix`. This guide cannot redefine case semantics.