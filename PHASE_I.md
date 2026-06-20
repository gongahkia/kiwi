# PHASE_I.md — Glyph Science Upgrade

**Goal:** Replace the hand-rolled 5×7 glyph bitmaps and 9-region overlap vectors with a font-driven, HoG-based, k-d-tree-accelerated shape matcher. Same shape-vector idea Phase E shipped, but richer features, faster lookup, and font-correct output.

**Exit criteria:** structure mode at 1080p with shape matching is measurably sharper on a fixed test clip (recorded NCC/MSE vs reference), at equal or better fps than v0.5, with the glyph table rebuilt from any user-supplied monospace font. Same `--mode structure` flag, same default behavior; opt-in to richer features via `--glyph-features {overlap|hog|sdf}`.

---

## Architecture decisions locked in this phase

- **FreeType is the source of truth.** Glyph shape vectors are derived from the actual rasterized glyph at the active cell pixel size, not from precomputed 5×7 art.
- **HoG by default, overlap as fallback.** A 2×2 spatial × 8 orientation HoG (32-D) replaces the 9-D circular overlap vector for matching. Overlap stays available behind `--glyph-features overlap` for back-compat and for tests.
- **k-d tree lookup, NCC fallback.** `nanoflann` (header-only) over the HoG vectors. NCC scan kept for `--glyph-features overlap` and for verification tests.
- **One-time offline glyph evolution.** Curated subsets (`portrait-30`, `lineart-40`, `blueprint-24`) ship as named charsets; the evolver is a build-time tool, not a runtime cost.

## §FreeType — dynamic glyph table

- Add FreeType to `third_party/` (or system pkg-config; provide both). Update `DEPENDENCIES.md`.
- New `src/glyph_font.{hpp,cpp}`:
  - `class GlyphFont` owns an `FT_Library`, `FT_Face`, and a cached `GlyphRaster` (`cellPxW × cellPxH`, 8-bit alpha) per `(codepoint, cellPxW, cellPxH)`.
  - Initialized at startup from `--font PATH` or a bundled metric-stable monospace (Iosevka Term Extended or similar; license-clean and small).
  - Recomputed on SIGWINCH / cell-aspect change.
- `GlyphFont::raster(codepoint)` returns the alpha-cell-buffer used by every downstream feature (HoG, SDF, overlap, MP4 export).

- **DoD:** changing `--font` produces a visibly different glyph choice on a fixed frame; the same `GlyphFont` raster feeds shape vectors, ramp ordering (Phase I3), and Phase G3 MP4 export.

## §RampSort — auto-order any user-supplied ramp by density

- Use the new `GlyphFont::raster` to compute total ink per glyph; sort the ramp ascending → consistent dark→light regardless of the order the user passed it in.
- Off by default (preserve current behavior); enable with `--ramp-sort`. Document that this changes output for custom ramps.
- **DoD:** passing a reversed default ramp with `--ramp-sort` produces the canonical output.

## §HoG — 32-D Histogram of Oriented Gradients per glyph

Per glyph, on its `GlyphFont` raster:
1. Compute gradient with a 3×3 Sobel.
2. Partition the cell into 2×2 spatial blocks.
3. In each block, weight each pixel by gradient magnitude into one of 8 orientation bins.
4. Concatenate the 4 × 8 = 32 values; L2-normalize.

Per terminal cell, on the existing `EdgeField` (DoG output or Sobel magnitude):
- Repeat the same procedure on the cell's sample block. Same 32-D vector space.

Match by cosine similarity (`dot(a, b)` since both normalized).

- **DoD:** `tests/glyph_hog_tests.cpp` covers: horizontal-line glyph yields a HoG concentrated in the vertical-gradient bin; diagonal yields the matching diagonal bin; identical glyphs yield identical vectors.

## §SDF — optional signed-distance-field feature mode

- `--glyph-features sdf`. Precompute SDF per glyph at build time (8SSEDT or brute force; cells are tiny so brute force is fine).
- Shape vector becomes continuous overlap integrals between sampling circles and the SDF (positive distance contributes inside, negative weighted by falloff).
- Better disambiguation on thin diagonals at small cell sizes; slightly slower table build, same per-frame cost.
- **DoD:** `--glyph-features sdf` runs; A/B test against `hog` on the cube clip recorded in BENCHMARKS.md.

## §kdTree — fast nearest-neighbor lookup

