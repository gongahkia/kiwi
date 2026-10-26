# 0044: Bounded colour glyphs and fallback placement

Status: accepted, 2026-10-26. Supersedes the grayscale-only rendering limits in
ADR 0014, ADR 0034 and the atlas baseline descriptions in ADR 0035/0036.

## Decision

Use one fixed RGBA atlas for coverage masks and colour bitmaps. This retains
the existing stable-UV allocator, cross-pane pins, LRU eviction and upload
generation. The default page is 1024×1024, now 4 MiB instead of 1 MiB. Whole-page
uploads remain bounded but cost four times the previous upload bandwidth;
dirty-region uploads are future performance work.

FreeType's BGRA output is premultiplied sRGB. Swizzle to RGBA without discarding
alpha or unpremultiplying on the CPU. Bilinear strike scaling preserves
premultiplication. The colour shader unpremultiplies before sRGB decoding and
straight-alpha blending. Coverage masks continue to sample R. A renderer-only
glyph flag selects colour ink; concealment and dim still apply. Colour fonts
skip synthetic bold/italic operations.

The render-model version advances to 3 and the GTK GL bridge to 4, so stale
native libraries cannot silently interpret new atlas bytes as R8. Glyph and
frame record sizes stay unchanged. The descriptor for the existing semantic
resource `text.alpha_atlas` reports `rgba8unorm`; the historical name does not
grant extensions access to pixels or GPU handles.

Fontconfig supplies at most 16 ranked candidates for a missing cluster.
Character-set filtering precedes loading; failed candidates do not immediately
end the search. The existing 32-face and 1,024-sequence budgets remain. Joiners,
variation selectors and emoji tags go to HarfBuzz but do not require standalone
coverage. The Unicode width policy also determines emoji presentation preference.
Bitmap-only faces select the nearest strike if pixel-size selection fails.
Shaping advances and bitmap metrics scale together. Colour artwork fits the
cluster's cells; each new shaping cluster is anchored to its terminal column.

## Bounds and limits

Input bitmaps must be grayscale or BGRA, non-null, at most 2,048 pixels per
dimension, with positive pitch covering the row and no greater than 16,384.
Scaled atlas glyphs remain limited to 512 pixels per dimension and available
page space. Invalid data is rejected before copying or eviction. Empty glyphs
have no ink and are omitted. CPU resampling uses four source samples per output
channel; there is no unbounded image allocation or per-frame font scan.

This implements bitmap colour fonts (sbix and CBDT/CBLC on the qualified hosts).
It does not implement COLRv1 paint graphs or an OpenType SVG renderer. Font
availability and artwork still vary by platform. Bidi is separate work.

## Verification

Deterministic tests check BGRA swizzling, premultiplied interpolation, pitched
rows, invalid dimensions/pitches, grayscale preservation, mixed-format eviction,
cross-owner pixel retention, arbitrary font sizes, joined sequences, flags and
skin tones, fallback candidates and terminal-column placement.

`make color-glyph-smoke` uses native framebuffer readback for a known
half-transparent red glyph, a grayscale mask tinted green, concealment and
actual emoji pixels. It runs on GLFW/WGPU, GTK/WGPU and GTK GL. GTK GL's explicit
diagnostic sampler is bounded to 16 million pixels and runs only on request.
`make bench-text-stress` additionally recovers 64 emoji in four renditions after
mixed-script/ASCII churn, checking actual glyph IDs and fixed page/entry budgets.
See the evidence ledger for executed hosts; CI configuration is not a local
passing result.

## References

- [FreeType bitmap pixel formats](https://freetype.org/freetype2/docs/reference/ft2-basic_types.html#ft_pixel_mode)
- [FreeType bitmap strike selection](https://freetype.org/freetype2/docs/reference/ft2-sizing_and_scaling.html#ft_select_size)
- [Text contract](../TEXT.md)
