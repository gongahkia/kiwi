# Renderer pass API v1

`kiwi.renderer.pass_api` is the small, versioned registration surface for a
trusted local Lua render pass. It is not an extension discovery, installer, or
sandbox. The host passes registration functions explicitly when it constructs
`Renderer`; optional extension configuration and containment are separate
work.

```lua
local PassApi = require("kiwi.renderer.pass_api")

local last_frame

local function register_frame_observer(api)
  api:register({
    api_version = PassApi.version,
    extension = "example",
    name = "frame_observer",
    order = 40,
    reads = { "frame.timing", "frame.viewport" },
    writes = {},
    after = { "terminal/cursor" },
    initialize = function(context)
      assert(context.api_version == 1)
    end,
    encode = function(context)
      local time = context.resources["frame.timing"].descriptor.time
      local columns = context.resources["frame.viewport"].descriptor.columns
      last_frame = { time = time, columns = columns }
    end,
    resize = function(context)
      last_frame = { previous = context.resize.previous, current = context.resize.current }
    end,
    shutdown = function(context)
      last_frame = nil
    end,
  })
end

Renderer.new(context, font, state, {
  extensions = { register_frame_observer },
})
```

`api_version` must be exactly `PassApi.version` (currently `1`). `extension`
and `name` are lowercase identifiers using letters, digits, `_`, and `-`; Kiwi
forms the stable pass identity `extension/<extension>/<name>`. A declaration
needs integer `order`, `reads`, `writes`, `after`, and an `encode` callback.
`initialize`, `resize`, and `shutdown` are optional. All declarations are
validated before the renderer's pass registry becomes active; ordering then
uses the same deterministic dependency graph as the built-ins.

Callbacks receive fresh plain-data context tables: API version, stable pass
metadata, phase, and cloned semantic resource descriptors. `resize` also
receives previous/current viewport descriptors. v1 never supplies a renderer,
command encoder, native WGPU handle, buffer, texture, pipeline, or shader
module. Reads are limited to ABI-v1 read resources and writes to
`surface.color`; a pass cannot retain or destroy Kiwi-owned resources.

This API deliberately supports observation and semantic lifecycle integration,
not arbitrary drawing. Future controlled rendering capabilities require their
own versioned ownership and budget contract.

`context.request_animation(delay_seconds)` is the only scheduling capability.
It coalesces an extension redraw deadline and clamps its cadence to the
renderer policy; it does not create an unbounded timer or background loop.

## Discovery and containment

Kiwi discovers no extensions by default and has no built-in network installer. A live
session can opt into trusted local modules with
`KIWI_RENDER_EXTENSIONS=module.one,module.two`; each module must return a
registration function or `{ register = function }`. `--no-extensions` skips
that list before any module is loaded.

Each configured registration runs in a fresh API collector and is preflighted
with the complete built-in graph plus previously accepted extensions. A
registration that raises, declares an invalid pass, exceeds the 32-pass
extension limit, or creates an invalid graph is discarded as a whole. It
cannot leave partially registered optional passes in the built-in graph.

The extension diagnostic snapshot is available through
`renderer.diagnostics.extensions` and the regular metrics snapshot. It is
plain data with `enabled`, a `disabled` pass-name map, and bounded diagnostic
records `{ extension, pass, phase, message }`; history holds at most 32
records and each message is capped at 4,096 bytes.

If an optional pass callback fails during initialization, encoding, resize, or
shutdown, Kiwi records its extension and pass identity, disables that pass for
the remaining renderer lifetime, and continues the core pass lifecycle where
the renderer can safely do so. A built-in pass failure remains fatal. This is
containment for trusted local code, not a Lua or native-code sandbox.
