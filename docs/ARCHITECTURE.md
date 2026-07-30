# Architecture

## 1. System overview

Stanczyk is divided into six major layers:

```text
backend event source
        ↓
normalised runtime events
        ↓
terminal parser and semantic state
        ↓
state-change log and damage model
        ↓
renderer snapshot
        ↓
effects, overlays, and final frame
```

Cross-cutting systems provide recording, debugging, configuration, clocks, and tests.

The central rule is that bytes and resize events affect terminal semantics before rendering. Renderers and effects observe state; they do not define it.

## 2. Layer responsibilities

### 2.1 Backend layer

Backends produce normalised events:

- `output(bytes)`;
- `input(bytes)` for recording or echo metadata;
- `resize(columns, rows)`;
- `mark(name, data)`;
- `status(state, detail)`;
- `exit(code, signal)`;
- `clock_advance(delta_us)` where required by storage or tests.

Backends do not modify the screen directly.

### 2.2 Runtime coordinator

The coordinator:

- polls the active backend;
- orders events;
- advances deterministic terminal time;
- records events when recording is enabled;
- feeds output bytes into the terminal parser;
- applies resize events;
- publishes semantic and damage events;
- updates effects using explicit terminal and visual clocks;
- presents snapshots to the renderer.

The coordinator should be small. It must not contain parser logic, PTY protocol logic, or shader code.

The bootstrap coordinator owns applying replay events to a terminal. Frame and control-sequence stepping remain here: the replay backend exposes raw framed data, while only the coordinator feeds output bytes into the parser and terminal model.

### 2.3 Terminal core

The terminal core includes:

- byte-stream parser;
- UTF-8 decoder;
- control-sequence dispatcher;
- terminal modes;
- screen buffers;
- scrollback;
- cursor and rendition state;
- cell and row model;
- damage tracking;
- semantic event emission;
- deterministic state digest.

It has no dependency on LÖVE, filesystems, subprocesses, or wall-clock APIs.

### 2.4 Recording subsystem

The recording subsystem:

- serialises normalised events;
- preserves raw bytes;
- maintains versioned metadata;
- writes and validates checksums;
- creates checkpoints;
- indexes recordings for seek;
- replays events using a supplied clock;
- exposes an inspection stream.

It does not render and does not execute recorded input.

### 2.5 Renderer

The renderer:

- maps terminal cells to glyphs and quads;
- applies cell backgrounds and decorations;
- draws the cursor;
- manages glyph caches and atlases;
- consumes damage regions;
- supplies intermediate targets for effects;
- draws overlays such as the debugger.

Renderer state may be mutable and GPU-specific. It is not serialised as terminal truth.

### 2.6 Effects

Effects may:

- observe semantic terminal events;
- maintain visual-only state;
- alter cell transforms and visual properties;
- add geometry before or after the terminal;
- run post-processing shaders;
- react to deterministic terminal time;
- use a supplied seeded PRNG.

Effects may not:

- modify cell text or terminal modes;
- inject backend input unless explicitly implemented as a separate trusted controller;
- alter recordings;
- read ambient randomness when deterministic mode is active;
- access PTY helper internals.

### 2.7 Debugger

The debugger consumes structured trace events from the backend, parser, terminal model, recording reader, and coordinator. It should not require ad hoc introspection into private tables.

## 3. Suggested module graph

```text
src/app/
  standalone.lua
  commands.lua
  config.lua

src/runtime/
  coordinator.lua
  event.lua
  clock.lua
  errors.lua

src/terminal/
  terminal.lua
  parser.lua
  utf8.lua
  dispatcher.lua
  screen.lua
  row.lua
  cell.lua
  cursor.lua
  modes.lua
  rendition.lua
  scrollback.lua
  damage.lua
  digest.lua
  sequences/

src/recording/
  format.lua
  binary.lua
  checksum.lua
  writer.lua
  reader.lua
  checkpoint.lua
  index.lua

src/backend/
  interface.lua
  replay.lua
  sandbox.lua
  pty_helper.lua
  direct.lua

src/renderer/
  renderer.lua
  font.lua
  glyph_atlas.lua
  grid_mesh.lua
  cursor.lua
  canvas_pool.lua
  metrics.lua

src/effects/
  host.lua
  manifest.lua
  clean.lua
  crt.lua
  kinetic.lua

src/shell/
  registry.lua
  tokenizer.lua
  environment.lua
  virtual_fs.lua
  completion.lua
  job.lua

src/debugger/
  trace.lua
  breakpoint.lua
  overlay.lua
  export.lua

src/plugin/
  loader.lua
  api.lua
  validation.lua
```

Names may evolve, but layer ownership must remain clear.

## 4. Core state model

### 4.1 Terminal

A terminal instance owns:

- immutable configuration;
- parser state;
- current screen buffer selector;
- primary screen;
- alternate screen;
- cursor and saved cursor;
- active rendition;
- terminal modes;
- tab stops;
- top and bottom margins;
- scrollback;
- title and metadata fields where supported;
- monotonic semantic revision;
- damage accumulator;
- debug trace sink.

### 4.2 Cell

A cell should conceptually contain:

```text
text: UTF-8 grapheme or empty
width: 0, 1, or 2
continuation: boolean
foreground: indexed/RGB/default colour
background: indexed/RGB/default colour
attributes: bitset
hyperlink_id: optional later field
revision: optional optimisation field
```

