# contourtty

![status: pre-alpha](https://img.shields.io/badge/status-pre--alpha-orange)
![CI](https://github.com/gongahkia/strok/actions/workflows/ci.yml/badge.svg)

contourtty is a C++20 terminal media renderer for live video, webcam, and stream playback as structure-aware ASCII: glyphs are selected from edge direction and shape, not brightness alone, while keeping audio/video sync in a native terminal UI.

![v0.5 side-by-side demo: luminance left, structure right](docs/v0.5-structure-demo.gif)

Demo source: public-domain Wikimedia Commons footage; luminance is left, structure mode is right. See [docs/demo-source.md](docs/demo-source.md).

## Status

Pre-alpha. Local video, images, GIFs, direct FFmpeg stream URLs, and YouTube URLs via yt-dlp now play as paced luminance or structure ASCII with audio sync where audio is present. Silent MP4, ANSI, and asciinema export work; webcam capture and published release artifacts are still pending.

## Build and run

```sh
cmake --preset ci
cmake --build --preset ci
./build/ci/contourtty <video-file>
```

Runtime dependency: contourtty links against system FFmpeg libraries (`libavformat`, `libavcodec`, `libavdevice`, `libavutil`, `libswscale`, `libswresample`) plus zlib. On macOS, install them with `brew install ffmpeg zlib`; on Debian/Ubuntu, install the matching `libav*-dev` packages for builds and the corresponding shared runtime packages for packaged binaries.

Install from source:

```sh
cmake -S . -B build/release -DCMAKE_BUILD_TYPE=Release
cmake --build build/release
cmake --install build/release --prefix /usr/local
```

Package locally:

```sh
scripts/package_release.sh
```

The package script emits a `.tar.gz` on macOS/Linux and a `.deb` on Linux. A head-only Homebrew formula is available at `packaging/homebrew/contourtty.rb`; install it with `brew install --HEAD ./packaging/homebrew/contourtty.rb`.

## Runtime notes

With audio present in local files, video is paced from the audio playback clock. Remote streams and camera input use wall-clock pacing to avoid full audio predecode before playback. Late video frames are dropped once they fall too far behind the clock, capped at 50ms, so playback holds sync instead of accumulating lag. `--max-fps N` decimates rendered video frames for slow terminals while audio continues; `--log FILE` records rendered/dropped frame counts and drift.

Structure mode overlays shape-matched edge glyphs over the luminance fill. `--edge-strength 0` disables the overlay, values below `1` make edges stricter, and values above `1` make edges more aggressive.

Structure knobs: `--mode luminance` uses the brightness ramp, `--mode structure` enables shape-aware edge glyphs, `--edge-threshold N` sets the minimum edge magnitude, `--dog-sigma N[,M]` enables DoG line isolation (`0` disables it), `--contrast N` boosts structure separation, and `--charset NAME|string` replaces the luminance ramp. Presets: `standard`, `blocks`, `detailed`, `binary`, and `braille`; `braille` packs a 2x4 luminance grid into each Unicode braille cell. `--gpu` uses the optional Metal structure-analysis backend for DoG, Sobel, glyph choice, and per-cell averages on macOS when available, and falls back to CPU elsewhere.

Image inputs: PNG/JPG/WebP render once and hold until `q`; animated GIFs loop with source frame timing.

Layout: `--width` and `--height` set render bounds, `--fit` clamps those bounds to the current terminal, output is centered, resize recomputes the fit and repaints, and `--loop` restarts video input at EOF.

Stream inputs: direct FFmpeg URLs such as HLS/HTTP/RTSP are passed through to libav. YouTube URLs require `yt-dlp`; contourtty resolves them with `yt-dlp -g` and fails with a clear install/direct-URL message when it is missing. Set `CONTOURTTY_YTDLP` to override the resolver binary path.

Camera inputs: use `--input cam` for the platform default (`avfoundation` on macOS, `v4l2` on Linux, `dshow` on Windows) or pass an explicit device alias such as `avfoundation:0`, `v4l2:/dev/video0`, or `dshow:video=Integrated Camera`. Live capture requests 640x480 at 30 fps for low-latency structure analysis. Camera playback mirrors horizontally by default; pass `--no-mirror` for sensor-native orientation.

Color defaults to truecolor when `COLORTERM=truecolor` or `24bit`, 256-color when `TERM` contains `256`, otherwise 16-color. `NO_COLOR` forces mono. `--color-mode` overrides detection; 256/16 output is palette-quantized. `--dither ordered` applies Bayer dithering; `--dither fs` applies CPU-side Floyd-Steinberg error diffusion, which is serial by design and not parallelized.

`--mode halfblock` renders with upper-half block cells: foreground is sampled from the top half, background from the bottom half, doubling vertical color resolution in truecolor/256-color terminals.

Controls: `space` pauses/resumes audio and video together, left/right arrows seek -/+5s, and `q` quits.

Export: `--export out.mp4` writes a silent rasterized video of the ASCII output; `--export out.ansi` writes the raw ANSI escape stream, replayable with `cat out.ansi`; `--export out.cast` writes asciinema v2 output. Export uses the same renderer and honors width/height, mode, charset, color, and dither flags.

Config: defaults are read from `$XDG_CONFIG_HOME/contourtty/config`, or `~/.config/contourtty/config` when `XDG_CONFIG_HOME` is unset. The file is simple `key=value` syntax using flag names without `--`, for example `mode=structure` or `charset=" .#"`; CLI flags override config defaults.

## Flag reference

| Flag | Meaning |
|---|---|
| `--help` | Show CLI help. |
| `--version` | Show version. |
| `--width N` | Target terminal columns or export columns. |
| `--height N` | Target terminal rows or export rows. |
| `--input PATH\|URL\|cam` | Input path, stream URL, or camera alias. |
| `--cell-aspect N` | Terminal cell width/height ratio; default is `0.5`. |
| `--fit`, `--no-fit` | Clamp output to terminal, or disable config-default fit. |
| `--fps N` | Override source fps for playback/export pacing. |
| `--max-fps N` | Cap rendered fps while preserving audio timing. |
| `--mode luminance\|structure\|halfblock` | Select renderer. |
| `--color-mode auto\|truecolor\|256\|16\|mono` | Select color tier. |
| `--color auto\|truecolor\|256\|16\|mono` | Alias for `--color-mode`. |
| `--mono`, `--no-mono` | Force mono, or restore automatic color detection. |
| `--charset NAME\|string` | Glyph preset or custom UTF-8 glyph ramp. |
| `--edge-threshold N` | Minimum structure edge magnitude. |
| `--edge-strength N` | Structure overlay multiplier; `0` disables edges. |
| `--dog-sigma N[,M]` | Difference-of-Gaussians sigma pair; `0` disables DoG. |
| `--dog-threshold N` | DoG response threshold. |
| `--contrast N` | Structure analysis contrast boost. |
| `--dither none\|ordered\|fs` | Palette dithering mode. |
| `--loop`, `--no-loop` | Loop video input, or disable config-default looping. |
| `--mirror`, `--no-mirror` | Enable or disable horizontal mirroring for camera playback. |
| `--log FILE` | Write diagnostics. |
| `--gpu`, `--no-gpu` | Request or disable the optional GPU analysis path. |
| `--debug-stats`, `--no-debug-stats` | Show or hide live FPS, CPU, and RSS diagnostics during playback; samples are also written when `--log` is set. |
| `--export FILE` | Offline export to `.mp4`, `.ansi`, or `.cast`. |
| `--dump-frame N` | Decode frame `N` for diagnostics. |
| `--dump-png FILE` | Write dumped frame as RGB PNG. |

## How structure mode works

Structure mode still starts from the same decoded RGB frame and terminal layout as luminance mode, but it adds an analysis pass before glyph selection:

```text
RGB frame -> luminance field -> optional contrast/DoG -> Sobel gradients
          -> per-cell edge orientation + magnitude -> glyph choice -> CellBuffer
```

The luminance renderer picks a glyph from the brightness ramp for every cell. Structure mode keeps that brightness glyph as a fallback, then detects directional edges in the cell. Strong vertical, horizontal, and diagonal gradients map to structure glyphs such as `|`, `_`, `/`, `\`, and `+`.

When shape matching is enabled, the edge magnitude field inside the cell is sampled into a compact shape vector and compared against precomputed vectors for the structure glyph set. This lets the renderer choose by local stroke shape rather than by brightness alone. DoG (`--dog-sigma`) can isolate line-like detail before Sobel, and `--contrast` can widen separation in low-contrast footage.

Benchmarks: [BENCHMARKS.md](BENCHMARKS.md).

## Name

Chosen name: `contourtty`.

Public namespace checks on 2026-06-18:

- GitHub user/org path: `https://github.com/contourtty` returned 404.
- GitHub public repository search: no exact `contourtty` repository name in the first 100 `in:name` matches.
- Homebrew Formula API: `https://formulae.brew.sh/api/formula/contourtty.json` returned 404.
- Homebrew Cask API: `https://formulae.brew.sh/api/cask/contourtty.json` returned 404.
- Saturated names rejected: `timg`, `tplay`, `chafa`, `ascii-video-player`.
- Alternatives rejected: `strok` (`https://github.com/strok` exists), `glyph`/`hatch` (Homebrew collisions), `glyphstream`/`etch`/`inkterm` (GitHub exact-repo collisions).

## License

MIT.
