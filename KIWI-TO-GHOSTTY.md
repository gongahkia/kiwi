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
2026-08-17. The strongest evidence is the [README](README.md),
[conformance contract](docs/CONFORMANCE.md), [macOS support note](docs/MACOS.md),
`src/kiwi/app/main.lua`, the platform bridge, and deterministic tests. The
current worktree has a GLFW/WGPU terminal on Linux and macOS, custom-rendered
tabs and splits, per-pane PTYs, HarfBuzz/Fontconfig text, bounded Kitty
PNG/APNG/GIF composition, and a locally reproducible macOS arm64 archive.

**Ghostty baseline.** Ghostty’s official feature, configuration, VT-reference,
and architecture documentation was consulted on 2026-08-17. Its VT reference
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
projection. Native macOS tabs/windows, VoiceOver validation, IME preedit,
session restoration, broad configuration, and broad VT compatibility remain
incomplete.

| Area | Kiwi now | Daily-driver target | Status |
| --- | --- | --- | --- |
| Linux and macOS runtime | Linux x86_64 Vulkan and macOS arm64 Cocoa/Metal are built locally; macOS has deterministic core/PTY/Cocoa/release-bundle checks. | Maintain the same executable, PTY, renderer, clipboard, resize, packaging, and smoke behavior on both targets. | **Partial** — Linux and Intel macOS require their own evidence. |
| Window/workspace model | One GLFW window contains bounded custom-rendered tabs and horizontal/vertical splits; panes have independent PTYs. | Multiple windows, per-window workspaces, lifecycle-safe close behavior, and persisted/restored non-sensitive layout state. | **Partial** |
| Native desktop UX | Cocoa window and basic `NSAccessibilityStaticText` adapter on macOS; AT-SPI active-pane adapter on Linux. | Platform-appropriate menu/shortcut/accessibility behavior, native validation, and no loss of core terminal semantics. | **Partial** |
| Text and media | Unicode 17 clusters, HarfBuzz shaping, Fontconfig fallback, bounded atlas, and PNG/APNG/GIF Kitty subset. | Stable behavior in daily applications; visual media tests supplement pass-level GPU checks. | **Partial** |
| Configuration | Strict bounded XDG file, environment overrides, reload, and `kiwi`, `nord`, and `light` themes. | Broader documented settings, multiple theme sources, system appearance behavior, and platform path precedence. | **Partial** |
| Terminal contract | Tested C0/ESC/CSI/OSC subset, primary/alternate screens, reflow, selected Kitty keyboard/mouse modes, OSC 8/52 policy, and local terminfo. | A versioned xterm-oriented compatibility ledger, regression corpus, honest terminfo, and documented policy for every advertised sequence. | **Partial** |
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
`make compatibility` emits the checked, machine-readable v1.0 manifest. Both
are versioned with the code and identify the evidence, support boundary, and
next sequence or application behavior for each area. They are deliberately not
a copy of Ghostty’s evolving VT reference.

| Priority | Workstream | Why it blocks daily use | Next implementation milestone |
| --- | --- | --- | --- |
| P0 | Release application behavior | A graphical macOS release bundle must be launchable by Finder/LaunchServices, not only from a shell. | **Implemented:** deterministic signed Mach-O bundle launcher plus extracted-bundle `open` smoke in `release-check`. |
| P1 | Multi-window/session layer | A daily terminal needs independent windows and safe state restoration, not only one workspace tree. | Introduce a platform-neutral window manager with independent workspace ownership and a non-sensitive layout snapshot. |
| P1 | Accessibility and IME | Basic projected text is not evidence of a usable screen-reader or composed-text experience. | Add repeatable macOS accessibility inspection and IME composition hooks; run manual VoiceOver validation. |
| P1 | Configuration and themes | Three hard-coded themes and a small key set do not meet common desktop configuration needs. | Add documented theme sources, macOS config-path precedence, and system-appearance selection without unbounded includes. |
| P1 | VT compatibility | Terminal programs depend on behavioral details beyond parser recognition. | Publish v1 of the sequence ledger and implement high-value gaps with corpus tests before widening terminfo. |
| P2 | Native chrome/integration | Ghostty uses native components and platform integrations; Kiwi’s workspace is custom-rendered. | Add native menu/window integration behind a platform adapter without coupling `kiwi.vt` to UI objects. |
| P2 | Distribution qualification | A build is not support evidence. | Validate Linux x86_64 and macOS arm64 on clean target hosts; add Intel macOS only after native validation. |

