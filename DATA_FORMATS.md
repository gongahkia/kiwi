# Data Formats and Versioning

## 1. Purpose

Doctrine stores player source, compiled policy bundles, mission content, replay inputs, canonical snapshots, causal traces, settings, and later campaign state. Durable formats must be explicit, versioned, validated, and safe to load without executing Python code.

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

Define a small deterministic binary or canonical JSON encoding for:

- state hashing;
- bytecode;
- replay checkpoints;
- trace chunks where size matters.

The implementation may begin with canonical JSON for inspectability, then move to a versioned binary format only after profiling. Hash semantics must remain explicitly versioned.

## 4. Policy source

Suggested extension: `.dtr`

Policy source files contain:

- optional language-version header;
- declarations;
- policy entry points;
- comments.

Example:

```text
language 1

policy cautious(view: Observation, memory: Memory) -> Decision =
  ...
```

If no header is allowed in the initial syntax, language version belongs in the containing project manifest.

## 5. Policy project manifest

Suggested file: `doctrine.policy.json`

Fields:

```json
{
  "format": "doctrine-policy-project",
  "version": 1,
  "name": "cautious-alpha",
  "language_version": 1,
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

## 7. Mission content

Suggested extension: `.dmission.json`

Top-level fields:

```json
{
  "format": "doctrine-mission",
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

Suggested extension: `.dtrace`

Trace may be chunked by tick range. Manifest fields:

- trace format version;
- replay hash;
- trace level;
- source-map references;
- chunk index;
- interning tables;
- retained tick ranges;
- consequence index;
- query metadata.

Trace data does not affect authoritative state hashes. Capturing trace must not change simulation semantics.

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
"doctrine:state:v1\0" + canonical_state_bytes
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
