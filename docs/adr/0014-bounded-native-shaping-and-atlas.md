# ADR 0014: bounded native shaping and glyph-ID atlas

## Context

Rendering the first Unicode scalar through M1's basic-Latin atlas cannot represent combining clusters, CJK fallback, glyph substitutions, or selected font glyphs. A new text path must keep terminal geometry semantic, preserve the renderer boundary, and remain safe when an installed fallback or glyph bitmap is unavailable.

## Decision

Kiwi uses Fontconfig for primary/fallback face selection, FreeType for metrics/rasterization, and HarfBuzz for LTR monotone-grapheme shaping. The grid retains terminal width; HarfBuzz only supplies glyph IDs, cluster mapping, and placement. Glyphs are cached by face ID and glyph ID in one fixed grayscale alpha atlas with entry/dimension limits. The fallback sequence cache and loaded-face cache are bounded. Any missing face, exhausted cache, unsupported color bitmap, or atlas failure degrades to a missing glyph rather than loading without bound or crashing fallback rendering.

## Consequences

The renderer has an explicit shaped-glyph GPU buffer in addition to legacy background-cell data, so M0/M1.5 benchmark paths remain available. Stable rows avoid reshaping until semantic grid damage reaches them. Current color emoji formats are unsupported, whole-page uploads trade simplicity for bandwidth, and LTR shaping does not claim bidi support. These are intentional M2 limits rather than silent fallback behavior.
