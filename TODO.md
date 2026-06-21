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
  - Local goldens exist for luminance, structure, halfblock, braille, blocks, octant, and sextant. Open: extend to every Phase I–O mode/style; gate CI on them once billing unblocks.
- [~] **G7. Packaging.** DoD: a user on a fresh machine can install and run with documented steps. Reference: PHASE_G §Packaging.
  - CPack TGZ + Linux DEB + tag-driven release workflow + head-only Homebrew formula present locally. Open: hosted artifact build (Actions billing blocks); Homebrew versioned bottle; static-FFmpeg link for self-contained releases (moves into PHASE_P §Packaging).
- [ ] **G8. Docs (README hero, contributing, man page, --help parity).** DoD: a newcomer can install, run, and understand the differentiator from the README alone. Reference: PHASE_G §Docs.
  - README + CONTRIBUTING + man page exist; v2 features will land their own README updates in Phase P. Open: refresh hero GIF after Phase P.
- [ ] **G10. Publish honest benchmark numbers.** DoD: numbers reproducible from documented commands; linked from README. Reference: PHASE_G §Bench.
  - BENCHMARKS.md scaffolded with current numbers. Open: full sweep across all modes/styles/backends in PHASE_P §Bench.
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
- [ ] **Phase I exit criteria.** DoD: structure mode at 1080p is measurably sharper than v0.5 on the reference clip, at equal-or-better fps; glyph table rebuilds from any monospace font.

---

## PHASE J — Blitter ladder & Unicode 16
*Doc: `PHASE_J.md`. Status: complete (capability detection, auto ladder, blocks/octant/sextant/braille blitters, structure overlay, line ligatures, and blitter benchmarks).* No open items.

---

## PHASE K — Stylized NPR modes
*Doc: `PHASE_K.md`. Goal: painterly / hatch / stipple / flow styles.*

- [~] **K4. Blue-noise stippling.** DoD: `--style stipple` uses void-and-cluster blue noise tile; optional sub-cell precision via braille/octant carriers. Reference: PHASE_K §Stipple.
  - `--style stipple` ships with a deterministic 64x64 rank tile and dot glyph pass. Open: replace generated hash-rank tile with checked-in void-and-cluster tile; add braille/octant sub-cell carriers.
- [~] **K5. Line Integral Convolution.** DoD: `--style flow` ink strokes align with motion gradients; turns off cleanly. Reference: PHASE_K §Flow.
  - `--style flow` ships ETF-guided spatial LIC strokes with `--lic-length`. Open: align with motion gradients after optical flow lands in Phase M.
- [x] **K6. OKLab posterise.** DoD: `--posterize N` quantises OKLab L (and optionally a/b) before any quantizer Pass; pairs naturally with hatch + stipple. Reference: PHASE_K §Posterize.
- [x] **K7. Style → Pass composition.** DoD: `--graph dump` for each `--style` shows the documented Pass insertion; `--style` is single-valued; multiple styles via `--graph file.yaml`. Reference: PHASE_K §StyleComposition.
- [x] **K8. NPR tests + bench.** DoD: per-style golden frames; 720p/1080p fps recorded per style, CPU vs GPU. Reference: PHASE_K §Tests / §Bench.
- [ ] **Phase K exit criteria.** DoD: four named styles ship; each at ≥24 fps 720p truecolor on the reference machine; styles compose with all blitter modes.

---

## PHASE L — Shader-in-terminal & procedural input → **v0.9**
*Doc: `PHASE_L.md`. Goal: Vulkan portable backend, GLSL/WGSL user shaders, OBJ scene loader.*

- [ ] **L1. Vulkan compute backend.** DoD: `src/gpu_vulkan/` ports Metal kernels (Sobel, DoG, cell-average, shape-match) to Vulkan 1.3; output matches macOS Metal reference within tolerance recorded in BENCHMARKS.md. Reference: PHASE_L §VulkanBackend.
  - Blocked locally: no Vulkan SDK/tools available (`vulkaninfo` absent, `pkg-config vulkan` absent).
