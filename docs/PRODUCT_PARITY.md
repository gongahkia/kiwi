# Terminal application parity

Kiwi's product is an experimental desktop terminal for Linux and macOS. The
terminal state machine, parser, process sessions, shaping stack and GPU renderer
are internal implementation components. The standalone libkiwi-vt header,
shared-library target, Lua facade, launcher, distribution and SDK tests have
been removed. There is no replacement public terminal SDK or C ABI commitment.

The GitHub description is:

> Cross-platform Terminal with GPU Acceleration

This assessment was updated on 2026-10-25. Implementation, local automated
verification, and desktop qualification are separate claims. The
[daily-driver ledger](DAILY_DRIVER_COMPATIBILITY.md) remains the release contract.
This change set improves the application; it does not establish complete parity.

## What the reference products establish

[Ghostty's action reference](https://ghostty.org/docs/config/keybind/reference)
provides a useful baseline for font sizing, pane navigation/resizing/zoom,
selection, history navigation and search. Its
[platform description](https://ghostty.org/docs/about) covers native macOS and
Linux applications. Windows should not be inferred from that comparison.

[WezTerm's feature list](https://wezterm.org/features.html) includes Windows,
macOS and Linux, local/remote multiplexing, searchable history, font fallback,
ligatures, colour emoji, richer text attributes, hot configuration reload,
SSH, serial connections and several image protocols. Matching that whole
product is substantially broader than building a dependable local terminal.

[Alacritty's README](https://github.com/alacritty/alacritty#readme) includes
Windows, macOS and Linux, and deliberately delegates tabs and splits to other
programs. Its [configuration reference](https://alacritty.org/config-alacritty.html)
covers working directories, live reload, font sizing, history/search and a vi
navigation mode. Kiwi does not need the union of all three products' features
to offer useful everyday terminal behavior.

## Current application baseline

| User need | Kiwi implementation | Evidence and remaining gap |
| --- | --- | --- |
| Start a shell or explicit program | POSIX PTYs, arguments, absolute working directory, headless help/version; explicit commands/directories bypass saved layouts | Options and real PTY tests. Failed `chdir` exits before executing the command. Windows ConPTY is absent. |
| Tabs, splits, windows | Bounded workspace tree, independent PTYs, same-process windows, session movement, saved topology with fresh shells | Model/manager tests and Cocoa smokes. Saved layouts do not preserve running processes. Linux native tab chrome remains experimental. |
| Navigate and arrange panes | Previous tab, cyclic/directional pane focus, nearest-divider resize, equalize and temporary zoom | Nested-layout tests and `interaction-smoke`; minimum geometry is checked before spawning another shell. Dragging native dividers and Linux desktop qualification remain open. |
| Comfortable font size | Increase/decrease/reset per window, including Command shortcuts on macOS | Bounds tests and live font changes; reset uses configured size. Changes are transient and do not rewrite config. |
| Copy, paste, history | Unicode selection, bracketed paste, select all, oldest/live history, clear history while retaining visible text | Clipboard/state tests, alternate-screen isolation, private Cocoa pasteboard smoke. X11 primary selection and broad Wayland clipboard qualification remain open. |
| Search | Exact retained-text search, next/previous result, palette/menu/shortcut routing | Search and interaction tests. Regex, indexing and vi copy mode remain absent. |
| Responsive output | Bounded PTY reads, immediate continuation after budget exhaustion, expired-deadline handling, one-shot host readiness notifications | Real PTY tests, sanitizer-tested C watcher, native host-wake smoke. No comparative latency, energy or throughput claim. |
| Configuration and discoverability | Bounded text config, themes, transactional automatic/manual reload on WGPU, title-bar errors, 37 built-in palette entries, Edit/View/Window menu actions | Parser, debounce/dependency tests, native file-watch lifecycle tests on Linux/macOS, allocation-failure tests and live Cocoa reload checks. Worst-case reload memory/latency and Linux graphical execution remain work. |
| Unicode and rendering | Unicode 17 grapheme/width handling, HarfBuzz shaping, styled FreeType/Fontconfig faces with synthesis, reclaimable bounded glyph storage, five underline styles/colours, primary-screen reflow | Text, bitmap, cache-churn, renderer suites and native underline readback. Bidi, colour emoji and visual quality on every GPU remain incomplete. |
| Terminal protocols | Documented VT subset, terminfo, true colour, mouse/focus, keyboard protocols, OSC metadata, bounded Kitty images | Conformance/fuzz tests; nine real-program PTY workflows passed on Linux and ten on macOS, with saved-file assertions and replay. Native input/rendering and broader application/version coverage remain separate. |
| Shell and remote use | Reversible Bash/Zsh/fish/Nushell integrations, OSC directory/command metadata, explicit terminfo SSH helper | Script tests, interactive shells and four real loopback SSH workflows passed on Linux/macOS. Nushell was exercised on macOS only. Remote OS/network differences and the transfer helper need further qualification; persistent remote sessions are absent. |
| Desktop integration | Cocoa menus/tabs/pasteboard/IME/accessibility bridges; GTK adapters and experimental GL presenter | Local Intel Cocoa evidence, Linux headless checks and GTK ABI compilation. Default GLFW/Wayland still lacks a composition bridge. Real IME workflows, screen readers, monitor transitions and Linux desktops require qualification. |
| Distribution | Linux/macOS build paths, local archives, checksums, development/release app launchers | Reproducibility gate exists. Signing/notarization, clean-machine dependency experience and Windows distribution remain separate deliverables. |

The supported application path for the new workspace actions is the WGPU
controller. The GTK GL prototype still has a narrower feature set and must not
be described as equivalent merely because it shares a command catalogue.

## Engineering work, in priority order

Effort bands describe the scope of code and validation, not delivery promises:
small = one existing subsystem; medium = several interacting subsystems;
large = native lifecycle or rendering changes; very large = a platform port or
new persistent service.

| Priority | Work | Complexity | Acceptance criterion |
| --- | --- | --- | --- |
| P0 | Keep launch, selection, workspace and scheduler regressions covered | Medium, ongoing | Headless/full/PTY checks pass; live actions and host wake pass on each released host. |
| P0 | Qualify real terminal applications | Large | tmux, Neovim, Vim, shells, SSH and full-screen tools pass the existing daily-driver corpus without unsupported-sequence failures being hidden. |
| P0 | Validate Linux desktop behavior | Large | Run both available Wayland/X11 paths, input/clipboard/IME, fractional scale, resize/minimize, GPU recovery and new interaction/wake gates. |
| P1 | Finish text presentation | Large | Bold/italic faces, bounded glyph recovery and underline variants/colours are implemented. Broader screenshot/readback fixtures across fallback, DPI, selection, wide and combining text remain required. Colour emoji requires atlas/texture-format work. |
| P1 | Qualify configuration reload under load | Medium/large | Transactional, debounced automatic WGPU reload and visible errors are implemented. The 10,000-line font-change benchmark still reached 1,925 ms wall p95 and 1,187 MiB sampled process RSS after optimization. Linux native watcher tests passed; Linux graphical reload and GTK GL parity remain open. |
| P1 | Improve everyday discoverability | Medium | Visible search feedback, keyboard-only selection, useful pane/tab titles, consistent shortcuts, unsaved-running-process close policy, accessibility validation. |
| P1 | Windows, if all-three-platform delivery is required | Very large; release blocker | ConPTY lifecycle, HWND/DX12 surface, font discovery, native input/clipboard/IME/accessibility, packaging and actual Windows CI/desktop evidence. Follow [ADR 0038](adr/0038-windows-native-feasibility.md). |
| P2 | Expand search and desktop conveniences | Medium | Bounded regex search with cancellation, primary selection policy, URL hint navigation and tested configuration migration. |
| P2 | Measure performance and idle cost | Medium/large | Same-machine baseline/candidate reports for cold launch, interactive latency, saturated output fairness, large history search, resize, RSS and idle wakeups; no regression in input responsiveness under load. |
| P3 | Remote persistent multiplexing, serial ports, additional graphics protocols | Very large | Explicit product demand and independent session/protocol contracts before implementation. |

Building a new terminal from scratch would still require these process,
rendering, Unicode, input and qualification layers. Retaining Kiwi's existing
application and reducing its public SDK surface keeps the work concentrated on
user-visible behavior. A GPU backend alone establishes neither speed nor parity.

## Scheduler ownership and limits

Each live native window owns one readiness worker watching up to 64 PTYs plus
one configuration event descriptor. The
worker polls readable/closed descriptors and posts a host event once per arm.
It never reads terminal bytes, runs Lua, accesses terminal state or touches GPU
objects. The UI thread rearms it before waiting, drains bounded output, parses
and renders. Destruction joins the worker before native host termination.

A closed or replaced descriptor can produce a harmless stale wake; the UI
thread rechecks its current sessions. EOF PTYs are excluded on the next arm.
The fallback wait remains bounded at 50 ms visible / 250 ms minimized; pending
writes and system-appearance checks still use these turns. The GTK pump now
waits on its main context with a timeout source instead of unconditional sleep.
Further idle-energy reductions require measuring and scheduling those remaining
polling responsibilities, not removing the fallback blindly.

The native watcher tests cover one-shot behavior, rearming unread output,
replacement, EOF, invalid bounds and repeated shutdown. The host smoke supplies
a deliberately delayed child and a two-second event-loop timeout; it verifies
that output interrupts the wait. It is not a display-latency benchmark.
