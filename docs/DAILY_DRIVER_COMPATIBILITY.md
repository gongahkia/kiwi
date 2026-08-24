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
| Presentation lifecycle | the WGPU presenter checks the current drawable size before every surface acquisition and reconfigures on a size change; host callbacks are detached before PTY/session teardown | Cocoa/Metal route needs current native verification | `make test`; `make device-loss-sim`; `make device-soak-native`; GTK Wayland/X11 and Cocoa smoke routes | **Partial:** deterministic lifecycle coverage includes zero-size drawables, missed resize notifications, configured recovery, and callback teardown. Linux WGPU device-loss simulation is available; GTK Wayland/X11, physical fractional-scale/monitor/occlusion transitions, and all current macOS results remain separately unqualified. Framebuffer readback is not colour-management evidence. |
| Image composition | native surface smoke when a display is available | native Metal surface smoke | `make kitty-graphics-smoke`, `make kitty-animation-smoke`, `make kitty-framebuffer-smoke` | **Partial:** framebuffer readback asserts rendered PNG pixels and GIF/APNG red/blue frame changes; real application images still need manual qualification. |
| Terminal RGB composition | native visual evidence requires a graphical session | Metal framebuffer readback | `make truecolour-framebuffer-smoke`; `make daily-driver-compatibility` | **Partial:** macOS arm64 readback observed the controlled terminal RGB background on 2026-08-22. On Linux, tmux 3.7b delivered a fixed direct-RGB marker, but replay also observed unsupported theme, version, and application-key controls; the current tmux gate therefore fails rather than treating byte pass-through as full compatibility. The earlier macOS tmux `tput` probe must be rerun using this stricter criterion. Colour-managed display output, a real RGB TUI under `xterm-kiwi` (Btop is unavailable), controlled SSH, and Linux native framebuffer evidence remain unqualified. |

## Desktop/session contract

