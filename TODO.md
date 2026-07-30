# Stanczyk Implementation Plan

This file is the execution queue. Work from the earliest milestone containing unchecked items. Do not skip an exit criterion to begin a later milestone.

Each implementation slice should:

- preserve a passing test suite;
- avoid mixing unrelated layers;
- update documentation when behaviour changes;
- add an ADR before introducing an irreversible public format or protocol decision;
- end with a concise progress note and the next smallest safe slice.

## Milestone 0 — Repository and testable core skeleton

Goal: establish a plain-Lua core that can be tested without a running LÖVE application.

### Repository setup

- [x] Create the directory structure described in `README.md`.
- [x] Add `main.lua` and `conf.lua` with a minimal standalone application shell.
- [x] Add a dependency/bootstrap script suitable for local development.
- [x] Select and document the Lua test runner.
- [x] Add formatting and linting commands.
- [x] Add `make check`, `make test`, `make lint`, and `make run` or equivalent commands.
- [x] Add CI for core tests and linting on macOS and Linux where practical.
- [x] Add a deterministic test seed mechanism.
- [x] Record the exact supported LÖVE and LuaJIT versions in the repository.

### Core interfaces

- [x] Define `Terminal`, `Backend`, `Renderer`, `RecordingReader`, and `Effect` interface contracts as Lua documentation and small stubs.
- [x] Define typed-enough event tables with constructors and validation.
- [x] Define a central error taxonomy.
- [x] Ensure terminal and recording modules do not access global `love.*` APIs.
- [x] Add import-smoke tests for every core module.

### Exit criteria

- [x] A clean checkout can run tests using documented commands.
- [x] Core modules load under plain LuaJIT.
- [x] The LÖVE app opens a blank terminal viewport without runtime errors.
- Deferred by user request: CI passes on the initial skeleton; verify after all implementation tasks.

## Milestone 1 — Terminal model and parser foundation

Goal: consume byte streams deterministically and produce a correct basic screen model.

### Data model

- [x] Implement immutable configuration for columns, rows, scrollback limit, and compatibility profile.
- [x] Implement `Cell` with text, width role, rendition attributes, and hyperlink placeholder.
- [x] Implement row storage with dirty-range tracking.
- [x] Implement primary and alternate screen buffers.
- [x] Implement cursor state, saved cursor state, margins, tab stops, and active rendition.
- [x] Implement bounded scrollback storage.
- [x] Implement a stable state digest for tests and replay verification.

### Parser

- [x] Implement a streaming byte parser with explicit states for ground, escape, CSI entry, CSI parameter, CSI intermediate, OSC string, and ignore/recovery paths.
- [x] Preserve parser state across arbitrary input chunk boundaries.
- [x] Implement C0 controls required by the compatibility document.
- [x] Implement printable ASCII.
- [x] Implement UTF-8 decoding with replacement behaviour for malformed sequences.
- [x] Implement the first CSI movement, erase, scroll, and SGR subset.
- [x] Implement DEC save/restore cursor and mode changes required for alternate screen operation.
- [x] Implement unknown-sequence reporting without state corruption.
- [x] Emit structured parser/debug events.

### Tests

- [x] Add fixture tests for every supported control sequence.
- [x] Add property tests showing chunk-boundary invariance.
- [x] Add property tests showing parser recovery after malformed input.
- [x] Add model tests for scrolling, margins, erase operations, and alternate-screen transitions.
- [x] Add golden state snapshots for representative streams.
- [x] Add explicit tests for zero, omitted, and large CSI parameters.

### Exit criteria

- [x] The same byte stream produces the same digest under arbitrary chunking.
- [x] Basic coloured shell-style output renders correctly in state snapshots.
- [x] Alternate-screen enter/exit restores the primary screen as documented.
- [x] Unsupported sequences are reported and safely ignored.
- [x] No parser code depends on LÖVE.

## Milestone 2 — Recording format and replay backend

