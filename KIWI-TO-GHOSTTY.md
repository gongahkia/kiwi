# Kiwi → Ghostty capability-gap map

## Conclusion

Kiwi is in the same *category* as Ghostty—a GPU-accelerated terminal emulator—but it is not yet in the same product class. Kiwi is deliberately a Linux-only, rendering-first research platform with a bounded, documented terminal contract. Ghostty is a configurable, native desktop terminal application for macOS and Linux whose stated goal is broad xterm and modern-protocol compatibility. Closing that distance is therefore not one renderer task: it requires a substantially broader terminal contract, an application/session layer, configuration and platform work, and a stable core boundary.

This document maps capabilities Ghostty demonstrably has that Kiwi does not, or has only as a deliberately narrower implementation. It does **not** claim that Ghostty implements every terminal sequence perfectly, that its public library API is stable, or that either project is faster. Those would need separate, version-pinned compatibility and benchmark work.

## Audit boundary and terminology

**Kiwi baseline.** This audit uses the checkout at `832d5e236e78aca66da33486fa879c1de0fc0b7b` (2026-08-16). The strongest local evidence is Kiwi's [README](README.md), [conformance contract](docs/CONFORMANCE.md), [architecture](docs/ARCHITECTURE.md), `src/kiwi/app/main.lua`, and deterministic tests. Kiwi itself says that it is not a daily-driver emulator and does not claim full VT/xterm compatibility.

**Ghostty baseline.** Product claims are taken from Ghostty's official documentation, consulted on 2026-08-16. API claims were also checked against upstream source commit [`ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949`](https://github.com/ghostty-org/ghostty/tree/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949). Ghostty's sequence reference explicitly says it is incomplete; “broader” below means Ghostty's stated compatibility objective and documented capabilities, not an assertion that every individual escape sequence has been independently tested here.

**Meaning of “missing.”** A row is a gap only where Ghostty documents or exposes the feature and Kiwi either documents it as out of scope or the current source has no corresponding application capability. It is not a claim that a feature is desirable for Kiwi's research goals. “Partial” means the underlying Kiwi kernel has related functionality but not the user-facing or compatibility-complete form.

## Implementation status after this audit

The original matrix is intentionally preserved as the baseline. Kiwi has since
closed several foundational rows: an internal host-neutral `kiwi.vt.terminal`
facade with typed effects and render updates; terminal-local OSC palette/default
colour operations; a strict XDG configuration file with themes, font controls,
reload, and an explicit OSC 52 write-only opt-in; supported Kitty keyboard flags
1, 2, and 8; and a bounded tab/split workspace topology. The live GLFW app now
uses tabs and rendered vertical/horizontal split panes. Each visible pane owns
an isolated terminal/PTY, is assigned its layout grid, and is composed through
one shared WGPU surface acquisition with viewport/scissor isolation; inactive
tabs continue to service their PTYs.

The major remaining gaps are wider xterm/mouse/keyboard behavior,
native multi-window UI, system appearance/theme catalogues, native
accessibility, macOS support, and a published C ABI. This is progress toward
the architecture, not Ghostty parity.

## High-level comparison

| Area | Ghostty | Kiwi today | Gap assessment |
| --- | --- | --- | --- |
| Product intent | A daily-use, native terminal application for macOS and Linux. | A rendering-first terminal research platform, explicitly not a daily-driver or full-compatibility claim. | **Foundational gap.** The projects optimize for different completion criteria. |
| Terminal compatibility | States an xterm-first, protocol-origin and de-facto-standard compatibility policy, with a VT reference that lists many supported controls and says more are supported. | A defined C0/ESC/CSI/OSC subset, exact 16-colour terminfo contract, and explicitly bounded unsupported cases. | **Large, ongoing gap.** This is not a single checklist item. |
| Native application shell | Native windows, tabs, and splits; native components on both supported desktop platforms. | One GLFW/Vulkan window with bounded tabs and real split panes, per-pane PTYs, grid resize, pointer focus routing, and shared-frame composition. | **Partial application gap.** Multi-window UI, native tab chrome, persistence, and platform-native integration remain absent. |
| Platforms | Shipping macOS and Linux applications; Linux supports Wayland and X11. Windows application support is planned, not current. | Linux x86_64 only; no macOS or Windows runtime is claimed. | **Large platform gap.** macOS is a Ghostty advantage; Windows is not yet an app-level Ghostty advantage. |
| Configuration and themes | Text config file, CLI equivalents, runtime reload, hundreds of options, built-in theme catalogue and system dark/light switching. | A bounded XDG config file, small `kiwi`/`nord`/`light` themes, environment overrides, and F6 reload cover core local controls. No broad option surface, includes, system appearance, or large theme catalogue exists. | **Partial product gap.** |
| Core reuse | Ghostty has a C-ABI core used by its platform GUIs, although its standalone public API remains unstable. | Kiwi's application now consumes experimental `kiwi.vt`/`kiwi.vt.headless` Lua API v1, but no public C ABI or foreign-runtime ownership contract exists. | **Architectural gap.** Detailed in [KIWI-TO-LIBGHOSTTY](KIWI-TO-LIBGHOSTTY). |