| Capability | Current behavior | Required evidence to become supported | Status |
| --- | --- | --- | --- |
| Tabs and splits in one window | On macOS, `New Tab` creates a host-owned AppKit tab containing one bounded custom split workspace with independent pane PTYs, resize, focus routing, and lifecycle tests; `Next Tab` invokes AppKit. Linux's default host retains custom workspace tabs and splits. Fresh tabs and splits inherit only a percent-decoded local active OSC 7 directory; remote or malformed metadata retains the launch directory. The opt-in GTK GL prototype has native `AdwTabView` pages with independent VT/PTY/input/IME/accessibility/renderer state plus bounded New Tab/Next Tab/Close Pane dispatch; closing a non-final page first detaches its GTK presentation, then tears down that page's session and PTY. It has no splits, transfer, detach, persistence, or graphical Linux qualification. | Existing workspace tests; `make cocoa-smoke` directly verifies grouping and next-tab selection; action-specific Cocoa smokes verify host-tab creation requests; deterministic OSC 7 local-path and PTY working-directory tests cover the inheritance boundary; `make gtk-gl-native-tabs-wayland-smoke` / `make gtk-gl-native-tabs-x11-smoke` are required Linux widget-presenter creation gates and their `*-close-*` companions require non-final-page session teardown; interactive macOS and Linux checks remain required. | partial |
| Multiple windows and session movement | `Ctrl+Shift+N` opens a fresh default-shell top-level window. On macOS Kiwi registers it outside the explicit `Ctrl+Shift+T` AppKit group; the verified GLFW/Cocoa default reports `NSWindowTabbingModeDisallowed` for that standalone window. A fresh window or duplicate receives the same bounded local OSC 7 directory policy as a fresh tab; a transferred session keeps its existing PTY. Each has its own WGPU context, compositor, workspace, and PTY set. `Ctrl+Shift+M` transfers the active live PTY/session to a new same-process native window; `Ctrl+Shift+Alt+M` transfers it to the next open window as a workspace tab. `Ctrl+Shift+D` and `Ctrl+Shift+Alt+D` create fresh default-shell counterparts. GLFW events remain process-wide. | `make new-window-smoke` proves same-process window creation; deterministic manager tests distinguish native-tab and new-window intent and retain the bounded initial directory; `make cocoa-smoke` verifies AppKit grouping/selection and independent Metal surfaces; `make session-move-smoke` proves a live PTY handoff across two native windows. | partial: interactive native tab behavior, Linux native tabs, user-selectable move targets, and per-target qualification remain. |
| Restored layout | At live-session changes Kiwi attempts a same-directory temporary-file/rename update of schema-v1 bounded geometry, tab/split topology, and active tab/pane. It restores that topology with fresh default shells; no terminal contents, PTY state, clipboard, command/environment values, or other host data are serialized. | Deterministic JSON/schema/corruption/fresh-session tests plus `make layout-restore-smoke`, which writes a split layout then restores it in a new native session. | partial: no migration exists beyond schema v1, and manual suspend/restore qualification remains. |
| Native UI behavior | GLFW owns custom split content. macOS delegates normal tab creation/selection to AppKit while explicitly keeping `New Window` separate; it adds a Cocoa global menu, unified titlebar toolbar, local-shell OSC 7 proxy URL, searchable AppKit palette, text-configuration Settings action, and an action-only `Kiwi.sdef`/Apple-event bridge. GTK has a shared `GMenu`, text-configuration Settings action, and searchable dialog whose `win.*` entries resolve to the active `GtkApplicationWindow`. Both dispatch the twelve default and configuration-augmented bounded product-action catalogue; the configuration action creates only a missing default comment template and opens it with the host text-file handler. The macOS toolbar exposes New Tab, Split Right, Split Down, Commands, and Settings; its proxy URL accepts only active empty/local-host OSC 7 metadata and clears remote metadata; its scripting bridge accepts only new window/tab, next tab, close pane, split right/down, reload configuration, and open configuration. Neither route implements native split content or menu accelerators. | Deterministic configuration tests cover default-path selection and non-overwriting initialization. `make cocoa-smoke` verifies Cocoa menu construction, direct AppKit group/next-tab selection, unified-toolbar dispatch, local/remote proxy URL handling, Settings callback routing, a configured palette entry, and bundle launch; `make cocoa-menu-smoke`, `make cocoa-toolbar-smoke`, `make cocoa-cwd-smoke`, and `make cocoa-palette-smoke` dispatch actions or terminal metadata through the live controller; `make cocoa-automation-smoke` validates the staged bundle's SDEF and bounded New Tab dispatch. `make gtk-host-check` verifies the GTK ABI; `make gtk-menu-smoke` and `make gtk-palette-smoke` are corresponding graphical-Linux gates. Qualification also requires interactive filtering/menu/window behavior on both targets. | **Partial:** no native split content, graphical settings editor, full automation object model, terminal-text automation, arbitrary palette execution, external Apple-event permission qualification, Linux native tabs, desktop text-handler qualification, Finder disclosure, or manual product-chrome qualification. |
| Experimental GTK widget presentation | `KIWI_GTK_PRESENTER=gl` selects one GTK `GtkGLArea` terminal by default. `KIWI_GTK_NATIVE_TABS=1` adds an experimental libadwaita tab container: `New Tab` creates a separate VT/PTy, Lua input correlation state, GTK IME/accessibility node, font, and GL renderer; `Next Tab` selects/focuses it while background PTYs continue to drain; `Close Pane` detaches one non-final page before releasing its session and PTY. It draws background, selection/search, alpha-atlas glyph, command-region, cursor, and the renderer-neutral scrollbar overlay; track and thumb-drag input take precedence over hyperlink, selection, and terminal mouse reporting. Initial, resize, and retry submissions are complete bounded grids; normal terminal updates retain a bounded native grid and upload only dirty cell ranges plus changed glyph/atlas resources. The accessible terminal is a dedicated focusable `GtkWidget` beneath the standard `GtkOverlay` GL child, so terminal semantics are not coupled to a GTK container subclass. Workspace persistence, splits, detach/transfer, manager host-tab ownership, recording, and Kitty images remain unavailable. | `make test` verifies producer/consumer damage, retry, cursor scheduling, scrollbar descriptors, controller option gates, and tab-group teardown ordering; `make gtk-gl-renderer-check` compiles the native host bridge and renderer; `make gtk-gl-wayland-smoke` and `make gtk-gl-x11-smoke` must observe the submitted revision and a one-cell subrange upload in a real GtkGLArea callback. `make gtk-gl-native-tabs-wayland-smoke` and `make gtk-gl-native-tabs-x11-smoke` additionally dispatch New Tab through the live GTK product action and require two distinct page/PTY owners; their `*-close-*` companions then dispatch Close Pane and require one retained live page/session. The desktop workflow also separately requires default-WGPU `gtk-wayland-smoke` / `gtk-x11-smoke` and their multi-window lifecycle gates, so a widget-presenter pass cannot be mistaken for ordinary GTK-host qualification. | **Partial:** the incremental protocol and native-tab lifecycle have local deterministic/source/ASan evidence, but no graphical Linux result, visual comparison, performance baseline, colour-management/sRGB result, fractional-scale, device-loss, occlusion/pacing, interactive input, accessibility qualification, or full tab group-owner lifecycle. |
| Keybinding model | A bounded 64-directive configuration trie replaces/removes the documented local tab, split, window, session, command-palette, and reload actions. Each binding has one through three chords; ambiguous prefix pairs are rejected and a pending prefix expires after one second. It accepts only explicit known actions and gives Kitty keyboard flag 8 to the terminal. | Deterministic parser/trie/action-precedence tests plus interactive native checks on each claimed platform. | partial |
| Kitty alternate-key reporting | macOS GLFW/Cocoa uses Carbon's current keyboard-layout table plus GLFW's physical key token. GTK obtains the event's active GDK group, level-zero and level-one Unicode mappings for the raw XKB keycode, and a fixed US PC-101 value for standard printable positions. GTK advertises flag 4 only after its live GDK keymap probe can derive the standard `A` position; Linux GLFW remains 1/2/8/16 only. | Deterministic Unicode/encoder tests, GTK bridge ABI keycode-table checks, `make gtk-input-wayland-smoke` / `make gtk-input-x11-smoke`, and manual modified-key checks on representative non-US macOS and Linux layouts. | **Partial:** current automation proves the bridge tuple, not real keyboard delivery or representative non-US layouts. The fixed table covers standard XKB codes; custom XKB keycode remapping is unqualified. Unmappable non-printable or non-PC-101 keys omit their alternate fields. |

