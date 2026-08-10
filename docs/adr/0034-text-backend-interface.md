# ADR 0034: text backend interface

## Context

Kiwi's M2 text path currently couples terminal-grid inspection, HarfBuzz
shaping, fallback selection, glyph rasterization, the grayscale atlas, and
renderer upload through one established implementation. M8 needs controlled
MSDF and vector experiments without permitting a renderer choice to alter
terminal columns, grapheme ownership, or resource lifetimes.

## Decision

`kiwi.text.backend` defines the renderer-scoped **text backend ABI v1**. Its
only implemented adapter is `atlas`, which delegates to the existing `Layout`
and Fontconfig/FreeType/HarfBuzz/glyph-cache path. The adapter is deliberately
a proof-of-contract, not a second renderer or an MSDF/vector implementation.

Construction takes the app-owned `FontSystem` and a requested backend name:

```lua
local backend = Backend.create(font_system, { requested = "atlas" })
local glyphs = backend:update(terminal_state)
local descriptor = backend:descriptor()
```

The stable v1 boundary is:

| Boundary | Contract |
| --- | --- |
| semantic input | visible terminal grid plus `text_damage`; no PTY, parser, input, or raw GPU data |
| layout authority | Kiwi's `Layout`, Unicode segmentation, width policy, and HarfBuzz run mapping remain authoritative |
| glyph output | bounded `text.shaped_glyphs` records consumed by the existing glyph pass |
| GPU resource | semantic `text.alpha_atlas`; wgpu texture/view/buffer/bind-group handles stay renderer-private |
| diagnostics | plain-data descriptor with ABI version, requested/active backend, explicit fallback, and capabilities |
| lifetime | `FontSystem` remains app-owned; the renderer owns all native GPU resources; the adapter owns no raw font or wgpu handle and is destroyed with the renderer |

`KIWI_TEXT_BACKEND` selects the requested name at renderer construction. `atlas`
is the default and only supported name. Any other non-empty name of at most 64
bytes is accepted as a request but deterministically activates `atlas` with
`fallback=true` and `fallback_reason="unsupported-backend"`. The descriptor
retains the requested name, so diagnostics distinguish an intentional baseline
from a unavailable experiment. An invalid empty/non-string selection fails at
construction.

The adapter cannot mutate terminal state, select a width policy, reflow rows,
change HarfBuzz options, or retain renderer resources. Current atlas data stays
inside the established renderer/font ownership path. A future adapter may not
expose a `FT_Face`, HarfBuzz buffer, glyph-cache entry, FFI array, or wgpu
handle through the descriptor or semantic resource ABI.

## Comparison and migration boundary

Every prototype must run the unchanged `kiwi-text-corpus-v1` scenarios and
publish the backend descriptor, text-corpus manifest, font inventory, shaping
options, fallback outcomes, glyph/instance/cache counters, CPU p50/p95/p99,
and a native visual-review screenshot. A prototype is not eligible to become
the active backend if it changes terminal cell widths, grapheme-safe mapping,
or the current bounded fallback/resource failure behavior. Different font,
content scale, driver/adapter, Unicode data, or corpus version is
non-comparable evidence, not a performance result.

The future MSDF or vector adapter must implement this v1 lifecycle against a
typed glyph-output/resource contract before it can be selectable. Until then,
the fallback is intentional and testable rather than an implied partial
implementation.

## Consequences

Renderer updates are routed through the adapter today, so the atlas adapter is
compiled and exercised by the normal native path. Existing semantic resources,
glyph shader, and resource accounting remain unchanged. Focused tests cover
the stable descriptor, unsupported-selection fallback, equivalent glyph output
for a wide CJK cell, invalid selection rejection, and use-after-destroy.

## References

- [ADR 0014](0014-bounded-native-shaping-and-atlas.md)
- [ADR 0016](0016-semantic-render-pass-resource-abi.md)
- [TEXT.md](../TEXT.md)
- [BENCHMARKS.md](../BENCHMARKS.md)
