# DEPENDENCIES.md

contourtty keeps runtime dependencies explicit and avoids hidden package-manager fetches during normal builds.

## Build tools

| Dependency | Minimum | Strategy | Notes |
|---|---:|---|---|
| CMake | 3.20 | system | Required for configure/build. |
| C++ compiler | C++20 | system | AppleClang, Clang, or GCC with C++20 support. |
| pkg-config | any current | system | Used to discover FFmpeg libraries. |
| zlib | any current | system/find-package | PNG dump compression for decode verification. |

## Media decode and conversion

| Library | Minimum | Strategy | Used for |
|---|---:|---|---|
| `libavformat` | FFmpeg 6.0 | `pkg-config` | Container open/probing and packet read. |
| `libavcodec` | FFmpeg 6.0 | `pkg-config` | Video/audio decoder setup and send/receive decode API. |
| `libavutil` | FFmpeg 6.0 | `pkg-config` | Core FFmpeg types, timestamps, buffers, errors. |
| `libswscale` | FFmpeg 6.0 | `pkg-config` | Pixel conversion and RGB scaling. |
| `libswresample` | FFmpeg 6.0 | `pkg-config` | Audio format/rate conversion for Phase D. |

Minimum FFmpeg target: 6.0. The send/receive decoder API exists in older FFmpeg releases, but 6.x is the support floor to reduce platform drift and deprecated-code pressure.

Expected CMake discovery:

```cmake
pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET
  libavformat
  libavcodec
  libavutil
  libswscale
  libswresample
)
```

## Audio

| Library | Minimum | Strategy | Used for |
|---|---:|---|---|
| miniaudio | pinned vendored header | vendored | Cross-platform playback, master audio clock, pause/seek in Phase D. |

`third_party/miniaudio.h` will be committed with version/source metadata when Phase D starts. No system audio library is required by default.

## CLI

| Library | Minimum | Strategy | Used for |
|---|---:|---|---|
| internal parser | in-tree | source | `--help`, `--version`, positional input, typed flags, enum validation. |

The Phase A parser is hand-rolled and in-tree to avoid an early external dependency. Revisit CLI11 only if flag complexity grows enough to justify vendoring it.

## Install prerequisites

macOS:

```sh
brew install cmake pkg-config ffmpeg
```

Ubuntu/Debian:

```sh
sudo apt-get update
sudo apt-get install -y build-essential cmake pkg-config \
  libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libswresample-dev zlib1g-dev
```
