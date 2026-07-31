local CRT = require("effects.crt")
local Host = require("effects.host")
local Kinetic = require("effects.kinetic")
local Errors = require("runtime.errors")
local Renderer = require("renderer.renderer")
local Terminal = require("terminal.terminal")

local Scenarios = {}
local scene_mt = {}
scene_mt.__index = scene_mt

Scenarios.contract = {
  execute = "execute(graphics, id) -> screenshot_scene | nil, error",
  get = "get(id) -> screenshot_scene_definition | nil, error",
  ids = "ids() -> scenario_ids",
}

function scene_mt:draw()
  return self.renderer:draw_terminal(self.terminal)
end

local viewport = { height = 640, width = 960 }
local terminal = { columns = 120, rows = 40 }
local seed = 31337
local timestamp_us = 33334
local output = table.concat({
  "\27[1;36mSTANCZYK // EFFECT FIXTURE\27[0m\r\n",
  "\27[32m[ok]\27[0m deterministic terminal scene\r\n",
  "\27[33m[warn]\27[0m visual layer is semantic-isolated\r\n",
  "\27[35m[info]\27[0m replay frame 000042\r\n",
  "\27[31m[trace]\27[0m output pulse accepted\r\n",
})

local definitions = {
  clean = { effects = "clean", id = "clean" },
  crt = { effects = "crt", id = "crt" },
  kinetic = { effects = "kinetic", id = "kinetic" },
  combined = { effects = "combined", id = "combined" },
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function copy_definition(definition)
  return {
    id = definition.id,
    seed = seed,
    terminal = { columns = terminal.columns, rows = terminal.rows },
    timestamp_us = timestamp_us,
    viewport = { height = viewport.height, width = viewport.width },
  }
end

local function effects_for(definition)
  if definition.effects == "clean" then
    return nil
  end
  if definition.effects == "crt" then
    return { assert(CRT.new({ bloom = 0.2, intensity = 0.35, persistence = 0.2 })) }
  end
  if definition.effects == "kinetic" then
    return { assert(Kinetic.new({ decay = 0.6, intensity = 0.35, max_offset = 0.25 })) }
  end
  return {
    assert(CRT.new({ bloom = 0.2, intensity = 0.35, persistence = 0.2 })),
    assert(Kinetic.new({ decay = 0.6, intensity = 0.35, max_offset = 0.25 })),
  }
end

function Scenarios.ids()
  return { "clean", "crt", "kinetic", "combined" }
end

function Scenarios.get(id)
  if type(id) ~= "string" or definitions[id] == nil then
    return config_error("screenshot scenario is unknown", { id = id })
  end
  return copy_definition(definitions[id])
end

function Scenarios.execute(graphics, id)
  local definition = definitions[id]
  if type(id) ~= "string" or definition == nil then
    return config_error("screenshot scenario is unknown", { id = id })
  end
  local effect_list = effects_for(definition)
  local effect_host
  if effect_list then
    local host_error
    effect_host, host_error = Host.new(effect_list, {
      headless = false,
      random_seed = seed,
      terminal = terminal,
      viewport = viewport,
    })
    if not effect_host then
      return nil, host_error
    end
  end
  local renderer, renderer_error = Renderer.new({
    baseline = 12,
    cell_height = 16,
    cell_width = 8,
    effect_host = effect_host,
    padding = 0,
  })
  if not renderer then
    return nil, renderer_error
  end
  local metrics, metrics_error = renderer:load_font(graphics)
  if not metrics then
    return nil, metrics_error
  end
  local layout, layout_error = renderer:resize(viewport.width, viewport.height)
  if not layout then
    return nil, layout_error
  end
  if layout.columns ~= terminal.columns or layout.rows ~= terminal.rows then
    return config_error("screenshot scenario grid is unstable")
  end
  local terminal_instance, terminal_error = Terminal.new(terminal)
  if not terminal_instance then
    return nil, terminal_error
  end
  local applied, output_error = terminal_instance:feed_output(output)
  if not applied then
    return nil, output_error
  end
  if effect_host then
    local advanced, advance_error = effect_host:update(16667)
    if not advanced then
      return nil, advance_error
    end
    local emitted, emit_error = effect_host:emit("output", { bytes = output }, 16667)
    if not emitted then
      return nil, emit_error
    end
    local settled, settle_error = effect_host:update(timestamp_us - 16667)
    if not settled then
      return nil, settle_error
    end
  end
  return setmetatable({
    definition = copy_definition(definition),
    effect_host = effect_host,
    layout = layout,
    renderer = renderer,
    terminal = terminal_instance,
  }, scene_mt)
end

return Scenarios
