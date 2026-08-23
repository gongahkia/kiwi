# Kiwi → Ghostty compatibility map

## Decision

Kiwi now adopts **daily-driver compatibility for its documented Linux x86_64
and macOS arm64 targets** as an explicit product goal. This is a target, not a
claim that Kiwi is already a safe replacement for Ghostty or any other mature
terminal emulator. A capability is only promoted to the daily-driver contract
after it has a documented behavior, deterministic coverage where possible, and
native validation on every supported platform.

Ghostty is the reference product for this work because it combines a broad
xterm-oriented terminal contract with a native desktop application on macOS
and Linux. Kiwi will not copy Ghostty implementation details or claim exact
feature-for-feature equivalence. “Parity” in this document means a Kiwi
behavior that meets the same user need with an explicit, tested contract.

## Audit boundary

**Kiwi baseline.** This audit was updated from the local worktree on
2026-08-23. The strongest evidence is the [README](README.md),
[conformance contract](docs/CONFORMANCE.md), [macOS support note](docs/MACOS.md),
`src/kiwi/app/main.lua`, the platform bridge, and deterministic tests. The
current worktree has a GLFW/WGPU terminal on Linux and macOS, custom-rendered
tabs and splits, per-pane PTYs, HarfBuzz/Fontconfig text, bounded Kitty
PNG/APNG/GIF composition, and a locally reproducible macOS arm64 archive.

**Ghostty baseline.** Ghostty’s official feature, configuration, VT-reference,
terminfo, and architecture documentation was consulted on 2026-08-23. Its VT reference
is explicitly work in progress, so a Ghostty row means “documented product
capability,” not an assertion that every sequence has been independently
reproduced here.

**Status labels.**

- **Implemented** — part of Kiwi’s documented behavior with automated checks.
- **Partial** — a related implementation exists but does not meet the
  daily-driver completion criteria.
- **Planned** — an accepted goal with no completed user-facing implementation.
- **Manual** — requires on-device validation that automation cannot establish.

## Current conclusion

Kiwi has meaningful renderer and platform foundations, but **does not have
direct Ghostty product parity today**. The previous report’s Linux-only and
“no macOS/NSAccessibility” claims are obsolete: macOS arm64 can build, run via
Cocoa/Metal, use clipboard and resize bridges, launch both development and
extracted release `.app` bundles, and expose a bounded native accessibility
projection. Native macOS tabs/windows, bounded IME preedit, cross-window
session movement, layout restoration, visual Kitty-image framebuffer checks,
and a VoiceOver-facing accessibility adapter are now implemented. Real
VoiceOver speech/navigation and input-source sessions remain manual gates, and
broad configuration and VT compatibility remain incomplete.

| Area | Kiwi now | Daily-driver target | Status |
| --- | --- | --- | --- |
| Linux and macOS runtime | Linux x86_64 Vulkan and macOS arm64 Cocoa/Metal are built locally; macOS has deterministic core/PTY/Cocoa/release-bundle checks. | Maintain the same executable, PTY, renderer, clipboard, resize, packaging, and smoke behavior on both targets. | **Partial** — Linux and Intel macOS require their own evidence. |
| Window/workspace model | One process-wide scheduler owns independent GLFW/Cocoa windows, WGPU contexts, compositors, workspaces, and PTY sets. On macOS, those top-level windows join a native AppKit tab group. Fresh tabs, splits, duplicates, and windows inherit only a validated current-host OSC 7 directory; a moved session keeps its PTY. `Ctrl+Shift+M` moves a live pane session to a new window, `Ctrl+Shift+Alt+M` moves it to the next window as a workspace tab, and the corresponding `D` bindings create fresh default-shell sessions. Schema-v1 persistence restores only geometry and tab/split topology with fresh shells. | Native in-window tab/split ownership, user-selectable move targets, Linux native tabs, schema migration, and interactive Linux/macOS lifecycle qualification. | **Partial** |
| Native desktop UX | Cocoa global menu and searchable AppKit palette on macOS; GTK `GMenu` and searchable dialog on Linux; bounded Cocoa/GTK text-input and accessibility adapters. Both native action surfaces share the product action catalogue and configurable one- through three-chord local bindings. | Platform-appropriate native tab/split/settings/automation behavior, interactive menu and palette validation, and no loss of core terminal semantics. | **Partial** |
| Text and media | Unicode 17 clusters, HarfBuzz shaping, Fontconfig fallback, bounded atlas, and PNG/APNG/GIF Kitty subset. | Stable behavior in daily applications; visual media tests supplement pass-level GPU checks. | **Partial** |
| Configuration | Strict bounded XDG file, environment overrides, validated reload, nine built-in themes, colour-only absolute theme files, system appearance selection, bounded command-palette entries, and bounded one- through three-chord product actions. | Broader user-visible settings and CLI mapping, additional safely-scoped appearance/font controls, and per-target interactive reload validation. | **Partial** |
| Terminal contract | Tested C0/ESC/CSI/OSC subset, primary/alternate screens, reflow, selected Kitty keyboard/mouse modes, OSC 8/52 policy, bounded Kitty OSC 21 palette/default/cursor controls, and an `xterm-kiwi` terminfo contract that advertises 256 indexed colours and direct RGB. | A versioned xterm-oriented compatibility ledger, regression corpus, honest terminfo, and documented policy for every advertised sequence. | **Partial** |
| Core reuse | Experimental renderer-free `libkiwi-vt` Lua/C surface with copied render updates, input encoders, and effects. | Keep the core platform-neutral while desktop capabilities remain host-owned and versioned. | **Partial** |

