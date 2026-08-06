# Stanczyk

Stanczyk is a programmable terminal runtime and visual laboratory built around LÖVE.

It is not a fake hacking terminal, a browser engine, or an attempt to replace mature daily-driver terminals in its first releases. Its core is a deterministic terminal state machine that can consume recorded output, a sandboxed command environment, or a real pseudo-terminal stream. Its renderer treats terminal cells as programmable scene data rather than a fixed text surface.

The project exists at the intersection of terminal emulation, deterministic replay, creative coding, game tooling, protocol debugging, and procedural rendering.

## Product thesis

Most terminal emulators treat rendering as the final presentation layer. Stanczyk treats rendering as an extensible runtime boundary.

The project should make it possible to:

- replay terminal sessions deterministically;
- inspect each escape sequence and resulting state transition;
- embed a terminal in a LÖVE application or game;
- run a real shell through an optional native PTY helper;
- implement effects as code without modifying the terminal parser;
- build visual terminal experiences without sacrificing a correct state model.

The visual effects are a supported product surface, not the definition of the project. Generated art assets are optional and non-essential. The core value is the reusable runtime, event model, renderer architecture, and debugging surface.

## Target users

1. Creative coders and game developers who want an embeddable terminal component.
2. TUI authors who need to inspect terminal control sequences and state changes.
3. Terminal enthusiasts who want programmable rendering and replay.
4. Developers producing deterministic terminal demos, tutorials, or recordings.

## Repository documentation

Read these documents in order before implementation:

1. [`PRD.md`](PRD.md)
2. [`TODO.md`](TODO.md)
3. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
4. [`docs/TERMINAL_COMPATIBILITY.md`](docs/TERMINAL_COMPATIBILITY.md)
5. [`docs/RECORDING_FORMAT.md`](docs/RECORDING_FORMAT.md)
6. [`docs/RENDERER_AND_EFFECTS.md`](docs/RENDERER_AND_EFFECTS.md)
7. [`docs/BACKENDS.md`](docs/BACKENDS.md)
8. [`docs/PLUGIN_API.md`](docs/PLUGIN_API.md)
9. [`docs/TESTING.md`](docs/TESTING.md)
10. [`docs/SECURITY.md`](docs/SECURITY.md)
11. [`docs/RELEASE_CRITERIA.md`](docs/RELEASE_CRITERIA.md)
12. [`AGENTS.md`](AGENTS.md)

Architecture decisions are recorded under [`docs/adr`](docs/adr).

## Initial release shape

The first credible public release should include:

- a deterministic terminal parser and screen state model;
- recorded-session playback with pause, seek, and single-event stepping;
- a LÖVE renderer with a glyph atlas and effect pipeline;
- a sandboxed command environment for web and game embedding;
- a Unix PTY helper for real interactive shells;
- a protocol-inspection overlay;
- several procedural effect presets;
- a small embedding example and a standalone application;
- state, property, replay, integration, and performance tests.

Windows PTY support, full xterm compatibility, remote sessions, and production-grade accessibility are later work.

## Canonical invariant

Given the same initial state, ordered backend events, configuration, and font metrics, Stanczyk must produce the same terminal state at every event boundary.

Rendering may be nondeterministic only where a plugin explicitly opts into wall-clock time or external randomness. The core runtime and recording playback must remain deterministic.

## Proposed repository shape

```text
stanczyk/
├── main.lua
├── conf.lua
├── src/
│   ├── terminal/
│   ├── recording/
│   ├── backend/
│   ├── renderer/
│   ├── effects/
│   ├── shell/
│   ├── debugger/
│   ├── plugin/
│   └── app/
├── native/
│   └── pty-helper/
├── examples/
│   ├── standalone/
│   ├── embedded-terminal/
│   └── protocol-debugger/
├── tests/
│   ├── unit/
│   ├── property/
│   ├── fixtures/
│   ├── golden/
│   └── integration/
├── docs/
└── tools/
```

## Project status

Milestone 0 provides the repository skeleton, plain-Lua interface contracts, validated runtime events, and a blank LÖVE viewport. It remains active until a clean checkout and CI run are verified; terminal semantics begin only after those exit criteria pass.

The current implementation unit is Milestone 0 in [`TODO.md`](TODO.md).

## Development

The verified bootstrap targets are LÖVE 11.5 and LuaJIT 2.1.1785192264. Core tests use the repository test runner at [`tools/test.lua`](tools/test.lua) under LuaJIT; it prints and accepts `STANCZYK_TEST_SEED` for reproducible generated tests.

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

Run `make benchmark` to measure the headless compiler, VM, fixed ticks, causal trace capture, and replay encode/decode paths against the checked-in policy and kernel fixture. It is an informational local measurement rather than a CI pass/fail gate; use `uv run --extra dev python -m kiwi.cli benchmark source.dtr fixture.kfixture.json --entry choose --arg true --iterations 100 --ticks 60` to select the source, fixture, and bounded work count.

