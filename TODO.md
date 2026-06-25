# TODO.md — Structure-Based ASCII Terminal Media Renderer (C++)

> **Project:** `contourtty` — a native, compiled, terminal-resident, A/V-synced media player whose
> headline feature is **structure-based ASCII**: directional/shape-aware glyph selection driven by edge
> orientation, running live on video, webcam, streams, shaders, and 3D scenes.
> **Language:** C++20. **Decode:** FFmpeg/libav. **Audio:** miniaudio. **GPU:** Metal (Darwin) + Vulkan (portable).
> **Differentiator:** glyphs chosen by *shape*, not just brightness, in real time — extended in v2 with
> HoG/SDF features, Unicode 16 octant/sextant blitters, shader-in-terminal input, temporal coherence,
> and Kitty/Sixel/iTerm hybrid output.
>
> This file is the master checklist. Each phase has its own detailed document (`PHASE_A.md` … `PHASE_P.md`).
> Work top to bottom. Do **not** start a phase until the previous phase's "Phase exit criteria" are all checked.
>
> Every task below has a **DoD** (Definition of Done) — a concrete, testable condition. A task is not
> complete until its DoD is objectively true.

---

## How to read this file

- `[ ]` = not started, `[~]` = in progress, `[x]` = done (DoD met).
- Tasks are grouped by phase; phase docs contain the *how*, this file is the *what + done-when*.
- "Reference" points to the relevant section of a phase doc.
- Bench/perf numbers are recorded in `BENCHMARKS.md`.

---

## Phase overview

| Phase | Title | Goal | Doc | Milestone |
|---|---|---|---|---|
| A | Foundations & scaffolding | Build system, repo, terminal raw mode, clean teardown | `PHASE_A.md` | — |
| B | Decode & frame pipeline | FFmpeg decode → RGB frames → correct-aspect downscale | `PHASE_B.md` | — |
| C | Luminance renderer + emission | Brightness→glyph, truecolor, differential writes | `PHASE_C.md` | `v0.1` |
| D | Audio & sync | Audio playback, master clock, frame-skip to hold timing | `PHASE_D.md` | — |
| E | Structure mode (the differentiator) | Edge/shape-aware glyph selection, live | `PHASE_E.md` | `v0.5` |
| F | Inputs & modes | Webcam, streams, images/GIF, color tiers, dithering | `PHASE_F.md` | — |
| G | Performance, polish, release | GPU path, exports, packaging, docs | `PHASE_G.md` | — |
| H | Render-graph refactor | Typed DAG of Passes; CPU/GPU sibling dispatch | `PHASE_H.md` | — |
| I | Glyph science upgrade | FreeType + HoG + SDF + nanoflann + evolved charsets | `PHASE_I.md` | — |
| J | Blitter ladder & Unicode 16 | Octant/sextant blitters, capability detection, line ligatures | `PHASE_J.md` | — |
| K | Stylized NPR modes | ETF/CLD, Kuwahara, hatch, stipple, LIC, OKLab posterise | `PHASE_K.md` | — |
| L | Shader-in-terminal & procedural | Vulkan backend, GLSL/WGSL shader input, OBJ scene loader | `PHASE_L.md` | `v0.9` |
| M | Temporal coherence | Hysteresis, optical-flow warped history, supersampling | `PHASE_M.md` | — |
| N | Hybrid graphics protocols | Kitty / Sixel / iTerm pixel + text overlay | `PHASE_N.md` | `v0.95` |
| O | New content paths | Image grid, stdin data, asciinema re-stylise, captions | `PHASE_O.md` | — |
| P | Interactivity, demos, polish | OSD, A/B split, snapshot, README, packaging, launch | `PHASE_P.md` | `v1.0` |

**Milestone tags:** end of C = `v0.1` (plumbing proven). End of E = `v0.5` (the reason it exists). End of L = `v0.9` (shader-in-terminal, scenes). End of N = `v0.95` (hybrid graphics). End of P = `v1.0` (best-in-class, launchable).

---

## PHASE A — Foundations & scaffolding
*Doc: `PHASE_A.md`. Status: substantially done; CI/exit criteria remain blocked on GitHub Actions billing.*

- [ ] **A10. CI: build matrix.** DoD: GitHub Actions builds on Linux + macOS (Windows optional flag), fails on warnings; badge in README. Reference: PHASE_A §CI.
  - Blocked: account billing/spending-limit state on hosted runners; local builds pass.
- [ ] **Phase A exit criteria.** DoD: clean build on ≥2 OSes in CI; raw-mode guard provably restores on normal exit, Ctrl-C, and exception; size query + SIGWINCH working.
  - Local PTY proof complete (`scripts/verify_terminal_paths.sh`, `terminal_tests`); hosted CI proof blocked.

---

## PHASE B — Decode & frame pipeline
*Doc: `PHASE_B.md`. Status: complete (decode + sws_scale + threaded queue working; PTS handling validated).* No open items.

