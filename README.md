# Kiwi

Kiwi is a rendering-first terminal research platform. M2 adds Unicode 17 extended grapheme clusters, deterministic terminal width, HarfBuzz shaping, Fontconfig fallback, and a bounded glyph-ID atlas to M1's interactive Linux and macOS terminal; M2.5 adds measured write-path attribution and local performance hardening. Kiwi now has an explicit daily-driver compatibility goal for its documented targets, but it is still experimental and does not claim full VT/xterm or Ghostty parity; see [KIWI-TO-GHOSTTY.md](KIWI-TO-GHOSTTY.md) and the [daily-driver compatibility ledger](docs/DAILY_DRIVER_COMPATIBILITY.md).

## Current scope

`make run` opens a native GLFW window backed by Vulkan on Linux or Metal on macOS, then starts `$SHELL` when it is an absolute path, otherwise `/bin/sh`. An explicit child follows `--`:

```sh
make run
make run ARGS='-- /usr/bin/printf "\033[31mred\033[0m\n"'
```

The child receives `TERM=kiwi` and `TERMINFO=$PWD/.build/terminfo`; Kiwi also unsets inherited `COLORTERM` so it does not accidentally advertise a capability that the terminfo entry withholds. Kiwi owns the version-controlled [terminfo source](terminfo/kiwi.ti); build and inspect it with:

```sh
make terminfo
TERMINFO="$PWD/.build/terminfo" infocmp kiwi
```

