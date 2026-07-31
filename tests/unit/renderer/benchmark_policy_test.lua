local assertions = require("support.assertions")
local Policy = require("renderer.benchmark_policy")

local function measurement(frame_time_us, bytes_per_frame, resources)
  return {
    bytes_per_frame = bytes_per_frame,
    frame_time_us = frame_time_us,
    resources = resources or {
      canvases = 0,
      effect_instances = 0,
      fonts = 1,
      shader_compilations = 0,
      shaders = 0,
      temporary_canvases = 0,
    },
  }
end

return {
  {
    name = "renderer benchmark policy permits fixture-local relative variation",
    run = function()
      local comparison = assert(Policy.compare(measurement(115, 115), measurement(100, 100)))
      assertions.truthy(comparison.passed)
      assertions.equal(228, comparison.allocation_limit)
    end,
  },
  {
    name = "renderer benchmark policy rejects budget and retained-resource regressions",
    run = function()
      local comparison = assert(Policy.compare(measurement(116, 229), measurement(100, 100)))
      assertions.falsy(comparison.passed)
      assertions.equal("frame_time", comparison.reasons[1])
      assertions.equal("bytes_per_frame", comparison.reasons[2])
      local resources = {
        canvases = 1,
        effect_instances = 0,
        fonts = 1,
        shader_compilations = 1,
        shaders = 0,
        temporary_canvases = 1,
      }
      comparison = assert(Policy.compare(measurement(100, 100, resources), measurement(100, 100)))
      assertions.equal("retained_canvases", comparison.reasons[1])
      assertions.equal("shader_compilations", comparison.reasons[2])
      assertions.equal("temporary_canvases", comparison.reasons[3])
    end,
  },
}