- [ ] **L2. Shader cross-compile.** DoD: `glslang` + SPIRV-Cross vendored; GLSL → SPIR-V → MSL on Darwin, GLSL → SPIR-V on Linux/Windows; golden SPIR-V tests for fixed inputs. Reference: PHASE_L §ShaderInput / §VulkanBackend.
  - Blocked locally: `glslangValidator` and `spirv-cross` are absent.
- [ ] **L3. User shader source.** DoD: `--input shader.glsl` accepts a Shadertoy-style `mainImage()`; uniforms `iResolution/iTime/iTimeDelta/iFrame/iMouse/iChannel0..3` populated; hot-reload on file change. Reference: PHASE_L §ShaderInput.
  - Blocked by L2 shader compiler plumbing.
- [~] **L4. OBJ scene loader + tiny rasteriser.** DoD: `--input scene.obj` rotates Suzanne at 320×120 cells at ≥30 fps producing albedo + depth + normal G-buffers. Reference: PHASE_L §SceneInput.
  - OBJ parser plus CPU albedo/depth/normal G-buffer rasterizer landed. Open: wire `--input scene.obj`, bundled Suzanne, camera controls, and fps evidence.
- [ ] **L5. Depth/normal-aware glyphs.** DoD: `normal-orient` + `depth-shade` Passes use the G-buffer instead of screen-space gradients; rotated cube shows hatching along surface curvature. Reference: PHASE_L §NormalGlyphs.
- [x] **L6. `--graph file.yaml` loader.** DoD: minimal in-tree YAML parser; example graph reproducing default `structure` pipeline byte-identical; documented examples in `share/contourtty/graphs/`. Reference: PHASE_L §GraphYaml.
- [ ] **L7. Bundled shaders.** DoD: `noise.glsl`, `plasma.glsl`, `feedback.glsl`, `sdf_room.glsl` ship under `share/contourtty/shaders/`; all compile clean on both backends; used as smoke tests. Reference: PHASE_L §Shaders.
- [ ] **L8. Shader/scene tests + bench.** DoD: `shader_compile_tests`, `vulkan_backend_tests`, `scene_source_tests` pass; cross-backend equivalence (Metal vs Vulkan Sobel within 1-LSB) verified; fps recorded per source. Reference: PHASE_L §Tests / §Bench.
- [ ] **Phase L exit criteria → tag `v0.9`.** DoD: `--input shader.glsl` runs on Vulkan or Metal at ≥30 fps 720p truecolor; `--input scene.obj` rotates an OBJ with depth+normal-aware glyphs; `--graph file.yaml` works as a power-user surface.

---

## PHASE M — Temporal coherence
*Doc: `PHASE_M.md`. Goal: kill ASCII shimmer.*

- [~] **M1. Glyph hysteresis.** DoD: `--glyph-stickiness eps` reduces per-cell glyph-change rate on near-static regions by ≥60% on a fixed pan clip; structure quality on real motion unchanged within tolerance; full-repaint paths clear history. Reference: PHASE_M §Hysteresis.
  - Score-returning glyph matcher, temporal glyph state, and `--glyph-stickiness` shipped. Open: fixed pan-clip flicker metric, real-motion tolerance proof, orientation bucket stickiness.
- [x] **M2. Optical flow on working luminance.** DoD: `src/optical_flow.{hpp,cpp}` block-matching produces vec2 displacements per coarse block; correct on synthetic translations; ~0 on static frames. Reference: PHASE_M §Flow.
- [~] **M3. Flow-warped history.** DoD: `warp-history` Pass warps previous-frame glyph/shape-vector buffers by flow; pan-induced flicker drops below the §Hysteresis-only baseline. Reference: PHASE_M §Flow.
  - `optical-flow` + `warp-history` passes now motion-compensate previous glyphs before hysteresis scoring. Open: pan-clip flicker comparison against hysteresis-only baseline and shape-vector warping.
