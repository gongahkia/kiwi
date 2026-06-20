# PHASE_N.md — Hybrid Graphics Protocols

**Goal:** On terminals that natively support Kitty graphics, Sixel, or iTerm inline images, render the *rasterised* output of the ASCII renderer back through that protocol — and, when the user asks, layer text glyphs *over* the pixel output for crisp contours. Bridges contourtty from "best ASCII player" to "best terminal media player full stop" without abandoning the ASCII look.

**Exit criteria → tag `v0.95`:** `--render-mode pixel` plays a clip via Kitty graphics on a Kitty-capable terminal at full-source-resolution fidelity; `--render-mode hybrid` overlays the structure-glyph layer on the pixel layer with measurable contour sharpness vs pixel-only; `text` mode (the default) is unaffected.

---

## Architecture decisions locked in this phase

- **Pixel output is the same buffer Phase G3 needs for MP4 export.** Reuse Phase I's `GlyphFont::raster` to compose a per-frame pixel buffer; emit through whichever protocol the terminal supports.
- **Hybrid layering is two passes, not a magic shader.** A pixel layer (image-protocol upload) underneath a sparse text layer (only cells where the structure overlay fires).
- **Detection lives in `TerminalCaps` from Phase J.** Already detects Kitty / Sixel / iTerm support. Phase N consumes that flag set.

## §RasterCompose — pixel buffer from the CellBuffer

New `src/raster_compose.{hpp,cpp}`:
- For each cell, look up `(glyph, fg, bg)` and rasterize the glyph from `GlyphFont` into the cell's `cellPxW × cellPxH` slot in a working RGB buffer at `cols*cellPxW × rows*cellPxH`.
- Use the alpha mask from FreeType: ink pixels get fg, background pixels get bg, anti-aliasing uses the alpha for fg/bg blending.
- This is the same code path Phase G3 (MP4 export rasterization) needs. Implement once, share.

- **DoD:** for a `--mode luminance` test frame, the composed pixel buffer rendered to PNG visually matches the terminal output (modulo font choice).

## §KittyGraphics — Kitty terminal graphics protocol

New `src/kitty_graphics.{hpp,cpp}`:
- Encode the composed pixel buffer as PNG (use `stb_image_write`, single-header) or raw RGB; protocol supports both. Prefer PNG for compression.
- Wrap in the Kitty graphics escape: `\x1b_Ga=T,f=100,m=...;<base64 chunked>\x1b\\`.
- Persistent IDs and `a=p` placement to avoid full reuploads when only part of the frame changes; track previous frame, send delta regions.
- Chunked transmission (4096-byte chunks per protocol).

- **DoD:** a 720p clip plays on Kitty/Ghostty/WezTerm via `--render-mode pixel`; resize and quit work cleanly; cursor position restored.

## §Sixel — sixel encoder

New `src/sixel.{hpp,cpp}`:
- Use `libsixel` (system or vendored). Pre-quantize to a 256-color palette (Phase F or Phase E1 OKLab quantizer).
- Encode per-frame; flush.
- Sixel performance is the bottleneck on most terminals; document that Sixel is for stills / slow playback, not real-time video.

- **DoD:** a still image renders via Sixel on xterm-sixel/foot/wezterm; documented that motion video may exceed terminal throughput.

## §ITermInline — iTerm2 image protocol

New `src/iterm_inline.{hpp,cpp}`:
- `\x1b]1337;File=inline=1;width=Npx;height=Mpx;preserveAspectRatio=0:<base64 PNG>\x07`.
- Best for the `--still` snapshot path (Phase P3); useful for one-shot frames.
- Real-time video via iTerm inline images is possible but inferior to Kitty graphics; supported but not the default.

- **DoD:** `--still` over iTerm inline produces an in-place image; per-frame motion supported on iTerm with documented caveats.

## §RenderMode — `--render-mode {text|pixel|hybrid|auto}`

- `text` (default): unchanged from prior phases; no graphics protocol.
- `pixel`: use the best supported graphics protocol per `TerminalCaps`; bypass blitter glyph selection except as overlay (see hybrid).
- `hybrid`: pixel layer underneath; text glyph layer on top, only for cells with strong structure-overlay glyphs (Phase J).
- `auto`: pick `pixel` if caps allow *and* `--mode auto` would have picked the pixel rung; else `text`.

