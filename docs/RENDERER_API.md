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
