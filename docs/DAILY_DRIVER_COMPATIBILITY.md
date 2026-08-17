# Daily-driver compatibility ledger

## Status

**Ledger version:** 0.1  
**Goal:** daily-driver compatibility on documented Linux x86_64 and macOS arm64 targets  
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
| Resize and clipboard bridge | GLFW adapter | GLFW Cocoa plus private Cocoa pasteboard smoke | `make cocoa-smoke` | **Partial:** public clipboard behavior requires manual user validation. |
| Image composition | native surface smoke when a display is available | native Metal surface smoke | `make kitty-graphics-smoke`, `make kitty-animation-smoke`, `make kitty-framebuffer-smoke` | **Partial:** framebuffer readback asserts rendered PNG pixels and GIF/APNG red/blue frame changes; real application images still need manual qualification. |

## Desktop/session contract

| Capability | Current behavior | Required evidence to become supported | Status |
| --- | --- | --- | --- |
| Tabs and splits in one window | Bounded custom-rendered workspace with independent pane PTYs, resize, focus routing, inactive-tab PTY servicing, and lifecycle tests. | Existing workspace tests plus interactive macOS and Linux checks. | partial |
| Multiple windows and session movement | `Ctrl+Shift+N` opens a fresh default-shell window. `Ctrl+Shift+M` transfers the active live PTY/session to a new same-process native window; `Ctrl+Shift+Alt+M` transfers it to the next open window as a tab. `Ctrl+Shift+D` and `Ctrl+Shift+Alt+D` create fresh default-shell counterparts. Each window owns its GLFW/Cocoa window, WGPU context, compositor, workspace, and PTY set; GLFW events remain process-wide. | `make new-window-smoke` proves same-process window creation; `make session-move-smoke` proves a live PTY handoff across two native windows; deterministic manager tests cover rollback, duplicate-session creation, and bounds. | partial: native menu/window integration and per-target interactive qualification remain. |
| Restored layout | At live-session changes Kiwi attempts a same-directory temporary-file/rename update of schema-v1 bounded geometry, tab/split topology, and active tab/pane. It restores that topology with fresh default shells; no terminal contents, PTY state, clipboard, command/environment values, or other host data are serialized. | Deterministic JSON/schema/corruption/fresh-session tests plus `make layout-restore-smoke`, which writes a split layout then restores it in a new native session. | partial: no migration exists beyond schema v1, and manual suspend/restore qualification remains. |
| Native UI behavior | GLFW-hosted custom tabs/splits. | macOS menu/window integration and Linux desktop behavior through platform adapters while terminal state stays host-neutral. | planned |
| Keybinding model | Terminal input plus a small fixed local workspace shortcut set. | User-visible binding reference, conflict policy with Kitty keyboard mode, and configurable safe application actions. | partial |

## Text input and accessibility contract

| Capability | Current behavior | Required evidence to become supported | Status |
| --- | --- | --- | --- |
| Committed Unicode input | GLFW character callbacks feed the terminal through bounded key/text correlation. | Native tests for representative composed Unicode text on Linux and macOS. | partial |
| IME composition/preedit | GLFW committed text only; no Wayland text-input lifecycle. | macOS has an `NSTextInputClient` responder with bounded marked-text/commit callbacks, a transient preedit overlay, and a cursor-anchored candidate rectangle. | **Partial:** `make cocoa-smoke` verifies the native and Lua callback lifecycle; real input-source qualification remains manual. |
| macOS accessibility | One bounded read-only `NSAccessibilityTextArea` projection for the active pane, with value, visible range, caret/selection, focus, and notifications. | `make voiceover-validation` plus manual VoiceOver navigation, caret, selection, resize, and pane-change validation. | manual |
| Linux accessibility | Bounded AT-SPI text projection for the active pane plus provider smoke. | Orca or equivalent manual navigation/selection/resize validation on a supported desktop session. | manual |

## Configuration and appearance contract

| Capability | Current behavior | Required evidence to become supported | Status |
| --- | --- | --- | --- |
| Base configuration | Bounded XDG `key = value` file, environment precedence, explicit `--config`, and F6 reload. | Parser/reload tests and documented platform path precedence. | partial |
| Theme selection | Built-in `kiwi`, `nord`, and `light` themes plus explicit palette overrides. | Expanded built-in catalogue, named custom theme files, bounded/cycle-safe source loading, and deterministic precedence tests. | planned |
| System appearance | No automatic dark/light selection. | Platform adapter reporting appearance changes, explicit override precedence, and native smoke/manual validation. | planned |
| Command-line settings | A narrow app argument surface; settings are mostly file/environment values. | Named option mapping, conflict/precedence documentation, and parser tests. | planned |

## VT and application-protocol contract

The detailed current contract and exclusions are in
[CONFORMANCE.md](CONFORMANCE.md). `make compatibility` emits the bounded,
machine-readable current manifest; it is checked by the deterministic suite
and intentionally separates supported, partial, deferred, and next-version
work. The versioned work sequence below prioritizes behavior that affects common
shells and full-screen terminal applications.

| Version | Scope | Current evidence | Gate before advertising |
| --- | --- | --- | --- |
| 1.0 | Current documented C0/ESC/CSI/OSC subset; primary/alternate state; Unicode clusters; PTY resize; mouse/focus; selection; OSC 8; bounded OSC 52; selected Kitty keyboard; bounded PNG/APNG/GIF graphics. | Deterministic terminal, parser, PTY, replay, and renderer tests. | Keep terminfo at its documented 16-colour capability boundary. |
| 1.1 | Complete a prioritized xterm behavior corpus around reset, tab stops, private modes, device/query replies, and mode restoration. | Existing partial behavior and conformance samples. | Corpus-driven parser/state/PTY tests plus terminfo review. |
| 1.2 | Broaden modern interaction only where applications require it: Kitty keyboard flag 4, remaining mouse policy, clipboard responses, and selected OSC effects. | No blanket compatibility claim. | Platform input/policy tests and explicit security limits. |
| 1.3 | Evaluate graphics expansion from real application demand. | Current direct-image/cache/placement implementation is bounded. | Protocol matrix, decode/resource limits, and visual/native evidence. |

General bidi/reordering, Sixel, video, touch/gesture/locator mouse, exhaustive
DEC private modes, and unbounded remote media are not in the current daily-driver
target. They remain unsupported unless a future ledger revision explicitly adds
them with a security and test plan.

## Required manual qualification

Automation does not replace these per-target checks:

- Linux x86_64: shell, Neovim or another full-screen TUI, tmux, resize,
  selection/clipboard, SSH, Unicode/emoji, accessibility screen reader, and
  suspend/restore behavior.
- macOS arm64: Finder launch of the release `.app`, VoiceOver navigation,
  native IME composition, clipboard permission behavior, display-scale change,
  window lifecycle, TUI, SSH, Unicode/emoji, and visible PNG/APNG/GIF fixtures.

Record the machine, OS, desktop/session, GPU, and failure reproduction without
capturing terminal contents or clipboard data. See [SUPPORT.md](SUPPORT.md) for
the privacy boundary.
