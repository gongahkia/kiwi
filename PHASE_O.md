# PHASE_O.md — New Content Paths

**Goal:** Reuse the render graph for inputs it was not built for: image grids / contact sheets, stdin data streams, asciinema re-stylisation, and the scene loader from Phase L. Same Passes, same emitters, new sources.

**Exit criteria:** four new `--input` types all work end-to-end: `--input "dir/*.png" --grid 4x3`; `cat data.csv | contourtty --input stdin --plot waveform`; `--input recording.cast`; `--input scene.obj`. None of them break existing video/camera/stream playback.

---

## Architecture decisions locked in this phase

- **Every new content type is a `MediaSource`.** The interface from Phase L is the contract. No special-case branching in `player.cpp`.
- **Sources can be composed.** The image-grid source is implemented as N parallel image sources tiled into a single virtual frame; the data source is one source per channel; both reuse single-source code.
- **No new heavyweight dep.** stdin parsing, CSV ingest, asciinema parsing, OBJ parsing — all in-tree.

## §ImageGrid — directory + grid

New `src/sources/image_grid.{hpp,cpp}`:
- `--input "*.png"` expands the glob in-process (do not rely on shell).
- `--grid CxR` chooses tile dimensions; total cells `cols×rows` split into `C×R` panels.
- Each tile is rendered through the full render graph at its panel's pixel patch.
- For animated GIFs in a grid, each tile advances independently at its own fps.

- **DoD:** a contact sheet of 12 PNGs renders as a 4×3 grid that fits the terminal; resizing reflows.

## §StdinData — plot from a data stream

New `src/sources/stdin_data.{hpp,cpp}`:
- Read whitespace- or comma-separated numbers from stdin; maintain a rolling window of N samples.
- Render via a tiny in-tree plotter that produces a `LuminanceField`/`EdgeField` directly (sparing the front of the graph).
- `--plot {waveform|spectrum|heatmap}`:
  - `waveform`: line plot of the last N samples; uses Phase J's `--line-ligatures` for continuous lines.
  - `spectrum`: FFT-magnitude column chart; FFT implemented in-tree (cooley-tukey, small fixed sizes).
  - `heatmap`: 2D sliding-window heatmap; useful for log-prefix-counting visualisation.
- `--plot-window N` samples; `--plot-rate Hz` poll rate.

- **DoD:** `seq 1 1000 | awk '{print sin($1/10)}' | contourtty --input stdin --plot waveform` shows a smooth sine; rendering rate matches `--plot-rate`.

## §Asciinema — re-stylise a `.cast`

New `src/sources/asciinema_in.{hpp,cpp}`:
- Parse asciinema v2 JSON header + event lines.
- Implement a minimal VTE-like interpreter: just enough to maintain a virtual `CellBuffer` of the recorded session (handle SGR, cursor move, common CSI sequences, scroll, clear). UTF-8 in.
- Replay timestamps drive frame production; output is the current virtual CellBuffer per frame.
- The render graph then re-stylises it: feed it as input to structure mode, change colors via OKLab posterise, etc.

- **DoD:** an asciinema recording of `htop` replays through `--mode halfblock --color-mode 256` at the original pacing; structure mode on it produces a stylised but readable version.

## §SceneSource — completes Phase L4

Phase L introduces `--input scene.obj`. Phase O ships:
- A small library of bundled OBJs (Suzanne, a textured cube, a simple character) under `share/contourtty/scenes/`.
- Built-in camera presets: `--scene-camera turntable|orbit|fly`.
- `--scene-anim time=10s,fps=30,rotate=Y` simple animation knobs.

- **DoD:** `contourtty --input contourtty:scene:suzanne --style cell-shade` runs the bundled Suzanne with depth-shaded cross-hatching; no extra files needed.

## §Pipeline — multi-source composition

`--graph file.yaml` (Phase L5) already allows multiple inputs as `iChannel0..N`. Phase O exposes one common case as a CLI:
- `--input video.mp4 --overlay scene.obj` renders a scene over the video; alpha from depth threshold.

- **DoD:** spinning Suzanne overlaid on a webcam feed works.

## §Captions — sidecar caption track (for accessibility)

While we have the render graph and structural information, generate a sidecar caption stream:
- New Pass `caption-summarise`: every N seconds, emit a one-line natural-language summary of the dominant gradient orientations, motion direction, average luminance, dominant colour region.
- `--captions out.srt` writes a sidecar SubRip file aligned to playback time.
- Not screen-reader integration; just sidecar text for accessibility / archival.

- **DoD:** a 10-second clip produces a sensible SRT (`00:00:01,000 → 00:00:03,000  high-contrast circle bottom-left, panning right`).

## §Tests
- `image_grid_tests.cpp` — glob expansion, tile layout, per-tile fps independence.
- `stdin_data_tests.cpp` — parser, FFT sanity, plot kinds.
- `asciinema_in_tests.cpp` — event timing, SGR + cursor playback against known recordings.
- `caption_summarise_tests.cpp` — golden SRT for a fixed clip; deterministic.

## §Bench
- stdin plot fps; per-event latency.
- Asciinema replay overhead.
- Image-grid per-tile cost vs single-image cost (should be ~linear in tile count).

## §Files
New: `src/sources/image_grid.{hpp,cpp}`, `src/sources/stdin_data.{hpp,cpp}`, `src/sources/asciinema_in.{hpp,cpp}`, `src/captions.{hpp,cpp}`, `src/plot/{waveform,spectrum,heatmap}.{hpp,cpp}`, `share/contourtty/scenes/*.obj`.
Modified: `src/cli.cpp` (`--grid`, `--plot`, `--plot-window`, `--plot-rate`, `--captions`, `--overlay`), `src/media_input.cpp`.

## Pitfalls
- Glob expansion in-process gets messy on Windows; use C++17 filesystem and document.
- Asciinema VTE-lite is a tar-pit; cap supported sequences explicitly and skip unknowns. Don't try to be a real terminal emulator.
- Stdin plot mixes the read thread and the render thread; bounded queue + non-blocking read.
- FFT on a non-power-of-2 window → either pad or reject; document.
- Caption summariser is *deterministic*, not "AI". Use coarse heuristics; don't oversell.
