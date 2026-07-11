# DEPENDENCIES.md

strok keeps runtime dependencies explicit and avoids hidden package-manager fetches during normal builds. System libraries are discovered by CMake/pkg-config; vendored code is limited to checked-in headers under `third_party/`.

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

Release packages dynamically link FFmpeg. Static-FFmpeg bundles are not shipped until the package build records FFmpeg configure flags and whether the resulting binary is LGPL-compatible, GPL-covered, or non-redistributable because of distributor options.

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

`third_party/miniaudio.h` is pinned to upstream tag `0.11.25` (`miniaudio - v0.11.25 - 2026-03-04`) from `https://github.com/mackron/miniaudio`. The header offers public domain or MIT-0 licensing. It is linked through `strok_audio`; the manual smoke executable is:

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

## Optional external tools

| Tool | Minimum | Strategy | License posture | Used for |
|---|---:|---|---|---|
| yt-dlp | any current release with `-g` | user-installed executable on `PATH`, overridable with `STROK_YTDLP` | Unlicense/public-domain equivalent | Resolving YouTube URLs to direct FFmpeg-readable media URLs. |
| glslangValidator | glslang 16.x target; local golden is 16.3.0 | user-installed executable on `PATH` | BSD-3-Clause | Optional GLSL-to-SPIR-V tests and runtime shader input. |
| spirv-cross | SPIRV-Cross 1.4.x target; local Homebrew is 1.4.350.1 | user-installed executable on `PATH` | Apache-2.0 | Optional SPIR-V-to-MSL tests and macOS Metal shader input. |

## Glyph lookup

| Library | Minimum | Strategy | License posture | Used for |
|---|---:|---|---|---|
| nanoflann | 1.9.0 | vendored header | BSD license | HoG glyph k-d tree nearest-neighbor lookup. |

`third_party/nanoflann.hpp` is pinned to upstream tag `v1.9.0` from `https://github.com/jlblancoc/nanoflann`. The checked-in header reports `NANOFLANN_VERSION 0x190`.

## GPU and platform backends

| Dependency | Minimum | Strategy | License posture | Status |
|---|---:|---|---|---|
| Metal / Foundation | macOS SDK | system frameworks | Apple SDK terms | Linked on Apple platforms for the default Metal Sobel backend unless `-DSTROK_LIGHT=ON` or `-DSTROK_FORCE_VULKAN=ON` is set. |
| Vulkan headers / loader | 1.3 | CMake `find_package(Vulkan)` | Vulkan-Headers Apache-2.0; Vulkan-Loader Apache-2.0/MIT-style | Optional `src/gpu_sobel_vulkan.cpp` backend for Sobel, DoG, structure glyphs, and per-cell RGB averages when Vulkan is found. |
| Mesa Vulkan drivers / MoltenVK | Vulkan 1.3-capable ICD | system runtime ICD | Mesa/MIT-style or Apache-2.0 for MoltenVK | Runtime device provider for Linux software/hardware Vulkan or macOS forced-Vulkan validation. |
| glslang | 16.x target; local golden is 16.3.0 | optional user-installed CLI | BSD-3-Clause | `glslangValidator` wrapper compiles GLSL-to-SPIR-V for shader tests, runtime shader input, and Vulkan backend compute modules; not linked or vendored. |
| SPIRV-Cross | 1.4.x target; local Homebrew is 1.4.350.1 | optional user-installed CLI | Apache-2.0 | `spirv-cross --msl` converts SPIR-V to MSL for shader tests and macOS runtime shader input; not linked or vendored. |

## Graphics protocol and image helpers

| Dependency | Minimum | Strategy | License posture | Status |
|---|---:|---|---|---|
| Kitty graphics protocol | terminal protocol | no library | protocol documentation only | Implemented with in-tree encoder. |
| iTerm2 inline images | terminal protocol | no library | protocol documentation only | Implemented with in-tree OSC 1337 encoder plus zlib PNG writer. |
| Sixel graphics protocol | terminal protocol | no library | protocol documentation only | Implemented with in-tree encoder and OKLab nearest-palette quantization. |
| stb_image_write | N/A | not used | N/A | Not vendored; PNG encoding is in-tree and uses zlib. |

## Shipped data assets

| Path | Origin | License posture | Notes |
|---|---|---|---|
| `share/strok/graphs/*.yaml` | in-tree authored | MIT (`LICENSE`) | Example render graphs. |
| `share/strok/charsets/*.json` | in-tree authored | MIT (`LICENSE`) | Evolved/curated glyph presets. |
| `share/strok/scenes/cube.obj` | in-tree authored | MIT (`LICENSE`) | Simple bundled OBJ smoke asset. |
| `share/strok/scenes/suzanne.obj` | Wikimedia Commons `File:Suzanne.stl`, converted to OBJ | GPL-3.0-or-later | Blender Suzanne test mesh by Willem-Paul van Overbruggen; source page: <https://commons.wikimedia.org/wiki/File:Suzanne.stl>. |
| `share/strok/shaders/*.glsl` | in-tree authored | MIT (`LICENSE`) | Shadertoy-style shader smoke and macOS runtime shader assets. |

The standalone asset audit is tracked in `share/strok/LICENSES.md`.

## Install prerequisites

macOS:

```sh
brew install cmake pkg-config ffmpeg freetype zlib
```

Ubuntu/Debian:

```sh
sudo apt-get update
sudo apt-get install -y build-essential cmake dpkg-dev file pkg-config \
  libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libswresample-dev \
  libavdevice-dev zlib1g-dev libfreetype-dev
```

Shader input and shader-toolchain tests also require the optional CLI tools:

```sh
brew install glslang spirv-cross
sudo apt-get install -y glslang-tools spirv-cross
```

Linux Vulkan builds additionally require the loader headers and an ICD:

```sh
sudo apt-get install -y libvulkan-dev vulkan-tools mesa-vulkan-drivers
```

macOS forced-Vulkan validation uses Homebrew's loader and MoltenVK:

```sh
brew install vulkan-headers vulkan-loader vulkan-tools molten-vk
cmake -S . -B build/vulkan -DCMAKE_BUILD_TYPE=Debug -DSTROK_FORCE_VULKAN=ON
```

Minimal build:

```sh
cmake -S . -B build/light -DCMAKE_BUILD_TYPE=Release -DSTROK_LIGHT=ON
cmake --build build/light --target strok --parallel
```

The light build keeps required decode/font/audio dependencies, skips optional Apple Metal/Vulkan linkage, and does not add runtime shader rendering. The shader compiler wrapper remains in the source build, but `glslangValidator` and `spirv-cross` are only required when shader-toolchain tests, shader input, or the Vulkan backend are exercised.

Local macOS Release measurement on 2026-06-21:

| Build | Command | Binary bytes | Optional framework delta |
|---|---|---:|---|
| default | `cmake -S . -B build/release -DCMAKE_BUILD_TYPE=Release` | 1,496,856 | Links Metal + Foundation on Apple platforms. |
| light | `cmake -S . -B build/light -DCMAKE_BUILD_TYPE=Release -DSTROK_LIGHT=ON` | 1,460,120 | Omits Metal + Foundation; `--gpu` falls back to CPU. |