- Add `third_party/nanoflann.hpp` (header-only).
- After the glyph table is built, construct a `KDTreeSingleIndexAdaptor` over its HoG vectors.
- Per cell shape-match: `tree.knnSearch(cellVec, 1, &bestIdx, &dist)`.
- Cap the curated set size at 128; document the budget.
- For `--glyph-features overlap` keep the existing linear NCC path so tests can verify equivalence.
- **DoD:** at curated-set size 64, shape-match cost per cell drops by ≥10× vs the linear path; output match-rate ≥99% vs linear (the remaining cases are ties broken differently and are documented).

## §Curated — named glyph subsets

- `--charset` already accepts a preset name or a string. Add:
  - `portrait-30` — glyphs that span the HoG space well for face/figure footage.
  - `lineart-40` — heavy in directional + corner glyphs; pairs with `--style hatch`.
  - `blueprint-24` — box-drawing + thin geometric set; engineering aesthetics.
- These are JSON files under `share/contourtty/charsets/`, loaded at startup.
- Built by §Evolve below.

- **DoD:** each preset selectable; the README lists the use case for each.

## §Evolve — offline glyph-subset search

- New `tools/evolve_charset.cpp` (build-only, not shipped in the runtime binary by default):
  - Inputs: a frame corpus (PNG dir), a candidate Unicode set (default: ASCII + Box Drawing + Block Elements + Geometric Shapes + selected Symbols for Legacy Computing).
  - Fitness: maximize average HoG-space spread of the chosen N-glyph subset over the corpus + minimize NCC-tie rate on real frames.
  - Output: a JSON charset file consumable by `--charset NAME`.
- Genetic algorithm or simulated annealing; population ≤200, generations ≤500; should finish under a minute on a laptop.
- Document seeds for reproducibility.
- **DoD:** rerunning the evolver with a fixed seed reproduces the shipped `portrait-30` byte-for-byte.

## §BlockSAD — SAD-based picker for block-element ramps

- For `--charset blocks` (`░▒▓█`) and Phase J's sextant/octant blitters, the right metric is per-pixel SAD against the cell sub-block, not HoG.
- New `src/block_sad.{hpp,cpp}`: precomputed bitmap per block glyph, per-cell SAD, argmin.
- Used by Phase J's blitters, not by structure mode.
- **DoD:** `--mode blocks` (a new mode flag introduced here) renders visibly closer to the source than the current ramp-only path on still-image input.

## §Tests
- `glyph_font_tests.cpp` — FreeType load, cache, resize invalidation.
- `glyph_hog_tests.cpp` — gradient direction sanity, normalization.
- `glyph_sdf_tests.cpp` — corner cases, distance signs.
- `kd_tree_tests.cpp` — nearest-neighbor matches linear scan on synthetic vectors.
- Extend `golden_frame_tests.cpp` with `--glyph-features hog` outputs (new goldens, marked as such).

## §Bench
- Record HoG-match vs overlap-match: per-cell ns, end-to-end fps at 720p / 1080p.
- Record SDF-mode cost vs HoG mode.
- Record curated-set size sweep (16/32/64/128) on the same clip.

## §Files
New: `src/glyph_font.*`, `src/glyph_hog.*`, `src/glyph_sdf.*`, `src/glyph_kdtree.*`, `src/block_sad.*`, `tools/evolve_charset.cpp`, `share/contourtty/charsets/*.json`.
Modified: `src/glyph_shape.cpp` (gains backend dispatch), `src/cli.cpp` (`--font`, `--glyph-features`, `--ramp-sort`), `src/renderer.cpp` (uses new Passes registered by these files), `CMakeLists.txt` (FreeType find_package, nanoflann include).

## Pitfalls
- HoG without L2 normalization → glyphs with more ink dominate matches. Always normalize.
- Building the SDF on every resize → wasted work. Trigger only on font / cell-size change.
- Mixing curated sets across `--glyph-features` modes — the HoG vector for `@` differs from the overlap vector. Each set ships its own precomputed table.
- FreeType hinting at very small cell sizes makes glyph rasters non-monotone in ink count → ramp-sort flips order between two adjacent fonts. Disable hinting (`FT_LOAD_NO_HINTING`) for table builds; keep it on for export-time rasterization.
- nanoflann's adaptor stores a *reference* to the vector array — rebuilding the array invalidates the tree. Rebuild both together.