Goal: make terminal sessions deterministic, persistent, seekable, and inspectable.

### Format implementation

- [ ] Implement the accepted recording header and frame format from ADR-0002.
- [ ] Implement canonical metadata encoding.
- [ ] Implement frame validation, payload bounds, and checksums.
- [ ] Implement output, input, resize, mark, and checkpoint frames.
- [ ] Implement streaming writer semantics with safe close/finalisation.
- [ ] Implement streaming reader semantics with clear corruption errors.
- [ ] Implement recording version negotiation and rejection of unsupported major versions.
- [ ] Add a human-readable inspection command or tool.

### Replay backend

- [ ] Implement play, pause, resume, stop, and speed controls.
- [ ] Implement single-frame and single-control-sequence stepping.
- [ ] Implement deterministic replay time independent of wall-clock rendering time.
- [ ] Implement checkpoint creation and restoration.
- [ ] Implement a seek index with bounded memory.
- [ ] Implement marks/bookmarks.
- [ ] Expose current frame, elapsed terminal time, total duration, and checkpoint status.

### Tests

- [ ] Add encoding/decoding round-trip tests for every frame type.
- [ ] Add truncation and corruption tests at every frame boundary.
- [ ] Add replay equivalence tests against direct event application.
- [ ] Add checkpoint restore equivalence tests.
- [ ] Add deterministic speed-control tests using a fake clock.
- [ ] Add generated recordings with random chunking and resizes.

### Exit criteria

- [ ] A representative session can be saved, reopened, replayed, paused, stepped, and sought.
- [ ] Replay and direct application end in identical terminal state.
- [ ] Corrupt recordings fail safely with precise errors.
- [ ] Seeking does not require replay from the beginning once checkpoints are indexed.

## Milestone 3 — Baseline LÖVE renderer

Goal: render terminal state efficiently without mixing semantic and visual state.

### Rendering foundation

- [ ] Implement font loading and explicit cell metrics.
- [ ] Implement a glyph atlas or cache suitable for ASCII and incremental Unicode expansion.
- [ ] Implement clean rendering of backgrounds, glyphs, underline, strike, inverse, conceal, faint, and bold approximation.
- [ ] Implement block, beam, and underline cursors.
- [ ] Implement dirty-row or dirty-range redraw.
- [ ] Implement window-to-grid sizing and resize events.
- [ ] Implement high-DPI handling.
- [ ] Implement a clean renderer preset with no post-processing.
- [ ] Keep all LÖVE calls below the renderer boundary.

### Unicode rendering

- [ ] Implement width-aware placement for single-width and double-width cells.
- [ ] Implement combining-mark composition or a documented approximation.
- [ ] Implement placeholder rendering for missing glyphs.
- [ ] Add deterministic font-metric fixtures for tests where possible.

### Performance work

- [ ] Add a continuous-output benchmark fixture.
- [ ] Measure allocations per frame.
- [ ] Avoid rebuilding unchanged vertex or sprite data.
- [ ] Add configurable maximum backend events processed per update.
- [ ] Document catch-up behaviour when replay or PTY output exceeds the frame budget.

### Exit criteria

- [ ] Recorded fixtures render in the standalone application.
- [ ] The clean renderer remains readable at multiple window sizes.
- [ ] No full-grid object allocation occurs per frame.
- [ ] Target responsiveness is measured and documented for a 120×40 grid.

## Milestone 4 — Effects pipeline and procedural presets

Goal: add visual differentiation without compromising terminal semantics.

### Effect API

- [ ] Implement effect manifests with ID, version, capabilities, parameter schema, and deterministic flag.
- [ ] Implement lifecycle hooks defined in `docs/PLUGIN_API.md`.
- [ ] Implement semantic event subscriptions for output, bell, cursor movement, scroll, resize, and damage.
- [ ] Implement seeded random-number access.
- [ ] Implement serialisable effect parameters.
- [ ] Implement effect enable, disable, reorder, and failure reporting.
- [ ] Prevent effects from mutating terminal state objects.

