# ADR 0036: MSDF backend feasibility

## Context

M8 permits alternative rasterization only through the renderer-scoped text
backend ABI. Kiwi's terminal width, EGC ownership, HarfBuzz shaping, fallback
selection, terminal-column mapping, and atlas fallback remain authoritative.
An MSDF experiment may replace glyph coverage generation and sampling; it may
not become a second layout engine or silently broaden normal startup.

## Research record

The primary Fedora 43/Linux `7.1.7-100.fc43.x86_64` host had no installed
`msdfgen` or `msdf-atlas-gen` command and no matching pkg-config package. The
checkout contains no MSDF source, native bridge, shader, RGBA text atlas, or
`text.msdf_atlas` resource. It currently has one 1024×1024 `r8unorm` alpha
atlas, an R-channel sampling glyph shader, and a 48-byte UV glyph record.

A transient source spike then built the upstream MIT-licensed `msdfgen` v1.13
commit `1874bcf7d9624ccc85b4bc9a85d78116f690f35b` with CMake 3.31.11 and GCC
15.3.1. It deliberately used the local FreeType 2.13.3 installation and
disabled vcpkg, Skia, SVG, and PNG support:

```sh
git clone --depth 1 --branch v1.13 https://github.com/Chlumsky/msdfgen.git msdfgen-v1.13
cmake -S msdfgen-v1.13 -B msdfgen-v1.13/build \
  -DMSDFGEN_USE_VCPKG=OFF -DMSDFGEN_USE_SKIA=OFF \
  -DMSDFGEN_DISABLE_SVG=ON -DMSDFGEN_DISABLE_PNG=ON \
  -DMSDFGEN_BUILD_STANDALONE=ON -DMSDFGEN_INSTALL=OFF
cmake --build msdfgen-v1.13/build --parallel 2
```

The resulting `msdfgen` CLI emitted four bounded 32×32 24-bit BMP fields with
`-pxrange 4 -autoframe`: U+0041, U+0301, U+4E2D, and U+1F469. ASCII and CJK
artifacts were each 3,194 bytes; their SHA-256 values were respectively
`c80670f537b42444c968df11cb6ff6319ee9493a1d226cec2b1cdb74dcd0131c` and
`821d61be255ec121cfeea493883750ca0f8f7becb255ccf087bfdf0191135377`.
Fifty CLI invocations, including process startup and BMP file output, averaged
3.631 ms for U+0041, 3.321 ms for U+0301, and 3.037 ms for U+4E2D on that
host. These are source-spike observations, not Kiwi preprocessing or baseline
performance results: they include a separate process and file I/O, and are
not comparable with `make text-lab` CPU samples.

The generated RGB fields are preprocessing artifacts, not decoded text. They
cannot establish terminal visual quality until a median-distance fragment
shader renders them at Kiwi's actual cell scale. The U+1F469 run likewise does
not establish color-emoji support; it only proves the generator emitted a
field for the selected COLRv1 font. Kiwi must retain its current monochrome or
missing-glyph/atlas behavior for unsupported color/vector glyphs until a
separate result proves otherwise. Combining-mark placement remains an existing
HarfBuzz layout responsibility; generating U+0301 independently is not proof
of combined-text fidelity.

## Required integration boundary

The upstream core is C++, while Kiwi's present native bridge is C17 and its
LuaJIT FFI only declares C APIs. A prototype therefore needs a small
Kiwi-owned C ABI bridge, built from a source-pinned msdfgen revision, which
accepts already-resolved FreeType face/glyph inputs and returns copied pixel
bytes plus plain dimensions/status. C++ objects, FreeType handles, and bridge
state must not cross the text-backend descriptor or semantic resource ABI.
The source revision, archive hash, CMake flags, compiler, generated notice,
and permitted subset of msdfgen files must be pinned and reviewed; a system
package, vcpkg fetch, or prebuilt artifact is not an approved dependency.

The renderer can create and sample `rgba8unorm` textures, but it needs a new
bounded renderer-owned MSDF page/resource and a candidate pass or shader
variant. At the same 1024×1024 page dimensions, an RGBA8 MSDF page occupies
four MiB while the current R8 page occupies one MiB. The prototype must state
entry, page, bitmap-dimension, pixel-range, upload, and failure limits before
allocating. It must not repurpose the current alpha-atlas descriptor or let a
candidate expose WGPU handles. The shader must cover median RGB distance,
derivative/scale handling, alpha blending, tiny-glyph behavior, and a stable
fallback when generation/upload/pipeline creation fails.

## Corpus and comparison requirements

The shared `kiwi-text-corpus-v1` remains the only comparison input. The source
spike covers its representative ASCII, combining, CJK, and emoji-related glyph
classes, but it does not cover shaped multi-glyph sequences, ligatures,
fallback chains, dense UI, final shader output, or a native screenshot. A
prototype must run the full corpus through `make text-lab
BACKENDS=atlas,msdf`, retain equivalent font inventory, shape options, content
scale, host, and terminal semantics, and capture native atlas/candidate
screenshots. Different source pin, font, driver, adapter, corpus, or fallback
outcome is non-comparable evidence.

## Decision

The recommendation is **defer** [issue #141](https://github.com/gongahkia/kiwi/issues/141).
The source spike shows that an audited C++ generator is plausible, but no
checked-in source supply chain, safe C bridge, bounded RGBA resource/shader,
or terminal-quality result exists. Proceed only after all of these gates are
met:

1. a reviewed source pin, archive hash, license/notice record, and reproducible non-vcpkg build are checked in;
2. C-ABI bridge construction, generation failures, ownership, and cleanup have focused tests;
3. MSDF page/resource, upload, shader lifecycle, and capacity failure are bounded and renderer-owned;
4. color glyphs, unsupported outlines, tiny text, CJK, combining marks, and fallback have explicit behavior; and
5. the full lab report, matching native visual evidence, and `make check` pass.

Until then, `atlas` remains the only available backend. A laboratory `msdf`
request is intentionally recorded as the existing `unsupported-backend`
fallback, never as a candidate measurement.

## References

- [msdfgen source and build overview](https://github.com/Chlumsky/msdfgen)
- [msdfgen v1.13 source tag](https://github.com/Chlumsky/msdfgen/tree/v1.13)
- [ADR 0034](0034-text-backend-interface.md)
- [TEXT_LAB.md](../TEXT_LAB.md)
- [BENCHMARKS.md](../BENCHMARKS.md)
