# ADR 0023: selection render pass

## Decision

Publish `terminal.selection` as a read-only semantic resource. Its descriptor carries only an `active` flag, viewport-relative normalized start/finish cell gaps, and normalized RGBA overlay color. It contains no selected text, byte offsets, native handles, or unbounded list of cells. The renderer derives the range from `State:selection_view()` and the active visible rows on every rendered frame. Endpoints may lie above or below the viewport; the shader clips that single range to the bounded grid.

`terminal/selection` is an alpha-blended built-in pass at order 15. It loads the `terminal/background` output, declares `terminal.selection`, `frame.viewport`, and `frame.timing` reads, and writes `surface.color`. `terminal/glyph` follows it at order 20 and `terminal/cursor` remains after glyphs at order 30. Thus the selection changes background contrast without obscuring text or cursor semantics. The pass draws at most the current grid capacity and uses the existing fixed frame uniform rather than allocating a selection buffer.

`KIWI_SELECTION_COLOR` configures the overlay as `#RRGGBB` with default alpha `70`, or as explicit `#RRGGBBAA`; malformed values fail renderer construction. The default is `#5E81AC70`.

Local pointer selection changes request the `selection` invalidation reason. They do not mark terminal-cell damage or text damage, so a selection-only frame refreshes the selection resource and uniform while the text layout reuses its stable shaped rows.

## Rationale

Selection is presentation state derived from M4's stable, grapheme-safe terminal state. Giving it a typed descriptor and dedicated pass preserves the M3 resource/lifecycle boundary and avoids encoding selection into glyph attributes, where it would force unnecessary shaping or couple text semantics to input policy.

## Consequences

Wide cells and combining clusters are already expanded by selection state before the descriptor is created. History and resize behavior is handled by the state model; the renderer only clips stable endpoints to the current viewport. The overlay changes no clipboard, OSC 52, accessibility, replay, or terminal protocol behavior. Tests cover descriptor clipping, grapheme-safe bounds, color parsing, typed resource access, pass ordering, and the native shader/pipeline smoke path.
