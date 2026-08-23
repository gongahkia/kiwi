# libkiwi-vt (experimental Lua and C APIs)

`libkiwi-vt` is Kiwi's renderer-neutral terminal-emulation boundary. It has
an **experimental pre-1.0 Lua API v2**, imported as `kiwi.vt`, and an
**experimental C API v2** in `include/kiwi/vt.h`. Neither API has an ABI or
source-compatibility promise. The C API is a small Linux x86_64 and macOS
arm64 adapter over the same LuaJIT core; it does not make Kiwi portable beyond
the supported application platform. Mutable terminal state is an
application-private adapter, not a consumer API.

The boundary deliberately excludes PTYs, GLFW, WGPU, fonts, clipboard bridges,
URL opening, and network fetching. Escape-sequence effects are retained as
bounded plain Lua data for the host to consume; the terminal never performs an
operating-system action by itself. The base API does not load GIF or PNG
libraries during construction. Kitty image transfers load Kiwi's optional
decoder only when a complete image arrives and report `decoder-unavailable` if
that decoder cannot be loaded.

## Minimal consumer

```lua
local VT = require("kiwi.vt")
local Headless = require("kiwi.vt.headless")

local terminal = VT.new({ columns = 80, rows = 24 })
terminal:write("hello\\r\\n")
terminal:finish()

local projection = Headless.render_terminal(terminal, {
  consume_damage = true,
  trim_trailing = true,
})
print(projection.text)
```

From a source checkout, the same renderer-free consumer is available as:

```sh
printf 'hello\r\n' | ./script/kiwi-vt --columns 80 --rows 24
```

or `make vt-demo`. It starts no native window, process, GPU context, or font
system.

`make libkiwi-vt` creates a reproducible, renderer-free SDK archive in
`dist/`. It contains the core Lua modules, `include/kiwi/vt.h`,
`lib/libkiwi_vt.so` on Linux or `lib/libkiwi_vt.dylib` on macOS, the standalone
Lua launcher, and a C consumer example. The shared library dynamically loads
the system LuaJIT runtime and finds the archive's adjacent `lua/` directory by
default. The verified targets are Linux x86_64 and macOS arm64; the macOS
x86_64 archive path is unverified. Set `KIWI_LIBKIWI_LUA_ROOT` only when
deliberately relocating the Lua files, and set
`KIWI_VT_LUAJIT_LIB=/absolute/path/to/libluajit-5.1.2.dylib` when macOS cannot
discover a nonstandard LuaJIT runtime.
It deliberately excludes renderer, platform, process, FFI, and image-decoder
modules. `make libkiwi-vt-c` builds the unpackaged C SDK into
`.build/libkiwi-vt`; `make libkiwi-vt-check` builds the archive twice, runs
both standalone consumers, and verifies that an image query reports bounded
`decoder-unavailable` rather than making the base terminal depend on media
libraries. A Lua host that needs Kitty image support may provide
`state_options.kitty_graphics.decoder`, a table with a `decode` function
matching Kiwi's image-decoder contract. Packaging an archive from a dirty
checkout needs `KIWI_LIBKIWI_ALLOW_DIRTY=1`; that is suitable for local testing
only.

## Version and ownership contract

`VT.api_version` is `2`. New incompatible behavior requires a new API version;
the experimental API may still gain compatible fields and methods. Callers must require
the module once and compare this number before relying on an optional feature.

