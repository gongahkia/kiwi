# Kiwi

Kiwi is a rendering-first terminal research platform: M0 is a LuaJIT + wgpu-native laboratory that turns a deterministic, structured terminal-cell model into ordered GPU passes, rather than treating a terminal as a pre-rendered bitmap.

## Status

M0 is a renderer laboratory, not a usable terminal emulator. It opens a native GLFW window, selects a Vulkan adapter through wgpu-native, rasterizes basic-Latin glyphs with FreeType, and renders a synthetic 160×50 screen through background, glyph, and cursor passes. PTYs, shells, VT parsing, scrollback, Unicode shaping, and terminal graphics protocols are intentionally absent.

## Architecture at a glance

```
LuaJIT app
  -> synthetic TerminalModel (logical cells + damage)
  -> Renderer (background -> glyph -> cursor)
  -> LuaJIT FFI + narrow C ABI bridge
  -> wgpu-native v29.0.1.1 -> Vulkan

FreeType -> bitmap glyph atlas -> GPU texture
GLFW -> native Wayland/X11 window + drawable size
```

More detail is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The consequential choices are recorded under [docs/adr](docs/adr).

## Fedora prerequisites

Kiwi M0 currently supports Linux x86_64. On Fedora 43, install the development toolchain and the system libraries:

```sh
sudo dnf install luajit gcc make curl unzip pkgconf-pkg-config \
  glfw-devel freetype-devel mesa-vulkan-drivers vulkan-loader-devel \
  vulkan-tools fontconfig google-noto-sans-mono-fonts
```

`make bootstrap` verifies LuaJIT, `pkg-config` metadata for GLFW and FreeType, downloads the pinned official wgpu-native Linux archive, verifies its SHA-256, and keeps it under `.deps/`.

## Commands

```sh
make bootstrap  # resolve pinned wgpu-native and validate prerequisites
make test       # deterministic model, atlas, packing, statistics, and JSON tests
make check      # normal non-interactive test and Lua syntax suite
make run        # open the native renderer-laboratory window
make smoke      # run a short native window/GPU smoke test; skips without a display
make bench      # run deterministic terminal-model/update benchmarks and write JSON
make clean      # remove generated native build output from .build/
```

`make run` uses a 30 Hz, vsynced FIFO presentation cadence because the animated semantic cursor needs redraws. It waits for window events between frames instead of spinning uncapped. `Esc` closes the window; `F2` toggles dirty-cell highlighting; `F3` toggles cell boundaries.

## Benchmarking

`make bench` runs static, typing, line-churn, scrolling-like, and full-redraw workloads at 160×50 and 240×80. It reports mean/p50/p95/p99 CPU update times, changed/uploaded cells, uploaded bytes, dirty ranges, full updates, and draw calls; it writes machine-readable output to `bench/results/<UTC timestamp>.json`.

The benchmark is deliberately headless and measures logical mutation, damage coalescing, and CPU packing in the same cell layout used for GPU uploads. It does not claim GPU frame timing or compare Kiwi with other terminals. See [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

## Current scope and non-features

M0 demonstrates a real bitmap glyph atlas and GPU text draw path for readable ASCII/basic Latin. It does not claim Unicode correctness: HarfBuzz shaping, ligatures, combining marks, RTL, CJK fallback, emoji, Nerd Font validation, and MSDF/vector paths are deferred. The synthetic model is a stable renderer input, not a VT emulator.

## Roadmap

The renderer-first direction through M8 is summarized in [docs/ROADMAP.md](docs/ROADMAP.md). The next coherent step is M1: retain this renderer boundary while introducing a PTY, shell lifecycle, deliberately scoped VT state/parser, resize propagation, scrollback, and deterministic replay tests.
