# Kiwi — Python Project Documentation

> Working title. Rename freely before public release.

Kiwi is a real-time, physics-aware squad tactics game in which the player does not directly command individual operatives. The player writes a small functional program that turns incomplete observations into tactical intentions. A mission then runs in real time, and an integrated causal debugger explains how battlefield consequences arose from specific expressions, data, decisions, and physical events.

The project is implemented in Python. `pygame-ce` provides the desktop application shell, rendering, input, audio, and bitmap-font presentation. The authoritative simulation, functional language toolchain, deterministic virtual machine, replay system, and causal-debugger model are project-owned Python modules and must run headlessly.

The player-facing language is **not Python**. It is a separate functional DSL with its own syntax, type system, compiler, bytecode, runtime limits, source maps, and versioning. Python is the implementation language because it supports rapid iteration on compiler architecture, simulation models, diagnostic tooling, trace analysis, and automated testing.

## Product promise

**Program the kiwi. Deploy the squad. Debug the consequences.**

The defining loop is:

1. Receive an incomplete mission briefing.
2. Select and equip a persistent squad.
3. Edit squad and operative policies in the in-game workbench.
4. Compile and validate those policies.
5. Run the mission in real time with only limited high-level signals.
6. Inspect a causal trace linking outcomes back to code and observed data.
7. Revise the kiwi and rerun or continue the campaign.

## Non-negotiable pillars

1. **Autonomous execution** — no ordinary select-and-right-click control.
2. **Functional programming** — user programs are pure transformations over immutable observations and explicit memory.
3. **Intent, not mutation** — programs request actions; the simulation resolves outcomes.
4. **Deterministic authority** — identical inputs, build, seed, and content produce identical state hashes.
5. **Causal legibility** — important outcomes can be traced back to program evaluations and world events.
6. **Small language core** — complexity is introduced through composition and libraries rather than dozens of primitive commands.
7. **Headless-first engineering** — the compiler, VM, simulation, replay, and explanation engine do not depend on pygame.

## Host stack

- Python 3.12 or later
- pygame-ce for rendering, input, audio, and window management
- project-owned fixed-step simulation
- project-owned functional DSL compiler and VM
- pytest for testing
- Hypothesis for property tests once the foundational representations stabilise
- Ruff for formatting and linting
- static type checking with mypy or Pyright, selected and pinned during Milestone 0

Pymunk, Box2D, or another external physics engine is **not** part of the MVP authority. It may later be used for non-authoritative debris or isolated experiments only after deterministic requirements are measured and documented.

## Documentation map