| Surface | Ownership and rule |
| --- | --- |
| `VT.new({ columns, rows, state_options?, parser_options?, effects?, effect_limit? })` | Creates one single-threaded terminal. Dimensions and limits are validated. `effects` is an optional host callback table. `state_options.keyboard_supported_flags` defaults to portable Kitty flags 1/2/8/16; a host may opt into flag 4 only when it has a truthful runtime provider for the variant meanings described below. `state_options.osc52_read` defaults to false; a host enabling it receives a bounded payload-free clipboard-read request and must decide whether to reply. |
| `terminal:write(bytes)` / `finish()` / `resize(columns, rows, options?)` / `set_cell_metrics(width, height)` | Mutate terminal state or provide host-measured physical cell metrics. `write` consumes a Lua byte string incrementally. Calls during a render update are rejected. Metrics enable only read-only xterm geometry replies; they do not let terminal applications resize a host. |
| `terminal:pop_response()` / `pop_responses()` / `pop_effect()` / `pop_effects()` | Transfer one response, all current responses, one effect, or all effects to the caller and remove them from the bounded queue. Response bytes are a subset of typed `write_pty` effects. |
| `terminal:begin_render_update()` / `end_render_update(consumed)` | Bracket a borrowed read view. Do not write, resize, finish, or re-enter the terminal until the matching end call. `consumed=true` acknowledges logical damage; `false` leaves it pending. Render-view cell colours include the active `DECSCNM` reverse-screen presentation transform; terminal storage remains semantic. |
| `view.input_modes` | Detached mode data needed to encode host input: application cursor/keypad, DECBKM backspace mode, bracketed paste, focus reporting, Kitty keyboard flags, current screen identity, alternate-scroll, mouse tracking/protocol, and the application’s XTSHIFTESCAPE request as `mouse_shift_escape` (`nil` for no request, `false` to permit a local Shift selection override, `true` to request Shift capture). The library exposes the request but does not choose host selection policy. |
| `VT.Input` | Host-neutral input helpers. `text(codepoint, modes)`, `key({ key?, unicode_key?, action, modifiers?, layout_key?, shifted_key?, base_key? }, modes)`, `new_mouse()`, and `paste(bytes, modes)` return terminal bytes or a host-decided local-action token. `key` is an optional symbolic/physical token; `unicode_key` is the distinct printable non-control scalar, required when a host's physical token overlaps its Unicode value. The optional variant scalars are the unshifted active-layout key, Shift active-layout key, and unshifted US PC-101 physical-position key for Kitty flag 4. A flag-4 host provides every applicable meaning it can derive and uses zero for an inapplicable or unavailable scalar; it must not invent one variant from another. Mouse events normally use 1-origin `column`/`row`; SGR-Pixels uses `pixel_x`/`pixel_y` instead. Symbolic special keys include `up`, `down`, `left`, `right`, `home`, `end`, `insert`, `delete`, `page_up`, `page_down`, `escape`, `enter`, `tab`, `backspace`, `f1` through `f12`, and `kp_0` through `kp_9` plus `kp_decimal`, `kp_divide`, `kp_multiply`, `kp_subtract`, `kp_add`, `kp_enter`, and `kp_equal`. |
| `kiwi.vt.headless.render(view, options?)` | Reads only the public render view and returns owned plain tables. Wide-cell continuation slots are omitted; their anchor cell contributes its full display text. |
| `kiwi.vt.headless.render_terminal(terminal, options?)` | Convenience transaction that always closes its update, including when rendering errors. `consume_damage` defaults to false. |
| `terminal:close()` | Releases bounded queues and prohibits further operations. It is idempotent outside active operations. |

Terminal objects, render views, and callbacks are single-threaded and
non-reentrant. A host effect callback must not call `write`, `finish`, or begin
a render update on the same terminal. The facade records a bounded effect error
instead of corrupting state when a callback fails; inspect it through
`terminal:diagnostics()`.

## Effects and host policy

The terminal exposes observable terminal effects such as `write_pty`, `bell`,
`title_changed`, `pwd_changed`, `shell_marker`, `palette_changed`,
`cursor_color_changed`, and `pointer_shape_changed`. The palette and cursor
effects expose the bounded state mutation from OSC 4/10/11/12 and the supported
OSC 21 numeric-palette/foreground/background/cursor subset; they never alter a
host palette or cursor by themselves. `pointer_shape_changed` carries a
bounded CSS cursor name from OSC 22; the host chooses its platform approximation
and performs the cursor update. Their exact set is driven by the terminal
contract, and values are copied before delivery. A host decides whether a title
reaches a window, whether a bell is audible, whether a terminal response is
written to a PTY, and whether a security-sensitive effect is allowed. OSC 52 remains denied by default under
the terminal configuration. A host that opts into `state_options.osc52_read` receives
`clipboard_read_requested` with only a selector and byte limit, validates its
clipboard independently, and writes any base64 OSC reply to its own PTY; the
terminal core never receives clipboard contents.

