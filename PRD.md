# Product Requirements Document: Stanczyk

## 1. Summary

Stanczyk is a programmable terminal runtime for LÖVE applications. It combines a deterministic terminal state machine, multiple input backends, recorded-session replay, protocol inspection, and a programmable renderer.

The project should feel like a terminal emulator internally and a creative runtime externally. The parser, screen model, backend, renderer, effects, debugger, and embedding API must remain separable.

Stanczyk should be useful even when all visual effects are disabled. Its base value is correctness, replayability, inspectability, and embeddability. Effects increase differentiation and demonstration value but must not compromise the core.

## 2. Problem

Existing terminal emulators are optimised for daily interactive use. Their rendering layers are generally not designed as programmable scene systems for games, art tools, recorded demonstrations, or protocol visualisation.

Creative coding projects often solve the opposite problem poorly: they create attractive fake terminals with scripted commands but no terminal protocol, no reusable state machine, no real PTY, and no deterministic replay.

TUI developers also lack approachable tools that reveal the relationship between raw output bytes, parsed control sequences, screen mutations, modes, cursor changes, and rendered results.

Stanczyk addresses these gaps with a runtime that can act as:

- a real terminal front-end on supported desktop platforms;
- a deterministic player for terminal recordings;
- a sandboxed terminal environment in games and web builds;
- a control-sequence debugger;
- a platform for procedural terminal renderers and effects.

## 3. Goals

### 3.1 Product goals

- Provide a real, testable terminal model rather than a scripted terminal illusion.
- Make terminal sessions deterministic and replayable.
- Support both standalone and embedded usage.
- Make control-sequence behaviour inspectable.
- Allow rendering and effects to be replaced or extended without changing parser logic.
- Offer a portable sandbox mode and an optional real PTY mode.
- Be visually distinctive enough to demonstrate well in screenshots and video.
- Produce a repository that demonstrates systems design, protocol parsing, testing, rendering, IPC, and API design.

### 3.2 Learning goals

The project should expose its maintainer to:

- finite-state protocol parsers;
- terminal screen models and modes;
- Unicode width and grapheme handling;
- event sourcing and deterministic replay;
- binary and versioned file formats;
- glyph caching and GPU batching;
- native process and PTY integration;
- IPC protocol design;
- sandbox boundaries;
- property-based and golden testing;
- performance profiling and regression control.

### 3.3 Adoption goals

The first release should be credible for:

- embedding in small LÖVE games and interactive fiction;
- replaying and styling recorded terminal sessions;
- debugging output from TUIs;
- experimenting with terminal rendering effects.

It does not need to be credible as a primary daily-driver terminal at v0.1.

## 4. Non-goals

The following are explicitly outside the initial project scope:

- implementing a web browser or browser engine;
- implementing a POSIX shell;
- complete xterm, Kitty, iTerm2, or DEC compatibility;
- replacing Ghostty, WezTerm, Kitty, Alacritty, or the user’s normal terminal;
- SSH, serial, container, or remote-session management;
- a plugin marketplace or hosted service;
- multi-user collaboration;
- arbitrary untrusted native plugins;
- a full desktop environment or fantasy computer;
- AI-generated assets as a product claim;
- pixel-perfect reproduction of every host terminal’s font rendering;
- Windows PTY support in the first Unix-focused alpha;
- accessibility claims before keyboard, contrast, and screen-reader behaviour are deliberately designed.

## 5. Product principles

### 5.1 Core before spectacle

A terminal session rendered without effects must still be correct, useful, and testable.

### 5.2 Determinism by default

Recorded input must reproduce the same state transitions. Randomised effects must use an explicit seed or opt out of deterministic export.

### 5.3 Explicit compatibility

Stanczyk must publish exactly which control sequences and modes are supported. Unsupported sequences must be ignored safely, logged in debugger mode, and never silently advertised as supported.

### 5.4 Boundaries over convenience

Parser, state, backends, rendering, effects, and native integration must communicate through narrow interfaces. Direct cross-layer access is prohibited unless recorded in an ADR.

### 5.5 No hidden host execution

