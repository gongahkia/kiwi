local Errors = require("runtime.errors")
local Scenarios = require("app.screenshot_scenarios")

local Capture = {}
local capture_mt = {}
capture_mt.__index = capture_mt

Capture.contract = {
  constructor = "new(graphics, filesystem, options) -> screenshot_capture | nil, error",
  draw = "draw() -> true | nil, error",
  paths = "paths() -> screenshot_paths",
  status = "status() -> screenshot_capture_status",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function options(value)
  if type(value) ~= "table" then
    return config_error("screenshot capture options must be a table")
  end
  for field in pairs(value) do
    if field ~= "environment" and field ~= "output_dir" and field ~= "scenario" then
      return config_error("screenshot capture option is unsupported", { field = field })
    end
  end
  if type(value.scenario) ~= "string" then
    return config_error("screenshot capture scenario must be a string")
  end
  local output_dir = value.output_dir or "screenshots/manual"
  if
    type(output_dir) ~= "string"
    or #output_dir == 0
    or #output_dir > 128
    or output_dir:sub(1, 1) == "/"
    or output_dir:find("%.%.", 1, true)
    or not output_dir:match("^[A-Za-z0-9_/%-]+$")
  then
    return config_error("screenshot capture output directory is invalid")
  end
  local environment = value.environment or "unknown"
  if
    type(environment) ~= "string"
    or #environment == 0
    or #environment > 128
    or not environment:match("^[A-Za-z0-9_.%-]+$")
  then
    return config_error("screenshot capture environment is invalid")
  end
  return {
    environment = environment,
    output_dir = output_dir,
    scenario = value.scenario,
  }
end

local function paths(definition, output_dir)
  local stem = table.concat({
    definition.id,
    definition.terminal.columns .. "x" .. definition.terminal.rows,
    "t" .. definition.timestamp_us,
    "seed" .. definition.seed,
  }, "-")
  return {
    metadata = output_dir .. "/" .. stem .. ".json",
    png = output_dir .. "/" .. stem .. ".png",
  }
end

local function metadata(definition, image_paths, environment)
  return table.concat({
    '{"environment":"',
    environment,
    '","grid":"',
    definition.terminal.columns,
    "x",
    definition.terminal.rows,
    '","id":"',
    definition.id,
    '","png":"',
    image_paths.png,
    '","seed":',
    definition.seed,
    ',"timestamp_us":',
    definition.timestamp_us,
    ',"viewport":"',
    definition.viewport.width,
    "x",
    definition.viewport.height,
    '"}',
  })
end

function Capture.new(graphics, filesystem, configuration)
  local settings, settings_error = options(configuration)
  if not settings then
    return nil, settings_error
  end
  if type(graphics) ~= "table" or type(graphics.captureScreenshot) ~= "function" then
    return config_error("screenshot capture graphics is incomplete")
  end
  if
    type(filesystem) ~= "table"
    or type(filesystem.createDirectory) ~= "function"
    or type(filesystem.write) ~= "function"
  then
    return config_error("screenshot capture filesystem is incomplete")
  end
  local scene, scene_error = Scenarios.execute(graphics, settings.scenario)
  if not scene then
    return nil, scene_error
  end
  local created, create_error = filesystem.createDirectory(settings.output_dir)
  if not created then
    return nil,
      Errors.new("renderer_resource_error", "screenshot capture directory failed", {
        cause = tostring(create_error),
      })
  end
  local image_paths = paths(scene.definition, settings.output_dir)
  return setmetatable({
    completed = false,
    environment = settings.environment,
    failure = nil,
    filesystem = filesystem,
    graphics = graphics,
    paths_value = image_paths,
    requested = false,
    scene = scene,
  }, capture_mt)
end

function capture_mt:paths()
  return { metadata = self.paths_value.metadata, png = self.paths_value.png }
end

function capture_mt:status()
  return {
    completed = self.completed,
    failure = self.failure and self.failure.message or nil,
    requested = self.requested,
  }
end

function capture_mt:draw()
  if self.failure then
    return nil, self.failure
  end
  if self.requested then
    return true
  end
  local drawn, draw_error = self.scene:draw()
  if not drawn then
    return nil, draw_error
  end
  self.requested = true
  self.graphics.captureScreenshot(function(image_data)
    local encoded, encode_error = image_data:encode("png", self.paths_value.png)
    if not encoded then
      self.failure = Errors.new("renderer_resource_error", "screenshot image encoding failed", {
        cause = tostring(encode_error),
      })
      return
    end
    local written, write_error = self.filesystem.write(self.paths_value.png, encoded)
    if not written then
      self.failure = Errors.new("renderer_resource_error", "screenshot image write failed", {
        cause = tostring(write_error),
      })
      return
    end
    local recorded, metadata_error = self.filesystem.write(
      self.paths_value.metadata,
      metadata(self.scene.definition, self.paths_value, self.environment)
    )
    if not recorded then
      self.failure = Errors.new("renderer_resource_error", "screenshot metadata write failed", {
        cause = tostring(metadata_error),
      })
      return
    end
    self.completed = true
  end)
  return true
end

return Capture
