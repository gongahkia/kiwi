# Kiwi

Kiwi is a rendering-first terminal research platform. M2 adds Unicode 17 extended grapheme clusters, deterministic terminal width, HarfBuzz shaping, Fontconfig fallback, and a bounded glyph-ID atlas to M1's interactive Linux terminal; M2.5 adds measured write-path attribution and local performance hardening. It is not a daily-driver terminal emulator or a claim of full VT/xterm compatibility.

## Current scope

`make run` opens a native GLFW/Vulkan window and starts `$SHELL` when it is an absolute path, otherwise `/bin/sh`. An explicit child follows `--`:

```sh
make run
make run ARGS='-- /usr/bin/printf "\033[31mred\033[0m\n"'
```

The child receives `TERM=kiwi` and `TERMINFO=$PWD/.build/terminfo`. Kiwi owns the version-controlled [terminfo source](terminfo/kiwi.ti); build and inspect it with:

```sh
make terminfo
TERMINFO="$PWD/.build/terminfo" infocmp kiwi
```

The entry honestly advertises 16 colours, cursor movement, erasing/editing, scrolling margins, alternate screen, basic SGR, and application cursor keys. The parser/state can represent 256-colour and RGB SGR values, but Kiwi does not advertise truecolour with `COLORTERM` in M1.

M1 supports a documented subset of C0/ESC/CSI/OSC, primary/alternate screens, margins, deferred autowrap, bounded primary scrollback, basic keyboard encoding, PTY resize propagation, DSR/DA replies, and title updates. The exact contract and unsupported cases are in [docs/CONFORMANCE.md](docs/CONFORMANCE.md).

## Fedora prerequisites

Kiwi currently supports Linux x86_64. On Fedora 43:

```sh
sudo dnf install luajit gcc make curl unzip pkgconf-pkg-config ncurses \
  glfw-devel freetype-devel harfbuzz-devel mesa-vulkan-drivers vulkan-loader-devel \
  vulkan-tools fontconfig google-noto-sans-mono-fonts
```

`make bootstrap` validates the local tools, GLFW/FreeType/HarfBuzz/Fontconfig metadata, `tic`/`infocmp`, and the pinned official wgpu-native archive.

## Commands

```sh
make bootstrap                         # validate prerequisites and fetch pinned wgpu-native
make check                             # deterministic LuaJIT, PTY, terminfo, and syntax checks
make test                              # deterministic unit, conformance, replay, and parser-bench tests
make test-pty                          # deterministic real-PTY integration tests
make run                               # launch the default shell
make demo                              # retain the M0 synthetic renderer mode
make smoke                             # bounded native live-terminal GPU smoke test; skips without display
make bench                             # M1.5 layered CPU pipeline benchmark; retains M0 synthetic data separately
make bench-burst                       # real-PTY burst, response, latency, and memory regression checks
make bench-text                        # M2 Unicode, shaping, fallback, glyph-cache, and row-layout CPU measurements
make bench-write                       # M2.5 parser/cluster/damage/shaping/atlas write-path attribution
make bench-text-stress                 # M2 bounded atlas/fallback/grid/memory stress check
make profile-text                      # ignored LuaJIT sampling profile; add KIWI_PROFILE_TRACE=1 for -jv traces
make replay REPLAY=path/session.jsonl  # headless deterministic replay and canonical snapshot
make vttest                            # launch vttest if installed, in an interactive graphical session
```

During a live session, `F2` toggles dirty-cell highlighting, `F3` cell boundaries, and `F4` the once-per-second diagnostic report. `Shift+PageUp` and `Shift+PageDown` navigate primary-screen history locally. `--inspect` reports text metadata at the final cursor; `--inspect=ROW,COLUMN` selects a zero-based cell and includes shaped-glyph mapping. `KIWI_AMBIGUOUS_WIDTH=1|2`, `KIWI_FONT`, `KIWI_FONT_FAMILY`, `KIWI_FONT_PX`, `KIWI_LIGATURES=1`, and `KIWI_CALT=1` configure the startup text system. Font faces/glyph cache are rebuilt when GLFW content scale changes. Other supported keys encode terminal input; closing the window shuts down the child process group.

WGSL hot reload is development-only: start Kiwi with `KIWI_DEVELOPMENT=1` and an explicit `KIWI_DEV_SHADER_PATH=/absolute/or/relative/terminal.wgsl`. Kiwi polls only that file at a 250 ms cadence; `F5` forces an immediate reload. It builds replacement modules and pipelines for every affected pass before swapping any active pipeline. Rejected source remains on disk for correction, while the last known-good pipelines stay active and the reason is reported to stderr. Without both settings, `F5` performs no shader compilation and production continues to use the bundled WGSL.

## Replay

`--record path.jsonl` records resize, PTY output, and input events at the terminal-kernel boundary. `--replay path.jsonl` performs headless state replay without a PTY or GPU. Records are versioned JSONL with base64 byte payloads; [a small sanitized live-session fixture](src/tests/fixtures/replay/live-color-cr.jsonl) is tested in the deterministic suite.

## Deliberate limits

M2 implements Unicode 17 EGCs, deterministic width, combining-mark handling, HarfBuzz shaping, and Fontconfig fallback. It does not implement bidi, Unicode line breaking, a runtime width-policy reflow, color emoji, a multiformat/multipage glyph atlas, mouse reporting, clipboard, hyperlinks, images, OSC shell integration, full reset/DECSTR coverage, every SGR rendering effect, or full xterm/VT100 certification. Unsupported OSC/DCS/APC/PM/SOS data is consumed safely rather than rendered as text. Unknown-sequence counts and bounded, structured samples are available through F4 diagnostics. The precise text contract is in [docs/TEXT.md](docs/TEXT.md).

The renderer remains structured: terminal cells and damage feed background, glyph, and cursor GPU passes; it does not parse escape sequences or render a terminal bitmap. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/BENCHMARKS.md](docs/BENCHMARKS.md), [docs/ROADMAP.md](docs/ROADMAP.md), and [docs/adr](docs/adr).