The headless projection is deliberately diagnostic: it preserves logical
grapheme anchors but performs no font fallback, bidi resolution, shaping,
ligatures, colour management, image composition, or GPU presentation. A real
renderer should consume the render-update view and provide those policies
outside `libkiwi-vt`.

`VT.Input` uses its own symbolic event contract and modifier bit constants;
it accepts no GLFW object or native handle. A key event may include a distinct
`unicode_key` scalar, which removes the collision between valid Unicode values
and the symbolic special-key range, and may include
`associated_text = { codepoint, ... }` for the negotiated Kitty 8+16 mode;
the sequence is bounded to non-control Unicode scalars. A host normally takes `input_modes`
from its most recent render update, passes it to these helpers, and writes only
their returned `bytes` to its own transport. Returned `local_action` tokens
describe optional UI policy such as copy, search, or scrollback navigation;
the library never performs those host actions itself.

## C API v2

The C ABI is deliberately smaller than the Lua facade. Every
`kiwi_vt_terminal` is an opaque, independently allocated handle with its own
LuaJIT state. Construct, use, and free a handle on one thread; no function may
run concurrently with another operation on that handle. `free(NULL)` is safe;
freeing a terminal also ends and invalidates an active C render update. All
pointer results are borrowed: `kiwi_vt_last_error()` is thread-local, and
`kiwi_vt_terminal_last_error()` remains valid only until the next operation on
that terminal or its destruction.

```c
#include <kiwi/vt.h>

kiwi_vt_options options = {
  .struct_size = sizeof(options),
  .api_version = KIWI_VT_API_VERSION,
  .columns = 80,
  .rows = 24,
  .scrollback_limit = 2000,
  .osc52_read = 0, /* default deny */
};
kiwi_vt_terminal *terminal = NULL;
if (kiwi_vt_terminal_new(&options, &terminal) != KIWI_VT_OK) {
  /* kiwi_vt_last_error() */
}
kiwi_vt_terminal_write(terminal, "hello\\r\\n", 7, NULL);
kiwi_vt_terminal_finish(terminal);
kiwi_vt_terminal_free(terminal);
```

`struct_size` must be at least `sizeof(kiwi_vt_options)` and `api_version`
must equal `KIWI_VT_API_VERSION`. Versions and dimension/scrollback bounds are
validated before creating a handle. Zero `scrollback_limit` selects the C API
default of 2,000 rows. Zero `keyboard_supported_flags` preserves the portable
1/2/8/16 Kitty mask; a host may use `31` only when it has a runtime provider
for the three flag-4 meanings and leaves an individual inapplicable variant at
zero. `osc52_read` is zero by default; set it to one only when the external
host has an explicit OSC 52 query policy and can consume the resulting
`KIWI_VT_EFFECT_CLIPBOARD_READ_REQUESTED` without exposing clipboard text to
the terminal core. `kiwi_vt_version()` reports Kiwi's package version;
`kiwi_vt_api_version()` reports the C API version.

