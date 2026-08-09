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
                                        terminal/damage.lua
                                             |
                                             v
text/layout.lua -> HarfBuzz glyph IDs -> bounded alpha atlas
                                             |
                                             v
renderer: background -> shaped glyph -> cursor -> wgpu-native -> Vulkan
```

The parser recognizes syntax only. Callback mode emits semantic print, execute, ESC, CSI, OSC, and ignored-string action tables; it remains the conformance and syntax-test boundary. The production state sink receives print codepoints directly while all non-print semantics remain actions, avoiding one transient action table per glyph without allowing the renderer to depend on parser state. `terminal/state.lua` is the only component that mutates screen cells or decides sequence semantics. The renderer consumes the same renderer-facing interface as M0: `columns`, `rows`, `cells`, `cursor`, `damage`, `position`, and `mark_all_dirty`.

## PTY and process boundary

`process/pty.lua` owns a `forkpty` child lifecycle. It validates argv/environment values, establishes the initial winsize, uses a nonblocking PTY master, reads at most `KIWI_PTY_READ_BUDGET` bytes per live-loop service turn (4 KiB by default), queues partial writes, observes exit with `waitpid(WNOHANG)`, and performs bounded HUP → TERM → KILL shutdown/reap on window close. The budget leaves event polling, terminal responses, and presentation opportunities between a busy child's chunks; no bytes are discarded. `TERM=kiwi` and the project-local `TERMINFO` path are set before the child executes. The default command is an absolute `$SHELL` or `/bin/sh`; `-- command args...` bypasses shell selection.

LuaJIT owns all lifecycle policy and terminal logic. The small C bridge only wraps the ABI-sensitive `TIOCSWINSZ` and nonblocking-fd operations, alongside the pre-existing GLFW/wgpu surface bridge. It contains no parser or terminal state.

## Parser and state

`terminal/parser.lua` is incremental over arbitrary byte chunks. It bounds CSI parameters/intermediates and control-string payloads, accepts OSC BEL/ST termination, discards unsupported DCS/APC/PM/SOS until ST, and uses the streaming decoder in `terminal/utf8.lua`. Invalid or truncated UTF-8 emits U+FFFD deterministically. The parser's outputs are intentionally plain action tables to keep syntax testing independent from semantic state testing.

`terminal/state.lua` holds primary and alternate `Screen` values. A screen is an array of row objects; scrolling moves row references and replaces only entering rows. Full-screen primary upward scrolling offers ejected rows to a fixed-size ring scrollback. Alternate-screen scrolling never enters primary history. State owns cursor/margins/autowrap/origin/insert/application-cursor/bracketed-paste modes, SGR attributes, saved cursor, tab stops, title, and terminal responses.

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

## Input, output, and responses

GLFW codepoints are UTF-8 encoded for the PTY. Physical keys encode CR, DEL, TAB, ESC, Ctrl-letter controls, normal/application arrows, navigation keys, and Alt-letter escape prefixes. `Shift+PageUp/Down` is terminal-local history navigation. Parser output feeds terminal state; pending DSR/DA response bytes are queued back to the PTY in the same nonblocking write path.

## Unicode grid, shaping, and glyph fallback

The parser remains syntax-only and the state remains the sole mutator, but state now stores one Unicode 17 UAX #29 extended grapheme cluster at an anchor cell plus a continuation for every two-column footprint. It retains raw code points and applies a versioned terminal-width policy independently of font metrics. Incoming chunks are not normalized; combining/ZWJ extensions join the prior adjacent cluster when valid. All destructive grid operations normalize anchors and continuations.

`text/layout.lua` observes logical damage and reuses stable rows. Dirty rows are grouped into same-face runs, shaped with HarfBuzz monotone grapheme clusters and explicit LTR direction, then mapped back to terminal columns. Fontconfig resolves primary/fallback faces; FreeType rasterizes resulting glyph IDs. Font face, fallback, glyph, and atlas resources have fixed bounds and failures render `?` or omit a glyph safely. The alpha atlas is one 1024×1024 grayscale page; M2 does not claim color-emoji or bidi rendering.

The legacy `KiwiGlyphInstance` remains a 40-byte cell/background record for M0/M1.5 code. M2 adds a separate 48-byte `KiwiTextGlyphInstance` for glyph geometry/UVs/color/glyph ID/cluster column. GPU bindings keep background cells, shaped glyphs, alpha atlas texture, sampler, and frame data distinct. Decorations/cursor remain semantic passes, not part of a terminal bitmap.

## Replay and diagnostics

Recording happens between PTY/input and parser/state: versioned JSONL records resize events and base64 byte events. Headless replay applies only the deterministic resize/output stream to a new state and emits canonical JSON snapshots. It has no PTY, GPU, or wall-clock dependency.

F4 diagnostics remain rate-limited to one report per second and combine M0 upload/frame data with PTY byte counters, the most recent PTY read byte/count, parser counters, terminal mutations, scrollback, active screen, grid size, child state, and unknown CSI/ESC/OSC counts. M2 adds Unicode version, font/fallback selection, EGC bound count, shaping invalidation/cache metrics, glyph-buffer uploads/drops, and alpha-atlas cache metrics. Unsupported sequence samples are bounded and structured; OSC payloads are never printed. `--inspect` explains the cursor cell's original code points, anchor, width, fallback choice, and resolved face.

## References and intentional boundary

M1 behavior follows the current [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html), [ECMA-48](https://ecma-international.org/publications-and-standards/standards/ecma-48/), [ncurses terminfo](https://invisible-island.net/ncurses/man/terminfo.5.html), and Linux [`TIOCSWINSZ`](https://www.man7.org/linux/man-pages/man2/TIOCSWINSZ.2const.html) documentation. Kiwi deliberately implements only the matrix in [CONFORMANCE.md](CONFORMANCE.md), not complete xterm behavior.
