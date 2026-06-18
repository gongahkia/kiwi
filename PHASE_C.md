# PHASE_C.md — Luminance Renderer + Emission (→ v0.1)

**Goal:** The complete live pipeline with the baseline brightness→glyph renderer, truecolor output, and — critically — the **differential emitter** that makes high framerates possible. At the end of this phase you can watch a video play in the terminal.

**Exit criteria → tag `v0.1`:** a stranger can build and run `<file>` and watch a video play as truecolor ASCII, correctly scaled, at a documented framerate, quitting cleanly.

---

## §Luminance
Per cell, average its sample block (from Phase B working resolution) to an RGB, then compute relative luminance:

```
linearize each channel (sRGB -> linear), then
Y = 0.2126*R_lin + 0.7152*G_lin + 0.0722*B_lin
```

For speed you may use the gamma-encoded approximation `Y ≈ 0.299R + 0.587G + 0.114B` on 0–255 values, but document the choice; the linear version looks better in ramps. Unit-test against known colors (pure white → 1.0, pure black → 0.0, mid-gray → ~0.5 in gamma space).

## §Ramp
- Default density ramp (dark→light): `" .:-=+*#%@"` (10 levels). Provide longer ramps as presets in Phase F.
- Map: `index = clamp(round(Y * (N-1)), 0, N-1)`; glyph = `ramp[index]`.
- `--charset` replaces the ramp; reject empty.
- Note: ramp ordering by *perceived density* matters; the default above is a reasonable start but the exact glyph density depends on the font. Document that it's tunable.

## §CellBuffer
```cpp
struct RGB { uint8_t r,g,b; };
struct Cell { char32_t glyph; RGB fg; RGB bg; };
struct CellBuffer {
    int cols, rows;
    std::vector<Cell> cells;     // size cols*rows, reused every frame
};
```
- Allocated once at the working size; resized only on terminal resize. No per-frame allocation.

## §SGR — truecolor emission
- Foreground: `ESC [ 38;2;r;g;b m` → `"\x1b[38;2;%d;%d;%dm"`.
- Background: `ESC [ 48;2;r;g;b m` → `"\x1b[48;2;%d;%d;%dm"`.
- Reset: `ESC [ 0 m`.
- Cursor move to (row,col), 1-based: `ESC [ row ; col H`.
- Build sequences into a reusable `std::string`/byte buffer; never `printf` per cell.

## §Diff — the differential frame emitter (the framerate enabler)

Re-emitting the entire screen every frame caps FPS and causes flicker. Instead:

1. Keep `prev` CellBuffer (previous frame's contents).
2. For each row, scan left to right. Maintain "current cursor position" and "current SGR color state" (last fg/bg emitted).
3. For runs of cells that differ from `prev`:
   - If the cursor isn't already at the run's start, emit a cursor-move.
   - For each cell in the run: if its fg differs from current SGR fg, emit the fg SGR; same for bg; then emit the glyph (UTF-8 encoded). Update current SGR state.
4. Skip unchanged runs entirely (no output, just advance the logical cursor — actually you must move the cursor when you next emit, so track that you "lost" cursor continuity across a skipped run).
5. Accumulate everything into ONE buffer; `write()` it in a single syscall; flush.
6. Swap `prev` and current.

**Why each piece matters:** cursor-positioning lets you skip static regions; SGR-state tracking avoids re-emitting identical color codes (color codes are the bulk of truecolor bytes); single buffered write avoids tearing and syscall overhead.

**Measurement:** instrument bytes-emitted-per-frame. A near-static scene should emit dramatically fewer bytes than a full repaint. Record in BENCHMARKS.md.

**Edge cases:** first frame is a full paint; after a resize, force a full repaint and clear (`ESC [ 2 J`).

## §Mono
- `--mono`: emit glyphs only, no SGR color; works on 8-color/limited terminals. Glyph still chosen by luminance.

## §Loop — live playback loop (no audio yet)
```
init terminal, decode thread, sizing
loop until quit:
  if resized: re-query size, recompute grid, recreate sws ctx, force full repaint
  pop next Frame from queue (or break at EOF)
  render Frame -> CellBuffer (luminance)
  diff-emit CellBuffer
  pace to source fps (see §Pacing)
  poll input: 'q' or Ctrl-C -> quit
restore terminal (RAII)
```
- Input polling: non-blocking read of stdin (raw mode); handle `q`, and let Ctrl-C path from Phase A work.

## §Pacing — wall-clock pacing (pre-audio)
- Compute per-frame deadline from source fps; `sleep_until(deadline)` (steady_clock). Don't busy-wait.
- If behind, skip the sleep (catch up); full frame-skip logic comes with audio in Phase D.
- **DoD:** measured playback duration ≈ source duration ±2%.

## §Bench
- Record sustained cols×rows×fps for 720p and 1080p, truecolor and mono; bytes/frame. This is the v0.1 perf baseline.

## §Demo
- Capture a short GIF of playback (asciinema → gif, or screen capture) into `docs/`; update README.

## Pitfalls
- Per-cell writes / per-cell printf → terminal-bound, slow, flickery. One buffered write per frame is mandatory.
- Re-emitting unchanged cells → wastes bandwidth, caps fps.
- Not resetting SGR state assumptions after a cursor jump → color bleed. Track state honestly; when in doubt re-emit color at run starts.
- UTF-8: glyphs beyond ASCII (blocks, braille later) must be UTF-8 encoded correctly.
- Forgetting full-repaint after resize → corrupted layout.