- `PRD.md` — product requirements, scope, users, risks, success criteria, and vertical slice.
- `GAME_DESIGN.md` — mission structure, player agency, operatives, combat, information, progression, and first scenario.
- `DSL_SPEC.md` — functional language semantics, syntax, type system, compiler, bytecode, VM, and diagnostics.
- `LANGUAGE_ROADMAP.md` — how the DSL can grow without invalidating the small-core design.
- `ARCHITECTURE.md` — repository layout, module boundaries, dependency rules, runtime pipeline, and performance budgets.
- `PYTHON_STACK.md` — Python, pygame-ce, dependency, performance, and packaging guidance.
- `SIMULATION_SPEC.md` — deterministic time, entities, observations, intentions, movement, projectiles, cover, damage, and hashing.
- `CAUSAL_DEBUGGER.md` — provenance model, trace levels, source linkage, queries, retention, and UI contract.
- `UX_UI.md` — workbench, terminal, mission view, debugger, controls, accessibility, and bitmap-font direction.
- `DATA_FORMATS.md` — source, bytecode, mission, replay, trace, save, and schema-versioning rules.
- `TESTING.md` — test layers, determinism harnesses, compiler goldens, properties, performance, and CI.
- `DECISIONS.md` — settled decisions, prohibited shortcuts, open decisions, and change process.
- [GitHub Issues](https://github.com/gongahkia/kiwi/issues) — gated implementation milestones, tasks, and exit evidence.
- `AGENTS.md` — rules for Codex and other repository agents.
- `CODEX_HANDOFF.md` — exact initial prompt and recommended implementation workflow.

## Recommended reading order

1. `AGENTS.md`
2. `PRD.md`
3. `DECISIONS.md`
4. `ARCHITECTURE.md`
5. `DSL_SPEC.md`
6. `SIMULATION_SPEC.md`
7. `CAUSAL_DEBUGGER.md`
8. The active GitHub issue
9. The specification relevant to the active milestone

## First technical proof

Before building a polished editor, campaign, or content pipeline, prove this chain headlessly:

```text
DSL source
  -> parsed AST with source spans
  -> typed core IR
  -> deterministic bytecode
  -> bounded VM evaluation
  -> emitted tactical intention
  -> deterministic simulation resolution
  -> causal event linked to the source expression
  -> replay with matching state hashes
```

The first playable proof must then demonstrate:

1. A squad fails because of a flawed policy.
2. The debugger identifies the decisive expression and evidence.
3. The player edits the function.
4. The compiler accepts the revision.
5. The same scenario and seed rerun deterministically.
6. The changed code produces a materially different tactical outcome.

If that loop is not satisfying, more missions, factions, graphics, and language features will not fix the project.

## Development

Canonical development runtime: CPython 3.12. `uv` manages the locked `.venv`; `.python-version` pins its interpreter selection. `pygame-ce` is the sole runtime dependency and is reserved for future presentation packages. It is not imported by headless commands.

```bash
uv sync --extra dev
make doctor
make check
```

Use standard `venv`/`pip` when `uv` is unavailable:

```bash
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
python -m kiwi.cli doctor
python -m ruff format --check .
python -m ruff check .
python -m mypy src tests
python -m pytest
```

`make format` applies formatting. `make check` runs formatting verification, linting, static types, and tests. The equivalent `uv` commands are `uv run --extra dev python -m kiwi.cli doctor`, `uv run --extra dev ruff format --check .`, `uv run --extra dev ruff check .`, `uv run --extra dev mypy src tests`, and `uv run --extra dev pytest`.

Parse a DSL source file headlessly with `uv run --extra dev python -m kiwi.cli parse path/to/policy.dtr`; successful parses emit stable surface-AST output and invalid input emits structured diagnostics.

Type-check and lower a DSL source file headlessly with `uv run --extra dev python -m kiwi.cli check path/to/policy.dtr`; successful checks emit stable core and source-map output and invalid input emits structured diagnostics.

Compile a type-clean source file with `uv run --extra dev python -m kiwi.cli compile path/to/policy.dtr`. Add `--output path/to/policy.kbc` to write the canonical `KWI-BC\0` bytecode payload; without it, the command reports the exact encoded byte count. Inspect compiled source with `uv run --extra dev python -m kiwi.cli disassemble path/to/policy.dtr`.

Run a named compiled entry headlessly with `uv run --extra dev python -m kiwi.cli run-policy path/to/policy.dtr entry --arg true`. Repeat `--arg` in parameter order; command-line arguments currently accept decimal integers, `true`, `false`, and `unit`. Milestone 4 source also supports strings, exact `ms`, `s`, `m`, `deg`, and `%` quantity literals; checked exact `+`, `-`, `<`, `<=`, `>`, and `>=` domain operations; built-in `Position { x, y }` and `Vector { dx, dy }` records; nominal immutable records declared with `type Name = { field: Type }`; closed `Option<T>` values using `Some(value)` or contextually typed `None`; exhaustive `match value with | Some(item) -> ... | None -> ...`; immutable `List<T>` literals such as `[1, 2]`; context-typed anonymous functions such as `fn item -> item`; and `value |> function(args...)` pipelines. Output renders closed runtime values. The command never evaluates Python source.

The simulation policy boundary accepts `MoveToward { target: Position }` and
`Wait { duration: Duration }`. MoveToward is capability-gated, uses canonical
integer route planning, and emits source-linked route and movement events; it
does not expose Python or renderer state to policy code.

The current authoring language, core IR, and bytecode use version `2`; `.dtr`
source has no header and compiles as version `2`. Historical `(1, 1, 1)`
bytecode decodes with its original semantics but cannot contain version-2
values, types, or instructions. Check the complete version-2 language example
with `uv run --extra dev python -m kiwi.cli check examples/policies/m4-language.dtr`.

Development versions are resolved in `uv.lock`; refresh them deliberately with `uv lock --upgrade`. pygame-ce is LGPL-2.1; packaging is deferred until after the vertical slice, when licence notices and distribution effects will be evaluated. The bundled BigBlue Terminal font is CC-BY-SA-4.0; its exact licence, attribution, source release, and SHA-256 are in `kiwi.render`'s packaged asset manifest.