### Built-in effects

- [ ] Implement the clean baseline as an explicit no-op effect chain.
- [ ] Implement a CRT/phosphor preset with scanlines, persistence, controlled bloom, and reduced-motion settings.
- [ ] Implement a kinetic output preset with bounded cell displacement and decay.
- [ ] Implement effect intensity controls.
- [ ] Implement a one-action reset to the clean renderer.
- [ ] Implement hot reload for built-in or development effects.

### Tests and performance

- [ ] Add deterministic effect tests using fixed seeds and times.
- [ ] Add failure-isolation tests for invalid hooks.
- [ ] Add performance budgets by effect class.
- [ ] Add screenshots or image hashes only where the CI environment is stable; prefer renderer command/state tests otherwise.

### Exit criteria

- [ ] Effects can be changed without restarting a replay.
- [ ] Disabling all effects yields the baseline renderer exactly.
- [ ] Built-in effects do not mutate terminal state or recording state.
- [ ] Deterministic presets reproduce the same event-driven visual state under a fixed seed.

## Milestone 5 — Sandboxed terminal backend and embedding API

Goal: make Stanczyk useful inside games and portable builds without host execution.

### Sandbox backend

- [ ] Implement command tokenisation with documented quoting rules.
- [ ] Implement a command registry.
- [ ] Implement incremental command output.
- [ ] Implement command history and completion.
- [ ] Implement a virtual working directory and minimal virtual filesystem interface.
- [ ] Implement built-in demonstration commands without imitating a full POSIX environment.
- [ ] Implement asynchronous application jobs through explicit scheduled callbacks.
- [ ] Ensure sandbox mode has no path to host process execution by default.

### Embedding API

- [ ] Implement public terminal instance construction.
- [ ] Implement explicit `update`, `draw`, `resize`, `feed`, and `destroy` methods.
- [ ] Implement per-instance backend and effect configuration.
- [ ] Implement sandbox command registration from a host game.
- [ ] Implement semantic event callbacks to the host game.
- [ ] Support multiple independent terminal instances.
- [ ] Add API documentation and version markers.

### Examples

- [ ] Add a minimal embedded terminal example.
- [ ] Add a game-door or puzzle example where a command changes game state.
- [ ] Add a replay-only example suitable for platforms without native helpers.

### Exit criteria

- [ ] A separate example project can embed Stanczyk using only public APIs.
- [ ] Sandbox commands can trigger host-game events.
- [ ] Multiple instances run without shared mutable state collisions.
- [ ] Sandbox mode cannot execute host commands through any documented API.

## Milestone 6 — Unix PTY helper and real shell integration

Goal: run real interactive terminal programs on macOS and Linux through a narrow helper process.

### Helper

- [ ] Scaffold `native/pty-helper` according to ADR-0003.
- [ ] Implement framed IPC over stdin/stdout or dedicated pipes.
- [ ] Implement spawn, input, resize, signal/terminate, status, output, and exit frames.
- [ ] Validate frame lengths and protocol versions.
- [ ] Implement non-blocking PTY reads.
- [ ] Implement child cleanup and helper shutdown policy.
- [ ] Avoid logging child terminal bytes to stderr by default.
- [ ] Add protocol conformance tests independent of LÖVE.

### LÖVE backend adapter

- [ ] Implement helper discovery and version handshake.
- [ ] Implement background I/O integration without blocking the render loop.
- [ ] Implement input forwarding.
- [ ] Implement resize forwarding.
- [ ] Implement process exit and helper crash reporting.
- [ ] Implement explicit PTY-mode indicators in the standalone application.
- [ ] Implement recording of PTY sessions.

### Compatibility validation

- [ ] Test ordinary shell prompts and commands.
- [ ] Test line editors using cursor movement and erase sequences.
- [ ] Test at least one supported full-screen TUI.
- [ ] Test alternate-screen entry and restoration.
- [ ] Test rapid resize sequences.
- [ ] Test clean shutdown and child termination.