---

## PHASE C — Luminance renderer + emission → **v0.1**
*Doc: `PHASE_C.md`. Status: complete (luminance ramp + truecolor SGR + diff emitter shipped).* No open items.

---

## PHASE D — Audio & sync
*Doc: `PHASE_D.md`. Status: complete (miniaudio backend, audio clock master, frame-skip working).* No open items.

---

## PHASE E — Structure mode (the differentiator) → **v0.5**
*Doc: `PHASE_E.md`. Status: complete (Sobel + DoG + 9-region shape vectors + NCC matching; Metal backend on Darwin).* No open items remaining in this scope; richer features (HoG/SDF) move to PHASE_I.

---

## PHASE F — Inputs & modes
*Doc: `PHASE_F.md`. Status: complete (webcam, images, GIFs, FFmpeg streams, yt-dlp resolver, truecolor/256/16/mono, ordered + FS dither, halfblock, braille).* No open items.

---

## PHASE G — Performance, polish, release
*Doc: `PHASE_G.md`. Status: partial.*

- [x] **G4. Asciinema + raw ANSI export.** Shipped.
- [x] **G5. Config file + defaults.** Shipped (`$XDG_CONFIG_HOME/contourtty/config`).
- [~] **G6. Golden-frame regression tests.** DoD: tests run in CI and catch regressions for every mode. Reference: PHASE_G §Tests.
  - Local goldens exist for luminance, structure, halfblock, braille, blocks, octant, sextant, NPR styles, O-phase source adapters, and implemented graphics emitters. CI/release workflows now install explicit FreeType/zlib deps matching CMake. Open: hosted CI proof once billing unblocks.
- [~] **G7. Packaging.** DoD: a user on a fresh machine can install and run with documented steps. Reference: PHASE_G §Packaging.
  - CPack TGZ + Linux DEB + tag-driven release workflow + head-only Homebrew formula present locally. `scripts/package_release.sh` now preflights required commands/pkg-config deps and local macOS TGZ packaging passed with 62/62 tests. Open: hosted artifact build (Actions billing blocks); Homebrew versioned bottle; static-FFmpeg link for self-contained releases (moves into PHASE_P §Packaging).
- [x] **G8. Docs (README hero, contributing, man page, --help parity).** DoD: a newcomer can install, run, and understand the differentiator from the README alone. Reference: PHASE_G §Docs.
  - README now covers current install deps, first run, structure-vs-luminance differentiator, mode/style/render-mode knobs, new content paths, export/still/caption outputs, and graph inspection. CONTRIBUTING documents local build/test/package flow; `help_manpage_parity_tests` keeps `--help` and `docs/contourtty.1` in sync from `src/cli_spec.cpp`. P5 still owns the v1.0 split hero/demo refresh.
- [x] **G10. Publish honest benchmark numbers.** DoD: numbers reproducible from documented commands; linked from README. Reference: PHASE_G §Bench.
  - BENCHMARKS.md records host specs, fixture generation, reproducible commands, and local fps/bytes/frame rows for decode, luminance, structure, blitters, styles, temporal passes, stdin plots, and asciinema replay; README links it from "How structure mode works". The exhaustive v1.0 matrix remains P8.
- [ ] **Phase G exit criteria → tag `v1.0`.** Deferred — `v1.0` now gates on PHASE_P exit. PHASE_G exit is partial: full golden coverage, hosted release artifacts, final docs/demo refresh, final benchmark sweep, and hosted CI remain.

### Cross-cutting (from G)
- [~] **X1. Memory safety.** DoD: ASan + UBSan clean in CI on the decode+render path.
  - Local macOS ASan/UBSan clean; hosted Linux proof blocked by billing.
- [~] **X2. No leaks on shutdown.** DoD: Valgrind/ASan reports no leaks after normal exit, Ctrl-C, and seek.
  - macOS `leaks --atExit` clean on normal export, seek+quit, SIGINT (`scripts/verify_shutdown_paths.sh`). Hosted Linux Valgrind/ASan proof blocked.

---

## PHASE H — Render-graph refactor *(load-bearing for I–P)*
*Doc: `PHASE_H.md`. Status: complete (all current modes resolve to graphs; graph/golden tests cover byte-stable output and extension mechanics).* No open items.

---

## PHASE I — Glyph science upgrade
*Doc: `PHASE_I.md`. Goal: FreeType-driven glyph table, HoG features, SDF option, k-d tree lookup, evolved charsets.*

