# ADR 0024: bounded scrollback search

## Context

Primary scrollback has stable row IDs and grapheme-aware anchor/continuation
cells, but it has no query/result state. A local search must neither mutate
terminal content nor send its query to the child PTY.

## Decision

`State` owns one local search object. `Ctrl+Shift+F` opens an exact UTF-8
query in the window title, which consumes character callbacks until `Enter`
submits or `Escape` clears it. `Ctrl+Shift+G` and `Ctrl+Shift+R` navigate a
submitted result set forward/backward. These bindings are reserved before
Kitty keyboard encoding and never enqueue PTY bytes.

The query is at most 1,024 UTF-8 bytes. Search compares each physical row's
stored anchor glyph sequence with a plain, case-sensitive byte search; it has
no regular expressions, normalization, indexing service, cross-session state,
or cross-row match. It retains at most 256 overlapping matches, ordered by
oldest row then byte position. Byte matches map back to complete anchor cells,
so a match inside a multibyte grapheme or a wide-cell anchor expands to the
whole grapheme footprint.

Each submitted result set records the terminal content generation and screen
scope. Content mutation, scrollback changes, or resize make the result
explicitly `stale`; navigation does not infer replacement ranges. Empty and
no-match submissions have distinct states. Current primary-scrollback results
adjust only `history_offset` to reveal the matching row. Search never changes
selection endpoints or terminal input.

`terminal.search` is a read-only ABI-v1 semantic resource. It exposes current
status/count/index and named bounded visible ranges, never query or terminal
text. The current match is a fixed viewport range in the frame uniform and
`terminal/search` alpha-blends it after selection and before glyphs.

## Consequences

The model has fixed query/result bounds and reuses row ownership rather than
building a second text store. Search-only changes request the `search` redraw
reason; input does not mark terminal or text damage. A search reveal changes
the viewport and therefore legitimately marks the visible grid dirty.

The interface is intentionally minimal: title-bar query feedback and a current
result highlight, not an in-grid find bar or all-match raster overlay. The
semantic descriptor still exposes every visible bounded match to trusted local
consumers. Tests cover Unicode/wide mapping, overlapping ordering, history
reveal, empty/no-match/stale states, keyboard reservation, resource shape, and
pass order. A real large-scrollback graphical search remains a manual
validation requirement.
