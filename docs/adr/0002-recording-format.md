# ADR-0002: Versioned Framed Binary Recordings

- Status: Accepted for bootstrap
- Date: 2026-07-30

## Context

Recordings must preserve arbitrary terminal bytes, timing, resize events, and future checkpoint data. A line-oriented text format is easy to inspect but inefficient, expands binary data, and complicates robust streaming.

LuaJIT also cannot assume Lua 5.3 binary packing APIs.

## Decision

Use a versioned framed binary file with:

- fixed magic;
- major and minor versions;
- bounded canonical JSON metadata;
- length-delimited frames;
- 32-bit microsecond time deltas;
- raw byte payloads;
- per-frame checksums;
- explicit frame kinds;
- future skippable non-critical frames.

Long timing gaps use clock-advance frames.

The exact checkpoint payload schema is deferred to a separate ADR because it serialises substantial terminal state.

### Bootstrap wire details

The bootstrap format fixes the following byte-level details:

- the magic is the exact nine-byte sequence `STANCZYK\x00`;
- all unsigned integers use big-endian byte order;
- writers emit version `1.0` with preamble and frame flags and reserved fields set to zero;
- metadata checksums use CRC-32/ISO-HDLC over the metadata bytes;
- frame checksums use CRC-32/ISO-HDLC over `flags`, `reserved`, `delta_us`, `payload_length`, and the raw payload, excluding `kind` and the checksum field itself.

CRC-32/ISO-HDLC uses reflected input and output, initial value `0xFFFFFFFF`, reflected polynomial `0xEDB88320`, and final XOR `0xFFFFFFFF`.

## Consequences

Positive:

- preserves raw bytes exactly;
- supports streaming and seeking;
- validates corruption locally;
- avoids base64 expansion;
- permits future frame kinds.

Negative:

- requires explicit binary helpers;
- less directly human-readable;
- requires an inspection tool and golden vectors;
- format changes require discipline.

## Rejected alternatives

### NDJSON with base64 payloads

Rejected as the primary format because of size overhead and weaker framing, though it remains useful as an inspection/export representation.

### Serialised Lua tables

Rejected because of unsafe or unstable deserialisation and poor cross-version guarantees.

### Store rendered frames

Rejected because recordings represent terminal events, not one renderer’s output.
