# TODO.md — Structure-Based ASCII Terminal Media Renderer (C++)

> **Project:** A native, compiled, terminal-resident, A/V-synced media player whose
> headline feature is **structure-based ASCII** — directional/shape-aware glyph
> selection driven by edge orientation — running live on video, webcam, and streams.
> **Language:** C++20. **Decode:** FFmpeg/libav. **Audio:** miniaudio (or SDL2).
> **Differentiator:** glyphs chosen by *shape*, not just brightness, in real time.
>
> This file is the master checklist. Each phase has its own detailed document
> (`PHASE_A.md` … `PHASE_G.md`). Work top to bottom. Do **not** start a phase
> until the previous phase's "Phase exit criteria" are all checked.
>
> Every task below has a **DoD** (Definition of Done) — a concrete, testable
> condition. A task is not complete until its DoD is objectively true.

---

## How to read this file

- `[ ]` = not started, `[~]` = in progress, `[x]` = done (DoD met).
- Tasks are grouped by phase; phase docs contain the *how*, this file is the *what + done-when*.
- "Reference" points to the relevant section of a phase doc.
- Bench/perf numbers are recorded in `BENCHMARKS.md` (create in Phase A).

---

## Phase overview

| Phase | Title | Goal | Doc |
|---|---|---|---|
| A | Foundations & scaffolding | Build system, repo, terminal raw mode, clean teardown | `PHASE_A.md` |
| B | Decode & frame pipeline | FFmpeg decode → RGB frames → correct-aspect downscale | `PHASE_B.md` |
| C | Luminance renderer + emission | Brightness→glyph, truecolor, differential writes | `PHASE_C.md` |
| D | Audio & sync | Audio playback, master clock, frame-skip to hold timing | `PHASE_D.md` |
| E | **Structure mode (the differentiator)** | Edge/shape-aware glyph selection, live | `PHASE_E.md` |
| F | Inputs & modes | Webcam, streams, images/GIF, color tiers, dithering | `PHASE_F.md` |
| G | Performance, polish, release | GPU path, exports, packaging, docs, launch | `PHASE_G.md` |

**Milestone tags:** end of C = `v0.1` (plumbing proven). End of E = `v0.5` (the reason it exists). End of G = `v1.0` (best-in-class, launchable).

---

## PHASE A — Foundations & scaffolding
*Doc: `PHASE_A.md`. Goal: a buildable, well-structured repo that opens the terminal, goes raw, restores cleanly, and has CI.*

- [ ] **A10. CI: build matrix.** DoD: GitHub Actions builds on Linux + macOS (Windows optional flag), fails on warnings; badge in README.
  - 2026-06-19: blocked by GitHub Actions billing/spending-limit state before any job steps start. Owner override: continue Phase B while A10/Phase A exit remain pending.
- [ ] **Phase A exit criteria.** DoD: clean build on ≥2 OSes in CI; raw-mode guard provably restores on normal exit, Ctrl-C, and exception; size query + SIGWINCH working.

---

## PHASE B — Decode & frame pipeline
*Doc: `PHASE_B.md`. Goal: turn any local file into a stream of RGB frames at the right grid resolution, using the modern send/receive libav API.*


---

## PHASE C — Luminance renderer + emission  → **v0.1**
*Doc: `PHASE_C.md`. Goal: the full live pipeline with the baseline brightness→glyph renderer, truecolor, and the differential emitter that makes high framerates possible.*

- [ ] **C4. Truecolor SGR emission.** DoD: emits `\e[38;2;r;g;bm` (fg) and `\e[48;2;r;g;bm` (bg) per the ANSI spec; a static image renders with correct colors in a truecolor terminal. Reference: PHASE_C §SGR.
- [ ] **C5. Differential frame emitter.** DoD: only changed cells are re-emitted; uses cursor positioning (`\e[row;colH`) to jump over unchanged runs; SGR color state tracked so color codes emit only on change; full frame built into one buffer and written with a single `write()`/flush per frame. Verified: a near-static scene emits far fewer bytes than a full repaint (measured). Reference: PHASE_C §Diff.
- [ ] **C6. Mono mode.** DoD: `--mono` ignores color, emits glyphs only; works on 8-color terminals. Reference: PHASE_C §Mono.
- [ ] **C7. Live playback loop (no audio yet).** DoD: a video plays start-to-finish in the terminal as luminance ASCII, auto-fit to terminal size, responding to resize; quit on `q`/Ctrl-C with clean restore. Reference: PHASE_C §Loop.
- [ ] **C8. Frame pacing (wall clock).** DoD: without audio, frames are paced to the source fps via a sleep-to-deadline scheme (not busy-wait); measured playback duration ≈ source duration ±2%. Reference: PHASE_C §Pacing.
- [ ] **C9. Perf pass + numbers.** DoD: sustained cols×rows×fps recorded for 720p and 1080p sources in truecolor and mono; bytes/frame recorded; documented in `BENCHMARKS.md`. Reference: PHASE_C §Bench.
- [ ] **C10. v0.1 demo asset.** DoD: a short screen-capture GIF of luminance playback committed to `docs/`; README updated. Reference: PHASE_C §Demo.
- [ ] **Phase C exit criteria → tag `v0.1`.** DoD: a stranger can `build && run <file>` and watch a video play as truecolor ASCII, correctly scaled, at a documented framerate, quitting cleanly. If this isn't true, do not proceed.