A local primary-screen wheel policy is deterministic on every current
presentation route, including per-session fractional accumulation and inactive
pane focus. The WGPU and experimental GTK GL routes have a renderer-drawn
primary-screen scrollbar overlay when history exists. Its descriptor contains
bounded history counts, normalized thumb geometry, and colour only; track
clicks and thumb drags remain pane-local and take priority over terminal mouse
reports inside the overlay. `scrollbar = never` disables it. **Partial:** this
is not a native Cocoa/GTK scrollbar, has no accessibility range/value
projection, and lacks manual or graphical desktop qualification.

## Text input and accessibility contract

| Capability | Current behavior | Required evidence to become supported | Status |
| --- | --- | --- | --- |
| Committed Unicode input | GLFW character callbacks and GTK `GtkIMMulticontext` commits feed the terminal through bounded key/text correlation. GTK key callbacks also carry an explicit Unicode scalar rather than conflating it with GLFW's overlapping special-key range. | Native representative composed Unicode input on Linux and macOS. | **Partial:** GTK input smokes exercise the bounded UTF-8, Unicode-key, and alternate-key callback boundary; real keyboard input remains manual. |
| IME composition/preedit | GTK has a `GtkIMMulticontext` attached to the terminal widget, bounded preedit/commit callbacks, a transient preedit overlay, and a cursor-anchored candidate rectangle. macOS has the corresponding `NSTextInputClient` responder. | Input-source composition, candidate placement, cancellation, focus changes, and Kitty-keyboard interaction on each native desktop. | **Partial:** `make gtk-input-smoke` and `make cocoa-smoke` verify their native/Lua callback lifecycles; real input-source qualification remains manual. |
| macOS accessibility | One bounded read-only `NSAccessibilityTextArea` projection for the active pane, with value, visible range, caret/selection, focus, and notifications. | `make voiceover-validation` plus manual VoiceOver navigation, caret, selection, resize, and pane-change validation. | manual |
| Linux accessibility | GTK's terminal widget implements bounded read-only `GtkAccessibleText` for the active pane, including contents, caret, selection, focus state, and change notifications. | `make gtk-accessibility-smoke` plus Orca or equivalent manual navigation/selection/resize validation on a supported desktop session. | manual |

## Configuration and appearance contract

