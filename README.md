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
  glfw-devel freetype-devel harfbuzz-devel libpng-devel mesa-vulkan-drivers vulkan-loader-devel \
  vulkan-tools fontconfig google-noto-sans-mono-fonts
```

`make bootstrap` validates the local tools, GLFW/FreeType/HarfBuzz/Fontconfig metadata, `tic`/`infocmp`, and the pinned official wgpu-native archive.

## Local release artifact

`make release` creates `dist/kiwi-<version>-linux-x86_64.tar.gz` and its
adjacent SHA-256 file. The archive contains the Lua sources, native surface
bridge, pinned wgpu-native runtime, compiled `kiwi` terminfo, a launcher, and
`metadata.json` with the version, Git revision, source-date epoch, dependency
identity, and runtime-library requirements. It neither uploads nor publishes
anything. `make release` refuses a dirty checkout, so a persistent artifact is
always attributable to its recorded revision. `make release-check` builds twice
in a disposable directory with normalized archive metadata,
compares the byte streams, verifies the checksum, extracts the archive, and
confirms that its launcher reports release mode even when
`KIWI_DEVELOPMENT=1` is inherited.

To verify a retained artifact from the checkout root, use its adjacent
checksum from inside `dist/`:

```sh
release="kiwi-$(< VERSION)-linux-x86_64"
(cd dist && sha256sum --check "$release.tar.gz.sha256")
tar -xzf "dist/$release.tar.gz"
./"$release"/bin/kiwi --version
```

The archive is for Linux x86_64 only and still needs a system LuaJIT plus GLFW,
FreeType, HarfBuzz, Fontconfig, libpng, a Vulkan loader/driver, and the normal
display-server runtime. `kiwi --version` reports the artifact version and
revision without opening a window. A release artifact forces `KIWI_RELEASE=1`:
shader hot reload, pass metrics/budgets, GPU timestamp instrumentation,
renderer inspector settings, and F2–F5 debug shortcuts remain off. It does not
publish a GitHub release or claim portability beyond the documented Linux
environment.

Nix users can build the pinned Linux x86_64 package with `nix build .#kiwi`,
enter the matching development environment with `nix develop`, and run the
flake verification subset with `nix flake check`; see [NIX.md](docs/NIX.md) for
the pinned-input update procedure and driver/display limitations.

Arch/AUR publication is currently deferred: the project has no publicly
fetchable immutable source archive, release tag, license file, or authorized
AUR maintainer. The evidence and prerequisites for revisiting that decision
are in [AUR.md](docs/AUR.md).

For the supported source and artifact launch paths, environment-only
configuration, safe-mode troubleshooting, maintained render-extension examples,
and support boundaries, see the [user guide](docs/USER_GUIDE.md).

## Commands

