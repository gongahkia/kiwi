-- Stage all GtkGLArea pages before changing any live terminal or font.
local Terminal = require("kiwi.session.terminal")
local StateTransaction = require("kiwi.terminal.state_transaction")

local Reload = {}
Reload.__index = Reload

local function dispose(value, errors)
  if not value then return end
  local ok, message = pcall(value.destroy, value)
  if not ok then errors[#errors + 1] = tostring(message) end
end

function Reload.validate(current, candidate)
  if candidate.background_opacity ~= 1 or candidate.custom_shader ~= nil then
    return nil, "background-opacity and custom-shader are unavailable in the experimental GTK GL presenter"
  end
  if current.ambiguous_width ~= candidate.ambiguous_width or current.scrollback_limit ~= candidate.scrollback_limit then
    return nil, "ambiguous-width and scrollback-limit require a new terminal session"
  end
  return true
end

function Reload:abort()
  if self.finished then return {} end
  assert(not self.activated, "cannot abort an activated configuration")
  self.finished = true
  local errors = {}
  for index = #self.entries, 1, -1 do
    local entry = self.entries[index]
    dispose(entry.consumer, errors)
    if entry.owns_font then dispose(entry.font, errors) end
  end
  return errors
end

function Reload.prepare(options)
  local current, candidate = options.current, options.candidate
  local accepted, reason = Reload.validate(current, candidate)
  if not accepted then return nil, reason end
  local self = setmetatable({ entries = {}, configuration = candidate }, Reload)
  local ok, message = pcall(function()
    local font_changed = options.force_font == true or current.font_size ~= candidate.font_size
      or current.font_path ~= candidate.font_path or current.font_family ~= candidate.font_family
      or current.ligatures ~= candidate.ligatures or current.contextual_alternates ~= candidate.contextual_alternates
    for _, session in ipairs(options.sessions) do
      assert(not session.closed, "cannot reload a closed GTK terminal page")
      local original = Terminal.state(session.terminal)
      local entry = { session = session, previous_font = session.font, previous_consumer = session.consumer,
        owns_font = font_changed, font = not font_changed and session.font or nil }
      self.entries[#self.entries + 1] = entry
      if font_changed then entry.font = assert(options.new_font(session.window, candidate)) end
      local columns, rows = options.dimensions(session.window, entry.font)
      -- A hidden/unallocated page keeps its grid until GTK gives it space.
      entry.allocated = columns ~= nil
      entry.columns, entry.rows = columns or original.columns, rows or original.rows
      entry.resized = entry.columns ~= original.columns or entry.rows ~= original.rows
      entry.transaction = StateTransaction.new(original, { columns = entry.columns, rows = entry.rows })
      local state = entry.transaction.state
      state:set_cell_metrics(entry.font.cell_width, entry.font.cell_height)
      state:configure_palette({ foreground = candidate.foreground, background = candidate.background, palette = candidate.palette })
      state:configure_osc52_read(candidate.osc52_read == "allow")
      state:configure_osc52_write(candidate.osc52_write)
      state:mark_all_dirty()
      entry.consumer = assert(options.new_consumer(session.window, entry.font, state, candidate, session.consumer.revision))
      entry.consumer:invalidate("configuration")
      if options.new_host_effects then entry.host_effects = options.new_host_effects(candidate, session.window) end
      entry.transaction:seal()
    end
  end)
  if not ok then
    local errors = self:abort()
    return nil, tostring(message) .. (#errors > 0 and ("; cleanup: " .. table.concat(errors, "; ")) or "")
  end
  return self
end

-- Pure state/resource publication; native child I/O and old resource disposal
-- follow only after every page and the controller configuration are installed.
function Reload:activate()
  assert(not self.finished and not self.activated, "configuration reload already activated")
  for _, entry in ipairs(self.entries) do
    entry.transaction:commit()
    local session = entry.session
    session.configuration, session.font, session.consumer = self.configuration, entry.font, entry.consumer
    session.columns, session.rows = entry.columns, entry.rows
    if entry.host_effects then session.host_effects = entry.host_effects end
    if entry.allocated then session.window.resized = false end
  end
  self.activated = true
end

function Reload:finish()
  assert(self.activated and not self.finished, "configuration reload must be activated exactly once")
  self.finished = true
  local errors = {}
  for _, entry in ipairs(self.entries) do
    entry.transaction:publish_effects()
    if entry.resized then
      local ok, message = pcall(entry.session.pty.resize, entry.session.pty, entry.columns, entry.rows)
      if not ok then errors[#errors + 1] = "PTY resize: " .. tostring(message) end
    end
    dispose(entry.previous_consumer, errors)
    if entry.owns_font then dispose(entry.previous_font, errors) end
  end
  return errors
end

return Reload
