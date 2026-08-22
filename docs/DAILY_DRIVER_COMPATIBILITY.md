# Daily-driver compatibility ledger

## Status

**Ledger version:** 0.1  
**Goal:** daily-driver compatibility on documented Linux x86_64 and macOS arm64 targets, with Intel macOS qualification tracked separately
**Current release status:** experimental; this ledger is not a release-readiness declaration.

This ledger is the versioned contract behind the daily-driver goal. A row can
move to **supported** only when its stated scope, automated evidence, native
evidence, and exclusions all remain true. A passing parser test alone is not
enough to support an interactive terminal behavior.

| Status | Meaning |
| --- | --- |
| supported | Documented scope has deterministic and required native evidence on every claimed target. |
| partial | Related implementation exists, but a required behavior, platform, or test boundary is missing. |
| planned | Accepted work with no supported user-facing behavior yet. |
| manual | Automation exists only as a supplement; the named manual validation is still required. |

## Release and platform contract

| Capability | Linux x86_64 | macOS arm64 | Evidence | Status / exclusions |
| --- | --- | --- | --- | --- |
| Source build, native surface, PTY, terminfo | supported in the documented Fedora-oriented source environment | supported in the documented Homebrew source environment | `make check`, `make test-pty` | **Partial:** clean-host qualification remains required. |
| Local reproducible release archive | supported | supported | `make release-check` rebuilds, compares, checksums, extracts, and invokes the release launcher | **Partial:** macOS launcher is deterministically ad-hoc signed only; Developer ID signing and notarization are absent. |
| Normal application launch | Linux desktop entry is packaged | development and extracted release `Kiwi.app` are launched through `open` | `make cocoa-smoke`, `make release-check` | **Partial:** no automated Linux desktop-session launch and no Intel macOS result. |
| Resize and clipboard bridge | GLFW and GTK4 adapters | GLFW Cocoa plus private Cocoa pasteboard smoke; GTK bounded clipboard bridge | `make cocoa-smoke`; `make daily-driver-compatibility COMPAT_ARGS='--host gtk'` | **Partial:** Linux public clipboard behavior requires manual user validation. |
| Image composition | native surface smoke when a display is available | native Metal surface smoke | `make kitty-graphics-smoke`, `make kitty-animation-smoke`, `make kitty-framebuffer-smoke` | **Partial:** framebuffer readback asserts rendered PNG pixels and GIF/APNG red/blue frame changes; real application images still need manual qualification. |
| Terminal RGB composition | native visual evidence requires a graphical session | Metal framebuffer readback | `make truecolour-framebuffer-smoke` | **Partial:** macOS arm64 readback observed the controlled terminal RGB background on 2026-08-22, and the native direct-RGB child plus tmux 3.7b contract probes passed. This remains compositor/protocol evidence only; colour-managed display output, a real RGB TUI under `xterm-kiwi` (Btop is unavailable), SSH, and Linux native evidence remain unqualified. |

## Desktop/session contract

| Capability | Current behavior | Required evidence to become supported | Status |
| --- | --- | --- | --- |
| Tabs and splits in one window | Bounded custom-rendered workspace with independent pane PTYs, resize, focus routing, inactive-tab PTY servicing, and lifecycle tests. | Existing workspace tests plus interactive macOS and Linux checks. | partial |
| Multiple windows and session movement | `Ctrl+Shift+N` opens a fresh default-shell window. `Ctrl+Shift+M` transfers the active live PTY/session to a new same-process native window; `Ctrl+Shift+Alt+M` transfers it to the next open window as a tab. `Ctrl+Shift+D` and `Ctrl+Shift+Alt+D` create fresh default-shell counterparts. Each window owns its GLFW/Cocoa window, WGPU context, compositor, workspace, and PTY set; GLFW events remain process-wide. | `make new-window-smoke` proves same-process window creation; `make session-move-smoke` proves a live PTY handoff across two native windows; deterministic manager tests cover rollback, duplicate-session creation, and bounds. | partial: native menu/window integration and per-target interactive qualification remain. |
| Restored layout | At live-session changes Kiwi attempts a same-directory temporary-file/rename update of schema-v1 bounded geometry, tab/split topology, and active tab/pane. It restores that topology with fresh default shells; no terminal contents, PTY state, clipboard, command/environment values, or other host data are serialized. | Deterministic JSON/schema/corruption/fresh-session tests plus `make layout-restore-smoke`, which writes a split layout then restores it in a new native session. | partial: no migration exists beyond schema v1, and manual suspend/restore qualification remains. |
| Native UI behavior | GLFW owns the custom tab/split workspace. macOS has a Cocoa global menu; GTK has a shared `GMenu` whose `win.*` entries resolve to the active `GtkApplicationWindow`. Both call the same logical product actions; neither replaces the GLFW workspace with native tab/split chrome or adds menu accelerators. | `make cocoa-smoke` verifies Cocoa menu construction; `make cocoa-menu-smoke` dispatches New Tab through the live controller. `make gtk-host-check` verifies the GTK ABI; `make gtk-menu-smoke` dispatches the corresponding GTK action in a graphical Linux session. Qualification also requires interactive menu/window behavior on both targets. | **Partial:** no native tab strip, settings surface, automation model, or manual product-chrome qualification. |
| Keybinding model | A bounded 64-entry configuration map replaces/removes the documented local tab, split, window, session, and reload actions. It accepts only explicit known actions and gives Kitty keyboard flag 8 to the terminal. | Deterministic parser/action precedence tests plus interactive native checks on each claimed platform. | partial |
| Kitty alternate-key reporting | macOS GLFW/Cocoa uses Carbon's current keyboard-layout table plus GLFW's physical key token to supply Kitty flag 4's layout, shifted-layout, and PC-101 base variants. GTK and Linux GLFW deliberately advertise only flags 1/2/8/16. | Deterministic Lua/C encoder tests, native build, and manual modified-key checks on representative non-US macOS layouts. | **Partial:** no interactive non-US-layout result; no Linux/GTK flag-4 implementation is claimed. |