### Exit criteria

- [ ] A user can run a configured shell on macOS and Linux.
- [ ] Input, output, resize, and exit status function through the helper.
- [ ] The LÖVE update loop remains responsive under output bursts.
- [ ] No child process is silently orphaned under normal shutdown paths.
- [ ] A PTY session can be recorded and replayed without the helper.

## Milestone 7 — Protocol debugger

Goal: turn the state machine into a practical inspection tool for TUI developers.

### Inspection model

- [ ] Retain event metadata required for inspection without unbounded memory growth.
- [ ] Display raw bytes and escaped representations.
- [ ] Display parser state transitions.
- [ ] Display decoded sequence names and parameters.
- [ ] Display cursor, modes, rendition, margins, and active screen.
- [ ] Display damaged rows and cells.
- [ ] Display unsupported and malformed sequences.
- [ ] Display recording position, timing, and checkpoint information.

### Controls

- [ ] Pause on any control sequence.
- [ ] Pause on unsupported or malformed input.
- [ ] Pause on bell, resize, alternate-screen transition, or selected cell change.
- [ ] Step by backend frame.
- [ ] Step by parsed sequence.
- [ ] Export a minimal selected event range to a new recording.
- [ ] Copy a human-readable diagnostic report.

### Exit criteria

- [ ] A user can identify why a fixture changed a selected cell.
- [ ] Unsupported sequences are visible with byte offsets.
- [ ] A selected event range can be exported and replayed independently.

## Milestone 8 — Release hardening

Goal: produce a credible v0.1 release rather than a private prototype.

### Documentation

- [ ] Document installation and helper setup.
- [ ] Document supported compatibility profile and known limitations.
- [ ] Document standalone controls.
- [ ] Document the embedding API.
- [ ] Document effect authoring.
- [ ] Document recording format and security considerations.
- [ ] Add troubleshooting for fonts, helper discovery, and unsupported sequences.
- [ ] Add an architecture diagram.

### Packaging

- [ ] Package desktop builds or provide reproducible packaging instructions.
- [ ] Package the correct PTY helper per supported platform.
- [ ] Verify clean-start behaviour without user configuration.
- [ ] Include sample recordings and effects.
- [ ] Choose and add a project licence.
- [ ] Add versioning and changelog policy.

### Quality

- [ ] Run compatibility fixtures and regression tests on release candidates.
- [ ] Run corruption and hostile-input tests for recordings and IPC.
- [ ] Run performance benchmarks and publish the environment and results.
- [ ] Audit public APIs for accidental internal exposure.
- [ ] Verify clean shutdown repeatedly.
- [ ] Verify reduced-motion and clean-renderer fallback.

### Release evidence

- [ ] Record a short demo showing replay, stepping, effects, sandbox embedding, and PTY mode.
- [ ] Provide a minimal example repository or self-contained example directory.
- [ ] Publish a compatibility table.
- [ ] Publish known non-goals prominently.

### Exit criteria

- [ ] All v0.1 requirements in `PRD.md` are met or explicitly deferred with rationale.
- [ ] No critical known data-corruption, child-process, or parser-state bugs remain.
- [ ] A new user can run the sample without maintainer intervention.
- [ ] The repository is ready for external issues and contributions.

## Post-v0.1 candidates

These are deliberately unordered and must not distract from v0.1:

- [ ] Windows ConPTY helper.
- [ ] Mouse tracking modes.
- [ ] OSC 8 hyperlinks.
- [ ] Clipboard integration with explicit permissions.
- [ ] Selection and copy mode.
- [ ] Inline image protocols.
- [ ] Recording diff and merge tools.
- [ ] Image-sequence or video export.
- [ ] Web replay and sandbox demo.
- [ ] Stable renderer package format.
- [ ] SSH or remote backend adapters.
- [ ] Accessibility programme.

## Deferred external verification

- [ ] CI passes on the initial skeleton.