- [ ] **M4. Temporal supersampling.** DoD: `--temporal-supersample N` decodes at N× source fps when source <30 fps; emits at source fps; cleaner orientations recorded on cube clip at the cost of ~1.5× decode CPU. Reference: PHASE_M §Supersample.
- [~] **M5. OKLab Δ diff threshold.** DoD: `--diff-oklab-eps` filters sub-perceptual SGR re-emits; bytes-per-frame on the pan clip drops 20–40% vs v0.5 with visuals unchanged within tolerance. Reference: PHASE_M §EmitDeltaOklab.
  - `--diff-oklab-eps` suppresses subthreshold truecolor SGR re-emits against the last emitted state. Open: pan-clip byte/frame benchmark vs v0.5.
- [~] **M6. Seek/resize history clear.** DoD: seeking forward then back, or resizing, doesn't carry ghost glyph choices. Reference: PHASE_M §Seek.
  - Playback seek, loop restart, and resize reset glyph hysteresis state alongside the diff emitter. Open: interactive seek/resize regression proof.
- [~] **M7. Temporal tests + bench.** DoD: `optical_flow_tests`, `hysteresis_tests`, golden flicker metric below threshold for default stickiness; BENCHMARKS.md records per-Pass cost. Reference: PHASE_M §Tests / §Bench.
  - `optical_flow_tests`, `hysteresis_tests`, `warp_history_tests`, graph goldens, and BENCHMARKS temporal pass cost rows are in place. Open: golden flicker metric threshold and supersample cost row.
- [ ] **Phase M exit criteria.** DoD: per-cell glyph-change rate on the pan-clip baseline drops by ≥60%; A/V drift unchanged within ±2 ms; no fidelity regression on real motion.

---

## PHASE N — Hybrid graphics protocols → **v0.95**
*Doc: `PHASE_N.md`. Goal: Kitty/Sixel/iTerm pixel + text overlay.*

- [~] **N1. `raster_compose` pixel buffer.** DoD: per-frame composed pixel buffer matches terminal output visually (modulo font); shared with Phase G3 MP4 export and Phase P3 still snapshot. Reference: PHASE_N §RasterCompose.
  - `src/raster_compose.{hpp,cpp}` now owns the cell-to-RGB raster path and MP4 export consumes it. Open: still snapshot and graphics-protocol consumers.
- [~] **N2. Kitty graphics encoder.** DoD: 720p clip plays on Kitty/Ghostty/WezTerm via `--render-mode pixel`; resize and quit clean; persistent IDs reused for delta uploads. Reference: PHASE_N §KittyGraphics.
  - Direct RGB24 Kitty encoder, base64 chunking, placement ids, and delete escapes are tested. Open: playback integration, resize/quit cleanup, persistent delta uploads, live Kitty/Ghostty/WezTerm proof.
- [ ] **N3. Sixel encoder.** DoD: still image renders via Sixel on xterm-sixel/foot/wezterm; bandwidth caveat documented; pre-quantised to OKLab palette. Reference: PHASE_N §Sixel.
  - Blocked locally: `libsixel`, `img2sixel`, and `sixel2png` are absent.
- [~] **N4. iTerm inline image.** DoD: `--still` over iTerm produces in-place image; per-frame motion supported with documented caveats. Reference: PHASE_N §ITermInline.
  - iTerm OSC 1337 inline PNG encoder is tested and reuses the in-tree PNG encoder. Open: `--still` wiring and live iTerm proof.
- [~] **N5. `--render-mode {text|pixel|hybrid|auto}`.** DoD: caps → mode resolution table tested; `auto` degrades to `text` silently when graphics unsupported; hybrid mode composes pixel layer + sparse text overlay. Reference: PHASE_N §RenderMode.
  - CLI parsing existed; `render_mode_tests` now covers caps-to-mode/protocol resolution and graphics-to-text degradation. Open: player dispatch and hybrid sparse text overlay composition.
