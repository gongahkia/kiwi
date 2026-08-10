# Kiwi M2 architecture

Kiwi retains M0's renderer-first boundary while replacing the normal synthetic producer with a real terminal kernel and native text path. The synthetic model and renderer benchmark remain available through `make demo` and `make bench`; M2 native-text measurements are separate under `make bench-text`.

## Live pipeline

```text
GLFW keyboard / text callbacks
             |
             v
      input/keyboard.lua
             |
             v
PTY master <---------------- terminal responses (DSR/DA)
  nonblocking, 4 KiB/tick read budget        ^
             |                              |
             v                              |
  terminal/parser.lua -- actions/direct print --> terminal/state.lua
        streaming UTF-8                  |
                       Unicode 17 EGC/width +-- screen rows: cluster anchors/continuations
                                      +-- modes/cursor/attributes
                                      +-- bounded scrollback
                                      +-- title/responses/diagnostics
                                             |
                                             v
                         logical damage + text-damage invalidation
                                             |
                                             v
text/layout.lua -> HarfBuzz glyph IDs -> bounded alpha atlas
                                             |
                                             v
renderer: background -> negative-z images -> selection -> search -> shaped glyph + hyperlink underline -> zero/positive-z images -> cursor -> wgpu-native -> Vulkan
```

The parser recognizes syntax only. Callback mode emits semantic print, execute, ESC, CSI, OSC, and ignored-string action tables; it remains the conformance and syntax-test boundary. The production state sink receives print codepoints directly while all non-print semantics remain actions, avoiding one transient action table per glyph without allowing the renderer to depend on parser state. `terminal/state.lua` is the only component that mutates screen cells or decides sequence semantics. The renderer consumes the same renderer-facing interface as M0: `columns`, `rows`, `cells`, `cursor`, `damage`, `position`, and `mark_all_dirty`.

## PTY and process boundary

`process/pty.lua` owns a `forkpty` child lifecycle. It validates argv/environment values, establishes the initial winsize, uses a nonblocking PTY master, reads at most `KIWI_PTY_READ_BUDGET` bytes per live-loop service turn (4 KiB by default), queues partial writes, observes exit with `waitpid(WNOHANG)`, and performs bounded HUP → TERM → KILL shutdown/reap on window close. The budget leaves event polling, terminal responses, and presentation opportunities between a busy child's chunks; no bytes are discarded. It builds a child-only environment vector before the fork and passes it directly to `execvpe`: the live child receives `TERM=kiwi` and the project-local `TERMINFO`, while inherited `COLORTERM` is removed to preserve Kiwi's 16-colour contract. The default command is an absolute `$SHELL` or `/bin/sh`; `-- command args...` bypasses shell selection.

LuaJIT owns all lifecycle policy and terminal logic. The small C bridge only wraps the ABI-sensitive `TIOCSWINSZ` and nonblocking-fd operations, alongside the pre-existing GLFW/wgpu surface bridge. It contains no parser or terminal state.

## Parser and state

Kitty APC-G reaches a bounded terminal transfer model for direct inline PNG and
a separate line-ID placement model. The transfer model validates and decodes
into a CPU cache, while the placement model follows scoped terminal rows through
scrollback, alternate screens, resize, clear, and deletion. The renderer gets
only stable upload and viewport-placement descriptors and native GPU handles
remain renderer-owned. It uploads only visible image IDs, releases textures when
their last viewport placement disappears, and preserves the documented negative
and non-negative z-index composition layers without marking terminal cells
dirty. The exact subset,
limits, failure codes, and ownership boundary are in
[KITTY_GRAPHICS.md](KITTY_GRAPHICS.md) and
[ADR 0033](adr/0033-kitty-graphics-parser-state-foundation.md).