## Text input and accessibility contract

| Capability | Current behavior | Required evidence to become supported | Status |
| --- | --- | --- | --- |
| Committed Unicode input | GLFW character callbacks and GTK `GtkIMMulticontext` commits feed the terminal through bounded key/text correlation. | Native representative composed Unicode input on Linux and macOS. | **Partial:** `make gtk-input-smoke` exercises GTK's bounded UTF-8 callback boundary; real keyboard input remains manual. |
| IME composition/preedit | GTK has a `GtkIMMulticontext` attached to the terminal widget, bounded preedit/commit callbacks, a transient preedit overlay, and a cursor-anchored candidate rectangle. macOS has the corresponding `NSTextInputClient` responder. | Input-source composition, candidate placement, cancellation, focus changes, and Kitty-keyboard interaction on each native desktop. | **Partial:** `make gtk-input-smoke` and `make cocoa-smoke` verify their native/Lua callback lifecycles; real input-source qualification remains manual. |
| macOS accessibility | One bounded read-only `NSAccessibilityTextArea` projection for the active pane, with value, visible range, caret/selection, focus, and notifications. | `make voiceover-validation` plus manual VoiceOver navigation, caret, selection, resize, and pane-change validation. | manual |
| Linux accessibility | GTK's terminal widget implements bounded read-only `GtkAccessibleText` for the active pane, including contents, caret, selection, focus state, and change notifications. | `make gtk-accessibility-smoke` plus Orca or equivalent manual navigation/selection/resize validation on a supported desktop session. | manual |

## Configuration and appearance contract

| Capability | Current behavior | Required evidence to become supported | Status |
| --- | --- | --- | --- |
| Base configuration | Bounded XDG `key = value` file, environment precedence, explicit `--config`, validated reload, bounded product actions, and host-effect policy. | Parser/configuration/reload tests and documented platform path precedence. | partial |
| Theme selection | Nine built-in themes, bounded colour-only absolute external theme files, and explicit colour overrides. | Deterministic catalogue, external-theme, bounds, and precedence tests plus native reload/manual checks. | partial |
| System appearance | `theme = system` selects bounded named dark/light themes; `appearance` can force dark/light or follow the current Cocoa/GTK adapter value. Explicit colour overrides survive a change. | Deterministic precedence tests plus native dark/light transition and display-scale qualification on each claimed target. | partial |
| OSC 9 host effects | Notifications and progress are default-denied. Configured GTK notifications submit bounded valid requests through GApplication; configured macOS GLFW/Cocoa maps ConEmu states 0/1/2/3/4 to remove/normal/error/indeterminate/paused per-window titlebar progress. Cocoa/GLFW notifications and GTK progress are unavailable. | Deterministic parser/policy tests, Cocoa progress lifecycle smoke, GTK desktop notification delivery, and platform-policy qualification. | partial |
| Command-line settings | A narrow app argument surface; settings are mostly file/environment values. | Named option mapping, conflict/precedence documentation, and parser tests. | planned |

## VT and application-protocol contract

The detailed current contract and exclusions are in
[CONFORMANCE.md](CONFORMANCE.md). `make compatibility` emits the bounded,
machine-readable current manifest; it is checked by the deterministic suite
and intentionally separates supported, partial, deferred, and next-version
work. The versioned work sequence below prioritizes behavior that affects common
shells and full-screen terminal applications.

The workload and evidence rules that decide this priority are in
[DAILY_DRIVER_CORPUS.md](DAILY_DRIVER_CORPUS.md). A protocol is not promoted
solely because it is listed by another terminal or accepted by Kiwi's parser.

