# Functional Language Roadmap

## 1. Purpose

The player language is expected to become more expressive over time. Growth must not destroy the small-core onboarding model or turn the project into an unrelated general-purpose language implementation.

This roadmap separates language evolution from the immediate game milestones.

## 2. Growth rule

A language feature should be added only when:

1. A concrete tactical policy is awkward, unsafe, or impossible without it.
2. A standard-library function or data type cannot solve the problem cleanly.
3. The feature can preserve deterministic budgets and causal provenance.
4. Diagnostics and migration behaviour are specified.
5. The implementation cost does not displace the active gameplay milestone.

## 3. Layered complexity model

Players should encounter complexity in this order:

1. Values and parameters.
2. Function calls.
3. Conditionals.
4. Options and pattern matching.
5. Lists and selection.
6. Explicit memory.
7. Messages and squad coordination.
8. Custom records and variants.
9. Higher-order composition.
10. Advanced static abstractions.

The language may contain advanced capabilities internally while the workbench exposes only the subset relevant to the current campaign or tutorial.

## 4. Version 0 — Compiler proof

Features:

- integers and booleans;
- names;
- function declaration and application;
- `let`;
- `if`;
- fixed entry point;
- explicit annotations;
- one intention constructor;
- bytecode and source maps.

Purpose: prove the full source-to-consequence chain.

## 5. Version 1 — Vertical-slice language

Features:

- strings;
- domain quantities;
- records;
- `Option`;
- pattern matching;
- lists;
- bounded higher-order list operations;
- explicit memory;
- tactical observations and intentions;
- closed standard library;
- capability checking;
- deterministic budgets;
- structured diagnostics.

This is the MVP language described in `DSL_SPEC.md`.

## 6. Version 2 — User-defined tactical models

Candidate features:

- user-defined record and variant types;
- record-update syntax;
- `Result` type;
- module-local helper namespaces;
- improved local type inference;
- typed message definitions;
- derivable equality for safe data types;
- warnings for non-exhaustive strategic states even where fallback exists.

Gameplay use:

- custom squad protocols;
- richer memory state;
- explicit strategy modes;
- safer communication handling.

## 7. Version 3 — Controlled polymorphism

Candidate features:

- rank-1 parametric polymorphism for pure functions;
- generic user helpers over lists, options, and records where tractable;
- constrained interfaces for sortable or comparable values;
- improved inference and typed completions.

Do not add unrestricted type classes or complex trait resolution. Prefer a small set of compiler-known constraints.

Gameplay use:

- reusable tactical utilities;
- policy libraries without duplicate functions;
- stronger abstractions for selection and prioritisation.

## 8. Version 4 — Effect and capability descriptions

Although runtime programs remain pure, the type system may describe requested effects or capabilities more precisely.

Candidates:

```text
Policy<CanMove + CanFire>
Intent<Movement>
Intent<Communication>
```

This is not an IO effect system. It statically describes which tactical intention families and observation capabilities a function may use.

Gameplay use:

- sharing policies across differently equipped operatives;
- better compile-time errors;
- explicit fallback composition.

## 9. Version 5 — Safe bounded recursion or structural recursion

Only consider recursion if list combinators and folds are insufficient for desired tactics.

Possible restriction:

- recursion only over compiler-recognised structurally smaller algebraic values;
- statically bounded depth;
- explicit cost inference;
- no general recursive fixpoint.

Gameplay use must be compelling enough to justify substantially greater compiler and VM complexity.

## 10. Features likely to remain excluded

- mutation;
- exceptions as control flow;
- reflection;
- metaprogramming;
- macros that generate arbitrary syntax;
- foreign function interfaces;
- Python embedding;
- runtime code loading;
- threads;
- async IO;
- unrestricted recursion;
- general objects and inheritance;
- implicit nullability;
- nondeterministic iteration;
- hidden randomness.

## 11. Syntax evolution

Syntax changes require:

- versioned parser fixtures;
- formatter updates;
- migration or clear rejection;
- diagnostic examples;
- workbench syntax-highlighting updates;
- source-map stability tests;
- saved policy compatibility decision.

Avoid cosmetic churn. Syntax should change only to improve readability, correctness, or extensibility.

## 12. Standard-library-first strategy

Before adding syntax, attempt to solve the need through:

- new tactical data types;
- standard-library function;
- policy template;
- typed configuration record;
- compiler diagnostic;
- editor tooling.

Examples:

- Do not add a loop when `List.fold` is sufficient.
- Do not add mutable state when explicit memory update is sufficient.
- Do not add special attack syntax when an intention constructor suffices.
- Do not add a query language when typed filtering functions suffice.

## 13. Tooling growth

Language complexity should be matched by tooling:

- syntax-aware completion;
- signature help;
- go to definition;
- find uses;
- inferred-type display;
- exhaustiveness suggestions;
- cost estimates;
- trace-to-source navigation;
- policy fixture runner;
- semantic diff between policy versions.

Do not add advanced language constructs without enough tooling to keep them understandable.

## 14. Compatibility strategy

Before public user-authored content exists, breaking changes may be acceptable but must increment the language version and update fixtures.

After public policy sharing exists:

- preserve source versions for a documented support window;
- provide migrations for mechanical changes;
- retain old compiler front ends where practical;
- never reinterpret old bytecode under new semantics;
- record all versions in policy bundles and replays.

## 15. Python host implications

Python makes language evolution easier because compiler phases and data structures can be changed rapidly, but it creates risks:

- accidental leakage of Python semantics;
- reliance on Python object identity;
- accidental nondeterministic ordering;
- use of exceptions instead of typed diagnostics;
- arbitrary Python values inside runtime objects.

The implementation must maintain a strict closed DSL runtime-value model. The host language is an implementation convenience, not part of the language contract.