Sandbox mode must never execute host commands. PTY mode must be visibly distinct and must require a deliberate backend selection.

### 5.6 Procedural-first visuals

Built-in effects should be represented as code, shaders, parameters, and generated textures where practical. Asset generation is optional and never a runtime dependency.

## 6. Personas and user stories

### 6.1 Creative game developer

As a LÖVE developer, I want to instantiate a terminal object inside a game so that commands can trigger game events without spawning a real shell.

Acceptance examples:

- create an 80×24 terminal instance;
- register commands from Lua;
- emit terminal output through the same parser used by recordings and PTY output;
- map command completion to game state;
- apply a renderer preset to that instance only.

### 6.2 TUI developer

As a TUI developer, I want to see raw bytes, parsed sequences, and resulting state mutations so that I can diagnose rendering bugs.

Acceptance examples:

- feed a captured stream into Stanczyk;
- pause at any event;
- inspect active modes and cursor position;
- see which cells changed;
- identify unsupported or malformed escape sequences;
- export a minimal reproduction recording.

### 6.3 Terminal-effects author

As an effects author, I want to react to terminal events and render cells through shaders so that I can build visual behaviours without modifying terminal semantics.

Acceptance examples:

- subscribe to output, cursor, bell, scroll, and damage events;
- modify visual position, opacity, colour, and post-processing;
- use deterministic seeded randomness;
- hot-reload an effect in development;
- declare effect capabilities and configuration schema.

### 6.4 Terminal recording author

As a documentation author, I want to record and replay a terminal session deterministically so that I can produce repeatable demos and exports.

Acceptance examples:

- record raw PTY output, input, resize events, and timing;
- pause, seek, speed up, and step through playback;
- verify recording integrity;
- render with a different visual preset without changing terminal state;
- export event metadata for debugging.

### 6.5 Terminal enthusiast

As a terminal enthusiast, I want to launch a real shell in the standalone app so that I can experience the renderer with authentic terminal programs.

Acceptance examples:

- launch the configured shell through a PTY helper;
- resize the window and propagate terminal dimensions;
- run basic TUIs supported by the declared compatibility level;
- exit cleanly without orphaning the child process.

## 7. Functional requirements

### 7.1 Terminal parser and state

The core must:

- consume arbitrary byte chunks without assuming sequence boundaries;
- preserve parser state across chunks;
- decode printable UTF-8 safely;
- model cursor position, margins, modes, rendition attributes, and screen buffers;
- support primary and alternate screen buffers;
- represent cells independently from rendering objects;
- model scrollback separately from visible rows;
- expose structured state-change events or damage information;
- treat malformed or unsupported sequences predictably;
- avoid dependence on the global `love` object.

The initial compatibility subset is defined in `docs/TERMINAL_COMPATIBILITY.md`.

### 7.2 Recording and replay

The runtime must:

- record output bytes, optional input bytes, resize events, marks, and timing deltas;
- use a versioned format with a stable magic header;
- preserve raw byte streams exactly;
- allow streaming reads without loading the entire recording;
- support deterministic pause, seek, replay speed, and single-event stepping;
- support checkpoints for bounded seeking cost;
- validate frame lengths and checksums before use;
- distinguish terminal time from renderer wall-clock time;
- expose recording metadata without executing or replaying content.

The format is defined in `docs/RECORDING_FORMAT.md`.

### 7.3 Backend interface

Every backend must implement the same conceptual interface:

- `start(config)`;
- `poll(now)` returning zero or more backend events;
- `send_input(bytes)` when supported;
- `resize(columns, rows)` when supported;
- `stop(reason)`;
- `capabilities()`;
- `status()`.

Required backends:

1. Replay backend.
2. Sandboxed command backend.
3. Unix PTY backend through an external helper.

Later backends may include Windows ConPTY, serial streams, sockets, or remote sessions, but these are not v0.1 requirements.

### 7.4 Sandboxed command environment

Sandbox mode must:

- never invoke the host shell or arbitrary host binaries;
- provide a virtual command registry;
- provide an in-memory or explicitly mounted virtual filesystem;
- provide command history and completion;
- support command output as incremental byte streams;
- support asynchronous game-controlled jobs without host process execution;
- expose a documented API for commands to emit output and domain events;
- remain deterministic under a fixed event schedule and seed.

The sandbox is not required to implement POSIX shell syntax. Basic tokenisation, quoted arguments, command dispatch, and optional pipelines are sufficient if documented.

### 7.5 Native PTY mode

The desktop PTY mode must:

- spawn a configured shell or command through a pseudo-terminal;
- forward input bytes;
- stream output without blocking the LÖVE update loop;
- forward terminal resizes;
- report process exit status;
- terminate or detach children according to a documented policy;
- use a narrow framed IPC protocol between LÖVE and the helper;
- avoid loading platform-specific native code directly into the LÖVE process for the initial implementation.

### 7.6 Renderer

The renderer must:

- consume immutable or read-only terminal snapshots and damage information;
- render visible cells using a glyph atlas or equivalent cache;
- batch draw operations by texture and relevant attributes;
- render cursor shapes independently from cell content;
- support selection and optional link decoration later;
- handle wide and combining characters according to the core cell model;
- scale cleanly across window sizes;
- keep visual state separate from semantic terminal state;
- expose stable hooks for effects and debugger overlays.

### 7.7 Effects

Effects must:

- be optional;
- operate through a declared plugin interface;
- be able to subscribe to semantic events without mutating terminal state;
- distinguish per-cell, per-row, full-frame, and post-process costs;
- support seeded randomness;
- declare whether deterministic export is supported;
- fail in isolation where possible;
- expose parameters through serialisable configuration;
- include at least three built-in presets for v0.1.

Recommended initial presets:

1. Clean baseline renderer.
2. CRT/phosphor preset using shaders and temporal buffers.
3. Kinetic preset reacting to output, scroll, bell, and cursor movement.

### 7.8 Protocol debugger

The debugger must make it possible to inspect:

- byte offsets and byte values;
- parser state before and after an event;
- recognised control sequence and parameters;
- unsupported or malformed sequences;
- cursor changes;
- mode changes;
- rendition changes;
- damaged rows and cells;
- active backend status;
- recording position and checkpoint information.

The debugger should support pausing on:

- any control sequence;
- unsupported sequences;
- bell events;
- alternate-screen transitions;
- resize events;
- a selected row or cell changing.

### 7.9 Embedding API

A LÖVE project must be able to:

- create one or more terminal instances;
- select a backend per instance;
- provide geometry and font configuration;
- feed bytes directly for tests or custom backends;
- register sandbox commands;
- receive semantic events;
- update and draw the instance explicitly;
- destroy the instance and associated resources;
- run multiple independent terminals without global state collisions.

### 7.10 Standalone application

The standalone application must provide:

- backend selection;
- recording open and save operations;
- PTY command configuration;
- effect preset selection;
- debugger overlay toggle;
- pause, seek, step, and playback speed controls;
- font and grid sizing;
- safe shutdown.

A complex settings UI is not required. A simple command palette or configuration file is acceptable.

## 8. Non-functional requirements

### 8.1 Correctness

- Parser and state modules must be testable in plain LuaJIT without starting LÖVE.
- Every supported control sequence must have positive and boundary tests.
- Chunk-boundary invariance must be property-tested.
- Recording replay must match direct event application.
- Unsupported sequences must not corrupt parser state or screen state.

### 8.2 Performance

Initial target on an ordinary developer laptop:

- 60 FPS at 120×40 with the clean renderer under continuous output;
- no full-grid allocation per frame;
- no reparsing of unchanged cells;
- bounded event processing per update with configurable catch-up behaviour;
- responsive input while processing moderate output bursts;
- seek to any point in a 30-minute recording within one second after checkpoint indexing, excluding first-time index creation;
- memory growth proportional to configured scrollback and recording buffers.

These are engineering targets, not public guarantees until benchmarked.

### 8.3 Portability