- [x] **I1. FreeType dynamic glyph table.** DoD: `--font PATH` produces visibly different glyph choices on a fixed frame; `GlyphFont` raster is the single source consumed by HoG, SDF, overlap, MP4 export, and Phase N `raster_compose`. Reference: PHASE_I §FreeType.
- [x] **Phase I exit criteria.** DoD: structure mode at 1080p is measurably sharper than v0.5 on the reference clip, at equal-or-better fps; glyph table rebuilds from any monospace font.
  - Local Release proof on a generated 12-frame 1920x1080 testsrc2 clip: legacy overlap baseline edge MSE 0.139187 at 29.268 fps; HoG + `lineart-40` + SFNSMono edge MSE 0.103041 at 40.000 fps. Edge NCC was worse (-0.029221 to -0.078364) and is recorded in `BENCHMARKS.md`. Menlo rebuild smoke loaded `/System/Library/Fonts/Menlo.ttc` and exported frames.

---

## PHASE J — Blitter ladder & Unicode 16
*Doc: `PHASE_J.md`. Status: complete (capability detection, auto ladder, blocks/octant/sextant/braille blitters, structure overlay, line ligatures, and blitter benchmarks).* No open items.

---

## PHASE K — Stylized NPR modes
*Doc: `PHASE_K.md`. Goal: painterly / hatch / stipple / flow styles.*

- [x] **K4. Blue-noise stippling.** DoD: `--style stipple` uses void-and-cluster blue noise tile; optional sub-cell precision via braille/octant carriers. Reference: PHASE_K §Stipple.
  - `--style stipple` ships with checked-in `share/contourtty/noise/blue_noise_64.bin`; `--mode braille` and `--mode octant` use source-frame 2x4 sub-cell dot carriers.
- [x] **K5. Line Integral Convolution.** DoD: `--style flow` ink strokes align with motion gradients; turns off cleanly. Reference: PHASE_K §Flow.
  - `--style flow` ships ETF-guided spatial LIC strokes with `--lic-length`; when temporal state is available it reuses optical flow and maps motion vectors into LIC stroke directions, with a gradient fallback on the first frame. `lic_tests` cover horizontal motion producing horizontal strokes; graph/runtime proof shows `optical-flow` feeding `lic`, and `--style none` has no LIC/flow passes.
- [x] **K6. OKLab posterise.** DoD: `--posterize N` quantises OKLab L (and optionally a/b) before any quantizer Pass; pairs naturally with hatch + stipple. Reference: PHASE_K §Posterize.
- [x] **K7. Style → Pass composition.** DoD: `--graph dump` for each `--style` shows the documented Pass insertion; `--style` is single-valued; multiple styles via `--graph file.yaml`. Reference: PHASE_K §StyleComposition.
- [x] **K8. NPR tests + bench.** DoD: per-style golden frames; 720p/1080p fps recorded per style, CPU vs GPU. Reference: PHASE_K §Tests / §Bench.
- [x] **Phase K exit criteria.** DoD: four named styles ship; each at ≥24 fps 720p truecolor on the reference machine; styles compose with all blitter modes.
  - BENCHMARKS.md records 720p truecolor style rows above 24 fps for painterly, hatch, stipple, and flow on the reference machine; `golden_frame_tests` smoke-render each style across luminance/structure/halfblock/blocks/octant/sextant/braille.

---

## PHASE L — Shader-in-terminal & procedural input → **v0.9**
*Doc: `PHASE_L.md`. Goal: Vulkan portable backend, GLSL/WGSL user shaders, OBJ scene loader.*

- [ ] **L1. Vulkan compute backend.** DoD: `src/gpu_vulkan/` ports Metal kernels (Sobel, DoG, cell-average, shape-match) to Vulkan 1.3; output matches macOS Metal reference within tolerance recorded in BENCHMARKS.md. Reference: PHASE_L §VulkanBackend.
  - Blocked locally: no Vulkan SDK/tools available (`vulkaninfo` absent, `pkg-config vulkan` absent).
- [ ] **L2. Shader cross-compile.** DoD: `glslang` + SPIRV-Cross vendored; GLSL → SPIR-V → MSL on Darwin, GLSL → SPIR-V on Linux/Windows; golden SPIR-V tests for fixed inputs. Reference: PHASE_L §ShaderInput / §VulkanBackend.
  - Blocked locally: `glslangValidator` and `spirv-cross` are absent.
- [ ] **L3. User shader source.** DoD: `--input shader.glsl` accepts a Shadertoy-style `mainImage()`; uniforms `iResolution/iTime/iTimeDelta/iFrame/iMouse/iChannel0..3` populated; hot-reload on file change. Reference: PHASE_L §ShaderInput.
  - Blocked by L2 shader compiler plumbing.
- [x] **L5. Depth/normal-aware glyphs.** DoD: `normal-orient` + `depth-shade` Passes use the G-buffer instead of screen-space gradients; rotated cube shows hatching along surface curvature. Reference: PHASE_L §NormalGlyphs.
  - `--style cell-shade` graph now includes `normal-orient` and `depth-shade` Passes over scene normal/depth buffers; scene playback passes the rendered G-buffer into `renderFrame`. Golden tests assert normal-driven orientation glyphs and depth-driven ramp darkening from synthetic G-buffer samples; a TTY cube run produced rendered scene frames with `render stats frames=1247 cells=598560`.
