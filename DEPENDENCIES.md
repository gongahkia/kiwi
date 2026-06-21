# DEPENDENCIES.md

contourtty keeps runtime dependencies explicit and avoids hidden package-manager fetches during normal builds. System libraries are discovered by CMake/pkg-config; vendored code is limited to checked-in headers under `third_party/`.

## Build tools

| Dependency | Minimum | Strategy | License posture | Notes |
|---|---:|---|---|---|
| CMake | 3.20 | system | Kitware BSD-style | Required for configure/build. |
| C++ compiler | C++20 | system | toolchain-provided | AppleClang, Clang, or GCC with C++20 support. |
| pkg-config | any current | system | GPL-2.0-or-later for freedesktop `pkg-config`; implementation may vary | Used to discover FFmpeg and FreeType. |
| Threads | CMake `Threads` | system | platform/system | Used by render workers and linked tests. |

## Media decode and conversion

| Library | Minimum | Strategy | License posture | Used for |
|---|---:|---|---|---|
| `libavformat` | FFmpeg 6.0 | `pkg-config` | LGPL/GPL depending distributor build; dynamically linked | Container open/probing and packet read. |
| `libavcodec` | FFmpeg 6.0 | `pkg-config` | LGPL/GPL depending distributor build; dynamically linked | Video/audio decoder setup and send/receive decode API. |
| `libavdevice` | FFmpeg 6.0 | `pkg-config` | LGPL/GPL depending distributor build; dynamically linked | Webcam/device input. |
| `libavutil` | FFmpeg 6.0 | `pkg-config` | LGPL/GPL depending distributor build; dynamically linked | Core FFmpeg types, timestamps, buffers, errors. |
| `libswscale` | FFmpeg 6.0 | `pkg-config` | LGPL/GPL depending distributor build; dynamically linked | Pixel conversion and RGB scaling. |
| `libswresample` | FFmpeg 6.0 | `pkg-config` | LGPL/GPL depending distributor build; dynamically linked | Audio format/rate conversion for Phase D. |

Minimum FFmpeg target: 6.0. The send/receive decoder API exists in older FFmpeg releases, but 6.x is the support floor to reduce platform drift and deprecated-code pressure.

Expected CMake discovery:

```cmake
pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET
  libavformat
  libavcodec
  libavdevice
  libavutil
  libswscale
  libswresample
)
pkg_check_modules(FREETYPE REQUIRED IMPORTED_TARGET freetype2)
```

## Raster output and fonts

| Library | Minimum | Strategy | License posture | Used for |
|---|---:|---|---|---|
| zlib | 1.2.x | CMake `find_package(ZLIB)` | zlib license; dynamically linked | PNG encoding for dumps, iTerm inline images, and still snapshots. |
| FreeType | 2.12 | `pkg-config` | FreeType License or GPL-2.0; dynamically linked | Font-backed glyph rasterization for shape matching, MP4 export, and `raster_compose`. |

## Audio

| Library | Minimum | Strategy | License posture | Used for |
|---|---:|---|---|---|
| miniaudio | 0.11.25 | vendored header | public domain or MIT-0 | Cross-platform playback, master audio clock, pause/seek in Phase D. |
| CoreAudio / AudioToolbox / AudioUnit / CoreFoundation | macOS SDK | system frameworks | Apple SDK terms | macOS audio backend used by miniaudio. |

`third_party/miniaudio.h` is pinned to upstream tag `0.11.25` (`miniaudio - v0.11.25 - 2026-03-04`) from `https://github.com/mackron/miniaudio`. The header offers public domain or MIT-0 licensing. It is linked through `contourtty_audio`; the manual smoke executable is:

```sh
./build/ci/audio_sine_smoke 0.25
```

The smoke target initializes the default playback device at f32/stereo/48 kHz and emits a generated sine wave. It is not added to CTest because hardware audio availability is environment-dependent.

Audio decode/resample smoke uses FFmpeg plus `libswresample` to decode the first audio stream into f32/stereo/48 kHz PCM, then plays it through miniaudio:

```sh
./build/ci/audio_file_smoke <media-file>
```

Audio clock smoke samples the miniaudio callback-backed playback clock while the decoded PCM is playing:

```sh
./build/ci/audio_clock_smoke <media-file>
```

## CLI

| Library | Minimum | Strategy | Used for |
|---|---:|---|---|
| internal parser | in-tree | source | `--help`, `--version`, positional input, typed flags, enum validation. |

The Phase A parser is hand-rolled and in-tree to avoid an early external dependency. Revisit CLI11 only if flag complexity grows enough to justify vendoring it.

## Glyph lookup

| Library | Minimum | Strategy | License posture | Used for |
|---|---:|---|---|---|
| nanoflann | 1.9.0 | vendored header | BSD license | HoG glyph k-d tree nearest-neighbor lookup. |

`third_party/nanoflann.hpp` is pinned to upstream tag `v1.9.0` from `https://github.com/jlblancoc/nanoflann`. The checked-in header reports `NANOFLANN_VERSION 0x190`.

## GPU and platform backends

| Dependency | Minimum | Strategy | License posture | Status |
|---|---:|---|---|---|
| Metal / Foundation | macOS SDK | system frameworks | Apple SDK terms | Linked on Apple platforms for the current Metal Sobel backend. |
| Vulkan SDK / loader | 1.3 | system or future vendored SDK headers | Vulkan-Headers Apache-2.0; loader Apache-2.0/MIT-style | Not linked yet; Phase L Vulkan backend is locally blocked until SDK/tools are present. |
| glslang | TBD | not vendored | BSD-3-Clause | Not vendored/linked yet; Phase L shader cross-compile blocked locally. |
| SPIRV-Cross | TBD | not vendored | Apache-2.0 | Not vendored/linked yet; Phase L shader cross-compile blocked locally. |

## Graphics protocol and image helpers

| Dependency | Minimum | Strategy | License posture | Status |
|---|---:|---|---|---|
| Kitty graphics protocol | terminal protocol | no library | protocol documentation only | Implemented with in-tree encoder. |
| iTerm2 inline images | terminal protocol | no library | protocol documentation only | Implemented with in-tree OSC 1337 encoder plus zlib PNG writer. |
| libsixel | TBD | not linked | MIT-style | Not present locally; Sixel encoder remains blocked. |
| stb_image_write | N/A | not used | N/A | Not vendored; PNG encoding is in-tree and uses zlib. |

## Shipped data assets

| Path | Origin | License posture | Notes |
|---|---|---|---|
| `share/contourtty/graphs/*.yaml` | in-tree authored | MIT (`LICENSE`) | Example render graphs. |
| `share/contourtty/charsets/*.json` | in-tree authored | MIT (`LICENSE`) | Evolved/curated glyph presets. |
| `share/contourtty/scenes/cube.obj` | in-tree authored | MIT (`LICENSE`) | Simple bundled OBJ smoke asset. |

The standalone asset audit is tracked in `share/contourtty/LICENSES.md`.

## Install prerequisites

macOS:

```sh
brew install cmake pkg-config ffmpeg freetype zlib
```

Ubuntu/Debian:

```sh
sudo apt-get update
sudo apt-get install -y build-essential cmake pkg-config \
  libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libswresample-dev \
  libavdevice-dev zlib1g-dev libfreetype-dev
```