## Daily-driver compatibility gate

The target is intentionally narrower and more measurable than “be Ghostty.” A
Kiwi release may call itself daily-driver compatible only when all of these are
true for a supported target:

1. The release artifact is reproducible, launches through the platform’s
   normal application path, and has a documented installation and rollback
   path.
2. A real PTY, resize, clipboard, text input, primary/alternate screen,
   scrollback, selection, and close lifecycle have automated coverage and a
   current native smoke result.
3. The advertised terminfo and terminal sequence matrix agree with the parser,
   terminal state, input encoder, and tests. Unsupported behavior remains
   explicit rather than silently approximated.
4. Tabs, splits, windows, configuration reload, and session recovery have
   bounded ownership and failure behavior. No persisted terminal output,
   clipboard, or secret-bearing environment data is required for restoration.
5. Accessibility and text-input behavior are tested with the platform tools
   and manually validated with VoiceOver on macOS and an AT-SPI screen reader
   on Linux.
6. Release qualification includes real interactive workloads, including a
   shell, a full-screen TUI, Unicode/emoji text, clipboard, SSH, resize, and
   supported image fixtures on every claimed target.

Until every gate is satisfied, releases remain experimental and must not claim
daily-driver readiness.

## Compatibility ledger

The authoritative implementation ledger is
[docs/DAILY_DRIVER_COMPATIBILITY.md](docs/DAILY_DRIVER_COMPATIBILITY.md).
`make compatibility` emits the checked, machine-readable v1.4 manifest. Both
are versioned with the code and identify the evidence, support boundary, and
next sequence or application behavior for each area. They are deliberately not
a copy of Ghostty’s evolving VT reference.

| Priority | Workstream | Why it blocks daily use | Next implementation milestone |
| --- | --- | --- | --- |
| P0 | Release application behavior | A graphical macOS release bundle must be launchable by Finder/LaunchServices, not only from a shell. | **Implemented:** deterministic signed Mach-O bundle launcher plus extracted-bundle `open` smoke in `release-check`. |
| P1 | Multi-window/session layer | A daily terminal needs independent windows and safe state restoration, not only one workspace tree. | **Implemented baseline:** transactional live-PTY handoff, fresh-session duplication, and bounded topology restoration; next add native menu integration, user-selectable targets, migrations, and interactive qualification. |
| P1 | Accessibility and IME | Basic projected text is not evidence of a usable screen-reader or composed-text experience. | Add repeatable macOS accessibility inspection and IME composition hooks; run manual VoiceOver validation. |
| P1 | Configuration and themes | The bounded theme/action surface and launch-time theme, appearance, font, scrollback, and shell settings are viable, but Kiwi still lacks a settings UI, broad Ghostty command-line parity, and per-target interactive qualification. | Add platform settings ownership and only further documented, bounded mappings without executable theme content. |
| P1 | VT compatibility | Terminal programs depend on behavioral details beyond parser recognition. | Triage application-stream failures and implement high-value xterm behavior with corpus, PTY, and native evidence; keep terminfo synchronized with the verified subset. |
| P2 | Native chrome/integration | Ghostty uses native components and platform integrations; Kiwi’s workspace is custom-rendered despite its Cocoa/GTK action bridges. | Promote native tab/split/settings/automation ownership behind a platform adapter without coupling `kiwi.vt` to UI objects. |
| P2 | Distribution qualification | A build is not support evidence. | Validate Linux x86_64 and macOS arm64 on clean target hosts; add Intel macOS only after native validation. |