- [x] **L6. `--graph file.yaml` loader.** DoD: minimal in-tree YAML parser; example graph reproducing default `structure` pipeline byte-identical; documented examples in `share/contourtty/graphs/`. Reference: PHASE_L §GraphYaml.
- [ ] **L7. Bundled shaders.** DoD: `noise.glsl`, `plasma.glsl`, `feedback.glsl`, `sdf_room.glsl` ship under `share/contourtty/shaders/`; all compile clean on both backends; used as smoke tests. Reference: PHASE_L §Shaders.
- [ ] **L8. Shader/scene tests + bench.** DoD: `shader_compile_tests`, `vulkan_backend_tests`, `scene_source_tests` pass; cross-backend equivalence (Metal vs Vulkan Sobel within 1-LSB) verified; fps recorded per source. Reference: PHASE_L §Tests / §Bench.
- [ ] **Phase L exit criteria → tag `v0.9`.** DoD: `--input shader.glsl` runs on Vulkan or Metal at ≥30 fps 720p truecolor; `--input scene.obj` rotates an OBJ with depth+normal-aware glyphs; `--graph file.yaml` works as a power-user surface.

---

## PHASE M — Temporal coherence
*Doc: `PHASE_M.md`. Goal: kill ASCII shimmer.*

- [x] **M1. Glyph hysteresis.** DoD: `--glyph-stickiness eps` reduces per-cell glyph-change rate on near-static regions by ≥60% on a fixed pan clip; structure quality on real motion unchanged within tolerance; full-repaint paths clear history. Reference: PHASE_M §Hysteresis.
  - Score-returning glyph matcher, temporal glyph state, `--glyph-stickiness`, and `--orient-stickiness` shipped; unit flicker, orientation-bucket stickiness, fixed pan-clip compensated-flicker, decisive real-motion switch, and reset/resize tests pass.
- [x] **M2. Optical flow on working luminance.** DoD: `src/optical_flow.{hpp,cpp}` block-matching produces vec2 displacements per coarse block; correct on synthetic translations; ~0 on static frames. Reference: PHASE_M §Flow.
- [x] **M3. Flow-warped history.** DoD: `warp-history` Pass warps previous-frame glyph/shape-vector buffers by flow; pan-induced flicker drops below the §Hysteresis-only baseline. Reference: PHASE_M §Flow.
  - `optical-flow` + `warp-history` passes now motion-compensate previous glyphs and shape regions before hysteresis scoring, and glyph hysteresis keeps the warped previous glyph rather than the stale same-cell glyph. `warp_history_tests` covers glyph/shape-region warps plus a fixed pan-clip compensated-flicker metric below 40% of the hysteresis-only baseline.
- [x] **M4. Temporal supersampling.** DoD: `--temporal-supersample N` decodes at N× source fps when source <30 fps; emits at source fps; cleaner orientations recorded on cube clip at the cost of ~1.5× decode CPU. Reference: PHASE_M §Supersample.
  - `--temporal-supersample N` parses, is documented in help/man/README, gates off at source fps >=30, and uses one-frame lookahead to blend the next decoded frame into low-fps structure analysis without changing emitted frame count. Tests cover parse bounds, lookahead stats, and decoder fps reporting. BENCHMARKS.md records N=1 vs N=2 Release rows: 12 emitted frames in both cases, 11 analysis-only blends for N=2, and 1.39x baseline user CPU on the 12 fps fixture.
- [x] **M6. Seek/resize history clear.** DoD: seeking forward then back, or resizing, doesn't carry ghost glyph choices. Reference: PHASE_M §Seek.
  - Playback seek, loop restart, split seam moves, live render-option changes, and resize reset glyph hysteresis state alongside the diff emitter and graphics bandwidth guard. `hysteresis_tests` now asserts explicit reset clears prior glyph choices. PTY proof: generated a 160x90@12, 12s clip, scripted seek forward, seek back, and PTY resize under `--glyph-stickiness 0.05`; log recorded `seek reset render state target_us=5000000`, `resize reset render state terminal=100x30`, and `seek reset render state target_us=0`, with transcript full clears after reset points.
- [x] **M7. Temporal tests + bench.** DoD: `optical_flow_tests`, `hysteresis_tests`, golden flicker metric below threshold for default stickiness; BENCHMARKS.md records per-Pass cost. Reference: PHASE_M §Tests / §Bench.
  - `optical_flow_tests`, `hysteresis_tests`, `warp_history_tests`, graph goldens, and BENCHMARKS temporal pass cost rows are in place. `hysteresis_tests` includes a deterministic alternating-glyph flicker metric below 40% of the unstuck baseline; `warp_history_tests` includes a pan-clip compensated-flicker metric below 40% of the hysteresis-only baseline. `golden_frame_tests` covers temporal supersample stats and BENCHMARKS.md records N=1/N=2 cost rows.
