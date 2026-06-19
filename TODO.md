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
  - 2026-06-19: `gh run view 27823322318` confirms all CI jobs fail before logs with: "recent account payments have failed or your spending limit needs to be increased."
- [ ] **Phase A exit criteria.** DoD: clean build on ≥2 OSes in CI; raw-mode guard provably restores on normal exit, Ctrl-C, and exception; size query + SIGWINCH working.
  - 2026-06-19: `scripts/verify_terminal_paths.sh` proves local PTY raw-mode restore on keyboard quit, Ctrl-C, and forced exception, plus terminal size query; `terminal_tests` covers SIGINT/SIGWINCH flags. CI proof remains blocked by billing/spending-limit state.

---

## PHASE B — Decode & frame pipeline
*Doc: `PHASE_B.md`. Goal: turn any local file into a stream of RGB frames at the right grid resolution, using the modern send/receive libav API.*


---

## PHASE C — Luminance renderer + emission  → **v0.1**
*Doc: `PHASE_C.md`. Goal: the full live pipeline with the baseline brightness→glyph renderer, truecolor, and the differential emitter that makes high framerates possible.*


---

## PHASE D — Audio & sync
*Doc: `PHASE_D.md`. Goal: audio playback with the audio track as the master clock, and adaptive frame-skip so video tracks audio rather than drifting.*


---

## PHASE E — Structure mode (the differentiator)  → **v0.5**
*Doc: `PHASE_E.md`. Goal: the reason the project exists — glyphs chosen by shape/edge orientation, not just brightness, computed live. This is the headline.*

---

## PHASE F — Inputs & modes
*Doc: `PHASE_F.md`. Goal: make it work on the inputs people actually want, and across terminal capability tiers.*

## PHASE G — Performance, polish, release  → **v1.0**
*Doc: `PHASE_G.md`. Goal: make it fast, packaged, documented, and launched.*

- [ ] **G2. Optional GPU compute path.** DoD: a compute-shader (Vulkan/OpenGL/compute via a chosen API) implementation of the analysis pass behind `--gpu`; falls back to CPU if unavailable; significant fps gain at high cell counts recorded. Reference: PHASE_G §GPU.
  - 2026-06-19: `--gpu` is parsed and now logs an explicit CPU fallback when requested; actual compute implementation and fps-gain proof remain open.
  - 2026-06-19: added a macOS Metal Sobel compute backend behind `--gpu`, CPU fallback/stub elsewhere, GPU-vs-CPU gradient parity coverage, and byte-for-byte export parity. High-cell smoke: 160x45 structure export on 4x 1280x720 frames improved render time from `1065487us` CPU to `610866us` Metal Sobel (1.74x render speedup, 1.41x wall speedup). Full per-cell glyph/shape compute pipeline remains open, so G2 stays unchecked.
- [ ] **G7. Packaging.** DoD: single static-ish binary releases for Linux/macOS (+ Windows if feasible); a Homebrew formula and/or `.deb`; documented `ffmpeg` runtime requirement. Reference: PHASE_G §Packaging.
  - 2026-06-19: added CPack install/TGZ packaging, Linux DEB generation path, tag-driven release workflow, head-only Homebrew formula, and FFmpeg runtime docs. Local macOS package script builds, runs tests, emits TGZ, extracts it, and verifies `contourtty --version`; hosted Linux/macOS artifact proof remains blocked by GitHub Actions billing/spending-limit state.
  - 2026-06-19: re-ran `scripts/package_release.sh` after adding the Objective-C++/Metal source; release build, 19 tests, and CPack TGZ generation passed locally on macOS arm64. Hosted Linux/macOS artifact proof remains blocked by GitHub Actions billing/spending-limit state.
- [ ] **G9. Technique writeup / launch.** DoD: a blog post or video explaining the structure-mode technique (the shareable artifact); links from README. Reference: PHASE_G §Launch.
  - 2026-06-19: drafted and linked `docs/structure-mode-writeup.md`; external publication/launch post remains unverified.
- [ ] **Phase G exit criteria → tag `v1.0`.** DoD: fast (GPU path or strong SIMD), packaged for ≥2 platforms, fully documented, with a published technique writeup and reproducible benchmarks.

---

## Cross-cutting / always-on tasks
- [ ] **X1. Memory safety.** DoD: ASan + UBSan clean in CI on the decode+render path.
  - 2026-06-19: local `asan-ubsan` build, CTest, structure export smoke, and shutdown-path smoke are clean; sanitizer CI is configured to run them, but hosted proof remains blocked by GitHub Actions billing/spending-limit state.
- [ ] **X2. No leaks on shutdown.** DoD: Valgrind/ASan reports no leaks after normal exit, Ctrl-C, and seek.
  - 2026-06-19: macOS `leaks --atExit` reports `0 leaks for 0 total leaked bytes` on normal structure export shutdown; Valgrind is unavailable locally, and Ctrl-C/seek leak paths remain unverified.
  - 2026-06-19: `scripts/verify_shutdown_paths.sh` proves normal export, keyboard quit, seek+quit, and SIGINT reach clean shutdown logs locally and is wired into sanitizer CI; this verifies shutdown behavior locally, with hosted ASan/LSan proof still blocked by GitHub Actions billing/spending-limit state.
  - 2026-06-19: Valgrind CI job is configured for normal structure export leak checks on Ubuntu; hosted Valgrind result and Ctrl-C/seek leak accounting remain unverified while GitHub Actions is billing-blocked.
  - 2026-06-19: Valgrind CI now wraps `scripts/verify_shutdown_paths.sh`, so normal export, keyboard quit, seek+quit, and SIGINT all run under definite-leak checks; sanitizer shutdown smoke now sets `ASAN_OPTIONS=detect_leaks=1:halt_on_error=1`. Hosted proof remains blocked by GitHub Actions billing/spending-limit state.

---

## Reference materials (study before/while building)
- **Decode:** dranger ffmpeg tutorial; leandromoreira/ffmpeg-libav-tutorial; FFmpeg send/receive API doxygen. Use the modern `avcodec_send_packet`/`avcodec_receive_frame` API, **not** `avcodec_decode_video2`.
- **Terminal color:** termstandard/colors; ANSI escape code (Wikipedia); "Terminal Colors Demystified". Truecolor SGR: `\e[38;2;r;g;bm` / `\e[48;2;r;g;bm`. Detect via `COLORTERM`; respect `NO_COLOR`.
- **Structure ASCII (the core technique):** Alex Harri, "ASCII characters are not pixels" (shape vectors via sampling-circle overlap + cel-shading contrast). Acerola's ASCII shader (Sobel/DoG + directional glyphs). Academic: structure-based ASCII (HoG/NCC glyph matching).
- **Reference tools to study (not copy):** `timg` and `chafa` source for protocol detection, dithering, threading, frame-skip; `mpv` `--vo=kitty` for the fidelity ceiling.
- **Aspect ratio:** terminal cells ≈ 1:2 (w:h); expose a correction knob (timg does). Circle test is the canary.

## Naming
Avoid the saturated `ascii-video-player` / `timg` / `tplay` / `chafa` namespace. Structure-angle candidates: `glyph`, `glyphstream`, `etch`, `inkterm`, `hatch`, `strok`. Verify on GitHub + crates/Homebrew before committing (task A2).
