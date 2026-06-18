# PHASE_E.md — Structure Mode (The Differentiator) (→ v0.5)

**Goal:** The reason this project exists. Choose glyphs by **shape / edge orientation**, not just brightness, computed live — so output looks *drawn* (characters follow contours, edges stay sharp) rather than *dithered* (blurry, jagged). This is what no existing terminal player does and what the graphics-programming audience rewards.

**Exit criteria → tag `v0.5`:** structure mode renders live video with contour-following, sharp-edged ASCII that is *visibly* better than luminance mode, at an interactive framerate, with tunable parameters.

---

## Background: why luminance ramps look bad at edges

Treating each cell as a single pixel (average brightness → ramp glyph) is nearest-neighbor downsampling. Even with supersampling you're just rendering a low-res blurry image with characters standing in for pixels. The fix (per Alex Harri's "ASCII characters are not pixels") is to **use the glyph's shape**: pick the character whose ink distribution within the cell matches the image structure in that cell. A diagonal edge should become `/` or `\`; a vertical edge `|`; a top-heavy region `T`/`▀`; etc.

Two implementations, building up:
- **E4 directional mapping** — fast, good: edge orientation → a small set of line glyphs. (Acerola's approach: Sobel/DoG edges drive directional characters.)
- **E5–E6 shape-vector matching** — best: quantify every glyph's shape and match each cell's structure to the closest glyph. (Alex Harri's approach.)

Ship E4 first (immediate visible win), then E6 as the high-fidelity tier.

## §Sampling — give each cell its full sub-region
- From Phase B, each cell corresponds to a `cellPxW × cellPxH` block of working-resolution pixels (e.g. 4×8). Structure mode analyzes the whole block, not just the center.
- Keep a grayscale version of the working image for gradient math.

## §Sobel — gradient per cell
- Apply Sobel operators over the grayscale working image:
  - `Gx = [[-1,0,1],[-2,0,2],[-1,0,1]] * I`, `Gy = transpose`.
- Per cell, aggregate (sum/average) the block's gradients → `Gx_cell, Gy_cell`.
- `magnitude m = hypot(Gx,Gy)`, `orientation θ = atan2(Gy,Gx)`.
- Unit tests: a vertical edge yields horizontal gradient (θ ≈ 0/π), a horizontal edge yields vertical gradient (θ ≈ ±π/2), a 45° edge yields θ ≈ ±π/4.

## §DoG — Difference-of-Gaussians line isolation (optional, improves quality)
- Blur the grayscale at two scales σ1 < σ2; `DoG = G(σ1) − k·G(σ2)`; threshold to isolate clean line structure and suppress noise/texture. This is the classic stylized-edge primitive (also used in Acerola's shader).
- Expose `--dog-sigma σ1[,σ2]` and a threshold; allow toggling DoG vs raw Sobel.
- Feed DoG (when on) into the edge decision instead of/in addition to raw Sobel magnitude.

## §Directional — orientation → glyph (E4, the first shippable win)
- If `m > edge_threshold`: quantize θ into bins → glyph:
  - |θ| near 0 or π (horizontal gradient ⇒ vertical edge) → `|`
  - θ near ±π/2 (vertical gradient ⇒ horizontal edge) → `-` or `_`
  - θ near +π/4 / −3π/4 → `/`
  - θ near −π/4 / +3π/4 → `\`
  - high magnitude in multiple directions / corner → `+`
- Else (`m ≤ threshold`): fall back to the §luminance ramp glyph.
- Test clip: a rotating cube/line should show characters tracking the contour as it rotates.
- **DoD:** edges visibly follow contours; below-threshold areas shade by luminance.

## §ShapeVectors — quantify every glyph's shape (E5)
Per Alex Harri's method:
- Render each candidate glyph into a cell-sized bitmap (use **FreeType** with a bundled monospace font, or precompute bitmaps offline and embed them).
- For each glyph, compute a **shape vector**: place several sampling regions (e.g. circles) within the cell — upper, lower, left, right, center, diagonals — and for each region compute the fraction of glyph ink covering it (overlap ∈ [0,1]). The vector of these overlaps quantifies *where in the cell the glyph puts ink*.
- Normalize vectors (divide each component by the max across glyphs) so they spread across the space rather than clustering.
- Store the glyph→shape-vector table once at startup (it's font- and cell-size-dependent; recompute on cell-size change).

## §Matching — pick the glyph whose shape matches the cell (E6, the high-fidelity tier)
- For each cell, build the **cell's shape vector** the same way: from the cell's sub-region, compute ink/structure coverage in the same sampling regions (using the DoG/edge field, or a thresholded structure map, as the "ink").
- Pick the glyph whose shape vector best matches via **normalized cross-correlation** (or nearest vector by cosine/Euclidean). That's the output glyph.
- Optionally blend with luminance for fill where there's no strong structure.
- Compare against E4 on the cube test: edges should be visibly sharper/cleaner.
- **Performance:** this is the hotspot — `cells × glyphs × vector_dim` per frame. Mitigations: cap the candidate glyph set (a curated ~30–60 glyphs, not all 95), precompute glyph vectors once, use a low vector dimension (6–9 regions), SIMD the matching, and defer to the GPU path in Phase G. Measure in §Bench.

## §Contrast — cel-shading-style contrast pre-pass (E7)
- Before matching, optionally enhance contrast / posterize to sharpen separation between regions (per the reference; this is what made the 3D Saturn/cube scenes read well).
- Expose `--contrast` (0 = off). Document that it trades realism for legibility.

## §Blend — combine fill + edges (E8)
- Final glyph selection policy: strong structure ⇒ shape-matched/directional glyph; weak structure ⇒ luminance ramp. A tunable edge-strength controls the crossover.
- For ANSI color mode, color comes from the cell's representative color regardless of glyph choice (Phase F handles palette tiers).

## §Knobs (E9)
Expose and document: `--mode {luminance|structure}`, `--edge-threshold`, `--dog-sigma`, `--contrast`, `--charset`, plus a `--structure-quality {directional|shape}` to pick E4 vs E6.

## §Bench (E10)
- structure (directional) fps, structure (shape-match) fps, and per-cell matching cost vs luminance, at 720p/1080p. Identify the hotspot for Phase G.

## §Demo (E11)
- Side-by-side GIF: luminance vs structure on *real* footage (not just Bad Apple). This is the asset the whole launch hinges on; make it good. README leads with it.

## Pitfalls
- Matching against all 95 glyphs every cell every frame → too slow. Curate the set; precompute; SIMD; GPU later.
- Shape vectors not normalized → everything maps to a few glyphs (the reference calls this out explicitly).
- Using raw Sobel on noisy/low-contrast footage → noisy glyph soup. DoG + threshold + the contrast pre-pass are what make real footage look good.
- Font dependence: glyph shapes (hence vectors and ramp density) depend on the rendering font. Bundle a known monospace font and compute vectors from it; document that the output assumes that font's metrics.
- Cell aspect must already be correct (Phase B); shape matching amplifies any stretch error.
