local Assert = require("tests.assert")
local Config = require("kiwi.config")
local Reload = require("kiwi.app.configuration_reload")
local Terminal = require("kiwi.session.terminal")
local Workspace = require("kiwi.session.workspace")

local function resource()
  return { cell_width = 8, cell_height = 16, invalidate = function() end, destroy = function() end }
end

local function renderer(_, state)
  -- Exercise the same projected-cell reads as the renderer without native fonts.
  for index = 0, state.columns * state.rows - 1 do assert(state.cells[index].fg) end
  return resource()
end

local function stage(weak, columns, rows, activate)
  local terminal = Terminal.new({ columns = 80, rows = 24, state_options = { scrollback_limit = 128 } })
  for line = 1, 160 do terminal:write(string.format("%04d retained Café 界 history\r\n", line)) end
  local state = Terminal.state(terminal)
  local font = resource()
  local session = { terminal = terminal, renderer = resource(), metrics = { font = font },
    pty = { resize = function() end } }
  local workspace = Workspace.new(); workspace:new_tab(session)
  local current = Config.parse("scrollback-limit = 128\nbackground = #000000")
  local candidate = Config.parse("scrollback-limit = 128\nbackground = #123456")
  state:configure_palette(current)
  for iteration = 1, 4 do
    local plan = assert(Reload.prepare({ current = current, candidate = candidate, font = font,
      workspace = workspace, dimensions = function() return columns, rows end,
      new_font = resource, new_renderer = renderer }))
    weak[iteration] = plan.entries[1].transaction.state
    if activate then
      plan:activate(); Assert.equal(#plan:finish(), 0)
      current, candidate = candidate, current
    else
      Assert.equal(#plan:abort(), 0)
      Assert.equal(state.columns, 80); Assert.equal(state.rows, 24)
      Assert.equal(state:get(0, 0).bg, current.background)
    end
    Assert.equal(Terminal.state(terminal), state)
    Assert.equal(state.scrollback:size(), 128)
  end
  terminal:write("\27[999;1H\r\nAFTER")
  Assert.equal(state:get(0, state.rows - 1).glyph, "A")
  terminal:close()
end

local function check(columns, rows, activate)
  local weak = setmetatable({}, { __mode = "v" })
  stage(weak, columns, rows, activate)
  collectgarbage("collect")
  collectgarbage("collect")
  -- Do not flush/disable JIT: compiled callbacks caused the original retention.
  for iteration = 1, 4 do
    Assert.equal(weak[iteration], nil, "discarded configuration snapshot retained at iteration " .. iteration)
  end
end

return {
  rejected_palette_snapshots_are_collectible = function() check(80, 24, false) end,
  rejected_reflow_snapshots_are_collectible = function() check(20, 21, false) end,
  rejected_height_resize_snapshots_are_collectible = function() check(80, 20, false) end,
  rejected_fast_resize_snapshots_are_collectible = function() check(72, 24, false) end,
  adopted_snapshots_are_collectible_while_live_state_keeps_working = function() check(20, 21, true) end,
}
