# Data Formats and Versioning

## 1. Purpose

Kiwi stores player source, compiled policy bundles, mission content, replay inputs, canonical snapshots, causal traces, settings, and later campaign state. Durable formats must be explicit, versioned, validated, and safe to load without executing Python code.

## 2. General rules

- Never use `pickle`, `marshal`, or arbitrary Python object serialisation for durable or untrusted files.
- Every top-level format includes a format identifier and integer schema version.
- IDs, quantities, and variants have canonical encodings.
- Parsers reject unknown required fields and malformed values with structured errors.
- Optional forward-compatible fields must be intentionally defined.
- Canonical hashing uses a stable byte encoding, not ordinary dictionary stringification.
- File loading has size and nesting limits.
- Migrations are explicit functions from one validated schema version to the next.
- Replays and traces record content hashes rather than assuming current files match historical runs.

## 3. Recommended encodings

### Human-authored content

Use UTF-8 source text and a human-readable structured format selected during Milestone 0 or the first content milestone. JSON is acceptable for early fixtures. TOML may be used for simple configuration. Do not add YAML unless its complexity is justified.

### Canonical internal bytes

Kiwi currently uses a small deterministic binary encoding for:

- state hashing;
- bytecode;
- replay checkpoints;
- trace chunks where size matters.

`KWI-STATE\0` version `18` is the canonical mission-state payload. It uses a
fixed big-endian field order, fixed-width scalar values, and ordered bounded
collections; it contains no Python object serialisation. BLAKE2b-256 hashes the
exact payload. Decoders reject versions `1` through `17`, unsupported versions,
malformed values, size limits, and trailing bytes rather than reinterpreting data.

## 4. Policy source

Suggested extension: `.dtr`

Policy source files contain:

- optional language-version header;
- declarations;
- policy entry points;
- comments.

Example:

```text
language 2

policy cautious(view: Observation, memory: Memory) -> Decision =
  ...
```

If no header is allowed in the initial syntax, language version belongs in the containing project manifest.

The current parser has no source-header syntax. It compiles all accepted `.dtr`
source as language version `2`; only historical `(1, 1, 1)` bytecode has a
compatibility decoder and it is never reinterpreted as current source.

## 5. Policy project manifest

Suggested file: `kiwi.policy.json`

Fields:

```json
{
  "format": "kiwi-policy-project",
  "version": 1,
  "name": "cautious-alpha",
  "language_version": 2,
  "entry_points": {
    "operative": "src/cautious.dtr#cautious"
  },
  "parameters": "parameters.json"
}
```

The manifest must not allow arbitrary paths outside the policy root.

## 6. Compiled policy bundle

Suggested extension: `.dpol`

A bundle contains:

- format and version;
- source language version;
- bytecode version;
- tactical API version;
- standard-library version;
- compiler build identifier;
- source module hashes;
- normalised historical source or source archive reference;
- constant pool;
- function table;
- bytecode instructions;
- type summary;
- capability manifest;
- source map;
- entry-point metadata;
- bundle hash.

Bytecode must not contain Python code objects, import paths, callables, or pickled values.

Milestone 4's in-memory `CapabilityManifest` is versioned separately from the
raw bytecode payload and currently has empty requirements. Adding it to a
compiled-policy bundle is deferred until the bundle format exists; it must not
silently alter the canonical `KWI-BC\0` encoding.

Kiwi encodes bytecode payloads with the `KWI-BC\0` binary format, encoding
version `1`. It has fixed big-endian integer fields and ordered length-prefixed
collections; its source map inherits source-file ID from the module header. The
current compiler emits source, core, and bytecode version `2`; the decoder also
accepts legacy `(1, 1, 1)` modules without reinterpreting them. Version 2 adds
bounded strings, dimension-tagged normalized rational quantities, records, and
closed `Option<T>` values. `Option<T>` uses version-2 type tag `11`; its values
use `BUILD_SOME` opcode `13` and `PUSH_NONE` opcode `14`. Option-match control
uses `JUMP_IF_NONE`, `UNWRAP_SOME`, and `POP` opcodes `15` through `17`; a
version-1 module rejects all six. `List<T>` uses version-2 type tag `12` and
`BUILD_LIST` opcode `18`; a version-1 module rejects both. List values are not
constants: `BUILD_LIST` encodes an ordered element count and the VM consumes
that many stack values in source order. Closures use `BUILD_CLOSURE` opcode
`19`, encoding its synthetic function ID and source-ordered capture count;
version-1 modules reject it. `PUSH_INTRINSIC` opcode `20` encodes one closed
one-byte standard-library identifier and is likewise rejected by version 1;
tags 1 through 6 are List intrinsics and tags 7 through 10 are Cover intrinsics.
`CALL` dispatches that identifier without a Python callable or dynamic lookup.
`BINARY_OPERATION` opcode `21` encodes one closed one-byte exact domain operator
and is likewise rejected by version 1. It operates only on statically checked
exact quantity and coordinate records; it does not encode host callables.
Record fields are encoded as an ordered field-name sequence and become lexically
ordered immutable runtime values. The payload
decoder has explicit size, collection, text, integer, and type-nesting limits,
rejects trailing bytes, and validates decoded bytecode before returning it. See
`DSL_SPEC.md` section 16.1 for the complete canonical layout.

