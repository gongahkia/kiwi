# ADR 0015: separate text invalidation and constrained ASCII mutation

## Context

M2 used logical terminal damage to decide both background/cursor uploads and shaped-row invalidation. Cursor movement therefore reshaped stable rows even though no cluster, face choice, or glyph record changed. M2.5 profiling also showed ordinary printable ASCII spending work on transient cell copying and per-byte direct-sink dispatch, while Unicode cluster semantics remained correctness-critical.

## Decision

`State` maintains `damage` for logical presentation and `text_damage` for content that requires reshaping. `Layout` consumes text damage after each update; cursor movement, cursor visibility, and SGR-state changes alone do not enter that stream. Content mutation, structural edit/scroll, resize/reset, history movement, and screen changes do.

Only the production direct parser sink writes existing singleton ASCII clusters directly into normal cells without a transient cell table. Parser byte streaming and callback mode are unchanged, and `Prepend × ASCII` uses the general grapheme path for its first ASCII scalar.

`FontSystem` caches the primary face's coverage result for singleton printable ASCII code points (U+0020–U+007E). A first encounter still queries the primary face; a negative result continues through the existing fallback path. The cache is therefore bounded to 95 entries and does not assume that every configured primary font supports ASCII.

## Consequences

Static and cursor-only frames avoid redundant text reshaping while background/cursor damage behavior remains intact. The ASCII optimizations are constrained to profiled fast paths and have parser callback-versus-sink snapshot coverage across controls, split input, and `Prepend`; they neither change grid storage nor create an ASCII-specific rendering model. The coverage cache removes repeated primary-face checks only after the first result and retains fallback for a missing primary glyph. Unicode property, grapheme, width, fallback, and shaping costs remain separately measured rather than bypassed.