## Detailed gap map

### Terminal and protocols

Ghostty documents an xterm-first, protocol-origin, and de-facto-standard
compatibility policy, including many controls, ESC, CSI, and OSC forms. Kiwi
has a consciously narrower contract. It already implements a substantial
subset—RIS, DECKPAM/DECKPNM, DECALN, left/right margins, selected mode reports,
palette/default/cursor color operations, OSC 8, a default-denied bounded OSC
52 write path, mouse modes, focus, and selected Kitty keyboard flags—but its
terminfo advertises only 16 colours and its documented unsupported list remains
large.

The main gap is therefore **contract breadth and evidence**, not the absence of
a terminal parser. The next sequence work must be selected from application
failures and the versioned ledger, then tested at parser, state, PTY, and native
application boundaries before it changes capability advertisement. Broader
Kitty graphics, Sixel/video, Kitty keyboard flag 4, locator/gesture/touch
mouse, general bidi, and many DEC private modes remain explicitly unsupported.

### Desktop model and platform integration

Ghostty documents multiple native windows with tabs and splits, macOS-native
components, Quick Terminal, AppleScript, Quick Look, secure keyboard entry,
and state recovery. Kiwi has one custom-rendered GLFW workspace window with
real tabs/splits. That is valuable core work but is not equivalent to
multi-window, native chrome, or restoration. The first Kiwi milestone is a
platform-neutral window/session manager; the platform adapter must own native
window creation and destruction while `kiwi.vt` remains free of host handles.

On macOS, Kiwi’s Cocoa bridge is real and verified for a private pasteboard,
drawable resize, Metal surface configuration, and development app-bundle
launch. An extracted release `.app` is now also launch-tested. Its current
accessibility adapter is one bounded static-text element for the active pane;
it does not expose editable text, ranges, selections, panes, or a completed
VoiceOver user experience. GLFW delivers committed Unicode codepoints but does
not expose IME preedit/composition, so composed East Asian input is a blocker
for daily-driver qualification.

### Configuration and appearance

Ghostty documents hundreds of text configuration options, CLI equivalents,
optional included files, platform-specific path precedence, runtime reload,
custom themes, and system dark/light theme selection. Kiwi’s strict parser is
deliberately smaller: it bounds file size and line count, rejects unknown keys,
supports a small set of terminal/rendering controls, and reloads with F6. This
is safer to extend than an unbounded ad hoc parser, but does not meet the
desired product surface yet. Kiwi will keep its bounded parser and add only
explicit, cycle-safe sources and documented precedence.

### Rendering, text, and images

Both projects are GPU terminal renderers. Kiwi has strong foundations in damage
tracking, grapheme safety, HarfBuzz shaping, fallback selection, glyph-ID
caching, bounded resource ownership, GPU recovery diagnostics, and Kitty image
composition. Ghostty has a broader end-user feature surface including font
feature selection, a large theme catalogue, and native application behavior.

Kiwi’s Kitty PNG/APNG/GIF smoke tests prove the renderer schedules the image
passes and frame updates. They are not pixel-readback tests; manual visual
confirmation remains part of the current image qualification.

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
- [GLFW platform adapter](src/kiwi/platform/window.lua)

### Ghostty, official documentation

- [features and compatibility principles](https://ghostty.org/docs/features)
- [configuration model](https://ghostty.org/docs/config)
- [VT sequence reference](https://ghostty.org/docs/vt/reference)
- [native application architecture](https://ghostty.org/docs/about)