- Core, replay, sandbox, and renderer should run on desktop LÖVE builds.
- Core modules should avoid OS dependencies.
- Web builds may support replay and sandbox only.
- Native PTY support initially targets macOS and Linux through the helper.
- Platform-specific code must remain under `native/` or explicit adapter modules.

### 8.4 Maintainability

- Avoid hidden singletons.
- Avoid direct `love.*` use in terminal, recording, and protocol modules.
- Use explicit constructors and dependency injection.
- Keep files focused; split modules before they become multi-purpose.
- All public interfaces must be documented and versioned before external release.
- Irreversible file-format or IPC changes require ADRs.

### 8.5 Security

- Replay files are untrusted input.
- Sandbox commands are trusted application code but must not automatically gain host execution.
- Effects are trusted Lua code in v0.1; the project must not imply strong plugin isolation.
- The PTY helper must validate frame lengths and commands.
- The app must visibly identify PTY mode.
- OSC clipboard and host-integration sequences are disabled until explicitly designed.

## 9. User experience requirements

### 9.1 Default experience

The first launch should open a sample deterministic recording or sandbox terminal rather than immediately starting a host shell.

This demonstrates the project safely and works on platforms without a PTY helper.

### 9.2 Visual hierarchy

The terminal must remain readable under all built-in presets. Effects may distort the presentation but must provide:

- an intensity control;
- a one-action route to the clean renderer;
- a reduced-motion mode for built-in effects;
- a deterministic export mode where applicable.

### 9.3 Error communication

Errors should distinguish:

- invalid recording;
- unsupported recording version;
- PTY helper missing;
- PTY helper protocol mismatch;
- child process exit;
- unsupported escape sequence;
- effect load failure;
- font or glyph failure;
- configuration error.

## 10. Data and configuration

Configuration should be serialisable and divided into:

- terminal semantics;
- backend configuration;
- renderer configuration;
- effect configuration;
- debugger configuration;
- application shortcuts.

User configuration must not be mixed into recordings. A recording may include metadata describing the original environment, but playback visuals are selected independently.

## 11. Success metrics

### 11.1 Engineering success

- Supported control-sequence fixtures pass.
- Property tests show identical final state under arbitrary input chunking.
- Direct event application and recording replay produce identical state digests.
- PTY integration runs representative commands and at least one supported TUI.
- The renderer maintains target responsiveness under benchmark fixtures.
- Example embedding requires minimal setup and no internal imports.

### 11.2 Product success

Within the first public release cycle, success would mean:

- external users can run the demo without maintainer assistance;
- at least one person embeds it in a separate LÖVE project;
- at least one TUI developer uses the debugger on a real output stream;
- at least one third-party effect or renderer experiment is created;
- issues focus on meaningful compatibility or API needs rather than basic setup failure.

No numerical adoption forecast should be treated as a release criterion.

## 12. Release boundaries

### 12.1 v0.1 required

- deterministic core parser and screen state;
- documented compatibility subset;
- replay backend and versioned recording format;
- sandbox backend and command API;
- LÖVE grid renderer;
- effect interface with clean, CRT, and kinetic presets;
- protocol debugger;
- macOS and Linux PTY helper support;
- standalone app and embedding example;
- automated tests and benchmark fixtures;
- documentation for limitations and security boundaries.

### 12.2 v0.1 optional

- recording export to image sequence;
- hyperlink inspection;
- mouse reporting;
- basic clipboard integration behind explicit permission;
- web demo;
- Windows support.

### 12.3 Later candidates

- ConPTY support;
- semantic selection and copy mode;
- inline image protocols;
- remote and SSH adapters;
- renderer packages;
- recording diff tools;
- accessibility work;
- a stable C or Lua module API independent of the standalone app.

## 13. Open product decisions

The following decisions should be resolved through ADRs before implementation reaches them:

- public project licence;
- final package/module naming conventions;
- exact font fallback strategy;
- whether mouse reporting enters v0.1;
- whether recording checkpoints are embedded or stored in a sidecar index;
- when the plugin API becomes stability-governed;
- whether the Unix PTY helper uses Rust permanently or only for the bootstrap implementation.
