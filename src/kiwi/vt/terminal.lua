local Parser = require("kiwi.terminal.parser")
local RenderState = require("kiwi.vt.render_state")
local State = require("kiwi.terminal.state")

local Terminal = {}
Terminal.__index = Terminal
Terminal.api_version = 1

local function copy_table(value)
  local copy = {}
  for key, item in pairs(value or {}) do copy[key] = item end
  return copy
end

local function validate_dimension(value, name)
  assert(type(value) == "number" and value % 1 == 0 and value > 0, name .. " must be a positive integer")
end

function Terminal.new(options)
  options = options or {}
  validate_dimension(options.columns, "terminal columns")
  validate_dimension(options.rows, "terminal rows")
  assert(options.effects == nil or type(options.effects) == "table", "terminal effects must be a table")

  local self = setmetatable({
    closed = false,
    effect_errors = {},
    effect_limit = options.effect_limit or 256,
    effects = {},
    effect_handlers = options.effects or {},
    in_update = false,
    in_write = false,
    responses = {},
  }, Terminal)
  assert(type(self.effect_limit) == "number" and self.effect_limit >= 1 and self.effect_limit % 1 == 0, "terminal effect limit must be a positive integer")

  local state_options = copy_table(options.state_options)
  state_options.queue_responses = false
  state_options.effect_sink = function(kind, value)
    self:emit_effect(kind, value)
  end
  self._state = State.new(options.columns, options.rows, state_options)
  self._parser = Parser.new(self._state, options.parser_options)
  self._render_state = RenderState.new(self._state)
  return self
end

function Terminal:assert_open()
  assert(not self.closed, "terminal is closed")
end

function Terminal:emit_effect(kind, value)
  local effect = { kind = kind, value = copy_table(value) }
  if #self.effects == self.effect_limit then table.remove(self.effects, 1) end
  self.effects[#self.effects + 1] = effect
  if kind == "write_pty" then self.responses[#self.responses + 1] = effect.value.bytes end

  local handler = self.effect_handlers[kind] or self.effect_handlers.any
  if handler == nil then return end
  local ok, message = pcall(handler, effect)
  if not ok and #self.effect_errors < self.effect_limit then
    self.effect_errors[#self.effect_errors + 1] = { kind = kind, message = tostring(message) }
  end
end

function Terminal:write(bytes)
  self:assert_open()
  assert(not self.in_update, "cannot write terminal bytes during a render-state update")
  assert(not self.in_write, "terminal effect callbacks must not write to the same terminal")
  assert(type(bytes) == "string", "terminal input must be a byte string")
  self.in_write = true
  local ok, result = xpcall(function()
    self._parser:feed(bytes)
    return #bytes
  end, debug.traceback)
  self.in_write = false
  if not ok then error(result, 0) end
  return result
end

function Terminal:finish()
  self:assert_open()
  assert(not self.in_update, "cannot finish terminal bytes during a render-state update")
  assert(not self.in_write, "terminal effect callbacks must not finish the same terminal")
  self.in_write = true
  local ok, result = xpcall(function()
    self._parser:finish()
  end, debug.traceback)
  self.in_write = false
  if not ok then error(result, 0) end
  return result
end

function Terminal:resize(columns, rows, options)
  self:assert_open()
  assert(not self.in_update, "cannot resize terminal during a render-state update")
  validate_dimension(columns, "terminal columns")
  validate_dimension(rows, "terminal rows")
  self._state:resize(columns, rows, options)
end

function Terminal:set_cell_metrics(width, height)
  self:assert_open()
  assert(not self.in_update, "cannot change terminal cell metrics during a render-state update")
  self._state:set_cell_metrics(width, height)
end

function Terminal:begin_render_update()
  self:assert_open()
  assert(not self.in_write, "cannot begin a render-state update during terminal processing")
  assert(not self.in_update, "render-state update is already active")
  self.in_update = true
  return self._render_state:begin_update()
end

function Terminal:end_render_update(consumed)
  self:assert_open()
  assert(self.in_update, "render-state update is not active")
  self._render_state:end_update(consumed == true)
  self.in_update = false
end

function Terminal:pop_responses()
  local responses = self.responses
  self.responses = {}
  return responses
end

function Terminal:pop_response()
  if #self.responses == 0 then return nil end
  return table.remove(self.responses, 1)
end

function Terminal:pop_effect()
  if #self.effects == 0 then return nil end
  return table.remove(self.effects, 1)
end

function Terminal:pop_effects()
  local effects = self.effects
  self.effects = {}
  return effects
end

function Terminal:diagnostics()
  local errors = {}
  for index, value in ipairs(self.effect_errors) do errors[index] = copy_table(value) end
  return {
    api_version = Terminal.api_version,
    effect_errors = errors,
    effects_pending = #self.effects,
    parser_errors = self._parser.stats.errors,
    responses_pending = #self.responses,
  }
end

function Terminal:close()
  if self.closed then return end
  assert(not self.in_write and not self.in_update, "cannot close terminal during an active operation")
  self.closed = true
  self.effects = {}
  self.responses = {}
end

return Terminal
