# Kiwi M2 text architecture

Kiwi M2 makes text a semantic terminal concern followed by a native shaping and rasterization pipeline. It is deliberately not a general Unicode layout engine: grid geometry comes from the terminal-width contract, HarfBuzz determines glyph IDs and placement inside that geometry, and bidi/reordering is outside this milestone.

## Unicode contract

The checked-in source is Unicode **17.0.0**. `unicode/17.0.0/SHA256SUMS` pins the exact official UCD inputs: GraphemeBreakProperty, GraphemeBreakTest, DerivedCoreProperties, EastAsianWidth, emoji-data, and emoji-variation-sequences. `src/kiwi/unicode/generated.lua` is generated data, not hand-maintained policy.

```sh
./script/fetch-unicode       # refetches only the pinned Unicode 17.0.0 inputs and records hashes
make generate-unicode        # regenerates generated.lua deterministically
make test-unicode            # runs the complete checked-in official GraphemeBreakTest corpus
```

`test_unicode.lua` validates all 766 cases in the pinned GraphemeBreakTest file. `unicode/grapheme.lua` implements extended grapheme cluster (EGC) boundaries under UAX #29, including CR/LF/control, Hangul, Extend/ZWJ/SpacingMark/Prepend, Indic_Conjunct_Break, Extended_Pictographic ZWJ, and regional-indicator rules. The input decoder, parser, and state accept arbitrary chunks; segmentation is independent of PTY read boundaries.

`src/tests/fixtures/text/width.lua` is Kiwi-owned, readable policy data. It covers ASCII, precomposed/decomposed and leading combining text, ambiguous-width modes, Han/Hiragana/Katakana/Hangul/fullwidth/halfwidth forms, presentation selectors, modifiers, ZWJ family/profession sequences, flags, keycaps, copyright/trademark presentation, private-use, and malformed UTF-8 replacement. This is separate from the official UAX #29 corpus because cluster width is Kiwi terminal policy rather than a Unicode conformance claim.

Kiwi retains original code points and does no normalization, NFC/NFD conversion, case folding, or rewrite. A leading combining mark, ZWJ, or spacing mark is stored as received and is rendered with a dotted-circle display fallback so it remains visible. A cluster is capped at 64 code points by default (`max_cluster_codepoints`); further non-breaking code points begin a new visible cluster and increment `over_limit_clusters`. This is a deliberate resource bound for hostile streams, not a Unicode normalization policy.

## Terminal-width policy

`terminal/width.lua` is the only authority for terminal columns. Its policy ID is `kiwi-m2-width-v1` and it never delegates widths to font advances, HarfBuzz, Fontconfig, or the host `wcwidth` implementation.

| Input class | Columns |
| --- | ---: |
| Normal EGC | 1 |
| East Asian Width `W` or `F` | 2 |
| EAW `A` | 1 by default; `KIWI_AMBIGUOUS_WIDTH=2` selects 2 |
| Private-use code point | 1 |
| Emoji presentation, VS16 emoji sequence, keycap, regional-indicator sequence, or emoji ZWJ sequence | 2 |
| VS15 text presentation | normal EAW/private-use result |

`KIWI_AMBIGUOUS_WIDTH` is a startup configuration and accepts the documented terminal choices `1` (default) or `2`; changing width policy during a session is intentionally not supported because it would require semantic reflow of the live terminal grid. The active policy is passed to every cluster width decision and is deterministic for replay. Private-use width is represented by the same policy object and defaults to 1; M2 does not expose a separate user switch yet.

When an extending code point changes a cluster from one to two columns, Kiwi takes the adjacent blank cell only if it is still available. Otherwise it preserves the old footprint and increments `width_change_clamped`; this avoids overwriting a subsequent cluster. At the right margin a two-column cluster wraps early with DECAWM enabled, or is displayed in one column with DECAWM disabled. The same `width_change_clamped` counter reports this safe degradation.

## Grid and mutation model

