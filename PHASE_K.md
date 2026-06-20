# PHASE_K.md — Stylized NPR Modes

**Goal:** Ship four named visual styles — painterly, hatch, stipple, flow — that produce distinct looks no other terminal player has. Each is a small set of Passes added to the graph, gated by `--style`. None of them remove existing modes; each composes with `--mode` so a user can ask for, say, octant-fill with hatch-overlay.

**Exit criteria:** each style produces a visibly distinct, recognizable look on the standard test clip; each runs at ≥ 24 fps on 720p truecolor on the reference Mac mini; styles compose cleanly with all blitter modes from Phase J.

---

## Architecture decisions locked in this phase

- **Style is a set of Passes inserted into the graph**, not a mode override. The graph for `--style painterly --mode octant --structure-overlay on` is: `decode → kuwahara → luminance → contrast → dog → sobel → edge-field → octant → overlay-structure → emit`.
- **All NPR Passes have CPU and GPU (Metal/Vulkan) implementations.** CPU first for correctness, GPU added once the algorithm is locked. ETF and Kuwahara are obvious GPU candidates.
- **No new dependencies.** Everything in K is built on Phase H's graph, Phase I's glyph table, and the existing Sobel/DoG primitives.

## §ETF — Edge Tangent Flow + Coherent Line Drawing

New `src/etf.{hpp,cpp}`:

- Start with the existing Sobel `GradientField`.
- Compute a smoothed tangent field by iterating: at each pixel, blend its tangent with neighbors weighted by `(magnitude_neighbor × cos(angle_diff))`.
- 3–5 iterations is enough; documented as `--etf-iters`.
- Output replaces the orientation source for Phase J's structure overlay and for Phase E's directional/shape selection.

A second small Pass (CLD): convolve a small kernel along the smoothed tangent direction to produce a cleaned-up "line" field; threshold for edges.

- **DoD:** on a rotated cube clip, character runs follow long edges as continuous diagonals instead of breaking into glyph noise; recorded visual A/B against raw Sobel.

## §Kuwahara — anisotropic Kuwahara filter pre-pass

New `src/kuwahara.{hpp,cpp}`:

- Anisotropic variant: per-pixel structure tensor → orientation + anisotropy → 8 directional sectors → pick the sector with the lowest variance, output its mean.
- Pre-pass before luminance/contrast/DoG.
- Cheap on GPU; CPU implementation provided too. Cost dominated by structure-tensor smoothing.

`--style painterly` chains Kuwahara → existing structure pipeline. The result is the painterly look that cel-shading + edge extraction is famous for.

- **DoD:** painterly preset produces visibly larger, flatter color regions before structure analysis; cube test still tracks contours.

## §Hatch — orientation-only cross-hatching

New `src/crosshatch.{hpp,cpp}`:

- Use only the hatch-glyph subset: `─│╱╲╳` plus Unicode 16 hatch characters where the font supports them.
- Orientation chosen by ETF tangent; magnitude controls density (stochastic drop based on a deterministic blue-noise mask).
- For shaded fills, density modulates by luminance: dark regions = dense hatch, light regions = sparse or blank.
- **DoD:** `--style hatch` renders a face/figure as an ink-style cross-hatch drawing; output is recognisable at 160×45.

## §Stipple — blue-noise stippling

New `src/stipple.{hpp,cpp}`:

- Precomputed blue-noise mask (`void-and-cluster`, 64×64 tile).
- Per cell, threshold luminance against the tiled mask sample to decide dot density bucket.
- Glyph subset: `·∙•●◉◍○◌◯⬤◇◆◊` (curated; verify each is monospace-safe in the active font via FreeType `FT_Get_Char_Index`).
- Optional sub-cell precision: use braille/octant *as the dot pattern carrier*, so a cell carries up to 8 (braille) or 8 (octant) stipple dots placed per the blue-noise field.

- **DoD:** `--style stipple` renders a high-contrast image as a recognizable point-cloud; sub-cell-precision flag improves apparent resolution without higher cell count.

## §Flow — Line Integral Convolution

New `src/lic.{hpp,cpp}`:

- Generate a per-frame deterministic noise field (hash-based, seed per source frame for temporal coherence).
- Integrate the noise along the ETF tangent direction for `--lic-length N` steps.
- Output drives braille / octant dot density along the flow lines.
- The look: pen hatching that *follows* image flow, not screen axes.

- **DoD:** rendering a video pan with `--style flow` shows ink strokes aligned with motion gradients; turns off cleanly when `--style none`.

## §Posterize — OKLab-bucketed contrast

Replace `--contrast` scalar with an optional OKLab-domain posterization step. (Existing scalar contrast stays as `--contrast-gain`.)

- `--posterize N` quantizes the L channel of OKLab into N levels; `a` and `b` optionally too.
- Pairs naturally with hatch and stipple modes; replaces the current cel-shading hack with a perceptual one.

- **DoD:** `--posterize 4 --style hatch` produces 4 distinct shading densities across a face; perceptually uniform.

## §StyleComposition — graph wiring

`--style` resolves to a Pass list inserted at fixed graph slots:

| Style       | Inserted Passes (in order)                                |
|-------------|-----------------------------------------------------------|
| `none`      | (no change)                                               |
| `painterly` | `kuwahara` before `luminance`                             |
| `hatch`     | `etf` after `sobel`; `crosshatch` replaces `overlay-structure` |
| `stipple`   | `stipple` replaces the blitter unless one is forced       |
| `flow`      | `etf` after `sobel`; `lic` consumes `etf` output          |

`--style` is single-valued. Multiple styles composed via `--graph file.yaml` (Phase L).

- **DoD:** `--graph dump` for each style shows the documented insertion.

## §Tests
- `etf_tests.cpp` — convergence on synthetic edge fields; idempotence after enough iterations.
- `kuwahara_tests.cpp` — known-flat-region preservation; edge-region orientation match.
- `crosshatch_tests.cpp` — orientation→glyph mapping.
- `stipple_tests.cpp` — blue-noise tile statistics; bucket boundaries.
- `lic_tests.cpp` — integration along a constant field is a constant; along a circular field traces a circle.
- Golden frames for each style.

## §Bench
- 720p / 1080p fps per style; CPU vs GPU per Pass.
- Identify which style is the slowest and whether GPU mitigates it (Kuwahara expected to dominate).

## §Files
New: `src/etf.{hpp,cpp}`, `src/kuwahara.{hpp,cpp}`, `src/crosshatch.{hpp,cpp}`, `src/stipple.{hpp,cpp}`, `src/lic.{hpp,cpp}`, `src/posterize.{hpp,cpp}`, `share/contourtty/noise/blue_noise_64.bin`.
Modified: `src/cli.cpp` (`--style`, `--etf-iters`, `--posterize`, `--lic-length`), `src/renderer.cpp` (graph insertion).

## Pitfalls
- ETF too many iterations → over-smoothed orientations, loses local detail. Cap iterations; expose knob.
- Kuwahara variance computation in 8 directional sectors is O(N) per pixel even on GPU; structure tensor smoothing dominates — make it separable.
- Stipple looks like banding if you use white noise; blue noise is non-negotiable.
- LIC noise re-seeded per frame → shimmer. Seed by source-frame index for temporal coherence (Phase M handles this; here, use a stable seed for now).
- Crosshatch on terminals with non-square cells: the hatch glyphs `╱╲` already assume cell aspect; if `--cell-aspect` is wrong the lines slope incorrectly. Document.
- Don't apply posterize *after* color quantization — the quantizer must see continuous color. Insert before any Phase F quantizer Pass.