`terminal/parser.lua` is incremental over arbitrary byte chunks. It bounds CSI parameters/intermediates and control-string payloads, accepts OSC BEL/ST termination, emits a separate action for bounded APC-G while discarding unsupported DCS/APC/PM/SOS until ST, and uses the streaming decoder in `terminal/utf8.lua`. Invalid or truncated UTF-8 emits U+FFFD deterministically. The parser's outputs are intentionally plain action tables to keep syntax testing independent from semantic state testing.

`terminal/state.lua` holds primary and alternate `Screen` values. A screen is an array of stable-ID row objects; scrolling moves row references and replaces only entering rows. Full-screen primary upward scrolling offers ejected rows to a fixed-size ring scrollback. Alternate-screen scrolling never enters primary history. State owns cursor/margins/autowrap/origin/insert/application-cursor/bracketed-paste/cursor-style/synchronized-output/mouse/focus modes, SGR attributes, saved cursor, tab stops, title, terminal responses, bounded OSC 8 hyperlink identity, bounded OSC 7/133 shell metadata, bounded derived command-region records, and bounded grapheme-aware selection endpoints. Link cells retain only an internal ID; URI targets stay in bounded terminal state. Shell records retain scope, stable row ID, cursor column, current-directory ID, optional exit status, and a logical event timestamp; directory URI text remains outside snapshots, diagnostics, and renderer resources. Command regions retain opaque identity, role positions, state, and recovery/interruption facts; each row carries at most eight opaque IDs that move with scrollback but never pin retention. Region coverage becomes retained/partial/evicted/truncated rather than leaving a dangling row reference, and no region reaches renderer ABI v1. `selection_view()` returns detached normalized gap endpoints for later rendering and clipboard consumers; its row IDs survive ordinary scrollback movement but clear when retention drops a selected row.

```text
normal scroll inside full primary screen
  row references shift upward
  -> ejected row enters bounded scrollback ring
  -> one new blank row is allocated
  -> damage marks the affected rectangle
```

This supersedes the M0 synthetic scrolling object's per-cell reconstruction without changing the M0 benchmark, which deliberately continues measuring its old synthetic workload.

## Resize and presentation

On framebuffer resize, the live app calculates `floor(drawable pixels / font cell pixels)`, rejects zero-sized drawables, then applies the same dimensions in this order:

```text
terminal state resize -> PTY TIOCSWINSZ -> renderer buffer recreation -> next present
```

Resizing preserves the selected screen's overlapping cells, resets margins to the full new screen, marks all logical cells dirty, and updates the child foreground process group through the kernel's normal winsize mechanism. The renderer is recreated because its storage-buffer capacity equals grid capacity.

The app also polls GLFW content scale. A scale transition recreates the primary face, HarfBuzz/FreeType resources, glyph cache, layout, renderer, and cell dimensions before the next frame. This prevents glyph bitmaps from one physical scale being reused at another; terminal cell width still comes from the configured primary font rather than fallback fonts.

DEC synchronized output leaves terminal mutation and renderer invalidation
intact but defers presentation while `?2026h` is active. `?2026l` presents the
latest bounded model; the terminal does not retain a second output queue or
frame history for this feature. A visible blinking DECSCUSR cursor schedules a
single 0.5-second cursor redraw deadline after a successful present; steady,
hidden, and synchronized-output cursors do not schedule one.

## Input, output, and responses

