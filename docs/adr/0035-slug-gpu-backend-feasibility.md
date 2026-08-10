# ADR 0035: Slug GPU backend feasibility

## Context

M8 permits an alternative text rasterizer only behind the renderer-scoped text
backend ABI. Kiwi's atlas path remains the semantic and visual baseline:
terminal width, EGC ownership, row damage, HarfBuzz shaping, fallback choice,
and terminal-column mapping must not move into a GPU backend.

HarfBuzz 14.0 introduced the experimental `libharfbuzz-gpu` library. Its Slug
path encodes glyph outlines on the CPU into compact blobs and provides WGSL
vertex/fragment shaders that decode and rasterize the blobs directly in the
fragment stage. It therefore does not require a compute pipeline or a bitmap
atlas. The library and its shader API are experimental; HarfBuzz's general
`hb.h` ABI promise does not make that peripheral API a stable Kiwi dependency.

## Local feasibility record

The M8 research host was Fedora 43/Linux `7.1.7-100.fc43.x86_64` on
2026-08-10. `pkg-config --modversion harfbuzz` reported `11.5.1`, and
`hb-shape` was available. Both `pkg-config --exists harfbuzz-gpu` and
`command -v hb-gpu` failed. The checkout has no Slug/MSDF source, no
`harfbuzz-gpu` FFI declaration, and no native build integration for it.

Kiwi's pinned `wgpu-native v29.0.1.1` binding already supports storage buffers
and vertex/fragment render pipelines, so a fragment-shader Slug experiment is
not blocked by missing compute support. It is not an adapter substitution,
however: the current `terminal/glyph` pass consumes fixed 48-byte UV/atlas
instances through `text.shaped_glyphs` and `text.alpha_atlas`. A Slug backend
needs a new versioned, renderer-owned blob resource and a distinct shader/pass
contract; neither exists today.

`make slug-feasibility` is the minimal native dependency prototype. It first
checks `harfbuzz-gpu`, then compiles, links, and runs a C program that creates
and destroys an `hb_gpu_draw_t`. It finally refuses to call the path integrated
until a `text.slug_blobs` resource exists. Exit status `2` means that the
native prerequisite or its encoder probe is unavailable; exit status `3` means
that the encoder works but Kiwi has not gained the renderer contract. These are
expected research outcomes, not successful renderer validation. On the
research host it stops at status `2` before compiling because the package is
absent. The probe does not fetch, install, or accept a system binary.

## Required prototype boundary

Any follow-up must begin with an audited, reproducible source build rather
than an unpinned distribution package or prebuilt library. The reviewed example
is HarfBuzz `14.1.0` commit `cfb70b0b91af933a08339c7c8eef459df1098d7b`; it is
evidence of the interface, not an approval to import that exact release. The
follow-up must pin its chosen source revision and archive hash, retain its
license and per-file notices, build with Meson/Ninja and a C++ compiler using
`-Dgpu=enabled -Dgpu_demo=disabled`, and record the resulting
`harfbuzz-gpu.pc` version. Disabling the demo avoids expanding Kiwi's runtime
surface with the demo's GLEW/GLFW/OpenGL requirements.

The dependency review must cover the selected HarfBuzz source, generated WGSL,
and any bridge code separately. HarfBuzz's top-level `COPYING` uses the Old MIT
license but directs readers to notices in subdirectories. The Slug patent
announcement and its separate MIT reference shaders are useful upstream
context, not a substitute for that source-level review or legal advice.

The proposed data flow is deliberately narrow:

```text
terminal grid/text damage
  -> existing Layout: width, fallback, HarfBuzz glyph IDs and columns
  -> bounded Slug encoder cache: copied blob bytes and extents
  -> renderer-owned storage buffer + HarfBuzz-pinned WGSL draw pass
  -> surface color
```

The encoder may use a narrow Kiwi-owned native bridge or a reviewed LuaJIT FFI
surface, but opaque HarfBuzz handles and `hb_blob_t` storage must never cross
the text-backend descriptor or semantic resource API. Blob bytes and all
per-face/per-glyph cache entries need explicit byte, entry, dimension, and
failure bounds. Failure to load the optional native component, encode a glyph,
allocate a buffer, or compile the Slug shader must select the existing atlas
for the affected renderer lifetime and expose a stable fallback reason.

## Comparison and decision

No Slug performance or quality result exists. A valid follow-up must use the
unchanged `kiwi-text-corpus-v1` scenarios from `make text-corpus-review` and
`make bench-text`, including the separate ligature/calt configuration when it
is under review. It must retain the same font inventory, width policy,
content-scale and terminal layout evidence, record the backend descriptor and
bounded blob/cache counters, and capture a native visual screenshot. Different
font resolution, driver/adapter, Unicode data, corpus, or unsupported glyph
fallback is non-comparable evidence rather than a performance result.

The recommendation is **defer** [issue #138](https://github.com/gongahkia/kiwi/issues/138).
Proceed only after all of these gates are met:

1. a source-pinned `libharfbuzz-gpu` build and notice review are checked in;
2. the native encoder probe passes on the primary Linux environment;
3. a versioned renderer-owned Slug blob/pass resource has explicit bounds and cleanup;
4. the atlas fallback is deterministic and observable for every native/shader/resource failure; and
5. backend selection, lifetime, corpus semantics, and native visual-review evidence pass alongside `make check`.

Until then, `atlas` remains the only implemented backend and an explicit Slug
request follows the existing `unsupported-backend` fallback path.

## References

- [HarfBuzz GPU overview and component status](https://github.com/harfbuzz/harfbuzz)
- [HarfBuzz 14.0 GPU release notes](https://github.com/harfbuzz/harfbuzz/releases/tag/14.0.0)
- [HarfBuzz 14.1.0 source tag](https://github.com/harfbuzz/harfbuzz/tree/14.1.0)
- [Slug patent announcement](https://terathon.com/blog/decade-slug.html)
- [ADR 0034](0034-text-backend-interface.md)
- [TEXT.md](../TEXT.md)
- [BENCHMARKS.md](../BENCHMARKS.md)