- [x] **Phase M exit criteria.** DoD: per-cell glyph-change rate on the pan-clip baseline drops by ≥60%; A/V drift unchanged within ±2 ms; no fidelity regression on real motion.
  - `hysteresis_tests` keeps the deterministic flicker metric below 40% of unstuck baseline; `warp_history_tests` keeps pan-clip compensated mismatch below 40% of hysteresis-only baseline. Release A/V playback proof on a 2s 12 fps clip with AAC: `--glyph-stickiness 0` and `--glyph-stickiness 0.05` both logged avg drift 3333us, max drift 6667us, 24 rendered frames, and 0 drops.

---

## PHASE N — Hybrid graphics protocols → **v0.95**
*Doc: `PHASE_N.md`. Goal: Kitty/Sixel/iTerm pixel + text overlay.*

- [~] **N1. `raster_compose` pixel buffer.** DoD: per-frame composed pixel buffer matches terminal output visually (modulo font); shared with Phase G3 MP4 export and Phase P3 still snapshot. Reference: PHASE_N §RasterCompose.
  - `src/raster_compose.{hpp,cpp}` now owns the cell-to-RGB raster path; MP4 export, pixel-mode export/playback, `graphics_emitter`, and `--still` consume it. Open: visual terminal-vs-raster proof.
- [ ] **N3. Sixel encoder.** DoD: still image renders via Sixel on xterm-sixel/foot/wezterm; bandwidth caveat documented; pre-quantised to OKLab palette. Reference: PHASE_N §Sixel.
  - In-tree Sixel encoder, OKLab nearest xterm-256 palette quantization, graphics-emitter dispatch, forced Sixel export proof, docs caveat, and `sixel_tests` landed. Open: live xterm-sixel/foot/wezterm proof; no Sixel terminal/decoder tooling is installed locally.
- [~] **N4. iTerm inline image.** DoD: `--still` over iTerm produces in-place image; per-frame motion supported with documented caveats. Reference: PHASE_N §ITermInline.
  - iTerm OSC 1337 inline PNG encoder is tested and reuses the in-tree PNG encoder; pixel-mode export/playback can emit cell-raster iTerm frames; `--still` writes raster PNG snapshots. Open: live iTerm proof.
- [x] **N5. `--render-mode {text|pixel|hybrid|auto}`.** DoD: caps → mode resolution table tested; `auto` degrades to `text` silently when graphics unsupported; hybrid mode composes pixel layer + sparse text overlay. Reference: PHASE_N §RenderMode.
  - CLI parsing existed; `render_mode_tests` covers caps-to-mode/protocol resolution and graphics-to-text degradation; pixel-mode export/playback dispatch is wired for implemented protocols; `hybrid_emitter_tests` cover pixel layer plus sparse foreground-only text overlay; `render_mode_live_smoke` proves PTY playback auto-degrades to text without graphics caps and dispatches hybrid over forced Kitty caps.
- [x] **N6. Bandwidth guard.** DoD: `--bandwidth-cap MB/s` (default 50) drops frames at the source when exceeded; one-time warning; tested against a deliberately slow pipe. Reference: PHASE_N §BandwidthGuard.
  - `--bandwidth-cap` parses with default 50 MB/s; `bandwidth_guard_tests` covers rolling-window drops and one-time warning state; graphics export/playback use the guard; forced Kitty export with a tiny cap drops graphics payloads and logs exactly one warning.
- [~] **N7. Hybrid pixel/text alignment.** DoD: vertical overlay `|` on uniform region produces a line aligned to within ±1 px of the cell-column boundary in screen captures. Reference: PHASE_N §Hybrid.
  - `graphics_alignment_tests` lock raster-to-cell boundary math and ±1 px tolerance checks. Open: live hybrid screen-capture proof after player dispatch exists.
- [ ] **Phase N exit criteria → tag `v0.95`.** DoD: `pixel` mode on Kitty runs at full source resolution; `hybrid` shows contour sharpness vs pixel-only; `text` default unchanged.

---

## PHASE O — New content paths
*Doc: `PHASE_O.md`. Goal: image grids, stdin data, asciinema in, scene polish, captions.*

- [x] **O1. Image grid / contact sheet.** DoD: `--input "*.png" --grid 4x3` renders a fitted grid; resize reflows; per-tile fps independent for GIF tiles. Reference: PHASE_O §ImageGrid.
  - `--grid CxR` parses; `image_grid_tests` cover in-process glob expansion, tile-slot layout, and fitted contact-sheet frame composition; grid inputs load sorted frames from GIF tiles and route through playback, ANSI/cast/MP4 export, and PNG still snapshots with resize reflow; proof used two GIF tiles with 0.5s and 0.25s frame delays, distinct `--still-at` hashes, and cast events at 0.25s/0.5s/0.75s.
