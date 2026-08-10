# Kiwi

Kiwi is a rendering-first terminal research platform. M2 adds Unicode 17 extended grapheme clusters, deterministic terminal width, HarfBuzz shaping, Fontconfig fallback, and a bounded glyph-ID atlas to M1's interactive Linux terminal; M2.5 adds measured write-path attribution and local performance hardening. It is not a daily-driver terminal emulator or a claim of full VT/xterm compatibility.

## Current scope

`make run` opens a native GLFW/Vulkan window and starts `$SHELL` when it is an absolute path, otherwise `/bin/sh`. An explicit child follows `--`:

```sh
make run
make run ARGS='-- /usr/bin/printf "\033[31mred\033[0m\n"'
```

The child receives `TERM=kiwi` and `TERMINFO=$PWD/.build/terminfo`; Kiwi also unsets inherited `COLORTERM` so it does not accidentally advertise a capability that the terminfo entry withholds. Kiwi owns the version-controlled [terminfo source](terminfo/kiwi.ti); build and inspect it with:

```sh
make terminfo
TERMINFO="$PWD/.build/terminfo" infocmp kiwi
```

The entry honestly advertises 16 colours, cursor movement, erasing/editing, scrolling margins, alternate screen, basic SGR, and application cursor keys. The parser/state can represent 256-colour and RGB SGR values, but Kiwi advertises neither truecolour terminfo extensions nor `COLORTERM`; see the evidence-gated decision in [CONFORMANCE.md](docs/CONFORMANCE.md#truecolour-decision).

M1 supports a documented subset of C0/ESC/CSI/OSC, primary/alternate screens, margins, deferred autowrap, bounded primary scrollback, legacy keyboard encoding plus the negotiated Kitty disambiguation subset, PTY resize propagation, DSR/DA replies, and title updates. The exact contract and unsupported cases are in [docs/CONFORMANCE.md](docs/CONFORMANCE.md).

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
make test-fuzz                         # bounded seed-reproducible parser/state property and hostile-input suite
make fuzz                              # longer local parser/state fuzz run
make test-pty                          # deterministic real-PTY integration tests
make run                               # launch the default shell
make demo                              # retain the M0 synthetic renderer mode
make smoke                             # bounded native live-terminal GPU smoke test; skips without display
make timestamp-probe                   # opt-in timestamp-query capability/readback probe; does not instrument frames
make gpu-timing-smoke                   # bounded live per-pass GPU timestamp/readback smoke test
make budget-smoke                       # live advisory-budget warning smoke test
make bench                             # M1.5 layered CPU pipeline benchmark; retains M0 synthetic data separately
make bench-burst                       # real-PTY burst, response, latency, and memory regression checks
make bench-text                        # M2 Unicode, shaping, fallback, glyph-cache, and row-layout CPU measurements
make bench-write                       # M2.5 parser/cluster/damage/shaping/atlas write-path attribution
make bench-text-stress                 # M2 bounded atlas/fallback/grid/memory stress check
make profile-text                      # ignored LuaJIT sampling profile; add KIWI_PROFILE_TRACE=1 for -jv traces
make replay REPLAY=path/session.jsonl  # headless deterministic replay and canonical snapshot
make vttest                            # launch vttest if installed, in an interactive graphical session
make conformance-evidence              # audit terminfo, local tmux behavior, and native top when available
```

During a live session, `F2` toggles dirty-cell highlighting, `F3` cell boundaries, and `F4` the once-per-second diagnostic report. `Shift+PageUp` and `Shift+PageDown` navigate primary-screen history locally. `Ctrl+Shift+F` opens a scrollback-search query in the window title; type the exact UTF-8 query and press `Enter`, then use `Ctrl+Shift+G`/`Ctrl+Shift+R` for forward/backward navigation or `Escape` to clear it. `Ctrl+primary-click` opens a safe OSC 8 link under the pointer and `Ctrl+Shift+O` opens one under the visible cursor; `http`, `https`, and `mailto` are the only allowed schemes, and `KIWI_HYPERLINK_COLOR` controls the underline. `--inspect` reports text metadata at the final cursor; `--inspect=ROW,COLUMN` selects a zero-based cell and includes shaped-glyph mapping. `KIWI_AMBIGUOUS_WIDTH=1|2`, `KIWI_FONT`, `KIWI_FONT_FAMILY`, `KIWI_FONT_PX`, `KIWI_LIGATURES=1`, and `KIWI_CALT=1` configure the startup text system. Font faces/glyph cache are rebuilt when GLFW content scale changes. Other supported keys encode terminal input; closing the window shuts down the child process group.

WGSL hot reload is development-only: start Kiwi with `KIWI_DEVELOPMENT=1` and an explicit `KIWI_DEV_SHADER_PATH=/absolute/or/relative/terminal.wgsl`. Kiwi polls only that file at a 250 ms cadence; `F5` forces an immediate reload. It builds replacement modules and pipelines for every affected pass before swapping any active pipeline. Rejected source remains on disk for correction, while the last known-good pipelines stay active and the reason is reported to stderr. Without both settings, `F5` performs no shader compilation and production continues to use the bundled WGSL.

`KIWI_PASS_METRICS=1` enables bounded per-pass CPU preparation and encoding samples in the renderer diagnostics. The default leaves this instrumentation disabled.

`KIWI_PASS_BUDGETS=1` enables advisory rolling-window budgets declared by render passes. A declaration may set `cpu_ms`, `gpu_ticks`, `allocation_bytes`, `cadence_hz`, and `window`; results are plain structured diagnostics and inspector status, never an automatic throttle or pass shutdown. CPU budgets remain usable when GPU timestamps are unavailable. API v1 has no extension-owned GPU allocation capability, so allocation accounting is explicitly unavailable rather than estimated. `KIWI_PASS_BUDGETS_REPORT=1` prints final warnings for development validation.

`KIWI_GPU_TIMESTAMPS=1` requests the optional `TimestampQuery` feature for the renderer device. When enabled on a supporting adapter, Kiwi keeps at most three asynchronous readbacks in flight and reports delayed per-pass GPU tick deltas; it never waits for a result in the present path. Device-feature request failures fall back to the normal device and report the reason in diagnostics. `KIWI_GPU_TIMESTAMPS_REPORT=1` prints the final diagnostic snapshot for development validation.

Optional render extensions are trusted local modules. Set `KIWI_RENDER_EXTENSIONS` to a comma-separated list of module names; each module must return a registration function, or a table with a `register` function. Kiwi has no built-in network discovery or installation. Start with `--no-extensions` to bypass that list entirely, including module loading:

```sh
KIWI_RENDER_EXTENSIONS='local.frame_observer,local.overlay' make run
make run ARGS='--no-extensions -- /bin/sh'
```

Each registration is preflighted independently against the complete built-in pass graph. A rejected registration is discarded and recorded in bounded `renderer.diagnostics.extensions` data. An optional pass that later fails during initialization, encoding, resize, or shutdown is disabled for that renderer lifetime; the built-in background, glyph, and cursor passes continue where the renderer can safely present. This is fault containment for trusted local code, not a sandbox for untrusted Lua or native modules.

Extension limits are enforced before registration or scheduling. `KIWI_EXTENSION_MAX_PASSES` sets the positive-integer optional-pass cap (default `32`); `KIWI_EXTENSION_MAX_ANIMATION_HZ` sets the maximum optional redraw rate from `1/60` through `60` Hz (default `60`). A registration that would exceed the pass cap is discarded as a whole. An animation request with a delay below the configured cadence is rejected without scheduling a redraw. Safe mode bypasses both extension module loading and extension-cap environment parsing.

API v1 permits no extension-owned GPU buffers, textures, shader modules, or GPU-memory accounting: those limits are fixed at zero until a separately versioned capability exists. One callback failure disables its optional pass, while diagnostic history is bounded to 32 records of at most 4,096 bytes each. The full plain-data cap state, including unavailable capability markers, is in `renderer.diagnostics.extensions.limits`.

Kiwi coalesces terminal, resize, cursor, selection, search, configuration, and extension redraw reasons. It only presents when work is pending or a bounded animation deadline is due; successful presentation clears consumed reasons.

DECSCUSR cursor styles and DEC synchronized output are supported as documented
in [the conformance matrix](docs/CONFORMANCE.md). `CSI ? 2026 h` defers
intermediate terminal presentation until `CSI ? 2026 l` or RIS; neither mode
is advertised through terminfo.

SGR mouse tracking (1000/1002/1003 with 1006) and focus reporting (1004) are
also supported, with exact scope and local-selection precedence in the
[conformance matrix](docs/CONFORMANCE.md). Selected cells receive a
pre-glyph alpha highlight; `KIWI_SELECTION_COLOR` accepts `#RRGGBB` or
`#RRGGBBAA`. The current scrollback-search result receives a second pre-glyph
alpha highlight; `KIWI_SEARCH_COLOR` has the same format. Neither input
capability is advertised through terminfo.

`Ctrl+Shift+C` copies a visible selection and `Ctrl+Shift+V` pastes the ordinary
Linux clipboard through GLFW. Clipboard reads/writes are limited to 1 MiB;
paste rejects invalid UTF-8 or NUL-containing bridge data and uses bracketed-paste framing only
when the terminal has enabled DECSET 2004. OSC 52 remains default-denied.

Kiwi has no production IME/preedit bridge. GLFW character callbacks continue to
provide committed Unicode text; the researched Wayland text-input boundary and
detached lifecycle spike are documented in
[ADR 0025](docs/adr/0025-wayland-ime-and-window-stack.md).

## Replay

`--record path.jsonl` records resize, PTY output, and input events at the terminal-kernel boundary. `--replay path.jsonl` performs headless state replay without a PTY or GPU. Records are versioned JSONL with base64 byte payloads; [a small sanitized live-session fixture](src/tests/fixtures/replay/live-color-cr.jsonl) is tested in the deterministic suite.

OSC 7 `file://` current-directory updates and OSC 133 A/B/C/D shell markers are
parsed into bounded replayable facts and an opaque prompt/command/output
lifecycle when a cooperative shell emits them. They do not enable shell setup,
path access, command execution, navigation, durable cross-session persistence,
a renderer resource, diagnostics output, or a UI. Opaque row associations move
through bounded scrollback and degrade explicitly when evicted. The contracts
are [ADR 0027](docs/adr/0027-bounded-shell-integration-metadata.md),
[ADR 0028](docs/adr/0028-stable-command-region-lifecycle.md), and
[ADR 0029](docs/adr/0029-command-region-retention-and-snapshot-boundary.md).

For retained primary history, `Ctrl+Alt+P/C/O` move backward through prompt,
command, and output boundaries; add Shift to move forward. The bindings are
local and status-gated during editing search, Kitty keyboard mode, or alternate
screen use. They only move the history viewport and never send PTY input,
copy text, execute a command, or expose a command UI. See
[ADR 0030](docs/adr/0030-command-region-navigation.md).

## Deliberate limits

M2 implements Unicode 17 EGCs, deterministic width, combining-mark handling, HarfBuzz shaping, Fontconfig fallback, and the documented SGR mouse/focus subset. M4 adds local Linux clipboard copy/paste, bounded exact scrollback search, and safe OSC 8 hyperlinks, but not primary selections, rich formats, automatic synchronization, OSC 52 writes, regular expressions, full-text indexing, link previews, or file/custom-scheme link activation. M6 currently adds bounded OSC 7/133 metadata, opaque command lifecycles, bounded row associations, and primary-history region navigation, but not shell setup, durable cross-session persistence, path access, execution, command output summarization, rendering, diagnostics, a command palette, or a region UI. Kiwi does not implement bidi, Unicode line breaking, a runtime width-policy reflow, color emoji, a multiformat/multipage glyph atlas, legacy/pixel/gesture mouse protocols, images, full reset/DECSTR coverage, every SGR rendering effect, or full xterm/VT100 certification. Unsupported OSC/DCS/APC/PM/SOS data is consumed safely rather than rendered as text. OSC 52 remains explicitly default-denied; its policy is in [ADR 0020](docs/adr/0020-clipboard-and-osc52-security-policy.md). Unknown-sequence counts and bounded, structured samples are available through F4 diagnostics. The precise text contract is in [docs/TEXT.md](docs/TEXT.md).

The renderer remains structured: terminal cells and damage feed background, selection, search, hyperlink-aware glyph, and cursor GPU passes; it does not parse escape sequences or render a terminal bitmap. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/BENCHMARKS.md](docs/BENCHMARKS.md), [docs/ROADMAP.md](docs/ROADMAP.md), and [docs/adr](docs/adr).