The entry honestly advertises 16 colours, cursor movement, erasing/editing, scrolling margins, alternate screen, DEC Special Graphics line drawing, basic SGR, and application cursor/keypad input. The parser/state can represent 256-colour and RGB SGR values, but Kiwi advertises neither truecolour terminfo extensions nor `COLORTERM`; see the evidence-gated decision in [CONFORMANCE.md](docs/CONFORMANCE.md#truecolour-decision).

M1 supports a documented subset of C0/ESC/CSI/OSC, primary/alternate screens, vertical and VT420 left/right margins, deferred autowrap plus xterm reverse-wraparound, bounded primary scrollback, legacy keyboard encoding plus negotiated Kitty keyboard flags 1/2/8/16, PTY resize propagation, DSR/DA plus read-only geometry replies, and title updates. The exact contract and unsupported cases are in [docs/CONFORMANCE.md](docs/CONFORMANCE.md).

## Linux prerequisites

The Linux support target is x86_64. On Fedora 43:

```sh
sudo dnf install luajit gcc make curl unzip pkgconf-pkg-config ncurses \
  glib2-devel glfw-devel freetype-devel harfbuzz-devel giflib libpng-devel mesa-vulkan-drivers vulkan-loader-devel \
  vulkan-tools fontconfig google-noto-sans-mono-fonts
```

`make bootstrap` validates the local tools, GLFW/FreeType/HarfBuzz/Fontconfig metadata, `tic`/`infocmp`, and the pinned official wgpu-native archive.

## macOS prerequisites

The macOS source target is verified on macOS 26.5.2 Apple Silicon. Install the source dependencies with Homebrew, then build and run from the checkout:

```sh
brew install luajit glfw freetype harfbuzz fontconfig giflib libpng pkgconf ncurses
make check
make run
```

Kiwi uses GLFW's Cocoa window, a `CAMetalLayer` WebGPU surface, and Metal; it retains FreeType/HarfBuzz for rasterization and shaping while Fontconfig provides the current font-discovery/fallback implementation. The matching macOS x86_64 bootstrap path exists but has not been validated on an Intel Mac. See [MACOS.md](docs/MACOS.md) for the supported boundary and verification status.

## Local release artifact

`make release` creates `dist/kiwi-<version>-<target>.tar.gz` and its
adjacent SHA-256 file. The archive contains the Lua sources, native surface
bridge, pinned wgpu-native runtime, compiled `kiwi` terminfo, a launcher, and
`metadata.json` with the version, Git revision, source-date epoch, dependency
identity, and runtime-library requirements. It neither uploads nor publishes
anything. `make release` refuses a dirty checkout, so a persistent artifact is
always attributable to its recorded revision. `make release-check` builds twice
in a disposable directory with normalized archive metadata,
compares the byte streams, verifies the checksum, extracts the archive, and
confirms that its launcher reports release mode even when
`KIWI_DEVELOPMENT=1` is inherited. On macOS, it also launches the extracted
`Kiwi.app` through LaunchServices and verifies that the packaged terminal
process starts before it is stopped.

To verify a retained artifact from the checkout root, use its adjacent
checksum from inside `dist/`:

```sh
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) target=linux-x86_64 ;;
  Darwin-arm64) target=macos-arm64 ;;
  Darwin-x86_64) target=macos-x86_64 ;;
  *) print -u2 "unsupported Kiwi release target"; exit 1 ;;
esac
release="kiwi-$(< VERSION)-$target"
(cd dist && sha256sum --check "$release.tar.gz.sha256")
tar -xzf "dist/$release.tar.gz"
./"$release"/bin/kiwi --version
```

The Linux archive needs a system LuaJIT plus GLib/GIO, GLFW, FreeType, HarfBuzz, Fontconfig, giflib, libpng, a Vulkan loader/driver, and a Wayland or X11 runtime. The verified macOS arm64 archive needs the corresponding Homebrew runtime dependencies and includes `Kiwi.app` as a convenience launcher. Its executable is deterministically ad-hoc signed so LaunchServices can launch it, but it has no Developer ID signature or notarization. `kiwi --version` reports the artifact version and
revision without opening a window. A release artifact forces `KIWI_RELEASE=1`:
shader hot reload, pass metrics/budgets, GPU timestamp instrumentation,
renderer inspector settings, and F2–F5 debug shortcuts remain off. It does not
publish a GitHub release or claim portability beyond the documented Linux and
macOS environments.

`make libkiwi-vt` separately produces the reproducible, renderer-free
`libkiwi-vt` SDK described in [docs/LIBKIWI.md](docs/LIBKIWI.md). It contains
the experimental LuaJIT core and a narrow Linux x86_64 or macOS arm64 C shared library for
byte input, resize, logical-text projection, logical cell/grid render updates,
terminal-mode-aware text/key/mouse/focus/paste encoding, and queued terminal
responses/effects. It is pre-1.0 and makes no ABI-stability claim.
Nix users can build the same SDK surface with `nix build .#libkiwi-vt`.

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
make release                           # create a local, checksummed release-mode artifact for the current target
make release-check                     # rebuild the artifact twice and verify byte identity, metadata, terminfo, and release mode
make doctor                            # local, privacy-bounded human-readable support report
make doctor ARGS='--json --bundle kiwi-support.json' # machine-readable report and explicit local bundle
make test                              # deterministic unit, conformance, replay, and parser-bench tests
make test-fuzz                         # bounded seed-reproducible parser/state property and hostile-input suite
make fuzz                              # longer local parser/state fuzz run
make test-pty                          # deterministic real-PTY integration tests
make run                               # launch the default shell
make demo                              # retain the M0 synthetic renderer mode
make vt-demo                           # renderer-free libkiwi-vt projection; reads terminal bytes from stdin
make libkiwi-vt-c                      # build the unpackaged experimental libkiwi-vt C SDK
make libkiwi-vt-check                  # reproducible core SDK archive, Lua/C consumer, and media-boundary check
make compatibility                     # machine-readable versioned terminal compatibility manifest
make kiwi-ssh SSH_ARGS='-- user@host'  # install private remote terminfo then open an SSH shell
make smoke                             # bounded native live-terminal GPU smoke test; skips without Linux display
make timestamp-probe                   # opt-in timestamp-query capability/readback probe; does not instrument frames
make gpu-timing-smoke                   # bounded live per-pass GPU timestamp/readback smoke test
make kitty-graphics-smoke               # bounded native direct-PNG Kitty graphics composition smoke test
make kitty-animation-smoke              # bounded native GIF/APNG playback and frame-texture update smoke test
make new-window-smoke                   # bounded native same-process Ctrl+Shift+N window-manager smoke; skips without a display
make session-move-smoke                 # bounded native Ctrl+Shift+M live-PTY handoff between same-process windows
make layout-restore-smoke               # save a tab/split topology then restore it with fresh shells
make accessibility-smoke                # semantic accessibility checks plus platform-native availability report
make accessibility-provider-smoke       # live Linux AT-SPI registry/query/event smoke; macOS reports its manual boundary
make cocoa-smoke                        # macOS private-pasteboard, NSAccessibility, two Metal surfaces, and development-app launch smoke
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

Kiwi does not fetch media URLs while parsing terminal output. To explicitly
load one HTTPS PNG, APNG, or GIF from a source checkout, run this inside a Kiwi shell:

```sh
./script/kiwi-image https://images.example/kiwi.png
```

The helper follows HTTPS redirects only, limits downloaded data, validates the
PNG/APNG or GIF header and dimensions, then emits Kiwi's bounded direct-image
graphics stream. GIF and APNG frames play through one GPU texture per visible
image; video remains unsupported. It consumes the placement acknowledgement and
places the next prompt below the selected rectangle by default;
`--no-cursor-advance` is reserved for deliberate layered composition. Release
and Nix installs provide the same command as `kiwi-image`.

During a live session, `F2` toggles dirty-cell highlighting, `F3` cell boundaries, and `F4` the once-per-second diagnostic report. `F6` validates and reloads the active [configuration file](docs/USER_GUIDE.md#configuration); theme, renderer-color, and font changes take effect in the running session, while width-policy and scrollback-limit changes require a new session. `Shift+PageUp` and `Shift+PageDown` navigate primary-screen history locally. `Ctrl+Shift+F` opens a scrollback-search query in the window title; type the exact UTF-8 query and press `Enter`, then use `Ctrl+Shift+G`/`Ctrl+Shift+R` for forward/backward navigation or `Escape` to clear it. `Ctrl+primary-click` opens a safe OSC 8 link under the pointer and `Ctrl+Shift+O` opens one under the visible cursor; `http`, `https`, and `mailto` are the only allowed schemes. `--inspect` reports text metadata at the final cursor; `--inspect=ROW,COLUMN` selects a zero-based cell and includes shaped-glyph mapping. `--config PATH` selects a configuration file; otherwise Kiwi reads the documented XDG path and preserves environment overrides such as `KIWI_FONT_PX`. Font faces/glyph cache are rebuilt when GLFW content scale changes. Other supported keys encode terminal input; closing the window shuts down the child process group.

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

X10/normal/button/any mouse tracking (9/1000/1002/1003), X10, UTF-8 (1005),
URXVT (1015), SGR-cell (1006), and SGR-pixel (1016) coordinate encodings,
plus focus reporting (1004), are supported with exact scope and local-selection precedence in the
[conformance matrix](docs/CONFORMANCE.md). Selected cells receive a
pre-glyph alpha highlight; `KIWI_SELECTION_COLOR` accepts `#RRGGBB` or
`#RRGGBBAA`. The current scrollback-search result receives a second pre-glyph
alpha highlight; `KIWI_SEARCH_COLOR` has the same format. Neither input
capability is advertised through terminfo.

`Ctrl+Shift+T` opens a local tab and `Ctrl+Tab` cycles tabs. `Ctrl+Shift+Enter`
creates a vertical split, `Ctrl+Shift+J` creates a horizontal split, and
`Ctrl+Shift+W` closes the active pane (or its tab when it is the last pane).
`Ctrl+Shift+N` creates a same-process default-shell window; `Ctrl+Shift+M`
moves the active live session to a new window, and `Ctrl+Shift+Alt+M` moves it
to the next open window as a tab. `Ctrl+Shift+D` and `Ctrl+Shift+Alt+D` create
fresh default-shell counterparts. Each visible pane has its own terminal and
PTY, is resized to its cell-layout rectangle, and is rendered into a scissored
viewport in one shared WGPU frame. Primary-clicking a pane focuses it before
pointer input is routed to that terminal. Inactive tabs continue to service
their PTYs. `Ctrl+Shift+C` copies a visible selection and `Ctrl+Shift+V` pastes the ordinary
GLFW's platform clipboard bridge. Clipboard reads/writes are limited to 1 MiB;
paste rejects invalid UTF-8 or NUL-containing bridge data and uses bracketed-paste framing only
when the terminal has enabled DECSET 2004. OSC 52 remains default-denied unless `osc52-write = true` explicitly permits its bounded write-only subset.

Kiwi has no production IME/preedit bridge. GLFW character callbacks continue to
provide committed Unicode text; the researched Wayland text-input boundary and
detached lifecycle spike are documented in
[ADR 0025](docs/adr/0025-wayland-ime-and-window-stack.md).

Kiwi exposes a bounded semantic accessibility model, a Linux AT-SPI bridge, and a macOS NSAccessibility element
for the active pane. The native provider is registry/query tested, but no
end-to-end screen-reader session has been validated; Windows UI Automation is
unimplemented. The contract, limits, and smoke
commands are in [ACCESSIBILITY.md](docs/ACCESSIBILITY.md).

Kiwi supports Linux x86_64 and, on a verified source path, macOS arm64. Windows DX12/ConPTY feasibility was
researched from a Linux cross-build environment but not run on a Windows host;
no Windows build or runtime support is claimed. The required native seams and
validation matrix are in [ADR 0038](docs/adr/0038-windows-native-feasibility.md).

macOS Metal/Cocoa support is implemented through a narrow Objective-C bridge and validated on an Apple-silicon host. Intel macOS, VoiceOver behavior, IME preedit, Developer ID signing, and notarization remain unverified; see [ADR 0039](docs/adr/0039-macos-native-feasibility.md).

## Replay

`--record path.jsonl` records resize, PTY output, and input events at the terminal-kernel boundary. `--replay path.jsonl` performs headless state replay without a PTY or GPU. Records are versioned JSONL with base64 byte payloads; [a small sanitized live-session fixture](src/tests/fixtures/replay/live-color-cr.jsonl) is tested in the deterministic suite.

The experimental, renderer-neutral Lua terminal boundary is documented in
[LIBKIWI.md](docs/LIBKIWI.md). `make vt-demo` consumes terminal bytes from
standard input and emits a logical text projection without starting a PTY,
window, GPU, or font system; it is useful for integration and contract checks,
not visual rendering.

Kiwi automatically injects its reversible Bash, Zsh, fish, or Nushell integration only
for its initial default shell; it never edits a dotfile. Set
`shell-integration = none` in the configuration file, or
`KIWI_SHELL_INJECTION=none`, to disable injection. Use `make kiwi-ssh
SSH_ARGS='--ssh-option -p --ssh-option 2222 -- user@host'` for an explicit SSH
session that installs the compiled `kiwi` terminfo entry under the remote
user's private cache before starting the remote shell. Its failure fallback
uses `TERM=xterm-256color`; see
[SHELL_INTEGRATION.md](docs/SHELL_INTEGRATION.md) for limits and manual paths.

OSC 7 `file://` current-directory updates and OSC 133 A/B/C/D shell markers are
parsed into bounded replayable facts and an opaque prompt/command/output
lifecycle when a cooperative shell emits them. The initial default Bash, Zsh,
fish, or Nushell shell receives Kiwi's reversible versioned asset automatically; manual
source blocks remain available for switched shells and explicit-command
launches, where they require `KIWI_SHELL_INTEGRATION=1`. Neither route enables
path access, command execution, durable cross-session persistence, a renderer
resource, diagnostics output, or a UI. Opaque row associations move through
bounded scrollback and degrade explicitly when evicted. See [shell integration v1](docs/SHELL_INTEGRATION.md),
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

Kitty graphics supports a bounded direct-image APC-G transfer/cache for PNG,
APNG, and GIF, explicit
terminal-cell placements, and renderer-owned WGPU image composition. Negative
z-index images render behind selection/text; zero and positive z-index images
render after glyphs and before the cursor. Its exact parser, lifecycle, limits,
decoder/cache ownership, fixture, and composition boundary are in
[KITTY_GRAPHICS.md](docs/KITTY_GRAPHICS.md) and
[ADR 0033](docs/adr/0033-kitty-graphics-parser-state-foundation.md).

## Deliberate limits

M2 implements Unicode 17 EGCs, deterministic width, combining-mark handling, HarfBuzz shaping, Fontconfig fallback, terminal-local palette/default/cursor colour state with OSC 4/10/11/12/104/110/111/112 updates, primary-screen width reflow, read-only xterm text-area/cell geometry replies, and documented classic/UTF-8/URXVT/SGR-cell/SGR-pixel mouse plus focus reporting. M4 adds GLFW clipboard copy/paste, bounded exact scrollback search, safe OSC 8 hyperlinks, and an explicitly configured bounded OSC 52 write-only subset, but not primary selections, rich formats, automatic synchronization, OSC 52 reads/queries, regular expressions, full-text indexing, link previews, or file/custom-scheme link activation. M6 currently adds bounded OSC 7/133 metadata, opaque command lifecycles, bounded row associations, primary-history region navigation, automatic initial-shell injection for Bash/Zsh/fish/Nushell with manual switched-shell assets, an explicit remote-terminfo SSH helper, and bounded PNG/APNG/GIF Kitty image composition. It also has a bounded Linux AT-SPI provider and macOS NSAccessibility element for the active pane, but no end-to-end screen-reader validation. Kiwi still excludes durable cross-session persistence, path access, execution, command output summarization, a command palette, and a region UI. Kiwi does not implement bidi, Unicode line breaking, color emoji, a multiformat/multipage glyph atlas, touch/gesture mouse protocols, arbitrary image transforms or editing, video, exhaustive reset/DECSTR and SGR rendering coverage, or full xterm/VT100 certification. Primary Kitty placement anchors are released on a width reflow because their fixed cell geometry is not yet reflow-aware; decoded image data remains cached. Unsupported OSC/DCS/APC/PM/SOS data is consumed safely rather than rendered as text, except for the documented bounded Kitty APC-G image transfer/cache, cell-placement, and composition subset. OSC 52 remains disabled unless explicitly configured; its policy is in [ADR 0020](docs/adr/0020-clipboard-and-osc52-security-policy.md). Unknown-sequence counts and bounded, structured samples are available through F4 diagnostics. The precise text contract is in [docs/TEXT.md](docs/TEXT.md).

The renderer remains structured: terminal cells and damage feed background, selection, search, hyperlink-aware glyph, and cursor GPU passes; it does not parse escape sequences or render a terminal bitmap. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/BENCHMARKS.md](docs/BENCHMARKS.md), [docs/ROADMAP.md](docs/ROADMAP.md), and [docs/adr](docs/adr).