## Detailed gap map

### Terminal and protocols

Ghostty documents an xterm-first, protocol-origin, and de-facto-standard
compatibility policy, including many controls, ESC, CSI, and OSC forms. Kiwi
has a consciously narrower contract. It already implements a substantial
subset—RIS, DECKPAM/DECKPNM, DECALN, left/right margins, selected mode reports,
palette/default/cursor color operations including the bounded Kitty OSC 21
numeric-palette/foreground/background/cursor subset, OSC 8, a default-denied bounded OSC
52 write path, mouse modes, focus, selected Kitty keyboard flags, and an
`xterm-kiwi` entry that advertises 256 indexed colours plus direct RGB. Its
documented unsupported list nevertheless remains large.

The main gap is therefore **contract breadth and evidence**, not the absence of
a terminal parser. The next sequence work must be selected from application
failures and the versioned ledger, then tested at parser, state, PTY, and native
application boundaries before it changes capability advertisement. Broader
Kitty graphics, Sixel/video, Kitty keyboard flag 4, locator/gesture/touch
mouse, general bidi, and many DEC private modes remain explicitly unsupported.

### Desktop model and platform integration

Ghostty documents multiple native windows with tabs and splits, macOS-native
components, Quick Terminal, AppleScript, Quick Look, secure keyboard entry,
and state recovery. Kiwi now has a process-wide live-window scheduler: each
custom-rendered GLFW workspace has its own WGPU context and PTY set, while GLFW
events are polled once for all controllers. On macOS, its top-level windows
join one AppKit tab group without sharing a WGPU surface, workspace, or PTY
set. It transactionally detaches an
active pane into a pending handoff, carries its live PTY and terminal state into
the destination, restores it to the source if destination creation fails, and
destroys only its old renderer before rebinding it to the new context. It also
restores a strict, bounded v1 topology with fresh shells, never persisted
terminal or host-sensitive data. This is not equivalent to
Ghostty's native chrome, arbitrary target selection, session persistence, or
broader recovery model; `kiwi.vt` remains free of host handles.

Ghostty's current command-finish notifications are driven by shell lifecycle
metadata. Kiwi now has the corresponding constrained policy: per-session OSC
133 `C`→`D` observation, a five-second default threshold, `never`/`unfocused`/
`always` configuration, and fixed payload-free notification text. GTK can
submit through its existing desktop-notification bridge; Cocoa/GLFW has no
notification provider yet. This is a useful host-policy seam, not equivalent
to Ghostty's broader notification, bell, focus, or native-UI behavior.

Kiwi now supplies the baseline scrollback interaction that a shell user
expects: primary-screen vertical wheel input moves local history unless an
application owns mouse reporting, and an inactive custom-workspace pane is
focused before it moves. It still has **no visible or native scrollbar**.
Ghostty 1.3 added native scrollbars, so this remains a material product-UX
gap. The next scrollbar implementation should be a host presentation feature,
not another terminal-state protocol: it needs a renderer-neutral viewport
descriptor, pane-local hit testing/drag ownership, accessibility value/range
projection, and separate Cocoa/GTK qualification.

On macOS, Kiwi’s Cocoa bridge is real and verified for a private pasteboard,
drawable resize, Metal surface configuration, and development app-bundle
launch. An extracted release `.app` is now also launch-tested. Its active-pane
accessibility adapter is a bounded read-only text area with value, visible,
caret, and selection ranges. The Cocoa text-input responder receives marked
text and commits, draws transient underlined preedit, and reports a cursor-
anchored candidate rectangle. `make cocoa-smoke` exercises both Objective-C
and Lua callback lifecycles; `make voiceover-validation` exercises the
accessibility contract. Neither can establish a spoken VoiceOver session or a
real third-party input-source workflow, which remain daily-driver gates.

### Configuration and appearance

Ghostty documents hundreds of text configuration options, CLI equivalents,
optional included files, platform-specific path precedence, runtime reload,
custom themes, and system dark/light theme selection. Kiwi’s strict parser is
deliberately smaller, but it now provides nine built-in themes, bounded
colour-only absolute theme files, system appearance selection, validated reload,
bounded command-palette entries, a native text-configuration opener, and a one-
through three-chord local action map. It still lacks a graphical settings
surface, broad command-line mapping, font-feature/fallback configuration, and
Ghostty's theme catalogue. Kiwi will
keep the bounded parser and add only explicit, cycle-safe sources and
documented precedence.

