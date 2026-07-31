local Errors = require("runtime.errors")

local EffectCanvas = {}
local effect_canvas_mt = {}
effect_canvas_mt.__index = effect_canvas_mt

EffectCanvas.contract = {
  constructor = "new(graphics) -> canvas_runtime | nil, error",
  draw = "draw(operation) -> true | false, detail?",
  restore = "restore() -> true | false, detail?",
  save = "save() -> true | false, detail?",
  stats = "stats() -> canvas_runtime_stats",
}

local required_methods = {
  "getBlendMode",
  "getCanvas",
  "getColor",
  "getDepthMode",
  "getFont",
  "getLineStyle",
  "getLineWidth",
  "getMeshCullMode",
  "getPointSize",
  "getScissor",
  "getShader",
  "getStencilTest",
  "line",
  "pop",
  "print",
  "push",
  "rectangle",
  "setBlendMode",
  "setCanvas",
  "setColor",
  "setDepthMode",
  "setFont",
  "setLineStyle",
  "setLineWidth",
  "setMeshCullMode",
  "setPointSize",
  "setScissor",
  "setShader",
  "setStencilTest",
}

local unpack_values = table.unpack or unpack

local function resource_error(message, detail)
  return nil, Errors.new("renderer_resource_error", message, detail)
end

local function pack(...)
  return { n = select("#", ...), ... }
end

local function invoke(graphics, name, ...)
  local method = graphics[name]
  local values = pack(pcall(method, ...))
  if not values[1] then
    return nil,
      Errors.new("renderer_resource_error", "renderer graphics " .. name .. " failed", {
        cause = tostring(values[2]),
        method = name,
      })
  end
  local result = { n = values.n - 1 }
  for index = 2, values.n do
    result[index - 1] = values[index]
  end
  return result
end

local function snapshot(graphics)
  local state = {}
  for _, name in ipairs({
    "getBlendMode",
    "getCanvas",
    "getColor",
    "getDepthMode",
    "getFont",
    "getLineStyle",
    "getLineWidth",
    "getMeshCullMode",
    "getPointSize",
    "getScissor",
    "getShader",
    "getStencilTest",
  }) do
    local values, values_error = invoke(graphics, name)
    if not values then
      return nil, values_error
    end
    state[name] = values
  end
  return state
end

local function restore_call(graphics, name, values, no_arguments_when_nil)
  local count = values.n
  if no_arguments_when_nil and values[1] == nil then
    count = 0
  end
  return invoke(graphics, name, unpack_values(values, 1, count))
end

local function restore_snapshot(graphics, state)
  local calls = {
    { "setCanvas", "getCanvas", true },
    { "setShader", "getShader", false },
    { "setBlendMode", "getBlendMode", false },
    { "setColor", "getColor", false },
    { "setScissor", "getScissor", true },
    { "setStencilTest", "getStencilTest", true },
    { "setFont", "getFont", false },
    { "setLineWidth", "getLineWidth", false },
    { "setLineStyle", "getLineStyle", false },
    { "setPointSize", "getPointSize", false },
    { "setDepthMode", "getDepthMode", true },
    { "setMeshCullMode", "getMeshCullMode", false },
  }
  for _, call in ipairs(calls) do
    local restored, restore_error = restore_call(graphics, call[1], state[call[2]], call[3])
    if not restored then
      return nil, restore_error
    end
  end
  return true
end

function EffectCanvas.new(graphics)
  if type(graphics) ~= "table" then
    return resource_error("renderer graphics must be a table")
  end
  for _, name in ipairs(required_methods) do
    if type(graphics[name]) ~= "function" then
      return resource_error("renderer graphics must implement " .. name)
    end
  end
  return setmetatable({ graphics = graphics, stack = {} }, effect_canvas_mt)
end

function effect_canvas_mt:save()
  if #self.stack >= 16 then
    return false, "effect canvas state depth exceeded"
  end
  local pushed, push_error = invoke(self.graphics, "push", "all")
  if not pushed then
    return false, push_error.message
  end
  local state, state_error = snapshot(self.graphics)
  if not state then
    invoke(self.graphics, "pop")
    return false, state_error.message
  end
  self.stack[#self.stack + 1] = state
  return true
end

function effect_canvas_mt:restore()
  local state = self.stack[#self.stack]
  if state == nil then
    return false, "effect canvas state stack is empty"
  end
  self.stack[#self.stack] = nil
  local first_error
  local popped, pop_error = invoke(self.graphics, "pop")
  if not popped then
    first_error = pop_error
  end
  local restored, restore_error = restore_snapshot(self.graphics, state)
  if not restored and first_error == nil then
    first_error = restore_error
  end
  if first_error then
    return false, first_error.message
  end
  return true
end

function effect_canvas_mt:draw(operation)
  if type(operation) ~= "table" then
    return false, "effect canvas operation is invalid"
  end
  local invoked, invoke_error
  if operation.kind == "fill_rect" then
    invoked, invoke_error = invoke(
      self.graphics,
      "rectangle",
      "fill",
      operation.x,
      operation.y,
      operation.width,
      operation.height
    )
  elseif operation.kind == "line" then
    invoked, invoke_error =
      invoke(self.graphics, "line", operation.x1, operation.y1, operation.x2, operation.y2)
  elseif operation.kind == "text" then
    invoked, invoke_error = invoke(self.graphics, "print", operation.text, operation.x, operation.y)
  else
    return false, "effect canvas operation is unsupported"
  end
  if not invoked then
    return false, invoke_error.message
  end
  return true
end

function effect_canvas_mt:stats()
  return { allocations = 0, state_depth = #self.stack }
end

return EffectCanvas
