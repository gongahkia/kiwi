# ADR 0033: Kitty graphics parser/state foundation

## Decision

Before decoding or GPU allocation, Kiwi will recognize only bounded Kitty APC-G
commands and derive a terminal-owned opaque image/placement ledger. The v1
subset is direct inline PNG transfer, final/continuation chunks, explicit
placement, deletion, and validation query as specified in
[KITTY_GRAPHICS.md](../KITTY_GRAPHICS.md). It has fixed command, byte, image,
placement, dimension, and in-flight-transfer limits.

No graphics payload, pixels, path, shared-memory name, file descriptor, image
texture, native handle, or renderer resource enters the terminal snapshot,
diagnostics, scrollback, or extension API. A completed transfer is only an
`undecoded` declaration. A later decoder/cache phase owns bytes and pixels; a
later renderer phase owns GPU resources and visual composition.

An incomplete or invalid transfer has no display effect. Commands are ordered:
another graphics action while a continuation is open rejects the partial ledger
entry. Image deletion cascades to placements; exact placement deletion does not
delete the image. Reset clears the whole ledger. Future row anchoring must be
separate from image data so scrollback eviction has a deterministic loss mode.

## Consequences

This creates an implementation checklist and executable fixture vocabulary
without granting a graphics feature prematurely. It preserves existing APC
discard behavior until the model and parser actions are implemented in the
following M7 issues.

## References

- [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
- [KITTY_GRAPHICS.md](../KITTY_GRAPHICS.md)