| Function | Contract |
| --- | --- |
| `kiwi_vt_terminal_new` / `kiwi_vt_terminal_free` | Allocate and destroy one opaque terminal. Construction failures use `kiwi_vt_last_error()`. |
| `kiwi_vt_terminal_write` / `finish` / `resize` / `set_cell_metrics` | Incrementally supply arbitrary bytes, flush a final partial sequence, change the grid, or provide positive host-measured cell width/height (maximum 65,535 pixels). Metrics enable the read-only xterm `CSI 14 t`, `16 t`, and `18 t` queries; terminal applications cannot resize or reposition the host through this API. `consumed`, when supplied to `write`, is zero on failure and the full supplied byte count on success. |
| `kiwi_vt_terminal_text` | Return a deterministic, trimmed logical text projection. It is diagnostic text, not a shaped or pixel-rendered frame. |
| `kiwi_vt_terminal_take_response` | Return and consume one queued terminal response, such as a DSR reply. It is the dedicated C PTY-response channel. |
| `kiwi_vt_terminal_take_effect` | Return one typed queued effect and consume it only after its payload buffer is sufficient. Its byte-safe payload observation never asks the terminal to perform a host action. |
| `kiwi_vt_terminal_input_modes` | Copy the current host-input modes: application cursor/keypad, DECBKM backspace mode, bracketed paste, focus, Kitty keyboard flags, mouse protocol/tracking enums, alternate-screen/alternate-scroll state, and `mouse_shift_escape` (`0` no application request, `1` local Shift override permitted, `2` Shift capture requested). The C API does not implement selection policy. |
| `kiwi_vt_terminal_encode_text` / `encode_key` / `encode_paste` | Encode host text, a key event, or paste bytes from the terminal's current negotiated modes. Key results contain a host-local action and text-suppression flag as well as optional terminal bytes. |
| `kiwi_vt_mouse_new` / `free` and `kiwi_vt_mouse_encode_*` | Create a terminal-owned stateful mouse/focus encoder. Button, motion, wheel, and focus events use the terminal's current mouse/focus modes and return optional terminal bytes. Wheel events accept vertical and optional horizontal offsets. |
| `kiwi_vt_terminal_begin_render_update` / `kiwi_vt_render_update_end` | Open and close an opaque, frozen logical view. No other operation may run on its terminal while it is active. Pass nonzero `consume_damage` to acknowledge logical damage; ending always invalidates the update handle. |
| `kiwi_vt_render_update_info` | Copy grid dimensions, primary/alternate screen identity, cursor state, generation, and aggregate damage into a size-tagged `kiwi_vt_render_state`. |
| `kiwi_vt_render_update_cell` | Copy one logical cell's coordinates, anchor/continuation/span, effective presentation `0xAARRGGBB` foreground/background (including active `DECSCNM` reverse-screen video), and style flags into `kiwi_vt_render_cell`; obtain UTF-8 display text with the same two-call buffer rule. |
| `kiwi_vt_last_error` / `kiwi_vt_terminal_last_error` | Return the latest bounded diagnostic for a failed construction or operation. Status codes remain the programmatic error contract. |

`text` and `take_response` use the same two-call buffer convention: `required`
includes the trailing NUL; call first with a null or too-small buffer, expect
`KIWI_VT_BUFFER_TOO_SMALL`, allocate `required` bytes, then call again. A
too-small response buffer does **not** consume that response. An empty response
queue returns `KIWI_VT_NOT_FOUND` and sets `required` to zero. Byte inputs and
responses may contain NUL bytes; use the reported byte length rather than C
string routines for protocol data.

`kiwi_vt_terminal_take_effect` uses the same preservation rule: fill a
size-tagged `kiwi_vt_effect`, query/allocate `payload_required`, then consume
the effect with a sufficiently sized payload buffer. `kind` uses the
`KIWI_VT_EFFECT_*` constants. The payload is deterministic JSON with
`kind` and `value` fields; every Lua string is represented as
`{"bytes":"base64"}` so titles, PTY reply bytes, clipboard text, and other
values remain byte-safe. `value` tables keep their named fields and
numeric/boolean values remain JSON primitives. The embedded payload kind makes
the `KIWI_VT_EFFECT_OTHER` fallback observable across future experimental
extensions. `palette_changed`, `cursor_color_changed`, and
`pointer_shape_changed` have typed `KIWI_VT_EFFECT_*` constants.
`pointer_shape_changed` carries the requested CSS name in `value.shape`; a host
treats it as presentation advice, not authority to perform another action.
`write_pty` effects are also visible through
`take_response`; a host normally chooses one of those interfaces for PTY
replies rather than consuming both queues.

`kiwi_vt_render_state` and `kiwi_vt_render_cell` are copied output structs: set
their `struct_size` fields before use. `active_screen` is
`KIWI_VT_SCREEN_PRIMARY` or `KIWI_VT_SCREEN_ALTERNATE`; style flags use the
`KIWI_VT_CELL_FLAG_*` constants. Cell text is logical UTF-8 for the cell's
grapheme; a continuation cell has `continuation=1`, width zero, and an
`anchor_column` pointing at its display-text cell. This view provides no font
fallback, shaping, bidi resolution, pixel geometry, GPU objects, damage ranges,
selection, or input-mode data.