A wide glyph occupies a lead cell and a continuation cell. Operations that erase or overwrite either position must preserve row consistency.

The semantic cell representation must not store LÖVE font, quad, shader, pixel coordinate, or animation state.

### 4.3 Row

A row owns a fixed number of cell slots and tracks:

- minimum and maximum dirty columns;
- wrapped-line metadata;
- row revision;
- optional semantic line identifier for scrollback and selection work.

### 4.4 Screen

A screen owns visible rows and cursor-related buffer state. Scrollback belongs to the terminal or primary-screen policy rather than the alternate screen.

### 4.5 State digest

The digest used in tests should include all semantic state that affects future behaviour:

- dimensions;
- active buffer;
- visible cell contents and attributes;
- scrollback contents within configured scope;
- cursor and saved cursor;
- modes;
- margins;
- tab stops;
- rendition;
- parser state and partial sequence buffers;
- title or metadata fields that are semantically exposed.

It must exclude:

- GPU resources;
- effect state;
- wall-clock timestamps;
- debug counters not affecting behaviour;
- table addresses or iteration order.

## 5. Parser architecture

Use an explicit state machine rather than regular-expression matching over complete strings.

Requirements:

- accept arbitrary byte chunks;
- process one byte at a time or in equivalent state-preserving batches;
- limit parameter counts and intermediate buffers;
- provide predictable recovery from malformed input;
- distinguish execute, collect, parameter, dispatch, and ignore actions;
- expose trace events without changing parse behaviour.

A table-driven parser is preferred if it remains readable and testable. Generated parser tables are acceptable only when the generator is checked in and deterministic.

## 6. Event ordering

Within a terminal instance, events are totally ordered.

Rules:

1. Backend events are assigned a sequence number by the coordinator.
2. Recording preserves this order.
3. Output bytes are parsed completely before the next backend event is applied, unless a future ADR introduces bounded interleaving.
4. Resize events apply atomically between output events.
5. Semantic events emitted during parsing inherit the parent backend sequence number and a local ordinal.
6. Effects observe semantic events after the terminal mutation that caused them.
7. Renderer snapshots are taken only at defined update boundaries.

## 7. Clocks

Stanczyk uses separate clocks:

- **terminal clock:** deterministic time advanced by backend or replay events;
- **visual clock:** time used for animation, normally derived from terminal time in deterministic mode and wall time in interactive mode;
- **wall clock:** host time, confined to application scheduling and never required by core tests.

Tests inject fake clocks.

## 8. Damage model

The terminal core should report the smallest practical changed region without making correctness depend on damage accuracy.

Damage categories may include:

- cell range changed;
- row replaced;
- region scrolled;
- full screen invalidated;
- cursor moved or changed;
- palette or default colours changed;
- title or metadata changed.

During early milestones, full-row invalidation is acceptable. Full-screen invalidation on every byte is not.

## 9. Snapshot boundary

The renderer should receive either:

- read-only references valid until the next core mutation; or
- an explicit snapshot object with structural sharing.

Do not deep-copy the full grid every frame.

The chosen ownership model must be documented when implemented. A simple single-threaded read phase after update is acceptable for v0.1.

## 10. Concurrency

LÖVE rendering remains on the main thread.

Potential background work:

- PTY helper I/O;
- recording indexing;
- font glyph rasterisation if supported safely;
- export encoding.

All cross-thread or cross-process messages must be framed and validated. The core terminal should initially remain single-threaded to preserve deterministic ordering.

## 11. Error taxonomy

Suggested categories:

- `config_error`;
- `parser_error` for internal invariant failures, not unsupported user input;
- `recording_corrupt`;
- `recording_unsupported_version`;
- `recording_io_error`;
- `backend_unavailable`;
- `backend_protocol_error`;
- `backend_exited`;
- `sandbox_command_error`;
- `renderer_resource_error`;
- `effect_load_error`;
- `effect_runtime_error`;
- `internal_invariant_error`.

Unsupported or malformed terminal sequences are trace events, not necessarily application errors.

## 12. Configuration layering

Configuration resolution order:

1. built-in defaults;
2. project or application defaults;
3. user configuration;
4. command-line or runtime overrides;
5. per-terminal instance options.

Recordings do not override renderer or effect configuration. They may specify original dimensions and metadata used as defaults.

## 13. Dependency policy

- Prefer small, auditable dependencies.
- Core terminal semantics should not rely on a large external terminal emulator library, because implementing and understanding this layer is a project goal.
- Native PTY functionality may use a focused library in the helper.
- Vendored Unicode tables must include source and generation instructions.
- Avoid dependencies that require a full package manager at runtime for end users.
- Pin build-time native dependencies for reproducible helper builds.

## 14. Architectural invariants

1. Terminal state is a pure function of initial state and ordered semantic inputs.
2. Rendering cannot change terminal semantics.
3. Effects cannot change terminal semantics.
4. Recordings preserve raw output bytes exactly.
5. Sandbox mode cannot execute host commands.
6. PTY protocol payloads are length-bounded and versioned.
7. Unsupported terminal sequences cannot corrupt parser state.
8. Core modules are loadable without LÖVE.
9. Multiple terminal instances do not share mutable semantic state.
10. Public persistent formats change only through versioned ADR-backed decisions.
