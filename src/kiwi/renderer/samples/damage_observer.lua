local PassApi = require("kiwi.renderer.pass_api")

local Sample = {}
local state = { frames = 0, scheduled = 0 }

function Sample.register(api)
  api:register({
    api_version = PassApi.version,
    extension = "sample",
    name = "damage-observer",
    order = 40,
    reads = { "terminal.damage", "frame.timing" },
    writes = {},
    after = { "terminal/cursor" },
    encode = function(context)
      state.frames = state.frames + 1
      if context.resources["terminal.damage"].descriptor.cells > 0 then
        local deadline = context.request_animation(0.25)
        if deadline then state.scheduled = state.scheduled + 1 end
      end
    end,
    shutdown = function()
      state.frames = 0
      state.scheduled = 0
    end,
  })
end

function Sample.snapshot()
  return { frames = state.frames, scheduled = state.scheduled }
end

return Sample