- [x] **O2. Stdin data plots.** DoD: `seq 1 1000 | awk '{print sin($1/10)}' | contourtty --input stdin --plot waveform` renders a smooth sine; `spectrum` runs a small in-tree FFT; `heatmap` slides a 2D window. Reference: PHASE_O §StdinData.
  - `--plot`, `--plot-window`, and `--plot-rate` parse; `stdin_data_tests` cover numeric parsing, in-tree FFT magnitudes, waveform/spectrum/heatmap plot rasterisation, and plot-raster frame conversion; `--input stdin` token-streams numeric samples through plot frames at `--plot-rate`, with output verified before producer EOF.
- [x] **O3. Asciinema re-stylise.** DoD: `--input recording.cast` replays through the render graph at original pacing; minimal VTE-lite handles SGR + cursor + scroll + clear; structure mode on a `htop` cast yields a stylised but readable version. Reference: PHASE_O §Asciinema.
  - `asciinema_in_tests` cover v2 header and event-line parsing; `asciinema_vte_tests` cover VTE-lite SGR, cursor, scroll, and clear handling; `asciinema_source_tests` cover output-event frames with original event timestamps; `.cast` playback routes those frames through `renderFrame` pacing; an actual bounded `htop` cast replays in structure mode under PTY with 17 rendered frames and dense structure-glyph transcript output.
- [x] **O5. Multi-source overlay.** DoD: `--input video.mp4 --overlay scene.obj` composes scene over video with depth-threshold alpha. Reference: PHASE_O §Pipeline.
  - `--overlay PATH|SOURCE`, `--overlay-alpha`, and `--overlay-depth-threshold` parse; `overlay_compose_tests` cover depth-threshold alpha blending against scene G-buffer depth; video playback/export/still routes scene overlays through composition before `renderFrame`; local still proof differs from base and visibly shows the scene overlay.
- [x] **O6. Caption sidecar.** DoD: `--captions out.srt` writes a deterministic, time-aligned SubRip summary track; covered by golden test. Reference: PHASE_O §Captions.
  - `--captions FILE.srt` parses; export and caption-only runs write deterministic frame-summary SRT cues from source PTS or `--fps`; `caption_summarise_tests` cover deterministic summaries, SRT formatting, and a literal two-cue SRT golden.
- [x] **O7. Content-path tests + bench.** DoD: `image_grid_tests`, `stdin_data_tests`, `asciinema_in_tests`, `caption_summarise_tests` all pass; stdin plot fps and asciinema replay overhead in BENCHMARKS.md. Reference: PHASE_O §Tests / §Bench.
  - `image_grid_tests`, `stdin_data_tests`, `asciinema_in_tests`, and `caption_summarise_tests` pass locally; BENCHMARKS.md records stdin waveform plot fps and asciinema replay overhead from Release runs.
---

## PHASE P — Interactivity, demos, polish → **v1.0**
*Doc: `PHASE_P.md`. Goal: OSD, split, snapshot, README, packaging, launch.*

- [x] **P1. OSD + live tuning.** DoD: `i`/`o` toggles bottom-row OSD; keys cycle `--style`, `--mode`, `--charset`, `--glyph-features`, `--gpu`; numeric keys bump `--edge-threshold`, `--dog-sigma`, `--contrast`; changes take effect within one frame; OSD never bleeds into diff'd content. Reference: PHASE_P §OSD.
  - Normal media playback now keeps a mutable live render option set. `i`/`o` toggles a two-row OSD outside the diff-emitted render area; `s/m/c/f/g` cycle or toggle style, mode, charset, glyph features, and GPU; `1/2`, `3/4`, and `5/6` adjust edge threshold, DoG sigma, and contrast. Each live change rebuilds ramp/shape state when needed, clears temporal/diff state, and applies on the next rendered frame. PTY proof: generated 160x90@12 clip, scripted `osmcfg246q` after alternate-screen entry, log recorded every live change, and transcript ended with `OSD m=halfblock s=painterly c=standard f=hog gpu=on e=0.40 dog=0.10 ctr=0.10` on rows 23-24 while render cells stayed in rows 6-16.
- [x] **P2. A/B split view.** DoD: `--split luminance:structure` runs two graphs side-by-side off a single decoded source; draggable seam; the split mode is the README hero. Reference: PHASE_P §Split.
  - CLI/runtime split support is in: `--split luminance:structure` renders left/right branches from the same decoded frame into separate cell buffers, composes them around a `┃` seam, and left/right arrows move the seam in split playback instead of seeking. `--graph a.yaml,b.yaml` is reserved for split graph pairs. PTY proof: generated 160x90@12 clip, scripted right/left arrows after alternate-screen entry, log recorded `split enabled left=luminance right=structure`, `split seam col=42`, then `split seam col=40`, and transcript contained seam glyphs at the expected columns. README now uses `docs/v1.0-split-demo.gif` as the hero.
