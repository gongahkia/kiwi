# Recording Format

## 1. Purpose

Stanczyk recordings preserve the ordered events needed to reproduce terminal state. They are not screen captures and do not store renderer or effect output as semantic truth.

A recording should support:

- exact raw output-byte preservation;
- optional input-byte preservation;
- resize events;
- deterministic timing;
- marks and metadata;
- checkpoints for seeking;
- streaming reads;
- corruption detection;
- future versioning.

The accepted bootstrap design is recorded in ADR-0002.

## 2. File extension and identity

Suggested extension: `.strec`.

Magic bytes:

```text
STANCZYK\x00
```

The magic is followed by a fixed-size preamble and a length-delimited metadata block.

## 3. Preamble

Conceptual fields:

```text
magic[8]
major_version:u16
minor_version:u16
flags:u32
metadata_length:u32
metadata_checksum:u32
```

All integers are encoded in a single documented byte order. The implementation must provide explicit binary helpers compatible with the selected Lua runtime rather than assuming Lua 5.3 packing functions.

## 4. Metadata

Metadata is canonical UTF-8 JSON for the bootstrap version.

Suggested fields:

```json
{
  "format": "stanczyk-recording",
  "profile": "stanczyk-basic-v1",
  "created_by": "stanczyk/<version>",
  "initial_columns": 80,
  "initial_rows": 24,
  "command": null,
  "shell": null,
  "platform": null,
  "started_at": null,
  "environment_allowlist": {},
  "notes": null
}
```

Rules:

- metadata is informational unless a field is explicitly defined as semantic;
- secrets and full environments must not be captured by default;
- timestamps may be omitted for reproducible fixtures;
- metadata key ordering must be canonical for stable test fixtures;
- readers ignore unknown metadata fields.

## 5. Frame structure

Each frame is length-delimited:

```text
kind:u8
flags:u8
reserved:u16
delta_us:u32
payload_length:u32
payload[payload_length]
checksum:u32
```

`delta_us` is the terminal-time delta since the previous frame. Gaps larger than the representable range use one or more clock-advance frames.

The checksum covers the frame header fields after `kind` as defined by the implementation and the payload. Exact coverage must be fixed in code and test vectors.

## 6. Frame kinds

Initial kinds:

- `0x01 OUTPUT`: raw bytes received from the backend;
- `0x02 INPUT`: raw bytes sent to an interactive backend;
- `0x03 RESIZE`: new columns and rows;
- `0x04 MARK`: named bookmark or diagnostic marker;
- `0x05 CHECKPOINT`: serialised semantic terminal state;
- `0x06 STATUS`: backend lifecycle metadata;
- `0x07 EXIT`: process or backend exit information;
- `0x08 CLOCK_ADVANCE`: extends long time gaps without semantic payload.

Unknown non-critical frame kinds may be skipped using their length. Critical-frame signalling may be added through flags.

## 7. Payloads

### 7.1 OUTPUT and INPUT

Payload is raw bytes with no text encoding transformation.

### 7.2 RESIZE

Conceptual payload:

```text
columns:u32
rows:u32
pixel_width:u32
pixel_height:u32
```

Pixel fields may be zero when unknown.

### 7.3 MARK

Canonical JSON payload with bounded UTF-8 fields:

```json
{
  "name": "checkpoint-before-demo",
  "data": {}
}
```

Marks never affect terminal semantics.

### 7.4 CHECKPOINT

The checkpoint payload is a versioned semantic state snapshot. It must include enough state to continue parsing exactly, including partial parser state.

It must exclude renderer resources and effect state.

Checkpoint encoding may initially use a documented internal binary schema. Because checkpoints are persistent and format-sensitive, the final schema requires its own ADR before implementation.

### 7.5 STATUS and EXIT

Status payloads are canonical JSON with bounded fields. Exit frames should represent normal exit code, signal where available, and a helper/backend reason.

## 8. Recording semantics

- Frames are applied in file order.
- Terminal time begins at zero.
- OUTPUT frames are parsed fully before the next frame.
- INPUT frames are informational during replay unless an interactive simulation explicitly consumes them.
- RESIZE frames apply atomically.
- MARK frames do not affect state.
- CHECKPOINT frames must match the state obtained by replaying all preceding semantic frames.
- STATUS and EXIT do not change terminal screen state unless the application renders them separately.

## 9. Checkpoints and indexing

Recordings may embed checkpoints at configurable intervals or semantic boundaries.

Recommended checkpoint triggers:

- elapsed terminal time interval;
- output-byte interval;
- alternate-screen transitions;
- explicit user mark;
- recording finalisation.

A sidecar index may map target times and frame numbers to byte offsets. The recording remains valid without the sidecar.

The index is cache data and may be rebuilt.

## 10. Integrity and corruption

Readers must reject:

- invalid magic;
- unsupported major version;
- metadata beyond configured bounds;
- frame payload beyond configured bounds;
- truncated frames;
- checksum mismatch;
- invalid resize dimensions;
- malformed checkpoint payloads;
- impossible integer overflows or offset arithmetic.

Readers must never allocate directly from an unvalidated payload length.

## 11. Privacy

Recording can expose:

- commands typed by the user;
- command output;
- file paths;
- secrets printed in the terminal;
- environment metadata;
- shell and platform information.

Therefore:

- input recording should be configurable;
- metadata capture should be allowlisted;
- password-redaction claims must not be made without reliable terminal-context support;
- the standalone app should warn before sharing a recording containing input;
- recordings are treated as sensitive files by default.

## 12. Determinism

A recording replay is semantically deterministic when:

- the same compatibility profile is used;
- the same initial terminal configuration is used;
- frame order and payloads are unchanged;
- terminal time is derived only from frame deltas;
- parser and state implementation conform to the same profile version.

Visual determinism additionally requires:

- the same effect configuration;
- the same seeded PRNG state;
- compatible font metrics;
- no effect opting into ambient wall time.

## 13. Test vectors

The repository should include small golden recordings covering:

- plain output;
- UTF-8 split across frames and chunks;
- colour and rendition;
- alternate screen;
- resize;
- malformed sequence recovery;
- marks;
- checkpoints;
- corruption at every structural boundary;
- unsupported minor-version fields.