| Capability | Current behavior | Required evidence to become supported | Status |
| --- | --- | --- | --- |
| Base configuration | Bounded XDG `key = value` file, environment precedence, explicit `--config`, validated reload, bounded product actions, and host-effect policy. | Parser/configuration/reload tests and documented platform path precedence. | partial |
| Theme selection | Nine built-in themes, bounded colour-only absolute external theme files, and explicit colour overrides. | Deterministic catalogue, external-theme, bounds, and precedence tests plus native reload/manual checks. | partial |
| System appearance | `theme = system` selects bounded named dark/light themes; `appearance` can force dark/light or follow the current Cocoa/GTK adapter value. Explicit colour overrides survive a change. | Deterministic precedence tests plus native dark/light transition and display-scale qualification on each claimed target. | partial |
| Host notifications and progress | OSC 9 notifications/progress are default-denied. Configured GTK notifications submit bounded valid requests through GApplication; configured macOS GLFW/Cocoa maps ConEmu states 0/1/2/3/4 to remove/normal/error/indeterminate/paused per-window titlebar progress. Separately, `notify-on-command-finish` defaults to `never` and can submit a fixed payload-free completion message after a bounded observed OSC 133 `C`→`D` interval for the same unfocused or any pane/tab. Cocoa/GLFW notifications and GTK progress are unavailable. | Deterministic parser/policy/session-isolation tests, Cocoa progress lifecycle smoke, GTK desktop notification delivery, and platform-policy qualification. | partial |
| Command-line settings | `--theme`, `--theme-file`, `--appearance`, `--font-family`, `--font-size`, `--scrollback-limit`, `--scrollbar`, and `--shell-integration` map to the bounded configuration parser. They override file and environment values and are reapplied on reload. | Deterministic option/precedence tests and interactive launch/reload checks on each native target. | partial |

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
| 1.1 | Complete a prioritized xterm behavior corpus around reset, tab stops, private modes, device/query replies, and mode restoration. | The deterministic reset/tab/private-mode fixture, PTY DECRQM response round-trip, and macOS native VT exercise cover TBC/DECST8C plus the queryable-mode XTSAVE/XTRESTORE subset. | Continue corpus-driven parser/state/PTY tests plus terminfo review; this does not widen the private `xterm-kiwi` terminfo contract. |
| 1.2 | Broaden modern interaction only where applications require it: complete Kitty flag-4 qualification beyond the macOS partial path, Shift mouse policy, clipboard responses, and selected OSC effects. | Deterministic state, selection-pointer, Lua SDK, C SDK, configuration, and host-bridge tests cover default-denied OSC 52 reads plus explicit bounded query requests and XTSHIFTESCAPE (`CSI > Ps s`) with the four `mouse-shift-capture` policies. Actual desktop clipboard permission and graphical pointer delivery remain unqualified. | Platform input/policy tests, a real focused desktop clipboard and pointer session, and explicit security limits. |
| 1.3 | Evaluate graphics expansion from real application demand. | Current direct-image/cache/placement implementation is bounded. | Protocol matrix, decode/resource limits, and visual/native evidence. |
| 1.4 | Add application-driven modern protocol breadth without widening the terminfo claim: bounded Kitty OSC 21 numeric-palette/default/cursor updates, queries, and resets. | Deterministic state and conformance fixtures plus the renderer-neutral Lua/C SDK consumer verify atomic update semantics and the typed palette effect. Dynamic and selection-colour OSC 21 policies remain unsupported. | Retain explicit input/key/value bounds and require a real client only before promoting broader Kitty colour compatibility. |

General bidi/reordering, Sixel, video, touch/gesture/locator mouse, exhaustive
DEC private modes, and unbounded remote media are not in the current daily-driver
target. They remain unsupported unless a future ledger revision explicitly adds
them with a security and test plan.

## Compatibility qualification suite

`make daily-driver-compatibility` is the cross-platform, bounded evidence
command for daily-driver surfaces. It builds the native bridge and local
terminfo, then checks tmux's nested TERM contract; Bash, Zsh, fish, and
Nushell OSC 7/133 integration when installed; native tmux, shell-metadata,
and OSC 8 record/replay; Neovim's Kitty keyboard negotiation; Vim mouse-mode
startup; and the host `top` TUI. Each native capture is revalidated as
captured, one byte at a time, and with eight deterministic randomized output
chunk layouts. GTK GL smokes also assert that an accepted one-cell update
reaches a subrange upload, rather than merely observing a rendered revision.
Where a native graphical session is available it also runs bounded compositor
readback for a non-palette terminal RGB background. A provided `--ssh-host` (or
`KIWI_COMPAT_SSH_HOST`) enables the fixed `kiwi-ssh --probe` workflow: it
uploads the local private terminfo entry then confirms `infocmp -x xterm-kiwi`,
`tput colors`, and direct-RGB `tput setrgbf` on that controlled remote host.
The Linux desktop workflow collects a GLFW report and one explicit GTK report
for the active Wayland or X11 backend; it uploads both bounded JSON files. Its
separate backend smoke commands test the other available backend when present.
After functional gates it also uploads bounded `pacing` and redraw-scheduling
(`power-smoke`) observations. Those are native present-loop diagnostics, not
portable latency, energy, or display-scanout claims.

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
and check statuses; review that report before sharing it. When the SSH check is
attempted, the report marks network use as `controlled SSH terminfo probe; host
excluded`; it never serializes the destination or connection options.

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

## Current qualification observations

On 2026-08-24, the Linux x86_64 local route passed the deterministic presentation
tests, `make device-loss-sim` (one configured WGPU retry after a simulated loss),
and `make device-soak-native` (bounded resize/minimize/restore cycling). The
default GTK WGPU and experimental GtkGLArea Wayland/X11 smoke routes, including
their multi-window and native-tab close variants, also passed after controller
teardown began detaching input callbacks before controller deregistration. This
is targeted Linux structural evidence only: no physical fractional-scale,
monitor-move, occlusion, colour-management, interactive input, controlled SSH,
or macOS result was collected in this run.

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