---

## PHASE D — Audio & sync
*Doc: `PHASE_D.md`. Goal: audio playback with the audio track as the master clock, and adaptive frame-skip so video tracks audio rather than drifting.*

- [ ] **D1. Audio backend chosen + integrated.** DoD: `DEPENDENCIES.md` records the choice (miniaudio recommended: header-only, cross-platform, no system deps; SDL2 as alternative); a sine wave plays through it from a smoke test. Reference: PHASE_D §Backend.
- [ ] **D2. Decode audio stream.** DoD: the audio stream is decoded (libav) and resampled (`swresample`) to the backend's required format/rate; verified by playing a clip's audio alone, no glitches. Reference: PHASE_D §AudioDecode.
- [ ] **D3. Master clock = audio playback position.** DoD: a query returns current audio playback time in microseconds, advancing in real time. Reference: PHASE_D §Clock.
- [ ] **D4. Video-to-audio sync.** DoD: the render loop selects the video frame whose PTS matches the audio clock; A/V drift stays under ~50 ms over a 3-minute clip (measured by logging |video_pts − audio_clock|). Reference: PHASE_D §Sync.
- [ ] **D5. Adaptive frame-skip.** DoD: when rendering can't keep up, frames are dropped to *hold* sync rather than fall behind; a `--max-fps`/decimation path exists; behavior documented (mirrors timg's frame-skip). Reference: PHASE_D §Skip.
- [ ] **D6. Pause / seek / quit controls.** DoD: space pauses (audio + video together), left/right seeks ±N seconds (audio + video stay synced after seek), `q` quits cleanly. Reference: PHASE_D §Controls.
- [ ] **D7. A/V sync bench.** DoD: measured drift and dropped-frame count recorded for 720p/1080p in `BENCHMARKS.md`. Reference: PHASE_D §Bench.
- [ ] **Phase D exit criteria.** DoD: video + audio play in sync to completion, survive pause/seek, hold sync under load via frame-skip.

---

## PHASE E — Structure mode (the differentiator)  → **v0.5**
*Doc: `PHASE_E.md`. Goal: the reason the project exists — glyphs chosen by shape/edge orientation, not just brightness, computed live. This is the headline.*