## Terminal-emulation and protocol gaps

| Ghostty capability | Kiwi evidence and current limit | What Kiwi would need |
| --- | --- | --- |
| **Broad xterm-oriented behavior.** Ghostty explicitly targets xterm behavior where appropriate and also follows protocol-origin behavior for modern extensions. Its public reference includes, among many others, full reset (`RIS`), application keypad, DEC alignment test, horizontal margins, palette operations, clipboard OSC, and desktop-notification/progress OSCs. | Kiwi's contract intentionally lists a narrower subset. It now replies to declared standard/DEC mode queries (`DECRQM`) and has palette operations, but reset coverage, DEC private modes, and xterm/VT100 certification remain incomplete. | Establish a compatibility policy, versioned sequence matrix, test corpus, and per-sequence implementation plan. Do not advertise a feature merely because the parser can retain some state for it. |
| **Resize reflow.** The public `libghostty-vt` header describes line wrapping and reflow on resize. | Kiwi now reflows bounded primary history on a column change, preserves grapheme-cell spans, maps stable row/cell-gap references for selection and shell metadata, invalidates search, and keeps the scrollback cap. The alternate screen remains a fixed-grid resize. Fixed Kitty image placements are released rather than using stale cell rectangles. | **Partial gap.** Exercise long-running application workloads and expand the image-placement model before claiming broad xterm-equivalent resize behavior. |
| **Terminal-side effects as product capabilities.** Ghostty documents title, working-directory, device/size responses, desktop notifications, progress, controlled clipboard write handling, unknown-sequence reporting, and terminal response callbacks. | `kiwi.vt` now offers bounded typed in-process effects and response draining for title/PWD/shell markers/bells/PTY replies; the app applies its own policy. OSC 52 remains default-denied, and notifications/progress have no native desktop surface. | **Partial gap.** Expand only with explicit permissions, limits, and payload-free diagnostics. |
| **Capability signaling and remote setup.** Ghostty supplies an `xterm-ghostty` terminfo flow and a `+ssh` wrapper that can install it remotely, with a documented fallback when that fails. | Kiwi keeps its 16-colour `TERM=kiwi` contract and now has explicit `kiwi-ssh`, which copies the compiled entry to a remote per-user cache then falls back visibly to `xterm-256color`. It has no SSH option forwarding, destination cache, automatic shell wrapper, or real-host validation. | **Partial gap.** Preserve the conservative capability contract and extend the SSH frontend only with a tested argument/policy model. |
| **Keyboard and mouse breadth.** Ghostty documents Kitty keyboard support and its public VT library supplies terminal-configured key, mouse, and focus encoders. | Kiwi has legacy keys plus a negotiated Kitty disambiguation subset; X10/normal/button/any mouse tracking with X10, UTF-8, URXVT, or SGR encoding; and focus reporting. Pixel, gesture, highlight, locator, and additional Kitty keyboard flags remain excluded. | **Partial gap.** Broaden only through app-facing event normalization and sequence-level conformance tests; preserve local-selection precedence and security rules. |
| **Terminal color/palette operations.** Ghostty's VT reference includes OSC palette and foreground/background/cursor color operations and resets. | Kiwi has bounded OSC 4/10/11/104/110/111 palette/default-colour query, update, and reset behavior while intentionally withholding truecolour terminfo advertisement. OSC 12 and remaining colour controls are absent. | **Partial gap.** Add only tested operations with clear renderer/configuration precedence. |
| **Clipboard protocol integration.** Ghostty documents OSC 52 among its VT facilities and exposes a library callback for clipboard writes. | Kiwi supports bounded local clipboard copy/paste and an explicit default-denied OSC 52 write-only subset. Primary selection, rich formats, automatic synchronization, reads, queries, and clear are absent. | **Partial gap.** Retain default deny and preserve per-operation limits. |
| **Shell integration delivered by the application.** Ghostty can automatically inject integrations for bash, elvish, fish, nushell, and zsh, with prompt navigation/selection and optional SSH wrapping. | Kiwi automatically injects its reversible Bash/Zsh/fish scripts for the initial default shell, with configuration disablement and manual switched-shell assets. It has no elvish/nushell support, prompt UI, persistence, or automatic `ssh` function wrapping. | **Partial gap.** Broaden only with per-shell startup and remote-session tests. |
| **Kitty graphics as a broad terminal protocol.** Ghostty documents support for the Kitty graphics protocol and exposes a renderer-neutral graphics interface in `libghostty-vt`. | Kiwi supports a carefully bounded APC-G direct-image/cache/placement/composition subset: PNG, APNG, and GIF in the current implementation, with no claim of broad Kitty-client compatibility. | Expand protocol coverage only through a compatibility matrix. Keep image decode limits, cache budgets, placement lifetime, z-order, and cursor movement explicitly specified. The audit does not establish an exact GIF/APNG feature-for-feature comparison with Ghostty. |