- [~] **N6. Bandwidth guard.** DoD: `--bandwidth-cap MB/s` (default 50) drops frames at the source when exceeded; one-time warning; tested against a deliberately slow pipe. Reference: PHASE_N §BandwidthGuard.
  - `--bandwidth-cap` parses with default 50 MB/s; `bandwidth_guard_tests` covers rolling-window drops and one-time warning state. Open: wire guard into graphics playback and slow-pipe proof.
- [~] **N7. Hybrid pixel/text alignment.** DoD: vertical overlay `|` on uniform region produces a line aligned to within ±1 px of the cell-column boundary in screen captures. Reference: PHASE_N §Hybrid.
  - `graphics_alignment_tests` lock raster-to-cell boundary math and ±1 px tolerance checks. Open: live hybrid screen-capture proof after player dispatch exists.
- [~] **N8. Graphics-protocol tests + bench.** DoD: `kitty_graphics_tests`, `sixel_tests`, `iterm_inline_tests`, `render_mode_tests` all pass; bytes/frame and fps recorded per protocol in BENCHMARKS.md. Reference: PHASE_N §Tests / §Bench.
  - `kitty_graphics_tests`, `iterm_inline_tests`, and `render_mode_tests` cover escape syntax, base64 payloads, chunk boundaries, delete escapes, inline PNG payloads, and caps-to-mode resolution. Open: Sixel tests plus bytes/frame and fps bench.
- [ ] **Phase N exit criteria → tag `v0.95`.** DoD: `pixel` mode on Kitty runs at full source resolution; `hybrid` shows contour sharpness vs pixel-only; `text` default unchanged.

---

## PHASE O — New content paths
*Doc: `PHASE_O.md`. Goal: image grids, stdin data, asciinema in, scene polish, captions.*

- [ ] **O1. Image grid / contact sheet.** DoD: `--input "*.png" --grid 4x3` renders a fitted grid; resize reflows; per-tile fps independent for GIF tiles. Reference: PHASE_O §ImageGrid.
- [ ] **O2. Stdin data plots.** DoD: `seq 1 1000 | awk '{print sin($1/10)}' | contourtty --input stdin --plot waveform` renders a smooth sine; `spectrum` runs a small in-tree FFT; `heatmap` slides a 2D window. Reference: PHASE_O §StdinData.
- [ ] **O3. Asciinema re-stylise.** DoD: `--input recording.cast` replays through the render graph at original pacing; minimal VTE-lite handles SGR + cursor + scroll + clear; structure mode on a `htop` cast yields a stylised but readable version. Reference: PHASE_O §Asciinema.
- [ ] **O4. Bundled scenes + camera presets.** DoD: `contourtty --input contourtty:scene:suzanne --style cell-shade` works with no extra files; `--scene-camera turntable|orbit|fly` selectable. Reference: PHASE_O §SceneSource.
- [ ] **O5. Multi-source overlay.** DoD: `--input video.mp4 --overlay scene.obj` composes scene over video with depth-threshold alpha. Reference: PHASE_O §Pipeline.
- [ ] **O6. Caption sidecar.** DoD: `--captions out.srt` writes a deterministic, time-aligned SubRip summary track; covered by golden test. Reference: PHASE_O §Captions.
- [ ] **O7. Content-path tests + bench.** DoD: `image_grid_tests`, `stdin_data_tests`, `asciinema_in_tests`, `caption_summarise_tests` all pass; stdin plot fps and asciinema replay overhead in BENCHMARKS.md. Reference: PHASE_O §Tests / §Bench.
- [ ] **Phase O exit criteria.** DoD: all four new `--input` types work end-to-end; no regression in video/camera/stream playback.

---

## PHASE P — Interactivity, demos, polish → **v1.0**
*Doc: `PHASE_P.md`. Goal: OSD, split, snapshot, README, packaging, launch.*