## 7. Mission content

Suggested extension: `.dmission.json`

Top-level fields:

```json
{
  "format": "kiwi-mission",
  "version": 1,
  "id": "glasshouse",
  "map": {},
  "entities": [],
  "objectives": [],
  "deployment": {},
  "signals": [],
  "timers": [],
  "seed_manifest": {}
}
```

Validation occurs in two stages:

1. Shape and primitive validation.
2. Semantic validation, including references, geometry, capabilities, objective reachability assumptions where practical, and deterministic ordering.

Milestone 5 selects JSON for the separate, deliberately narrow
`.kfixture.json` kernel-fixture format. Its top-level `format` is
`"kiwi-kernel-fixture"`, version is integer `1`, and required fields are `id`,
`tick_rate`, unsigned 64-bit `seed`, content-ID keyed `entities`, and
`scheduled_triggers`. Entity maps are canonically sorted by lowercase ASCII
content ID before the simulation bootstrap assigns dynamic IDs; therefore JSON
member insertion order cannot affect authority. The loader accepts only UTF-8,
rejects duplicate and unknown fields, bounds bytes, nesting, and collection
sizes, and returns structured JSON-path diagnostics. This format is not the
future full `kiwi-mission` schema.

## 8. Canonical state snapshot

Suggested extension: `.dsnap`

Snapshot fields:

- format and version;
- simulation semantic version;
- tick;
- content hashes;
- canonical state payload;
- random-stream states;
- policy memory;
- scheduled events;
- command cursor;
- state hash.

Snapshots must contain all authority required to resume. Presentation state is excluded.

The current internal canonical-state payload is distinct from the future
`.dsnap` container: it encodes the authority state only, starting with
`KWI-STATE\0`, 16-bit format version `18`, tick, phase, entities, optional map
geometry, entity-ID ordered active movement actions, policy-memory records,
entity-ID ordered policy-version records, cover geometry, and `(cover ID, slot
index)`-ordered cover reservations, weapon-ID-ordered equipped weapons with
bounded magazines, entity-ID-ordered nonzero aim qualities, entity-ID-ordered
nonzero suppression values, projectile-ID-ordered live point projectiles with
their Fire intention ID, invocation ID, expression ID, source file/span,
policy-list index, and creation tick,
entity-ID-ordered non-default operative conditions, type-local ID allocator
counters, scheduled-event queue, random-algorithm
version, root seed, and named random-stream states.
Counts are 32-bit big-endian values bounded to 65,536 items. Memory values are
closed data-only DSL values: integers, booleans, unit, UTF-8 strings, exact
quantities, options, lists, and lexically ordered records; callable values are
rejected. Entity coordinates are signed 64-bit millimetres; elevation,
sequences, stream state, and seed use unsigned 64-bit values. A policy-version
record contains an entity ID and a 32-byte BLAKE2b digest of canonical `KWI-BC`
bytes plus its selected entry function ID. Versions `1` through `4` are
intentionally unsupported. Versions `5` through `17` are also intentionally
unsupported. A snapshot container will add content/replay metadata
around this payload without changing its hash semantics. Milestone 5's in-memory
`AuthoritySnapshot` carries that payload with a redundant tick and BLAKE2b-256
state hash; restore rejects invalid payloads and tick or hash mismatches. It is
not a `.dsnap` container yet.

When present, map geometry encodes a one-byte presence tag, map bounds as
signed 64-bit minimum x, minimum y, maximum x, and maximum y, an obstacle
count, then each ascending obstacle's signed 64-bit ID, unsigned 64-bit
elevation, and bounds in the same order. Rectangles are non-empty and closed;
every obstacle rectangle is wholly within map bounds.