### Important protocol qualification

The Ghostty reference is not exhaustive, and Kiwi's source does contain more than a toy parser: alternate screen, margins, scrollback, UTF-8 streaming, grapheme clusters, 256/RGB SGR state, OSC 8, Kitty keyboard negotiation, classic/UTF-8/URXVT/SGR mouse and focus reporting, and limited Kitty graphics all have deterministic tests. The gap is the **supported contract and breadth**, not “Ghostty has a parser while Kiwi does not.”

## Text, font, and rendering-product gaps

| Ghostty capability | Kiwi status | Gap assessment |
| --- | --- | --- |
| **User-configurable font features and ligatures.** Ghostty documents ligature rendering plus selective OpenType feature enable/disable. | Kiwi has HarfBuzz shaping, Fontconfig fallback, a glyph-ID atlas, and opt-in ligature/`calt` startup toggles. | **Partial gap.** Kiwi has the foundation but not Ghostty's broader, documented end-user font-configuration surface. |
| **Theme product.** Ghostty ships hundreds of themes, custom themes, and automatic system dark/light switching. | Kiwi has a small persistent XDG configuration with three built-in themes and runtime reload, but no broad catalogue, custom theme import, or system-appearance integration. | **Clear product gap.** |
| **Native window behavior and system integration.** Ghostty's macOS application integrates native tabs/splits, Quick Terminal, AppleScript, Quick Look, secure keyboard entry, and state recovery; Linux is a GTK4 application. | Kiwi has GLFW-hosted tabs/splits rather than native widgets, and still has no multi-window/session restoration or AT-SPI, NSAccessibility, or UI Automation adapter. | **Clear platform/UI gap.** Do not infer that Ghostty's native UI claim alone proves every assistive-technology scenario; that needs a dedicated accessibility audit. |
| **Renderer portability.** Ghostty documents Metal on macOS and OpenGL on Linux. | Kiwi uses a GLFW/WGPU native bridge with Vulkan on its supported Linux path. | **Platform scope gap, not a simple renderer-quality ranking.** GPU acceleration exists in both projects. |
| **Bidirectional text.** | Ghostty's feature page says it correctly clusters some Arabic/Hebrew graphemes but currently supports only left-to-right text. Kiwi explicitly does not implement bidi. | **Not a Ghostty advantage today.** Neither project should claim general bidi/reordering from the evidence used here. |

Kiwi should not chase renderer backend parity as a proxy for product parity. Its font fallback, HarfBuzz shaping, glyph caching, damage tracking, GPU timing diagnostics, animation scheduler, and bounded image passes are already substantial renderer work. The larger gaps are user configuration, platform UI, and the terminal contract around that renderer.

## Desktop-application gaps