### Rendering, text, and images

Both projects are GPU terminal renderers. Kiwi has strong foundations in damage
tracking, grapheme safety, HarfBuzz shaping, fallback selection, glyph-ID
caching, bounded resource ownership, GPU recovery diagnostics, and Kitty image
composition. Ghostty has a broader end-user feature surface including font
feature selection, a large theme catalogue, and native application behavior.

Kiwi’s Kitty PNG/APNG/GIF smoke tests prove the renderer schedules the image
passes and frame updates. `make kitty-framebuffer-smoke` adds bounded native
surface readback: it sees the composed PNG region and the distinct red/blue
GIF and APNG frames. Manual visual confirmation of real application images,
colour management, and display behavior remains part of qualification.

### libkiwi-vt and libghostty-vt

`libkiwi-vt` is already a shipped experimental Lua API v2 and C API v2, not a
proposed extraction. Its C adapter creates one opaque terminal backed by an
independent LuaJIT state and supplies copied logical render updates, input
encoders, typed queued effects, and an explicit two-call buffer convention.
The archive check rebuilds the SDK reproducibly and compiles standalone Lua and
C consumers. Its deliberate boundary excludes a renderer, PTY, window,
clipboard, process launcher, and network transport.

[Inference] That makes it useful today for a controlled same-platform embedder that needs
Kiwi's terminal state and already owns presentation and transport. It is **not
yet a credible general replacement for libghostty-vt**: Kiwi supports only the
application's macOS arm64 and Linux x86_64 targets, carries LuaJIT as its
implementation dependency, has no ABI-stability promise, and has only the
checked-in consumer coverage. `libghostty-vt` likewise documents its C API as
work in progress, but its public header and repository already cover a much
broader terminal surface, a custom allocator/system interface, formatters,
WebAssembly helpers, examples, and a stated macOS/Linux/Windows/WebAssembly
target. Those are adoption advantages that Kiwi cannot infer from its current
package check.

[Inference] The right next milestone is not a rename or a broad public marketing claim.
Keep `libkiwi-vt` as the sibling library name, add two non-Kiwi integration
consumers with different ownership models, and then decide whether a stable v1
is warranted. Its potentially distinguishable value is a small LuaJIT-native,
strictly bounded terminal kernel with host effects that never perform desktop
actions themselves; that is narrower than libghostty-vt, not more compatible.
Until a consumer needs a capability, the public ABI should not absorb Kiwi's
renderer, GTK/AppKit, PTY, or configuration objects.

## Features that are not useful parity signals

- Windows desktop support is not a current Ghostty application advantage: its
  own feature page says it is planned, and Kiwi also does not support Windows.
- Ghostty documents only left-to-right text despite grapheme handling for some
  right-to-left scripts. Kiwi has no bidi implementation, so neither project
  should claim general bidirectional layout from this comparison.
- Kiwi’s renderer-extension API, resource budgets, and diagnostics are research
  features. Their absence or presence is not a daily-driver comparison metric.

## Sources

### Kiwi, local checkout

- [README: support boundary and commands](README.md)
- [Daily-driver compatibility ledger](docs/DAILY_DRIVER_COMPATIBILITY.md)
- [Conformance contract](docs/CONFORMANCE.md)
- [macOS support boundary](docs/MACOS.md)
- [accessibility boundary](docs/ACCESSIBILITY.md)
- [live workspace composition](src/kiwi/app/main.lua)
- [live window manager](src/kiwi/app/window_manager.lua)
- [GLFW platform adapter](src/kiwi/platform/window.lua)

### Ghostty, official documentation

- [features and compatibility principles](https://ghostty.org/docs/features)
- [configuration model](https://ghostty.org/docs/config)
- [configuration reference](https://ghostty.org/docs/config/reference)
- [terminfo installation and remote fallback](https://ghostty.org/docs/help/terminfo)
- [VT sequence reference](https://ghostty.org/docs/vt/reference)
- [native application architecture](https://ghostty.org/docs/about)
- [libghostty-vt public C header and scope](https://github.com/ghostty-org/ghostty/blob/main/include/ghostty/vt.h)
- [Ghostty 1.3 libghostty status](https://ghostty.org/docs/install/release-notes/1-3-0)