- [x] **P3. Still snapshot.** DoD: `--still hero.png` (and `--still-at HH:MM:SS`) writes a PNG visually matching the live frame; reuses Phase I FreeType + Phase N `raster_compose`. Reference: PHASE_P §Still.
  - `--still FILE.png` and `--still-at HH:MM:SS[.ffffff]` parse; still snapshots render through `renderFrame` + `raster_compose` + `png_writer`; `VideoDecoder::seekToUs` now advances past backward keyframe seeks to the requested-or-later frame, shared by live seek and still snapshots. Proof: generated 160x90@10 test clip with `/System/Library/Fonts/SFNSMono.ttf`, `--still-at 00:00:00.300000` changed the PNG hash from the 0s snapshot, still/export dimensions matched at 320x132, and still-vs-lossy-MP4 first-frame PSNR was 36.78 dB.
- [x] **P4. `--help` ↔ man page parity.** DoD: every CLI flag from H–O appears in both `--help` and `docs/contourtty.1`; both generated from a single declarative source; parity test gates the build. Reference: PHASE_P §HelpAndMan.
  - `src/cli_spec.cpp` owns the declarative CLI help registry; `helpText()` renders from it, `scripts/generate_manpage.sh` consumes `contourtty --help`, and `help_manpage_parity_tests` checks help/man page parity in both directions.
- [x] **P5. README + docs refresh.** DoD: hero GIF is the v2 split demo; "How structure mode works" diagram updated for the render graph; "What's new in v1.0" callout; one-line install per platform. Reference: PHASE_P §README.
  - README now uses `docs/v1.0-split-demo.gif`, includes a v1.0-track callout with pending items named honestly, documents `--temporal-supersample`, updates the structure pipeline diagram, and adds one-line source install commands for macOS and Debian/Ubuntu. `docs/demo-source.md` records the generated split demo and bundled cube scene demo provenance.
- [ ] **P6. Pull the CI trigger.** DoD: once billing unblocks: green badge on main; ASan+UBSan+Valgrind on Linux; cross-backend Metal/Vulkan equivalence test; tagged releases build signed binaries + .deb + Homebrew bottle. Reference: PHASE_P §CI.
  - CI/release dependency installs now include explicit FreeType/zlib dependencies, matching current CMake. Open: hosted runner proof, Linux sanitizer/Valgrind proof, and future Metal/Vulkan equivalence once Vulkan exists.
- [~] **P7. Finish packaging.** DoD: `brew install contourtty` on fresh macOS; `apt install ./contourtty_*.deb` on Ubuntu; GitHub Releases binaries run on clean machines with documented FFmpeg dependency; static-FFmpeg link offered for self-contained builds. Reference: PHASE_P §Packaging.
  - Package preflight checks for CMake/CPack/pkg-config and required FFmpeg/FreeType packages landed; local macOS TGZ package build and packaged binary smoke passed. Ubuntu 24.04 Docker proof built with GCC `-Werror`, generated a CPack `.deb`, installed it with `apt-get install`, ran `contourtty --version`, and checked dynamic links with `ldd`. README now states packages still link system FFmpeg/FreeType/zlib. Open: hosted releases, versioned Homebrew bottle, and static-FFmpeg release option.
- [ ] **P8. Benchmarks final sweep.** DoD: BENCHMARKS.md rows for every mode (luminance / structure-HoG / structure-SDF / octant / sextant / halfblock / braille / blocks / hatch / stipple / painterly / flow / pixel-Kitty) × 720p/1080p × CPU/GPU, with reproducible commands and ±10% repeatability. Reference: PHASE_P §Bench.
- [~] **P9. Demo assets.** DoD: `docs/v1.0-split-demo.gif`, `docs/v1.0-shader-demo.gif`, `docs/v1.0-scene-demo.gif` all in repo and linked from README. Reference: PHASE_P §Demo.
  - `docs/v1.0-split-demo.gif` and `docs/v1.0-scene-demo.gif` are generated and documented. `writeStillSnapshot` now supports scene inputs so the scene demo uses the real cell-shade render path. Open: `docs/v1.0-shader-demo.gif`, blocked until shader input exists.
- [x] **P10. Golden coverage for everything new.** DoD: every new style/mode/source/render-mode has at least one golden frame test; capability matrix parameterized test; OSD-driven render test via `--input-keys`. Reference: PHASE_P §Tests.
  - `--input-keys TEXT` queues literal playback key bytes for automated PTY flows; `input_keys_smoke` drives OSD/style/mode/knob changes on a generated clip and asserts live-change logs. `render_mode_tests` runs a request x capability matrix for text/auto/pixel/hybrid over no-graphics/Kitty/Sixel/iTerm. `golden_frame_tests` covers new modes/styles and O-phase source adapters; `graphics_emitter_tests` locks Kitty/iTerm render-mode payload bytes; `render_mode_live_smoke` proves PTY auto-degrade and hybrid dispatch.
