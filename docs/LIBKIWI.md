# libkiwi-vt (experimental Lua API)

`libkiwi-vt` is Kiwi's renderer-neutral terminal-emulation boundary. In this
source checkout it is an **experimental, LuaJIT-only API v1 under a pre-1.0
stability policy**, imported as `kiwi.vt`. It is not a C ABI, does not promise ABI stability, and does not
make Kiwi portable beyond the supported application platform.

The boundary deliberately excludes PTYs, GLFW, WGPU, fonts, clipboard bridges,
URL opening, and network fetching. Escape-sequence effects are retained as
bounded plain Lua data for the host to consume; the terminal never performs an
operating-system action by itself.

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

## Version and ownership contract

`VT.api_version` is `1`. New incompatible behavior requires a new API version;
the experimental API may still gain compatible fields and methods. Callers must require
the module once and compare this number before relying on an optional feature.

| Surface | Ownership and rule |
| --- | --- |
| `VT.new({ columns, rows, state_options?, parser_options?, effects?, effect_limit? })` | Creates one single-threaded terminal. Dimensions and limits are validated. `effects` is an optional host callback table. |
| `terminal:write(bytes)` / `finish()` / `resize(columns, rows, options?)` | Mutate terminal state. `write` consumes a Lua byte string incrementally. Calls during a render update are rejected. |
| `terminal:pop_responses()` / `pop_effects()` | Transfer ownership of the current bounded queues to the caller and replace them with empty queues. Response bytes are a subset of typed `write_pty` effects. |
| `terminal:begin_render_update()` / `end_render_update(consumed)` | Bracket a borrowed read view. Do not write, resize, finish, or re-enter the terminal until the matching end call. `consumed=true` acknowledges logical damage; `false` leaves it pending. |
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
`title_changed`, `pwd_changed`, and `shell_marker`. Their exact set is driven
by the terminal contract, and values are copied before delivery. A host decides
whether a title reaches a window, whether a bell is audible, whether a terminal
response is written to a PTY, and whether a security-sensitive effect is
allowed. OSC 52 remains denied by default under the terminal configuration.

The headless projection is deliberately diagnostic: it preserves logical
grapheme anchors but performs no font fallback, bidi resolution, shaping,
ligatures, colour management, image composition, or GPU presentation. A real
renderer should consume the render-update view and provide those policies
outside `libkiwi-vt`.

## Current non-goals

- A C ABI, opaque foreign-language handles, custom allocation hooks, or a
  stable ABI policy.
- Thread-safe access or concurrent reader/writer synchronization.
- Snapshot restore or persistence-format compatibility.
- A renderer, text rasterizer, PTY, window, OS clipboard, process launcher, or
  remote-media downloader.

This deliberately narrow boundary is the basis for a future standalone library
only after it has external-consumer coverage and an explicit ownership/error
contract appropriate for a C API. The comparison and extraction roadmap are in
[KIWI-TO-LIBGHOSTTY.md](../KIWI-TO-LIBGHOSTTY.md).