Concretely, hybrid mode runs the full structure pipeline; emits the pixel buffer as a graphics-protocol frame; then emits a sparse text overlay using the existing diff emitter for only the cells where structure overlay produced a non-default glyph. Terminal text rendering composites the text over the image automatically.

- **DoD:** on Kitty, `--render-mode hybrid --mode structure` shows pixel-quality color fill with crisp text-glyph contours where the overlay fires; on a non-graphics terminal, `auto` degrades to `text` silently.

## §BandwidthGuard — protocol throttling

Graphics protocols send orders of magnitude more bytes than text. Guard:
- Track bytes-emitted-per-second; if it exceeds `--bandwidth-cap MB/s` (default 50), drop frames at the source rather than backing up the terminal.
- For Kitty: prefer delta uploads (only changed tiles) once supported; for Sixel/iTerm full uploads only.
- Show a one-time warning if cap is hit.

- **DoD:** on a deliberately slow terminal pipe, the cap engages and rendered fps drops without locking the terminal.

## §Hybrid — alignment guarantees

Pixel cells must align to text cells exactly. Two layers of care:
1. The composed pixel buffer is sized to `cols*cellPxW × rows*cellPxH` where `cellPxW/H` come from `TerminalCaps.xpixel/ypixel` if reported, otherwise from FreeType metrics of the bundled font.
2. Kitty graphics positioning (`X=c,Y=r`) places the image at cell coordinates; cursor moves for the overlay use the same coordinates.

Misalignment produces shimmering edges; visually noticeable, automatically tested.

- **DoD:** alignment golden: in hybrid mode, an overlay `|` glyph on a uniform-color region produces a vertical line whose pixels (after screen capture) align to within ±1 px of the cell column boundary.

## §Tests
- `kitty_graphics_tests.cpp` — escape syntax, chunk boundaries, base64 correctness.
- `sixel_tests.cpp` — palette quantization stability; encoder output round-trips via a sixel decoder.
- `iterm_inline_tests.cpp` — escape syntax; PNG payload round-trips.
- `render_mode_tests.cpp` — caps → mode resolution table.

## §Bench
- Bytes/frame for `pixel` (Kitty/Sixel/iTerm) vs `text` at the same content.
- Sustained fps for hybrid mode at 720p / 1080p; expected: lower than text-only because of the pixel upload, higher fidelity.

## §Files
New: `src/raster_compose.{hpp,cpp}`, `src/kitty_graphics.{hpp,cpp}`, `src/sixel.{hpp,cpp}`, `src/iterm_inline.{hpp,cpp}`, `src/render_mode.{hpp,cpp}`, `src/bandwidth_guard.{hpp,cpp}`.
Modified: `src/diff_emitter.cpp` (sparse-overlay mode), `src/cli.cpp` (`--render-mode`, `--bandwidth-cap`), `src/player.cpp` (mode dispatch), `CMakeLists.txt` (libsixel optional).
Optional dependency: `stb_image_write.h` vendored (header-only); `libsixel` via pkg-config (optional; `-DCONTOURTTY_SIXEL=ON`).

## Pitfalls
- Forgetting to clean up Kitty graphics IDs on exit → image fragments persist on the user's screen. RAII cleanup; quit handler emits delete-all-images escape.
- Sixel palette flicker between frames: lock the palette across frames or use ordered dithering at the same level as Phase F.
- iTerm doesn't support in-place updates the way Kitty does → every frame is a fresh image and the cursor moves; document the bandwidth and visual implications.
- Hybrid overlay where the structure glyph's foreground equals the underlying pixel color is invisible. Detect and skip those overlay cells (saves bandwidth) or force a contrasting fg in those cases.
- Some terminals report `kitty_graphics=true` for backwards-incompatible variants. Allowlist by `TERM_PROGRAM` + version where possible.
- Forgetting to emit a cursor-position reset between pixel upload and text overlay → the overlay lands somewhere else. Always re-position before the overlay block.
