local Coordinator = require("runtime.coordinator")
local Errors = require("runtime.errors")
local Replay = require("backend.replay")
local Renderer = require("renderer.renderer")
local SampleRecording = require("app.sample_recording")
local Terminal = require("terminal.terminal")

local Standalone = {}
local standalone_mt = {}
standalone_mt.__index = standalone_mt

Standalone.contract = {
  from_love = "from_love(graphics, options?) -> standalone | nil, error",
  new = "new(graphics, options) -> standalone | nil, error",
  draw = "draw() -> true | nil, error",
  resize = "resize(width, height, pixel_width?, pixel_height?) -> layout | nil, error",
  resize_window = "resize_window() -> layout | nil, error",
  update = "update(seconds) -> applied_events | nil, error",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function options_for(options, requires_dimensions)
  if type(options) ~= "table" then
    return config_error("standalone options must be a table")
  end
  local allowed = {
    padding = true,
    recording_source = true,
    window_height = true,
    window_width = true,
  }
  for name in pairs(options) do
    if not allowed[name] then
      return config_error("unknown standalone option", { option = name })
    end
  end
  if requires_dimensions and (options.window_width == nil or options.window_height == nil) then
    return config_error("standalone window dimensions must be provided")
  end
  return options
end

local function recording_source(options)
  if options.recording_source ~= nil then
    return options.recording_source
  end
  return SampleRecording.new_source()
end

local function build(renderer, layout, options)
  local terminal, terminal_error = Terminal.new({ columns = layout.columns, rows = layout.rows })
  if not terminal then
    return nil, terminal_error
  end
  local source, source_error = recording_source(options)
  if not source then
    return nil, source_error
  end
  local replay, replay_error = Replay.new(source)
  if not replay then
    return nil, replay_error
  end
  local coordinator, coordinator_error = Coordinator.new(terminal, replay)
  if not coordinator then
    return nil, coordinator_error
  end
  return setmetatable({ coordinator = coordinator, renderer = renderer }, standalone_mt)
end

local function renderer_options(options)
  return { padding = options.padding }
end

function Standalone.new(graphics, options)
  local settings, settings_error = options_for(options, true)
  if not settings then
    return nil, settings_error
  end
  local renderer, renderer_error = Renderer.new(renderer_options(settings))
  if not renderer then
    return nil, renderer_error
  end
  local loaded, load_error = renderer:load_font(graphics)
  if not loaded then
    return nil, load_error
  end
  local layout, resize_error = renderer:resize(settings.window_width, settings.window_height)
  if not layout then
    return nil, resize_error
  end
  return build(renderer, layout, settings)
end

function Standalone.from_love(graphics, options)
  if options == nil then
    options = {}
  end
  local settings, settings_error = options_for(options, false)
  if not settings then
    return nil, settings_error
  end
  local renderer, renderer_error = Renderer.new(renderer_options(settings))
  if not renderer then
    return nil, renderer_error
  end
  local loaded, load_error = renderer:load_font(graphics)
  if not loaded then
    return nil, load_error
  end
  local layout, resize_error = renderer:resize_window()
  if not layout then
    return nil, resize_error
  end
  return build(renderer, layout, settings)
end

function standalone_mt:draw()
  local terminal = self.coordinator:terminal_instance()
  local drawn, draw_error = self.renderer:draw_terminal(terminal)
  if not drawn then
    return nil, draw_error
  end
  return true
end

function standalone_mt:resize(window_width, window_height, pixel_width, pixel_height)
  local layout, resize_event_or_error =
    self.renderer:resize(window_width, window_height, pixel_width, pixel_height)
  if not layout then
    return nil, resize_event_or_error
  end
  if resize_event_or_error then
    local resized, resize_error = self.coordinator
      :terminal_instance()
      :resize(resize_event_or_error.columns, resize_event_or_error.rows)
    if not resized then
      return nil, resize_error
    end
  end
  return layout
end

function standalone_mt:resize_window()
  local layout, resize_event_or_error = self.renderer:resize_window()
  if not layout then
    return nil, resize_event_or_error
  end
  if resize_event_or_error then
    local resized, resize_error = self.coordinator
      :terminal_instance()
      :resize(resize_event_or_error.columns, resize_event_or_error.rows)
    if not resized then
      return nil, resize_error
    end
  end
  return layout
end

function standalone_mt:update(seconds)
  if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 or seconds == math.huge then
    return config_error("standalone update seconds must be a non-negative finite number", {
      provided = seconds,
    })
  end
  local microseconds = math.floor(seconds * 1000000)
  if microseconds > 0xFFFFFFFF then
    return config_error("standalone update seconds exceed replay bounds", { provided = seconds })
  end
  return self.coordinator:update(microseconds)
end

function standalone_mt:stop()
  return self.coordinator:stop("standalone closed")
end

function standalone_mt:terminal_instance()
  return self.coordinator:terminal_instance()
end

return Standalone
