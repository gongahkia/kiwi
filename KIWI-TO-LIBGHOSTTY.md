# Kiwi → libghostty: feasibility and extraction map

## Conclusion

Yes: extracting a useful `libkiwi` is feasible. It is **not only** a packaging exercise. This checkout now publishes a deliberately narrow experimental `libkiwi-vt` C API v1, but it is not yet a full `libghostty-vt`-class embedding surface. The realistic peer is an emulator library called **`libkiwi-vt`**, not the current GLFW/WGPU application and not an immediate clone of all of Ghostty.

Kiwi already contains a strong candidate terminal kernel: incremental parsing, UTF-8/grapheme/width handling, screen and bounded scrollback state, terminal input encoding, semantic selection/search/link/shell metadata, damage tracking, and bounded Kitty graphics state. The present implementation is nonetheless application-owned LuaJIT code with mutable Lua tables, direct `Parser → State` calls, direct GPU/media coupling in terminal state, a JSON observation snapshot only, and no stable ABI, ownership rules, or host callback contract. Those seams must be created before another program can safely embed it.

The initial extraction now exists as the experimental, host-neutral `kiwi.vt`
Lua API v1, with `kiwi.vt.render_state` and `kiwi.vt.headless`: it owns
incremental writes, bounded typed effects, response draining, borrowed
render-update views, explicit damage acknowledgement, and logical headless
projection without importing PTY, GLFW, WGPU, or font modules. `make
libkiwi-vt` produces a reproducible Linux x86_64 SDK archive containing that
Lua core plus `include/kiwi/vt.h` and `lib/libkiwi_vt.so`; the C v1 layer offers
opaque handles, versioned options, explicit destruction, status codes, byte
writes, resize, logical-text projection, frozen logical cell/grid snapshots,
and one-at-a-time response draining.
`make libkiwi-vt-check` proves both standalone consumers start without
renderer, platform, FFI, or media-decoder modules. Kiwi's application consumes
the richer Lua facade through a deliberately private mutable-state adapter.
Both surfaces remain single-threaded and pre-1.0. The next publication work is
to expand the C contract only where a real consumer needs it—not to export
mutable Lua tables.

## What “libghostty” means in this comparison

Ghostty's project documentation calls its shared Zig core **`libghostty`**, a cross-platform C-ABI-compatible library that the macOS and Linux applications consume. The public upstream header audited here is specifically **`libghostty-vt`**, an incomplete and explicitly unstable C API for terminal emulation and rendering data. It includes terminal state, rendering state, input encoding, formatters, snapshots, selection, Kitty graphics, memory allocation, and WebAssembly helpers.

This document compares a proposed `libkiwi-vt` primarily with that public `libghostty-vt` surface—not with Ghostty's complete font/render/platform core. A future `libkiwi` that also exports font selection and a concrete GPU renderer would be a larger, separate product with materially different portability and dependency constraints.

## Audit boundary

**Kiwi baseline:** checkout `832d5e236e78aca66da33486fa879c1de0fc0b7b` (2026-08-16). Evidence comes from [architecture](docs/ARCHITECTURE.md), [application composition](src/kiwi/app/main.lua), terminal modules under [`src/kiwi/terminal`](src/kiwi/terminal), input modules under [`src/kiwi/input`](src/kiwi/input), and renderer modules under [`src/kiwi/renderer`](src/kiwi/renderer).