Each semantic cell stores `glyph`, original `codepoints`, `display_text`, SGR attributes, and width. A two-column cluster has one anchor (`width=2`) followed by one continuation (`width=0`, `continuation=true`, `anchor_column=<anchor>`). Continuation cells have no independently drawable text. Parser writes route code points to the terminal state, which joins an EGC only when its previous cluster is still adjacent on the same active screen; cursor movement, edits, scrolling, resize, alternate-screen changes, and reset clear that context.

Printable ASCII takes a narrow-state fast path: it retains the same singleton cluster semantics while bypassing Unicode-property width classification when the prior cluster cannot be a UAX #29 `Prepend` sequence. The production direct sink updates those existing singleton clusters without transient cell tables. Controls, non-ASCII bytes, callback-mode parsing, and `Prepend × ASCII` remain on their established paths. This lowers ordinary ASCII terminal-state cost without making ASCII a separate storage model.

Overwrite, erase, insert/delete character, resize, scroll, and alternate-screen transitions normalize rows so an anchor is never left without its continuation and a continuation is never left without its anchor. A clipped right-edge wide anchor degrades to one cell during normalization. Snapshots expose structured cluster metadata only when needed, preserving legacy ASCII fixture readability.

Logical grid damage and shaped-glyph invalidation are separate. State maintains `damage` for cells/cursor presentation and `text_damage` for content that requires reshaping. Cursor movement, cursor visibility, and SGR state changes alone do not mark `text_damage`; cell mutation, edit/scroll, resize/reset, history movement, and screen changes do. `text/layout.lua` consumes text damage after an update and reshapes each affected row once; static rows reuse their cached glyph list. The renderer still uploads background cell records only for logical damage, while the shaped-glyph buffer represents the visual layer.

Changing HarfBuzz feature options or clearing fallback decisions increments the font text generation and invalidates shaped rows without falsely expanding logical terminal damage. Replacing the font system likewise invalidates the layout. The live app recreates font faces, glyph cache, row layout, renderer, and terminal grid dimensions when GLFW content scale changes, so bitmaps are not reused at the wrong physical size.

## Native shaping, fallback, and rendering

The native path is FreeType + HarfBuzz + Fontconfig through narrow LuaJIT FFI declarations. `FontSystem` owns the FreeType library, `Face` owns a FreeType face and its HarfBuzz font, and destruction runs in reverse ownership order: HarfBuzz font, FreeType face, then FreeType library. Construction failures clean up partially acquired native handles.

For a contiguous same-face run, the layout concatenates its cluster display text and shapes it with `hb_ft_font_create_referenced`, a fresh HarfBuzz buffer, `HB_BUFFER_CLUSTER_LEVEL_MONOTONE_GRAPHEMES`, and explicit LTR direction. Glyph cluster byte offsets are mapped back to terminal columns. `liga` and `calt` are disabled by default to preserve terminal-cell behavior; `KIWI_LIGATURES=1` and `KIWI_CALT=1` enable them at startup. These options change glyph placement only; they never change terminal cell width.

Fontconfig chooses the configured primary family (`KIWI_FONT_FAMILY`, default `monospace`) or `KIWI_FONT` path. Singleton printable ASCII primary-coverage results are cached after the first FreeType probe in a bounded 95-entry table; a negative result still proceeds to normal fallback rather than assuming ASCII coverage. Missing clusters are otherwise matched by their full code-point set, then cached. The primary face is required; fallback face loading, face-cache exhaustion (default 32 faces), unavailable code points, and negative matches degrade to the missing-glyph path instead of expanding unboundedly or crashing the rendering path. The sequence fallback cache is capped at 1024 entries, including negative entries.

Rasterization is by **glyph ID**, not the first Unicode scalar. The dynamic grayscale atlas has one 1024×1024 `r8unorm` page, a default 8,192-entry bound, 512-pixel bitmap-dimension bound, and no eviction. It keys entries by face ID, glyph ID, size, and raster mode. On glyph-cache or page exhaustion, unsupported bitmap format, missing glyph, or a glyph-instance capacity overflow, Kiwi emits the existing `?` fallback or omits that glyph safely and records diagnostics. An atlas generation upload currently sends the whole alpha page; this is simple and bounded but is an acknowledged performance limitation.