Each movement action encodes its entity ID, next-waypoint index, dominant-axis
segment progress, and endpoint-inclusive waypoint tuple. Every waypoint has
signed 64-bit x/y coordinates and an unsigned 64-bit elevation. The decoder
reconstructs its path against the already-decoded mission map and rejects an
action without one.

## 9. Replay package

Suggested extension: `.drun`

Fields:

- replay format version;
- application build;
- simulation semantic version;
- mission hash;
- policy bundle hashes;
- initial snapshot or mission reference plus canonical initialisation inputs;
- seed manifest;
- command log;
- checkpoint hashes;
- optional embedded snapshots;
- optional trace manifest;
- completion summary.

A replay verifier must be able to report:

- unsupported version;
- missing content;
- content hash mismatch;
- first divergent checkpoint;
- invalid command sequence;
- corrupt payload.

## 10. Command log

Each command contains:

```text
Command {
  tick
  sequence
  source
  kind
  payload
}
```

Commands are sorted by `(tick, sequence)`. Duplicate sequence IDs are invalid.

## 11. Trace package

`.dtrace` currently carries one `KWI-TRACE\0` version `1` packet: magic, a
16-bit big-endian version, then canonical UTF-8 JSON with sorted keys and no
insignificant whitespace. It records the exact canonical run-state hash, trace
level, node-ID-ordered policy-invocation, expression, observation, intention,
resolution, world-event, and consequence records, followed by edge-ID-ordered
typed links. Source spans, closed IDs, fixed 32-byte digests, bounded text, and
explicit nullable fields are encoded as data; arbitrary Python objects are
never serialised.

Decoders reject version `0`, unsupported versions, duplicate or unknown fields,
malformed values, packets over 16 MiB, and valid-but-noncanonical JSON. Version
`1` is one complete immutable run-local graph: chunk indexes, interning tables,
retention ranges, and query metadata are deferred until their owning milestones.
Trace data does not affect authoritative state hashes. Capturing trace must not
change simulation semantics.

## 12. Historical source

A run that supports source navigation must preserve the exact source text or a content-addressed reference to it. Current working-tree source is not sufficient.

Historical source metadata includes:

- module path within policy project;
- source hash;
- UTF-8 bytes;
- language version;
- line-start index for navigation.

## 13. Campaign save

Deferred until after the vertical slice. Expected fields:

- save format and version;
- campaign content hash;
- operative persistent state;
- inventory;
- policy-project references;
- unlocked language/library features;
- mission history;
- current strategic state;
- migration history.

Do not mix replay authority with mutable campaign convenience data.

## 14. Settings

Settings are non-authoritative and may use a simple human-readable format. Examples:

- window size;
- UI scale;
- font scale;
- audio levels;
- key bindings;
- accessibility preferences;
- last opened policy.

Invalid settings fall back safely and do not prevent headless operation.

## 15. Asset manifest

Bundled assets should have a manifest containing:

- path;
- content hash;
- type;
- licence reference;
- attribution requirement;
- source or generation note.

Generated assets should record enough provenance for repository maintenance without making “AI-generated” a gameplay dependency.

## 16. Canonical hashing

Canonical hashing rules must specify:

- field order;
- integer encoding;
- string encoding and normalisation;
- list order;
- map key ordering;
- variant tags;
- absent optional fields;
- version prefix;
- hash algorithm.

Hash input should be domain-separated, for example:

```text
"kiwi:state:v1\0" + canonical_state_bytes
```

Select the actual hash algorithm during implementation and record it in `DECISIONS.md` if it becomes durable.

## 17. Migration policy

A migration:

- accepts only one known source version;
- validates before and after;
- is deterministic;
- does not silently discard unknown meaningful data;
- emits a migration report;
- has fixture tests;
- increments version one step at a time.

Before public release, destructive migration may be acceptable if clearly documented. After public release, preserve user policies and saves where practical.

## 18. Security limits

Loaders enforce:

- maximum file size;
- maximum string length;
- maximum list and map size;
- maximum nesting depth;
- path confinement;
- no symbolic path escape in packaged projects;
- no dynamic Python imports;
- no embedded executable native payloads.

## 19. Acceptance criteria

- All durable formats carry explicit versions.
- Unknown or corrupt data fails with structured errors.
- Bytecode and replay files never execute Python code during loading.
- Canonical state hashing is stable in golden fixtures.
- Historical source navigation does not depend on current source.
- Content references are validated and path-confined.
