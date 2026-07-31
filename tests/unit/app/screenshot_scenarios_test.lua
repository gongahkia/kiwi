local assertions = require("support.assertions")
local Capture = require("app.screenshot_capture")
local Scenarios = require("app.screenshot_scenarios")
local Font = require("fixtures.renderer.font")

local function graphics()
  local value = {}
  function value.newFont()
    return Font.new()
  end
  function value.getBlendMode()
    return "alpha", "alphamultiply"
  end
  function value.getCanvas()
    return nil
  end
  function value.getColor()
    return 1, 1, 1, 1
  end
  function value.getDepthMode()
    return false, false
  end
  function value.getFont()
    return nil
  end
  function value.getLineStyle()
    return "rough"
  end
  function value.getLineWidth()
    return 1
  end
  function value.getMeshCullMode()
    return "none"
  end
  function value.getPointSize()
    return 1
  end
  function value.getScissor()
    return nil
  end
  function value.getShader()
    return nil
  end
  function value.getStencilTest()
    return nil
  end
  function value.line() end
  function value.pop() end
  function value.print() end
  function value.push() end
  function value.rectangle() end
  function value.setBlendMode() end
  function value.setCanvas() end
  function value.setColor() end
  function value.setDepthMode() end
  function value.setFont() end
  function value.setLineStyle() end
  function value.setLineWidth() end
  function value.setMeshCullMode() end
  function value.setPointSize() end
  function value.setScissor() end
  function value.setShader() end
  function value.setStencilTest() end
  function value.captureScreenshot(callback)
    callback({
      encode = function(_, format, path)
        value.format = format
        value.path = path
        return "png-bytes"
      end,
    })
  end
  return value
end

return {
  {
    name = "screenshot scenarios define deterministic effect scenes",
    run = function()
      local ids = Scenarios.ids()
      assertions.equal("clean", ids[1])
      assertions.equal("combined", ids[4])
      for _, id in ipairs(ids) do
        local definition = assert(Scenarios.get(id))
        assertions.equal(31337, definition.seed)
        assertions.equal(33334, definition.timestamp_us)
        assertions.equal(120, definition.terminal.columns)
        assertions.equal(40, definition.terminal.rows)
        assertions.equal(960, definition.viewport.width)
        assertions.equal(640, definition.viewport.height)
        local scene = assert(Scenarios.execute(graphics(), id))
        assertions.equal(id, scene.definition.id)
        assertions.equal(120, scene.layout.columns)
        assertions.equal(40, scene.layout.rows)
        assertions.truthy(scene:draw())
      end
      local scenario, scenario_error = Scenarios.get("unknown")
      assertions.falsy(scenario)
      assertions.equal("config_error", scenario_error.kind)
    end,
  },
  {
    name = "screenshot capture writes deterministic paths and metadata",
    run = function()
      local written = {}
      local filesystem = {}
      function filesystem.createDirectory(path)
        filesystem.directory = path
        return true
      end
      function filesystem.write(path, bytes)
        written[path] = bytes
        return true
      end
      local api = graphics()
      local capture = assert(Capture.new(api, filesystem, {
        environment = "love-11.5",
        output_dir = "screenshots/manual",
        scenario = "combined",
      }))
      assertions.equal("screenshots/manual", filesystem.directory)
      assert(capture:draw())
      local paths = capture:paths()
      assertions.equal("screenshots/manual/combined-120x40-t33334-seed31337.png", paths.png)
      assertions.equal("png", api.format)
      assertions.equal("png-bytes", written[paths.png])
      assertions.truthy(written[paths.metadata]:find('"id":"combined"', 1, true))
      assertions.truthy(capture:status().completed)
    end,
  },
}
