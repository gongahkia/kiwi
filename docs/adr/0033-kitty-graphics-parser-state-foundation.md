# ADR 0033: Kitty graphics parser/state foundation

## Decision

Kiwi recognizes bounded Kitty APC-G commands and accepts direct inline PNG
transfers, validation queries, explicit cell placements, and selected deletion
operations. A completed transfer is validated and decoded into a terminal-owned,
bounded CPU RGBA cache as specified in
[KITTY_GRAPHICS.md](../KITTY_GRAPHICS.md). It has fixed APC, transfer chunk,
encoded byte, image, dimension, pixel, decoded-data, CPU-cache, GPU-accounting,
and in-flight-transfer limits.

No graphics payload, decoded pixels, path, shared-memory name, file descriptor,
image texture, native handle, or renderer resource enters the terminal snapshot,
diagnostics, scrollback, or extension API. An incomplete transfer briefly owns
bounded Base64 chunks; after decode the CPU cache owns pixels. A later renderer
phase owns GPU resources and visual composition, and receives release
descriptors rather than giving native handles to terminal state.

An incomplete or invalid transfer has no display effect. Commands are ordered:
another graphics action while a continuation is open rejects the partial
transfer, except that deletion aborts it. Placements are anchored to bounded
stable row IDs and carry no pixels. Scrollback keeps those references until a
row is evicted; resize and partial scrolling clip them; visible clear, `1049`,
and reset remove them deterministically. Reset clears the cache and creates
renderer release work for any accounted GPU upload. Rendering and composition
remain separate future work.

## Consequences

This establishes a constrained transfer/cache and terminal-placement capability
without granting image rendering. Generic APC data remains discarded; only
APC-G reaches the terminal graphics model.

## References

- [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
- [KITTY_GRAPHICS.md](../KITTY_GRAPHICS.md)
