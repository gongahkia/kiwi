# ADR 0004: FreeType basic-Latin bitmap atlas

## Decision

Use FreeType rasterization of Fontconfig's monospace font for codepoints 32–126, packed into a fixed 1024×1024 single-channel shelf atlas.

## Rationale

This provides real, readable glyphs with a low-level, inspectable path while keeping M0's scope manageable. Atlas placement/bookkeeping is separate from draw encoding, so later cache policy, multiple fonts/sizes, MSDF, or vector backends can replace the bitmap source without replacing terminal semantics.

## Consequences

M0 explicitly does not solve shaping, ligatures, combining marks, RTL, CJK, emoji, fallback, or full Nerd Font coverage. Those belong to M2 and M5.