The cache also remembers bounded rasterization failures and records a saturation reason once the page/entry limit is reached. Repeated glyphs after saturation return the deterministic failure without invoking FreeType again. Negative-failure entries are bounded independently; this keeps both atlas memory and repeated raster work bounded under hostile unique-glyph streams.

The GPU has separate cell/background, shaped-glyph, dynamic alpha-atlas, sampler, and frame bindings. `KiwiGlyphInstance` remains the 40-byte legacy cell record for M0/M1.5 measurements. `KiwiTextGlyphInstance` is a separate, asserted 48-byte record carrying float glyph geometry, UVs, color/flags, glyph ID, and terminal cluster column. A fixed selection range in the frame uniform clips stable row-ID endpoints to the current viewport; it is alpha-blended after background and before glyphs, so it does not change shaping or cluster ownership. The terminal is rendered as background, selection, glyph, then cursor passes—not as a precomposed bitmap.

FreeType BGRA/color glyph bitmaps are rejected safely by the grayscale atlas. On the verified Fedora host, Fontconfig selected a monochrome fallback for the default emoji case and direct Noto Color Emoji COLRv1 rasterization did not yield a usable grayscale bitmap. Therefore M2 provides semantic emoji clustering, width, fallback selection, and monochrome glyph rendering where a usable face exists; it does **not** claim color emoji rendering. Private-use/Nerd Font characters use ordinary Fontconfig fallback and the same glyph-ID path; the optional `MartianMono Nerd Font` test exercises U+E0B0 when that host font is installed. Ligatures are opt-in and are not treated as terminal-width features.

## Text backend boundary

`kiwi.text.backend` is the renderer-scoped v1 seam for experimental
rasterization. Normal startup always selects the `atlas` baseline. A developer
laboratory request is explicit and isolated: `KIWI_TEXT_LAB=1` together with
`KIWI_TEXT_LAB_BACKEND=atlas` (or a future candidate) is the only app-level
selection route. An unsupported requested name remains observable in renderer
metrics as an `atlas` fallback with `fallback_reason=unsupported-backend`; it
never changes terminal layout, width, HarfBuzz mapping, or PTY input. The
backend descriptor contains only plain capability data, not font or wgpu
handles. The renderer continues to own GPU resources and `FontSystem` remains
app-owned. See [ADR 0034](adr/0034-text-backend-interface.md) for the stable
input/output, lifetime, fallback, and prototype-comparison contract.

The Slug investigation is currently deferred, rather than exposed as a partial
`KIWI_TEXT_BACKEND` choice. The native HarfBuzz GPU library is absent from the
supported host and the current glyph pass owns only `text.shaped_glyphs` and
`text.alpha_atlas`. `make slug-feasibility` records the exact missing
precondition (and intentionally exits nonzero); [ADR 0035](adr/0035-slug-gpu-backend-feasibility.md)
defines the source pin, bounded blob/resource, fallback, and corpus gates that
must be met before the existing atlas fallback can be changed.

MSDF is also deferred after a source-only generator spike: it produced bounded
raw fields but has no reviewed C++ bridge, RGBA text resource, final shader, or
native terminal-quality evidence. A laboratory `msdf` request remains an
observable atlas fallback. [ADR 0036](adr/0036-msdf-backend-feasibility.md)
records the source pin, representative glyph artifacts, comparison limits, and
promotion gates.

## Diagnostics and inspection

F4 diagnostics include pinned Unicode version, primary path, loaded fallback face count, visible shaped run/glyph totals, row invalidation/reshape/run/glyph counts, shaped-row cache hits/misses, glyph-buffer upload/drop counts, atlas hit/miss/failure counts, fallback results, wide-cluster count, and over-limit cluster count alongside M1 PTY/parser metrics. They are rate-limited to one report per second and do not dump control-string payloads.

Run a bounded native text laboratory child with:

```sh
KIWI_MAX_FRAMES=240 make text-demo
```

`--inspect` prints the cell at the terminal cursor after the child exits; `--inspect=ROW,COLUMN` selects a zero-based cell explicitly. It reports raw code points, anchor/continuation status, width, selected face path/ID, fallback decision, stored text, and mapped HarfBuzz glyph IDs/clusters/advances/offsets/atlas page. It is a single-cell inspector, not an interactive selection UI.

## Measurement and stress

```sh
make bench-text
KIWI_TEXT_BENCH_ITERATIONS=100 KIWI_TEXT_BENCH_WARMUP=20 make bench-text
make text-corpus-review
KIWI_MAX_FRAMES=240 make text-corpus-demo
make text-lab
make text-lab BACKENDS=atlas,msdf
make text-lab-demo BACKEND=atlas
make bench-write
KIWI_WRITE_BENCH_ITERATIONS=500 KIWI_WRITE_BENCH_WARMUP=100 make bench-write
make bench-text-stress
KIWI_TEXT_STRESS_ROUNDS=2000 make bench-text-stress
```

`src/kiwi/text/benchmark_corpus.lua` supplies the shared ASCII, combining, CJK, emoji, ligature, and dense-UI scenarios to `bench-text` and `text-corpus-demo`. `make text-corpus-review` writes the deterministic corpus/host manifest used with a native screenshot for quality review; see [BENCHMARKS.md](BENCHMARKS.md) for the source/license fields, comparison limits, and required artifact. `bench-text` writes `bench/results/*-text.json` and separates UAX #29 segmentation, width policy, fresh/cached HarfBuzz shaping, initial/primary/cached Fontconfig fallback, glyph-cache miss/hit/bounded-capacity paths, cold/cached/edited row layout, and the full parser → terminal-cluster → glyph-instance CPU path. `bench-write` writes schema-4 `*-write.json` stage attribution for parser/UTF-8, cluster mutation, two damage streams, run construction, HarfBuzz, fallback, atlas/glyph records, cursor-only invalidation, and full parser-to-glyph-record CPU work. Setup objects are intentionally created before a timed iteration, as documented in each result scope; GPU submission, execution, and presentation are excluded. `bench-text-stress` mixes unique glyph pressure, combining-limit pressure, CJK, emoji, PUA, bounded negative fallback, CSI edits, resize, row layout, and repeated text-system construction/destruction while asserting grid, atlas, face/fallback cache, and RSS bounds. It writes `*-text-stress.json`.

`make text-lab` writes a bounded `*-text-lab.json` report with the atlas
baseline first, every requested backend descriptor, per-corpus `backend:update`
CPU samples, semantic manifest, font inventory, fallback status, manual visual
review command, and promotion/retirement criteria. It is a developer tool, not
a user setting: `BACKENDS=atlas,msdf` affects only the report, while
`make text-lab-demo BACKEND=msdf` passes the explicit laboratory gate to a
bounded native corpus run. A fallback record is deliberately labeled
unavailable rather than treated as a candidate result. See
[TEXT_LAB.md](TEXT_LAB.md) for the report template and review procedure.

The native smoke target and a windowed `make text-demo` exercise shader compilation and the GPU path; they are not pixel-comparison or color-emoji conformance tests. See [BENCHMARKS.md](BENCHMARKS.md) for output semantics and [CONFORMANCE.md](CONFORMANCE.md) for deterministic test coverage.

## Explicit M2 boundaries

- Logical LTR shaping only; no bidi, Arabic joining/reordering policy, or Unicode line-break algorithm.
- No color emoji atlas, COLR/CBDT/SVG compositor, variable-font UI, font hot reload, or atlas eviction/multipage growth.
- No runtime width-policy switch or grid reflow; choose the width convention at terminal startup.
- No proof that a particular installed Nerd Font covers a private-use code point; missing coverage uses normal fallback behavior.
- No visual equality claim against other terminal emulators. Deterministic state and HarfBuzz differential tests cover the bounded behavior implemented here.