```sh
make bootstrap                         # validate prerequisites and fetch pinned wgpu-native
make check                             # deterministic LuaJIT, PTY, terminfo, and syntax checks
make release                           # create a local, checksummed Linux x86_64 release-mode artifact
make release-check                     # rebuild the artifact twice and verify byte identity, metadata, terminfo, and release mode
make doctor                            # local, privacy-bounded human-readable support report
make doctor ARGS='--json --bundle kiwi-support.json' # machine-readable report and explicit local bundle
make test                              # deterministic unit, conformance, replay, and parser-bench tests
make test-fuzz                         # bounded seed-reproducible parser/state property and hostile-input suite
make fuzz                              # longer local parser/state fuzz run
make test-pty                          # deterministic real-PTY integration tests
make run                               # launch the default shell
make demo                              # retain the M0 synthetic renderer mode
make smoke                             # bounded native live-terminal GPU smoke test; skips without display
make timestamp-probe                   # opt-in timestamp-query capability/readback probe; does not instrument frames
make gpu-timing-smoke                   # bounded live per-pass GPU timestamp/readback smoke test
make kitty-graphics-smoke               # bounded native direct-PNG Kitty graphics composition smoke test
make budget-smoke                       # live advisory-budget warning smoke test
make pacing                             # bounded native PTY-output/present-call pacing report; skips without display
make power-smoke                        # bounded redraw scheduler observation; skips without display
make device-soak                        # CI-friendly deterministic pass/resource/extension lifecycle soak
make device-soak-native                 # bounded native resize/minimize/restore + extension-churn soak; skips without display
make device-loss-sim                    # bounded native device-recreation policy simulation; skips without display
make bench                             # M1.5 layered CPU pipeline benchmark; retains M0 synthetic data separately
make bench-burst                       # real-PTY burst, response, latency, and memory regression checks
make bench-text                        # M2 Unicode, shaping, fallback, glyph-cache, and row-layout CPU measurements
make text-corpus-review                # M8 deterministic text-corpus manifest with host/driver inventory
make text-corpus-demo                  # bounded native visual review of that same corpus
make text-lab                          # M8 atlas-baseline laboratory report; BACKENDS=atlas,msdf adds requested candidates
make text-lab-demo BACKEND=atlas        # bounded native corpus review through an explicit laboratory backend request
make slug-feasibility                  # M8 native Slug prerequisite probe; currently exits 2 because libharfbuzz-gpu is unavailable
make bench-write                       # M2.5 parser/cluster/damage/shaping/atlas write-path attribution
make bench-text-stress                 # M2 bounded atlas/fallback/grid/memory stress check
make bench-longrun                     # M9 history, fragmented-update, resize, and text-cache pressure profile
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

GPU faults have an explicit bounded policy. A transient surface-acquire or present status requests a surface reconfiguration on the next render attempt. A `wgpu device lost` callback tears down all renderer-owned resources and retries once by recreating the WGPU context and renderer against the existing window, terminal state, PTY, and font. A second device loss, a failed recreation, or another native GPU error exits after printing a bounded diagnostic with backend, vendor, adapter, and last renderer pass/phase. Kiwi does not claim transparent recovery for every driver. `renderer.diagnostics.gpu_recovery` retains at most 16 records with at most 2,048 message bytes each, and contains no terminal, clipboard, command, or display content. `make device-loss-sim` exercises the policy path with a synthetic marker; it is not evidence that a driver delivered the WGPU device-loss callback.

Kiwi coalesces terminal, resize, cursor, selection, search, Kitty-image, configuration, and extension redraw reasons. It only presents when work is pending or a bounded animation deadline is due; successful presentation clears consumed reasons.

The redraw policy uses a 50 ms maximum GLFW wait while a window is visible, because this Linux path must also service a nonblocking PTY without a combined GLFW/PTY wait primitive. Terminal output, keyboard input, resize, local interaction, and configuration invalidate immediately; a visible blinking cursor adds one 0.5-second deadline after presentation. A minimized window retains pending terminal state but does not acquire or present a surface, extends its maximum wait to 250 ms, and reconfigures/presents after restoration. Synchronized output similarly retains work without presenting. Trusted extension animation requests remain bounded by `KIWI_EXTENSION_MAX_ANIMATION_HZ` (1/60–60 Hz). `make power-smoke` emits a bounded local aggregate report of loop wakeups, states, rendered frames, deferred presentation, output/input event counts, and invalidation reasons; its fixed synthetic PTY input is labeled separately from physical keyboard input. It does not measure battery, GPU energy, compositor work, display scan-out, or portable occlusion.

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

Kiwi exposes a bounded, platform-neutral semantic accessibility model for
future adapters, but it has no implemented AT-SPI, NSAccessibility, or UI
Automation bridge and therefore makes no screen-reader support claim. The
contract and adapter procedure are in [ACCESSIBILITY.md](docs/ACCESSIBILITY.md).

Kiwi currently supports Linux x86_64 only. Windows DX12/ConPTY feasibility was
researched from a Linux cross-build environment but not run on a Windows host;
no Windows build or runtime support is claimed. The required native seams and
validation matrix are in [ADR 0038](docs/adr/0038-windows-native-feasibility.md).

macOS Metal/Cocoa feasibility was also assessed without a macOS host or target
artifacts. The pinned header exposes a prospective Metal surface seam, but no
macOS build or runtime support is claimed; see [ADR
0039](docs/adr/0039-macos-native-feasibility.md).

## Replay

`--record path.jsonl` records resize, PTY output, and input events at the terminal-kernel boundary. `--replay path.jsonl` performs headless state replay without a PTY or GPU. Records are versioned JSONL with base64 byte payloads; [a small sanitized live-session fixture](src/tests/fixtures/replay/live-color-cr.jsonl) is tested in the deterministic suite.

OSC 7 `file://` current-directory updates and OSC 133 A/B/C/D shell markers are
parsed into bounded replayable facts and an opaque prompt/command/output
lifecycle when a cooperative shell emits them. Versioned Bash, Zsh, and fish
assets are available as an explicit, reversible opt-in; they are inactive
unless the user sources them in an interactive `TERM=kiwi` shell with
`KIWI_SHELL_INTEGRATION=1`. They do not enable path access, command execution,
durable cross-session persistence, a renderer resource, diagnostics output, or
a UI. Opaque row associations move through bounded scrollback and degrade
explicitly when evicted. See [shell integration v1](docs/SHELL_INTEGRATION.md),
[ADR 0027](docs/adr/0027-bounded-shell-integration-metadata.md),
[ADR 0028](docs/adr/0028-stable-command-region-lifecycle.md), and
[ADR 0029](docs/adr/0029-command-region-retention-and-snapshot-boundary.md).

