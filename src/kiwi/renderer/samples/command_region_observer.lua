local PassApi = require("kiwi.renderer.pass_api")

local Sample = {}
local state = { boundaries = 0, frames = 0 }

function Sample.register(api)
  api:register({
    api_version = PassApi.version,
    extension = "sample",
    name = "command-region-observer",
    order = 40,
    reads = { "terminal.command_regions", "frame.timing" },
    writes = {},
    after = { "terminal/cursor" },
    encode = function(context)
      state.frames = state.frames + 1
      state.boundaries = context.resources["terminal.command_regions"].descriptor.boundary_count
    end,
    shutdown = function()
      state.boundaries = 0
      state.frames = 0
    end,
  })
end

function Sample.snapshot()
  return { boundaries = state.boundaries, frames = state.frames }
end

return Sample