**Ghostty baseline:** upstream source commit [`ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949`](https://github.com/ghostty-org/ghostty/tree/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949), dated 2026-08-15. The headers themselves warn that the API is work in progress and not stable. This is important: `libghostty-vt` is a useful architectural reference, not a frozen ABI to copy mechanically.

## Proposed scope: `libkiwi-vt`, not “Kiwi without a window”

### Include in the library

- VT byte-stream parsing, UTF-8 streaming, grapheme clustering, deterministic width policy, terminal actions, screen/cursor/mode state, primary/alternate screens, scrollback, and resize semantics.
- A renderer-neutral **render-state view**: visible rows/cells/styles/cursor/selection/dirty information, with an explicit snapshot/update lifetime.
- Terminal-generated effects through callbacks: PTY response bytes, title, bell, working-directory/shell markers, hyperlinks, clipboard requests, diagnostics, and unknown sequences. The embedder decides which effects are enabled.
- Keyboard, mouse, focus, and paste encoding that is configured from terminal modes but has no GLFW dependency.
- Safe, versioned snapshot **encode and restore** API, if restoration is made a supported contract.
- Optional semantic extras—selection, exact search, OSC 8 links, shell/command regions—only if they have clear host-neutral semantics and resource limits.
- Optional Kitty-graphics protocol state, with caller-supplied decode/storage callbacks and renderer-facing placement/image views.

### Keep outside the library

- `forkpty`, child process launching, signals, polling, and environment policy (`src/kiwi/process/pty.lua`). An embedding program needs its own process model.
- GLFW window creation/event callbacks, clipboard bridge, URL opening, and desktop accessibility adapters.
- WGPU device/surface ownership, shaders, pipelines, GPU texture lifetime, pass registry, diagnostics UI, and frame scheduler.
- Fontconfig discovery, FreeType faces/rasterization, HarfBuzz integration, and the concrete glyph atlas. They can become a later `libkiwi-text`/renderer layer, but should not block `libkiwi-vt` extraction.
- URL downloading (`script/kiwi-image`) and any network policy. A VT library must never fetch remote media as a consequence of terminal output.

### Package shape

| Proposed artifact | Responsibility | Current source candidates | Deliberate exclusion |
| --- | --- | --- | --- |
| `libkiwi-vt` | Parsing, state, Unicode/width, screen/scrollback, Lua effects/input/views, plus C v1 byte/resize/text/response/effect polling, logical render updates, and text/key/mouse/focus/paste encoding. | The renderer-free SDK built by `script/package-libkiwi-vt`: selected `terminal/*`, `unicode/*`, `input/{keyboard,mouse,search,selection}`, `vt/*`, `include/kiwi/vt.h`, and `libkiwi_vt.so`. | PTY, GLFW, WGPU, font discovery/rasterization, renderer/platform/FFI modules, the default media decoder, and C effect callbacks/selection/media APIs. |
| `libkiwi-render-state` or a `libkiwi-vt` submodule | Transactional, dirty-region-aware screen projection for a renderer. | Terminal damage plus the read-only data requirements currently consumed by `renderer/*`. | WGSL, GPU resources, frame scheduling. |
| `libkiwi-media` (optional) | Kitty image transport/cache/placement semantics and host callbacks for decode/storage. | `terminal/{kitty_graphics,kitty_placements,image_decoder}` after decoupling. | libpng/giflib hard dependency, GPU texture upload, network URL fetching. |
| `kiwi-app` | PTY, window, WGPU renderer, fonts, clipboard/URL policy, shell integration UX, configuration, packaging. | `app`, `process`, `platform`, `gpu`, `renderer`, `font`, platform input adapters. | Public embedding ABI. |

This division is intentional. A consumer that only needs a terminal model should not have to link GLFW, Vulkan, Fontconfig, GIF/APNG libraries, or a process launcher.

## Current Kiwi assets that are worth extracting

| Existing Kiwi capability | Evidence | Value to a hypothetical library | Extraction status |
| --- | --- | --- | --- |
| Incremental parser with bounded parameter/string limits and an action sink. | [`terminal/parser.lua`](src/kiwi/terminal/parser.lua) accepts a callback or state sink; deterministic/fuzz tests cover chunk boundaries. | Good library core: it already has an abstraction point. | **Reusable, but formalize error/result reporting and continuation serialization.** |
| Terminal state, cursor/margins, primary/alternate screens, editing, scrollback, responses, modes. | [`terminal/state.lua`](src/kiwi/terminal/state.lua), [`screen.lua`](src/kiwi/terminal/screen.lua), [`scrollback.lua`](src/kiwi/terminal/scrollback.lua). | Core emulator state. | **Reusable, but currently a mutable Lua object with presentation and policy concerns mixed in.** |
| Unicode 17 grapheme processing and deterministic width policy. | `unicode/*`, `terminal/{utf8,width}.lua`, [text contract](docs/TEXT.md). | A strong differentiator for an embedding API, if the policy/version becomes explicit. | **Reusable.** Export the Unicode data version and width policy in the API. |
| Cell-level damage and separate text damage. | [`terminal/damage.lua`](src/kiwi/terminal/damage.lua) and renderer tests. | Useful basis for incremental render updates. | **Needs a stable read model and lifetime/clear rules.** |
| Selection, exact search, hyperlinks, shell markers, command regions. | `input/{selection,search}.lua`, `terminal/{hyperlink,shell_integration,command_regions}.lua`. | Useful optional semantic APIs above raw terminal cells. | **Partition into optional features.** Do not make a window-title search UI or local URL opener part of the library. |
| Keyboard/mouse protocol encoders. | [`vt/input.lua`](src/kiwi/vt/input.lua), [`input/keyboard.lua`](src/kiwi/input/keyboard.lua), [`input/mouse.lua`](src/kiwi/input/mouse.lua). | Natural host-neutral library functionality. | **Initial extraction complete.** Public symbolic keys, modifier bits, text/key/paste helpers, and a stateful mouse encoder take no GLFW object. A render update publishes the needed input modes. |
| Kitty image cache/placements and bounded PNG/APNG/GIF playback. | `terminal/{kitty_graphics,kitty_placements,image_decoder}.lua`, [Kitty graphics contract](docs/KITTY_GRAPHICS.md). | Optional modern terminal facility. | **Requires a hard boundary.** Current image lifetime is coupled to application-side decode and GPU upload assumptions. |
| Recording/replay and JSON snapshot. | [`replay.lua`](src/kiwi/replay.lua), [`terminal/snapshot.lua`](src/kiwi/terminal/snapshot.lua). | Good test and diagnostic assets. | **Not yet a persistence API.** Kiwi's current snapshot is observation-only and cannot restore terminal state. |

## Comparison with `libghostty-vt`

| Concern | `libghostty-vt` as audited | Current Kiwi / proposed `libkiwi-vt` | Gap and design response |
| --- | --- | --- | --- |
| **Public boundary** | C header with opaque handles and a documented API taxonomy; callable from C and Zig. Header warns that it is incomplete and unstable. | Experimental LuaJIT API v1 plus experimental Linux x86_64 C API v1: documented opaque handles, header, shared object, and C consumer/check. The C surface covers bytes, resize, logical text, responses/effect polling, cell/grid render updates, and text/key/mouse/focus/paste encoding. | **Partial gap.** Kiwi now has a C entry point, but not `libghostty-vt`'s broad embedding taxonomy or non-C bindings. |
| **Lifecycle, allocation, and errors** | Explicit `new/free` lifecycles, result codes, and optional custom allocator interface; documented borrowed-pointer lifetimes. | The C layer has explicit `new/free`, versioned/size-tagged options, bounded result codes, and borrowed error strings. It uses one internally allocated LuaJIT state per handle, with no custom allocator or ABI-stability promise. | **Partial gap.** Keep the small contract experimental; add allocator control only for an actual consumer need. |
| **Byte-stream processing** | `GhosttyTerminal` receives VT bytes and retains parser continuation with explicit APIs. | `Parser:feed` sends actions directly to `State`; it is already incremental and bounded. | Preserve the parser's strengths but expose one terminal-write function plus well-defined continuation/limit configuration. Do not expose action tables as a permanent ABI. |
| **Terminal effects / host policy** | Opt-in synchronous callbacks for PTY replies, bell, title/PWD, size/device/color queries, clipboard writes, notifications, progress, and unknown sequences; reentrancy is documented as forbidden. | Lua v1 queues bounded typed effects. C v1 now polls one typed effect at a time and uses a deterministic byte-safe JSON payload; it never invokes a foreign callback or OS action. PTY replies remain separately drainable. | **Partial gap.** C lacks a typed callback vtable and per-effect C structs. Keep OSC 52 default-denied unless the host enables it. |
| **Render-state contract** | Separate render-state handle designed for incremental updates; exposes global/row dirty state, cell/row iterators, cursor and color data, with begin/end update for short terminal lock windows. | Lua v1 has copied cell/row accessors, cursor/selection data, and explicit acknowledgement. C v1 mirrors an opaque begin/end update with copied grid/cursor/damage state and per-cell UTF-8/style/color data; a separate copied input-mode query exposes host input policy without holding a render update. No operation may interleave with an active update. | **Partial gap.** C lacks row iterators, precise damage ranges, selection data, and a live-renderer migration. It creates no GPU objects. |
| **Threading** | Render-state documentation describes a controlled lock-held update window for a renderer/IO-thread design; individual callback contracts are explicit. | Lua API v1 and C API v1 both explicitly require single-threaded, non-concurrent terminal use. The C handle owns one private LuaJIT state; the app remains one LuaJIT/GLFW event loop. | **Partial gap.** The constraint is now explicit, but there is no renderer/IO synchronization model. Do not imply thread safety because data is momentarily read-only. |
| **Scrollback and reflow** | Supports scrollback, resize reflow, and caller-driven bounded incremental compression. | Bounded scrollback and primary-screen column reflow exist. Reflow preserves grapheme cells and remaps semantic positions, but it has no host-driven compression lifecycle and releases fixed Kitty placement anchors. | **Partial gap.** Expose reflow/eviction events, quotas, and compression controls in the eventual API; do not make placement geometry a silent side effect. |
| **Snapshots** | Binary CRC-protected encoder plus a decoder that can restore a renderable terminal before incrementally prepending history; format v1 is also explicitly not compatibility-guaranteed. | Versioned JSON view of visible state and metadata only; no restore API. | Do not call Kiwi's current snapshot persistence. Add a decoder/restore lifecycle, parser-continuation rules, resource limits, and version policy—or retain replay as the supported persistence mechanism. |
| **Input encoding** | Public key, mouse, focus, and paste utilities; key/mouse encoders can derive options from terminal state. | `VT.Input` publishes symbolic key/text/mouse/focus/paste helpers and render views include the relevant detached terminal input modes, including alternate-screen and alternate-scroll state. C API v1 supplies size-tagged text/key/paste encoding, including bounded associated text for Kitty 8+16 reports, and an opaque terminal-owned mouse handle for button/motion/wheel/focus from current terminal modes, including optional SGR-Pixels coordinates, horizontal wheel, and alternate-scroll output. | **Partial gap.** The currently supported input subset has a C contract; broaden protocol coverage only with sequence and lifetime tests. |
| **Selection and grids** | Public selection APIs, grid references including tracked references, and renderer-visible selection data. | Selection is grapheme-safe and tracks scrollback rows, but it is tightly combined with input/UI state and local clipboard behavior. | Keep terminal-semantic selection as optional host-neutral APIs; move pointer gestures, keybindings, and clipboard ownership to the application. Add durable reference/lifetime semantics. |
| **Kitty graphics** | Optional system PNG decoder callback; library owns decoded RGBA/image/placement state and exposes placement iterators, geometry helpers, generation stamps, and borrowed-data lifetime. | Full Kiwi has a lazy built-in PNG/GIF decoder, bounded cache, placement state, GPU-oriented renderer passes, and GIF/APNG animation cadence. The core package contains no decoder and reports `decoder-unavailable` for an image query unless its host supplies one. | **Partial gap.** Expose decoded pixels/placements to the host through a stable public view and formalize decoder/storage callbacks. Animated image scheduling and texture upload belong in `kiwi-app` or an optional media/renderer layer. |
| **Formatting / utility APIs** | Public terminal formatters (plain/VT/HTML), standalone OSC/SGR parsers, Unicode and I/O helpers. | No public equivalents; internal JSON/snapshot/replay/test utilities exist. | Low priority for first extraction. Add only after core views and lifetimes are stable, and only where a consumer need exists. |
| **Portability** | Header targets C consumers and includes WebAssembly utilities; Ghostty docs describe its core as cross-platform. | Linux x86_64 C shared object dynamically loading system LuaJIT; Kiwi application remains Linux x86_64. | A C ABI alone does not make Kiwi portable. macOS, Windows, WASM, static linking, and cross-compilation need distinct build and runtime acceptance targets. |
| **Release/support contract** | Public headers/examples exist, while the API explicitly remains unstable. | `libkiwi-vt` has versioned Lua and C API v1 documentation, a header, C example, reproducible SDK archive, extracted-C-consumer test, and a pre-1.0 policy. It has no bindings or compatibility guarantee. | **Partial gap.** Keep publishing conservative: source and ABI compatibility require explicit compatibility fixtures and external consumers before any stability promise. |

## The main blockers in the current code

1. **The terminal core is not isolated from application policy.** `State.new` constructs search, selection, shell/command-region, hyperlink, and Kitty graphics objects. Some of those are good core semantics; others are UI and host-policy decisions. They need feature flags or separate ownership.

2. **The renderer-neutral read boundary is not yet the live-renderer boundary.** `kiwi.vt` provides a versioned, single-threaded render update with copied cells and explicit damage acknowledgement; C API v1 now mirrors a bounded cell/grid snapshot. The GPU renderer, font system, and semantic resources still coordinate through internal Lua structures, and C has no damage ranges, selection/input modes, or renderer adoption.

3. **Media is only partially separated across layers.** The core now lazy-loads its default decoder and the core package omits all media/FFI modules, but image cache state still lives with terminal state while playback, GPU textures, and redraw deadlines belong to the renderer/app. That is why the current direct implementation cannot simply be exported as a generic graphics API.

4. **C error and resource semantics are only foundational.** API v1 validates bounded construction/write/resize inputs, has result codes, explicit destruction, and borrowed error diagnostics, but still has no custom allocator, typed effects vtable, callbacks, or foreign-runtime bindings beyond C. Those must stay deliberate rather than leaking Lua values.

5. **Snapshot/replay semantics are not persistence semantics.** The current `Snapshot` encodes a visible diagnostic view. A library either needs an explicit restore format or must state that it deliberately has none.

6. **Threading is intentionally single-threaded.** API v1 requires each handle to be used on one thread with no concurrent operations. This is a documented limitation, not an I/O/render synchronization design; renderer and I/O concurrency should not be added implicitly.

7. **The terminal contract remains deliberately narrower than Ghostty's.** Extraction will make Kiwi reusable; it does not by itself provide comprehensive legacy behavior, broad mouse/key protocol support, reflow-aware image placement, or full xterm compatibility. Those are independent feature projects.

## A practical extraction plan

### Phase 0 — write the contract and prove a minimal consumer

- Select the first consumer: Kiwi itself, a headless recorder, or a second renderer. Without a second consumer, an ABI risks simply fossilizing app internals.
- Completed: name the target `libkiwi-vt`, state a v0.x instability policy,
  publish Lua/C API contracts, package the Lua closure and Linux x86_64 C SDK
  reproducibly, and prove standalone no-renderer/no-FFI Lua and C consumers.
- Completed for C API v1: define its supported platform/runtime, opaque-handle
  lifecycle, versioned options, bounds, errors, and single-thread rule. Still
  required before widening it: quotas beyond construction, callbacks, allocator
  policy, and a broader external-consumer matrix.

### Phase 1 — isolate a pure Lua core

- Move parser/state/screen/scrollback/Unicode code into an importable core with no PTY, GLFW, WGPU, Fontconfig, URL opener, or clipboard bridge imports.
- Replace application calls with an effects sink. Initially keep Kiwi's present policy and test output byte-for-byte where possible.
- Separate semantic extras behind construction options; maintain existing limits and default-deny behavior.
- Add an internal render-state object that snapshots the visible projection and exposes dirty updates without importing renderer modules.

### Phase 2 — validate the new seam

- Make `kiwi-app` consume only the new core boundary.
- Add a headless example that drives bytes, resizes, consumes effects, encodes input, and renders an ASCII/debug projection without GLFW/WGPU.
- Run existing parser, replay, PTY, selection, Kitty graphics, and fuzz tests through both paths. This phase is complete only if no intended terminal behavior changed.

### Phase 3 — widen the narrow embedding API only from consumer evidence

- Completed: publish opaque handles, a C-compatible size/versioned options
  struct, `new/free`, result codes, a header/shared object, and a checked C
  example for Linux x86_64.
- Completed: publish a C begin/end render update with copied grid/cursor/damage
  metadata, per-cell UTF-8/style/color data, explicit damage acknowledgement,
  and a checked lifetime consumer. Never expose raw Lua tables or internals.
- Completed: publish C text/key/paste encoding from current terminal modes,
  with size-tagged key/result structs and checked local-action semantics.
- Completed: publish a terminal-owned C mouse/focus handle with checked button,
  wheel, focus, and terminal-destruction lifecycle semantics.
- Completed: publish C polling of bounded typed effects, preserving byte values
  in a deterministic JSON observation and leaving all host actions to callers.
- Add typed effect callbacks, allocator policy, and bindings incrementally. Keep
  the entire ABI marked experimental until external semantic and compatibility
  tests are stable.

### Phase 4 — optional capability modules

- Add snapshot restore, selected formatters, richer input protocols, media decoder callbacks, and reflow only when each has a written contract and resource model.
- Consider `libkiwi-text` and platform render backends only after `libkiwi-vt` is independently useful. Do not pull GLFW/WGPU into the VT library merely to reproduce the current application.

## Minimal public API shape to design toward

This is a contract sketch, not proposed code or a promise of exact names.

| Operation | Required property |
| --- | --- |
| Create/destroy terminal | Opaque handle; caller-selected dimensions/limits/width policy; documented allocation and errors. |
| Write VT bytes | Incremental, bounded; returns consumed/status; emits no hidden OS effects. |
| Resize / viewport / scrollback | Explicit current semantics, including whether reflow is supported; returns the resulting damage/effects. |
| Configure and consume effects | Typed callbacks with one userdata context, synchronous/asynchronous and reentrancy rules, denied-by-default security-sensitive operations. |
| Begin/end render update | Stable borrowed data only for a defined scope; rows/cells/styles/cursor/selection plus precise dirty clearing. |
| Encode input | Public key/mouse/focus/paste event structs; options sourced from current terminal modes without platform types. |
| Snapshot | Versioned encode/decode, continuation handling, resource limits, and stated compatibility policy. |
| Optional media | Decoder/storage callbacks, generation/lifetime information, image and placement iterators; no network fetch and no GPU object requirement. |

## Explicit non-goals for the first release

- A drop-in replacement for `libghostty`, libvterm, or xterm compatibility.
- A bundled process launcher, window toolkit, font stack, or renderer backend.
- A stable ABI before there are at least two consumers and external integration tests.
- Implicit OS effects from escape sequences, network access from terminal output, or relaxed media/clipboard limits.
- A claim of cross-platform/WASM availability before native CI and runtime tests exist on each target.

## Decision

Extracting `libkiwi-vt` is worthwhile if Kiwi intends to support more than one frontend, renderer, or headless consumer. It will improve Kiwi's own architecture even before third-party use: it makes application policy, renderer ownership, media scheduling, and terminal semantics independently testable.

It is not the fastest route if the only goal is to improve the present Linux GLFW terminal. In that case, a formal library boundary adds significant API/lifetime work without an immediate user-visible feature. If the goal is eventually a Ghostty-like multi-platform application or an embeddable terminal core, create the boundary now—but keep the first library deliberately narrower than Ghostty's and explicitly experimental.

## Sources

### Kiwi, local checkout

- [Architecture](docs/ARCHITECTURE.md), [README scope and limits](README.md), and [conformance contract](docs/CONFORMANCE.md)
- [Application composition](src/kiwi/app/main.lua) and [PTY adapter](src/kiwi/process/pty.lua)
- [Parser](src/kiwi/terminal/parser.lua), [state](src/kiwi/terminal/state.lua), [snapshot](src/kiwi/terminal/snapshot.lua), [damage](src/kiwi/terminal/damage.lua), and [Kitty graphics](src/kiwi/terminal/kitty_graphics.lua)
- [Input encoders](src/kiwi/input/keyboard.lua) and [mouse](src/kiwi/input/mouse.lua)
- [Renderer implementation](src/kiwi/renderer/renderer.lua) and [resource ownership](src/kiwi/renderer/resources.lua)

### Ghostty, official material and source audited at `ad6e72d`

- [Ghostty architecture and public-library status](https://ghostty.org/docs/about)
- [`libghostty-vt` overview/header](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt.h)
- [Terminal lifecycle, effects, options, and scrollback API](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt/terminal.h)
- [Incremental renderer-facing state API](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt/render.h)
- [Snapshot encode/restore API](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt/snapshot.h)
- [Allocator/error-ownership design](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt/allocator.h)
- [Kitty graphics views](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt/kitty_graphics.h) and [host system/decode callbacks](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt/sys.h)
- [Key](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt/key.h), [mouse](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt/mouse.h), and [focus](https://github.com/ghostty-org/ghostty/blob/ad6e72ddc4e9e259c9b70bff6e2b389e0ce91949/include/ghostty/vt/focus.h) encoders