For retained primary history, `Ctrl+Alt+P/C/O` move backward through prompt,
command, and output boundaries; add Shift to move forward. The bindings are
local and status-gated during editing search, Kitty keyboard mode, or alternate
screen use. They only move the history viewport and never send PTY input,
copy text, execute a command, or expose a command UI. See
[ADR 0030](docs/adr/0030-command-region-navigation.md).

`KIWI_COMMAND_REGIONS=1` enables an opt-in, subtle separator pass for visible
command/output boundaries. It receives only a bounded content-free descriptor;
the same typed resource is available to trusted local extension observers, but
API v1 grants them no drawing or GPU-allocation capability. See
[ADR 0032](docs/adr/0032-bounded-command-region-render-resource.md).
`KIWI_COMMAND_REGION_COLOR` accepts `#RRGGBB` or `#RRGGBBAA` and defaults to
`#88C0D055`.

Kitty graphics supports a bounded direct-PNG APC-G transfer/cache, explicit
terminal-cell placements, and renderer-owned WGPU image composition. Negative
z-index images render behind selection/text; zero and positive z-index images
render after glyphs and before the cursor. Its exact parser, lifecycle, limits,
decoder/cache ownership, fixture, and composition boundary are in
[KITTY_GRAPHICS.md](docs/KITTY_GRAPHICS.md) and
[ADR 0033](docs/adr/0033-kitty-graphics-parser-state-foundation.md).

## Deliberate limits

M2 implements Unicode 17 EGCs, deterministic width, combining-mark handling, HarfBuzz shaping, Fontconfig fallback, and the documented SGR mouse/focus subset. M4 adds local Linux clipboard copy/paste, bounded exact scrollback search, and safe OSC 8 hyperlinks, but not primary selections, rich formats, automatic synchronization, OSC 52 writes, regular expressions, full-text indexing, link previews, or file/custom-scheme link activation. M6 currently adds bounded OSC 7/133 metadata, opaque command lifecycles, bounded row associations, primary-history region navigation, opt-in Bash/Zsh/fish scripts, and bounded direct-PNG Kitty image composition, but not automatic shell setup, durable cross-session persistence, path access, execution, command output summarization, a command palette, or a region UI. Kiwi does not implement bidi, Unicode line breaking, a runtime width-policy reflow, color emoji, a multiformat/multipage glyph atlas, legacy/pixel/gesture mouse protocols, arbitrary image transforms or editing, full reset/DECSTR coverage, every SGR rendering effect, or full xterm/VT100 certification. Unsupported OSC/DCS/APC/PM/SOS data is consumed safely rather than rendered as text, except for the documented direct-PNG Kitty APC-G transfer/cache, cell-placement, and composition subset. OSC 52 remains explicitly default-denied; its policy is in [ADR 0020](docs/adr/0020-clipboard-and-osc52-security-policy.md). Unknown-sequence counts and bounded, structured samples are available through F4 diagnostics. The precise text contract is in [docs/TEXT.md](docs/TEXT.md).

The renderer remains structured: terminal cells and damage feed background, selection, search, hyperlink-aware glyph, and cursor GPU passes; it does not parse escape sequences or render a terminal bitmap. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/BENCHMARKS.md](docs/BENCHMARKS.md), [docs/ROADMAP.md](docs/ROADMAP.md), and [docs/adr](docs/adr).