- [ ] **Phase P exit criteria → tag `v1.0`.** DoD: OSD + split + snapshot ship; README is launch-quality; releases on GitHub + Homebrew + .deb; honest benchmarks published; CI green.

---

## Cross-cutting / always-on tasks

- [~] **X1. Memory safety.** Local clean; hosted Linux ASan/UBSan blocked by billing (carried into PHASE_P §CI).
- [~] **X2. No leaks on shutdown.** Local macOS clean across normal/seek/Ctrl-C; hosted Linux Valgrind blocked.
- [x] **X3. Dependency hygiene.** DoD: `DEPENDENCIES.md` lists every system + vendored library with minimum versions and license posture; updated as Phases I/L/N add FreeType / glslang / Vulkan / graphics protocols / nanoflann / stb_image_write.
  - `DEPENDENCIES.md` covers build tools, FFmpeg, zlib, FreeType, miniaudio, Apple frameworks, nanoflann, Metal, future Vulkan/glslang/SPIRV-Cross, graphics protocols, shipped assets, install prerequisites, and optional yt-dlp. Homebrew formula includes the required FFmpeg/FreeType/zlib deps.
  - `DEPENDENCIES.md` now lists current system/vendored libraries, license posture, platform frameworks, protocol-only encoders, planned blocked Vulkan/glslang/SPIRV-Cross deps, and shipped data assets. Open: finalize after Vulkan/shader deps are actually added.
- [x] **X4. Build size budget.** DoD: `-DCONTOURTTY_LIGHT=ON` builds a minimal binary (no shader cross-compile, no Vulkan, no external graphics-protocol libraries) for users who want a small install; default build documents its size impact.
  - `CONTOURTTY_LIGHT` configures a CPU-only build that skips optional Apple Metal linkage; `build/light/contourtty` built locally and omits Metal/Foundation in `otool -L`. `DEPENDENCIES.md` records the local Release size delta: 1,496,856 bytes default vs 1,460,120 bytes light.
- [x] **X5. Licence audit on shipped charsets/fonts/noise tiles.** DoD: every binary asset in `share/contourtty/` is documented with origin + licence in `share/contourtty/LICENSES.md`.
  - `share/contourtty/LICENSES.md` lists current charsets, graph presets, blue-noise tile, and bundled OBJ scene; it records that no fonts, shader files, or third-party binary assets are currently shipped there.
- [x] **X6. Web embed surface.** DoD: JS-enabled sites can embed exported contourtty `.cast`/`.ansi` output as a package, element, or React component; static Markdown fallback is documented.
  - `packages/contourtty-embed` contains unpublished package `@contourtty/embed` with a Web Component, parser/render helpers, React wrapper, TypeScript declarations, package README, and Node/browser smoke tests. Root README documents static Markdown media embeds vs JS-enabled component embeds.

---

## Reference materials (study before/while building)

- **Decode:** dranger ffmpeg tutorial; leandromoreira/ffmpeg-libav-tutorial; FFmpeg send/receive API doxygen. Use `avcodec_send_packet`/`avcodec_receive_frame`, not `avcodec_decode_video2`.
- **Terminal color:** termstandard/colors; ANSI escape code (Wikipedia); "Terminal Colors Demystified"; OKLab — Raph Levien critique; `prettypretty` (OKLab in terminal palettes).
- **Structure ASCII (the core technique):** Alex Harri, "ASCII characters are not pixels"; Acerola's ASCII shader (Sobel/DoG + directional glyphs); academic: Chung 2022 (HoG/NCC glyph matching); Dalal & Triggs (HoG); SDF text — Metal by Example, libGDX.
- **Stylised NPR:** Coherent Line Drawing; anisotropic Kuwahara; void-and-cluster blue noise; Line Integral Convolution.
- **Terminal capability:** Unicode 16 Symbols for Legacy Computing (octants, sextants); notcurses blitter ladder; chafa symbol picker; Kitty graphics protocol; Sixel; iTerm2 inline image; Tattoy text compositor (Shadertoy-in-terminal).
- **Reference tools to study (not copy):** `timg`, `chafa`, `notcurses`, `viu`, `mpv --vo=kitty`, `tattoy`.
- **Aspect ratio:** terminal cells ≈ 1:2 (w:h); expose a correction knob; circle test is the canary.

---

## Naming

Project name: `contourtty`. Saturated names rejected (timg / tplay / chafa / ascii-video-player). Alternatives rejected for collisions (`strok`, `glyph`, `hatch`, `glyphstream`, `etch`, `inkterm`). The repo directory is still `strok/` for historical reasons; binary is `contourtty`.
