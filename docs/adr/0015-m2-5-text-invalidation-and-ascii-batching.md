# ADR 0015: separate text invalidation and constrained ASCII batching

## Context

M2 used logical terminal damage to decide both background/cursor uploads and shaped-row invalidation. Cursor movement therefore reshaped stable rows even though no cluster, face choice, or glyph record changed. M2.5 profiling also showed ordinary printable ASCII spending work on transient cell copying and per-byte direct-sink dispatch, while Unicode cluster semantics remained correctness-critical.

## Decision

`State` maintains `damage` for logical presentation and `text_damage` for content that requires reshaping. `Layout` consumes text damage after each update; cursor movement, cursor visibility, and SGR-state changes alone do not enter that stream. Content mutation, structural edit/scroll, resize/reset, history movement, and screen changes do.

Only the production direct parser sink groups contiguous bytes U+0020 through U+007E. State writes the existing singleton ASCII clusters directly into normal cells without a transient cell table. The parser still accounts for every decoded print action, callback mode is unchanged, controls/non-ASCII bytes split a batch, and `Prepend × ASCII` uses the general grapheme path for its first ASCII scalar.

## Consequences

Static and cursor-only frames avoid redundant text reshaping while background/cursor damage behavior remains intact. The ASCII optimization is constrained to a profiled fast path and has parser callback-versus-sink snapshot coverage across controls, split input, and `Prepend`; it neither changes grid storage nor creates an ASCII-specific rendering model. Unicode property, grapheme, width, fallback, and shaping costs remain separately measured rather than bypassed.
