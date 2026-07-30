# Testing Strategy

## 1. Objectives

Testing must establish:

- parser correctness under arbitrary byte chunking;
- semantic state correctness;
- safe recovery from malformed and unsupported input;
- recording round trips and replay equivalence;
- backend contract compliance;
- PTY helper lifecycle correctness;
- renderer invariants and performance;
- effect isolation and deterministic behaviour;
- embedding API stability.

## 2. Test layers

### 2.1 Unit tests

Use for:

- individual parser actions;
- cell and row operations;
- cursor movement;
- margins and scrolling;
- colour and rendition parsing;
- binary encoding helpers;
- checksums;
- tokenizer and sandbox commands;
- effect manifest validation.

### 2.2 Model tests

Use small reference models where practical for:

- cursor clamping;
- erase behaviour;
- insert/delete operations;
- scroll regions;
- queue ordering;
- checkpoint restore.

### 2.3 Property tests

Required properties include:

1. **Chunk-boundary invariance**  
   Splitting the same byte stream at arbitrary positions produces the same final state and trace sequence.

2. **Replay equivalence**  
   Applying events directly and replaying their recording produces the same state digest.

3. **Checkpoint equivalence**  
   Restoring a checkpoint and replaying the suffix equals replaying from the beginning.

4. **Encode/decode round trip**  
   Valid recording frames decode to the original values.

5. **Malformed input containment**  
   Random malformed sequences do not crash, exceed configured buffers, or violate state invariants.

6. **Resize invariants**  
   After arbitrary valid resizes, cursor, rows, wide cells, and margins remain valid.

7. **Effect non-interference**  
   Enabling any built-in effect does not change the terminal state digest.

8. **Deterministic effect replay**  
   Fixed events, time, parameters, and seed reproduce the same effect-state digest.

Every generated failure must print the seed and a minimisable case representation.

## 3. Golden fixtures

Golden fixtures should contain:

- input bytes or recording;
- expected semantic state snapshot;
- expected trace summary where useful;
- compatibility profile;
- fixture provenance and purpose.

Golden state should use a stable human-readable form, not raw Lua table serialisation with nondeterministic ordering.

Recommended snapshot sections:

```text
profile
size
active_buffer
cursor
modes
margins
rendition
visible_rows
scrollback_tail
parser_state
unsupported_events
```

## 4. Recording corruption matrix

Test corruption at:

- every preamble field boundary;
- metadata length and checksum;
- every frame header field;
- payload truncation at zero, middle, and final byte;
- invalid payload lengths;
- invalid checksums;
- unsupported major version;
- unknown minor fields;
- invalid resize payloads;
- malformed checkpoints;
- integer overflow and offset overflow paths.

The reader must fail without allocating unbounded memory or partially applying a corrupt frame.

## 5. PTY helper tests

### 5.1 Protocol tests

- valid handshake;
- version mismatch;
- unknown message kind;
- oversized frame;
- truncated frame;
- invalid UTF-8 in metadata fields where text is required;
- raw binary output payload preservation;
- message ordering.

### 5.2 Lifecycle tests

- spawn success;
- spawn failure;
- ordinary exit code;
- signal termination;
- helper shutdown;
- LÖVE-side disconnect;
- child cleanup;
- rapid resize;
- sustained output;
- input after exit;
- idempotent stop.

### 5.3 Platform tests

Maintain a small platform matrix. Tests should avoid assuming one shell prompt or locale. Prefer purpose-built helper child programs for deterministic integration tests.

## 6. Renderer tests

State correctness should not depend on screenshot comparison.

Testable renderer components:

- layout calculations;
- cell-to-pixel mapping;
- dirty-range translation;
- glyph-cache keys;
- atlas allocation;
- wide-cell geometry;
- cursor geometry;
- effect ordering;
- parameter validation;
- deterministic effect-state evolution.

Renderer unit tests use deterministic fixture fonts for ascent, height, width, and glyph coverage. They do not depend on host-installed fonts or screenshot output.

Visual regression tests may be added for stable environments, but should be limited and reviewed carefully.

## 7. Performance tests

Benchmark fixtures:

- plain continuous output;
- colour-heavy logs;
- full-screen redraws;
- scrolling region stress;
- wide-character output;
- alternate-screen TUI-style updates;
- replay seek and checkpoint restoration;
- CRT post-processing;
- kinetic event bursts;
- PTY output burst handling.

Record:

- environment;
- LÖVE and LuaJIT versions;
- grid size;
- font configuration;
- effect chain;
- events or bytes per second;
- frame time percentiles;
- allocations where measurable;
- memory growth.

Do not make performance claims without publishing the fixture and environment.

## 8. Determinism controls

Tests must use:

- injected clocks;
- explicit seeds;
- canonical JSON and snapshot ordering;
- fixed font test metrics where possible;
- no dependency on local shell prompts;
- no dependency on current date, locale, or username;
- bounded scheduling with deterministic queue order.

## 9. CI tiers

### Fast tier

Run on every change:

- lint;
- unit tests;
- core property tests with fixed seeds;
- golden state tests;
- recording round trips;
- import smoke tests.

### Full tier

Run on merge or release candidates:

- larger generated-property runs;
- corruption matrix;
- PTY helper integration;
- renderer smoke tests;
- performance regression checks;
- packaging checks.

## 10. Test acceptance rule

A bug fix is incomplete until a failing reproduction exists at the lowest practical layer and passes after the fix.