Run `make glasshouse` (or `uv run --extra dev python -m kiwi.glasshouse`) for the local pygame Glasshouse causal drill. Before the briefing, it detects the runtime platform and lets you choose standard (`Cmd+G`, `Cmd+T`, `Cmd+Enter`, `Cmd+R`) or function-key (`F1`, `F2`, `Cmd`/`Ctrl`+`Enter`, `F5`) controls; both modes retain visible `Compile` and `Compile + run` buttons. `Compile + run` opens an editable, line-numbered source pane on the left and a recorded deterministic scenario preview on the right, selecting the `1` in Lark's `<= 1m` caution decision; type `0` to hot-reload a no-injury rerun. Hot reload is enabled by default: source-text changes recompile and rerun the same two ticks; invalid source blocks the preview with its diagnostic rather than showing stale results. The `Theme` button, `F3`, or `Cmd`/`Ctrl`+`Shift`+`T` cycles cyan, amber, and phosphor palettes. Typing a DSL prefix opens a bounded hard-coded completion list; `Tab` accepts its first result, or changes policy when no completion is available. Click `Pause`, `Step`, or `Hot reload`; `Cmd`/`Ctrl`+`P`, `Cmd`/`Ctrl`+`.`, and `Cmd`/`Ctrl`+`L` are alternatives. The trace panel is backed by retained policy/intention/world-event records and selects the responsible current source span. Policies evaluate once each fixed tick; the DSL has no unbounded loops. Click the source to position the blinking cursor; `D` opens the debrief, `R` follows causal evidence to source, and `Esc` returns to the workbench or exits before the briefing. The drill is local-only and does not submit telemetry or test responses.

Parse a DSL source file headlessly with `uv run --extra dev python -m kiwi.cli parse path/to/policy.dtr`; successful parses emit stable surface-AST output and invalid input emits structured diagnostics.

Type-check and lower a DSL source file headlessly with `uv run --extra dev python -m kiwi.cli check path/to/policy.dtr`; successful checks emit stable core and source-map output and invalid input emits structured diagnostics.

Compile a type-clean source file with `uv run --extra dev python -m kiwi.cli compile path/to/policy.dtr`. Add `--output path/to/policy.kbc` to write the canonical `KWI-BC\0` bytecode payload; without it, the command reports the exact encoded byte count. Inspect compiled source with `uv run --extra dev python -m kiwi.cli disassemble path/to/policy.dtr`.

Run a named compiled entry headlessly with `uv run --extra dev python -m kiwi.cli run-policy path/to/policy.dtr entry --arg true`. Repeat `--arg` in parameter order; command-line arguments currently accept decimal integers, `true`, `false`, and `unit`. Milestone 4 source also supports strings, exact `ms`, `s`, `m`, `deg`, and `%` quantity literals; checked exact `+`, `-`, `<`, `<=`, `>`, and `>=` domain operations; built-in `Position { x, y }` and `Vector { dx, dy }` records; nominal immutable records declared with `type Name = { field: Type }`; closed `Option<T>` values using `Some(value)` or contextually typed `None`; exhaustive `match value with | Some(item) -> ... | None -> ...`; immutable `List<T>` literals such as `[1, 2]`; context-typed anonymous functions such as `fn item -> item`; and `value |> function(args...)` pipelines. Output renders closed runtime values. The command never evaluates Python source.

Query an encoded `KWI-TRACE\0` packet headlessly with `uv run --extra dev python -m kiwi.cli trace-query path/to/run.ktrace why-selected 1`. The query name is one of `why-selected`, `why-not-selected`, `why-failed`, or `consequence-chain`; the final positive ID is an intention ID except for `consequence-chain`, which takes a trace node ID. Output is deterministic evidence or an explicit retention-unavailable code.

Record a policy-free kernel-fixture replay with `uv run --extra dev python -m kiwi.cli replay-record tests/fixtures/minimal.kfixture.json 3 /tmp/minimal.drun --application-build dev --simulation-version sim-v1`. The command hashes the exact fixture bytes as mission content, records every checkpoint, and writes strict `KWI-RUN\0` v1 bytes. Use `replay-verify /tmp/minimal.drun`, `replay-inspect /tmp/minimal.drun`, and `replay-compare expected.drun actual.drun` for deterministic verification, metadata inspection, and baseline/policy-manifest comparison. The current CLI cannot resolve policy bundles, so it verifies only policy-free replay packets.

The simulation policy boundary accepts `MoveToward { target: Position }`,
`TakeCover { cover_id: Int, side: String }`, and `Wait { duration: Duration }`.
MoveToward is capability-gated, uses canonical integer route planning, and emits
source-linked route and movement events. TakeCover is capability-gated and
reserves the first eligible requested-side slot with deterministic contention
events. The direct-only `Cover` helpers rank supplied visible geometry and
contacts without reading hidden map, reservation, or renderer state. Neither
exposes Python or renderer state to policy code.

The current authoring language, core IR, and bytecode use version `2`; `.dtr`
source has no header and compiles as version `2`. Historical `(1, 1, 1)`
bytecode decodes with its original semantics but cannot contain version-2
values, types, or instructions. Check the complete version-2 language example
with `uv run --extra dev python -m kiwi.cli check examples/policies/m4-language.dtr`.

Development versions are resolved in `uv.lock`; refresh them deliberately with `uv lock --upgrade`. pygame-ce is LGPL-2.1; packaging is deferred until after the vertical slice, when licence notices and distribution effects will be evaluated. The bundled BigBlue Terminal font is CC-BY-SA-4.0; its exact licence, attribution, source release, and SHA-256 are in `kiwi.render`'s packaged asset manifest.