GLFW codepoints are UTF-8 encoded for the PTY unless `input/search.lua` owns an active `Ctrl+Shift+F` title-bar query. `Enter` submits it, `Escape` clears it, and `Ctrl+Shift+G/R` moves the bounded exact-match set forward/backward; all four actions remain local under Kitty keyboard disambiguation. `Ctrl+Shift+C/V` are likewise reserved explicit local copy/paste actions; the former reconstructs the visible normalized selection and the latter validates the GLFW clipboard before enqueuing exact or bracketed input. `Ctrl+Shift+O` and `Ctrl+primary-click` are explicit local OSC 8 actions, which revalidate the cursor/pointer target then pass allowed URI schemes as one argv element to detached `xdg-open`; they never send terminal input. `Ctrl+Alt+P/C/O` and Shift-forward variants navigate resolved prompt/command/output positions through primary history only; they remain local and report gated/no-target states when search editing, Kitty keyboard mode, alternate screen, or retention prevents a move. Other physical keys encode CR, DEL, TAB, ESC, Ctrl-letter controls, normal/application arrows, navigation keys, and Alt-letter escape prefixes. Pointer callbacks first map GLFW logical coordinates through current content scale and cell dimensions. With SGR normal, button-event, or any-event tracking enabled, `input/mouse.lua` retains only supported button/cell state and emits bounded reports for the child. Otherwise `input/selection_pointer.lua` owns primary-button drag, double-click word, and triple-click row gestures, passing grapheme-safe gaps to terminal state and requesting a selection-only redraw when that range changes. `renderer/selection.lua` and `renderer/search.lua` map their ranges into the current viewport; their alpha passes sit between background and glyph rendering, while `renderer/hyperlink.lua` publishes only a bounded visible-cell count and underline color for the glyph pass. Scroll and focus callbacks continue through the mouse boundary. `Shift+PageUp/Down` is terminal-local history navigation unless the negotiated keyboard mode owns that key. Parser output feeds terminal state; pending DSR/DA and keyboard-query response bytes are queued back to the PTY in the same nonblocking write path.

`input/composition_spike.lua` specifies a detached, bounded preedit/commit/done
lifecycle but is intentionally not installed as a GLFW callback or Wayland
client. A future platform text-input bridge must remain main-thread, route
committed text through this input boundary, and keep preedit outside terminal
state, PTY, replay, clipboard, and diagnostics. GLFW remains the owner of the
window and event loop; a compiled Wayland bridge may use its native display and
surface only after runtime platform selection. See [ADR 0025](adr/0025-wayland-ime-and-window-stack.md).

## Unicode grid, shaping, and glyph fallback

The parser remains syntax-only and the state remains the sole mutator, but state now stores one Unicode 17 UAX #29 extended grapheme cluster at an anchor cell plus a continuation for every two-column footprint. It retains raw code points and applies a versioned terminal-width policy independently of font metrics. Incoming chunks are not normalized; combining/ZWJ extensions join the prior adjacent cluster when valid. All destructive grid operations normalize anchors and continuations.

`terminal/state.lua` maintains separate logical and text-damage streams. Cursor movement and cursor visibility can invalidate logical cell/cursor presentation without reshaping text; content mutation, scroll, reset, resize, history movement, and screen changes invalidate text rows. `text/layout.lua` consumes text damage once per update, builds same-face runs, shapes with HarfBuzz monotone grapheme clusters and explicit LTR direction, then maps glyphs back to terminal columns. Fontconfig resolves primary/fallback faces; FreeType rasterizes resulting glyph IDs. Font face, fallback, glyph, and atlas resources have fixed bounds and failures render `?` or omit a glyph safely. The alpha atlas is one 1024×1024 grayscale page; M2 does not claim color-emoji or bidi rendering.

The legacy `KiwiGlyphInstance` remains a 40-byte cell/background record for M0/M1.5 code. M2 adds a separate 48-byte `KiwiTextGlyphInstance` for glyph geometry/UVs/color/glyph ID/cluster column. GPU bindings keep background cells, shaped glyphs, alpha atlas texture, sampler, and frame data distinct. Selection and the current search result use fixed-size viewport-relative ranges in the frame uniform; neither allocates text or a per-cell buffer. `terminal.search` also exposes all bounded visible match descriptors as plain data for semantic consumers, without query text. `terminal.hyperlinks` exposes only active state, RGBA underline color, and bounded visible-cell count: never targets, IDs, text, or native opener state. Both alpha passes and the hyperlink glyph decoration remain semantic presentation, rather than part of a terminal bitmap.

