# ADR-0005: Checkpoint Payload Schema

- Status: Accepted for bootstrap
- Date: 2026-07-30
- Amended: 2026-07-31

## Context

Checkpoint frames make replay seeking practical only if restoring one produces the exact semantic state needed to interpret subsequent output. Persistent payloads must remain safe to decode without Lua evaluation, implementation-dependent iteration, or unbounded allocation.

## Decision

`CHECKPOINT` frame payloads use schema v2, a canonical binary layout. The payload begins with a little-endian `u16` schema version (`2`). All remaining multi-byte integers are unsigned big-endian. There is no optional-field bitmap, implicit default, Lua serialization, JSON, MessagePack, or table iteration in the payload. Decoders retain schema-v1 support for existing bootstrap recordings.

Schema v2 serializes only terminal semantic state:

- compatibility profile, dimensions, and scrollback limit;
- active-screen selection, cursor and saved cursor, rendition and saved rendition, modes, margins, and tab stops;
- primary and alternate screens independently, including row wrapping and every cell;
- scrollback rows in oldest-to-newest order;
- parser configuration, state, byte offset, and incomplete control-sequence buffers;
- incomplete UTF-8 decoder state.

It omits row damage/revisions, renderer resources, visual effects, backend/process state, timing, host environment, and the unsupported nil-only hyperlink placeholder. Decoders mark restored rows dirty and may assign fresh row revisions.

### Canonical layout

Fields appear in this exact order:

```text
schema_version:u16le
profile:u8                         # 1 = stanczyk-basic-v1
columns:u16
rows:u16
scrollback_limit:u32
active_screen:u8                   # 0 = primary, 1 = alternate
modes:auto_wrap:u8,cursor_visible:u8
margins:top:u16,bottom:u16
tab_stop_bytes:u16
tab_stop_bits[tab_stop_bytes]       # bit 0 maps to column 1
cursor:row:u16,column:u16,pending_wrap:u8
saved_cursor:row:u16,column:u16,pending_wrap:u8
rendition
saved_rendition
primary_screen
alternate_screen
scrollback_count:u32
scrollback_rows[scrollback_count]  # each row carries its own cell_count
parser_state:u8
parser_byte_offset:u53be
max_csi_bytes:u32
max_escape_intermediate_bytes:u32
max_osc_bytes:u32
csi_intermediates:length:u32,bytes[length]
csi_parameters:length:u32,bytes[length]
escape_intermediates:length:u32,bytes[length]
osc_payload:length:u32,bytes[length]
utf8_codepoint:u32
utf8_minimum:u32
utf8_remaining:u8
```

`u53be` is seven big-endian bytes and represents `0..2^53-1`, the exact-integer range used by LuaJIT numbers. A checkpoint encoder rejects a larger parser byte offset.

A rendition is `attributes:u32`, then foreground and background colours. A colour is `kind:u8`; `0` is default, `1` is indexed followed by `index:u8`, and `2` is RGB followed by `red:u8,green:u8,blue:u8`.

A screen is `row_count:u16` followed by exactly that many rows. A row is `wrapped:u8`, `cell_count:u16`, then exactly that many cells. A cell is `text_length:u16`, raw text bytes, `width:u8` (`0`, `1`, or `2`), and a rendition. Visible-screen `row_count` and `cell_count` must respectively equal the checkpoint dimensions; repeated counts make malformed nesting detectable before allocation. Schema-v2 scrollback rows retain their encoded `cell_count` independently.

Parser-state discriminants are fixed: `0 ground`, `1 escape`, `2 escape_ignore`, `3 csi_entry`, `4 csi_parameter`, `5 csi_intermediate`, `6 csi_ignore`, `7 osc_string`, `8 osc_escape`, `9 osc_ignore`, and `10 osc_ignore_escape`.

All booleans are exactly `0` or `1`. All enum values outside their specified discriminants are invalid.

### Bounds and decoding

The decoder checks the total payload size before parsing and validates dimensions, all declared counts, nested string lengths, parser buffer bounds, and exact remaining bytes before creating a terminal. Defaults are deliberately bounded: 16 MiB total checkpoint bytes, 262144 visible cells per screen, 524288 total cells across both screens and scrollback, 100000 scrollback rows, 4096 cell-text bytes, and 65536 parser-buffer bytes. Callers may supply stricter configured limits.

Schema v2 permits scrollback rows with independent widths so non-reflowing resizes retain historical rows unchanged. Visible primary and alternate screen rows still require the active terminal width. Schema v1 requires every scrollback row to match the active terminal width.

Any unsupported schema version, invalid discriminant, impossible dimension, inconsistent count, oversized field, truncation, trailing byte, or invalid terminal/parser/UTF-8 invariant produces a typed error and no restored terminal. Re-encoding the same logical state produces the same bytes.

### Stability

Schema-v2 stability begins only when the recording format reaches its first public compatibility commitment. Until then, this accepted bootstrap schema remains subject to repository-controlled changes accompanied by an ADR update.

## Consequences

Positive:

- seeking can resume exact parser and UTF-8 continuation;
- payloads are deterministic and auditable;
- malicious lengths are rejected before nested allocation;
- outer recording-frame CRC-32 continues to cover the entire checkpoint payload.

Negative:

- checkpoint payloads are intentionally verbose;
- terminal model changes affecting persisted fields require a schema decision;
- large configured terminals may require explicit higher checkpoint limits.

## Rejected alternatives

### Lua table serialization

Rejected because it is unsafe, implementation-dependent, and not canonical.

### JSON or MessagePack state blobs

Rejected because they do not provide the required fixed field order, explicit discriminants, and straightforward pre-allocation bounds checks.

### Renderer snapshots

Rejected because they cannot continue terminal parsing and would couple recordings to visual implementation.
