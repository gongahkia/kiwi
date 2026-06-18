# PHASE_F.md — Inputs & Modes

**Goal:** Make it work on the inputs people actually want (webcam, images, GIFs, streams) and across terminal capability tiers (truecolor / 256 / 16 / mono / half-block), with dithering and charset options.

**Exit criteria:** webcam, image, GIF, file, and at least one stream type all render; truecolor/256/16/mono/halfblock all produce correct output on the appropriate terminals.

---

## §Webcam (F1)
- Capture via libav's device input (avdevice): on Linux `v4l2` (`/dev/video0`), macOS `avfoundation`, Windows `dshow`. Open with `avformat_open_input` using the matching input format and device name.
- Feed captured frames through the same decode→downscale→render path.
- Mirror horizontally by default (selfie view); `--no-mirror` to disable.
- Keep latency low: small/zero queue for live capture (don't buffer ahead).
- **DoD:** live structure-ASCII webcam with acceptable latency; per-OS capture documented.

## §Images (F2)
- Still image (png/jpg/webp): decode one frame, render once, hold until quit.
- Animated GIF: decode frames with their per-frame delays; loop honoring timing.
- **DoD:** image holds; GIF loops at correct speed.

## §Streams (F3)
- Network URLs (HLS/RTSP/RTMP/http): `avformat_open_input` handles many directly.
- YouTube/site URLs: shell out to `yt-dlp` to resolve a direct stream URL (or pipe its output), then decode. Document the optional `yt-dlp` dependency.
- Graceful failure: unreachable URL / unsupported → clear message, non-zero exit.
- **DoD:** an HLS/RTSP URL plays; a YouTube URL plays via yt-dlp.

## §Detect — terminal capability detection (F4)
- Truecolor: `COLORTERM` == `truecolor` or `24bit` ⇒ 24-bit. (Most modern terminals set this; Windows Terminal supports truecolor since build 14931 even without it.)
- 256-color: `TERM` ends with `256`/`256color` ⇒ 256.
- Else assume 8/16.
- **Respect `NO_COLOR`**: if set, force mono regardless.
- `--color-mode {auto|truecolor|256|16|mono}` overrides detection.
- Optional advanced: interactive DECRQSS query to confirm truecolor by setting a color and reading it back (transparent to ssh/sudo) — nice-to-have, not required.
- **DoD:** correct tier chosen automatically; NO_COLOR honored; override works.

## §Quantize — 256 and 16 color (F5)
- 256: map RGB to the xterm 6×6×6 color cube + 24-step grayscale ramp; pick nearest. Add ordered dithering to reduce banding.
- 16: map to the 16 ANSI colors; dither.
- Emit with the appropriate SGR forms (`38;5;N` for 256-color indexed; `30–37`/`90–97` for 16-color).
- **DoD:** recognizable output on a 256-color and a 16-color terminal.

## §HalfBlock — 24-bit half-block mode (F6)
- Use `▀` (upper half block) with fg = top pixel color, bg = bottom pixel color (or `▄` lower half). This packs **two vertical pixels per cell**, doubling vertical resolution — the highest-fidelity *text-only* mode.
- Requires truecolor (or 256) for the two colors.
- Aspect: with half-blocks each cell represents 1 wide × 2 tall pixels; recompute grid mapping accordingly.
- **DoD:** `--mode halfblock` renders near-photographic color blocks with correct aspect.

## §Dither — algorithm choice (F7)
- `--dither {none|ordered|fs}`.
- **Ordered/Bayer**: a threshold matrix; per-cell, parallel-friendly; default for color quantization.
- **Floyd–Steinberg (fs)**: error diffusion; better gradients but **inherently serial** (each pixel's error propagates to neighbors) — implement CPU-side, single-threaded over the row order; document that it does not parallelize and is therefore not on the GPU path.
- **DoD:** both run; banding visibly reduced vs none; FS limitation documented.

## §Charsets — presets + custom (F8)
- Presets:
  - `standard` ` .:-=+*#%@`
  - `detailed` long 70-char ramp
  - `blocks` ` ░▒▓█`
  - `binary` ` 01` or just `01`
  - `braille` — uses Unicode braille (U+2800..U+28FF) packing a **2×4 dot grid per cell**, giving the highest spatial resolution of any character mode; map the cell sub-block's on/off pixels to the 8 dot bits.
- `--charset "<string>"` for custom ramps.
- **DoD:** all presets selectable; braille uses correct 2×4 dot packing; custom string works.

## §Layout — loop / fit / position (F9)
- `--loop` (video/gif), `--width`, `--height`, `--fit` (fit to terminal preserving aspect), centering.
- Live re-fit on SIGWINCH (recompute grid + sws ctx + force full repaint), OR a clean documented guard ("resize pauses and re-fits") if live re-fit is deferred — prior art warns that naive resize corrupts layout, so this must be handled deliberately.
- **DoD:** flags behave; resize doesn't corrupt output.

## Pitfalls
- avdevice not compiled into the system FFmpeg → webcam unavailable; detect and message.
- yt-dlp absent → stream-from-site fails; detect and message.
- Half-block aspect math differs from glyph-mode aspect — handle separately.
- Braille dot bit order is specific (U+2800 + bitmask with a particular dot numbering); get the mapping right or output looks scrambled.
- 256-color nearest-match without dithering bands badly on gradients.
