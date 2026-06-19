# Contributing

## Setup

Install CMake, pkg-config, FFmpeg development libraries, and zlib. On macOS:

```sh
brew install cmake pkg-config ffmpeg zlib
```

On Debian/Ubuntu:

```sh
sudo apt-get install cmake pkg-config libavformat-dev libavcodec-dev libavdevice-dev libavutil-dev libswscale-dev libswresample-dev zlib1g-dev
```

## Build And Test

```sh
cmake --preset ci
cmake --build --preset ci
ctest --test-dir build/ci --output-on-failure
```

Run the sanitizer preset before touching decode, render, or terminal teardown paths:

```sh
cmake --preset asan-ubsan
cmake --build --preset asan-ubsan
ctest --test-dir build/asan-ubsan --output-on-failure
```

## Change Rules

Keep changes scoped to the task. Do not refactor unrelated renderer, terminal, or decoder code in the same patch.

Add tests for new behavior. Renderer changes should include CellBuffer-level coverage where possible; terminal-byte tests alone are not enough for glyph selection behavior.

Record benchmarks in `BENCHMARKS.md` for changes that affect decode, analysis, render, emit, export, or sync performance.

## Architecture Notes

Decode uses FFmpeg send/receive APIs and returns owned RGB frames. Rendering produces a `CellBuffer`; terminal output and exports are consumers of that buffer. Structure mode builds luminance, optional DoG contrast, Sobel gradients, and optional shape-vector glyph matches before emission.

Terminal raw mode must restore on normal exit, Ctrl-C, and handled exceptions. Changes that introduce blocking I/O must respect the quit/interrupt path.

## Packaging

Use:

```sh
scripts/package_release.sh
```

The script performs a Release build, runs CTest, then emits CPack packages. Do not commit generated packages.
