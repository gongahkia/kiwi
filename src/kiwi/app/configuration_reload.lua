local Terminal = require("kiwi.session.terminal")
local StateTransaction = require("kiwi.terminal.state_transaction")

local Reload = {}
Reload.__index = Reload

local function dispose(value, errors)
  if not value then return end
  local ok, message = pcall(value.destroy, value)
  if not ok then errors[#errors + 1] = tostring(message) end
end

function Reload:abort()
  if self.finished then return {} end
  assert(not self.activated, "cannot abort an activated configuration")
  self.finished = true
  local errors = {}
  for index = #self.entries, 1, -1 do dispose(self.entries[index].renderer, errors) end
  if self.owns_font then dispose(self.font, errors) end
  return errors
end

function Reload.prepare(options)
  local current, candidate = options.current, options.candidate
  if current.ambiguous_width ~= candidate.ambiguous_width or current.scrollback_limit ~= candidate.scrollback_limit then
    return nil, "ambiguous-width and scrollback-limit require a new terminal session"
  end
  local self = setmetatable({ entries = {}, previous_font = options.font, font = options.font }, Reload)
  local ok, message = pcall(function()
    self.owns_font = options.force_font == true or current.font_size ~= candidate.font_size
      or current.font_path ~= candidate.font_path or current.font_family ~= candidate.font_family
      or current.ligatures ~= candidate.ligatures or current.contextual_alternates ~= candidate.contextual_alternates
    -- Do not own the original font if its replacement constructor throws.
    if self.owns_font then self.font = nil; self.font = assert(options.new_font(candidate)) end
    self.columns, self.rows = options.dimensions(self.font)
    assert(self.columns and options.workspace:fits(self.columns, self.rows),
      "font size leaves insufficient space for the current pane layout")
    self.layout = assert(options.workspace:layout(self.columns, self.rows))
    local placements, ids = {}, {}
    for _, placement in ipairs(self.layout) do placements[placement.pane_id] = placement end
    for id in pairs(options.workspace.panes) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local session = options.workspace.panes[id].session
      local transaction = StateTransaction.new(Terminal.state(session.terminal))
      local state = transaction.state
      local placement = placements[id]
      local entry = { session = session, transaction = transaction,
        previous_renderer = session.renderer, columns = state.columns, rows = state.rows,
        metrics_changed = state.cell_width ~= self.font.cell_width or state.cell_height ~= self.font.cell_height }
      self.entries[#self.entries + 1] = entry
      if placement then entry.columns, entry.rows = placement.width, placement.height end
      entry.resized = state.columns ~= entry.columns or state.rows ~= entry.rows
      state:set_cell_metrics(self.font.cell_width, self.font.cell_height)
      if entry.resized then state:resize(entry.columns, entry.rows) end
      state:configure_palette({ foreground = candidate.foreground, background = candidate.background, palette = candidate.palette })
      state:configure_osc52_read(candidate.osc52_read == "allow")
      state:configure_osc52_write(candidate.osc52_write)
      state:mark_all_dirty()
      -- Replacement textures own independent residency, even when the decoded
      -- pixels and image generations are unchanged.
      for image_id, image in pairs(state.kitty_graphics.images) do
        state.kitty_graphics:release_gpu_upload(image_id, image.generation, "configuration")
      end
      entry.renderer = assert(options.new_renderer(self.font, state, options.renderer_options))
      entry.renderer:invalidate("configuration")
      transaction:seal()
    end
  end)
  if not ok then
    local cleanup = self:abort()
    return nil, tostring(message) .. (#cleanup > 0 and ("; cleanup: " .. table.concat(cleanup, "; ")) or "")
  end
  return self
end

-- No native allocation, parser callbacks or child I/O during activation.
-- The caller installs the configuration and pane projections before finish().
function Reload:activate()
  assert(not self.finished and not self.activated, "configuration reload already activated")
  for _, entry in ipairs(self.entries) do
    entry.transaction:commit()
    entry.session.renderer = entry.renderer
    entry.session.metrics.font = self.font
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
    dispose(entry.previous_renderer, errors)
  end
  if self.owns_font then dispose(self.previous_font, errors) end
  return errors
end

return Reload
