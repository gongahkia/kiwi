# PHASE_G.md — Performance, Polish, Release (→ v1.0)

**Goal:** Make it fast (SIMD/threads, optional GPU), add exports, package it, document it thoroughly, and launch with honest demos.

**Exit criteria → tag `v1.0`:** fast (GPU path or strong SIMD), packaged for ≥2 platforms, fully documented, with reproducible benchmarks.

---

## §CPU — SIMD + multithreading the analysis pass (G1)
- The Phase E hotspot is per-cell gradient + shape-vector matching. Parallelize:
  - Split the cell grid into row bands across a thread pool (one band per worker).
  - SIMD the inner loops (gradient, vector dot-products) with portable intrinsics or compiler auto-vectorization (`-O3 -march=native` for local builds; portable baseline for releases).
- Correctness guard: a golden-frame test must produce identical output before/after (see §Tests).
- **DoD:** measured multicore speedup recorded; output unchanged.

## §GPU — optional compute path (G2)
- Sobel/DoG and shape-matching parallelize cleanly (per-cell independent) → ideal GPU compute workload. (Floyd–Steinberg stays CPU-side — it's serial.)
- Pick an API: Vulkan compute (portable, heavy), OpenGL compute shaders (simpler, widely available), or a thin abstraction. For a terminal tool, OpenGL compute or Vulkan headless is reasonable; document the choice and the headless-context setup.
- Pipeline: upload working-resolution frame + glyph shape-vector table to GPU buffers; compute per-cell glyph indices + colors; read back the CellBuffer; emit on CPU.
- Behind `--gpu`; auto-fallback to CPU if no device/context.
- **DoD:** significant fps gain at high cell counts recorded; correctness matches CPU path within tolerance.

## §ExportMP4 — render to a video file (G3)
- `--export out.mp4`: run the full render offline (no real-time pacing), rasterize each ASCII frame to an image (render the chosen font + colors to a pixel buffer via FreeType), encode with libav (H.264) at source fps, mux audio.
- **DoD:** the MP4 plays in a normal player and shows the ASCII rendering.

## §ExportCast — asciinema + raw ANSI (G4)
- `--export out.cast`: write a valid asciinema v2 recording (JSON header + timed event lines of the escape stream).
- `--export out.ansi`: write the raw escape-sequence stream; replayable with `cat out.ansi` (or `less -R`).
- **DoD:** `.cast` plays in asciinema; `.ansi` replays via cat.

## §Config — config file + defaults (G5)
- Read `~/.config/<name>/config` (TOML or simple key=value) for defaults; CLI flags override.
- **DoD:** changing a default in config (e.g. default charset) takes effect without recompiling; CLI still wins.

## §Tests — golden-frame regression (G6)
- Fixed input frames → expected CellBuffer (serialized). CI compares byte-for-byte (mono) or within perceptual tolerance (color/structure).
- Cover: luminance mapping, directional mapping, shape matching, each color tier, each charset, half-block, braille.
- **DoD:** tests run in CI and catch regressions.

## §Packaging (G7)
- Static-ish single binary per platform. FFmpeg is the tricky dependency:
  - Document the runtime requirement (system FFmpeg libs), OR
  - For releases, statically link FFmpeg (build a static FFmpeg and link) to ship a self-contained binary — larger but install-free. Document the tradeoff.
- Provide: GitHub Releases binaries (Linux x86_64/arm64, macOS arm64/x86_64), a Homebrew formula, optionally a `.deb`. Windows build if the platform abstraction (Phase A) was kept.
- **DoD:** a user on a fresh machine can install and run with documented steps.

## §Docs (G8)
- README: hero GIF (the structure-mode side-by-side from Phase E), one-line install, usage examples, full flag reference, a "How structure mode works" section (the technique, with a diagram), benchmarks link, license.
- `CONTRIBUTING.md`, a generated man page, and inline `--help` parity with README.
- **DoD:** a newcomer can install, run, and understand the differentiator from the README alone.

## §Bench — publish honest numbers (G10)
- Finalize `BENCHMARKS.md`: machine specs, exact commands, sustained cols×rows×fps per mode (luminance / directional / shape-match / half-block / braille), CPU vs GPU, A/V drift, dropped frames. Reproducible.
- **DoD:** numbers are reproducible from the documented commands; linked from README.

## Pitfalls
- `-march=native` in shipped binaries → crashes on older CPUs. Use a portable baseline for releases; native only for local builds.
- GPU readback latency can eat the gains at small grids — GPU helps at *high* cell counts; keep the CPU path competitive for typical sizes and auto-choose.
- Static FFmpeg linking is fiddly (licensing: prefer LGPL components or comply with GPL if you enable GPL'd codecs); document the license posture.
- Export rasterization must use the *same* font/metrics as the live renderer or exports won't match what users saw.
- Don't let the launch demo oversell: show real footage, state the framerate honestly, name the terminal used.