- [ ] **E1. Grayscale + luminance field per source region.** DoD: for each cell, the *full sub-region* of source pixels is available (not just center sample), enabling shape analysis. Reference: PHASE_E §Sampling.
- [ ] **E2. Sobel gradient pass.** DoD: per cell, compute Gx, Gy, magnitude `m=hypot(Gx,Gy)`, orientation `θ=atan2(Gy,Gx)`; unit-tested on synthetic edges (vertical edge → horizontal gradient, etc.). Reference: PHASE_E §Sobel.
- [ ] **E3. Difference-of-Gaussians line isolation.** DoD: an optional DoG pre-pass (tunable σ1, σ2, threshold) isolates clean line structure and suppresses noise; toggle + params exposed. Reference: PHASE_E §DoG.
- [ ] **E4. Directional glyph mapping (v1 of structure mode).** DoD: cells with `m > threshold` map orientation→glyph (`- _ | / \ +`); below threshold fall back to luminance ramp; produces visibly contour-following edges on a rotating-cube/test clip. Reference: PHASE_E §Directional.
- [ ] **E5. Glyph shape vectors (the high-fidelity path).** DoD: each candidate glyph is rendered (via a bundled monospace font + FreeType, or precomputed bitmaps) and quantified by region-overlap "shape vectors" (per Alex Harri's sampling-circle method); stored as feature vectors at startup. Reference: PHASE_E §ShapeVectors.
- [ ] **E6. Shape-based glyph matching.** DoD: per cell, build the cell's shape vector from its sub-region and pick the glyph with the best match (normalized cross-correlation / nearest vector); edges look sharp, not blurry, on the cube test (compare against E4 visually). Reference: PHASE_E §Matching.
- [ ] **E7. Cel-shading contrast pre-pass.** DoD: an optional contrast/posterize enhancement increases separation between regions before matching (per the reference technique), with a `--contrast` knob; improves 3D-scene legibility. Reference: PHASE_E §Contrast.
- [ ] **E8. Blend fill + edges.** DoD: luminance fill and structure edges are combined into a single coherent output (edges drawn over fill) with a tunable edge strength; documented. Reference: PHASE_E §Blend.
- [ ] **E9. Tunable knobs exposed.** DoD: `--edge-threshold`, `--dog-sigma`, `--contrast`, `--charset`, `--mode {luminance|structure}` all work and are documented in `--help` and README. Reference: PHASE_E §Knobs.
- [ ] **E10. Structure-mode perf bench.** DoD: structure vs luminance fps and per-cell matching cost recorded; identifies the hotspot for Phase G GPU work. Reference: PHASE_E §Bench.
- [ ] **E11. v0.5 demo asset.** DoD: a side-by-side GIF (luminance vs structure) on real footage committed; README leads with it. Reference: PHASE_E §Demo.
- [ ] **Phase E exit criteria → tag `v0.5`.** DoD: structure mode renders live video with contour-following, sharp-edged ASCII that is *visibly* better than luminance mode, at an interactive framerate, with tunable parameters.

---

## PHASE F — Inputs & modes
*Doc: `PHASE_F.md`. Goal: make it work on the inputs people actually want, and across terminal capability tiers.*

- [ ] **F1. Webcam input.** DoD: `--input cam` (or device path) shows live structure-ASCII of the webcam with acceptable latency; documented per-OS capture path. Reference: PHASE_F §Webcam.
- [ ] **F2. Image + GIF input.** DoD: a still image renders once and holds; an animated GIF loops at correct timing. Reference: PHASE_F §Images.
- [ ] **F3. Streaming URLs.** DoD: an HLS/RTSP URL plays; a YouTube URL plays via yt-dlp handoff; failures degrade with a clear message. Reference: PHASE_F §Streams.
- [ ] **F4. Terminal capability detection.** DoD: detects truecolor via `COLORTERM`=truecolor/24bit, 256 via `TERM` containing 256; respects `NO_COLOR`; falls back gracefully; `--color-mode {auto|truecolor|256|16|mono}` overrides. Reference: PHASE_F §Detect.
- [ ] **F5. 256-color + 16-color quantization.** DoD: truecolor is quantized to the 6×6×6 + grayscale 256 cube and to the 16-color palette, with dithering, for limited terminals; output is recognizable. Reference: PHASE_F §Quantize.
- [ ] **F6. Half-block 24-bit mode.** DoD: a `--mode halfblock` uses `▀`/`▄` with separate fg/bg colors to double vertical resolution (highest text-only fidelity); correct aspect. Reference: PHASE_F §HalfBlock.
- [ ] **F7. Dither algorithm choice.** DoD: `--dither {none|ordered|fs}`; ordered/Bayer runs on the per-cell path; Floyd–Steinberg implemented CPU-side with a documented note that it does not parallelize. Reference: PHASE_F §Dither.
- [ ] **F8. Custom + preset charsets.** DoD: several named presets (`blocks`, `detailed`, `binary`, `braille`) plus `--charset` custom string; braille mode uses 2×4 dot packing for high spatial resolution. Reference: PHASE_F §Charsets.
- [ ] **F9. Loop / fit / position flags.** DoD: `--loop`, `--width`, `--height`, `--fit`, centering all behave; live re-fit on resize OR a clean documented guard if live re-fit is deferred. Reference: PHASE_F §Layout.
- [ ] **Phase F exit criteria.** DoD: webcam, image, GIF, file, and at least one stream type all render; truecolor/256/16/mono/halfblock all produce correct output on appropriate terminals.

---

## PHASE G — Performance, polish, release  → **v1.0**
*Doc: `PHASE_G.md`. Goal: make it fast, packaged, documented, and launched.*

- [ ] **G1. SIMD / multithread the analysis pass.** DoD: Sobel/DoG/matching parallelized across cores (and/or SIMD); measured speedup recorded; correctness unchanged (golden-frame test). Reference: PHASE_G §CPU.
- [ ] **G2. Optional GPU compute path.** DoD: a compute-shader (Vulkan/OpenGL/compute via a chosen API) implementation of the analysis pass behind `--gpu`; falls back to CPU if unavailable; significant fps gain at high cell counts recorded. Reference: PHASE_G §GPU.
- [ ] **G3. Export: rendered MP4.** DoD: `--export out.mp4` writes a video of the ASCII output (offline render path) that plays in a normal player. Reference: PHASE_G §ExportMP4.
- [ ] **G4. Export: asciinema cast + raw ANSI.** DoD: `--export out.cast` produces a valid asciinema recording; `--export out.ansi` writes the raw escape stream replayable with `cat`. Reference: PHASE_G §ExportCast.
- [ ] **G5. Config file + sane defaults.** DoD: a config file (e.g. `~/.config/<name>/config`) sets defaults; CLI overrides it; no recompile needed for tuning. Reference: PHASE_G §Config.
- [ ] **G6. Golden-frame regression tests.** DoD: known inputs produce byte-identical (or perceptually-identical within tolerance) CellBuffers; CI runs them. Reference: PHASE_G §Tests.
- [ ] **G7. Packaging.** DoD: single static-ish binary releases for Linux/macOS (+ Windows if feasible); a Homebrew formula and/or `.deb`; documented `ffmpeg` runtime requirement. Reference: PHASE_G §Packaging.
- [ ] **G8. Documentation.** DoD: README with hero GIF, install, usage, all flags, the "how structure mode works" section, and a CONTRIBUTING guide; man page generated. Reference: PHASE_G §Docs.
- [ ] **G9. Technique writeup / launch.** DoD: a blog post or video explaining the structure-mode technique (the shareable artifact); links from README. Reference: PHASE_G §Launch.
- [ ] **G10. Honest benchmark publication.** DoD: `BENCHMARKS.md` finalized with machine specs and reproducible commands; linked from README. Reference: PHASE_G §Bench.
- [ ] **Phase G exit criteria → tag `v1.0`.** DoD: fast (GPU path or strong SIMD), packaged for ≥2 platforms, fully documented, with a published technique writeup and reproducible benchmarks.

---

## Cross-cutting / always-on tasks
- [ ] **X1. Memory safety.** DoD: ASan + UBSan clean in CI on the decode+render path.
- [ ] **X2. No leaks on shutdown.** DoD: Valgrind/ASan reports no leaks after normal exit, Ctrl-C, and seek.
- [ ] **X3. Terminal always restored.** DoD: there is no code path (panic, signal, error) that leaves the terminal in raw mode or alt screen.
- [ ] **X4. Bench after every perf-relevant change.** DoD: `BENCHMARKS.md` updated whenever the render/decode path changes materially.

---

## Reference materials (study before/while building)
- **Decode:** dranger ffmpeg tutorial; leandromoreira/ffmpeg-libav-tutorial; FFmpeg send/receive API doxygen. Use the modern `avcodec_send_packet`/`avcodec_receive_frame` API, **not** `avcodec_decode_video2`.
- **Terminal color:** termstandard/colors; ANSI escape code (Wikipedia); "Terminal Colors Demystified". Truecolor SGR: `\e[38;2;r;g;bm` / `\e[48;2;r;g;bm`. Detect via `COLORTERM`; respect `NO_COLOR`.
- **Structure ASCII (the core technique):** Alex Harri, "ASCII characters are not pixels" (shape vectors via sampling-circle overlap + cel-shading contrast). Acerola's ASCII shader (Sobel/DoG + directional glyphs). Academic: structure-based ASCII (HoG/NCC glyph matching).
- **Reference tools to study (not copy):** `timg` and `chafa` source for protocol detection, dithering, threading, frame-skip; `mpv` `--vo=kitty` for the fidelity ceiling.
- **Aspect ratio:** terminal cells ≈ 1:2 (w:h); expose a correction knob (timg does). Circle test is the canary.

## Naming
Avoid the saturated `ascii-video-player` / `timg` / `tplay` / `chafa` namespace. Structure-angle candidates: `glyph`, `glyphstream`, `etch`, `inkterm`, `hatch`, `strok`. Verify on GitHub + crates/Homebrew before committing (task A2).
