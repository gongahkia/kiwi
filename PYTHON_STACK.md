# Python Stack and Implementation Guidance

## 1. Recommendation

Use Python as the host implementation language and pygame-ce as the graphical layer. Keep the functional DSL, VM, tactical simulation, and durable data formats independent from Python semantics.

Python is the preferred host because the project’s difficult work is dominated by:

- compiler data structures and diagnostics;
- repeated language-design iteration;
- deterministic state transforms;
- causal graph construction and queries;
- replay tooling;
- automated fixture generation and testing;
- custom editor and analysis interfaces.

The target scale is a compact small-squad simulation, so the project should not assume a performance problem before profiling.

## 2. Runtime dependencies

### Required

- `pygame-ce`: window, events, input, audio, image loading, drawing, and frame presentation.

### Not initially required

- Pymunk or another physics engine;
- an ECS framework;
- a parser generator;
- NumPy;
- a GUI toolkit;
- an embedded database;
- a serialisation framework;
- a game engine editor.

Keep the initial runtime dependency surface small.

## 3. Development dependencies

Recommended categories:

- `pytest` for tests;
- `hypothesis` for property tests;
- `ruff` for formatting and linting;
- `mypy` or Pyright for static checking;
- coverage tooling if useful;
- packaging tooling only when distribution work begins.

Select exact versions and lock them in Milestone 0. Do not encode current version numbers in architecture documents unless the repository pins them.

## 4. Project layout

Use a src layout and `pyproject.toml`. Avoid running code from repository-relative import accidents.

The package should be installable in editable mode for development, and CLI tools should work through `python -m kiwi.cli` or registered console scripts.

## 5. Data structures

Use:

- frozen slotted dataclasses for durable values;
- enums or tagged dataclasses for variants;
- immutable tuples in canonical state where useful;
- stable typed IDs rather than raw strings;
- explicit builders for high-volume tick-local work;
- read-only presentation snapshots.

Avoid:

- arbitrary nested dictionaries as the main domain model;
- Python object identity as IDs;
- mutable default fields;
- ad hoc tuples with undocumented positions;
- storing pygame surfaces or vectors in authority.

## 6. Numeric discipline

Python integers are useful for deterministic canonical quantities. Define wrappers or typed aliases for:

- ticks;
- distance subunits;
- angle units;
- probability basis points;
- health and suppression;
- IDs.

Do not rely on runtime type aliases alone to prevent unit errors; the DSL type system and simulation APIs should use explicit constructors and validators.

## 7. Performance strategy

Optimise in this order:

1. Measure with representative fixtures.
2. Fix algorithmic problems.
3. Reduce unnecessary allocations in hot paths.
4. Use slotted structures and local variables.
5. Batch geometry and trace operations.
6. Reduce trace detail when appropriate.
7. Consider specialised arrays or native extension only for measured bottlenecks.

Do not rewrite in Rust or C before semantics and profiling stabilise. If a native extension is later required, keep a Python reference implementation and deterministic equivalence tests.

## 8. Concurrency

The MVP should be single-threaded in authority. Deterministic policy evaluations may conceptually be independent, but parallel execution introduces ordering, error, and trace complexity without necessity at small scale.

Background threads may later handle non-authoritative tasks such as asset loading or compression, provided they do not mutate authority.

## 9. Error model

Use typed result values or domain exceptions at clear external boundaries. Internally:

- compiler errors are collected diagnostics;
- DSL runtime problems are VM fault values;
- content errors are validation issue lists;
- replay incompatibility is a typed error;
- simulation invariant failure is an internal defect with context.

Do not display raw Python tracebacks for normal player mistakes.

## 10. pygame boundary

pygame modules may:

- initialise display and audio;
- translate events into application actions;
- render snapshots;
- manage bitmap fonts and textures;
- play non-authoritative effects.

pygame modules may not:

- update operative authority;
- calculate canonical collision outcomes;
- read or mutate policy memory;
- decide objective completion;
- generate unrecorded authoritative randomness;
- use frame delta to advance authority directly.

## 11. Optional Pymunk policy

Pymunk is deferred. If introduced later:

- specify whether it is visual-only or authoritative;
- document platform determinism expectations;
- isolate it behind an adapter;
- prevent its objects from entering canonical formats;
- provide a deterministic fallback or reference path if authority depends on it;
- add replay equivalence tests.

The default remains project-owned tactical geometry.

## 12. Packaging

Do not select a packager in Milestone 0 as an irreversible architecture choice. After the vertical slice, evaluate candidates using:

- macOS application behaviour;
- Windows and Linux support;
- pygame asset handling;
- startup time;
- bundle size;
- code signing implications;
- reproducibility;
- licence notices.

## 13. Why not expose Python to players

Exposing Python would undermine:

- deterministic sandboxing;
- instruction budgets;
- closed capability model;
- source-level causal instrumentation;
- stable semantics;
- safe replay loading;
- beginner-focused language design;
- future type-system evolution.

Python is the implementation language because it accelerates building the game’s language. It should not become the game’s language.