M3's versioned semantic pass/resource ABI is recorded in [ADR 0016](adr/0016-semantic-render-pass-resource-abi.md). It preserves background, selection, search, glyph, and cursor ordering while adding bounded hyperlink metadata to glyph presentation; it does not expose native wgpu handles to Lua passes.

The initial trusted-local registration surface is [Renderer pass API v1](RENDERER_API.md). It validates declaration version, semantic resources, and lifecycle callbacks before pass activation, gives callbacks only cloned resource descriptors, and reuses the deterministic pass graph for initialization, encoding, resize, and shutdown.

`terminal.command_regions` is a read-only renderer resource derived from the
active viewport. It contains at most 32 `{ row, column, role }` boundaries and
omits IDs, text, CWD data, status, timestamps, and offscreen history. A visible
descriptor change requests a distinct `command_regions` invalidation.
`KIWI_COMMAND_REGIONS=1` adds the built-in alpha-blended separator pass between
search and glyphs; extensions can observe the descriptor but API v1 cannot
draw with it.

Optional extensions are local-module configuration only: `KIWI_RENDER_EXTENSIONS` names trusted modules, while `--no-extensions` bypasses discovery before loading any module. Kiwi preflights each registration in isolation, retains bounded structured diagnostics, and disables a failing optional pass for the active renderer lifetime; it does not treat this as a sandbox for untrusted Lua or native code.

`renderer/samples/damage_observer.lua` is the maintained API-v1 reference
module. It observes only semantic damage/timing descriptors and requests one
coalesced follow-up deadline after damage; it has no overlay because v1 does
not expose command encoders, shaders, or extension-owned GPU allocation.

API v1 enforces a bounded optional-pass count and a maximum extension animation rate before graph activation or redraw scheduling. It exposes no extension-owned GPU allocation or shader capability, so those limits are explicit zero-capability states; the pinned native binding also has no GPU-memory budget query. Future allocation, shader, or memory-budget support must be versioned rather than bypassing this boundary.

Passes may additionally declare opt-in advisory CPU, GPU-tick, allocation, and
cadence budgets. The renderer retains only each declaration's bounded rolling
window and structured warnings. GPU data remains delayed/optional, allocation
accounting is unavailable for API v1 extensions, and no warning changes the
pass lifecycle or terminal output.

## Replay and diagnostics

Recording happens between PTY/input and parser/state: versioned JSONL records resize events and base64 byte events. Headless replay applies only the deterministic resize/output stream to a new state and emits canonical JSON snapshots. OSC 7/133 data, command-region lifecycle, and bounded row references are derived again from that output with monotonic logical timestamps; snapshots retain only opaque shell/region IDs and positions, not directory URI data. Snapshot `v: 1` is observation-only and has no decoder; replay JSONL v1 remains the version-checked restore boundary. Replay has no PTY, GPU, or wall-clock dependency.

F4 diagnostics remain rate-limited to one report per second and combine M0 upload/frame data with PTY byte counters, the most recent PTY read byte/count, parser counters, terminal mutations, scrollback, active screen, grid size, child state, and unknown CSI/ESC/OSC counts. M2 adds Unicode version, font/fallback selection, EGC bound count, shaping invalidation/cache metrics, glyph-buffer uploads/drops, and alpha-atlas cache metrics. Unsupported sequence samples are bounded and structured; OSC payloads are never printed. `--inspect` explains the cursor cell's original code points, anchor, width, fallback choice, and resolved face.

## References and intentional boundary

M1 behavior follows the current [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html), [ECMA-48](https://ecma-international.org/publications-and-standards/standards/ecma-48/), [ncurses terminfo](https://invisible-island.net/ncurses/man/terminfo.5.html), and Linux [`TIOCSWINSZ`](https://www.man7.org/linux/man-pages/man2/TIOCSWINSZ.2const.html) documentation. Kiwi deliberately implements only the matrix in [CONFORMANCE.md](CONFORMANCE.md), not complete xterm behavior.
