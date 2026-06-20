# PHASE_M.md — Temporal Coherence

**Goal:** Kill the per-frame shimmer that makes terminal ASCII video look noisy on pans and slow motion. Three orthogonal levers: glyph-choice hysteresis, optical-flow-warped history, and temporal supersampling. Each lever is a Pass; each is independently toggleable.

**Exit criteria:** on a fixed test clip with a slow camera pan, the rendered ASCII output exhibits visibly less per-cell glyph-flicker than v0.5 (measured: glyph-change rate per cell per second on near-static regions drops by ≥ 60%); A/V drift is unchanged within ±2 ms.

---

## Architecture decisions locked in this phase

- **Temporal state is a separate buffer per `CellBuffer`.** History lives in `src/diff_emitter.cpp` already (the diff emitter holds previous-frame cell state); extend it with score and orientation history for hysteresis.
- **Optical flow is coarse and cheap.** Compute on the working-resolution luminance field (already produced by `LuminanceField` Pass), not on the source RGB; pyramidal Lucas-Kanade or Farnebäck via OpenCV is out of scope (we don't ship OpenCV) — write a 30-line dense block-matching pass in-tree.
- **Frame interpolation is opt-in.** Temporal supersampling decodes faster than the source fps; skip it unless source is < 30 fps. Default off.

## §Hysteresis — sticky glyph selection

Extend Phase I's `shape-match` Pass with a sibling `match-hysteresis`:
- Holds previous-frame `(cell → best_glyph, best_score)`.
- For each cell this frame: compute the new best match; if `new_score < (prev_score × (1 - eps))` *and* `prev_glyph != new_glyph`, keep `prev_glyph`. Otherwise switch.
- `eps` exposed as `--glyph-stickiness` (default 0.05).
- Special case: full repaints (resize, first frame, seek) clear history.

Same idea applied to the directional path: orientation buckets are sticky within `--orient-stickiness` radians.

- **DoD:** on a still image, hysteresis is a no-op (no flicker to suppress). On the pan clip, the per-cell glyph-change rate on near-static regions drops by ≥ 60% with default stickiness; structure quality on real motion unchanged within tolerance.

## §Flow — optical flow on the working luminance

New `src/optical_flow.{hpp,cpp}`:
- Block-matching: working luminance divided into 8×8 blocks; per block, search ±8 pixels for the minimum SAD against the previous frame; store the displacement vector.
- Or a coarse Farnebäck implementation in-tree (more accurate, more code). Block-matching is good enough for the warping step below; start there.
- Output: `FlowField` Pass-buffer, vec2 per coarse block.

`Pass: warp-history` uses `FlowField` to warp the previous `CellGlyphs`/`CellShapeVectors` by the inverse flow before §Hysteresis compares them; the comparison happens in motion-compensated space.

- **DoD:** on a horizontal-pan clip, glyph stability across the pan improves (per-region flicker score drops); on a static clip, flow is ~0 and warping is a no-op.

## §Supersample — temporal supersampling

- When source fps < 30, decode at 2× source fps (one extra interpolated frame between each pair via libavfilter `framerate` or a tiny in-tree blend).
- Accumulate `GradientField` and `LuminanceField` across the two sub-frames before passing into the shape match.
- Emits at source fps; the supersampled analysis just feeds a cleaner signal into the matcher.
- `--temporal-supersample N` (default 1 = off).

- **DoD:** at source fps 12, `--temporal-supersample 2` produces measurably steadier orientation fields on the cube clip vs N=1, at the cost of ~1.5× decode CPU.

## §EmitDeltaOklab — perceptual diff threshold

Extend `src/diff_emitter.cpp`:
- Currently emits when glyph or color differs. Switch the color test to "differs in OKLab by > Δ" so sub-perceptual changes don't re-emit SGR.
- Δ exposed as `--diff-oklab-eps` (default 0.005).
- Reduces wire bandwidth on subtle-gradient pans by an estimated 20-40% without visible quality loss.

- **DoD:** bytes-per-frame on the pan clip drops vs v0.5; visual goldens unchanged within tolerance.

## §Seek — temporal state clear

- On `space`-pause/resume, no clear (history stays valid).
- On left/right arrow seek, clear all temporal buffers and force full repaint (already done for full repaint; extend to clear history).
- On `--loop` wraparound, clear.

- **DoD:** seeking forward then back doesn't carry ghost glyph choices into the new region.

## §Tests
- `optical_flow_tests.cpp` — synthetic translation produces matching flow vectors; static frames produce zero flow.
- `hysteresis_tests.cpp` — verify decision boundary at the stickiness threshold; verify state clears on seek/resize.
- Temporal flicker metric in `tests/golden_frame_tests.cpp`: render N frames of a paired clip, count per-cell glyph changes per second; assert below a threshold for `--glyph-stickiness 0.05`.

## §Bench
- Per-Pass cost: optical_flow at 720p, hysteresis check overhead, supersample decode overhead.
- Bandwidth: bytes/frame with vs without OKlab Δ filter on pan and static clips.

## §Files
New: `src/optical_flow.{hpp,cpp}`, `src/hysteresis.{hpp,cpp}`, `src/warp_history.{hpp,cpp}`, `src/temporal_supersample.{hpp,cpp}`.
Modified: `src/diff_emitter.cpp` (OKLab diff), `src/cli.cpp` (`--glyph-stickiness`, `--orient-stickiness`, `--temporal-supersample`, `--diff-oklab-eps`), `src/renderer.cpp` (Pass insertion), `src/player.cpp` (history clear on seek).

## Pitfalls
- Hysteresis on top of a noisy matcher → glyphs "stick" to a wrong choice once and never recover. Always allow switches when new score is clearly better; bound the stickiness ε.
- Block-matching flow has aperture problems on featureless regions; output is unreliable on flat colour and that's OK — warp-history just falls back to the unwarped previous glyph there.
- Temporal supersample causes apparent motion blur in the matcher; document and disable for sports/action content.
- OKLab diff threshold tuned too high → visible color popping; default conservative.
- History buffer not invalidated on `--font` change → glyph ids point to wrong codepoints. Clear on every config change that affects the glyph table.