| Ghostty capability | Kiwi status | What is missing |
| --- | --- | --- |
| Multiple windows, native tabs, and splits. | One GLFW window with rendered tabs/splits, pane hit-testing, per-pane PTY ownership, and bounded session layout. | Multiple windows, native-widget adapters/chrome, persistence and restoration policy, and platform lifecycle integration. |
| Persistent user configuration, CLI parity, includes, and runtime reload. | Bounded XDG discovery, validation, environment precedence, and F6 reload exist for a small configuration set. | CLI parity, includes, schema tooling, broader settings, and per-platform paths. |
| Theme inventory and appearance switching. | Three built-in themes and runtime renderer/font reload; no system appearance adapter. | Theme format/import, packaged catalogue, appearance signals, and a wider precedence model. |
| Linux desktop integration and distribution support. | Fedora-oriented source prerequisites, a local Linux x86_64 release artifact, and Nix support. | A supported-install matrix, desktop entry/icon/session behavior, GTK/Wayland/X11 strategy or an equally documented alternative, packaging/release policy, and end-user support boundary. |
| macOS-native application. | A feasibility assessment exists but Kiwi claims no macOS runtime or artifacts. | Cocoa/Metal or chosen platform abstraction, input/IME/accessibility, packaging/signing, and on-device verification. |
| Automatic shell injection and SSH convenience workflow. | Initial Bash/Zsh/fish injection and explicit remote terminfo upload/fallback exist. | Automatic wrapping, option forwarding, remote cache policy, additional shells, and real-host tests. |

## Features Kiwi already has, or where Ghostty is not demonstrably ahead

This prevents the roadmap from becoming a misleading one-way feature list.

- Both are GPU-accelerated terminal projects.
- Kiwi already has a real PTY, bounded primary scrollback, alternate screen, resize propagation, terminal replies, Unicode 17 extended grapheme processing, HarfBuzz shaping, Fontconfig fallback, mouse/focus support, selection, scrollback search, safe hyperlinks, shell markers, local clipboard, replay/recording, and Kitty graphics support.
- Kiwi has explicit bounded GIF/APNG playback and an HTTPS image helper. This audit does **not** establish that Ghostty lacks those features; it only establishes Ghostty's documented Kitty graphics support and Kiwi's deliberately narrow composition contract.
- Ghostty's desktop application does not currently support Windows according to its own feature page; it is planned. Kiwi also does not support Windows.
- Neither project's public documentation cited here establishes general bidirectional-text layout support.
- Kiwi's trusted local renderer-extension API, GPU timing probes, pass budgets, and research diagnostics are not mapped as Ghostty deficits because this audit is about what Kiwi lacks, not a claim that Ghostty must expose the same development interfaces.

## Recommended order if the goal is “closer to Ghostty”

1. **Decide the target, before adding isolated features.** Either preserve Kiwi as a research terminal with a precise bounded contract, or adopt a daily-driver compatibility target. The latter requires a maintained sequence/terminfo matrix, not ad hoc support driven by screenshots.
2. **Strengthen terminal semantics first.** Prioritize reflow architecture, reset/mode behavior, input protocol breadth, effects/callback policy, and a realistic terminfo/capability plan. These are prerequisites for dependable TUIs and embedding.
3. **Extract a core boundary.** Create the `libkiwi-vt` boundary described in [KIWI-TO-LIBGHOSTTY](KIWI-TO-LIBGHOSTTY) before building tabs/splits across a tightly coupled application state.
4. **Build the desktop product layer.** Add configuration/themes, multi-surface session management, native integration, shell/SSH workflow, and accessibility adapters above the stable core.
5. **Add platforms only with native verification.** macOS and Windows are separate engineering efforts; neither should be represented as supported from cross-build feasibility work alone.

## Sources

### Kiwi, local checkout

- [README: scope, commands, media, deliberate limits](README.md)
- [Conformance contract and evidence boundaries](docs/CONFORMANCE.md)
- [Architecture: parser/state/PTY/renderer composition](docs/ARCHITECTURE.md)
- [Live application composition](src/kiwi/app/main.lua)
- [Parser interface](src/kiwi/terminal/parser.lua), [terminal state](src/kiwi/terminal/state.lua), and [observation-only snapshot](src/kiwi/terminal/snapshot.lua)

### Ghostty, official material

- [About Ghostty: native application and libghostty architecture](https://ghostty.org/docs/about)
- [Feature overview: platforms, tabs/splits, themes, ligatures, graphemes, Kitty graphics, compatibility policy](https://ghostty.org/docs/features)
- [Configuration: config file, CLI mapping, reload, and option scope](https://ghostty.org/docs/config)
- [Linux support and Wayland/X11/package statement](https://ghostty.org/docs/linux)
- [Shell integration](https://ghostty.org/docs/features/shell-integration) and [SSH workflow](https://ghostty.org/docs/features/ssh)
- [VT reference and its explicit work-in-progress limitation](https://ghostty.org/docs/vt/reference)
- Audited source headers at [`ad6e72d`](https://github.com/ghostty-org/ghostty/tree/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949): [`vt.h`](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt.h), [`terminal.h`](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt/terminal.h), and [`kitty_graphics.h`](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt/kitty_graphics.h)
