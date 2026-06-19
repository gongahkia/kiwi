# contourtty

![status: pre-alpha](https://img.shields.io/badge/status-pre--alpha-orange)
![CI](https://github.com/gongahkia/strok/actions/workflows/ci.yml/badge.svg)

contourtty is a C++20 terminal media renderer for live video, webcam, and stream playback as structure-aware ASCII: glyphs are selected from edge direction and shape, not brightness alone, while keeping audio/video sync in a native terminal UI.

![v0.5 side-by-side demo: luminance left, structure right](docs/v0.5-structure-demo.gif)

Demo source: public-domain Wikimedia Commons footage; luminance is left, structure mode is right. See [docs/demo-source.md](docs/demo-source.md).

## Status

Pre-alpha. Local video, images, GIFs, direct FFmpeg stream URLs, and YouTube URLs via yt-dlp now play as paced luminance or structure ASCII with audio sync where audio is present. Webcam capture, exports, and packaging are still pending.

## Build and run

```sh
cmake --preset ci
cmake --build --preset ci
./build/ci/contourtty <video-file>
```

## Runtime notes

With audio present, video is paced from the audio playback clock. Late video frames are dropped once they fall too far behind the clock, capped at 50ms, so playback holds sync instead of accumulating lag. `--max-fps N` decimates rendered video frames for slow terminals while audio continues; `--log FILE` records rendered/dropped frame counts and drift.

Structure mode overlays shape-matched edge glyphs over the luminance fill. `--edge-strength 0` disables the overlay, values below `1` make edges stricter, and values above `1` make edges more aggressive.

Structure knobs: `--mode luminance` uses the brightness ramp, `--mode structure` enables shape-aware edge glyphs, `--edge-threshold N` sets the minimum edge magnitude, `--dog-sigma N[,M]` enables DoG line isolation (`0` disables it), `--contrast N` boosts structure separation, and `--charset NAME|string` replaces the luminance ramp. Presets: `standard`, `blocks`, `detailed`, `binary`, and `braille`; `braille` packs a 2x4 luminance grid into each Unicode braille cell.

Image inputs: PNG/JPG/WebP render once and hold until `q`; animated GIFs loop with source frame timing.

Layout: `--width` and `--height` set render bounds, `--fit` clamps those bounds to the current terminal, output is centered, resize recomputes the fit and repaints, and `--loop` restarts video input at EOF.

Stream inputs: direct FFmpeg URLs such as HLS/HTTP/RTSP are passed through to libav. YouTube URLs require `yt-dlp`; contourtty resolves them with `yt-dlp -g` and fails with a clear install/direct-URL message when it is missing. Set `CONTOURTTY_YTDLP` to override the resolver binary path.

Camera inputs: use `--input cam` for the platform default (`avfoundation` on macOS, `v4l2` on Linux, `dshow` on Windows) or pass an explicit device alias such as `avfoundation:0`, `v4l2:/dev/video0`, or `dshow:video=Integrated Camera`.

Color defaults to truecolor when `COLORTERM=truecolor` or `24bit`, 256-color when `TERM` contains `256`, otherwise 16-color. `NO_COLOR` forces mono. `--color-mode` overrides detection; 256/16 output is palette-quantized. `--dither ordered` applies Bayer dithering; `--dither fs` applies CPU-side Floyd-Steinberg error diffusion, which is serial by design and not parallelized.

`--mode halfblock` renders with upper-half block cells: foreground is sampled from the top half, background from the bottom half, doubling vertical color resolution in truecolor/256-color terminals.

Controls: `space` pauses/resumes audio and video together, left/right arrows seek -/+5s, and `q` quits.

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