| Version | Scope | Current evidence | Gate before advertising |
| --- | --- | --- | --- |
| 1.0 | Current documented C0/ESC/CSI/OSC subset; primary/alternate state; Unicode clusters; PTY resize; mouse/focus; selection; OSC 8; bounded OSC 52/9 policy; selected Kitty keyboard; bounded PNG/APNG/GIF graphics; 256 indexed colours and direct RGB SGR. | Deterministic terminal, parser, PTY, replay, renderer, configuration, host-effect, terminfo-`tput`, native RGB readback, and RGB-TUI-stream tests. | Retain only the explicitly tested `xterm-kiwi` terminfo capabilities; remote SSH qualification remains required before deployment claims. |
| 1.1 | Complete a prioritized xterm behavior corpus around reset, tab stops, private modes, device/query replies, and mode restoration. | Existing partial behavior and conformance samples. | Corpus-driven parser/state/PTY tests plus terminfo review. |
| 1.2 | Broaden modern interaction only where applications require it: complete Kitty flag-4 qualification beyond the macOS partial path, remaining mouse policy, clipboard responses, and selected OSC effects. | No blanket compatibility claim. | Platform input/policy tests and explicit security limits. |
| 1.3 | Evaluate graphics expansion from real application demand. | Current direct-image/cache/placement implementation is bounded. | Protocol matrix, decode/resource limits, and visual/native evidence. |

General bidi/reordering, Sixel, video, touch/gesture/locator mouse, exhaustive
DEC private modes, and unbounded remote media are not in the current daily-driver
target. They remain unsupported unless a future ledger revision explicitly adds
them with a security and test plan.

## Compatibility qualification suite

`make daily-driver-compatibility` is the cross-platform, bounded evidence
command for daily-driver surfaces. It builds the native bridge and local
terminfo, then checks tmux's nested TERM contract; Bash, Zsh, fish, and
Nushell OSC 7/133 integration when installed; native shell-metadata and OSC 8
record/replay; Neovim's Kitty keyboard negotiation; Vim mouse-mode startup;
and the host `top` TUI. Each native capture is revalidated as captured, one
byte at a time, and with eight deterministic randomized output chunk layouts.
Where a native graphical session is available it also runs bounded compositor
readback for a non-palette terminal RGB background. A provided `--ssh-host` (or
`KIWI_COMPAT_SSH_HOST`) enables the fixed `kiwi-ssh --probe` workflow: it
uploads the local private terminfo entry then confirms `infocmp -x xterm-kiwi`,
`tput colors`, and direct-RGB `tput setrgbf` on that controlled remote host.

Use `--host glfw` (the default) or `--host gtk` to select the native adapter
for desktop workloads. GTK qualification is Linux x86_64 only and builds its
private host bridge before launch. A passing run is bounded rendering/PTY
evidence, not proof of interactive keyboard, IME, accessibility, public
clipboard, or scaled-monitor behavior.

Use `--require-desktop` for a qualification runner. On Linux, the option fails
instead of skipping when neither `DISPLAY` nor `WAYLAND_DISPLAY` is available.
On macOS, native window creation is the platform boundary. The command does not
retain recordings, terminal output, shell output, or clipboard data. Pass
`--report path.json` to retain only the bounded machine/OS/session/GPU summary
and check statuses; review that report before sharing it.

Clipboard has an explicit safety boundary. macOS uses a private AppKit
pasteboard round trip. Linux public clipboard qualification is manual by
default; `--allow-public-clipboard` is only for an isolated desktop session and
writes a fixed probe before restoring the exact prior value. It refuses to
write when it cannot first preserve the current value. Neither route tests
third-party clipboard managers, rich formats, or concurrent clipboard changes.

The repository has an Intel macOS GitHub Actions qualification job on
`macos-15-intel` and a manually dispatched self-hosted `kiwi-desktop` Linux
workflow. A successful run is required evidence, not an implicit support claim.
At this revision, the recorded macOS native evidence is Apple Silicon; the
Intel job and a real Linux desktop runner are the mechanisms for collecting the
missing qualification.

## Required manual qualification

The suite is structural and does not replace these per-target checks:

- Linux x86_64: interactive Neovim and tmux use, resize and a fractional-scale
  monitor, selection/copy/paste, GTK keyboard and IME composition/candidate
  placement, SSH login, Unicode/emoji, Orca navigation, and suspend/restore.
- macOS arm64 and Intel: Finder launch of the release `.app`, VoiceOver
  navigation, native IME composition, public clipboard permission behavior,
  display-scale change, window lifecycle, interactive TUI/SSH, Unicode/emoji,
  and visible PNG/APNG/GIF fixtures.

Record the machine, OS, desktop/session, GPU, and failure reproduction without
capturing terminal contents or clipboard data. See [SUPPORT.md](SUPPORT.md) for
the privacy boundary.