- [ ] **P1. OSD + live tuning.** DoD: `i`/`o` toggles bottom-row OSD; keys cycle `--style`, `--mode`, `--charset`, `--glyph-features`, `--gpu`; numeric keys bump `--edge-threshold`, `--dog-sigma`, `--contrast`; changes take effect within one frame; OSD never bleeds into diff'd content. Reference: PHASE_P §OSD.
- [ ] **P2. A/B split view.** DoD: `--split luminance:structure` runs two graphs side-by-side off a single decoded source; draggable seam; the split mode is the README hero. Reference: PHASE_P §Split.
- [ ] **P3. Still snapshot.** DoD: `--still hero.png` (and `--still-at HH:MM:SS`) writes a PNG visually matching the live frame; reuses Phase I FreeType + Phase N `raster_compose`. Reference: PHASE_P §Still.
- [ ] **P4. `--help` ↔ man page parity.** DoD: every CLI flag from H–O appears in both `--help` and `docs/contourtty.1`; both generated from a single declarative source; parity test gates the build. Reference: PHASE_P §HelpAndMan.
- [ ] **P5. README + docs refresh.** DoD: hero GIF is the v2 split demo; "How structure mode works" diagram updated for the render graph; "What's new in v1.0" callout; one-line install per platform. Reference: PHASE_P §README.
- [ ] **P6. Pull the CI trigger.** DoD: once billing unblocks: green badge on main; ASan+UBSan+Valgrind on Linux; cross-backend Metal/Vulkan equivalence test; tagged releases build signed binaries + .deb + Homebrew bottle. Reference: PHASE_P §CI.
- [ ] **P7. Finish packaging.** DoD: `brew install contourtty` on fresh macOS; `apt install ./contourtty_*.deb` on Ubuntu; GitHub Releases binaries run on clean machines with documented FFmpeg dependency; static-FFmpeg link offered for self-contained builds. Reference: PHASE_P §Packaging.
- [ ] **P8. Benchmarks final sweep.** DoD: BENCHMARKS.md rows for every mode (luminance / structure-HoG / structure-SDF / octant / sextant / halfblock / braille / blocks / hatch / stipple / painterly / flow / pixel-Kitty) × 720p/1080p × CPU/GPU, with reproducible commands and ±10% repeatability. Reference: PHASE_P §Bench.
- [ ] **P9. Demo assets.** DoD: `docs/v1.0-split-demo.gif`, `docs/v1.0-shader-demo.gif`, `docs/v1.0-scene-demo.gif` all in repo and linked from README. Reference: PHASE_P §Demo.
- [ ] **P10. Golden coverage for everything new.** DoD: every new style/mode/source/render-mode has at least one golden frame test; capability matrix parameterized test; OSD-driven render test via `--input-keys`. Reference: PHASE_P §Tests.
- [ ] **Phase P exit criteria → tag `v1.0`.** DoD: OSD + split + snapshot ship; README is launch-quality; releases on GitHub + Homebrew + .deb; honest benchmarks published; CI green.

---

## Cross-cutting / always-on tasks

- [~] **X1. Memory safety.** Local clean; hosted Linux ASan/UBSan blocked by billing (carried into PHASE_P §CI).
- [~] **X2. No leaks on shutdown.** Local macOS clean across normal/seek/Ctrl-C; hosted Linux Valgrind blocked.
- [ ] **X3. Dependency hygiene.** DoD: `DEPENDENCIES.md` lists every system + vendored library with minimum versions and license posture; updated as Phases I/L/N add FreeType / glslang / Vulkan / libsixel / nanoflann / stb_image_write.
- [ ] **X4. Build size budget.** DoD: `-DCONTOURTTY_LIGHT=ON` builds a minimal binary (no shader cross-compile, no Vulkan, no sixel) for users who want a small install; default build documents its size impact.
- [ ] **X5. Licence audit on shipped charsets/fonts/noise tiles.** DoD: every binary asset in `share/contourtty/` is documented with origin + licence in `share/contourtty/LICENSES.md`.

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