`kiwi_vt_terminal_encode_text`, `encode_key`, and `encode_paste` use the
terminal's current negotiated modes without accepting a GLFW object or native
handle. `kiwi_vt_key_event` and `kiwi_vt_input_result` are size-tagged. Its
optional `unicode_key`, `layout_key`, `shifted_key`, and `base_key` fields are
non-control Unicode scalars (or zero when unavailable). `unicode_key` is the
printable scalar for the current event; the remaining flag-4 fields are respectively the
unshifted active-layout result, Shift active-layout result, and unshifted US
PC-101 physical-position result. A consumer opting into flag 4 supplies every
meaning it can derive with a runtime provider; an individual inapplicable
scalar remains zero. Kiwi does not derive one from another.
`KIWI_VT_KEY_*`, `KIWI_VT_KEY_ACTION_*`, and `KIWI_VT_MODIFIER_*` are the
complete symbolic C key vocabulary for this API version. Legacy ASCII
printable keys may use `key`; every non-ASCII printable value belongs in
`unicode_key`. Set `key` to zero only when the host has no symbolic or
physical token. `KIWI_VT_KEY_KP_*` covers the numeric keypad. A successful
key operation can have no terminal bytes when it reports a
`KIWI_VT_LOCAL_ACTION_*` token such as copy or search; the host must decide
whether to perform that action. A key with neither bytes nor a
local action returns `KIWI_VT_NOT_FOUND`.

When legacy application keypad mode is active (`ESC =`), the keypad event
helpers encode the documented VT220 SS3 forms; normal keypad mode (`ESC >`)
encodes the corresponding printable byte. A negotiated Kitty all-keys flag
(`8`) takes precedence: this experimental API does not yet assign Kitty
keycodes to keypad events, so it returns `KIWI_VT_NOT_FOUND` rather than
mixing a legacy application-keypad sequence into the Kitty protocol.

DECBKM (`CSI ? 67 h/l`) is exposed as `backarrow` in the input-mode copies.
Outside Kitty all-keys reporting, `backspace` encodes BS when it is enabled and
DEL otherwise. Kitty key reports retain their protocol-defined Backspace
codepoint rather than being rewritten by this legacy mode.

`kiwi_vt_mouse_new` returns an opaque stateful mouse handle associated with one
terminal. Set the `struct_size` fields of `kiwi_vt_mouse_button_event`,
`kiwi_vt_mouse_motion_event`, or `kiwi_vt_mouse_wheel_event` before use.
Buttons are `0` (primary), `1` (middle), or `2` (secondary), and actions use
`KIWI_VT_MOUSE_ACTION_*`; positions are one-based terminal cells except when
the terminal selected SGR-Pixels (`?1016`), which requires a nonzero one-based
physical `pixel_x`/`pixel_y` pair. Free the mouse before its terminal when
practical; freeing the terminal also frees and
invalidates every associated mouse handle. As with other encoders,
`KIWI_VT_NOT_FOUND` means the current terminal mode did not request a report.
`horizontal_delta`, when present on a wheel event, maps positive to xterm
button 6 (right) and negative to button 7 (left); it is independently bounded
to 16 reports per call.

The installed example is `examples/c_consumer.c`. A source-checkout smoke
consumer can be built with `make libkiwi-vt-c` followed by the same compiler
and runtime-library search path used in `script/libkiwi-vt-check`.

## Current non-goals

- A stable ABI policy, custom allocation hooks, or bindings beyond the checked
  C example.
- Thread-safe access or concurrent reader/writer synchronization.
- C callbacks/effect subscriptions, damage-range iteration,
  selection/search/media views, or snapshot restore.
- Snapshot restore or persistence-format compatibility.
- A renderer, text rasterizer, PTY, window, OS clipboard, process launcher, or
  remote-media downloader.

This deliberately narrow boundary is the shipped experimental SDK surface.
Promotion to a standalone library with a stable compatibility commitment still
requires external-consumer coverage and an explicit ownership/error contract
appropriate for a C API. The comparison and extraction roadmap are in
[KIWI-TO-GHOSTTY.md](../KIWI-TO-GHOSTTY.md).
