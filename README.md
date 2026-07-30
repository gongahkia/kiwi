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

Documentation and initial architecture are defined. Implementation has not begun.

The first implementation unit is Milestone 0 in [`TODO.md`](TODO.md).
